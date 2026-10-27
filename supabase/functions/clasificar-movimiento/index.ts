// ============================================================================
// SmartMoney · Clasificador de movimientos (Edge Function)
// ----------------------------------------------------------------------------
// POST /functions/v1/clasificar-movimiento
//   Cabecera: Authorization: Bearer <JWT del usuario>
//   Body: { "descripcion": string }   (2 a 100 caracteres tras trim)
//
// Clasifica la descripción de un egreso en uno de los 13 grupos del modelo
// entrenado y devuelve la categoría de egreso que la app debería preseleccionar.
// Antes del modelo se consulta la memoria del usuario (memoria.ts): si ya
// registró un egreso con la misma descripción, se sugiere la categoría que
// eligió esa vez (version_modelo = "memoria-usuario-v1").
//
// El usuario_id SIEMPRE sale del JWT. Las lecturas usan el cliente service_role
// filtrando por ese usuario_id. La descripción nunca se registra en los logs.
// ============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

import {
  buscarEnMemoria,
  type EgresoPrevio,
  LIMITE_HISTORIAL_MEMORIA,
  type Recuerdo,
  VERSION_MEMORIA,
} from "./memoria.ts";
import { modelo, nombreGrupo, predecir } from "./modelo.ts";

const URL_SUPABASE = Deno.env.get("SUPABASE_URL") ?? "";
const CLAVE_ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CLAVE_SERVICIO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/** Confianza mínima para que la app preseleccione la categoría sugerida. */
export const UMBRAL_PRESELECCION = 0.5;

/** Ventana (días) para decidir cuál categoría del usuario se usa más. */
const DIAS_VENTANA_CATEGORIA = 90;

/** Zona horaria de referencia para "hoy". */
const ZONA_HORARIA = "America/Bogota";

/** Longitud de la descripción (tras trim) admitida por la función. */
const LARGO_MIN = 2;
const LARGO_MAX = 100;

const CABECERAS_CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

// --- Utilidades HTTP ---------------------------------------------------------

function responder(cuerpo: unknown, estado = 200): Response {
  return new Response(JSON.stringify(cuerpo), {
    status: estado,
    headers: { ...CABECERAS_CORS, "Content-Type": "application/json" },
  });
}

function leerJwt(req: Request): string | null {
  const encabezado = req.headers.get("Authorization");
  if (!encabezado) return null;
  const [esquema, token] = encabezado.split(" ");
  if (!token || esquema.toLowerCase() !== "bearer") return null;
  return token;
}

async function leerCuerpo(req: Request): Promise<Record<string, unknown>> {
  const texto = await req.text();
  if (!texto) return {};
  try {
    const json = JSON.parse(texto);
    return typeof json === "object" && json !== null
      ? json as Record<string, unknown>
      : {};
  } catch {
    return {};
  }
}

/** Fecha de hoy ('YYYY-MM-DD') en la zona horaria del usuario. */
function hoyEnBogota(): string {
  return new Date().toLocaleDateString("en-CA", { timeZone: ZONA_HORARIA });
}

function sumarDias(fecha: string, dias: number): string {
  const d = new Date(`${fecha}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}

function redondear(valor: number, decimales = 4): number {
  const factor = 10 ** decimales;
  return Math.round(valor * factor) / factor;
}

// --- Lecturas (service_role, siempre filtradas por usuario) ------------------

interface CategoriaEgreso {
  id: string;
  nombre: string;
  usuario_id: string | null;
}

/** Categorías de egreso del grupo: las del usuario y las por defecto (null). */
async function leerCategoriasEgreso(
  admin: SupabaseClient,
  usuarioId: string,
  grupoId: number,
): Promise<CategoriaEgreso[]> {
  const { data, error } = await admin
    .from("categorias")
    .select("id, nombre, usuario_id")
    .eq("tipo", "egreso")
    .eq("grupo_id", grupoId)
    .or(`usuario_id.is.null,usuario_id.eq.${usuarioId}`)
    .order("nombre", { ascending: true });
  if (error) {
    throw new Error(`No se pudieron leer las categorías: ${error.message}`);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((fila) => ({
    id: String(fila["id"]),
    nombre: String(fila["nombre"] ?? ""),
    usuario_id: fila["usuario_id"] === null ? null : String(fila["usuario_id"]),
  }));
}

/** Nº de egresos del usuario por categoría dentro de la ventana. */
async function contarUsoCategorias(
  admin: SupabaseClient,
  usuarioId: string,
  categoriaIds: string[],
  desde: string,
): Promise<Map<string, number>> {
  const conteos = new Map<string, number>();
  if (categoriaIds.length === 0) return conteos;

  const { data, error } = await admin
    .from("transacciones")
    .select("categoria_id")
    .eq("usuario_id", usuarioId)
    .eq("tipo", "egreso")
    .gte("fecha", desde)
    .in("categoria_id", categoriaIds);
  if (error) {
    throw new Error(`No se pudieron leer las transacciones: ${error.message}`);
  }

  for (const fila of (data ?? []) as Record<string, unknown>[]) {
    const id = String(fila["categoria_id"]);
    conteos.set(id, (conteos.get(id) ?? 0) + 1);
  }
  return conteos;
}

/**
 * Categoría de egreso sugerida para el grupo:
 *   a) la categoría propia del usuario con más egresos en los últimos 90 días;
 *   b) si ninguna propia tiene uso, la categoría por defecto (usuario_id null);
 *   c) si no existe ninguna, null.
 */
async function elegirCategoria(
  admin: SupabaseClient,
  usuarioId: string,
  grupoId: number,
  hoy: string,
): Promise<CategoriaEgreso | null> {
  const categorias = await leerCategoriasEgreso(admin, usuarioId, grupoId);
  const propias = categorias.filter((categoria) =>
    categoria.usuario_id === usuarioId
  );

  if (propias.length > 0) {
    const conteos = await contarUsoCategorias(
      admin,
      usuarioId,
      propias.map((categoria) => categoria.id),
      sumarDias(hoy, -DIAS_VENTANA_CATEGORIA),
    );
    let elegida: CategoriaEgreso | null = null;
    let maximo = 0;
    for (const categoria of propias) {
      const uso = conteos.get(categoria.id) ?? 0;
      if (uso > maximo) {
        maximo = uso;
        elegida = categoria;
      }
    }
    if (elegida !== null) return elegida;
  }

  return categorias.find((categoria) => categoria.usuario_id === null) ?? null;
}

/**
 * Egresos recientes del usuario con descripción y categoría, del más reciente
 * al más antiguo, para la memoria por usuario.
 */
async function leerHistorialEgresos(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<EgresoPrevio[]> {
  const { data, error } = await admin
    .from("transacciones")
    .select(
      "descripcion, categoria_id, categorias!fk_transacciones_categoria(nombre, grupo_id)",
    )
    .eq("usuario_id", usuarioId)
    .eq("tipo", "egreso")
    .not("descripcion", "is", null)
    .not("categoria_id", "is", null)
    .order("fecha", { ascending: false })
    .limit(LIMITE_HISTORIAL_MEMORIA);
  if (error) {
    throw new Error(`No se pudo leer el historial: ${error.message}`);
  }

  return ((data ?? []) as Record<string, unknown>[]).map((fila) => {
    const categoria = (fila["categorias"] ?? null) as
      | Record<string, unknown>
      | null;
    const grupo = categoria?.["grupo_id"];
    return {
      descripcion: fila["descripcion"] === null
        ? null
        : String(fila["descripcion"]),
      categoria_id: fila["categoria_id"] === null
        ? null
        : String(fila["categoria_id"]),
      categoria_nombre: categoria?.["nombre"] == null
        ? null
        : String(categoria["nombre"]),
      grupo_id: grupo == null ? null : Number(grupo),
    };
  });
}

/**
 * Categoría recordada para la descripción, o null. Si la lectura falla, se
 * sigue con el modelo: la memoria nunca impide que haya sugerencia.
 */
async function recordarCategoria(
  admin: SupabaseClient,
  usuarioId: string,
  descripcion: string,
): Promise<Recuerdo | null> {
  try {
    const historial = await leerHistorialEgresos(admin, usuarioId);
    return buscarEnMemoria(descripcion, historial);
  } catch (error) {
    console.error("clasificar-movimiento: memoria no disponible:", error);
    return null;
  }
}

// --- HTTP --------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CABECERAS_CORS });
  }

  try {
    if (req.method !== "POST") {
      return responder({ error: "Método no permitido." }, 405);
    }

    const jwt = leerJwt(req);
    if (!jwt) {
      return responder(
        { error: "Falta el encabezado Authorization con el JWT del usuario." },
        401,
      );
    }

    const clienteUsuario = createClient(URL_SUPABASE, CLAVE_ANON, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: errorAuth } = await clienteUsuario.auth
      .getUser(jwt);
    if (errorAuth || !user) {
      return responder({ error: "Token inválido o vencido." }, 401);
    }

    // El usuario sale del token, nunca del body.
    const usuarioId = user.id;

    const cuerpo = await leerCuerpo(req);
    const descripcionCruda = cuerpo["descripcion"];
    if (typeof descripcionCruda !== "string") {
      return responder({ error: "El campo 'descripcion' debe ser un texto." }, 400);
    }
    const descripcion = descripcionCruda.trim();
    if (descripcion.length < LARGO_MIN || descripcion.length > LARGO_MAX) {
      return responder(
        { error: "La descripción debe tener entre 2 y 100 caracteres." },
        400,
      );
    }

    const admin = createClient(URL_SUPABASE, CLAVE_SERVICIO, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    // 1) Memoria del usuario: misma descripción → la categoría que eligió.
    const recuerdo = await recordarCategoria(admin, usuarioId, descripcion);
    if (recuerdo !== null) {
      return responder({
        sugerencia: {
          grupo_id: recuerdo.grupo_id,
          grupo_nombre: nombreGrupo(recuerdo.grupo_id),
          confianza: 1,
          categoria_id: recuerdo.categoria_id,
          categoria_nombre: recuerdo.categoria_nombre,
          preseleccionar: true,
          version_modelo: VERSION_MEMORIA,
          top3: [],
        },
      });
    }

    // 2) Modelo general.
    const prediccion = predecir(descripcion);
    if (prediccion === null) {
      return responder({ sugerencia: null });
    }
    const categoria = await elegirCategoria(
      admin,
      usuarioId,
      prediccion.grupo_id,
      hoyEnBogota(),
    );

    const confianza = redondear(prediccion.confianza);
    return responder({
      sugerencia: {
        grupo_id: prediccion.grupo_id,
        grupo_nombre: nombreGrupo(prediccion.grupo_id),
        confianza,
        categoria_id: categoria?.id ?? null,
        categoria_nombre: categoria?.nombre ?? null,
        preseleccionar: confianza >= UMBRAL_PRESELECCION,
        version_modelo: modelo.version,
        top3: prediccion.top3.map((item) => ({
          grupo_id: item.grupo_id,
          prob: redondear(item.prob),
        })),
      },
    });
  } catch (error) {
    // Mensaje genérico al cliente; el detalle queda solo en el log del servidor
    // (nunca la descripción del usuario).
    console.error("clasificar-movimiento:", error);
    return responder({ error: "No se pudo procesar la solicitud." }, 500);
  }
});

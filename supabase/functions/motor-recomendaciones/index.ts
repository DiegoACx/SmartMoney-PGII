// ============================================================================
// SmartMoney · Motor de recomendaciones (Edge Function)
// ----------------------------------------------------------------------------
// POST /functions/v1/motor-recomendaciones
//   Cabecera: Authorization: Bearer <JWT del usuario>
//   Body (opcional): { "forzar": true }  → ignora la caché de HORAS_CACHE
//
// El usuario_id SIEMPRE sale del JWT. Las lecturas y escrituras usan el cliente
// service_role, filtrando por ese usuario_id.
//
// Cuerpo del flujo:
//   1. autenticar      → index.ts
//   2. leer datos      → index.ts
//   3. línea base      → estadistica.ts
//   4. hallazgos       → detectores.ts
//   5. puntaje/elección→ puntaje.ts
//   6. textos          → plantillas.ts
// ============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

import * as CFG from "./config.ts";
import {
  type AgregadoClave,
  type CategoriaBase,
  type GrupoReferencia,
  type LineaBaseCategoria,
  type LineaBaseGrupo,
  type TransaccionBase,
  agregarPorClave,
  calcularLineaBaseCategorias,
  calcularLineaBaseGrupos,
  fechaMayor,
  lunesDeSemana,
  medianaIngresoMensual,
  mesAnterior,
  mesDe,
  movimientosPorCategoria,
  primeraSemanaConRegistros,
  sumarDias,
} from "./estadistica.ts";
import {
  type EscalonCatalogo,
  type HallazgoBase,
  type MetaActiva,
  type NivelCatalogo,
  detectarAporteMeta,
  detectarGastoAnomalo,
  detectarLeccionSugerida,
  detectarLogro,
  detectarRiesgoFinDeMes,
  detectarSobregastoCategoria,
} from "./detectores.ts";
import {
  type HallazgoPuntuado,
  type RecomendacionPrevia,
  puntuarHallazgos,
  seleccionar,
  yaRecomendado,
} from "./puntaje.ts";
import { textoRecomendacion } from "./plantillas.ts";

const URL_SUPABASE = Deno.env.get("SUPABASE_URL") ?? "";
const CLAVE_ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const CLAVE_SERVICIO = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

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
  if (req.method !== "POST") return {};
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
  return new Date().toLocaleDateString("en-CA", {
    timeZone: CFG.ZONA_HORARIA,
  });
}

function haceIso(horas: number): string {
  return new Date(Date.now() - horas * 3_600_000).toISOString();
}

function datosAnidados(
  fila: Record<string, unknown>,
): Record<string, unknown> | null {
  const anidado = fila["hallazgos"];
  if (!anidado) return null;
  const objeto = Array.isArray(anidado) ? anidado[0] : anidado;
  return (objeto?.["datos"] as Record<string, unknown>) ?? null;
}

// --- Lecturas (service_role, siempre filtradas por usuario) ------------------

async function leerCategorias(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<CategoriaBase[]> {
  const { data, error } = await admin
    .from("categorias")
    .select("id, nombre, grupo_id, tipo")
    .or(`usuario_id.is.null,usuario_id.eq.${usuarioId}`);
  if (error) throw new Error(`No se pudieron leer las categorías: ${error.message}`);

  return ((data ?? []) as Record<string, unknown>[]).map((fila) => ({
    id: String(fila["id"]),
    nombre: String(fila["nombre"] ?? ""),
    grupo_id: fila["grupo_id"] === null ? null : Number(fila["grupo_id"]),
    tipo: String(fila["tipo"] ?? ""),
  }));
}

async function leerGrupos(admin: SupabaseClient): Promise<GrupoReferencia[]> {
  const { data, error } = await admin
    .from("grupos_referencia")
    .select("id, nombre, proporcion_referencia, incluir_en_referencia");
  if (error) throw new Error(`No se pudieron leer los grupos: ${error.message}`);

  return ((data ?? []) as Record<string, unknown>[]).map((fila) => ({
    id: Number(fila["id"]),
    nombre: String(fila["nombre"] ?? ""),
    proporcion_referencia: fila["proporcion_referencia"] === null
      ? null
      : Number(fila["proporcion_referencia"]),
    incluir_en_referencia: fila["incluir_en_referencia"] === true,
  }));
}

/** Transacciones normalizadas; el grupo se resuelve con el mapa de categorías. */
async function leerTransacciones(
  admin: SupabaseClient,
  usuarioId: string,
  desde: string,
  gruposPorCategoria: Map<string, number | null>,
): Promise<TransaccionBase[]> {
  const { data, error } = await admin
    .from("transacciones")
    .select("id, categoria_id, tipo, monto, fecha, es_gasto_trabajo")
    .eq("usuario_id", usuarioId)
    .gte("fecha", desde);
  if (error) throw new Error(`No se pudieron leer las transacciones: ${error.message}`);

  return ((data ?? []) as Record<string, unknown>[]).map((fila) => {
    const categoriaId = String(fila["categoria_id"]);
    return {
      id: String(fila["id"]),
      categoria_id: categoriaId,
      grupo_id: gruposPorCategoria.get(categoriaId) ?? null,
      tipo: fila["tipo"] === "ingreso" ? "ingreso" : "egreso",
      monto: Number(fila["monto"] ?? 0),
      fecha: String(fila["fecha"]).slice(0, 10),
      es_gasto_trabajo: fila["es_gasto_trabajo"] === true,
    };
  });
}

async function leerMetas(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<MetaActiva[]> {
  const { data, error } = await admin
    .from("metas_ahorro")
    .select("id, nombre, monto_objetivo, monto_actual, fecha_limite, cumplida")
    .eq("usuario_id", usuarioId);
  if (error) throw new Error(`No se pudieron leer las metas: ${error.message}`);

  const metas: MetaActiva[] = [];
  for (const fila of (data ?? []) as Record<string, unknown>[]) {
    if (fila["cumplida"] === true) continue;
    const fechaLimite = fila["fecha_limite"];
    if (typeof fechaLimite !== "string" || fechaLimite.length === 0) continue;
    metas.push({
      id: String(fila["id"]),
      nombre: String(fila["nombre"] ?? "tu meta"),
      monto_objetivo: Number(fila["monto_objetivo"] ?? 0),
      monto_actual: Number(fila["monto_actual"] ?? 0),
      fecha_limite: fechaLimite.slice(0, 10),
    });
  }
  return metas;
}

/** Suma neta de aportes por meta (los retiros van como montos negativos). */
async function leerAportesPorMeta(
  admin: SupabaseClient,
  usuarioId: string,
  desde: string,
): Promise<Map<string, number>> {
  const { data, error } = await admin
    .from("aportes_meta")
    .select("meta_id, monto, fecha")
    .eq("usuario_id", usuarioId)
    .gte("fecha", desde);
  if (error) throw new Error(`No se pudieron leer los aportes: ${error.message}`);

  const totales = new Map<string, number>();
  for (const fila of (data ?? []) as Record<string, unknown>[]) {
    const metaId = String(fila["meta_id"]);
    totales.set(metaId, (totales.get(metaId) ?? 0) + Number(fila["monto"] ?? 0));
  }
  return totales;
}

async function leerCatalogoEducativo(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<{
  niveles: NivelCatalogo[];
  escalones: EscalonCatalogo[];
  completados: Set<string>;
}> {
  const [niveles, escalones, progreso] = await Promise.all([
    admin.from("educacion_niveles").select("id, orden"),
    admin.from("educacion_escalones").select(
      "id, nivel_id, orden, titulo, tipo, disponible",
    ),
    admin.from("educacion_progreso").select("escalon_id, completado").eq(
      "usuario_id",
      usuarioId,
    ),
  ]);

  if (niveles.error) throw new Error(`No se pudieron leer los niveles: ${niveles.error.message}`);
  if (escalones.error) throw new Error(`No se pudieron leer los escalones: ${escalones.error.message}`);
  if (progreso.error) throw new Error(`No se pudo leer el progreso: ${progreso.error.message}`);

  return {
    niveles: ((niveles.data ?? []) as Record<string, unknown>[]).map((fila) => ({
      id: String(fila["id"]),
      orden: Number(fila["orden"] ?? 0),
    })),
    escalones: ((escalones.data ?? []) as Record<string, unknown>[]).map(
      (fila) => ({
        id: String(fila["id"]),
        nivel_id: String(fila["nivel_id"]),
        orden: Number(fila["orden"] ?? 0),
        titulo: String(fila["titulo"] ?? ""),
        tipo: String(fila["tipo"] ?? ""),
        disponible: fila["disponible"] === true,
      }),
    ),
    completados: new Set(
      ((progreso.data ?? []) as Record<string, unknown>[])
        .filter((fila) => fila["completado"] === true)
        .map((fila) => String(fila["escalon_id"])),
    ),
  };
}

/**
 * Recomendaciones de los últimos días. Sirven para penalizar repeticiones y
 * para no volver a recomendar lo mismo: se traen todas, respondidas o no.
 */
async function leerRecomendacionesRecientes(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<RecomendacionPrevia[]> {
  const dias = Math.max(
    CFG.DIAS_REPETICION,
    CFG.DIAS_RECOMENDACION_VIGENTE,
  );
  const { data, error } = await admin
    .from("recomendaciones")
    .select("tipo, objetivo, creado_en")
    .eq("usuario_id", usuarioId)
    .gte("creado_en", haceIso(dias * 24));
  if (error) throw new Error(`No se pudieron leer las recomendaciones previas: ${error.message}`);

  return ((data ?? []) as Record<string, unknown>[]).map((fila) => ({
    tipo: String(fila["tipo"]) as CFG.TipoHallazgo,
    objetivo: String(fila["objetivo"] ?? ""),
    creadoEn: String(fila["creado_en"]).slice(0, 10),
  }));
}

/** Recomendaciones vigentes: sin responder y de los últimos 7 días. */
async function leerRecomendacionesVigentes(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<Record<string, unknown>[]> {
  const { data, error } = await admin
    .from("recomendaciones")
    .select("id, tipo, texto, prioridad, creado_en, hallazgos ( datos )")
    .eq("usuario_id", usuarioId)
    .is("respondido_en", null)
    .gte("creado_en", haceIso(CFG.DIAS_RECOMENDACION_VIGENTE * 24))
    .order("prioridad", { ascending: false });
  if (error) throw new Error(`No se pudieron leer las recomendaciones: ${error.message}`);

  return ((data ?? []) as Record<string, unknown>[]).map((fila) => ({
    id: fila["id"],
    tipo: fila["tipo"],
    texto: fila["texto"],
    prioridad: fila["prioridad"],
    creado_en: fila["creado_en"],
    datos: datosAnidados(fila),
  }));
}

async function hayHallazgosRecientes(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<boolean> {
  const { data, error } = await admin
    .from("hallazgos")
    .select("id")
    .eq("usuario_id", usuarioId)
    .gte("creado_en", haceIso(CFG.HORAS_CACHE))
    .limit(1);
  if (error) throw new Error(`No se pudo consultar la caché: ${error.message}`);

  return ((data ?? []) as Record<string, unknown>[]).length > 0;
}

// --- Escrituras (service_role) -----------------------------------------------

async function guardarLineaBase(
  admin: SupabaseClient,
  usuarioId: string,
  lineas: LineaBaseCategoria[],
): Promise<void> {
  if (lineas.length === 0) return;
  const filas = lineas.map((linea) => ({
    usuario_id: usuarioId,
    categoria_id: linea.categoria_id,
    mediana: linea.mediana,
    mad: linea.mad,
    n_semanas: linea.n_semanas,
    n_movimientos: linea.n_movimientos,
    actualizado_en: new Date().toISOString(),
  }));
  const { error } = await admin
    .from("linea_base_usuario")
    .upsert(filas, { onConflict: "usuario_id,categoria_id" });
  if (error) throw new Error(`No se pudo guardar la línea base: ${error.message}`);
}

function filaHallazgo(usuarioId: string, hallazgo: HallazgoPuntuado) {
  return {
    usuario_id: usuarioId,
    tipo: hallazgo.tipo,
    datos: { ...hallazgo.datos, objetivo: hallazgo.objetivo },
    severidad: hallazgo.severidad,
    impacto: hallazgo.impacto,
    confianza: hallazgo.confianza,
    repeticion: hallazgo.repeticion,
    peso_tipo_usado: hallazgo.peso_tipo_usado,
    puntaje: hallazgo.puntaje,
  };
}

async function insertarHallazgosSinRecomendar(
  admin: SupabaseClient,
  usuarioId: string,
  hallazgos: HallazgoPuntuado[],
): Promise<void> {
  if (hallazgos.length === 0) return;
  const { error } = await admin
    .from("hallazgos")
    .insert(hallazgos.map((hallazgo) => filaHallazgo(usuarioId, hallazgo)));
  if (error) throw new Error(`No se pudieron guardar los hallazgos: ${error.message}`);
}

/** Inserta un hallazgo y devuelve su id (se necesita para la recomendación). */
async function insertarHallazgo(
  admin: SupabaseClient,
  usuarioId: string,
  hallazgo: HallazgoPuntuado,
): Promise<string> {
  const { data, error } = await admin
    .from("hallazgos")
    .insert(filaHallazgo(usuarioId, hallazgo))
    .select("id")
    .single();
  if (error) throw new Error(`No se pudo guardar el hallazgo: ${error.message}`);

  return String((data as Record<string, unknown>)["id"]);
}

/** Inserta la recomendación. `objetivo` permite bloquear duplicados recientes. */
async function insertarRecomendacion(
  admin: SupabaseClient,
  usuarioId: string,
  hallazgoId: string,
  hallazgo: HallazgoPuntuado,
): Promise<void> {
  const { error } = await admin.from("recomendaciones").insert({
    usuario_id: usuarioId,
    hallazgo_id: hallazgoId,
    tipo: hallazgo.tipo,
    texto: textoRecomendacion(hallazgo),
    origen_texto: "plantilla",
    prioridad: hallazgo.puntaje,
    objetivo: hallazgo.objetivo,
  });
  if (error) throw new Error(`No se pudo guardar la recomendación: ${error.message}`);
}

// --- Recalculo ---------------------------------------------------------------

async function recalcular(
  admin: SupabaseClient,
  usuarioId: string,
  hoy: string,
): Promise<void> {
  // 1) Lectura de datos
  const categorias = await leerCategorias(admin, usuarioId);
  const gruposPorCategoria = new Map(
    categorias.map((categoria) => [categoria.id, categoria.grupo_id]),
  );
  const grupos = await leerGrupos(admin);
  const transacciones = await leerTransacciones(
    admin,
    usuarioId,
    sumarDias(hoy, -CFG.DIAS_VENTANA_TRANSACCIONES),
    gruposPorCategoria,
  );
  const metas = await leerMetas(admin, usuarioId);
  const aportesPorMeta = await leerAportesPorMeta(
    admin,
    usuarioId,
    sumarDias(hoy, -CFG.DIAS_RITMO_APORTES),
  );
  const { niveles, escalones, completados } = await leerCatalogoEducativo(
    admin,
    usuarioId,
  );
  const previas = await leerRecomendacionesRecientes(admin, usuarioId);

  // 2) Ingreso mensual y línea base (sin gastos de trabajo)
  const ingresoMensual = medianaIngresoMensual(
    transacciones.filter((t) => t.tipo === "ingreso"),
  );
  const egresosBase = transacciones.filter((t) =>
    t.tipo === "egreso" && !t.es_gasto_trabajo
  );
  const egresosConGrupo = egresosBase.filter((t) => t.grupo_id !== null);

  const lunesFinal = lunesDeSemana(hoy);
  const lunesLimite = sumarDias(
    lunesFinal,
    -7 * (CFG.SEMANAS_HISTORIAL - 1),
  );
  const primeraSemana = primeraSemanaConRegistros(egresosBase);

  let lineasCategorias: LineaBaseCategoria[] = [];
  let lineasGrupos: LineaBaseGrupo[] = [];
  let movimientos: Map<string, TransaccionBase[]> = new Map();
  let historialPorGrupo: Map<string, AgregadoClave> = new Map();
  if (primeraSemana !== null) {
    // Las semanas sin gasto cuentan como 0 desde la primera semana del usuario.
    const lunesInicial = fechaMayor(primeraSemana, lunesLimite);
    movimientos = movimientosPorCategoria(egresosBase, lunesInicial, lunesFinal);
    lineasCategorias = calcularLineaBaseCategorias({
      agregados: agregarPorClave(
        egresosBase,
        (t) => t.categoria_id,
        lunesInicial,
        lunesFinal,
      ),
      movimientos,
    });
    lineasGrupos = calcularLineaBaseGrupos({
      agregados: agregarPorClave(
        egresosConGrupo,
        (t) => String(t.grupo_id),
        lunesInicial,
        lunesFinal,
      ),
      grupos,
      ingresoMensual,
    });
    // Semanas anteriores al último mes completo: el logro se mide contra el
    // promedio habitual del propio usuario, no contra la referencia DANE.
    historialPorGrupo = agregarPorClave(
      egresosConGrupo,
      (t) => String(t.grupo_id),
      lunesInicial,
      sumarDias(lunesDeSemana(`${mesAnterior(hoy)}-01`), -7),
    );
  }

  // 3) Detectores
  const mesActual = mesDe(hoy);
  const mesCompleto = mesAnterior(hoy);
  const nombresCategorias = new Map(
    categorias.map((categoria) => [categoria.id, categoria.nombre]),
  );

  const sobregastos = detectarSobregastoCategoria({
    hoy,
    ingresoMensual,
    lineasBaseGrupos: lineasGrupos,
    egresosMesActual: egresosBase.filter((t) => mesDe(t.fecha) === mesActual),
  });

  const anomalias = detectarGastoAnomalo({
    ingresoMensual,
    egresosUltimos7Dias: egresosBase.filter((t) =>
      t.fecha >= sumarDias(hoy, -(CFG.DIAS_GAS_ANOMALO - 1))
    ),
    movimientosPorCategoria: movimientos,
    nombresCategorias,
  });

  const lecciones = detectarLeccionSugerida({
    sobregastos,
    niveles,
    escalones,
    completados,
    mapaLecciones: CFG.MAPA_LECCIONES,
  });

  const aportesDeMetas = detectarAporteMeta({
    hoy,
    ingresoMensual,
    metas: metas.filter((meta) => meta.fecha_limite > hoy),
    aportesPorMeta,
  });

  const logros = detectarLogro({
    mes: mesCompleto,
    ingresoMensual,
    lineasBaseGrupos: lineasGrupos,
    historialPorGrupo,
    sobregastos,
    egresosMes: egresosBase.filter((t) => mesDe(t.fecha) === mesCompleto),
  });

  const riesgos = detectarRiesgoFinDeMes({
    hoy,
    ingresoMensual,
    ingresosMes: transacciones.filter((t) =>
      t.tipo === "ingreso" && mesDe(t.fecha) === mesActual
    ),
    // Incluye los gastos de trabajo: el riesgo es de caja, no de referencia.
    egresosMes: transacciones.filter((t) =>
      t.tipo === "egreso" && mesDe(t.fecha) === mesActual
    ),
  });

  // 4) Puntaje y selección
  const hallazgos: HallazgoBase[] = [
    ...sobregastos,
    ...anomalias,
    ...lecciones,
    ...aportesDeMetas,
    ...logros,
    ...riesgos,
  ];
  const puntuados = puntuarHallazgos({
    hallazgos,
    previas,
    hoy,
    obtenerPeso: (tipo) => CFG.obtenerPesoTipo(usuarioId, tipo),
  });
  const seleccionados = seleccionar(puntuados);
  const clavesSeleccionadas = new Set(
    seleccionados.map((h) => `${h.tipo}:${h.objetivo}`),
  );

  // 5) Escritura
  await guardarLineaBase(admin, usuarioId, lineasCategorias);
  await insertarHallazgosSinRecomendar(
    admin,
    usuarioId,
    puntuados.filter((h) => !clavesSeleccionadas.has(`${h.tipo}:${h.objetivo}`)),
  );
  for (const hallazgo of seleccionados) {
    const hallazgoId = await insertarHallazgo(admin, usuarioId, hallazgo);
    // El hallazgo siempre se guarda; la recomendación no se duplica si ya hubo
    // una del mismo tipo y objetivo en los últimos 7 días, respondida o no.
    if (yaRecomendado(hallazgo, previas, hoy)) continue;
    await insertarRecomendacion(admin, usuarioId, hallazgoId, hallazgo);
    previas.push({
      tipo: hallazgo.tipo,
      objetivo: hallazgo.objetivo,
      creadoEn: hoy,
    });
  }
}

// --- HTTP --------------------------------------------------------------------

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CABECERAS_CORS });
  }

  try {
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
    const forzar = cuerpo["forzar"] === true;
    const hoy = hoyEnBogota();

    const admin = createClient(URL_SUPABASE, CLAVE_SERVICIO, {
      auth: { persistSession: false, autoRefreshToken: false },
    });

    if (!forzar && await hayHallazgosRecientes(admin, usuarioId)) {
      return responder({
        recalculado: false,
        recomendaciones: await leerRecomendacionesVigentes(admin, usuarioId),
      });
    }

    await recalcular(admin, usuarioId, hoy);

    return responder({
      recalculado: true,
      recomendaciones: await leerRecomendacionesVigentes(admin, usuarioId),
    });
  } catch (error) {
    console.error("motor-recomendaciones:", error);
    return responder(
      { error: error instanceof Error ? error.message : String(error) },
      500,
    );
  }
});

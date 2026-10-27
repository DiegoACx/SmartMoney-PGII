// ============================================================================
// SmartMoney · Eliminar cuenta · Manejador HTTP (Edge Function)
// ----------------------------------------------------------------------------
// POST /functions/v1/eliminar-cuenta
//   Cabecera: Authorization: Bearer <JWT del usuario>
//   Body: ninguno (el id del usuario SIEMPRE sale del token, nunca del body)
//
// Borra todos los datos del usuario autenticado (paso a paso y comprobando el
// error de cada uno) y, como último paso, su cuenta en Supabase Auth.
//
// La clave de servicio (SUPABASE_SERVICE_ROLE_KEY) vive SOLO aquí, en el
// servidor: nunca viaja a la app ni se escribe en los logs.
//
// Todos los borrados son idempotentes: si el usuario reintenta tras un fallo,
// la operación puede repetirse sin problema.
// ============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { PLAN_BORRADO } from "./plan.ts";

/** Configuración leída del entorno en tiempo de petición, no al importar. */
interface Entorno {
  urlSupabase: string;
  claveAnon: string;
  claveServicio: string;
}

function leerEntorno(): Entorno {
  return {
    urlSupabase: Deno.env.get("SUPABASE_URL") ?? "",
    claveAnon: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    claveServicio: Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  };
}

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

// --- Borrado -----------------------------------------------------------------

/**
 * Ejecuta el plan de borrado, paso a paso y en orden. Si un paso falla se
 * detiene y propaga el error (el detalle queda solo en el log del servidor).
 *
 * El filtro por columna ya garantiza que en `categorias` solo se borren las
 * filas propias: las predeterminadas tienen `usuario_id` NULL.
 */
export async function eliminarDatosDeUsuario(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<void> {
  for (const paso of PLAN_BORRADO) {
    const { error } = await admin
      .from(paso.tabla)
      .delete()
      .eq(paso.columna, usuarioId);
    if (error) {
      throw new Error(`No se pudo borrar en ${paso.tabla}: ${error.message}`);
    }
  }
}

/** Último paso: borrado del usuario en Supabase Auth. */
async function eliminarUsuarioDeAuth(
  admin: SupabaseClient,
  usuarioId: string,
): Promise<void> {
  const { error } = await admin.auth.admin.deleteUser(usuarioId);
  if (error) {
    throw new Error(`No se pudo borrar en auth: ${error.message}`);
  }
}

// --- HTTP --------------------------------------------------------------------

export async function manejarPeticion(req: Request): Promise<Response> {
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

    const entorno = leerEntorno();

    const clienteUsuario = createClient(entorno.urlSupabase, entorno.claveAnon, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: { user }, error: errorAuth } = await clienteUsuario.auth
      .getUser(jwt);
    if (errorAuth || !user) {
      return responder({ error: "Token inválido o vencido." }, 401);
    }

    // El usuario sale del token, nunca del body.
    const usuarioId = user.id;

    const admin = createClient(
      entorno.urlSupabase,
      entorno.claveServicio,
      {
        auth: { persistSession: false, autoRefreshToken: false },
      },
    );

    await eliminarDatosDeUsuario(admin, usuarioId);
    await eliminarUsuarioDeAuth(admin, usuarioId);

    return responder({ ok: true });
  } catch (error) {
    // Mensaje genérico al cliente; el detalle queda solo en el log del
    // servidor y nunca incluye datos personales.
    console.error("eliminar-cuenta:", error);
    return responder({ error: "No se pudo eliminar la cuenta" }, 500);
  }
}

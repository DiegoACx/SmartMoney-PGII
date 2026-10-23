// ============================================================================
// SmartMoney · Chat IA · Manejador HTTP (Edge Function)
// ----------------------------------------------------------------------------
// POST /functions/v1/chat-ia
//   Cabecera: Authorization: Bearer <JWT del usuario>
//   Body: { "mensaje": string }  (1 a 500 caracteres tras trim)
//
// El usuario_id SIEMPRE sale del JWT, nunca del body. Las lecturas y escrituras
// usan el cliente service_role filtrando por ese usuario_id.
//
// Flujo: valida el mensaje → aplica el límite diario → oculta datos personales
// → clasifica la intención → resuelve la respuesta → guarda los dos mensajes.
//
// La lógica vive aquí (y no en index.ts) para poder probarla sin servidor: las
// dependencias (usuario, datos, fetch y reloj) se pueden inyectar.
// ============================================================================

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

import {
  clasificarIntencion as clasificarIntencionReal,
  grupos as gruposReales,
  UMBRAL_INTENCION,
  type ClasificacionIntencion,
} from "./clasificadores.ts";
import { responderConsultaDatos } from "./consultar_datos.ts";
import { responderConversacion } from "./conversacion.ts";
import { responderFaq } from "./faq.ts";
import { hoyEnBogota, inicioDelDiaBogota, sumarDias } from "./fechas.ts";
import { ocultarDatosPersonales } from "./privacidad.ts";
import {
  crearRepositorioSupabase,
  type RepositorioChat,
} from "./repositorio.ts";
import type {
  Intencion,
  RespuestaChat,
  RespuestaIntencion,
} from "./tipos.ts";

/** Longitud máxima del mensaje del usuario (tras trim). */
export const LARGO_MAXIMO_MENSAJE = 500;

/** Mensajes del usuario permitidos por día (hora de Colombia). */
export const MAX_MENSAJES_POR_DIA = 40;

/** Respuesta provisional de las intenciones que llegan en la Fase 6B-2. */
export const RESPUESTA_PROVISIONAL =
  "Estoy aprendiendo a responder este tipo de preguntas. Pronto podré ayudarte con eso.";

const CABECERAS_CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/** Todo lo externo que necesita el manejador, inyectable en las pruebas. */
export interface DependenciasChat {
  /** Resuelve el usuario a partir del JWT; null si el token no sirve. */
  resolverUsuario(jwt: string): Promise<string | null>;
  /** Acceso a datos (service_role) ya filtrable por usuario_id. */
  repositorio: RepositorioChat;
  /** fetch para Gemini. */
  fetchFn: typeof fetch;
  /** Reloj (para "hoy" y el límite diario). */
  ahora(): Date;
  /** Clave de Gemini; undefined = leer de GEMINI_API_KEY. */
  claveLLM?: string | null;
  /** Clasificador de intención. */
  clasificarIntencion(texto: string): ClasificacionIntencion;
}

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

function redondear(valor: number, decimales = 4): number {
  const factor = 10 ** decimales;
  return Math.round(valor * factor) / factor;
}

// --- Dependencias reales -----------------------------------------------------

function dependenciasReales(): DependenciasChat {
  const urlSupabase = Deno.env.get("SUPABASE_URL") ?? "";
  const claveAnon = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
  const claveServicio = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

  const clienteUsuario = createClient(urlSupabase, claveAnon, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin: SupabaseClient = createClient(urlSupabase, claveServicio, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return {
    resolverUsuario: async (jwt) => {
      const { data: { user }, error } = await clienteUsuario.auth.getUser(jwt);
      return error || !user ? null : user.id;
    },
    repositorio: crearRepositorioSupabase(admin),
    fetchFn: fetch,
    ahora: () => new Date(),
    clasificarIntencion: clasificarIntencionReal,
  };
}

// --- Enrutamiento por intención ---------------------------------------------

async function resolverRespuesta(
  intencion: Intencion,
  mensaje: string,
  usuarioId: string,
  deps: DependenciasChat,
): Promise<RespuestaIntencion> {
  switch (intencion) {
    case "consultar_datos":
      return await responderConsultaDatos(
        mensaje,
        usuarioId,
        { repositorio: deps.repositorio, grupos: gruposReales },
        deps.ahora(),
      );
    case "ayuda_app":
      return responderFaq(mensaje);
    case "conversacion":
      return await responderConversacion({
        mensaje,
        ultimoMensajeAsistente: await deps.repositorio.ultimoMensajeAsistente(
          usuarioId,
        ),
        fetchFn: deps.fetchFn,
        claveLLM: deps.claveLLM,
      });
    default:
      // simular_escenario, aprender_concepto y pedir_consejo (Fase 6B-2).
      return {
        respuesta: RESPUESTA_PROVISIONAL,
        origen: "plantilla",
        motivo: "provisional",
      };
  }
}

// --- HTTP --------------------------------------------------------------------

export async function manejarPeticion(
  req: Request,
  deps?: DependenciasChat,
): Promise<Response> {
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

    const dependencias = deps ?? dependenciasReales();
    const usuarioId = await dependencias.resolverUsuario(jwt);
    if (usuarioId === null) {
      return responder({ error: "Token inválido o vencido." }, 401);
    }

    const cuerpo = await leerCuerpo(req);
    const mensajeCrudo = cuerpo["mensaje"];
    if (typeof mensajeCrudo !== "string") {
      return responder({ error: "El campo 'mensaje' debe ser un texto." }, 400);
    }
    const mensaje = mensajeCrudo.trim();
    if (mensaje.length === 0) {
      return responder({ error: "Escríbeme algo y con gusto te ayudo." }, 400);
    }
    if (mensaje.length > LARGO_MAXIMO_MENSAJE) {
      return responder(
        {
          error:
            `Tu mensaje es muy largo. Resúmelo en ${LARGO_MAXIMO_MENSAJE} caracteres o menos.`,
        },
        400,
      );
    }

    const ahora = dependencias.ahora();
    const hoy = hoyEnBogota(ahora);
    const mensajesHoy = await dependencias.repositorio.contarMensajesUsuario(
      usuarioId,
      inicioDelDiaBogota(hoy),
      inicioDelDiaBogota(sumarDias(hoy, 1)),
    );
    if (mensajesHoy >= MAX_MENSAJES_POR_DIA) {
      return responder(
        {
          error:
            `Por hoy ya alcanzaste el límite de ${MAX_MENSAJES_POR_DIA} mensajes. Mañana seguimos revisando tus finanzas.`,
        },
        429,
      );
    }

    // A partir de aquí el mensaje ya está libre de datos personales.
    const limpio = ocultarDatosPersonales(mensaje);

    const datos = { baja_confianza: false };
    let { intencion, confianza } = dependencias.clasificarIntencion(limpio);
    if (intencion === null || confianza < UMBRAL_INTENCION) {
      datos.baja_confianza = true;
      intencion = "pedir_consejo";
    }

    const resultado = await resolverRespuesta(
      intencion,
      limpio,
      usuarioId,
      dependencias,
    );
    const confianzaFinal = redondear(confianza);
    const motivo = datos.baja_confianza ? "baja_confianza" : resultado.motivo;

    await dependencias.repositorio.insertarMensaje({
      usuario_id: usuarioId,
      rol: "usuario",
      contenido: limpio,
      intencion,
      confianza: confianzaFinal,
      origen: null,
      accion: null,
    });
    await dependencias.repositorio.insertarMensaje({
      usuario_id: usuarioId,
      rol: "asistente",
      contenido: resultado.respuesta,
      intencion,
      confianza: confianzaFinal,
      origen: resultado.origen,
      accion: resultado.accion ?? null,
    });

    // Log de una línea, sin el contenido del mensaje.
    console.log(
      `[chat] intencion=${intencion} conf=${confianzaFinal} origen=${resultado.origen} motivo=${motivo}`,
    );

    const respuesta: RespuestaChat = {
      respuesta: resultado.respuesta,
      intencion,
      confianza: confianzaFinal,
      origen: resultado.origen,
    };
    if (resultado.accion !== undefined) respuesta.accion = resultado.accion;
    return responder(respuesta);
  } catch (error) {
    // Mensaje genérico al cliente; el detalle queda solo en el log del servidor
    // (nunca el contenido del mensaje del usuario).
    console.error("chat-ia:", error);
    return responder(
      { error: "No pude procesar tu mensaje. Intenta de nuevo en un momento." },
      500,
    );
  }
}

// ============================================================================
// Pruebas de manejador.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red ni Supabase: se inyectan DependenciasChat (usuario, repositorio, fetch
// y reloj) para verificar el flujo HTTP completo.
// ============================================================================

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";

import { UMBRAL_INTENCION } from "./clasificadores.ts";
import {
  fijarDependenciasDeRespaldo,
  LARGO_MAXIMO_MENSAJE,
  manejarPeticion,
  MAX_MENSAJES_POR_DIA,
  RESPUESTA_PROVISIONAL,
  type DependenciasChat,
} from "./manejador.ts";
import type { MensajeNuevo, RepositorioChat } from "./repositorio.ts";

const URL_CHAT = "https://proyecto.supabase.co/functions/v1/chat-ia";

function repoCaptura(parcial: Partial<RepositorioChat> = {}) {
  const mensajes: MensajeNuevo[] = [];
  const repositorio: RepositorioChat = {
    contarMensajesUsuario: async () => 0,
    ultimoMensajeAsistente: async () => null,
    insertarMensaje: async (mensaje) => {
      mensajes.push(mensaje);
    },
    leerTransacciones: async () => [],
    leerCategorias: async () => [],
    leerMetasActivas: async () => [],
    ...parcial,
  };
  return { repositorio, mensajes };
}

function deps(cambios: Partial<DependenciasChat> = {}): DependenciasChat {
  return {
    resolverUsuario: async () => "usuario-1",
    repositorio: repoCaptura().repositorio,
    fetchFn: (async () => {
      throw new Error("no hay red en las pruebas");
    }) as unknown as typeof fetch,
    ahora: () => new Date("2026-10-21T15:00:00Z"),
    claveLLM: null,
    clasificarIntencion: () => ({ intencion: "conversacion", confianza: 0.9 }),
    ...cambios,
  };
}

function peticionPost(cuerpo: unknown, jwt: string | null = "jwt-bueno"): Request {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (jwt !== null) headers.set("Authorization", `Bearer ${jwt}`);
  return new Request(URL_CHAT, {
    method: "POST",
    headers,
    body: JSON.stringify(cuerpo),
  });
}

async function cuerpo(res: Response): Promise<Record<string, unknown>> {
  return await res.json() as Record<string, unknown>;
}

Deno.test("OPTIONS responde ok (CORS)", async () => {
  const res = await manejarPeticion(
    new Request(URL_CHAT, { method: "OPTIONS" }),
  );
  assertEquals(res.status, 200);
  assertEquals(await res.text(), "ok");
  assertEquals(res.headers.get("Access-Control-Allow-Origin"), "*");
});

Deno.test("método distinto de POST responde 405", async () => {
  const res = await manejarPeticion(new Request(URL_CHAT, { method: "GET" }));
  assertEquals(res.status, 405);
});

Deno.test("sin JWT responde 401", async () => {
  const res = await manejarPeticion(peticionPost({ mensaje: "hola" }, null));
  assertEquals(res.status, 401);
});

Deno.test("con JWT inválido responde 401", async () => {
  const res = await manejarPeticion(
    peticionPost({ mensaje: "hola" }, "jwt-malo"),
    deps({ resolverUsuario: async () => null }),
  );
  assertEquals(res.status, 401);
});

Deno.test("mensaje vacío responde 400", async () => {
  const res = await manejarPeticion(peticionPost({ mensaje: "   " }), deps());
  assertEquals(res.status, 400);
});

Deno.test("mensaje que no es texto responde 400", async () => {
  const res = await manejarPeticion(peticionPost({ mensaje: 123 }), deps());
  assertEquals(res.status, 400);
});

Deno.test("mensaje demasiado largo responde 400", async () => {
  const res = await manejarPeticion(
    peticionPost({ mensaje: "a".repeat(LARGO_MAXIMO_MENSAJE + 1) }),
    deps(),
  );
  assertEquals(res.status, 400);
});

Deno.test("límite diario alcanzado responde 429", async () => {
  const { repositorio } = repoCaptura({
    contarMensajesUsuario: async () => MAX_MENSAJES_POR_DIA,
  });
  const res = await manejarPeticion(
    peticionPost({ mensaje: "hola" }),
    deps({ repositorio }),
  );
  assertEquals(res.status, 429);
  assert(String((await cuerpo(res))["error"]).includes("límite"));
});

Deno.test("justo antes del límite diario se procesa el mensaje", async () => {
  const { repositorio } = repoCaptura({
    contarMensajesUsuario: async () => MAX_MENSAJES_POR_DIA - 1,
  });
  const res = await manejarPeticion(
    peticionPost({ mensaje: "hola" }),
    deps({ repositorio }),
  );
  assertEquals(res.status, 200);
});

Deno.test("baja confianza cae a pedir_consejo (provisional)", async () => {
  const { repositorio, mensajes } = repoCaptura();
  const res = await manejarPeticion(
    peticionPost({ mensaje: "algo muy raro que no se clasifica" }),
    deps({
      repositorio,
      clasificarIntencion: () => ({ intencion: "consultar_datos", confianza: 0.2 }),
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "pedir_consejo");
  assertEquals(salida["respuesta"], RESPUESTA_PROVISIONAL);
  assertEquals(salida["origen"], "plantilla");
  assertEquals(salida["confianza"], 0.2);

  assertEquals(mensajes.length, 2);
  assertEquals(mensajes[0].rol, "usuario");
  assertEquals(mensajes[0].origen, null);
  assertEquals(mensajes[1].rol, "asistente");
  assertEquals(mensajes[1].origen, "plantilla");
});

Deno.test("routing consultar_datos: origen calculo", async () => {
  const { repositorio, mensajes } = repoCaptura({
    leerTransacciones: async () => [
      { categoria_id: "c1", tipo: "egreso", monto: 85000, fecha: "2026-10-20" },
    ],
    leerCategorias: async () => [
      { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
    ],
  });
  const res = await manejarPeticion(
    peticionPost({ mensaje: "cuanto llevo gastado esta semana" }),
    deps({
      repositorio,
      clasificarIntencion: () => ({ intencion: "consultar_datos", confianza: 0.92 }),
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "consultar_datos");
  assertEquals(salida["origen"], "calculo");
  assert(String(salida["respuesta"]).includes("$85.000"));
  assertEquals(mensajes[1].origen, "calculo");
});

Deno.test("routing ayuda_app: origen faq con acción de navegación", async () => {
  const { repositorio } = repoCaptura();
  const res = await manejarPeticion(
    peticionPost({ mensaje: "como cambio mi contrasena" }),
    deps({
      repositorio,
      clasificarIntencion: () => ({ intencion: "ayuda_app", confianza: 0.8 }),
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["origen"], "faq");
  assertEquals(salida["accion"], { tipo: "ir_a", destino: "perfil" });
});

Deno.test("oculta datos personales antes de guardar", async () => {
  const { repositorio, mensajes } = repoCaptura();
  const res = await manejarPeticion(
    peticionPost({ mensaje: "hola, mi cedula es 1020456789" }),
    deps({ repositorio }),
  );
  assertEquals(res.status, 200);
  const guardado = mensajes[0].contenido;
  assert(guardado.includes("[dato oculto]"));
  assert(!guardado.includes("1020456789"));
});

Deno.test("el usuario sale del JWT y no del body", async () => {
  const { repositorio, mensajes } = repoCaptura();
  const res = await manejarPeticion(
    peticionPost({ mensaje: "hola", usuario_id: "usuario-falso" }),
    deps({ repositorio, resolverUsuario: async () => "usuario-real" }),
  );
  assertEquals(res.status, 200);
  assertEquals(mensajes[0].usuario_id, "usuario-real");
  assertEquals(mensajes[1].usuario_id, "usuario-real");
});

Deno.test("un segundo argumento (ServeHandlerInfo) cae a las dependencias por defecto", async () => {
  // Deno.serve invoca el handler con (req, info). Si el manejador se pasa
  // directamente, ese ServeHandlerInfo ocupa el lugar de "dependencias" y, sin
  // el respaldo, se llamaría a resolverUsuario sobre él (500 en producción).
  // Se sustituye la fábrica del respaldo para no tocar la red y poder verificar
  // que la resolución por defecto sí se usó.
  const JWT = "jwt-de-prueba";
  const { repositorio, mensajes } = repoCaptura();
  const jwtRecibido: (string | null)[] = [];
  const anterior = fijarDependenciasDeRespaldo(() => ({
    ...deps(),
    repositorio,
    resolverUsuario: async (jwt) => {
      jwtRecibido.push(jwt);
      return jwt === JWT ? "usuario-1" : null;
    },
  }));

  try {
    const res = await manejarPeticion(
      peticionPost({ mensaje: "hola" }, JWT),
      // Simula el ServeHandlerInfo que Deno.serve pasa como segundo argumento.
      { remoteAddr: { transport: "tcp", hostname: "127.0.0.1", port: 1234 } } as unknown as never,
    );

    assertNotEquals(res.status, 500);
    assertEquals(res.status, 200);
    assertEquals(jwtRecibido, [JWT]);
    assertEquals(mensajes[0].usuario_id, "usuario-1");
  } finally {
    fijarDependenciasDeRespaldo(anterior);
  }
});

Deno.test("el umbral de intención usado por el manejador es 0.45", () => {
  assertEquals(UMBRAL_INTENCION, 0.45);
});

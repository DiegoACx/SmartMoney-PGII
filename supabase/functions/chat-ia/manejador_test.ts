// ============================================================================
// Pruebas de manejador.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red ni Supabase: se inyectan DependenciasChat (usuario, repositorio, fetch
// y reloj) para verificar el flujo HTTP completo.
// ============================================================================

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1";

import { GEMINI_MODELO } from "../_shared/gemini.ts";
import { UMBRAL_INTENCION, type ClasificacionIntencion } from "./clasificadores.ts";
import {
  decidirIntencion,
  fijarDependenciasDeRespaldo,
  LARGO_MAXIMO_MENSAJE,
  manejarPeticion,
  MAX_MENSAJES_POR_DIA,
  type DependenciasChat,
} from "./manejador.ts";
import { AVISO_CONSEJO } from "./pedir_consejo.ts";
import type { MensajeNuevo, RepositorioChat } from "./repositorio.ts";
import { AVISO_SIMULACION } from "./simular_escenario.ts";

const URL_CHAT = "https://proyecto.supabase.co/functions/v1/chat-ia";

function repoCaptura(parcial: Partial<RepositorioChat> = {}) {
  const mensajes: MensajeNuevo[] = [];
  const repositorio: RepositorioChat = {
    contarMensajesUsuario: () => Promise.resolve(0),
    ultimoMensajeAsistente: () => Promise.resolve(null),
    insertarMensaje: (mensaje) => {
      mensajes.push(mensaje);
      return Promise.resolve();
    },
    leerTransacciones: () => Promise.resolve([]),
    leerCategorias: () => Promise.resolve([]),
    leerMetasActivas: () => Promise.resolve([]),
    leerAportes: () => Promise.resolve([]),
    leerLeccionesValidas: () => Promise.resolve([]),
    leerHallazgosRecientes: () => Promise.resolve([]),
    ...parcial,
  };
  return { repositorio, mensajes };
}

function deps(cambios: Partial<DependenciasChat> = {}): DependenciasChat {
  return {
    resolverUsuario: () => Promise.resolve("usuario-1"),
    repositorio: repoCaptura().repositorio,
    fetchFn: (() =>
      Promise.reject(
        new Error("no hay red en las pruebas"),
      )) as unknown as typeof fetch,
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

const ANTERIOR_SEGUIMIENTO =
  "Esta semana llevas $85.000 en gastos, el 40 % en Comidas.";

/** fetch que responde 429 (cuota agotada) en cualquier modelo. */
const fetch429 = (() =>
  Promise.resolve(
    new Response(
      JSON.stringify({ error: { code: 429, status: "RESOURCE_EXHAUSTED" } }),
      { status: 429, headers: { "Content-Type": "application/json" } },
    ),
  )) as unknown as typeof fetch;

/** fetch que da 429 en el modelo principal y 200 con `texto` en el respaldo. */
function fetch429YRespaldoOk(texto: string): typeof fetch {
  return ((input: RequestInfo | URL) => {
    const esPrincipal = String(input).includes(`${GEMINI_MODELO}:`);
    if (esPrincipal) {
      return Promise.resolve(
        new Response(
          JSON.stringify({ error: { code: 429, status: "RESOURCE_EXHAUSTED" } }),
          { status: 429, headers: { "Content-Type": "application/json" } },
        ),
      );
    }
    return Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: texto }] } }] }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  }) as unknown as typeof fetch;
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
    deps({ resolverUsuario: () => Promise.resolve(null) }),
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
    contarMensajesUsuario: () => Promise.resolve(MAX_MENSAJES_POR_DIA),
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
    contarMensajesUsuario: () => Promise.resolve(MAX_MENSAJES_POR_DIA - 1),
  });
  const res = await manejarPeticion(
    peticionPost({ mensaje: "hola" }),
    deps({ repositorio }),
  );
  assertEquals(res.status, 200);
});

Deno.test("baja confianza cae a pedir_consejo (con plantilla y aviso)", async () => {
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
  assertEquals(salida["origen"], "plantilla");
  assertEquals(salida["confianza"], 0.2);
  assertEquals(salida["aviso"], AVISO_CONSEJO);

  assertEquals(mensajes.length, 2);
  assertEquals(mensajes[0].rol, "usuario");
  assertEquals(mensajes[0].origen, null);
  assertEquals(mensajes[0].motivo, "baja_confianza|consejo:sin_clave");
  assertEquals(mensajes[1].rol, "asistente");
  assertEquals(mensajes[1].origen, "plantilla");
  // El aviso viaja con la respuesta del asistente para poder mostrarlo aparte.
  assertEquals(mensajes[1].aviso, AVISO_CONSEJO);
});

Deno.test("routing consultar_datos: origen calculo", async () => {
  const { repositorio, mensajes } = repoCaptura({
    leerTransacciones: () =>
      Promise.resolve([
        { categoria_id: "c1", tipo: "egreso", monto: 85000, fecha: "2026-10-20" },
      ]),
    leerCategorias: () =>
      Promise.resolve([
        { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
      ]),
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
    deps({ repositorio, resolverUsuario: () => Promise.resolve("usuario-real") }),
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
    resolverUsuario: (jwt) => {
      jwtRecibido.push(jwt);
      return Promise.resolve(jwt === JWT ? "usuario-1" : null);
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

Deno.test("routing simular_escenario: cálculo, aviso y acción a metas", async () => {
  const { repositorio, mensajes } = repoCaptura({
    leerTransacciones: (_u, _d, _h, tipo) =>
      Promise.resolve(
        tipo === "ingreso"
          ? [
            { categoria_id: null, tipo: "ingreso", monto: 2_000_000, fecha: "2026-07-10" },
            { categoria_id: null, tipo: "ingreso", monto: 2_000_000, fecha: "2026-08-10" },
            { categoria_id: null, tipo: "ingreso", monto: 2_000_000, fecha: "2026-09-10" },
          ]
          : [
            { categoria_id: null, tipo: "egreso", monto: 1_200_000, fecha: "2026-09-15" },
          ],
      ),
    leerMetasActivas: () =>
      Promise.resolve([
        {
          id: "m1",
          nombre: "Viaje",
          monto_objetivo: 3_000_000,
          monto_actual: 1_000_000,
          fecha_limite: "2027-04-30",
          cumplida: false,
        },
      ]),
  });
  const res = await manejarPeticion(
    peticionPost({ mensaje: "¿llego a 3 millones para diciembre?" }),
    deps({
      repositorio,
      clasificarIntencion: () => ({ intencion: "simular_escenario", confianza: 0.9 }),
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "simular_escenario");
  assertEquals(salida["origen"], "calculo");
  assertEquals(salida["aviso"], AVISO_SIMULACION);
  assertEquals(salida["accion"], { tipo: "ir_a", destino: "metas" });
  assert(String(salida["respuesta"]).includes("$3.000.000"));
  assertEquals(mensajes[1].origen, "calculo");
});

Deno.test("regla híbrida: 'si recorto…' va a simular_escenario antes del modelo", async () => {
  const { repositorio, mensajes } = repoCaptura();
  let modeloConsultado = false;
  const res = await manejarPeticion(
    peticionPost({
      mensaje: "si recorto lo que gasto en domicilios cuanto mas rapido cumplo mi meta",
    }),
    deps({
      repositorio,
      // El modelo diría otra cosa; la regla debe ganar.
      clasificarIntencion: () => {
        modeloConsultado = true;
        return { intencion: "consultar_datos", confianza: 0.92 };
      },
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "simular_escenario");
  assertEquals(salida["confianza"], 1);
  assertEquals(modeloConsultado, false);
  assertEquals(mensajes[0].motivo, "regla:si recorto|simulacion:recorte:sin_clave");
  assertEquals(mensajes[1].motivo, "regla:si recorto|simulacion:recorte:sin_clave");
});

Deno.test("sin regla, la intención la decide el modelo", async () => {
  const { repositorio, mensajes } = repoCaptura({
    leerTransacciones: () =>
      Promise.resolve([
        { categoria_id: "c1", tipo: "egreso", monto: 85000, fecha: "2026-10-20" },
      ]),
    leerCategorias: () =>
      Promise.resolve([
        { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
      ]),
  });
  const consultas: string[] = [];
  const res = await manejarPeticion(
    peticionPost({ mensaje: "cuanto gaste en domicilios" }),
    deps({
      repositorio,
      clasificarIntencion: (texto) => {
        consultas.push(texto);
        return { intencion: "consultar_datos", confianza: 0.9 };
      },
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(consultas.length, 1);
  assertEquals(salida["intencion"], "consultar_datos");
  assertEquals(mensajes[0].motivo?.startsWith("regla:"), false);
});

Deno.test("el umbral de intención usado por el manejador es 0.45", () => {
  assertEquals(UMBRAL_INTENCION, 0.45);
});

Deno.test("429 en el principal y en el respaldo: plantilla, motivo y 200", async () => {
  // Punto 3a: Gemini responde 429 (cuota agotada) en ambos modelos. La petición
  // NO puede terminar en 500: cae a la plantilla y responde 200.
  const { repositorio, mensajes } = repoCaptura({
    ultimoMensajeAsistente: () => Promise.resolve(ANTERIOR_SEGUIMIENTO),
  });
  const res = await manejarPeticion(
    peticionPost({ mensaje: "explícamelo más fácil" }),
    deps({
      repositorio,
      fetchFn: fetch429,
      claveLLM: "clave-prueba",
      clasificarIntencion: () => ({ intencion: "conversacion", confianza: 0.9 }),
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "conversacion");
  assertEquals(salida["origen"], "plantilla");
  assert(String(salida["respuesta"]).includes(ANTERIOR_SEGUIMIENTO));
  // Punto 3c: el motivo deja rastro del fallo y se distingue de "sin_clave".
  assertEquals(mensajes[1].origen, "plantilla");
  assertEquals(mensajes[1].motivo, "modelo|gemini_429_ambos_plantilla");
});

Deno.test("429 solo en el principal y 200 en el respaldo: se usa el respaldo", async () => {
  // Punto 3b: el principal da 429 y el respaldo (lite) responde 200 con texto
  // válido, así que la respuesta sale del LLM y la petición responde 200.
  const TEXTO_RESPALDO =
    "En corto: esta semana has gastado $85.000 y el 40 % se fue en Comidas.";
  const { repositorio, mensajes } = repoCaptura({
    ultimoMensajeAsistente: () => Promise.resolve(ANTERIOR_SEGUIMIENTO),
  });
  const res = await manejarPeticion(
    peticionPost({ mensaje: "explícamelo más fácil" }),
    deps({
      repositorio,
      fetchFn: fetch429YRespaldoOk(TEXTO_RESPALDO),
      claveLLM: "clave-prueba",
      clasificarIntencion: () => ({ intencion: "conversacion", confianza: 0.9 }),
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "conversacion");
  assertEquals(salida["origen"], "llm");
  assertEquals(salida["respuesta"], TEXTO_RESPALDO);
  assertEquals(mensajes[1].origen, "llm");
  assertEquals(mensajes[1].motivo, "modelo|gemini_429_principal_respaldo_ok");
});

Deno.test("regla híbrida: 'q es el 4 por mil…' va a aprender_concepto antes del modelo", async () => {
  const { repositorio, mensajes } = repoCaptura();
  let modeloConsultado = false;
  const res = await manejarPeticion(
    peticionPost({ mensaje: "q es el 4 por mil y cuando me lo cobran" }),
    deps({
      repositorio,
      // El modelo diría otra cosa; la regla debe ganar.
      clasificarIntencion: () => {
        modeloConsultado = true;
        return { intencion: "consultar_datos", confianza: 0.92 };
      },
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "aprender_concepto");
  assertEquals(salida["confianza"], 1);
  assertEquals(modeloConsultado, false);
  assertEquals(mensajes[0].motivo, "regla:concepto|aprender:glosario:gmf-cuenta-exenta:sin_clave");
  assertEquals(mensajes[1].motivo, "regla:concepto|aprender:glosario:gmf-cuenta-exenta:sin_clave");
  // Sin LLM se usa la definición del glosario del GMF.
  assert(String(salida["respuesta"]).includes("4x1000"));
});

Deno.test("regla híbrida: 'Q es el 4x1000…' también va a aprender_concepto", async () => {
  const { repositorio, mensajes } = repoCaptura();
  let modeloConsultado = false;
  const res = await manejarPeticion(
    peticionPost({ mensaje: "Q es el 4x1000 y cuando me lo cobran" }),
    deps({
      repositorio,
      clasificarIntencion: () => {
        modeloConsultado = true;
        return { intencion: "consultar_datos", confianza: 0.92 };
      },
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "aprender_concepto");
  assertEquals(salida["confianza"], 1);
  assertEquals(modeloConsultado, false);
  assertEquals(mensajes[0].motivo, "regla:concepto|aprender:glosario:gmf-cuenta-exenta:sin_clave");
  assert(String(salida["respuesta"]).includes("4x1000"));
});

Deno.test("regla híbrida: elegir entre cdt o abonar va a pedir_consejo", async () => {
  const { repositorio, mensajes } = repoCaptura();
  let modeloConsultado = false;
  const res = await manejarPeticion(
    peticionPost({
      mensaje:
        "tengo una prima de 1 millon, la meto a un cdt o abono a la deuda?",
    }),
    deps({
      repositorio,
      clasificarIntencion: () => {
        modeloConsultado = true;
        return { intencion: "consultar_datos", confianza: 0.92 };
      },
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(salida["intencion"], "pedir_consejo");
  assertEquals(salida["confianza"], 1);
  assertEquals(modeloConsultado, false);
  assertEquals(mensajes[0].motivo, "regla:decision|consejo:sin_clave");
});

Deno.test("'como funciona la app' no aplica regla:concepto y la decide el modelo", async () => {
  const { repositorio, mensajes } = repoCaptura();
  let modeloConsultado = false;
  const res = await manejarPeticion(
    peticionPost({ mensaje: "como funciona la app" }),
    deps({
      repositorio,
      clasificarIntencion: () => {
        modeloConsultado = true;
        return { intencion: "ayuda_app", confianza: 0.8 };
      },
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(modeloConsultado, true);
  assertEquals(salida["intencion"], "ayuda_app");
  assertEquals(mensajes[0].motivo?.startsWith("regla:"), false);
});

Deno.test("'cuanto me rinde un cdt de 1 millon' sigue en simular_escenario (sin regla)", async () => {
  const { repositorio, mensajes } = repoCaptura();
  let modeloConsultado = false;
  const res = await manejarPeticion(
    peticionPost({ mensaje: "cuanto me rinde un cdt de 1 millon" }),
    deps({
      repositorio,
      clasificarIntencion: () => {
        modeloConsultado = true;
        return { intencion: "simular_escenario", confianza: 0.9 };
      },
    }),
  );
  assertEquals(res.status, 200);
  const salida = await cuerpo(res);
  assertEquals(modeloConsultado, true);
  assertEquals(salida["intencion"], "simular_escenario");
  assertEquals(mensajes[0].motivo?.startsWith("regla:"), false);
});

Deno.test("decidirIntencion coincide con el manejador en los casos de reglas híbridas", async () => {
  // La evaluación del sistema (ia/fase6/evaluar_sistema.ts) decide la intención
  // con decidirIntencion: esta prueba fija que da exactamente lo mismo que el
  // manejador (misma intención, misma confianza y mismo origen del motivo) en
  // los mensajes de las pruebas de reglas híbridas de arriba.
  const casos: {
    mensaje: string;
    clasificar: (texto: string) => ClasificacionIntencion;
  }[] = [
    {
      mensaje:
        "si recorto lo que gasto en domicilios cuanto mas rapido cumplo mi meta",
      clasificar: () => ({ intencion: "consultar_datos", confianza: 0.92 }),
    },
    {
      mensaje: "q es el 4 por mil y cuando me lo cobran",
      clasificar: () => ({ intencion: "consultar_datos", confianza: 0.92 }),
    },
    {
      mensaje: "tengo una prima de 1 millon, la meto a un cdt o abono a la deuda?",
      clasificar: () => ({ intencion: "consultar_datos", confianza: 0.92 }),
    },
    {
      mensaje: "cuanto gaste en domicilios",
      clasificar: () => ({ intencion: "consultar_datos", confianza: 0.9 }),
    },
    {
      mensaje: "como funciona la app",
      clasificar: () => ({ intencion: "ayuda_app", confianza: 0.8 }),
    },
    {
      mensaje: "cuanto me rinde un cdt de 1 millon",
      clasificar: () => ({ intencion: "simular_escenario", confianza: 0.9 }),
    },
    {
      // Sin señal del modelo y por debajo del umbral: respaldo a pedir_consejo.
      mensaje: "algo muy raro que no se clasifica",
      clasificar: () => ({ intencion: "simular_escenario", confianza: 0.3 }),
    },
  ];

  for (const caso of casos) {
    const { repositorio, mensajes } = repoCaptura();
    const res = await manejarPeticion(
      peticionPost({ mensaje: caso.mensaje }),
      deps({ repositorio, clasificarIntencion: caso.clasificar }),
    );
    assertEquals(res.status, 200, caso.mensaje);
    const salida = await cuerpo(res);
    const esperado = decidirIntencion(caso.mensaje, caso.clasificar);
    assertEquals(salida["intencion"], esperado.intencion, caso.mensaje);
    assertEquals(salida["confianza"], esperado.confianza, caso.mensaje);
    // El motivo arranca con el origen que devolvió decidirIntencion.
    assertEquals(
      mensajes[0].motivo?.startsWith(`${esperado.origen}|`),
      true,
      caso.mensaje,
    );
    assertEquals(
      mensajes[1].motivo?.startsWith(`${esperado.origen}|`),
      true,
      caso.mensaje,
    );
  }
});

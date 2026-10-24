// ============================================================================
// Pruebas de aprender_concepto.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red ni Supabase: el repositorio y el `fetch` se inyectan. Se cubren los
// dos caminos (con fuente del glosario o de una lección, y sin fuente) y sus
// respaldos cuando Gemini no está disponible o no pasa la validación.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  CIERRE_FUENTE_OFICIAL,
  responderAprendizaje,
  SIN_INFORMACION,
} from "./aprender_concepto.ts";
import type { FilaLeccion, RepositorioChat } from "./repositorio.ts";

/** Repositorio mínimo: el aprendizaje solo lee las lecciones válidas. */
function repoAprendizaje(lecciones: FilaLeccion[] = []): RepositorioChat {
  return {
    contarMensajesUsuario: () => Promise.resolve(0),
    ultimoMensajeAsistente: () => Promise.resolve(null),
    insertarMensaje: () => Promise.resolve(),
    leerTransacciones: () => Promise.resolve([]),
    leerCategorias: () => Promise.resolve([]),
    leerMetasActivas: () => Promise.resolve([]),
    leerAportes: () => Promise.resolve([]),
    leerLeccionesValidas: () => Promise.resolve(lecciones),
    leerHallazgosRecientes: () => Promise.resolve([]),
  };
}

/** `fetch` falso que responde 200 con el texto dado. */
function fetchQueResponde(texto: string): typeof fetch {
  return (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: texto }] } }] }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    )) as unknown as typeof fetch;
}

/** `fetch` falso que responde un texto distinto en cada llamada, en orden. */
function fetchPorLlamadas(textos: string[]): typeof fetch {
  let llamada = 0;
  return (() => {
    const texto = textos[Math.min(llamada, textos.length - 1)];
    llamada++;
    return Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: texto }] } }] }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  }) as unknown as typeof fetch;
}

const LECCION_SOBRES: FilaLeccion = {
  id: "e12",
  titulo: "Separar la plata en sobres",
  contenido:
    "Separar la plata en sobres te ayuda a no gastar de más. Puedes separar la plata en sobres para la comida, el transporte y los gustos.",
};

const LECCION_PRESUPUESTO: FilaLeccion = {
  id: "e20",
  titulo: "Presupuesto mensual",
  contenido:
    "Un presupuesto es un plan para repartir tu plata entre gastos, ahorro y gustos. Sirve para decidir antes de gastar.",
};

// --- Con fuente: glosario -----------------------------------------------------

Deno.test("aprender glosario: sin Gemini usa la definición y el ejemplo", async () => {
  const resultado = await responderAprendizaje("que es un cdt", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchQueResponde("no se debe usar"),
    claveLLM: null,
  });

  assertEquals(resultado.origen, "plantilla");
  assertEquals(resultado.motivo, "aprender:glosario:cdt:sin_clave");
  assert(resultado.respuesta.startsWith("Un CDT es un ahorro"));
  assert(resultado.respuesta.includes("Dejar $1.000.000 en un CDT"));
  assertEquals(resultado.accion, undefined);
  assertEquals(resultado.aviso, undefined);
});

Deno.test("aprender glosario: Gemini explica solo con la fuente", async () => {
  const texto =
    "Un CDT es un ahorro que dejas quieto por un tiempo pactado y a cambio la entidad te paga un interés.";
  const resultado = await responderAprendizaje("que es un cdt", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchQueResponde(texto),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.respuesta, texto);
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.motivo, "aprender:glosario:cdt");
});

Deno.test("aprender glosario: cifra inventada cae a la plantilla", async () => {
  const resultado = await responderAprendizaje("que es un cdt", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchQueResponde("Dejas la plata y ganas un 25 % de interés."),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.origen, "plantilla");
  assertEquals(
    resultado.motivo,
    "aprender:glosario:cdt:validacion:cifra_no_permitida:25",
  );
  assert(resultado.respuesta.startsWith("Un CDT es un ahorro"));
});

// --- Con fuente: lección ------------------------------------------------------

Deno.test("aprender lección: usa el texto de la lección y ofrece abrirla", async () => {
  const resultado = await responderAprendizaje(
    "como separar la plata en sobres",
    {
      repositorio: repoAprendizaje([LECCION_SOBRES]),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
  );

  assertEquals(resultado.motivo, "aprender:leccion:e12:sin_clave");
  assertEquals(resultado.origen, "plantilla");
  assert(resultado.respuesta.startsWith("Separar la plata en sobres:"));
  assertEquals(resultado.accion, { tipo: "abrir_leccion", escalon_id: "e12" });
});

Deno.test("aprender glosario y lección: gana el glosario pero ofrece la lección", async () => {
  const texto =
    "Un presupuesto es un plan para repartir tu plata entre gastos, ahorro y gustos antes de gastar.";
  const resultado = await responderAprendizaje("que es un presupuesto", {
    repositorio: repoAprendizaje([LECCION_PRESUPUESTO]),
    fetchFn: fetchQueResponde(texto),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.motivo, "aprender:glosario:presupuesto");
  assertEquals(resultado.respuesta, texto);
  assertEquals(resultado.accion, { tipo: "abrir_leccion", escalon_id: "e20" });
});

// --- Con fuente: la fuente no explica el concepto -----------------------------

Deno.test("aprender con fuente: si Gemini dice SIN_INFORMACION pasa a la rama general", async () => {
  const general =
    "Es una idea amplia que depende de cada caso, así que conviene mirarla con calma. " +
    CIERRE_FUENTE_OFICIAL;
  // Primera llamada (con fuente) devuelve SIN_INFORMACION; la segunda (general)
  // ya trae una explicación válida.
  const resultado = await responderAprendizaje("que es un cdt", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchPorLlamadas([SIN_INFORMACION, general]),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.motivo, "aprender:general");
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.respuesta, general);
  assertEquals(resultado.accion, undefined);
});

Deno.test("aprender con fuente: si la respuesta menciona la fuente pasa a la rama general", async () => {
  const general = "Un CDT deja tu plata quieta por un tiempo pactado. " +
    CIERRE_FUENTE_OFICIAL;
  const resultado = await responderAprendizaje("que es un cdt", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchPorLlamadas([
      "Según el texto fuente, un CDT deja tu plata quieta.",
      general,
    ]),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.motivo, "aprender:general");
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.respuesta, general);
});

// --- Sin fuente: conocimiento general ----------------------------------------

Deno.test("aprender general: Gemini responde sin cifras y con el cierre", async () => {
  const texto =
    "Es una idea amplia que depende de cada caso, así que conviene mirarla con calma y con tus propios datos. " +
    CIERRE_FUENTE_OFICIAL;
  const resultado = await responderAprendizaje("por que mi jefe no me sube el sueldo", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchQueResponde(texto),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.respuesta, texto);
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.motivo, "aprender:general");
});

Deno.test("aprender general: rechaza cifras y ofrece conceptos del glosario", async () => {
  const resultado = await responderAprendizaje("por que mi jefe no me sube el sueldo", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchQueResponde(
      "Podrías ahorrar el 20 % de tus ingresos. " + CIERRE_FUENTE_OFICIAL,
    ),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.origen, "plantilla");
  assertEquals(
    resultado.motivo,
    "aprender:general:validacion:cifra_no_permitida:20",
  );
  assert(resultado.respuesta.startsWith(SIN_INFORMACION));
  assert(resultado.respuesta.includes("Fondo de emergencia"));
  assert(resultado.respuesta.includes("Interés compuesto"));
  assert(resultado.respuesta.includes("Presupuesto"));
});

Deno.test("aprender general: exige el cierre de fuente oficial", async () => {
  const resultado = await responderAprendizaje("por que mi jefe no me sube el sueldo", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchQueResponde("Es una idea amplia y depende de cada caso."),
    claveLLM: "clave-de-prueba",
  });

  assertEquals(resultado.origen, "plantilla");
  assertEquals(resultado.motivo, "aprender:general:validacion:sin_fuente_oficial");
  assert(resultado.respuesta.startsWith(SIN_INFORMACION));
});

Deno.test("aprender general: sin Gemini cae a la plantilla", async () => {
  const resultado = await responderAprendizaje("por que mi jefe no me sube el sueldo", {
    repositorio: repoAprendizaje(),
    fetchFn: fetchQueResponde("no se debe usar"),
    claveLLM: null,
  });

  assertEquals(resultado.origen, "plantilla");
  assertEquals(resultado.motivo, "aprender:general:sin_clave");
  assert(resultado.respuesta.startsWith(SIN_INFORMACION));
});

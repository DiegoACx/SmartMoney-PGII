// ============================================================================
// Pruebas de conversacion.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: saludo/gracias/despedida/bot/fuera de tema se resuelven con reglas;
// el seguimiento se prueba con un fetch falso que devuelve un texto fijo.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import { responderConversacion } from "./conversacion.ts";

const ANTERIOR = "Esta semana llevas $85.000 en gastos, el 40 % en Comidas.";

/** fetch que devuelve siempre el mismo texto de Gemini. */
function fetchTexto(texto: string): typeof fetch {
  return (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({
          candidates: [{ content: { parts: [{ text: texto }] } }],
        }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    )) as unknown as typeof fetch;
}

/** fetch que simula un fallo de red (nunca debería usarse en las reglas). */
const fetchQueFalla = (() =>
  Promise.reject(new Error("no debe llamarse"))) as unknown as typeof fetch;

Deno.test("saludo: respuesta corta con ejemplos", async () => {
  const resultado = await responderConversacion({
    mensaje: "hola",
    ultimoMensajeAsistente: null,
    fetchFn: fetchQueFalla,
  });
  assertEquals(resultado.motivo, "saludo");
  assertEquals(resultado.origen, "plantilla");
  assert(resultado.respuesta.includes("Hola"));
});

Deno.test("agradecimiento", async () => {
  const resultado = await responderConversacion({
    mensaje: "muchas gracias por la ayuda",
    ultimoMensajeAsistente: null,
    fetchFn: fetchQueFalla,
  });
  assertEquals(resultado.motivo, "gracias");
});

Deno.test("despedida", async () => {
  const resultado = await responderConversacion({
    mensaje: "chao, hasta luego",
    ultimoMensajeAsistente: null,
    fetchFn: fetchQueFalla,
  });
  assertEquals(resultado.motivo, "despedida");
});

Deno.test("pregunta por el bot", async () => {
  const resultado = await responderConversacion({
    mensaje: "eres un bot o una persona?",
    ultimoMensajeAsistente: null,
    fetchFn: fetchQueFalla,
  });
  assertEquals(resultado.motivo, "bot");
  assert(resultado.respuesta.includes("asistente de SmartMoney"));
});

Deno.test("fuera de tema: solo finanzas y app", async () => {
  const resultado = await responderConversacion({
    mensaje: "quién ganó el partido de fútbol anoche",
    ultimoMensajeAsistente: null,
    fetchFn: fetchQueFalla,
  });
  assertEquals(resultado.motivo, "fuera_de_tema");
  assert(resultado.respuesta.startsWith("Solo puedo ayudarte con tus finanzas"));
});

Deno.test("seguimiento sin mensaje anterior usa plantilla", async () => {
  const resultado = await responderConversacion({
    mensaje: "no entendí",
    ultimoMensajeAsistente: null,
    fetchFn: fetchQueFalla,
  });
  assertEquals(resultado.motivo, "seguimiento_sin_anterior");
  assertEquals(resultado.origen, "plantilla");
});

Deno.test("seguimiento con LLM válido (sin cifras nuevas)", async () => {
  const resultado = await responderConversacion({
    mensaje: "explícamelo más fácil",
    ultimoMensajeAsistente: ANTERIOR,
    fetchFn: fetchTexto(
      "En pocas palabras: esta semana has gastado 85000, sobre todo en comida.",
    ),
    claveLLM: "clave-prueba",
  });
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.motivo, "ok");
  assert(resultado.respuesta.includes("85000"));
});

Deno.test("seguimiento rechaza cifras nuevas y cae a plantilla", async () => {
  const resultado = await responderConversacion({
    mensaje: "explícamelo más fácil",
    ultimoMensajeAsistente: ANTERIOR,
    fetchFn: fetchTexto("Gastaste 90000 esta semana."),
    claveLLM: "clave-prueba",
  });
  assertEquals(resultado.origen, "plantilla");
  assert(resultado.motivo.startsWith("validacion:"));
  assert(resultado.respuesta.includes(ANTERIOR));
});

Deno.test("seguimiento sin clave de LLM cae a plantilla", async () => {
  const resultado = await responderConversacion({
    mensaje: "otra vez",
    ultimoMensajeAsistente: ANTERIOR,
    fetchFn: fetchTexto("No debería usarse."),
    claveLLM: null,
  });
  assertEquals(resultado.origen, "plantilla");
  assertEquals(resultado.motivo, "sin_clave");
  assert(resultado.respuesta.includes(ANTERIOR));
});

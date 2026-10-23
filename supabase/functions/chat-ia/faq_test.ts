// ============================================================================
// Pruebas de faq.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: el emparejado es puro (Jaccard de trigramas sobre faq.json).
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import { responderFaq, UMBRAL_FAQ } from "./faq.ts";

import faqJson from "./faq.json" with { type: "json" };

interface EntradaFaq {
  id: string;
  pregunta: string;
  respuesta: string;
  accion?: { tipo: string; destino?: string };
}

const PREGUNTAS = faqJson.preguntas as EntradaFaq[];
const LISTA_CAPACIDADES = faqJson.lista_capacidades as string;

function porId(id: string): EntradaFaq {
  const encontrada = PREGUNTAS.find((item) => item.id === id);
  if (encontrada === undefined) throw new Error(`No existe la FAQ ${id}`);
  return encontrada;
}

Deno.test("el umbral de FAQ es 0.35", () => {
  assertEquals(UMBRAL_FAQ, 0.35);
});

Deno.test("«como cambio mi contrasena» responde la FAQ de contraseña", () => {
  const resultado = responderFaq("como cambio mi contrasena");
  const esperada = porId("perfil-contrasena");
  assertEquals(resultado.respuesta, esperada.respuesta);
  assertEquals(resultado.motivo, "faq:perfil-contrasena");
  assertEquals(resultado.origen, "faq");
  assertEquals(resultado.accion, { tipo: "ir_a", destino: "perfil" });
});

Deno.test("«como registro un movimiento» responde la FAQ de registro", () => {
  const resultado = responderFaq("como registro un movimiento");
  assertEquals(resultado.respuesta, porId("registrar-movimiento").respuesta);
  assertEquals(resultado.motivo, "faq:registrar-movimiento");
  assertEquals(resultado.accion, { tipo: "ir_a", destino: "movimientos" });
});

Deno.test("una FAQ sin pantalla asociada no trae accion", () => {
  const resultado = responderFaq("de donde salen las recomendaciones");
  assertEquals(resultado.motivo, "faq:recomendaciones");
  assertEquals(resultado.accion, undefined);
});

Deno.test("un texto sin relación devuelve la lista de capacidades", () => {
  const resultado = responderFaq("zzz qqq vvv xyzzy frobnicate");
  assertEquals(resultado.respuesta, LISTA_CAPACIDADES);
  assertEquals(resultado.motivo, "faq_sin_match");
  assertEquals(resultado.origen, "faq");
  assert(resultado.accion === undefined);
});

Deno.test("los ejemplos de cada FAQ se emparejan con su propia entrada", () => {
  for (const entrada of PREGUNTAS) {
    const resultado = responderFaq(entrada.pregunta);
    assertEquals(
      resultado.motivo,
      `faq:${entrada.id}`,
      `la pregunta "${entrada.pregunta}" no se emparejó consigo misma`,
    );
  }
});

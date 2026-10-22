// ============================================================================
// SmartMoney · Clasificador de movimientos · Pruebas del modelo
// ----------------------------------------------------------------------------
// Ejecutar:  deno test supabase/functions/clasificar-movimiento/modelo_test.ts
// ============================================================================

import {
  assert,
  assertAlmostEquals,
  assertEquals,
} from "jsr:@std/assert@1";

import {
  modelo,
  ngramasCharWb,
  normalizar,
  predecir,
  probabilidades,
} from "./modelo.ts";

Deno.test("normalizar: quita tildes, puntuación y espacios sobrantes", () => {
  assertEquals(normalizar("  Pasaje   METROLÍNEA!! "), "pasaje metrolinea");
  assertEquals(normalizar("Ñame"), "name");
});

Deno.test("ngramasCharWb: palabra corta con rango (2,5) no repite ngramas", () => {
  // "de" → acolchada " de " (largo 4) → n=2: " d","de","e "; n=3: " de","de ";
  // n=4: la palabra acolchada cabe, se agrega una sola vez y se corta el ciclo.
  assertEquals(ngramasCharWb("de", 2, 5), [
    " d",
    "de",
    "e ",
    " de",
    "de ",
    " de ",
  ]);

  const repetidos = ngramasCharWb("de", 2, 5).filter((g) => g === " de ").length;
  assertEquals(repetidos, 1);
});

Deno.test("predecir: texto vacío o sin ngramas conocidos devuelve null", () => {
  assertEquals(predecir(""), null);
  assertEquals(predecir("!!!"), null);
});

Deno.test("predecir: reproduce los casos de prueba del modelo", () => {
  assert(modelo.casos_prueba.length > 0);
  for (const caso of modelo.casos_prueba) {
    assertEquals(normalizar(caso.texto), caso.normalizado, caso.texto);

    const prediccion = predecir(caso.texto);
    assert(prediccion !== null, `sin predicción para "${caso.texto}"`);
    assertEquals(prediccion.grupo_id, caso.grupo_id, caso.texto);
    assert(
      Math.abs(prediccion.confianza - caso.probabilidad) < 0.001,
      `confianza ${prediccion.confianza} vs ${caso.probabilidad} en "${caso.texto}"`,
    );
  }
});

Deno.test("probabilidades: la suma sobre las 13 clases es 1", () => {
  const probs = probabilidades(modelo.casos_prueba[0].texto);
  assert(probs !== null);
  assertEquals(probs.length, modelo.clases.length);

  const suma = probs.reduce((total, p) => total + p, 0);
  assertAlmostEquals(suma, 1, 1e-9);
});

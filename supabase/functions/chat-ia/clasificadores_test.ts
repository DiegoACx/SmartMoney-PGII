// ============================================================================
// Pruebas de clasificadores.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: reproduce los casos_prueba de modelo_intencion.json con el predictor
// genérico y comprueba el enrutamiento por nombre de intención.
// ============================================================================

import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import {
  ClasificadorNgramas,
  type ModeloClasificador,
} from "../_shared/clasificador_ngramas.ts";
import { clasificarIntencion, grupos, UMBRAL_INTENCION } from "./clasificadores.ts";

import modeloIntencionJson from "./modelo_intencion.json" with { type: "json" };

const modelo = modeloIntencionJson as unknown as ModeloClasificador;

Deno.test("el umbral de intención es 0.45", () => {
  assertEquals(UMBRAL_INTENCION, 0.45);
});

Deno.test("un texto vacío no produce intención", () => {
  const resultado = clasificarIntencion("");
  assertEquals(resultado.intencion, null);
  assertEquals(resultado.confianza, 0);
});

Deno.test("el predictor reproduce todos los casos_prueba del modelo", () => {
  const clasificador = new ClasificadorNgramas(modelo);
  assert(modelo.casos_prueba.length > 0, "el modelo no trae casos_prueba");
  for (const caso of modelo.casos_prueba) {
    const prediccion = clasificador.predecir(caso.texto);
    assert(prediccion !== null, `sin predicción para "${caso.texto}"`);
    assertEquals(
      prediccion.grupo_id,
      caso.grupo_id,
      `clase distinta para "${caso.texto}"`,
    );
    assertAlmostEquals(prediccion.confianza, caso.probabilidad, 0.01);
  }
});

Deno.test("las probabilidades suman 1", () => {
  const clasificador = new ClasificadorNgramas(modelo);
  const probs = clasificador.probabilidades("cuanto gaste en comida este mes");
  assert(probs !== null);
  const suma = probs.reduce((total, valor) => total + valor, 0);
  assertAlmostEquals(suma, 1, 1e-6);
});

Deno.test("clasificarIntencion traduce la clase con el mapa de nombres", () => {
  for (const caso of modelo.casos_prueba) {
    const resultado = clasificarIntencion(caso.texto);
    assertEquals(
      resultado.intencion,
      modelo.nombres[String(caso.grupo_id)],
      `nombre distinto para "${caso.texto}"`,
    );
    assert(resultado.confianza > 0);
  }
});

Deno.test("el clasificador de grupos devuelve grupo y nombre", () => {
  const prediccion = grupos.predecir("pague el arriendo del apartamento");
  assert(prediccion !== null);
  assert(typeof prediccion.grupo_id === "number");
  assert(prediccion.confianza >= 0 && prediccion.confianza <= 1);
  const nombre = grupos.nombreGrupo(prediccion.grupo_id);
  assert(nombre.length > 0);
  assertEquals(grupos.nombreGrupo(11), "Comidas fuera y domicilios");
});

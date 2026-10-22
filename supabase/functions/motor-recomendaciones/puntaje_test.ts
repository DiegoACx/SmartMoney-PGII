// ============================================================================
// Pruebas de puntaje.ts  (deno test)
// ============================================================================

import { assertAlmostEquals, assertEquals } from "jsr:@std/assert";

import type { TipoHallazgo } from "./config.ts";
import type { HallazgoBase } from "./detectores.ts";
import {
  type HallazgoPuntuado,
  type RecomendacionPrevia,
  calcularConfianza,
  calcularPuntaje,
  calcularRepeticion,
  esRepeticion,
  puntuarHallazgos,
  seleccionar,
} from "./puntaje.ts";

function hallazgo(
  tipo: TipoHallazgo,
  severidad: number,
  impacto: number,
  p: number,
  objetivo = "grupo:1",
): HallazgoBase {
  return { tipo, datos: {}, severidad, impacto, p, objetivo };
}

function puntuado(
  tipo: TipoHallazgo,
  puntaje: number,
  objetivo = "objetivo",
): HallazgoPuntuado {
  return {
    tipo,
    datos: {},
    severidad: 1,
    impacto: 1,
    p: 1,
    objetivo,
    confianza: 1,
    repeticion: 1,
    peso_tipo_usado: 1,
    puntaje,
  };
}

// --- Factores ----------------------------------------------------------------

Deno.test("confianza = 0,5 + 0,5 × p", () => {
  assertEquals(calcularConfianza(0), 0.5);
  assertEquals(calcularConfianza(0.5), 0.75);
  assertEquals(calcularConfianza(1), 1);
});

Deno.test("repeticion = 0,2 si se recomendó hace poco; si no, 1", () => {
  assertEquals(calcularRepeticion(true), 0.2);
  assertEquals(calcularRepeticion(false), 1);
});

Deno.test("puntaje = peso × severidad × impacto × confianza × repeticion", () => {
  assertAlmostEquals(
    calcularPuntaje({
      peso_tipo: 1,
      severidad: 0.5,
      impacto: 0.5,
      confianza: 0.75,
      repeticion: 1,
    }),
    0.1875,
  );
});

Deno.test("esRepeticion compara tipo y objetivo dentro de los últimos 7 días", () => {
  const objetivo = hallazgo("sobregasto_categoria", 0.5, 0.5, 0.5, "grupo:7");

  const reciente: RecomendacionPrevia[] = [{
    tipo: "sobregasto_categoria",
    objetivo: "grupo:7",
    creadoEn: "2026-10-18",
  }];
  assertEquals(esRepeticion(objetivo, reciente, "2026-10-21"), true);

  const vieja: RecomendacionPrevia[] = [{
    tipo: "sobregasto_categoria",
    objetivo: "grupo:7",
    creadoEn: "2026-10-01",
  }];
  assertEquals(esRepeticion(objetivo, vieja, "2026-10-21"), false);

  // Otro objetivo (mismo tipo) no penaliza
  const otroObjetivo: RecomendacionPrevia[] = [{
    tipo: "sobregasto_categoria",
    objetivo: "grupo:1",
    creadoEn: "2026-10-20",
  }];
  assertEquals(esRepeticion(objetivo, otroObjetivo, "2026-10-21"), false);

  // Mismo objetivo pero otro tipo tampoco penaliza
  const otroTipo: RecomendacionPrevia[] = [{
    tipo: "logro",
    objetivo: "grupo:7",
    creadoEn: "2026-10-20",
  }];
  assertEquals(esRepeticion(objetivo, otroTipo, "2026-10-21"), false);
});

// --- Puntaje de todos los hallazgos ------------------------------------------

Deno.test("puntuarHallazgos no descarta ninguno y llena los factores", () => {
  const puntuados = puntuarHallazgos({
    hallazgos: [
      hallazgo("aporte_meta", 0.5, 0.5, 1, "meta:1"),
      hallazgo("gasto_anomalo", 0.5, 0.5, 0.5, "categoria:1"),
    ],
    previas: [{
      tipo: "aporte_meta",
      objetivo: "meta:1",
      creadoEn: "2026-10-20",
    }],
    hoy: "2026-10-21",
    obtenerPeso: (tipo) => (tipo === "aporte_meta" ? 0.9 : 0.7),
  });

  assertEquals(puntuados.length, 2);

  const meta = puntuados[0];
  assertEquals(meta.peso_tipo_usado, 0.9);
  assertEquals(meta.confianza, 1); // p = 1
  assertEquals(meta.repeticion, 0.2); // repetida hace un día
  assertAlmostEquals(
    meta.puntaje,
    0.9 * 0.5 * 0.5 * 1 * 0.2,
    1e-12,
  );

  const anomalia = puntuados[1];
  assertEquals(anomalia.peso_tipo_usado, 0.7);
  assertEquals(anomalia.confianza, 0.75); // p = 0,5
  assertEquals(anomalia.repeticion, 1);
  assertAlmostEquals(
    anomalia.puntaje,
    0.7 * 0.5 * 0.5 * 0.75 * 1,
    1e-12,
  );
});

// --- Selección ---------------------------------------------------------------

Deno.test("selección: el riesgo de fin de mes va siempre primero", () => {
  const seleccionados = seleccionar([
    puntuado("sobregasto_categoria", 0.9),
    puntuado("riesgo_fin_de_mes", 0.01),
  ]);

  assertEquals(seleccionados.length, 2);
  assertEquals(seleccionados[0].tipo, "riesgo_fin_de_mes");
  assertEquals(seleccionados[1].tipo, "sobregasto_categoria");
});

Deno.test("selección: solo el mejor de los otros cinco tipos si supera el mínimo", () => {
  const seleccionados = seleccionar([
    puntuado("sobregasto_categoria", 0.30),
    puntuado("gasto_anomalo", 0.50),
    puntuado("logro", 0.40),
  ]);

  assertEquals(seleccionados.length, 1);
  assertEquals(seleccionados[0].tipo, "gasto_anomalo");
});

Deno.test("selección: si ninguno supera el mínimo, cae al mejor logro o lección", () => {
  const seleccionados = seleccionar([
    puntuado("sobregasto_categoria", 0.10),
    puntuado("logro", 0.05),
    puntuado("leccion_sugerida", 0.08),
  ]);

  assertEquals(seleccionados.length, 1);
  assertEquals(seleccionados[0].tipo, "leccion_sugerida");
});

Deno.test("selección: sin logro ni lección y sin umbral, no recomienda nada", () => {
  assertEquals(
    seleccionar([
      puntuado("sobregasto_categoria", 0.10),
      puntuado("gasto_anomalo", 0.05),
    ]).length,
    0,
  );
});

Deno.test("selección: respaldo con riesgo presente y umbral no superado", () => {
  const seleccionados = seleccionar([
    puntuado("riesgo_fin_de_mes", 0.01),
    puntuado("sobregasto_categoria", 0.10),
    puntuado("logro", 0.05),
  ]);

  assertEquals(seleccionados.length, 2);
  assertEquals(seleccionados[0].tipo, "riesgo_fin_de_mes");
  assertEquals(seleccionados[1].tipo, "logro");
});

Deno.test("selección: nunca pasa de dos recomendaciones", () => {
  const seleccionados = seleccionar([
    puntuado("riesgo_fin_de_mes", 0.9),
    puntuado("sobregasto_categoria", 0.8),
    puntuado("gasto_anomalo", 0.7),
  ]);
  assertEquals(seleccionados.length, 2);

  // Con un tope explícito de 1, solo sale el riesgo
  assertEquals(seleccionar([puntuado("riesgo_fin_de_mes", 0.9)], 1).length, 1);
});

// ============================================================================
// Pruebas de montos.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: solo funciones puras de extracción (montos, porcentajes,
// periodicidad y plazos).
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import {
  aMensual,
  analizarMontos,
  detectarPeriodicidad,
  extraerMontos,
  extraerPlazoMeses,
  extraerPorcentajes,
  parsearNumero,
} from "./montos.ts";

const HOY = "2026-10-21";

/** Primer monto del texto, o null si no se detectó ninguno. */
function primerMonto(texto: string): number | null {
  const montos = extraerMontos(texto);
  return montos.length > 0 ? montos[0].valor : null;
}

Deno.test("montos: unidades escritas de mil", () => {
  assertEquals(primerMonto("300 mil"), 300_000);
  assertEquals(primerMonto("300mil"), 300_000);
  assertEquals(primerMonto("300k"), 300_000);
  assertEquals(primerMonto("50 lucas"), 50_000);
});

Deno.test("montos: número plano con separador de miles", () => {
  assertEquals(primerMonto("$300.000"), 300_000);
  assertEquals(primerMonto("300.000"), 300_000);
  assertEquals(primerMonto("$1.200.000 de gastos"), 1_200_000);
});

Deno.test("montos: millones en todas sus formas", () => {
  assertEquals(primerMonto("1 millón"), 1_000_000);
  assertEquals(primerMonto("un millon"), 1_000_000);
  assertEquals(primerMonto("1.5 millones"), 1_500_000);
  assertEquals(primerMonto("1,5 millones"), 1_500_000);
  assertEquals(primerMonto("3 millones"), 3_000_000);
  assertEquals(primerMonto("2 palos"), 2_000_000);
});

Deno.test("montos: los plazos y porcentajes NO se toman como montos", () => {
  assertEquals(extraerMontos("en 2 años"), []);
  assertEquals(extraerMontos("en 6 meses"), []);
  assertEquals(extraerMontos("10 %"), []);
  assertEquals(extraerMontos("10 por ciento"), []);
});

Deno.test("montos: varios montos se devuelven en orden", () => {
  const montos = extraerMontos("si ahorro 300 mil para un carro de 30 millones");
  assertEquals(montos.map((m) => m.valor), [300_000, 30_000_000]);
});

Deno.test("parsearNumero: miles con punto y decimales con coma", () => {
  assertEquals(parsearNumero("300.000"), 300_000);
  assertEquals(parsearNumero("1.5"), 1.5);
  assertEquals(parsearNumero("1,5"), 1.5);
  assertEquals(parsearNumero("1.234,5"), 1234.5);
});

Deno.test("porcentajes: %, con espacio y 'por ciento'", () => {
  assertEquals(extraerPorcentajes("ahorro el 10%"), [10]);
  assertEquals(extraerPorcentajes("ahorro el 10 %"), [10]);
  assertEquals(extraerPorcentajes("ahorro el 10 por ciento"), [10]);
  assertEquals(extraerPorcentajes("ahorro 2,5 %"), [2.5]);
  assertEquals(extraerPorcentajes("no hay ninguno"), []);
});

Deno.test("periodicidad: por palabra clave, mensual por defecto", () => {
  assertEquals(detectarPeriodicidad("ahorro 10 mil diarios"), "diario");
  assertEquals(detectarPeriodicidad("ahorro 10 mil cada semana"), "semanal");
  assertEquals(detectarPeriodicidad("ahorro 300 mil cada quincena"), "quincenal");
  assertEquals(detectarPeriodicidad("ahorro 300 mil al mes"), "mensual");
  assertEquals(detectarPeriodicidad("ahorro 3 millones al año"), "anual");
  assertEquals(detectarPeriodicidad("ahorro 300 mil"), "mensual");
});

Deno.test("aMensual: convierte cada periodicidad a un mes", () => {
  assertEquals(aMensual(100_000, "quincenal"), 200_000);
  assertEquals(aMensual(100_000, "mensual"), 100_000);
  assertEquals(aMensual(100_000, "semanal"), 434_500);
  assertEquals(aMensual(100_000, "diario"), 3_000_000);
  assertEquals(aMensual(1_200_000, "anual"), 100_000);
});

Deno.test("plazos: meses, años, 'para/en <mes>' y fin de año", () => {
  assertEquals(extraerPlazoMeses("en 6 meses", HOY), 6);
  assertEquals(extraerPlazoMeses("en 3 años", HOY), 36);
  assertEquals(extraerPlazoMeses("en un año", HOY), 12);
  assertEquals(extraerPlazoMeses("para diciembre", HOY), 2);
  assertEquals(extraerPlazoMeses("en diciembre", HOY), 2);
  assertEquals(extraerPlazoMeses("para enero", HOY), 3);
  assertEquals(extraerPlazoMeses("a fin de año", HOY), 2);
  assertEquals(extraerPlazoMeses("no digo plazo", HOY), null);
});

Deno.test("analizarMontos: lee todo de una sola vez", () => {
  const analisis = analizarMontos(
    "si ahorro 300 mil cada quincena, ¿en cuánto llego a mi meta para diciembre?",
    HOY,
  );
  assertEquals(analisis.montos.map((m) => m.valor), [300_000]);
  assertEquals(analisis.porcentajes, []);
  assertEquals(analisis.periodicidad, "quincenal");
  assertEquals(analisis.plazoMeses, 2);
});

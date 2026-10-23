// ============================================================================
// Pruebas de fechas.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: periodos, tipo (ingreso/egreso) y aritmética de fechas en la zona
// horaria de Colombia. El 2026-10-21 es miércoles.
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import { normalizar } from "../_shared/clasificador_ngramas.ts";
import {
  hoyEnBogota,
  inicioDelDiaBogota,
  interpretarTipo,
  lunesDeSemana,
  mesAnterior,
  periodoDe,
  rangoDePeriodo,
  sumarDias,
  ultimoDiaDeMes,
} from "./fechas.ts";

const HOY = "2026-10-21"; // miércoles

Deno.test("hoyEnBogota usa la zona horaria de Colombia, no la del servidor", () => {
  // 05:00 UTC ya es medianoche del 21 en Bogotá (UTC−5).
  assertEquals(hoyEnBogota(new Date("2026-10-21T05:00:00Z")), "2026-10-21");
  // 02:00 UTC todavía es el 20 en Bogotá.
  assertEquals(hoyEnBogota(new Date("2026-10-21T02:00:00Z")), "2026-10-20");
});

Deno.test("inicioDelDiaBogota devuelve la medianoche local en ISO UTC", () => {
  assertEquals(
    inicioDelDiaBogota("2026-10-21"),
    "2026-10-21T05:00:00.000Z",
  );
});

Deno.test("rangoDePeriodo: hoy, ayer y este año", () => {
  assertEquals(rangoDePeriodo("hoy", HOY), { desde: HOY, hasta: HOY });
  assertEquals(rangoDePeriodo("ayer", HOY), {
    desde: "2026-10-20",
    hasta: "2026-10-20",
  });
  assertEquals(rangoDePeriodo("este_anio", HOY), {
    desde: "2026-01-01",
    hasta: HOY,
  });
});

Deno.test("rangoDePeriodo: semanas (lunes a domingo)", () => {
  assertEquals(rangoDePeriodo("esta_semana", HOY), {
    desde: "2026-10-19",
    hasta: "2026-10-21",
  });
  assertEquals(rangoDePeriodo("semana_pasada", HOY), {
    desde: "2026-10-12",
    hasta: "2026-10-18",
  });
});

Deno.test("rangoDePeriodo: mes actual y mes pasado completos", () => {
  assertEquals(rangoDePeriodo("este_mes", HOY), {
    desde: "2026-10-01",
    hasta: HOY,
  });
  assertEquals(rangoDePeriodo("mes_pasado", HOY), {
    desde: "2026-09-01",
    hasta: "2026-09-30",
  });
});

Deno.test("rangoDePeriodo: mes pasado cruza el año", () => {
  assertEquals(rangoDePeriodo("mes_pasado", "2026-01-15"), {
    desde: "2025-12-01",
    hasta: "2025-12-31",
  });
});

Deno.test("periodoDe reconoce las expresiones típicas", () => {
  assertEquals(periodoDe("¿cuánto gasté esta semana?"), "esta_semana");
  assertEquals(periodoDe("y la semana pasada"), "semana_pasada");
  assertEquals(periodoDe("cuánto llevo hoy"), "hoy");
  assertEquals(periodoDe("lo de ayer"), "ayer");
  assertEquals(periodoDe("el mes pasado"), "mes_pasado");
  assertEquals(periodoDe("cuánto llevo este año"), "este_anio");
  assertEquals(periodoDe("cuánto llevo este mes"), "este_mes");
});

Deno.test("periodoDe usa 'este mes' por defecto", () => {
  assertEquals(periodoDe("cuánto llevo gastado"), "este_mes");
});

Deno.test("mes pasado tiene prioridad sobre 'mes'", () => {
  assertEquals(periodoDe("el mes pasado gasté más"), "mes_pasado");
});

Deno.test("interpretarTipo distingue ingresos de egresos", () => {
  const tipo = (mensaje: string) => interpretarTipo(normalizar(mensaje));
  assertEquals(tipo("cuánto gané este mes"), "ingreso");
  assertEquals(tipo("cuánto recibí"), "ingreso");
  assertEquals(tipo("me pagaron la semana pasada"), "ingreso");
  assertEquals(tipo("me entró plata"), "ingreso");
  assertEquals(tipo("cuánto gasté hoy"), "egreso");
  assertEquals(tipo("en qué se me fue la plata"), "egreso");
});

Deno.test("aritmética de fechas", () => {
  assertEquals(lunesDeSemana("2026-10-21"), "2026-10-19");
  assertEquals(lunesDeSemana("2026-10-19"), "2026-10-19");
  assertEquals(lunesDeSemana("2026-10-25"), "2026-10-19"); // domingo
  assertEquals(sumarDias("2026-10-31", 1), "2026-11-01");
  assertEquals(sumarDias("2026-01-01", -1), "2025-12-31");
  assertEquals(mesAnterior("2026-01"), "2025-12");
  assertEquals(mesAnterior("2026-10"), "2026-09");
  assertEquals(ultimoDiaDeMes("2026-02"), "2026-02-28");
  assertEquals(ultimoDiaDeMes("2024-02"), "2024-02-29");
});

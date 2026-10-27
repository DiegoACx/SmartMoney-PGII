// ============================================================================
// Pruebas de plan.ts  (deno test)
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import {
  PASO_AUTH,
  PLAN_BORRADO,
  authEsUltimoPaso,
  ordenDeBorrado,
  posicionDe,
  precedeA,
} from "./plan.ts";

Deno.test("educacion_progreso se borra antes que categorias", () => {
  assertEquals(precedeA("educacion_progreso", "categorias"), true);
});

Deno.test("transacciones se borra antes que categorias (RESTRICT de la FK)", () => {
  assertEquals(precedeA("transacciones", "categorias"), true);
});

Deno.test("aportes_meta se borra antes que metas_ahorro", () => {
  assertEquals(precedeA("aportes_meta", "metas_ahorro"), true);
});

Deno.test("usuarios se borra antes del borrado en Auth", () => {
  assertEquals(precedeA("usuarios", PASO_AUTH), true);
});

Deno.test("el borrado en Auth es el último paso", () => {
  assertEquals(authEsUltimoPaso(), true);
  assertEquals(ordenDeBorrado()[ordenDeBorrado().length - 1], PASO_AUTH);
  assertEquals(posicionDe(PASO_AUTH), ordenDeBorrado().length - 1);
});

Deno.test("categorias solo borra las filas propias y por usuario_id", () => {
  const categorias = PLAN_BORRADO.find((paso) => paso.tabla === "categorias");
  assertEquals(categorias?.soloPropias, true);
  assertEquals(categorias?.columna, "usuario_id");
});

Deno.test("cada tabla aparece una sola vez, filtrada por columna, y usuarios cierra la lista", () => {
  const tablas = PLAN_BORRADO.map((paso) => paso.tabla);
  assertEquals(new Set(tablas).size, tablas.length);
  assertEquals(tablas[tablas.length - 1], "usuarios");
  for (const paso of PLAN_BORRADO) {
    assertEquals(paso.columna.length > 0, true);
    assertEquals(ordenDeBorrado().includes(paso.tabla), true);
  }
});

Deno.test("el plan cubre las tablas con columna de usuario", () => {
  const esperadas = [
    "educacion_progreso",
    "transacciones",
    "aportes_meta",
    "metas_ahorro",
    "mensajes_ia",
    "recomendaciones",
    "hallazgos",
    "preferencias_recomendacion",
    "linea_base_usuario",
    "categorias",
    "usuarios",
  ];
  assertEquals(PLAN_BORRADO.map((paso) => paso.tabla), esperadas);
});

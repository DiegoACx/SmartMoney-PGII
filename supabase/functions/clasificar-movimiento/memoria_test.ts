// ============================================================================
// SmartMoney · Clasificador de movimientos · Pruebas de la memoria por usuario
// ----------------------------------------------------------------------------
// Ejecutar:  deno test supabase/functions/clasificar-movimiento/memoria_test.ts
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import {
  buscarEnMemoria,
  type EgresoPrevio,
  VERSION_MEMORIA,
} from "./memoria.ts";

const OBLIGACIONES = "cat-obligaciones";
const ENTRETENIMIENTO = "cat-entretenimiento";

function egreso(
  descripcion: string | null,
  categoria_id: string | null,
  grupo_id: number | null = 13,
  categoria_nombre: string | null = "Obligaciones y transferencias",
): EgresoPrevio {
  return { descripcion, categoria_id, categoria_nombre, grupo_id };
}

Deno.test("memoria: recuerda la categoría elegida para la misma descripción", () => {
  const historial = [egreso("gym", OBLIGACIONES)];
  assertEquals(buscarEnMemoria("gym", historial), {
    categoria_id: OBLIGACIONES,
    categoria_nombre: "Obligaciones y transferencias",
    grupo_id: 13,
  });
});

Deno.test("memoria: ignora mayúsculas, tildes, puntuación y espacios", () => {
  const historial = [egreso("  Mensualidad   GYM. ", OBLIGACIONES)];
  assertEquals(
    buscarEnMemoria("mensualidad gym", historial)?.categoria_id,
    OBLIGACIONES,
  );
  const conTilde = [egreso("Gimnasio Bodytech", OBLIGACIONES)];
  assertEquals(
    buscarEnMemoria("gimnásio bodytech", conTilde)?.categoria_id,
    OBLIGACIONES,
  );
});

Deno.test("memoria: usa el egreso más reciente (el historial viene ordenado)", () => {
  const historial = [
    egreso("gym", ENTRETENIMIENTO, 9, "Entretenimiento"),
    egreso("gym", OBLIGACIONES),
  ];
  assertEquals(buscarEnMemoria("Gym", historial)?.categoria_id, ENTRETENIMIENTO);
});

Deno.test("memoria: solo coincidencia exacta, no parcial", () => {
  const historial = [egreso("gym", OBLIGACIONES)];
  assertEquals(buscarEnMemoria("mensualidad gym", historial), null);
  assertEquals(buscarEnMemoria("gy", historial), null);
});

Deno.test("memoria: sin historial o descripción vacía devuelve null", () => {
  assertEquals(buscarEnMemoria("gym", []), null);
  assertEquals(buscarEnMemoria("¡¡ ..", [egreso("..", OBLIGACIONES)]), null);
});

Deno.test("memoria: salta egresos sin categoría, sin descripción o sin grupo", () => {
  const historial = [
    egreso("gym", null),
    egreso(null, OBLIGACIONES),
    egreso("gym", "cat-sin-grupo", null),
    egreso("gym", ENTRETENIMIENTO, 9, "Entretenimiento"),
  ];
  assertEquals(buscarEnMemoria("gym", historial)?.categoria_id, ENTRETENIMIENTO);
});

Deno.test("memoria: la versión distingue estas sugerencias del modelo", () => {
  assertEquals(VERSION_MEMORIA, "memoria-usuario-v1");
});

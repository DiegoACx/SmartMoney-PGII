// ============================================================================
// Pruebas de conocimiento.ts  (deno test)
// ----------------------------------------------------------------------------
// Recuperación por similitud de trigramas contra el glosario y las lecciones.
// Sin red ni Supabase: las lecciones se pasan ya leídas.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  buscarConocimiento,
  buscarGlosario,
  buscarLeccion,
  sugerirConceptos,
  UMBRAL_GLOSARIO,
  UMBRAL_LECCION,
} from "./conocimiento.ts";
import type { FilaLeccion } from "./repositorio.ts";

Deno.test("recuperación: 'que es un cdt' encuentra la entrada del CDT", () => {
  const coincidencia = buscarGlosario("que es un cdt");

  assert(coincidencia !== null);
  assertEquals(coincidencia.entrada.id, "cdt");
  assert(coincidencia.puntaje >= UMBRAL_GLOSARIO);
});

Deno.test("recuperación: 'tasa efectiva anual' encuentra esa entrada", () => {
  const coincidencia = buscarGlosario("que es la tasa efectiva anual");

  assert(coincidencia !== null);
  assertEquals(coincidencia.entrada.id, "tasa-efectiva-anual");
  assert(coincidencia.puntaje >= UMBRAL_GLOSARIO);
});

Deno.test("recuperación: '4x1000' encuentra el GMF y la cuenta exenta", () => {
  const coincidencia = buscarGlosario("que es el 4x1000");

  assert(coincidencia !== null);
  assertEquals(coincidencia.entrada.id, "gmf-cuenta-exenta");
  assert(coincidencia.puntaje >= UMBRAL_GLOSARIO);
});

Deno.test("recuperación: 'que es datacredito' encuentra el historial crediticio", () => {
  const coincidencia = buscarGlosario("que es datacredito");

  assert(coincidencia !== null);
  assertEquals(coincidencia.entrada.id, "historial-crediticio");
  assert(coincidencia.puntaje >= UMBRAL_GLOSARIO);
});

Deno.test("recuperación: un término inexistente no supera el umbral", () => {
  assertEquals(buscarGlosario("que es un chuquimbo cuantico"), null);
  assertEquals(buscarLeccion("que es un chuquimbo cuantico", []), null);
});

Deno.test("recuperación: encuentra la lección más parecida al mensaje", () => {
  const lecciones: FilaLeccion[] = [
    {
      id: "e12",
      titulo: "Separar la plata en sobres",
      contenido:
        "Separar la plata en sobres te ayuda a no gastar de más. Puedes separar la plata en sobres para la comida, el transporte y los gustos.",
    },
    {
      id: "e13",
      titulo: "Pagar deudas caras",
      contenido:
        "Empieza por la deuda con la tasa más alta y paga más del mínimo cada mes.",
    },
  ];

  const coincidencia = buscarLeccion("como separar la plata en sobres", lecciones);

  assert(coincidencia !== null);
  assertEquals(coincidencia.leccion.id, "e12");
  assert(coincidencia.puntaje >= UMBRAL_LECCION);
});

Deno.test("recuperación: un mensaje puede coincidir con glosario y lección a la vez", () => {
  const lecciones: FilaLeccion[] = [{
    id: "e20",
    titulo: "Presupuesto mensual",
    contenido:
      "Un presupuesto es un plan para repartir tu plata entre gastos, ahorro y gustos. Sirve para decidir antes de gastar.",
  }];

  const coincidencia = buscarConocimiento("que es un presupuesto", lecciones);

  assert(coincidencia.glosario !== null);
  assertEquals(coincidencia.glosario.entrada.id, "presupuesto");
  assert(coincidencia.leccion !== null);
  assertEquals(coincidencia.leccion.leccion.id, "e20");
});

Deno.test("recuperación: 'que es el bitcoin' no empareja con ninguna lección", () => {
  // El contenido habla de activos y de bitcoin, pero el TÍTULO no: si se
  // comparara contra el contenido, "que es el bitcoin" emparejaría con "Activos".
  const lecciones: FilaLeccion[] = [
    {
      id: "e30",
      titulo: "Activos",
      contenido:
        "Un activo es algo que te puede dar plata en el futuro. El bitcoin es un activo muy volátil, igual que las acciones.",
    },
    {
      id: "e20",
      titulo: "Presupuesto mensual",
      contenido: "Un presupuesto es un plan para repartir tu plata.",
    },
  ];

  assertEquals(buscarLeccion("que es el bitcoin", lecciones), null);
  assertEquals(buscarConocimiento("que es el bitcoin", lecciones).leccion, null);
});

Deno.test("recuperación: sin coincidencias sugiere tres conceptos del glosario", () => {
  assertEquals(buscarConocimiento("que es un chuquimbo cuantico", []), {
    glosario: null,
    leccion: null,
  });

  const sugeridos = sugerirConceptos();
  assertEquals(sugeridos.length, 3);
  assertEquals(sugeridos.map((entrada) => entrada.id), [
    "fondo-emergencia",
    "interes-compuesto",
    "presupuesto",
  ]);
});

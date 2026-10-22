// ============================================================================
// Pruebas de detectores.ts  (deno test)
// Cada detector tiene un caso que dispara y un caso que no.
// ============================================================================

import { assertAlmostEquals, assertEquals } from "jsr:@std/assert";

import {
  type EscalonCatalogo,
  type HallazgoBase,
  type NivelCatalogo,
  cadenaEscalones,
  detectarAporteMeta,
  detectarGastoAnomalo,
  detectarLeccionSugerida,
  detectarLogro,
  detectarRiesgoFinDeMes,
  detectarSobregastoCategoria,
  estaDesbloqueado,
} from "./detectores.ts";
import type {
  LineaBaseCategoria,
  LineaBaseGrupo,
  TransaccionBase,
} from "./estadistica.ts";

const INGRESO = 4_000_000; // 10 % = 400.000 (unidad de impacto)

function egreso(
  fecha: string,
  monto: number,
  categoriaId = "cat-1",
  grupoId: number | null = 1,
): TransaccionBase {
  return {
    id: `t-${fecha}-${monto}`,
    categoria_id: categoriaId,
    grupo_id: grupoId,
    tipo: "egreso",
    monto,
    fecha,
    es_gasto_trabajo: false,
  };
}

function lineaGrupo(
  parcial: Partial<LineaBaseGrupo> & { grupo_id: number },
): LineaBaseGrupo {
  return {
    nombre: "Mercado",
    proporcion_referencia: 13.2,
    mediana: 0,
    n: 0,
    p: 0.5,
    referencia_semanal: 0,
    normal_semanal: null,
    normal_mensual: null,
    ...parcial,
  };
}

function lineaCategoria(
  parcial: Partial<LineaBaseCategoria> & { categoria_id: string },
): LineaBaseCategoria {
  return { mediana: 0, mad: 0, n_semanas: 0, ...parcial };
}

/** Hallazgo de sobregasto mínimo, para alimentar el detector de lecciones. */
function sobregasto(grupoId: number, severidad: number): HallazgoBase {
  return {
    tipo: "sobregasto_categoria",
    severidad,
    impacto: 0.8,
    p: 0.5,
    objetivo: `grupo:${grupoId}`,
    datos: { grupo_id: grupoId, nombre_grupo: "Mercado" },
  };
}

const ESCALONES: EscalonCatalogo[] = [
  { id: "e1", nivel_id: "n1", orden: 1, titulo: "Lección 1", tipo: "leccion", disponible: true },
  { id: "e2", nivel_id: "n1", orden: 2, titulo: "Evaluación 1", tipo: "evaluacion", disponible: true },
  { id: "e3", nivel_id: "n2", orden: 1, titulo: "Lección 3", tipo: "leccion", disponible: true },
  { id: "e4", nivel_id: "n2", orden: 2, titulo: "Lección oculta", tipo: "leccion", disponible: false },
];
const NIVELES: NivelCatalogo[] = [
  { id: "n2", orden: 2 },
  { id: "n1", orden: 1 },
];

// --- a) sobregasto_categoria -------------------------------------------------

Deno.test("sobregasto dispara cuando la proyección supera 1,20 × normal", () => {
  const hallazgos = detectarSobregastoCategoria({
    hoy: "2026-10-21", // día 21 de 31
    ingresoMensual: INGRESO,
    lineasBaseGrupos: [
      lineaGrupo({ grupo_id: 1, n: 3, normal_mensual: 1_000_000 }),
    ],
    egresosMesActual: [egreso("2026-10-10", 900_000)],
  });

  assertEquals(hallazgos.length, 1);
  const hallazgo = hallazgos[0];
  assertEquals(hallazgo.tipo, "sobregasto_categoria");
  assertEquals(hallazgo.objetivo, "grupo:1");
  assertAlmostEquals(
    Number(hallazgo.datos.proyeccion),
    (900_000 / 21) * 31,
    1e-6,
  );
  assertAlmostEquals(hallazgo.severidad, (900_000 / 21) * 31 / 1_000_000 - 1, 1e-9);
  assertAlmostEquals(
    hallazgo.impacto,
    (((900_000 / 21) * 31) - 1_000_000) / (0.1 * INGRESO),
    1e-9,
  );
});

Deno.test("sobregasto no dispara: proyección baja o mes muy nuevo", () => {
  const linea = lineaGrupo({ grupo_id: 1, n: 3, normal_mensual: 1_000_000 });

  assertEquals(
    detectarSobregastoCategoria({
      hoy: "2026-10-21",
      ingresoMensual: INGRESO,
      lineasBaseGrupos: [linea],
      egresosMesActual: [egreso("2026-10-10", 400_000)],
    }).length,
    0,
  );

  // Día 5 del mes: todavía no se evalúa
  assertEquals(
    detectarSobregastoCategoria({
      hoy: "2026-10-05",
      ingresoMensual: INGRESO,
      lineasBaseGrupos: [linea],
      egresosMesActual: [egreso("2026-10-01", 5_000_000)],
    }).length,
    0,
  );

  // Sin normal_mensual no hay contra qué comparar
  assertEquals(
    detectarSobregastoCategoria({
      hoy: "2026-10-21",
      ingresoMensual: INGRESO,
      lineasBaseGrupos: [lineaGrupo({ grupo_id: 1, normal_mensual: null })],
      egresosMesActual: [egreso("2026-10-01", 5_000_000)],
    }).length,
    0,
  );
});

// --- b) gasto_anomalo --------------------------------------------------------

Deno.test("gasto anómalo dispara con z robusto > 3", () => {
  const hallazgos = detectarGastoAnomalo({
    ingresoMensual: INGRESO,
    egresosUltimos7Dias: [egreso("2026-10-20", 300_000)],
    lineasBaseCategorias: [
      lineaCategoria({
        categoria_id: "cat-1",
        mediana: 200_000,
        mad: 20_000,
        n_semanas: 6,
      }),
    ],
    nombresCategorias: new Map([["cat-1", "Mercado"]]),
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].tipo, "gasto_anomalo");
  assertEquals(hallazgos[0].datos.transaccion_id, "t-2026-10-20-300000");
  assertAlmostEquals(hallazgos[0].datos.z as number, 100_000 / 29_652, 1e-6);
  assertAlmostEquals(hallazgos[0].severidad, (100_000 / 29_652) / 6, 1e-9);
  assertAlmostEquals(hallazgos[0].impacto, 300_000 / (0.1 * INGRESO), 1e-9);
});

Deno.test("gasto anómalo no dispara: z bajo, categoría sin historial o MAD = 0", () => {
  const base = lineaCategoria({
    categoria_id: "cat-1",
    mediana: 200_000,
    mad: 20_000,
    n_semanas: 6,
  });

  // z = 1,69
  assertEquals(
    detectarGastoAnomalo({
      ingresoMensual: INGRESO,
      egresosUltimos7Dias: [egreso("2026-10-20", 250_000)],
      lineasBaseCategorias: [base],
      nombresCategorias: new Map(),
    }).length,
    0,
  );

  // n < MIN_SEMANAS_ANOMALIA
  assertEquals(
    detectarGastoAnomalo({
      ingresoMensual: INGRESO,
      egresosUltimos7Dias: [egreso("2026-10-20", 5_000_000)],
      lineasBaseCategorias: [{ ...base, n_semanas: 3 }],
      nombresCategorias: new Map(),
    }).length,
    0,
  );

  // MAD = 0 y el monto no supera 3 × mediana
  assertEquals(
    detectarGastoAnomalo({
      ingresoMensual: INGRESO,
      egresosUltimos7Dias: [egreso("2026-10-20", 250_000)],
      lineasBaseCategorias: [{ ...base, mad: 0 }],
      nombresCategorias: new Map(),
    }).length,
    0,
  );
});

Deno.test("gasto anómalo con MAD = 0 y monto > 3 × mediana toma z = 6", () => {
  const hallazgos = detectarGastoAnomalo({
    ingresoMensual: INGRESO,
    egresosUltimos7Dias: [egreso("2026-10-20", 400_000)],
    lineasBaseCategorias: [
      lineaCategoria({
        categoria_id: "cat-1",
        mediana: 100_000,
        mad: 0,
        n_semanas: 6,
      }),
    ],
    nombresCategorias: new Map(),
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].datos.z, 6);
  assertEquals(hallazgos[0].severidad, 1);
});

// --- c) aporte_meta ----------------------------------------------------------

Deno.test("aporte a meta dispara cuando el ritmo está por debajo del sugerido", () => {
  const hallazgos = detectarAporteMeta({
    hoy: "2026-10-21",
    ingresoMensual: INGRESO,
    metas: [{
      id: "meta-1",
      nombre: "Viaje",
      monto_objetivo: 1_200_000,
      monto_actual: 200_000,
      fecha_limite: "2027-01-19", // 90 días → 3 meses
    }],
    aportesPorMeta: new Map([["meta-1", 0]]),
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].objetivo, "meta:meta-1");
  assertEquals(hallazgos[0].datos.meses, 3);
  assertAlmostEquals(
    hallazgos[0].datos.aporte_sugerido as number,
    1_000_000 / 3,
    1e-6,
  );
  assertEquals(hallazgos[0].severidad, 1);
  assertAlmostEquals(
    hallazgos[0].impacto,
    (1_000_000 / 3) / (0.1 * INGRESO),
    1e-9,
  );
});

Deno.test("aporte a meta no dispara: ritmo suficiente, meta cumplida o fecha vencida", () => {
  const meta = {
    id: "meta-1",
    nombre: "Viaje",
    monto_objetivo: 1_200_000,
    monto_actual: 200_000,
    fecha_limite: "2027-01-19",
  };

  assertEquals(
    detectarAporteMeta({
      hoy: "2026-10-21",
      ingresoMensual: INGRESO,
      metas: [meta],
      aportesPorMeta: new Map([["meta-1", 400_000]]),
    }).length,
    0,
  );

  assertEquals(
    detectarAporteMeta({
      hoy: "2026-10-21",
      ingresoMensual: INGRESO,
      metas: [{ ...meta, monto_actual: 1_300_000 }],
      aportesPorMeta: new Map(),
    }).length,
    0,
  );

  assertEquals(
    detectarAporteMeta({
      hoy: "2026-10-21",
      ingresoMensual: INGRESO,
      metas: [{ ...meta, fecha_limite: "2026-10-01" }],
      aportesPorMeta: new Map(),
    }).length,
    0,
  );
});

// --- d) leccion_sugerida -----------------------------------------------------

Deno.test("cadenaEscalones ordena por nivel y luego por orden", () => {
  assertEquals(cadenaEscalones(NIVELES, ESCALONES).map((e) => e.id), [
    "e1",
    "e2",
    "e3",
    "e4",
  ]);
});

Deno.test("estaDesbloqueado: el primero siempre, los demás tras el anterior", () => {
  const cadena = cadenaEscalones(NIVELES, ESCALONES);
  assertEquals(estaDesbloqueado(0, cadena, new Set()), true);
  assertEquals(estaDesbloqueado(1, cadena, new Set()), false);
  assertEquals(estaDesbloqueado(1, cadena, new Set(["e1"])), true);
  assertEquals(estaDesbloqueado(2, cadena, new Set(["e1"])), false);
  assertEquals(estaDesbloqueado(2, cadena, new Set(["e1", "e2"])), true);
});

Deno.test("lección sugerida: motivo tema_relacionado elige la del grupo saltando ids inválidos", () => {
  const hallazgos = detectarLeccionSugerida({
    sobregastos: [sobregasto(7, 1)],
    niveles: NIVELES,
    escalones: ESCALONES,
    completados: new Set(["e1", "e2"]), // e3 queda desbloqueada
    mapaLecciones: { 7: ["e9", "e3"] }, // e9 no existe
  });

  assertEquals(hallazgos.length, 1);
  const hallazgo = hallazgos[0];
  assertEquals(hallazgo.tipo, "leccion_sugerida");
  assertEquals(hallazgo.objetivo, "grupo:7");
  assertEquals(hallazgo.datos.escalon_id, "e3");
  assertEquals(hallazgo.datos.titulo, "Lección 3");
  assertEquals(hallazgo.datos.grupo_id, 7);
  assertEquals(hallazgo.datos.nombre_grupo, "Mercado");
  assertEquals(hallazgo.datos.motivo, "tema_relacionado");
  assertAlmostEquals(hallazgo.severidad, 0.6); // 0,6 × 1
  assertEquals(hallazgo.impacto, 0.5);
});

Deno.test("lección sugerida: motivo siguiente_en_ruta cuando ninguna del grupo sirve", () => {
  const hallazgos = detectarLeccionSugerida({
    sobregastos: [sobregasto(9, 1)],
    niveles: NIVELES,
    escalones: ESCALONES,
    completados: new Set(["e1", "e2"]),
    mapaLecciones: { 9: ["e4"] }, // e4 no está disponible
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].datos.motivo, "siguiente_en_ruta");
  assertEquals(hallazgos[0].datos.escalon_id, "e3"); // próxima de la ruta
  assertEquals(hallazgos[0].datos.titulo, "Lección 3");
  assertEquals(hallazgos[0].datos.grupo_id, 9);
  assertAlmostEquals(hallazgos[0].severidad, 0.3); // 0,3 × 1
});

Deno.test("lección sugerida: todas las lecciones válidas completadas no generan hallazgo", () => {
  assertEquals(
    detectarLeccionSugerida({
      sobregastos: [sobregasto(7, 1)],
      niveles: NIVELES,
      escalones: ESCALONES,
      completados: new Set(["e1", "e2", "e3", "e4"]),
      mapaLecciones: { 7: ["e1", "e3"] },
    }).length,
    0,
  );
});

Deno.test("lección sugerida: las evaluaciones cuentan para la cadena pero no se sugieren", () => {
  // e2 es evaluación, desbloqueada y sin completar: no se sugiere, y sin
  // completarla e3 sigue bloqueada → no hay hallazgo.
  assertEquals(
    detectarLeccionSugerida({
      sobregastos: [sobregasto(7, 1)],
      niveles: NIVELES,
      escalones: ESCALONES,
      completados: new Set(["e1"]),
      mapaLecciones: { 7: ["e2", "e3"] },
    }).length,
    0,
  );
});

Deno.test("lección sugerida: un escalón 'Próximamente' no se sugiere", () => {
  const escalones: EscalonCatalogo[] = [{
    id: "p1",
    nivel_id: "n1",
    orden: 1,
    titulo: "Próximamente",
    tipo: "leccion",
    disponible: true,
  }];

  assertEquals(
    detectarLeccionSugerida({
      sobregastos: [sobregasto(7, 1)],
      niveles: [{ id: "n1", orden: 1 }],
      escalones,
      completados: new Set(),
      mapaLecciones: { 7: ["p1"] },
    }).length,
    0,
  );
});

Deno.test("lección sugerida: el respaldo de ruta se emite una sola vez", () => {
  const hallazgos = detectarLeccionSugerida({
    sobregastos: [sobregasto(7, 1), sobregasto(9, 1)],
    niveles: NIVELES,
    escalones: ESCALONES,
    completados: new Set(["e1", "e2"]),
    mapaLecciones: { 7: ["e4"], 9: ["e4"] }, // ambos caen al respaldo
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].datos.motivo, "siguiente_en_ruta");
  assertEquals(hallazgos[0].datos.grupo_id, 7);
});

// --- e) logro ----------------------------------------------------------------

Deno.test("logro dispara cuando el gasto del mes quedó bajo el 90 % del normal", () => {
  const hallazgos = detectarLogro({
    mes: "2026-09",
    ingresoMensual: INGRESO,
    lineasBaseGrupos: [
      lineaGrupo({ grupo_id: 1, n: 8, p: 2 / 3, normal_mensual: 1_000_000 }),
    ],
    egresosMes: [
      egreso("2026-09-10", 500_000),
      egreso("2026-09-20", 300_000),
    ],
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].tipo, "logro");
  assertEquals(hallazgos[0].datos.mes, "2026-09");
  assertAlmostEquals(hallazgos[0].severidad, (1 - 0.8) / 0.3, 1e-9);
  assertAlmostEquals(hallazgos[0].impacto, 200_000 / (0.1 * INGRESO), 1e-9);
});

Deno.test("logro no dispara: gasto alto, poco historial, grupo 13 o poca relevancia", () => {
  const mes = "2026-09";
  const egresosAltos = [egreso("2026-09-10", 950_000)];

  assertEquals(
    detectarLogro({
      mes,
      ingresoMensual: INGRESO,
      lineasBaseGrupos: [
        lineaGrupo({ grupo_id: 1, n: 8, normal_mensual: 1_000_000 }),
      ],
      egresosMes: egresosAltos,
    }).length,
    0,
  );

  // n < K
  assertEquals(
    detectarLogro({
      mes,
      ingresoMensual: INGRESO,
      lineasBaseGrupos: [
        lineaGrupo({ grupo_id: 1, n: 2, normal_mensual: 1_000_000 }),
      ],
      egresosMes: [egreso("2026-09-10", 100_000)],
    }).length,
    0,
  );

  // grupo 13 queda fuera
  assertEquals(
    detectarLogro({
      mes,
      ingresoMensual: INGRESO,
      lineasBaseGrupos: [
        lineaGrupo({ grupo_id: 13, n: 8, normal_mensual: 1_000_000 }),
      ],
      egresosMes: [egreso("2026-09-10", 100_000, "cat-1", 13)],
    }).length,
    0,
  );

  // normal_mensual por debajo del 2 % del ingreso: no vale la pena contarlo
  assertEquals(
    detectarLogro({
      mes,
      ingresoMensual: INGRESO,
      lineasBaseGrupos: [
        lineaGrupo({ grupo_id: 1, n: 8, normal_mensual: 50_000 }),
      ],
      egresosMes: [egreso("2026-09-10", 10_000)],
    }).length,
    0,
  );
});

// --- f) riesgo_fin_de_mes ----------------------------------------------------

Deno.test("riesgo de fin de mes dispara cuando el ritmo supera el saldo", () => {
  const hallazgos = detectarRiesgoFinDeMes({
    hoy: "2026-10-21", // día 21 de 31 → quedan 10
    ingresoMensual: INGRESO,
    ingresosMes: [{
      ...egreso("2026-10-01", 4_000_000),
      tipo: "ingreso",
      categoria_id: "cat-ingreso",
      grupo_id: null,
    }],
    egresosMes: [egreso("2026-10-10", 3_200_000)],
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].tipo, "riesgo_fin_de_mes");
  assertEquals(hallazgos[0].severidad, 1);
  // faltante = 152.380,95 × 10 − 800.000 = 723.809,52 → impacto topado en 1
  assertAlmostEquals(hallazgos[0].datos.faltante as number, 723_809.52, 1e-2);
  assertEquals(hallazgos[0].impacto, 1);
});

Deno.test("riesgo de fin de mes no dispara con saldo holgado", () => {
  assertEquals(
    detectarRiesgoFinDeMes({
      hoy: "2026-10-21",
      ingresoMensual: INGRESO,
      ingresosMes: [{
        ...egreso("2026-10-01", 5_000_000),
        tipo: "ingreso",
        grupo_id: null,
      }],
      egresosMes: [egreso("2026-10-10", 1_000_000)],
    }).length,
    0,
  );
});

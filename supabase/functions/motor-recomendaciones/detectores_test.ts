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
import {
  type AgregadoClave,
  type LineaBaseGrupo,
  type TransaccionBase,
  agregarPorClave,
} from "./estadistica.ts";
import { K, SEMANAS_POR_MES, VENTANA_LOGRO } from "./config.ts";

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
    promedio_semanal: 0,
    n: 0,
    p: 0.5,
    referencia_semanal: 0,
    normal_semanal: null,
    normal_mensual: null,
    ...parcial,
  };
}

/** Movimientos de mercado alrededor de los 100.000, para el baseline por monto. */
function movimientos(montosPorFecha: [string, number][]): TransaccionBase[] {
  return montosPorFecha.map(([fecha, monto]) => egreso(fecha, monto));
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

Deno.test("gasto anómalo dispara con z robusto > 3 sobre los montos por movimiento", () => {
  const evaluado = egreso("2026-10-20", 300_000);
  const hallazgos = detectarGastoAnomalo({
    ingresoMensual: INGRESO,
    egresosUltimos7Dias: [evaluado],
    // mediana 200.000 y MAD 20.000 (el movimiento evaluado no entra al cálculo)
    movimientosPorCategoria: new Map([[
      "cat-1",
      [
        ...movimientos([
          ["2026-09-01", 160_000],
          ["2026-09-08", 180_000],
          ["2026-09-15", 200_000],
          ["2026-09-22", 200_000],
          ["2026-09-29", 220_000],
          ["2026-10-06", 240_000],
        ]),
        evaluado,
      ],
    ]]),
    nombresCategorias: new Map([["cat-1", "Mercado"]]),
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].tipo, "gasto_anomalo");
  assertEquals(hallazgos[0].datos.transaccion_id, "t-2026-10-20-300000");
  assertEquals(hallazgos[0].datos.mediana_monto, 200_000);
  assertEquals(hallazgos[0].datos.mad_monto, 20_000);
  assertEquals(hallazgos[0].datos.n_movimientos, 6);
  assertAlmostEquals(hallazgos[0].datos.z as number, 100_000 / 29_652, 1e-6);
  assertAlmostEquals(hallazgos[0].severidad, (100_000 / 29_652) / 6, 1e-9);
  assertAlmostEquals(hallazgos[0].impacto, 300_000 / (0.1 * INGRESO), 1e-9);
  // confianza = 0,5 + 0,5 × n_mov/(n_mov + 5) → p = 6/11
  assertAlmostEquals(hallazgos[0].p, 6 / 11, 1e-12);
});

Deno.test("gasto anómalo no dispara: z bajo, pocos movimientos o MAD = 0 sin exceso", () => {
  const previos: [string, number][] = [
    ["2026-09-01", 160_000],
    ["2026-09-08", 180_000],
    ["2026-09-15", 200_000],
    ["2026-09-22", 200_000],
    ["2026-09-29", 220_000],
    ["2026-10-06", 240_000],
  ];

  // z = 1,69
  assertEquals(
    detectarGastoAnomalo({
      ingresoMensual: INGRESO,
      egresosUltimos7Dias: [egreso("2026-10-20", 250_000)],
      movimientosPorCategoria: new Map([["cat-1", movimientos(previos)]]),
      nombresCategorias: new Map(),
    }).length,
    0,
  );

  // Menos de MIN_MOVIMIENTOS_ANOMALIA (5) movimientos previos
  assertEquals(
    detectarGastoAnomalo({
      ingresoMensual: INGRESO,
      egresosUltimos7Dias: [egreso("2026-10-20", 5_000_000)],
      movimientosPorCategoria: new Map([[
        "cat-1",
        movimientos([
          ["2026-09-01", 200_000],
          ["2026-09-08", 200_000],
          ["2026-09-15", 200_000],
          ["2026-09-22", 200_000],
          ["2026-10-20", 5_000_000], // solo el evaluado
        ]),
      ]]),
      nombresCategorias: new Map(),
    }).length,
    0,
  );

  // MAD = 0 y el monto no supera 3 × mediana
  assertEquals(
    detectarGastoAnomalo({
      ingresoMensual: INGRESO,
      egresosUltimos7Dias: [egreso("2026-10-20", 250_000)],
      movimientosPorCategoria: new Map([[
        "cat-1",
        movimientos([
          ["2026-09-01", 200_000],
          ["2026-09-08", 200_000],
          ["2026-09-15", 200_000],
          ["2026-09-22", 200_000],
          ["2026-09-29", 200_000],
        ]),
      ]]),
      nombresCategorias: new Map(),
    }).length,
    0,
  );
});

Deno.test("gasto anómalo no dispara nunca si la mediana de montos previos es 0", () => {
  const evaluado = egreso("2026-10-20", 500_000);
  assertEquals(
    detectarGastoAnomalo({
      ingresoMensual: INGRESO,
      egresosUltimos7Dias: [evaluado],
      // Devoluciones y montos en cero: mediana 0, MAD 0 → antes bastaba con
      // superar 3 × mediana (0) para marcarlo.
      movimientosPorCategoria: new Map([[
        "cat-1",
        [
          ...movimientos([
            ["2026-09-01", -150_000],
            ["2026-09-08", 0],
            ["2026-09-15", 0],
            ["2026-09-22", 0],
            ["2026-09-29", 0],
            ["2026-10-06", 0],
          ]),
          evaluado,
        ],
      ]]),
      nombresCategorias: new Map(),
    }).length,
    0,
  );
});

Deno.test("gasto anómalo dispara con un mercado de 500.000 frente a mercados de ~100.000", () => {
  const hallazgos = detectarGastoAnomalo({
    ingresoMensual: INGRESO,
    egresosUltimos7Dias: [egreso("2026-10-20", 500_000)],
    // mediana 100.000 y MAD 2.000 por movimiento
    movimientosPorCategoria: new Map([[
      "cat-1",
      movimientos([
        ["2026-09-01", 95_000],
        ["2026-09-08", 100_000],
        ["2026-09-15", 100_000],
        ["2026-09-22", 105_000],
        ["2026-09-29", 98_000],
        ["2026-10-06", 102_000],
      ]),
    ]]),
    nombresCategorias: new Map([["cat-1", "Mercado"]]),
  });

  assertEquals(hallazgos.length, 1);
  assertEquals(hallazgos[0].datos.mediana_monto, 100_000);
  assertEquals(hallazgos[0].datos.mad_monto, 2_000);
  assertEquals(hallazgos[0].datos.n_movimientos, 6);
  assertAlmostEquals(
    hallazgos[0].datos.z as number,
    400_000 / (1.4826 * 2_000),
    1e-6,
  );
  assertEquals(hallazgos[0].severidad, 1); // z muy por encima de SEVERIDAD_Z_MAX
});

Deno.test("gasto anómalo con MAD = 0 y monto > 3 × mediana toma z = 6", () => {
  const hallazgos = detectarGastoAnomalo({
    ingresoMensual: INGRESO,
    egresosUltimos7Dias: [egreso("2026-10-20", 400_000)],
    movimientosPorCategoria: new Map([[
      "cat-1",
      movimientos([
        ["2026-09-01", 100_000],
        ["2026-09-08", 100_000],
        ["2026-09-15", 100_000],
        ["2026-09-22", 100_000],
        ["2026-09-29", 100_000],
      ]),
    ]]),
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

/** Ocho semanas de mercado a 200.000, desde la semana del 2026-06-29. */
function ochoSemanasDeMercado(): TransaccionBase[] {
  const fechas = [
    "2026-06-29",
    "2026-07-06",
    "2026-07-13",
    "2026-07-20",
    "2026-07-27",
    "2026-08-03",
    "2026-08-10",
    "2026-08-17",
  ];
  return fechas.map((fecha) => egreso(fecha, 200_000));
}

/** Historial por grupo de 12 semanas (vacías las 4 primeras) hasta 2026-08-17. */
function historialDeGrupo(
  transacciones: TransaccionBase[],
): Map<string, AgregadoClave> {
  return agregarPorClave(
    transacciones,
    (t) => String(t.grupo_id),
    "2026-06-01",
    "2026-08-17",
  );
}

Deno.test("logro dispara cuando el gasto del mes queda bajo el 90 % de su promedio habitual", () => {
  const normalPersonal = 200_000 * SEMANAS_POR_MES; // 869.000
  const hallazgos = detectarLogro({
    mes: "2026-09",
    ingresoMensual: INGRESO,
    lineasBaseGrupos: [lineaGrupo({ grupo_id: 1 })],
    historialPorGrupo: historialDeGrupo(ochoSemanasDeMercado()),
    sobregastos: [],
    egresosMes: [
      egreso("2026-09-10", 400_000),
      egreso("2026-09-20", 300_000),
    ],
  });

  assertEquals(hallazgos.length, 1);
  const hallazgo = hallazgos[0];
  assertEquals(hallazgo.tipo, "logro");
  assertEquals(hallazgo.objetivo, "grupo:1");
  assertEquals(hallazgo.datos.mes, "2026-09");
  assertEquals(Number(hallazgo.datos.gasto_mes), 700_000);
  assertEquals(Number(hallazgo.datos.semanas_previas), 8);
  assertAlmostEquals(
    Number(hallazgo.datos.normal_personal_mensual),
    normalPersonal,
    1e-9,
  );
  assertAlmostEquals(
    Number(hallazgo.datos.ahorro_mes),
    normalPersonal - 700_000,
    1e-9,
  );
  // La confianza sale de p = n / (n + K) con las semanas previas al mes.
  assertAlmostEquals(hallazgo.p, 8 / (8 + K), 1e-9);
  assertAlmostEquals(
    hallazgo.severidad,
    (1 - 700_000 / normalPersonal) / VENTANA_LOGRO,
    1e-9,
  );
  assertAlmostEquals(
    hallazgo.impacto,
    (normalPersonal - 700_000) / (0.1 * INGRESO),
    1e-9,
  );
});

Deno.test("logro no dispara: gasto alto, poco historial, grupo 13 o poca relevancia", () => {
  const base = {
    mes: "2026-09",
    ingresoMensual: INGRESO,
    lineasBaseGrupos: [lineaGrupo({ grupo_id: 1 })],
  };

  // El gasto del mes supera el 90 % del promedio habitual.
  assertEquals(
    detectarLogro({
      ...base,
      historialPorGrupo: historialDeGrupo(ochoSemanasDeMercado()),
      sobregastos: [],
      egresosMes: [egreso("2026-09-10", 950_000)],
    }).length,
    0,
  );

  // Menos de K semanas de historial previo.
  assertEquals(
    detectarLogro({
      ...base,
      historialPorGrupo: historialDeGrupo([
        egreso("2026-08-10", 200_000),
        egreso("2026-08-17", 200_000),
      ]),
      sobregastos: [],
      egresosMes: [egreso("2026-09-10", 100_000)],
    }).length,
    0,
  );

  // El grupo 13 (obligaciones) queda fuera del logro.
  assertEquals(
    detectarLogro({
      ...base,
      lineasBaseGrupos: [lineaGrupo({ grupo_id: 13 })],
      historialPorGrupo: historialDeGrupo(
        ochoSemanasDeMercado().map((t) => ({ ...t, grupo_id: 13 })),
      ),
      sobregastos: [],
      egresosMes: [egreso("2026-09-10", 100_000, "cat-1", 13)],
    }).length,
    0,
  );

  // Promedio habitual por debajo del 2 % del ingreso: no vale la pena contarlo.
  assertEquals(
    detectarLogro({
      ...base,
      historialPorGrupo: historialDeGrupo(
        ochoSemanasDeMercado().map((t) => ({ ...t, monto: 1_000 })),
      ),
      sobregastos: [],
      egresosMes: [egreso("2026-09-10", 10_000)],
    }).length,
    0,
  );
});

Deno.test("logro no dispara si el grupo ya tiene sobregasto en la misma ejecución", () => {
  const parametros = {
    mes: "2026-09",
    ingresoMensual: INGRESO,
    lineasBaseGrupos: [lineaGrupo({ grupo_id: 1 })],
    historialPorGrupo: historialDeGrupo(ochoSemanasDeMercado()),
    egresosMes: [
      egreso("2026-09-10", 400_000),
      egreso("2026-09-20", 300_000),
    ],
  };

  // Sin sobregasto del grupo, el mismo mes sí genera logro.
  assertEquals(detectarLogro({ ...parametros, sobregastos: [] }).length, 1);

  // Con un sobregasto_categoria del grupo, el logro se descarta.
  assertEquals(
    detectarLogro({ ...parametros, sobregastos: [sobregasto(1, 0.5)] }).length,
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

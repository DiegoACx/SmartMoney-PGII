// ============================================================================
// Pruebas de estadistica.ts  (deno test)
// ============================================================================

import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert";

import {
  type TransaccionBase,
  agregarPorClave,
  calcularLineaBaseGrupos,
  diaDelMes,
  diasDelMes,
  diasEntre,
  lunesDeSemana,
  mad,
  mediana,
  medianaIngresoMensual,
  mesAnterior,
  normalMensual,
  normalSemanal,
  pesoPersonal,
  primeraSemanaConRegistros,
  referenciaSemanal,
  semanaISO,
  semanasEntre,
  sumarDias,
  zRobusto,
} from "./estadistica.ts";
import { K } from "./config.ts";

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

function ingreso(fecha: string, monto: number): TransaccionBase {
  return {
    id: `i-${fecha}-${monto}`,
    categoria_id: "cat-ingreso",
    grupo_id: null,
    tipo: "ingreso",
    monto,
    fecha,
    es_gasto_trabajo: false,
  };
}

// --- Estadística básica ------------------------------------------------------

Deno.test("mediana con cantidad impar, par y vacío", () => {
  assertEquals(mediana([3, 1, 2]), 2);
  assertEquals(mediana([4, 1, 3, 2]), 2.5);
  assertEquals(mediana([]), 0);
});

Deno.test("mad con caso conocido", () => {
  // [1,2,3,4,5] → mediana 3 → desviaciones [2,1,0,1,2] → mediana 1
  assertEquals(mad([1, 2, 3, 4, 5]), 1);
  assertEquals(mad([7, 7, 7]), 0);
});

Deno.test("zRobusto con MAD conocido y MAD = 0", () => {
  assertAlmostEquals(zRobusto(10, 10, 10), 0);
  assertAlmostEquals(zRobusto(24.826, 10, 10), 1);
  // MAD = 0 → escala indefinida: el detector aplica su propia regla
  assertEquals(zRobusto(1000, 10, 0), 0);
});

Deno.test("pesoPersonal con n = 1, 4 y 12 (K = 4)", () => {
  assertEquals(K, 4);
  assertAlmostEquals(pesoPersonal(1), 0.2);
  assertAlmostEquals(pesoPersonal(4), 0.5);
  assertAlmostEquals(pesoPersonal(12), 0.75);
  assertEquals(pesoPersonal(0), 0);
});

Deno.test("referencia, normal semanal y normal mensual", () => {
  const referencia = referenciaSemanal(4_000_000, 13.2);
  // 4.000.000 × 0,83 × 13,2 % / 4,345
  assertAlmostEquals(referencia, 100_860.7595, 1e-3);

  const p = 2 / 3; // 8 semanas con registros
  const normal = normalSemanal(p, 100_000, referencia);
  assert(normal > 100_000 && normal < referencia);
  assertAlmostEquals(normalMensual(normal), normal * 4.345);
});

// --- Fechas ------------------------------------------------------------------

Deno.test("utilidades de fecha", () => {
  assertEquals(lunesDeSemana("2026-10-21"), "2026-10-19"); // miércoles → lunes
  assertEquals(lunesDeSemana("2026-10-19"), "2026-10-19"); // lunes
  assertEquals(lunesDeSemana("2026-10-25"), "2026-10-19"); // domingo
  assertEquals(semanaISO("2026-10-21"), "2026-W43");
  assertEquals(sumarDias("2026-10-19", 7), "2026-10-26");
  assertEquals(diasEntre("2026-10-01", "2026-10-21"), 20);
  assertEquals(diaDelMes("2026-10-21"), 21);
  assertEquals(diasDelMes("2026-10-21"), 31);
  assertEquals(diasDelMes("2026-02-10"), 28);
  assertEquals(mesAnterior("2026-10-21"), "2026-09");
  assertEquals(mesAnterior("2026-01-15"), "2025-12");
  assertEquals(semanasEntre("2026-10-05", "2026-10-19"), [
    "2026-10-05",
    "2026-10-12",
    "2026-10-19",
  ]);
});

// --- Agregación semanal ------------------------------------------------------

Deno.test("agregarPorClave rellena con 0 las semanas sin gasto", () => {
  const transacciones = [
    egreso("2026-10-07", 100_000),
    egreso("2026-10-20", 50_000), // semana del 19
    egreso("2026-09-30", 999_999), // fuera de la ventana
  ];
  const agregados = agregarPorClave(
    transacciones,
    (t) => t.categoria_id,
    "2026-10-05",
    "2026-10-19",
  );

  const agregado = agregados.get("cat-1")!;
  assert(agregado !== undefined);
  assertEquals(agregado.serie, [100_000, 0, 50_000]);
  assertEquals(agregado.n, 2); // dos semanas con registros
  assertEquals(agregado.semanas[0].clave, "2026-W41");
  assertEquals(agregado.semanas[2].clave, "2026-W43");
  // mediana([100.000, 0, 50.000]) = 50.000 y MAD = 50.000
  assertEquals(agregado.mediana, 50_000);
  assertEquals(agregado.mad, 50_000);
});

Deno.test("agregarPorClave ignora claves nulas", () => {
  const agregados = agregarPorClave(
    [egreso("2026-10-07", 100_000, "cat-1", null)],
    (t) => (t.grupo_id === null ? null : String(t.grupo_id)),
    "2026-10-05",
    "2026-10-19",
  );
  assertEquals(agregados.size, 0);
});

Deno.test("primeraSemanaConRegistros devuelve el lunes del primer registro", () => {
  assertEquals(primeraSemanaConRegistros([]), null);
  assertEquals(
    primeraSemanaConRegistros([egreso("2026-10-07", 1), egreso("2026-09-01", 1)]),
    "2026-08-31",
  );
});

// --- Ingreso mensual ---------------------------------------------------------

Deno.test("ingreso mensual: mediana de los últimos 3 meses con ingresos", () => {
  assertEquals(medianaIngresoMensual([]), null);
  assertEquals(
    medianaIngresoMensual([
      ingreso("2026-08-01", 2_000_000),
      ingreso("2026-09-01", 4_000_000),
      ingreso("2026-10-01", 6_000_000),
    ]),
    4_000_000,
  );
  // Cuatro meses: solo entran los tres más recientes
  assertEquals(
    medianaIngresoMensual([
      ingreso("2026-07-01", 9_000_000),
      ingreso("2026-08-01", 2_000_000),
      ingreso("2026-09-01", 4_000_000),
      ingreso("2026-10-01", 6_000_000),
    ]),
    4_000_000,
  );
});

// --- Línea base --------------------------------------------------------------

Deno.test("línea base por grupo con y sin ingreso mensual", () => {
  const agregados = agregarPorClave(
    [
      egreso("2026-10-07", 100_000, "cat-1", 1),
      egreso("2026-10-14", 120_000, "cat-1", 1),
      egreso("2026-10-21", 140_000, "cat-1", 1),
    ],
    (t) => String(t.grupo_id),
    "2026-10-05",
    "2026-10-19",
  );
  const grupos = [
    {
      id: 1,
      nombre: "Mercado",
      proporcion_referencia: 13.2,
      incluir_en_referencia: true,
    },
    {
      id: 13,
      nombre: "Obligaciones y transferencias",
      proporcion_referencia: null,
      incluir_en_referencia: false,
    },
  ];

  const conIngreso = calcularLineaBaseGrupos({
    agregados,
    grupos,
    ingresoMensual: 4_000_000,
  });
  const lineaUno = conIngreso.find((linea) => linea.grupo_id === 1)!;
  assertEquals(lineaUno.n, 3); // las tres semanas de la ventana tienen gasto
  assertAlmostEquals(lineaUno.p, 3 / 7);
  assertAlmostEquals(lineaUno.referencia_semanal, 100_860.7595, 1e-3);
  assert(lineaUno.normal_semanal !== null);
  assertAlmostEquals(
    lineaUno.normal_mensual!,
    lineaUno.normal_semanal! * 4.345,
    1e-9,
  );

  const sinIngreso = calcularLineaBaseGrupos({
    agregados,
    grupos,
    ingresoMensual: null,
  });
  const lineaUnoSinIngreso = sinIngreso.find((linea) => linea.grupo_id === 1)!;
  // Sin ingreso solo hay normal si n ≥ K (aquí n = 3 < 4 → sin normal)
  assertEquals(lineaUnoSinIngreso.normal_semanal, null);
  assertEquals(lineaUnoSinIngreso.normal_mensual, null);
});

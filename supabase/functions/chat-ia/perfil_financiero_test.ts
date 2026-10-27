// ============================================================================
// Pruebas de perfil_financiero.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red ni Supabase: las funciones de cálculo son puras y
// `leerPerfilFinanciero` recibe un repositorio falso.
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import {
  calcularGastoPorGrupo,
  calcularIngresoMensual,
  calcularMetasPerfil,
  leerPerfilFinanciero,
  MESES_HISTORIAL,
  mediana,
  mesesCompletos,
  mesesEntre,
} from "./perfil_financiero.ts";
import type {
  FilaAporte,
  FilaCategoria,
  FilaMeta,
  FilaTransaccion,
  RepositorioChat,
} from "./repositorio.ts";

const AHORA = new Date("2026-10-21T15:00:00Z"); // 2026-10-21 en Bogotá
const HOY = "2026-10-21";

interface Llamada {
  desde: string;
  hasta: string;
  tipo: string | null;
}

interface OpcionesRepo {
  transacciones?: FilaTransaccion[];
  aportes?: FilaAporte[];
  metas?: FilaMeta[];
  categorias?: FilaCategoria[];
  llamadas?: Llamada[];
}

/** Repositorio falso: filtra por tipo y rango, y anota cada consulta. */
function repoFalso(opciones: OpcionesRepo = {}): RepositorioChat {
  const llamadas = opciones.llamadas ?? [];
  const transacciones = opciones.transacciones ?? [];
  const aportes = opciones.aportes ?? [];

  return {
    contarMensajesUsuario: () => Promise.resolve(0),
    ultimoMensajeAsistente: () => Promise.resolve(null),
    insertarMensaje: () => Promise.resolve(),
    leerTransacciones: (_usuarioId, desde, hasta, tipo) => {
      llamadas.push({ desde, hasta, tipo });
      return Promise.resolve(
        transacciones.filter((fila) =>
          fila.tipo === tipo && fila.fecha >= desde && fila.fecha <= hasta
        ),
      );
    },
    leerCategorias: () => Promise.resolve(opciones.categorias ?? []),
    leerMetasActivas: () => Promise.resolve(opciones.metas ?? []),
    leerAportes: (_usuarioId, desde, hasta) => {
      llamadas.push({ desde, hasta, tipo: null });
      return Promise.resolve(
        aportes.filter((fila) =>
          fila.fecha >= desde && fila.fecha <= hasta
        ),
      );
    },
    leerLeccionesValidas: () => Promise.resolve([]),
    leerHallazgosRecientes: () => Promise.resolve([]),
  };
}

function transaccion(
  fecha: string,
  monto: number,
  tipo: "ingreso" | "egreso" = "ingreso",
  categoriaId: string | null = null,
  esGastoTrabajo = false,
): FilaTransaccion {
  return {
    categoria_id: categoriaId,
    tipo,
    monto,
    fecha,
    es_gasto_trabajo: esGastoTrabajo,
  };
}

// --- Cálculos puros ----------------------------------------------------------

Deno.test("mediana: impar, par y sin datos", () => {
  assertEquals(mediana([]), 0);
  assertEquals(mediana([5]), 5);
  assertEquals(mediana([3, 1, 2]), 2);
  assertEquals(mediana([4, 1, 3, 2]), 2.5);
});

Deno.test("mesesEntre: meses completos entre dos fechas, nunca negativo", () => {
  assertEquals(mesesEntre("2026-10-21", "2027-04-30"), 6);
  assertEquals(mesesEntre("2026-10-21", "2026-12-31"), 2);
  assertEquals(mesesEntre("2026-10-21", "2026-11-05"), 0);
  assertEquals(mesesEntre("2026-10-21", "2026-10-21"), 0);
  assertEquals(mesesEntre("2026-10-21", "2026-01-01"), 0);
});

Deno.test("mesesCompletos: los meses calendario anteriores al actual", () => {
  assertEquals(MESES_HISTORIAL, 3);
  assertEquals(mesesCompletos(HOY), ["2026-07", "2026-08", "2026-09"]);
  assertEquals(mesesCompletos("2026-01-15"), ["2025-10", "2025-11", "2025-12"]);
});

Deno.test("ingreso mensual: mediana de los meses completos con ingreso", () => {
  const ingresos = [
    transaccion("2026-07-10", 2_000_000),
    transaccion("2026-07-25", 500_000),
    transaccion("2026-09-10", 3_000_000),
  ];
  assertEquals(
    calcularIngresoMensual(ingresos, [], ["2026-07", "2026-08", "2026-09"]),
    2_750_000, // jul 2.500.000 y sep 3.000.000 (ago no tiene ingresos)
  );
});

Deno.test("ingreso mensual: sin meses completos usa el mes actual", () => {
  assertEquals(
    calcularIngresoMensual(
      [],
      [transaccion("2026-10-03", 1_200_000)],
      ["2026-07", "2026-08", "2026-09"],
    ),
    1_200_000,
  );
});

Deno.test("ingreso mensual: sin ningún dato es null", () => {
  assertEquals(
    calcularIngresoMensual([], [], ["2026-07", "2026-08", "2026-09"]),
    null,
  );
});

Deno.test("gasto por grupo: promedio mensual e ignora sin categoría o sin grupo", () => {
  const egresos = [
    transaccion("2026-08-15", 600_000, "egreso", "c1"),
    transaccion("2026-09-10", 900_000, "egreso", "c2"),
    transaccion("2026-09-25", 900_000, "egreso", "c1"),
    transaccion("2026-09-26", 100_000, "egreso", null),
    transaccion("2026-09-27", 100_000, "egreso", "c3"),
  ];
  const grupos = new Map<string, number | null>([
    ["c1", 11],
    ["c2", 7],
    ["c3", null],
  ]);

  const promedio = calcularGastoPorGrupo(egresos, grupos);
  assertEquals(promedio.get(11), 500_000);
  assertEquals(promedio.get(7), 300_000);
  assertEquals(promedio.size, 2);
});

Deno.test("metas: falta, plazo, aporte necesario y ritmo reciente", () => {
  const metas: FilaMeta[] = [{
    id: "m1",
    nombre: "Viaje",
    monto_objetivo: 3_000_000,
    monto_actual: 1_200_000,
    fecha_limite: "2027-04-30",
    cumplida: false,
  }];
  const aportes: FilaAporte[] = [
    { meta_id: "m1", monto: 150_000, fecha: "2026-09-25" },
    { meta_id: "otra", monto: 999_999, fecha: "2026-09-25" },
  ];

  const [meta] = calcularMetasPerfil(metas, aportes, HOY);
  assertEquals(meta.nombre, "Viaje");
  assertEquals(meta.falta, 1_800_000);
  assertEquals(meta.meses_restantes, 6);
  assertEquals(meta.aporte_necesario_mes, 300_000);
  assertEquals(meta.ritmo_mes, 150_000);
  assertEquals(meta.meses_al_ritmo_actual, 12);
});

Deno.test("metas: sin fecha no hay aporte necesario y sin ritmo no hay meses", () => {
  const metas: FilaMeta[] = [{
    id: "m2",
    nombre: "Moto",
    monto_objetivo: 1_000_000,
    monto_actual: 400_000,
    fecha_limite: null,
    cumplida: false,
  }];

  const [meta] = calcularMetasPerfil(metas, [], HOY);
  assertEquals(meta.falta, 600_000);
  assertEquals(meta.meses_restantes, null);
  assertEquals(meta.aporte_necesario_mes, null);
  assertEquals(meta.ritmo_mes, 0);
  assertEquals(meta.meses_al_ritmo_actual, null);
});

// --- Lectura con el repositorio ----------------------------------------------

const TRANSACCIONES: FilaTransaccion[] = [
  transaccion("2026-07-10", 2_000_000, "ingreso", "c3"),
  transaccion("2026-08-10", 2_400_000, "ingreso", "c3"),
  transaccion("2026-09-10", 3_000_000, "ingreso", "c3"),
  transaccion("2026-08-15", 600_000, "egreso", "c1"),
  transaccion("2026-09-10", 900_000, "egreso", "c2", true),
  transaccion("2026-09-25", 900_000, "egreso", "c1"),
];

const APORTES: FilaAporte[] = [
  { meta_id: "m1", monto: 200_000, fecha: "2026-08-01" },
  { meta_id: "m1", monto: 400_000, fecha: "2026-09-01" },
  { meta_id: "m1", monto: 150_000, fecha: "2026-09-25" },
];

const METAS: FilaMeta[] = [{
  id: "m1",
  nombre: "Viaje",
  monto_objetivo: 3_000_000,
  monto_actual: 1_200_000,
  fecha_limite: "2027-04-30",
  cumplida: false,
}];

const CATEGORIAS: FilaCategoria[] = [
  { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
  { id: "c2", nombre: "Transporte", grupo_id: 7 },
  { id: "c3", nombre: "Salario", grupo_id: null },
];

Deno.test("perfil: reúne las cifras de la ventana de historial", async () => {
  const llamadas: Llamada[] = [];
  const perfil = await leerPerfilFinanciero(
    "usuario-1",
    repoFalso({
      transacciones: TRANSACCIONES,
      aportes: APORTES,
      metas: METAS,
      categorias: CATEGORIAS,
      llamadas,
    }),
    AHORA,
  );

  assertEquals(perfil.ingreso_mensual, 2_400_000);
  assertEquals(perfil.gasto_mensual, 800_000);
  assertEquals(perfil.gasto_trabajo_mensual, 300_000);
  assertEquals(perfil.excedente_mensual, 1_600_000);
  assertEquals(perfil.ahorro_mensual, 250_000);
  assertEquals(perfil.gasto_mensual_por_grupo.get(11), 500_000);
  assertEquals(perfil.gasto_mensual_por_grupo.get(7), 300_000);
  assertEquals(perfil.historial_insuficiente, false);

  assertEquals(perfil.metas.length, 1);
  assertEquals(perfil.metas[0].falta, 1_800_000);
  assertEquals(perfil.metas[0].meses_restantes, 6);
  assertEquals(perfil.metas[0].aporte_necesario_mes, 300_000);
  assertEquals(perfil.metas[0].ritmo_mes, 150_000);
  assertEquals(perfil.metas[0].meses_al_ritmo_actual, 12);

  // Ingresos de los 3 meses completos, el mes actual, y la ventana rodante de
  // 90 días (2026-07-23) para el gasto por grupo y el ahorro, más los 30 días
  // del ritmo.
  assertEquals(llamadas, [
    { desde: "2026-07-01", hasta: "2026-09-30", tipo: "ingreso" },
    { desde: "2026-10-01", hasta: "2026-10-21", tipo: "ingreso" },
    { desde: "2026-07-01", hasta: "2026-09-30", tipo: "egreso" },
    { desde: "2026-07-23", hasta: "2026-10-21", tipo: "egreso" },
    { desde: "2026-07-23", hasta: "2026-10-21", tipo: null },
    { desde: "2026-09-21", hasta: "2026-10-21", tipo: null },
  ]);
});

Deno.test("perfil: el gasto por grupo incluye los egresos del mes en curso", async () => {
  const perfil = await leerPerfilFinanciero(
    "usuario-1",
    repoFalso({
      // Solo un domicilio, y es de este mes: con los 3 meses calendario
      // completos (jul-sep) no aparecería.
      transacciones: [transaccion("2026-10-10", 300_000, "egreso", "c1")],
      categorias: CATEGORIAS,
    }),
    AHORA,
  );

  assertEquals(perfil.gasto_mensual_por_grupo.get(11), 100_000);
});

Deno.test("perfil: sin movimientos marca historial insuficiente", async () => {
  const perfil = await leerPerfilFinanciero("usuario-1", repoFalso(), AHORA);

  assertEquals(perfil.historial_insuficiente, true);
  assertEquals(perfil.ingreso_mensual, null);
  assertEquals(perfil.excedente_mensual, null);
  assertEquals(perfil.gasto_mensual, 0);
  assertEquals(perfil.ahorro_mensual, 0);
  assertEquals(perfil.gasto_mensual_por_grupo.size, 0);
  assertEquals(perfil.metas, []);
});

Deno.test("perfil: con solo el mes actual usa ese ingreso y avisa historial corto", async () => {
  const perfil = await leerPerfilFinanciero(
    "usuario-1",
    repoFalso({ transacciones: [transaccion("2026-10-05", 1_500_000)] }),
    AHORA,
  );

  assertEquals(perfil.ingreso_mensual, 1_500_000);
  assertEquals(perfil.excedente_mensual, 1_500_000);
  assertEquals(perfil.historial_insuficiente, true);
});

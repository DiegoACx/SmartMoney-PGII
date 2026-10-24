// ============================================================================
// SmartMoney · Chat IA · Perfil financiero del usuario
// ----------------------------------------------------------------------------
// Reúne las cifras de base con las que se simula un escenario: ingreso, gasto,
// excedente, ahorro a metas, gasto por grupo y el avance de cada meta.
//
// Las funciones de cálculo son PURAS (reciben ya los datos); `leerPerfilFinanciero`
// es la única que habla con el repositorio. Nada de red ni de Supabase aquí.
// ============================================================================

import {
  hoyEnBogota,
  mesAnterior,
  sumarDias,
  ultimoDiaDeMes,
} from "./fechas.ts";
import type {
  FilaAporte,
  FilaMeta,
  FilaTransaccion,
  RepositorioChat,
} from "./repositorio.ts";

/** Meses calendario completos que se usan como historial. */
export const MESES_HISTORIAL = 3;

/**
 * Días de la ventana rodante del gasto por grupo y del ahorro (90 días ≈ 3
 * meses). Se prefiere a los 3 meses calendario completos porque incluye los
 * gastos recientes: un egreso de este mes ya cuenta para el recorte.
 */
export const DIAS_HISTORIAL = 90;

/** Días que cubre el "ritmo" reciente de aportes a metas. */
export const DIAS_RITMO = 30;

/** Una meta de ahorro ya resumida para la simulación. */
export interface MetaPerfil {
  nombre: string;
  /** Lo que ya lleva ahorrado en la meta. */
  monto_actual: number;
  /** Cuánto falta para el objetivo (nunca negativo). */
  falta: number;
  fecha_limite: string | null;
  /** Meses entre hoy y la fecha límite; null si no hay fecha. */
  meses_restantes: number | null;
  /** Falta / meses restantes; null si no hay fecha o ya venció. */
  aporte_necesario_mes: number | null;
  /** Aportes netos de los últimos DIAS_RITMO días. */
  ritmo_mes: number;
  /** Meses para cubrir `falta` al ritmo actual; null si el ritmo es 0. */
  meses_al_ritmo_actual: number | null;
}

/** Todo lo que necesita una simulación. */
export interface PerfilFinanciero {
  /** Mediana de ingresos de los meses completos; null si no hay datos. */
  ingreso_mensual: number | null;
  /** Promedio de egresos de los 3 meses completos (incluye gasto de trabajo). */
  gasto_mensual: number;
  /** Igual que gasto_mensual pero solo gastos de trabajo. */
  gasto_trabajo_mensual: number;
  /** ingreso_mensual − gasto_mensual; null si no hay ingreso. */
  excedente_mensual: number | null;
  /** Promedio mensual de aportes netos a metas de los últimos 90 días. */
  ahorro_mensual: number;
  /** Promedio mensual de egresos por grupo de referencia (últimos 90 días). */
  gasto_mensual_por_grupo: Map<number, number>;
  metas: MetaPerfil[];
  /** true si no hay ni un mes completo de movimientos. */
  historial_insuficiente: boolean;
}

// --- Cálculos puros ----------------------------------------------------------

/** Mediana de una lista (0 elementos → 0). No modifica la entrada. */
export function mediana(valores: number[]): number {
  if (valores.length === 0) return 0;
  const orden = [...valores].sort((a, b) => a - b);
  const medio = Math.floor(orden.length / 2);
  return orden.length % 2 === 1
    ? orden[medio]
    : (orden[medio - 1] + orden[medio]) / 2;
}

/** Meses calendario cumplidos entre dos fechas 'YYYY-MM-DD' (nunca negativo). */
export function mesesEntre(desde: string, hasta: string): number {
  const [a1, m1, d1] = desde.split("-").map(Number);
  const [a2, m2, d2] = hasta.split("-").map(Number);
  let meses = (a2 - a1) * 12 + (m2 - m1);
  if (d2 < d1) meses -= 1;
  return Math.max(0, meses);
}

/** Los meses completos [m1, m2, m3] anteriores al mes de `hoy`, más antiguo primero. */
export function mesesCompletos(hoy: string, cuantos = MESES_HISTORIAL): string[] {
  const meses: string[] = [];
  let mes = hoy.slice(0, 7);
  for (let i = 0; i < cuantos; i++) {
    mes = mesAnterior(mes);
    meses.unshift(mes);
  }
  return meses;
}

/** Suma de montos de un conjunto de filas. */
function sumaMontos(filas: { monto: number }[]): number {
  return filas.reduce((total, fila) => total + fila.monto, 0);
}

/** Ingreso mensual: mediana de los meses completos con ingreso o el mes actual. */
export function calcularIngresoMensual(
  ingresosVentana: FilaTransaccion[],
  ingresosMesActual: FilaTransaccion[],
  meses: string[],
): number | null {
  const porMes = new Map<string, number>();
  for (const fila of ingresosVentana) {
    const mes = fila.fecha.slice(0, 7);
    porMes.set(mes, (porMes.get(mes) ?? 0) + fila.monto);
  }
  const conIngreso = meses
    .map((mes) => porMes.get(mes) ?? 0)
    .filter((total) => total > 0);
  if (conIngreso.length > 0) return mediana(conIngreso);

  const delMesActual = sumaMontos(ingresosMesActual);
  return delMesActual > 0 ? delMesActual : null;
}

/** Promedio mensual de egresos por grupo de referencia en la ventana. */
export function calcularGastoPorGrupo(
  egresos: FilaTransaccion[],
  grupoPorCategoria: Map<string, number | null>,
  meses = MESES_HISTORIAL,
): Map<number, number> {
  const porGrupo = new Map<number, number>();
  for (const fila of egresos) {
    if (fila.categoria_id === null) continue;
    const grupo = grupoPorCategoria.get(fila.categoria_id);
    if (grupo === null || grupo === undefined) continue;
    porGrupo.set(grupo, (porGrupo.get(grupo) ?? 0) + fila.monto);
  }
  const promedio = new Map<number, number>();
  for (const [grupo, total] of porGrupo) promedio.set(grupo, total / meses);
  return promedio;
}

/** Resumen de cada meta activa (falta, plazo, aporte necesario y ritmo). */
export function calcularMetasPerfil(
  metas: FilaMeta[],
  aportesRitmo: FilaAporte[],
  hoy: string,
): MetaPerfil[] {
  const ritmoPorMeta = new Map<string, number>();
  for (const aporte of aportesRitmo) {
    ritmoPorMeta.set(
      aporte.meta_id,
      (ritmoPorMeta.get(aporte.meta_id) ?? 0) + aporte.monto,
    );
  }

  return metas.map((meta) => {
    const falta = Math.max(0, meta.monto_objetivo - meta.monto_actual);
    const mesesRestantes = meta.fecha_limite
      ? mesesEntre(hoy, meta.fecha_limite)
      : null;
    const aporteNecesario = mesesRestantes !== null && mesesRestantes > 0
      ? falta / mesesRestantes
      : null;
    const ritmo = ritmoPorMeta.get(meta.id) ?? 0;
    return {
      nombre: meta.nombre,
      monto_actual: meta.monto_actual,
      falta,
      fecha_limite: meta.fecha_limite,
      meses_restantes: mesesRestantes,
      aporte_necesario_mes: aporteNecesario,
      ritmo_mes: ritmo,
      meses_al_ritmo_actual: ritmo > 0 ? Math.ceil(falta / ritmo) : null,
    };
  });
}

// --- Lectura con el repositorio ----------------------------------------------

/** Arma el perfil financiero del usuario. */
export async function leerPerfilFinanciero(
  usuarioId: string,
  repositorio: RepositorioChat,
  ahora: Date = new Date(),
): Promise<PerfilFinanciero> {
  const hoy = hoyEnBogota(ahora);
  const meses = mesesCompletos(hoy);
  const ventanaDesde = `${meses[0]}-01`;
  const ventanaHasta = ultimoDiaDeMes(meses[meses.length - 1]);
  const inicioMesActual = `${hoy.slice(0, 7)}-01`;
  // Ventana rodante de 90 días: incluye los movimientos del mes en curso.
  const historialDesde = sumarDias(hoy, -DIAS_HISTORIAL);

  const [
    ingresosVentana,
    ingresosMesActual,
    egresosVentana,
    egresosHistorial,
    aportesHistorial,
    aportesRitmo,
    metas,
    categorias,
  ] = await Promise.all([
    repositorio.leerTransacciones(usuarioId, ventanaDesde, ventanaHasta, "ingreso"),
    repositorio.leerTransacciones(usuarioId, inicioMesActual, hoy, "ingreso"),
    repositorio.leerTransacciones(usuarioId, ventanaDesde, ventanaHasta, "egreso"),
    repositorio.leerTransacciones(usuarioId, historialDesde, hoy, "egreso"),
    repositorio.leerAportes(usuarioId, historialDesde, hoy),
    repositorio.leerAportes(usuarioId, sumarDias(hoy, -DIAS_RITMO), hoy),
    repositorio.leerMetasActivas(usuarioId),
    repositorio.leerCategorias(usuarioId),
  ]);

  const ingresoMensual = calcularIngresoMensual(
    ingresosVentana,
    ingresosMesActual,
    meses,
  );
  const gastoMensual = sumaMontos(egresosVentana) / MESES_HISTORIAL;
  const gastoTrabajoMensual =
    sumaMontos(egresosVentana.filter((f) => f.es_gasto_trabajo === true)) /
    MESES_HISTORIAL;
  const ahorroMensual = sumaMontos(aportesHistorial) / MESES_HISTORIAL;

  const grupoPorCategoria = new Map<string, number | null>(
    categorias.map((c) => [c.id, c.grupo_id]),
  );

  return {
    ingreso_mensual: ingresoMensual,
    gasto_mensual: gastoMensual,
    gasto_trabajo_mensual: gastoTrabajoMensual,
    excedente_mensual: ingresoMensual === null
      ? null
      : ingresoMensual - gastoMensual,
    ahorro_mensual: ahorroMensual,
    gasto_mensual_por_grupo: calcularGastoPorGrupo(egresosHistorial, grupoPorCategoria),
    metas: calcularMetasPerfil(metas, aportesRitmo, hoy),
    historial_insuficiente: ingresosVentana.length === 0 &&
      egresosVentana.length === 0,
  };
}

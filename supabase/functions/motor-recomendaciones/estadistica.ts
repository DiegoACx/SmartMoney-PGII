// ============================================================================
// SmartMoney · Motor de recomendaciones · Estadística
// ----------------------------------------------------------------------------
// Funciones PURAS. Ninguna de estas funciones llama a Supabase: reciben arrays
// y devuelven resultados, de modo que se pueden probar con Deno.test sin red.
// ============================================================================

import {
  FACTOR_CONSUMO,
  GRUPO_OBLIGACIONES,
  K,
  SEMANAS_POR_MES,
} from "./config.ts";

// --- Tipos de datos ----------------------------------------------------------

/** Transacción ya normalizada por index.ts (monto numérico, fecha 'YYYY-MM-DD'). */
export interface TransaccionBase {
  id: string;
  categoria_id: string;
  /** Grupo DANE de la categoría (null en ingresos y en categorías sin grupo). */
  grupo_id: number | null;
  tipo: "ingreso" | "egreso";
  monto: number;
  fecha: string;
  es_gasto_trabajo: boolean;
}

export interface CategoriaBase {
  id: string;
  nombre: string;
  grupo_id: number | null;
  tipo: string;
}

export interface GrupoReferencia {
  id: number;
  nombre: string;
  proporcion_referencia: number | null;
  incluir_en_referencia: boolean;
}

/** Línea base de una categoría: es lo que se persiste en linea_base_usuario. */
export interface LineaBaseCategoria {
  categoria_id: string;
  /** Mediana de los MONTOS POR MOVIMIENTO de la categoría. */
  mediana: number;
  /** MAD de los MONTOS POR MOVIMIENTO de la categoría. */
  mad: number;
  /** Semanas con registros de la categoría. */
  n_semanas: number;
  /** Movimientos usados para la mediana y la MAD. */
  n_movimientos: number;
}

/** Línea base de un grupo: se calcula en memoria, no se persiste. */
export interface LineaBaseGrupo {
  grupo_id: number;
  nombre: string;
  proporcion_referencia: number | null;
  /** Gasto semanal medio del grupo desde su primera semana con registros. */
  promedio_semanal: number;
  n: number;
  p: number;
  referencia_semanal: number;
  normal_semanal: number | null;
  normal_mensual: number | null;
}

/** Gasto de una semana ISO concreta. */
export interface SemanaGasto {
  /** Clave ISO 8601, por ejemplo '2026-W42'. */
  clave: string;
  /** Lunes de esa semana, 'YYYY-MM-DD'. */
  lunes: string;
  monto: number;
}

/** Serie semanal de una categoría o de un grupo. */
export interface AgregadoClave {
  clave: string;
  semanas: SemanaGasto[];
  /** Montos alineados con la ventana consultada (semanas sin gasto valen 0). */
  serie: number[];
  /** Suma de la serie / semanas de historial (desde la primera con registros). */
  promedio_semanal: number;
  mediana: number;
  mad: number;
  /** Semanas con registros (monto > 0). */
  n: number;
}

// --- Estadística básica ------------------------------------------------------

/** Mediana de un conjunto de valores. Devuelve 0 si el arreglo está vacío. */
export function mediana(valores: number[]): number {
  if (valores.length === 0) return 0;
  const ordenados = [...valores].sort((a, b) => a - b);
  const medio = Math.floor(ordenados.length / 2);
  if (ordenados.length % 2 === 1) return ordenados[medio];
  return (ordenados[medio - 1] + ordenados[medio]) / 2;
}

/** Desviación absoluta mediana (MAD) respecto de la mediana indicada. */
export function mad(valores: number[], medianaValor?: number): number {
  if (valores.length === 0) return 0;
  const centro = medianaValor ?? mediana(valores);
  return mediana(valores.map((valor) => Math.abs(valor - centro)));
}

/** Promedio aritmético. Devuelve 0 si el arreglo está vacío. */
export function promedio(valores: number[]): number {
  if (valores.length === 0) return 0;
  const total = valores.reduce((suma, valor) => suma + valor, 0);
  return total / valores.length;
}

/**
 * z robusto = (observado − mediana) / (1,4826 × MAD).
 * Si la escala es indefinida (MAD = 0) devuelve 0: el llamador debe aplicar
 * explícitamente la regla de MAD = 0.
 */
export function zRobusto(
  observado: number,
  medianaValor: number,
  madValor: number,
): number {
  const escala = 1.4826 * madValor;
  if (escala <= 0) return 0;
  return (observado - medianaValor) / escala;
}

/** Peso personal p = n / (n + K), con n semanas con registros. */
export function pesoPersonal(n: number, k: number = K): number {
  if (n <= 0) return 0;
  return n / (n + k);
}

/** Consumo de referencia semanal de un grupo a partir del ingreso mensual. */
export function referenciaSemanal(
  ingresoMensual: number,
  proporcionReferencia: number,
): number {
  return (
    (ingresoMensual * FACTOR_CONSUMO * (proporcionReferencia / 100)) /
    SEMANAS_POR_MES
  );
}

/**
 * Normal semanal: mezcla el componente personal (promedio semanal del propio
 * usuario) con la referencia según p.
 */
export function normalSemanal(
  p: number,
  personalSemanal: number,
  referencia: number,
): number {
  return p * personalSemanal + (1 - p) * referencia;
}

/** Convierte un normal semanal en normal mensual. */
export function normalMensual(normalSem: number): number {
  return normalSem * SEMANAS_POR_MES;
}

// --- Fechas (UTC para no arrastrar la zona horaria del servidor) --------------

export function aFechaUTC(fecha: string): Date {
  const [anio, mes, dia] = fecha.split("-").map(Number);
  return new Date(Date.UTC(anio, mes - 1, dia));
}

export function aTextoFecha(fecha: Date): string {
  return fecha.toISOString().slice(0, 10);
}

export function sumarDias(fecha: string, dias: number): string {
  const resultado = aFechaUTC(fecha);
  resultado.setUTCDate(resultado.getUTCDate() + dias);
  return aTextoFecha(resultado);
}

/** Días completos entre dos fechas (hasta − desde). */
export function diasEntre(desde: string, hasta: string): number {
  return Math.round(
    (aFechaUTC(hasta).getTime() - aFechaUTC(desde).getTime()) / 86_400_000,
  );
}

/** 'YYYY-MM' de una fecha. */
export function mesDe(fecha: string): string {
  return fecha.slice(0, 7);
}

/** Día del mes (1..31). */
export function diaDelMes(fecha: string): number {
  return Number(fecha.slice(8, 10));
}

/** Días del mes calendario al que pertenece la fecha. */
export function diasDelMes(fecha: string): number {
  const anio = Number(fecha.slice(0, 4));
  const mes = Number(fecha.slice(5, 7));
  return new Date(Date.UTC(anio, mes, 0)).getUTCDate();
}

/** Mes calendario inmediatamente anterior, 'YYYY-MM'. */
export function mesAnterior(fecha: string): string {
  const anio = Number(fecha.slice(0, 4));
  const mes = Number(fecha.slice(5, 7));
  if (mes === 1) return `${anio - 1}-12`;
  return `${anio}-${String(mes - 1).padStart(2, "0")}`;
}

/** Lunes de la semana ISO a la que pertenece la fecha. */
export function lunesDeSemana(fecha: string): string {
  const dia = aFechaUTC(fecha).getUTCDay(); // 0 = domingo
  const desplazamiento = dia === 0 ? -6 : 1 - dia;
  return sumarDias(fecha, desplazamiento);
}

/** Clave ISO 8601 de la semana de una fecha, por ejemplo '2026-W42'. */
export function semanaISO(fecha: string): string {
  const base = aFechaUTC(fecha);
  const dia = base.getUTCDay() || 7;
  const jueves = new Date(base.getTime());
  jueves.setUTCDate(base.getUTCDate() + 4 - dia);
  const anio = jueves.getUTCFullYear();
  const primeroDeAnio = new Date(Date.UTC(anio, 0, 1));
  const numero = Math.ceil(
    ((jueves.getTime() - primeroDeAnio.getTime()) / 86_400_000 + 1) / 7,
  );
  return `${anio}-W${String(numero).padStart(2, "0")}`;
}

/** Lista de lunes entre dos lunes (incluidos), avanzando de 7 en 7 días. */
export function semanasEntre(
  lunesInicial: string,
  lunesFinal: string,
): string[] {
  const semanas: string[] = [];
  let actual = lunesInicial;
  while (actual <= lunesFinal) {
    semanas.push(actual);
    actual = sumarDias(actual, 7);
  }
  return semanas;
}

/** Devuelve la fecha más reciente de las dos (comparación de texto ISO). */
export function fechaMayor(a: string, b: string): string {
  return a >= b ? a : b;
}

// --- Agregación por semanas --------------------------------------------------

export function sumarMontos(transacciones: TransaccionBase[]): number {
  return transacciones.reduce((total, t) => total + t.monto, 0);
}

/** Lunes de la primera semana con registros del usuario (null si no hay). */
export function primeraSemanaConRegistros(
  transacciones: TransaccionBase[],
): string | null {
  if (transacciones.length === 0) return null;
  let menor = transacciones[0].fecha;
  for (const t of transacciones) {
    if (t.fecha < menor) menor = t.fecha;
  }
  return lunesDeSemana(menor);
}

/**
 * Semanas de historial de una serie: desde su primera semana con registros
 * hasta la última de la serie; las semanas vacías intermedias cuentan.
 * 0 si la serie no tiene ningún registro.
 */
export function semanasHistorial(serie: number[]): number {
  const primera = serie.findIndex((monto) => monto > 0);
  return primera < 0 ? 0 : serie.length - primera;
}

/**
 * Agrupa transacciones por una clave (categoría o grupo) y construye su serie
 * semanal sobre la ventana [lunesInicial, lunesFinal].
 *
 * Las semanas sin gasto cuentan como 0 desde la primera semana con registros:
 * eso se logra llamando con lunesInicial = primera semana del usuario.
 */
export function agregarPorClave(
  transacciones: TransaccionBase[],
  clave: (t: TransaccionBase) => string | null,
  lunesInicial: string,
  lunesFinal: string,
): Map<string, AgregadoClave> {
  const lunes = semanasEntre(lunesInicial, lunesFinal);
  const posicion = new Map(lunes.map((dia, indice) => [dia, indice]));
  const series = new Map<string, number[]>();

  for (const t of transacciones) {
    const llave = clave(t);
    if (llave === null) continue;
    const indice = posicion.get(lunesDeSemana(t.fecha));
    if (indice === undefined) continue; // fuera de la ventana
    if (!series.has(llave)) {
      series.set(llave, Array.from({ length: lunes.length }, () => 0));
    }
    series.get(llave)![indice] += t.monto;
  }

  const resultado = new Map<string, AgregadoClave>();
  for (const [llave, serie] of series) {
    const med = mediana(serie);
    const nHistorial = semanasHistorial(serie);
    resultado.set(llave, {
      clave: llave,
      semanas: lunes.map((dia, indice) => ({
        clave: semanaISO(dia),
        lunes: dia,
        monto: serie[indice],
      })),
      serie,
      // El promedio se divide entre las semanas de historial (desde la primera
      // con registros), no entre todas las semanas de la ventana.
      promedio_semanal: promedio(serie.slice(serie.length - nHistorial)),
      mediana: med,
      mad: mad(serie, med),
      n: serie.filter((monto) => monto > 0).length,
    });
  }
  return resultado;
}

/**
 * Movimientos por categoría dentro de [lunesInicial, lunesFinal].
 * El detector de anomalías usa esta lista para calcular la mediana y la MAD de
 * los MONTOS POR MOVIMIENTO de cada categoría, excluyendo el movimiento que
 * está evaluando (por eso se devuelven las transacciones, no solo los montos).
 */
export function movimientosPorCategoria(
  transacciones: TransaccionBase[],
  lunesInicial: string,
  lunesFinal: string,
): Map<string, TransaccionBase[]> {
  const porCategoria = new Map<string, TransaccionBase[]>();
  for (const transaccion of transacciones) {
    const lunes = lunesDeSemana(transaccion.fecha);
    if (lunes < lunesInicial || lunes > lunesFinal) continue;
    const lista = porCategoria.get(transaccion.categoria_id);
    if (lista) lista.push(transaccion);
    else porCategoria.set(transaccion.categoria_id, [transaccion]);
  }
  return porCategoria;
}

/**
 * Ingreso mensual = mediana de la suma mensual de ingresos de los últimos 3
 * meses calendario con ingresos. Null si el usuario no tiene ingresos.
 */
export function medianaIngresoMensual(
  ingresos: TransaccionBase[],
): number | null {
  const porMes = new Map<string, number>();
  for (const t of ingresos) {
    const mes = mesDe(t.fecha);
    porMes.set(mes, (porMes.get(mes) ?? 0) + t.monto);
  }
  const mesesConIngreso = [...porMes.entries()]
    .filter(([, monto]) => monto > 0)
    .sort((a, b) => (a[0] < b[0] ? 1 : -1));
  if (mesesConIngreso.length === 0) return null;
  return mediana(mesesConIngreso.slice(0, 3).map(([, monto]) => monto));
}

// --- Línea base --------------------------------------------------------------

/**
 * Línea base por categoría: la mediana y la MAD se calculan sobre los MONTOS
 * DE CADA MOVIMIENTO de la categoría (no sobre totales semanales), porque lo
 * que se evalúa luego es el monto de un movimiento suelto.
 * n_semanas sigue siendo el de los agregados semanales.
 */
export function calcularLineaBaseCategorias(params: {
  agregados: Map<string, AgregadoClave>;
  movimientos: Map<string, TransaccionBase[]>;
}): LineaBaseCategoria[] {
  const { agregados, movimientos } = params;
  const lineas: LineaBaseCategoria[] = [];
  for (const [categoriaId, agregado] of agregados) {
    const montos = (movimientos.get(categoriaId) ?? []).map((t) => t.monto);
    const med = mediana(montos);
    lineas.push({
      categoria_id: categoriaId,
      mediana: med,
      mad: mad(montos, med),
      n_semanas: agregado.n,
      n_movimientos: montos.length,
    });
  }
  return lineas;
}

/**
 * Línea base por grupo (1..13).
 *   referencia_semanal = ingreso × FACTOR_CONSUMO × proporcion / 100 / 4,345
 *   promedio_semanal   = suma del gasto semanal / semanas de historial, es
 *                        decir desde la primera semana con registros del grupo
 *                        (las semanas vacías cuentan); 0 si no hay historial
 *   p = n / (n + K), con n = semanas desde la primera semana con registros
 *       del grupo hasta la semana actual (las semanas vacías cuentan)
 *   normal_semanal = p × promedio_semanal + (1 − p) × referencia_semanal
 * Si no hay ingreso mensual o el grupo es el 13, normal_semanal = promedio
 * (solo si n ≥ K; si no, queda sin normal).
 */
export function calcularLineaBaseGrupos(params: {
  agregados: Map<string, AgregadoClave>;
  grupos: GrupoReferencia[];
  ingresoMensual: number | null;
}): LineaBaseGrupo[] {
  const { agregados, grupos, ingresoMensual } = params;
  const lineas: LineaBaseGrupo[] = [];

  for (const grupo of grupos) {
    const agregado = agregados.get(String(grupo.id));
    if (!agregado) continue;

    // Semanas desde la primera semana con registros del grupo (las vacías cuentan).
    const n = semanasHistorial(agregado.serie);
    const p = pesoPersonal(n);
    const promedioSemanal = agregado.promedio_semanal;
    const proporcion = grupo.proporcion_referencia;
    const usarReferencia = ingresoMensual !== null &&
      ingresoMensual > 0 &&
      grupo.id !== GRUPO_OBLIGACIONES &&
      proporcion !== null;

    let referencia = 0;
    let normalSem: number | null;
    if (usarReferencia) {
      referencia = referenciaSemanal(ingresoMensual!, proporcion!);
      normalSem = normalSemanal(p, promedioSemanal, referencia);
    } else {
      normalSem = n >= K ? promedioSemanal : null;
    }

    lineas.push({
      grupo_id: grupo.id,
      nombre: grupo.nombre,
      proporcion_referencia: proporcion,
      promedio_semanal: promedioSemanal,
      n,
      p,
      referencia_semanal: referencia,
      normal_semanal: normalSem,
      normal_mensual: normalSem === null ? null : normalMensual(normalSem),
    });
  }
  return lineas;
}

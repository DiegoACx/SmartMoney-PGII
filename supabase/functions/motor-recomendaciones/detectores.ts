// ============================================================================
// SmartMoney · Motor de recomendaciones · Detectores
// ----------------------------------------------------------------------------
// Funciones PURAS, una por tipo de hallazgo. Ninguna llama a Supabase: reciben
// los datos ya leídos y devuelven hallazgos {tipo, datos, severidad, impacto}.
// Este módulo no decide puntajes ni escribe nada (eso vive en puntaje.ts y en
// index.ts).
// ============================================================================

import {
  DIA_MINIMO_SOBREGASTO,
  DIAS_POR_MES,
  FACTOR_MAD_CERO,
  FACTOR_SEVERIDAD_LECCION,
  FACTOR_SEVERIDAD_LECCION_RUTA,
  FRACCION_IMPACTO_INGRESO,
  GRUPO_REFERENCIA_MAX,
  IMPACTO_LECCION,
  IMPACTO_SIN_INGRESO,
  K,
  MIN_SEMANAS_ANOMALIA,
  RELEVANCIA_MIN,
  SEVERIDAD_RIESGO,
  SEVERIDAD_Z_MAX,
  TITULO_PROXIMAMENTE,
  UMBRAL_LOGRO,
  UMBRAL_SOBREGASTO,
  VENTANA_LOGRO,
  Z_MAD_CERO,
  Z_UMBRAL,
  type TipoHallazgo,
} from "./config.ts";
import {
  type LineaBaseCategoria,
  type LineaBaseGrupo,
  type TransaccionBase,
  diaDelMes,
  diasDelMes,
  diasEntre,
  pesoPersonal,
  sumarMontos,
  zRobusto,
} from "./estadistica.ts";

// --- Tipos -------------------------------------------------------------------

/**
 * Hallazgo previo al puntaje: lo que produce un detector.
 * `datos` es el jsonb que se guarda en hallazgos.datos (cifras usadas).
 * `p` es el peso personal con el que se calcula la confianza.
 * `objetivo` identifica la entidad señalada (grupo, categoría o meta) y sirve
 * para detectar repetición y para rastrear de dónde salió la recomendación.
 */
export interface HallazgoBase {
  tipo: TipoHallazgo;
  datos: Record<string, unknown>;
  severidad: number;
  impacto: number;
  p: number;
  objetivo: string;
}

export interface MetaActiva {
  id: string;
  nombre: string;
  monto_objetivo: number;
  monto_actual: number;
  fecha_limite: string;
}

export interface NivelCatalogo {
  id: string;
  orden: number;
}

export interface EscalonCatalogo {
  id: string;
  nivel_id: string;
  orden: number;
  titulo: string;
  tipo: string;
  disponible: boolean;
}

/** De dónde salió la lección sugerida: tema del grupo o ruta del usuario. */
export type MotivoLeccion = "tema_relacionado" | "siguiente_en_ruta";

// --- Utilidades --------------------------------------------------------------

function limitar(valor: number): number {
  if (Number.isNaN(valor)) return 0;
  return Math.min(Math.max(valor, 0), 1);
}

/** Impacto = faltante / (10 % del ingreso). Sin ingreso, 0,5. */
function calcularImpacto(
  faltante: number,
  ingresoMensual: number | null,
): number {
  if (ingresoMensual === null || ingresoMensual <= 0) {
    return IMPACTO_SIN_INGRESO;
  }
  return limitar(faltante / (FRACCION_IMPACTO_INGRESO * ingresoMensual));
}

function gastoPorGrupoDelMes(
  egresos: TransaccionBase[],
): Map<number, number> {
  const totales = new Map<number, number>();
  for (const t of egresos) {
    if (t.grupo_id === null) continue;
    totales.set(t.grupo_id, (totales.get(t.grupo_id) ?? 0) + t.monto);
  }
  return totales;
}

// --- a) Sobregasto proyectado por grupo --------------------------------------

/**
 * Compara la proyección de cierre de mes de cada grupo contra su normal_mensual.
 * Solo evalúa a partir del día DIA_MINIMO_SOBREGASTO del mes en curso.
 * `egresosMesActual` debe venir filtrado: mes calendario en curso y sin gastos
 * de trabajo (igual que la línea base).
 */
export function detectarSobregastoCategoria(params: {
  hoy: string;
  ingresoMensual: number | null;
  lineasBaseGrupos: LineaBaseGrupo[];
  egresosMesActual: TransaccionBase[];
}): HallazgoBase[] {
  const { hoy, ingresoMensual, lineasBaseGrupos, egresosMesActual } = params;
  const diaActual = diaDelMes(hoy);
  if (diaActual < DIA_MINIMO_SOBREGASTO) return [];

  const diasMes = diasDelMes(hoy);
  const gastadoPorGrupo = gastoPorGrupoDelMes(egresosMesActual);
  const hallazgos: HallazgoBase[] = [];

  for (const linea of lineasBaseGrupos) {
    const normal = linea.normal_mensual;
    if (normal === null || normal <= 0) continue;

    const gastadoMes = gastadoPorGrupo.get(linea.grupo_id) ?? 0;
    const proyeccion = (gastadoMes / diaActual) * diasMes;
    if (proyeccion <= normal * UMBRAL_SOBREGASTO) continue;

    const severidad = limitar(proyeccion / normal - 1);
    const impacto = calcularImpacto(proyeccion - normal, ingresoMensual);

    hallazgos.push({
      tipo: "sobregasto_categoria",
      severidad,
      impacto,
      p: linea.p,
      objetivo: `grupo:${linea.grupo_id}`,
      datos: {
        grupo_id: linea.grupo_id,
        nombre_grupo: linea.nombre,
        gastado_mes: gastadoMes,
        dia_actual: diaActual,
        dias_mes: diasMes,
        dias_restantes: diasMes - diaActual,
        proyeccion,
        normal_mensual: normal,
        umbral_sobregasto: UMBRAL_SOBREGASTO,
        n_semanas: linea.n,
        severidad,
        impacto,
      },
    });
  }
  return hallazgos;
}

// --- b) Gasto anómalo por transacción ---------------------------------------

/**
 * Marca egresos sueltos de los últimos 7 días que se alejan del patrón de su
 * categoría (z robusto > Z_UMBRAL). Solo categorías con n ≥ MIN_SEMANAS_ANOMALIA.
 */
export function detectarGastoAnomalo(params: {
  ingresoMensual: number | null;
  egresosUltimos7Dias: TransaccionBase[];
  lineasBaseCategorias: LineaBaseCategoria[];
  nombresCategorias: Map<string, string>;
}): HallazgoBase[] {
  const {
    ingresoMensual,
    egresosUltimos7Dias,
    lineasBaseCategorias,
    nombresCategorias,
  } = params;

  const basePorCategoria = new Map<string, LineaBaseCategoria>();
  for (const linea of lineasBaseCategorias) {
    basePorCategoria.set(linea.categoria_id, linea);
  }

  const hallazgos: HallazgoBase[] = [];
  for (const t of egresosUltimos7Dias) {
    const linea = basePorCategoria.get(t.categoria_id);
    if (!linea || linea.n_semanas < MIN_SEMANAS_ANOMALIA) continue;

    let z: number;
    let anomalo: boolean;
    if (linea.mad === 0) {
      anomalo = t.monto > FACTOR_MAD_CERO * linea.mediana;
      z = Z_MAD_CERO;
    } else {
      z = zRobusto(t.monto, linea.mediana, linea.mad);
      anomalo = z > Z_UMBRAL;
    }
    if (!anomalo) continue;

    const severidad = limitar(z / SEVERIDAD_Z_MAX);
    const impacto = calcularImpacto(t.monto, ingresoMensual);

    hallazgos.push({
      tipo: "gasto_anomalo",
      severidad,
      impacto,
      p: pesoPersonal(linea.n_semanas),
      objetivo: `categoria:${t.categoria_id}`,
      datos: {
        transaccion_id: t.id,
        categoria_id: t.categoria_id,
        nombre_categoria: nombresCategorias.get(t.categoria_id) ?? "tu categoría",
        monto: t.monto,
        fecha: t.fecha,
        mediana_semanal: linea.mediana,
        mad_semanal: linea.mad,
        z,
        n_semanas: linea.n_semanas,
        severidad,
        impacto,
      },
    });
  }
  return hallazgos;
}

// --- c) Aporte a metas -------------------------------------------------------

/**
 * Metas activas con fecha límite futura: compara el aporte mensual necesario
 * contra el ritmo real de los últimos DIAS_RITMO_APORTES días.
 * `aportesPorMeta` es la suma neta de aportes_meta.monto (los retiros cuentan
 * negativos, así que la suma neta ya descuenta).
 */
export function detectarAporteMeta(params: {
  hoy: string;
  ingresoMensual: number | null;
  metas: MetaActiva[];
  aportesPorMeta: Map<string, number>;
}): HallazgoBase[] {
  const { hoy, ingresoMensual, metas, aportesPorMeta } = params;
  const hallazgos: HallazgoBase[] = [];

  for (const meta of metas) {
    const restante = meta.monto_objetivo - meta.monto_actual;
    if (restante <= 0) continue;

    const diasRestantes = diasEntre(hoy, meta.fecha_limite);
    if (diasRestantes <= 0) continue;

    const meses = Math.max(1, Math.ceil(diasRestantes / DIAS_POR_MES));
    const aporteSugerido = restante / meses;
    const ritmo = aportesPorMeta.get(meta.id) ?? 0;
    if (ritmo >= aporteSugerido) continue;

    const severidad = limitar(1 - ritmo / aporteSugerido);
    const impacto = calcularImpacto(aporteSugerido, ingresoMensual);

    hallazgos.push({
      tipo: "aporte_meta",
      severidad,
      impacto,
      p: 1,
      objetivo: `meta:${meta.id}`,
      datos: {
        meta_id: meta.id,
        nombre_meta: meta.nombre,
        monto_objetivo: meta.monto_objetivo,
        monto_actual: meta.monto_actual,
        restante,
        fecha_limite: meta.fecha_limite,
        dias_restantes: diasRestantes,
        meses,
        aporte_sugerido: aporteSugerido,
        ritmo_30_dias: ritmo,
        severidad,
        impacto,
      },
    });
  }
  return hallazgos;
}

// --- d) Lección sugerida -----------------------------------------------------

/** Cadena global de escalones: por orden de nivel y luego por orden de escalón. */
export function cadenaEscalones(
  niveles: NivelCatalogo[],
  escalones: EscalonCatalogo[],
): EscalonCatalogo[] {
  const nivelesOrdenados = [...niveles].sort((a, b) => a.orden - b.orden);
  const cadena: EscalonCatalogo[] = [];
  for (const nivel of nivelesOrdenados) {
    const delNivel = escalones
      .filter((e) => e.nivel_id === nivel.id)
      .sort((a, b) => a.orden - b.orden);
    cadena.push(...delNivel);
  }
  return cadena;
}

/**
 * Un escalón está desbloqueado si es el primero de la cadena o si el escalón
 * inmediatamente anterior está completado (misma regla de educacion_logic.dart).
 */
export function estaDesbloqueado(
  indice: number,
  cadena: EscalonCatalogo[],
  completados: Set<string>,
): boolean {
  if (indice <= 0) return true;
  return completados.has(cadena[indice - 1].id);
}

/** Una lección es sugerible si está publicada, disponible y no es evaluación. */
export function esLeccionSugerible(escalon: EscalonCatalogo): boolean {
  return escalon.tipo !== "evaluacion" &&
    escalon.disponible &&
    escalon.titulo !== TITULO_PROXIMAMENTE;
}

/**
 * Primera lección de la cadena global que esté publicada, desbloqueada y sin
 * completar (la ruta del usuario). Null si no queda ninguna.
 */
export function primeraLeccionDisponible(
  cadena: EscalonCatalogo[],
  completados: Set<string>,
): EscalonCatalogo | null {
  for (let indice = 0; indice < cadena.length; indice++) {
    const escalon = cadena[indice];
    if (!esLeccionSugerible(escalon)) continue;
    if (completados.has(escalon.id)) continue;
    if (!estaDesbloqueado(indice, cadena, completados)) continue;
    return escalon;
  }
  return null;
}

/**
 * Si hay sobregasto en un grupo, sugiere la primera lección mapeada a ese grupo
 * que esté publicada, desbloqueada y sin completar (motivo 'tema_relacionado').
 * Si ninguna cumple, sugiere la siguiente lección de la ruta del usuario
 * (motivo 'siguiente_en_ruta'); el respaldo se emite una sola vez. Si el usuario
 * ya completó todas las lecciones válidas, no genera hallazgo.
 */
export function detectarLeccionSugerida(params: {
  sobregastos: HallazgoBase[];
  niveles: NivelCatalogo[];
  escalones: EscalonCatalogo[];
  completados: Set<string>;
  mapaLecciones: Record<number, string[]>;
}): HallazgoBase[] {
  const { sobregastos, niveles, escalones, completados, mapaLecciones } = params;
  const cadena = cadenaEscalones(niveles, escalones);
  const indicePorId = new Map(cadena.map((e, indice) => [e.id, indice]));
  const hallazgos: HallazgoBase[] = [];
  let respaldoUsado = false;

  for (const sobregasto of sobregastos) {
    const grupoId = Number(sobregasto.datos.grupo_id);
    const nombreGrupo = String(sobregasto.datos.nombre_grupo ?? "");
    const severidadSobregasto = sobregasto.severidad;

    let elegida: EscalonCatalogo | null = null;
    let motivo: MotivoLeccion = "tema_relacionado";

    for (const escalonId of mapaLecciones[grupoId] ?? []) {
      const indice = indicePorId.get(escalonId);
      if (indice === undefined) continue;
      const escalon = cadena[indice];
      if (!esLeccionSugerible(escalon)) continue;
      if (completados.has(escalon.id)) continue;
      if (!estaDesbloqueado(indice, cadena, completados)) continue;
      elegida = escalon;
      break;
    }

    if (elegida === null) {
      if (respaldoUsado) continue;
      elegida = primeraLeccionDisponible(cadena, completados);
      if (elegida === null) continue;
      motivo = "siguiente_en_ruta";
      respaldoUsado = true;
    }

    const factor = motivo === "tema_relacionado"
      ? FACTOR_SEVERIDAD_LECCION
      : FACTOR_SEVERIDAD_LECCION_RUTA;
    const severidad = limitar(factor * severidadSobregasto);

    hallazgos.push({
      tipo: "leccion_sugerida",
      severidad,
      impacto: IMPACTO_LECCION,
      p: sobregasto.p,
      objetivo: `grupo:${grupoId}`,
      datos: {
        escalon_id: elegida.id,
        titulo: elegida.titulo,
        grupo_id: grupoId,
        nombre_grupo: nombreGrupo,
        motivo,
        severidad_sobregasto: severidadSobregasto,
        severidad,
        impacto: IMPACTO_LECCION,
      },
    });
  }
  return hallazgos;
}

// --- e) Logro del último mes completo ---------------------------------------

/**
 * Reconocimiento del último mes calendario completo: grupos 1..12 con n ≥ K
 * cuyo gasto quedó por debajo del 90 % de su normal mensual. Un logro por
 * grupo y por mes.
 * `egresosMes` debe venir filtrado: mes completo y sin gastos de trabajo.
 */
export function detectarLogro(params: {
  mes: string;
  ingresoMensual: number | null;
  lineasBaseGrupos: LineaBaseGrupo[];
  egresosMes: TransaccionBase[];
}): HallazgoBase[] {
  const { mes, ingresoMensual, lineasBaseGrupos, egresosMes } = params;
  const gastadoPorGrupo = gastoPorGrupoDelMes(egresosMes);
  const hallazgos: HallazgoBase[] = [];

  for (const linea of lineasBaseGrupos) {
    if (linea.grupo_id > GRUPO_REFERENCIA_MAX) continue;
    const normal = linea.normal_mensual;
    if (normal === null || normal <= 0) continue;
    if (linea.n < K) continue;

    const gastoMes = gastadoPorGrupo.get(linea.grupo_id) ?? 0;
    if (gastoMes > normal * UMBRAL_LOGRO) continue;

    const relevante = ingresoMensual === null || ingresoMensual <= 0
      ? normal > 0
      : normal >= RELEVANCIA_MIN * ingresoMensual;
    if (!relevante) continue;

    const severidad = limitar((1 - gastoMes / normal) / VENTANA_LOGRO);
    const impacto = calcularImpacto(normal - gastoMes, ingresoMensual);

    hallazgos.push({
      tipo: "logro",
      severidad,
      impacto,
      p: linea.p,
      objetivo: `grupo:${linea.grupo_id}`,
      datos: {
        grupo_id: linea.grupo_id,
        nombre_grupo: linea.nombre,
        mes,
        gasto_mes: gastoMes,
        normal_mensual: normal,
        ahorro_mes: normal - gastoMes,
        n_semanas: linea.n,
        severidad,
        impacto,
      },
    });
  }
  return hallazgos;
}

// --- f) Riesgo de fin de mes -------------------------------------------------

/**
 * Saldo del mes contra el ritmo de gasto restante. Usa TODOS los egresos del
 * mes (incluidos los gastos de trabajo), porque el problema es de caja y no de
 * comparación con la referencia.
 */
export function detectarRiesgoFinDeMes(params: {
  hoy: string;
  ingresoMensual: number | null;
  ingresosMes: TransaccionBase[];
  egresosMes: TransaccionBase[];
}): HallazgoBase[] {
  const { hoy, ingresoMensual, ingresosMes, egresosMes } = params;
  const diaActual = diaDelMes(hoy);
  const diasRestantes = diasDelMes(hoy) - diaActual;

  const ingresos = sumarMontos(ingresosMes);
  const egresos = sumarMontos(egresosMes);
  const saldo = ingresos - egresos;
  const gastoDiario = egresos / diaActual;
  const faltante = gastoDiario * diasRestantes - saldo;
  if (faltante <= 0) return [];

  const impacto = calcularImpacto(faltante, ingresoMensual);

  return [{
    tipo: "riesgo_fin_de_mes",
    severidad: SEVERIDAD_RIESGO,
    impacto,
    p: 1,
    objetivo: "riesgo:mes",
    datos: {
      ingresos_mes: ingresos,
      egresos_mes: egresos,
      saldo,
      dia_actual: diaActual,
      dias_restantes: diasRestantes,
      gasto_diario: gastoDiario,
      faltante,
      severidad: SEVERIDAD_RIESGO,
      impacto,
    },
  }];
}

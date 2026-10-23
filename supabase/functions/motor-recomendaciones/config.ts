// ============================================================================
// SmartMoney · Motor de recomendaciones · Configuración
// ----------------------------------------------------------------------------
// Todas las constantes de negocio del motor viven aquí. Salvo los parámetros de
// Gemini (que se reexportan desde `_shared/gemini.ts`), este módulo no importa
// nada más del proyecto, así que puede usarse desde cualquier otro módulo y
// desde las pruebas sin efectos de borde.
// ============================================================================

/** Tipos de hallazgo admitidos por el esquema (hallazgos.tipo / recomendaciones.tipo). */
export type TipoHallazgo =
  | "sobregasto_categoria"
  | "gasto_anomalo"
  | "aporte_meta"
  | "leccion_sugerida"
  | "logro"
  | "riesgo_fin_de_mes";

/** Tipos que compiten dentro del bandido Thompson Sampling. */
export type TipoBandido =
  | "sobregasto_categoria"
  | "gasto_anomalo"
  | "aporte_meta"
  | "leccion_sugerida"
  | "logro";

/** Tipos que participan en el bandido (riesgo_fin_de_mes queda fuera). */
export const TIPOS_BANDIDO: TipoBandido[] = [
  "sobregasto_categoria",
  "gasto_anomalo",
  "aporte_meta",
  "leccion_sugerida",
  "logro",
];

/** Tipos de hallazgo que participan en la selección "normal" (todos menos riesgo). */
export const TIPOS_SELECCIONABLES: TipoHallazgo[] = [...TIPOS_BANDIDO];

// --- Parámetros estadísticos -------------------------------------------------

/** Fuerza del suavizado bayesiano del peso personal: p = n / (n + K). */
export const K = 4;

/** Semanas de historial usadas para la línea base. */
export const SEMANAS_HISTORIAL = 12;

/** Fracción del ingreso mensual que se asume consumido (canasta básica). */
export const FACTOR_CONSUMO = 0.83;

/** Umbral del z robusto a partir del cual un gasto es anómalo. */
export const Z_UMBRAL = 3;

/**
 * Movimientos previos mínimos en una categoría para evaluar anomalías.
 * También es la fuerza del suavizado de la confianza del hallazgo anómalo:
 * p = n_mov / (n_mov + MIN_MOVIMIENTOS_ANOMALIA).
 */
export const MIN_MOVIMIENTOS_ANOMALIA = 5;

/** Multiplicador sobre normal_mensual a partir del cual hay sobregasto. */
export const UMBRAL_SOBREGASTO = 1.2;

/** Día del mes a partir del cual se evalúa el sobregasto proyectado. */
export const DIA_MINIMO_SOBREGASTO = 7;

/** Fracción de normal_mensual bajo la cual el gasto del mes se considera logro. */
export const UMBRAL_LOGRO = 0.9;

/** Peso mínimo de normal_mensual frente al ingreso para que un logro importe. */
export const RELEVANCIA_MIN = 0.02;

/** Puntaje mínimo para recomendar un hallazgo distinto de riesgo_fin_de_mes. */
export const PUNTAJE_MINIMO = 0.15;

/** Horas durante las cuales se reutilizan los hallazgos ya calculados. */
export const HORAS_CACHE = 6;

/** Semanas promedio por mes calendario (365,25 / 12 / 7). */
export const SEMANAS_POR_MES = 4.345;

/** Días de mes usados para prorratear el aporte a metas. */
export const DIAS_POR_MES = 30;

// --- Normalizadores internos -------------------------------------------------

/** Días de transacciones que se leen de la base en cada ejecución. */
export const DIAS_VENTANA_TRANSACCIONES = 400;

/** Ventana (días) para medir el ritmo de aportes a metas. */
export const DIAS_RITMO_APORTES = 30;

/** Ventana (días) para considerar "reciente" una anomalía o un logro del mes. */
export const DIAS_GAS_ANOMALO = 7;

/** Días durante los cuales una recomendación sin responder sigue vigente. */
export const DIAS_RECOMENDACION_VIGENTE = 7;

/** Días hacia atrás en los que repetir el mismo objetivo penaliza el puntaje. */
export const DIAS_REPETICION = 7;

/** Factor de puntaje cuando el mismo objetivo ya se recomendó en DIAS_REPETICION. */
export const FACTOR_REPETICION = 0.2;

/** Fracción del ingreso mensual usada como unidad de impacto (10 %). */
export const FRACCION_IMPACTO_INGRESO = 0.1;

/** Impacto por defecto cuando no hay ingreso mensual calculable. */
export const IMPACTO_SIN_INGRESO = 0.5;

/** Divisor de severidad para el z robusto (z = 6 → severidad 1). */
export const SEVERIDAD_Z_MAX = 6;

/** Con MAD = 0 un gasto es anómalo si supera este múltiplo de la mediana. */
export const FACTOR_MAD_CERO = 3;

/** z que se asigna cuando MAD = 0 y el gasto resulta anómalo. */
export const Z_MAD_CERO = 6;

/** Ancho de la banda de logro: (1 − gasto/normal) / 0,30 → severidad. */
export const VENTANA_LOGRO = 0.3;

/** Fracción de la severidad del sobregasto que hereda la lección sugerida. */
export const FACTOR_SEVERIDAD_LECCION = 0.6;

/** Fracción de la severidad del sobregasto que hereda la lección de respaldo. */
export const FACTOR_SEVERIDAD_LECCION_RUTA = 0.3;

/** Título que marca un escalón aún no publicado; nunca se sugiere. */
export const TITULO_PROXIMAMENTE = "Próximamente";

/** Impacto fijo de una lección sugerida. */
export const IMPACTO_LECCION = 0.5;

/** Severidad fija del riesgo de fin de mes. */
export const SEVERIDAD_RIESGO = 1;

/** Máximo de recomendaciones emitidas por ejecución. */
export const MAX_RECOMENDACIONES = 2;

/** Grupo de obligaciones y transferencias: queda fuera de la referencia DANE. */
export const GRUPO_OBLIGACIONES = 13;

/** Último grupo que entra en la comparación contra la referencia (1..12). */
export const GRUPO_REFERENCIA_MAX = 12;

/** Zona horaria de referencia para "hoy" y el mes calendario del usuario. */
export const ZONA_HORARIA = "America/Bogota";

// --- LLM (Gemini) ------------------------------------------------------------

/**
 * Los parámetros de Gemini viven en `_shared/gemini.ts` (los comparten el motor
 * y el chat): se reexportan aquí para no romper los puntos de importación.
 */
export {
  GEMINI_MODELO,
  GEMINI_MODELO_RESPALDO,
  GEMINI_TIMEOUT_MS,
  LLM_MAX_CARACTERES,
} from "../_shared/gemini.ts";

/** Interruptor del LLM: en false, todo sale de las plantillas. */
export const LLM_ACTIVO = true;

// --- Bandido Thompson Sampling ----------------------------------------------

/**
 * Media de utilidad de DISEÑO por tipo (0..1): el punto de partida antes de
 * tener datos reales. Es un supuesto de diseño, no una tasa observada.
 */
export const MU_DISENO: Record<TipoBandido, number> = {
  sobregasto_categoria: 0.80,
  aporte_meta: 0.75,
  gasto_anomalo: 0.65,
  logro: 0.55,
  leccion_sugerida: 0.50,
};

/**
 * Pesos del grupo de control: los mismos valores de diseño, para que control y
 * bandido partan del mismo nivel y PUNTAJE_MINIMO siga calibrado.
 */
export const PESO_TIPO_CONTROL: Record<TipoBandido, number> = { ...MU_DISENO };

/** Peso fijo del riesgo de fin de mes: queda fuera del bandido. */
export const PESO_RIESGO_FIN_DE_MES = 1;

/** Fuerza del prior poblacional: respuestas virtuales que aporta el diseño. */
export const C_DISENO = 4;

/**
 * Fuerza del prior del usuario: respuestas virtuales que aporta la población.
 *
 * Calibrado con la simulación de la Fase 5 (ia/fase5, `sensibilidad_M.csv`,
 * 300 usuarios × 30 interacciones × 50 semillas en dos escenarios): M = 1 nunca
 * queda por debajo de Thompson sin prior en ninguno de los dos escenarios y es
 * el mejor a 30 interacciones. Con M = 4 (valor anterior) el jerárquico caía por
 * debajo del bandido sin prior en el escenario de «perfiles opuestos».
 */
export const M_PRIOR = 1;

/** Interruptor del bandido: en false, todos usan los pesos de control. */
export const BANDIDO_ACTIVO = true;

/** Interruptor del A/B: en false, todos los usuarios van al grupo 'bandido'. */
export const AB_ACTIVO = true;

// --- Mapa grupo → lecciones --------------------------------------------------

/**
 * grupo_id (1..13) → lista de escalon_id de educacion_escalones, en orden de
 * preferencia. Cuando ninguno sirve, el detector cae a la siguiente lección de
 * la ruta del usuario.
 */
export const MAPA_LECCIONES: Record<number, string[]> = {
  1:  ['97c20577-72bf-487a-98f9-e8835b1ae21c', '78489ad0-7c7d-4a11-961d-19be43dbb2e9'], // Gastos fijos y variables, Egresos
  2:  ['93df5638-caeb-4b4c-880f-19d52942d1de', 'f3c61be0-202c-49a3-ac65-37aee41e5f4e'], // Gastos hormiga, Necesidades vs deseos
  3:  ['f3c61be0-202c-49a3-ac65-37aee41e5f4e', '78489ad0-7c7d-4a11-961d-19be43dbb2e9'], // Necesidades vs deseos, Egresos
  4:  ['97c20577-72bf-487a-98f9-e8835b1ae21c', '29905b73-338d-4c4c-b2b2-46341a824b0c'], // Gastos fijos y variables, Capacidad de pago
  5:  ['97c20577-72bf-487a-98f9-e8835b1ae21c', 'f3c61be0-202c-49a3-ac65-37aee41e5f4e'], // Gastos fijos y variables, Necesidades vs deseos
  6:  ['47c16a92-103d-4eb3-b5b6-daac00c9224a', '97c20577-72bf-487a-98f9-e8835b1ae21c'], // Fondo de emergencia, Gastos fijos y variables
  7:  ['97c20577-72bf-487a-98f9-e8835b1ae21c', '93df5638-caeb-4b4c-880f-19d52942d1de'], // Gastos fijos y variables, Gastos hormiga
  8:  ['93df5638-caeb-4b4c-880f-19d52942d1de', '97c20577-72bf-487a-98f9-e8835b1ae21c'], // Gastos hormiga, Gastos fijos y variables
  9:  ['f3c61be0-202c-49a3-ac65-37aee41e5f4e', '93df5638-caeb-4b4c-880f-19d52942d1de', '78489ad0-7c7d-4a11-961d-19be43dbb2e9'], // Necesidades vs deseos, Gastos hormiga, Egresos
  10: ['97c20577-72bf-487a-98f9-e8835b1ae21c', '426f8535-da2b-42db-931f-8d145cf3bb86'], // Gastos fijos y variables, Ahorro
  11: ['93df5638-caeb-4b4c-880f-19d52942d1de', 'f3c61be0-202c-49a3-ac65-37aee41e5f4e', '78489ad0-7c7d-4a11-961d-19be43dbb2e9'], // Gastos hormiga, Necesidades vs deseos, Egresos
  12: ['f3c61be0-202c-49a3-ac65-37aee41e5f4e', '93df5638-caeb-4b4c-880f-19d52942d1de'], // Necesidades vs deseos, Gastos hormiga
  13: ['6257371e-a120-413e-8819-675669362467', '29905b73-338d-4c4c-b2b2-46341a824b0c', 'b148ceda-822f-4f65-871f-f8531224e690'], // Pasivos, Capacidad de pago, Interés simple
};

// ============================================================================
// SmartMoney · Chat IA · Tipos compartidos
// ----------------------------------------------------------------------------
// Las 6 intenciones del clasificador (ia/fase6/modelo_intencion.json) y la
// forma de la respuesta que consume la app. Este módulo no importa nada del
// proyecto: se puede usar desde cualquier otro sin efectos de borde.
// ============================================================================

/** Intenciones que reconoce el clasificador de intención. */
export type Intencion =
  | "consultar_datos"
  | "simular_escenario"
  | "aprender_concepto"
  | "pedir_consejo"
  | "ayuda_app"
  | "conversacion";

/** De dónde salió el texto de la respuesta. */
export type Origen = "plantilla" | "llm" | "faq" | "calculo";

/** Acción de navegación que la app puede ejecutar tras mostrar la respuesta. */
export type Accion =
  | { tipo: "abrir_leccion"; escalon_id: string }
  | { tipo: "ir_a"; destino: "metas" | "movimientos" | "perfil" };

/** Respuesta JSON de la Edge Function. */
export interface RespuestaChat {
  respuesta: string;
  intencion: Intencion;
  confianza: number;
  origen: Origen;
  accion?: Accion;
}

/**
 * Lo que devuelve cada intención antes de que el manejador le agregue la
 * intención y el nivel de confianza del clasificador.
 */
export interface RespuestaIntencion {
  respuesta: string;
  origen: Origen;
  accion?: Accion;
  /** Motivo corto para el log de auditoría (nunca contiene el mensaje). */
  motivo: string;
}

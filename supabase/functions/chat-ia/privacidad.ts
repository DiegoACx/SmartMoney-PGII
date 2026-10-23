// ============================================================================
// SmartMoney · Chat IA · Privacidad del mensaje
// ----------------------------------------------------------------------------
// Antes de guardar un mensaje o de enviarlo a Gemini se ocultan los datos
// personales: secuencias de 8 o más dígitos (cédulas, cuentas, tarjetas,
// incluso con espacios o guiones) y correos electrónicos.
//
// Los MONTOS no se ocultan: "300 mil" o "$1.200.000" se conservan tal cual,
// porque el usuario los escribe para preguntar por sus cifras.
// ============================================================================

/** Texto con el que se reemplaza cada dato personal. */
export const MARCADOR_DATO_OCULTO = "[dato oculto]";

/** Correo electrónico. */
const RE_CORREO = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;

/**
 * 8 o más dígitos seguidos, con espacios o guiones intercalados.
 * "$1.200.000" no coincide (los puntos cortan la secuencia y solo quedarían
 * 7 dígitos: 1 200 000).
 */
const RE_SECUENCIA_LARGA = /\d(?:[ -]?\d){7,}/g;

/** Reemplaza cédulas/cuentas/tarjetas y correos por [dato oculto]. */
export function ocultarDatosPersonales(texto: string): string {
  return texto
    .replace(RE_CORREO, MARCADOR_DATO_OCULTO)
    .replace(RE_SECUENCIA_LARGA, MARCADOR_DATO_OCULTO);
}

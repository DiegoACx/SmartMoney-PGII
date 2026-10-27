// ============================================================================
// SmartMoney · Chat IA · ¿El usuario está pidiendo una decisión?
// ----------------------------------------------------------------------------
// Frases y patrones que delatan que el usuario quiere elegir entre dos caminos
// (por ejemplo "¿la meto a un CDT o abono a la deuda?"). Se comparte entre:
//   · la regla híbrida de intención (manejador.ts → pedir_consejo), y
//   · la plantilla de respaldo de pedir_consejo.ts, que ante una decisión da
//     criterios para decidir en vez de los consejos genéricos.
//
// Es lógica pura (regex): no toca Supabase ni la red.
// ============================================================================

import { minusculasSinTildes } from "./montos.ts";

/** Frases que delatan que el usuario está pidiendo una decisión. */
export const FRASES_DECISION = [
  "me conviene",
  "es mejor",
  "que es mejor",
  "deberia",
  "vale la pena",
  "que me recomiendas",
  "recomiendame",
  "que hago",
].join("|");

/**
 * Elección entre dos caminos: "<verbo> … o <abono|pago|invierto|ahorro|meto|
 * guardo>". El verbo de la izquierda solo abre la puerta; lo que confirma que
 * es una decisión es la opción de la derecha.
 */
export const RE_ELECCION =
  /\b(?:meto|mando|pongo|dejo|guardo|ahorro|invierto|abono|pago|compro|uso|dedico)\b[^.!?,]{0,40}?\bo\s+(?:abono|pago|invierto|ahorro|meto|guardo)\b/;

/** Una frase de decisión o una elección explícita "A o B". */
export const RE_DECISION = new RegExp(
  `\\b(?:${FRASES_DECISION})\\b|${RE_ELECCION.source}`,
);

/** true si el mensaje pide una decisión (frase de decisión o elección "A o B"). */
export function esDecision(mensaje: string): boolean {
  return RE_DECISION.test(minusculasSinTildes(mensaje));
}

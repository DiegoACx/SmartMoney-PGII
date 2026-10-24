// ============================================================================
// SmartMoney · Similitud de textos cortos · Trigramas de caracteres
// ----------------------------------------------------------------------------
// Emparejado difuso sin red ni LLM: se comparan conjuntos de trigramas de
// caracteres de dos textos ya normalizados con `normalizar`.
//
//   · trigramas   → conjunto de trigramas de un texto YA normalizado.
//   · jaccard     → índice de Jaccard (0..1): qué tanto se parecen dos textos
//                   del mismo tamaño. Es el que usa ayuda_app (faq.ts).
//   · solapamiento → coeficiente de solapamiento (0..1): qué tanto del texto
//                   MÁS CORTO aparece dentro del más largo. Es el que usa
//                   aprender_concepto, donde se compara un término corto del
//                   glosario contra la pregunta completa del usuario (Jaccard
//                   castigaría al término por ser corto).
//
// Este módulo no toca Supabase ni la red: se prueba con `deno test`.
// ============================================================================

/** Trigramas de caracteres de un texto YA normalizado (con `normalizar`). */
export function trigramas(normalizado: string): Set<string> {
  const acolchado = ` ${normalizado} `;
  const conjunto = new Set<string>();
  if (acolchado.length < 3) {
    if (normalizado.length > 0) conjunto.add(normalizado);
    return conjunto;
  }
  for (let i = 0; i + 3 <= acolchado.length; i++) {
    conjunto.add(acolchado.slice(i, i + 3));
  }
  return conjunto;
}

/** Índice de Jaccard entre dos conjuntos de trigramas (0..1). */
export function jaccard(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let interseccion = 0;
  for (const trigrama of a) {
    if (b.has(trigrama)) interseccion++;
  }
  return interseccion / (a.size + b.size - interseccion);
}

/**
 * Coeficiente de solapamiento entre dos conjuntos de trigramas (0..1):
 * intersección / tamaño del conjunto más pequeño. Vale 1 cuando el texto más
 * corto está contenido en el más largo.
 */
export function solapamiento(a: Set<string>, b: Set<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  const [menor, mayor] = a.size <= b.size ? [a, b] : [b, a];
  let interseccion = 0;
  for (const trigrama of menor) {
    if (mayor.has(trigrama)) interseccion++;
  }
  return interseccion / menor.size;
}

/**
 * Trigramas de un texto normalizado (minúsculas, sin tildes, sin signos) o null
 * si queda demasiado corto: un texto de 1 o 2 caracteres generaría conjuntos
 * diminutos que harían coincidir cualquier cosa.
 */
export function trigramasDeTexto(texto: string): Set<string> | null {
  const partes = texto
    .toLowerCase()
    .normalize("NFD")
    .replace(/\p{Mn}/gu, "")
    .replace(/[^a-z0-9]+/g, " ")
    .trim();
  if (partes.length < 3) return null;
  return trigramas(partes);
}

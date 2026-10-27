// ============================================================================
// SmartMoney · Chat IA · Recuperación de conocimiento (glosario y lecciones)
// ----------------------------------------------------------------------------
// Empareja el mensaje del usuario con la entrada del glosario y/o la lección
// educativa más parecidas, usando similitud de trigramas de caracteres sobre
// textos normalizados con `normalizar`.
//
// Se usa el COEFICIENTE DE SOLAPAMIENTO (y no Jaccard) porque aquí se compara
// un término CORTO del glosario contra una pregunta larga: Jaccard castigaría al
// término por tener pocos trigramas, mientras que el solapamiento mide qué tanto
// del texto más corto aparece en el más largo.
//
// Este módulo no toca Supabase ni la red: las lecciones llegan ya leídas y se
// prueba con `deno test`.
// ============================================================================

import { normalizar } from "../_shared/clasificador_ngramas.ts";
import { solapamiento, trigramas } from "../_shared/similitud.ts";
import type { FilaLeccion } from "./repositorio.ts";

import glosarioJson from "./glosario.json" with { type: "json" };

/** Similitud mínima para aceptar una entrada del glosario. */
export const UMBRAL_GLOSARIO = 0.6;

/** Similitud mínima para aceptar una lección educativa. */
export const UMBRAL_LECCION = 0.6;

/**
 * Caracteres del contenido de una lección que se usan como fuente: para el
 * emparejado y para el texto que se le pasa al LLM.
 */
export const LARGO_FUENTE_LECCION = 1500;

/** Una entrada del glosario de finanzas personales. */
export interface EntradaGlosario {
  id: string;
  termino: string;
  alias: string[];
  definicion: string;
  ejemplo: string;
  grupos_relacionados: number[];
  revisado: boolean;
}

/** Coincidencia del glosario con su puntaje (0..1). */
export interface CoincidenciaGlosario {
  entrada: EntradaGlosario;
  puntaje: number;
}

/** Coincidencia de una lección con su puntaje (0..1). */
export interface CoincidenciaLeccion {
  leccion: FilaLeccion;
  puntaje: number;
}

/** Mejor entrada del glosario y mejor lección para un mensaje. */
export interface Coincidencia {
  glosario: CoincidenciaGlosario | null;
  leccion: CoincidenciaLeccion | null;
}

const ENTRADAS = glosarioJson.entradas as EntradaGlosario[];

/**
 * Trigramas de cada término candidato (término + alias) ya normalizados UNA sola
 * vez: el glosario es fijo, así que no tiene sentido recalcularlos por mensaje.
 */
const CANDIDATOS: { entrada: EntradaGlosario; conjuntos: Set<string>[] }[] =
  ENTRADAS.map((entrada) => ({
    entrada,
    conjuntos: [entrada.termino, ...entrada.alias].map((texto) =>
      trigramas(normalizar(texto))
    ),
  }));

/** La entrada del glosario más parecida al mensaje, o null si ninguna supera el umbral. */
export function buscarGlosario(mensaje: string): CoincidenciaGlosario | null {
  const delMensaje = trigramas(normalizar(mensaje));
  let mejor: EntradaGlosario | null = null;
  let mejorPuntaje = 0;

  for (const candidato of CANDIDATOS) {
    for (const conjunto of candidato.conjuntos) {
      const puntaje = solapamiento(delMensaje, conjunto);
      if (puntaje > mejorPuntaje) {
        mejorPuntaje = puntaje;
        mejor = candidato.entrada;
      }
    }
  }

  return mejor !== null && mejorPuntaje >= UMBRAL_GLOSARIO
    ? { entrada: mejor, puntaje: mejorPuntaje }
    : null;
}

/** Texto de una lección que se usa como fuente (título + inicio del contenido). */
export function textoLeccion(leccion: FilaLeccion): string {
  return `${leccion.titulo} ${(leccion.contenido ?? "").slice(0, LARGO_FUENTE_LECCION)}`;
}

/** Frases de pregunta que se quitan del mensaje antes de compararlo con el título. */
const FRASES_PREGUNTA_LECCION = ["que es", "q es", "no entiendo", "explicame"];

/** Artículos que se quitan del mensaje antes de compararlo con el título. */
const ARTICULOS_LECCION = new Set(["el", "la", "un", "una", "de", "del"]);

/**
 * Mensaje normalizado y sin frases de pregunta ni artículos: así "que es un
 * presupuesto" queda "presupuesto" y puede superar el umbral contra el título
 * "Presupuesto mensual".
 */
function limpiarParaTitulo(mensaje: string): string {
  let texto = normalizar(mensaje);
  for (const frase of FRASES_PREGUNTA_LECCION) {
    texto = texto.replace(new RegExp(`\\b${frase}\\b`, "g"), " ");
  }
  return texto
    .split(" ")
    .filter((palabra) => palabra.length > 0 && !ARTICULOS_LECCION.has(palabra))
    .join(" ");
}

/**
 * La lección más parecida al mensaje, o null si ninguna supera el umbral.
 *
 * Se compara SOLO contra el TÍTULO: el contenido de la lección solo se usa como
 * texto fuente una vez elegida. Del mensaje se quitan las frases de pregunta y
 * los artículos para no diluir la coincidencia.
 */
export function buscarLeccion(
  mensaje: string,
  lecciones: FilaLeccion[],
): CoincidenciaLeccion | null {
  const delMensaje = trigramas(limpiarParaTitulo(mensaje));
  let mejor: FilaLeccion | null = null;
  let mejorPuntaje = 0;

  for (const leccion of lecciones) {
    const puntaje = solapamiento(
      delMensaje,
      trigramas(normalizar(leccion.titulo)),
    );
    if (puntaje > mejorPuntaje) {
      mejorPuntaje = puntaje;
      mejor = leccion;
    }
  }

  return mejor !== null && mejorPuntaje >= UMBRAL_LECCION
    ? { leccion: mejor, puntaje: mejorPuntaje }
    : null;
}

/** Mejor entrada del glosario y mejor lección para el mismo mensaje. */
export function buscarConocimiento(
  mensaje: string,
  lecciones: FilaLeccion[],
): Coincidencia {
  return {
    glosario: buscarGlosario(mensaje),
    leccion: buscarLeccion(mensaje, lecciones),
  };
}

/** Ids del glosario que se ofrecen cuando no hay ninguna coincidencia. */
const IDS_SUGERIDOS = ["fondo-emergencia", "interes-compuesto", "presupuesto"];

/** Hasta `cuantos` conceptos del glosario para sugerirle al usuario. */
export function sugerirConceptos(cuantos = 3): EntradaGlosario[] {
  const porId = new Map(ENTRADAS.map((entrada) => [entrada.id, entrada]));
  const sugeridas = IDS_SUGERIDOS
    .map((id) => porId.get(id))
    .filter((entrada): entrada is EntradaGlosario => entrada !== undefined);
  return sugeridas.slice(0, cuantos);
}

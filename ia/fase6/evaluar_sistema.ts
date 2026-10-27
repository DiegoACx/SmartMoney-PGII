// ============================================================================
// SmartMoney · Fase 6 · Evaluación del sistema de intención TAL COMO FUNCIONA
//                      EN PRODUCCIÓN
// ----------------------------------------------------------------------------
// Pasa las 216 preguntas reales del formulario por la MISMA lógica de decisión
// de intención que usa supabase/functions/chat-ia/manejador.ts:
//
//   reglas híbridas (simulación, decisión, concepto)
//     → modelo TF-IDF + regresión logística
//       → umbral UMBRAL_INTENCION (0.45) → respaldo a pedir_consejo
//
// La decisión se toma con decidirIntencion(), la misma función que usa el
// manejador (importada del propio manejador.ts), así que lo que se mide aquí es
// el comportamiento real del servidor, no una copia.
//
// Estándar de oro: la etiqueta donde A y B coinciden; donde no, la de
// resolucion_desacuerdos.csv.
//
// Ejecutar:
//   deno run --allow-read --allow-write ia/fase6/evaluar_sistema.ts
//
// No llama a Gemini, ni a Supabase, ni a la red: solo clasifica intención.
// ============================================================================

import { parse, stringify } from "jsr:@std/csv@1";

import { clasificarIntencion } from "../../supabase/functions/chat-ia/clasificadores.ts";
import { decidirIntencion } from "../../supabase/functions/chat-ia/manejador.ts";
import { ocultarDatosPersonales } from "../../supabase/functions/chat-ia/privacidad.ts";
import type { Intencion } from "../../supabase/functions/chat-ia/tipos.ts";

// --- Rutas -------------------------------------------------------------------

const CARPETA = new URL("./", import.meta.url);
const ARCHIVO_A = new URL("para_etiquetar_A.csv", CARPETA);
const ARCHIVO_B = new URL("para_etiquetar_B.csv", CARPETA);
const ARCHIVO_DESACUERDOS = new URL("resolucion_desacuerdos.csv", CARPETA);
/**
 * CSV de salida. Por defecto ia/fase6/resultados_sistema.csv; se puede pasar
 * otro nombre (relativo a ia/fase6/) como primer argumento, por ejemplo:
 *   deno run --allow-read --allow-write ia/fase6/evaluar_sistema.ts resultados_sistema_v2.csv
 */
const ARCHIVO_SALIDA = new URL(Deno.args[0] ?? "resultados_sistema.csv", CARPETA);

/** Total esperado de preguntas evaluadas. */
const TOTAL_ESPERADO = 216;

/** Las 6 intenciones del clasificador, en el orden de tipos.ts. */
const CLASES: Intencion[] = [
  "consultar_datos",
  "simular_escenario",
  "aprender_concepto",
  "pedir_consejo",
  "ayuda_app",
  "conversacion",
];

/** Remuestreos y semilla del intervalo de confianza por bootstrap. */
const REMUESTREOS = 2000;
const SEMILLA = 42;

/** Umbral de cobertura del modelo (el mismo del sistema y uno más exigente). */
const CONFIANZA_ALTA = 0.7;

// --- Lectura de CSV ----------------------------------------------------------

interface FilaCsv {
  [columna: string]: string;
}

/** Lee un CSV (con BOM opcional) y devuelve registros con el encabezado. */
async function leerCsv(ruta: URL): Promise<FilaCsv[]> {
  let texto = await Deno.readTextFile(ruta);
  if (texto.charCodeAt(0) === 0xfeff) texto = texto.slice(1);

  const filas = parse(texto);
  if (filas.length === 0) {
    throw new Error(`El archivo ${ruta.pathname} está vacío.`);
  }

  const encabezado = filas[0].map((columna) => columna.trim());
  const registros: FilaCsv[] = [];
  for (let i = 1; i < filas.length; i++) {
    const fila = filas[i];
    if (fila.length === 1 && fila[0].trim() === "") continue; // línea vacía
    const registro: FilaCsv = {};
    encabezado.forEach((columna, j) => {
      registro[columna] = fila[j] ?? "";
    });
    registros.push(registro);
  }
  return registros;
}

interface Etiqueta {
  texto: string;
  intencion: string;
}

/** Mapa id → { texto, intencion }, sin tolerar ids repetidos. */
function indexarPorId(filas: FilaCsv[], archivo: string): Map<string, Etiqueta> {
  const mapa = new Map<string, Etiqueta>();
  for (const fila of filas) {
    const id = (fila["id"] ?? "").trim();
    const intencion = (fila["intencion"] ?? "").trim();
    if (id === "") {
      throw new Error(`Hay una fila sin id en ${archivo}.`);
    }
    if (mapa.has(id)) {
      throw new Error(`El id ${id} aparece dos veces en ${archivo}.`);
    }
    mapa.set(id, { texto: fila["texto"] ?? "", intencion });
  }
  return mapa;
}

interface Caso {
  id: string;
  texto: string;
  oro: Intencion;
}

// --- Métricas ----------------------------------------------------------------

type Par = [oro: string, pred: string];

interface MetricasClase {
  soporte: number;
  precision: number;
  exhaustividad: number;
  f1: number;
}

function metricasClase(pares: Par[], clase: string): MetricasClase {
  let tp = 0;
  let fp = 0;
  let fn = 0;
  for (const [oro, pred] of pares) {
    if (pred === clase && oro === clase) tp++;
    else if (pred === clase) fp++;
    else if (oro === clase) fn++;
  }
  const precision = tp + fp > 0 ? tp / (tp + fp) : 0;
  const exhaustividad = tp + fn > 0 ? tp / (tp + fn) : 0;
  const f1 = precision + exhaustividad > 0
    ? (2 * precision * exhaustividad) / (precision + exhaustividad)
    : 0;
  return { soporte: tp + fn, precision, exhaustividad, f1 };
}

function exactitud(pares: Par[]): number {
  if (pares.length === 0) return 0;
  let aciertos = 0;
  for (const [oro, pred] of pares) if (oro === pred) aciertos++;
  return aciertos / pares.length;
}

/** F1 macro: promedio del F1 de las 6 intenciones. */
function f1Macro(pares: Par[]): number {
  let suma = 0;
  for (const clase of CLASES) suma += metricasClase(pares, clase).f1;
  return suma / CLASES.length;
}

// --- Utilidades estadísticas -------------------------------------------------

/** PRNG determinista (mulberry32) para que el bootstrap sea reproducible. */
function prng(semilla: number): () => number {
  let a = semilla >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function percentil(ordenados: number[], q: number): number {
  if (ordenados.length === 0) return 0;
  const posicion = q * (ordenados.length - 1);
  const base = Math.floor(posicion);
  const resto = posicion - base;
  const siguiente = ordenados[base + 1];
  return siguiente === undefined
    ? ordenados[base]
    : ordenados[base] + resto * (siguiente - ordenados[base]);
}

interface Intervalo {
  f1: number;
  inferior: number;
  superior: number;
}

/** IC 95 % del F1 macro por bootstrap con remuestreo de los casos. */
function bootstrapF1Macro(pares: Par[]): Intervalo {
  const aleatorio = prng(SEMILLA);
  const n = pares.length;
  const valores: number[] = [];
  for (let r = 0; r < REMUESTREOS; r++) {
    const muestra: Par[] = new Array(n);
    for (let i = 0; i < n; i++) {
      muestra[i] = pares[Math.floor(aleatorio() * n)];
    }
    valores.push(f1Macro(muestra));
  }
  valores.sort((a, b) => a - b);
  return {
    f1: f1Macro(pares),
    inferior: percentil(valores, 0.025),
    superior: percentil(valores, 0.975),
  };
}

const LOG_FACTORIAL: number[] = [0];
function logFactorial(n: number): number {
  for (let i = LOG_FACTORIAL.length; i <= n; i++) {
    LOG_FACTORIAL[i] = LOG_FACTORIAL[i - 1] + Math.log(i);
  }
  return LOG_FACTORIAL[n];
}

function logCombinatorio(n: number, k: number): number {
  return logFactorial(n) - logFactorial(k) - logFactorial(n - k);
}

/**
 * Prueba de McNemar exacta (binomial, dos colas) con corrección por
 * combinatoria: p = 2 × Σ_{k≤min(b,c)} C(n,k) / 2^n, acotado a 1.
 */
function mcnemarExacto(b: number, c: number): number {
  const n = b + c;
  if (n === 0) return 1;
  const menor = Math.min(b, c);
  let suma = 0;
  for (let k = 0; k <= menor; k++) {
    suma += Math.exp(logCombinatorio(n, k) - n * Math.LN2);
  }
  return Math.min(1, 2 * suma);
}

// --- Formato -----------------------------------------------------------------

const num = (valor: number): string => valor.toFixed(4);
const pct = (valor: number): string => `${(valor * 100).toFixed(1)}%`;
const col = (valor: string, ancho: number): string => valor.padEnd(ancho);

// --- Carga de datos ----------------------------------------------------------

const [filasA, filasB, filasDesacuerdos] = await Promise.all([
  leerCsv(ARCHIVO_A),
  leerCsv(ARCHIVO_B),
  leerCsv(ARCHIVO_DESACUERDOS),
]);

const mapaA = indexarPorId(filasA, "para_etiquetar_A.csv");
const mapaB = indexarPorId(filasB, "para_etiquetar_B.csv");
const mapaDesacuerdos = indexarPorId(
  filasDesacuerdos,
  "resolucion_desacuerdos.csv",
);

const casos: Caso[] = [];
let coincidencias = 0;
let desacuerdos = 0;

for (const [id, etiquetaA] of mapaA) {
  const etiquetaB = mapaB.get(id);
  if (etiquetaB === undefined) {
    throw new Error(
      `El id ${id} está en para_etiquetar_A.csv pero no en para_etiquetar_B.csv.`,
    );
  }
  let etiqueta: string;
  if (etiquetaA.intencion === etiquetaB.intencion) {
    coincidencias++;
    etiqueta = etiquetaA.intencion;
  } else {
    desacuerdos++;
    const desempate = mapaDesacuerdos.get(id);
    if (desempate === undefined) {
      throw new Error(
        `A y B no coinciden en ${id} (A=${etiquetaA.intencion}, ` +
          `B=${etiquetaB.intencion}) y el id no está en resolucion_desacuerdos.csv.`,
      );
    }
    etiqueta = desempate.intencion;
  }
  if (!CLASES.includes(etiqueta as Intencion)) {
    throw new Error(
      `El id ${id} tiene la etiqueta "${etiqueta}", que no es una intención válida.`,
    );
  }
  casos.push({ id, texto: etiquetaA.texto, oro: etiqueta as Intencion });
}

for (const id of mapaB.keys()) {
  if (!mapaA.has(id)) {
    throw new Error(
      `El id ${id} está en para_etiquetar_B.csv pero no en para_etiquetar_A.csv.`,
    );
  }
}

if (casos.length !== TOTAL_ESPERADO) {
  throw new Error(
    `Se esperaban ${TOTAL_ESPERADO} preguntas y se armaron ${casos.length}. ` +
      `Revisa los archivos de etiquetado (faltan o sobran ids).`,
  );
}

// --- Evaluación --------------------------------------------------------------

interface Resultado {
  id: string;
  texto: string;
  oro: Intencion;
  predModelo: Intencion;
  confModelo: number;
  predSistema: Intencion;
  origenSistema: string;
}

const resultados: Resultado[] = [];
let enmascarados = 0;
let sinSenal = 0;

for (const caso of casos) {
  // Igual que el manejador: el clasificador ve el texto ya enmascarado (PII
  // fuera), y con ese mismo texto se decide la intención.
  const limpio = ocultarDatosPersonales(caso.texto);
  if (limpio !== caso.texto) enmascarados++;

  // a) "Modelo solo": argmax del clasificador, sin reglas ni umbral.
  const modelo = clasificarIntencion(limpio);
  if (modelo.intencion === null) sinSenal++;
  const predModelo: Intencion = modelo.intencion ?? "pedir_consejo";

  // b) "Sistema completo": la misma decisión que usa el manejador.
  const decision = decidirIntencion(limpio);

  resultados.push({
    id: caso.id,
    texto: caso.texto,
    oro: caso.oro,
    predModelo,
    confModelo: modelo.confianza,
    predSistema: decision.intencion,
    origenSistema: decision.origen,
  });
}

const paresModelo: Par[] = resultados.map((r) => [r.oro, r.predModelo]);
const paresSistema: Par[] = resultados.map((r) => [r.oro, r.predSistema]);

const icModelo = bootstrapF1Macro(paresModelo);
const icSistema = bootstrapF1Macro(paresSistema);

// --- 7) McNemar --------------------------------------------------------------

let ambos = 0;
let soloModelo = 0;
let soloSistema = 0;
let ninguno = 0;
for (const fila of resultados) {
  const aciertaModelo = fila.predModelo === fila.oro;
  const aciertaSistema = fila.predSistema === fila.oro;
  if (aciertaModelo && aciertaSistema) ambos++;
  else if (aciertaModelo) soloModelo++;
  else if (aciertaSistema) soloSistema++;
  else ninguno++;
}
const pMcNemar = mcnemarExacto(soloModelo, soloSistema);

// --- Informe -----------------------------------------------------------------

const linea = "=".repeat(78);
const separador = "-".repeat(78);

console.log(linea);
console.log("SmartMoney · Fase 6 · Evaluación del sistema de intención (producción)");
console.log(linea);
console.log(`Preguntas evaluadas: ${casos.length}`);
console.log(
  `Estándar de oro: A y B coinciden en ${coincidencias}; ` +
    `desacuerdos resueltos con resolucion_desacuerdos.csv: ${desacuerdos}.`,
);
console.log(`Enmascaramiento de PII: alteró ${enmascarados} de ${casos.length} textos.`);
console.log(`Modelo sin señal (ningún n-grama conocido): ${sinSenal}.`);
console.log(separador);

console.log("\n1) MÉTRICAS GLOBALES");
console.log(
  `   ${col("Variante", 34)}${col("Exactitud", 12)}${col("F1 macro", 12)}IC 95 % del F1 macro`,
);
console.log(
  `   ${col("Modelo solo (argmax)", 34)}${col(num(exactitud(paresModelo)), 12)}` +
    `${col(num(icModelo.f1), 12)}[${num(icModelo.inferior)}, ${num(icModelo.superior)}]`,
);
console.log(
  `   ${col("Sistema completo (reglas+umbral)", 34)}` +
    `${col(num(exactitud(paresSistema)), 12)}${col(num(icSistema.f1), 12)}` +
    `[${num(icSistema.inferior)}, ${num(icSistema.superior)}]`,
);
console.log(
  `   (bootstrap: ${REMUESTREOS} remuestreos, semilla ${SEMILLA})`,
);

console.log("\n2) MÉTRICAS POR INTENCIÓN");
for (
  const [titulo, pares] of [
    ["Modelo solo (argmax)", paresModelo],
    ["Sistema completo (reglas+umbral)", paresSistema],
  ] as [string, Par[]][]
) {
  console.log(`\n   ${titulo}`);
  console.log(
    `   ${col("Intención", 20)}${col("Soporte", 10)}${col("Precisión", 12)}` +
      `${col("Exhaustividad", 16)}F1`,
  );
  for (const clase of CLASES) {
    const m = metricasClase(pares, clase);
    console.log(
      `   ${col(clase, 20)}${col(String(m.soporte), 10)}` +
        `${col(num(m.precision), 12)}${col(num(m.exhaustividad), 16)}${num(m.f1)}`,
    );
  }
  console.log(`   ${col("macro", 58)}${num(f1Macro(pares))}`);
}

console.log("\n3) MATRIZ DE CONFUSIÓN DEL SISTEMA COMPLETO (filas = oro, columnas = predicción)");
const ancho = 21;
console.log(`   ${col("oro \\ pred", ancho)}${CLASES.map((c) => col(c.slice(0, 19), ancho)).join("")}`);
for (const oro of CLASES) {
  const fila = CLASES.map((pred) => {
    const n = resultados.filter((r) => r.oro === oro && r.predSistema === pred).length;
    return col(String(n), ancho);
  }).join("");
  console.log(`   ${col(oro, ancho)}${fila}`);
}

console.log("\n4) CÓMO SE DECIDIÓ CADA PREGUNTA (sistema completo)");
const origenes = new Map<string, { n: number; aciertos: number }>();
for (const fila of resultados) {
  const actual = origenes.get(fila.origenSistema) ?? { n: 0, aciertos: 0 };
  actual.n++;
  if (fila.predSistema === fila.oro) actual.aciertos++;
  origenes.set(fila.origenSistema, actual);
}
const reglas = [...origenes.keys()].filter((o) => o.startsWith("regla:")).sort();
const otros = ["modelo", "baja_confianza"].filter((o) => origenes.has(o));
console.log(`   ${col("Origen", 34)}${col("Preguntas", 12)}Exactitud`);
for (const origen of [...reglas, ...otros]) {
  const dato = origenes.get(origen)!;
  console.log(
    `   ${col(origen, 34)}${col(String(dato.n), 12)}${pct(dato.aciertos / dato.n)}`,
  );
}
const nModelo = origenes.get("modelo")?.n ?? 0;
const nBaja = origenes.get("baja_confianza")?.n ?? 0;
const nReglas = resultados.length - nModelo - nBaja;
console.log(
  `   → reglas: ${nReglas} · modelo: ${nModelo} · baja confianza: ${nBaja}`,
);

console.log("\n5) COBERTURA DEL MODELO (confianza del argmax sobre las 216)");
const cobertura = (umbral: number): string => {
  const n = resultados.filter((r) => r.confModelo >= umbral).length;
  return `${n}/${resultados.length} (${pct(n / resultados.length)})`;
};
console.log(`   confianza ≥ 0.45: ${cobertura(0.45)}`);
console.log(`   confianza ≥ 0.70: ${cobertura(CONFIANZA_ALTA)}`);

console.log("\n6) PRUEBA DE McNEMAR EXACTA (modelo solo vs sistema completo, dos colas)");
console.log("                            sistema acierta   sistema falla");
console.log(`   modelo acierta                 ${col(String(ambos), 16)}${soloModelo}`);
console.log(`   modelo falla                   ${col(String(soloSistema), 16)}${ninguno}`);
console.log(
  `   b (solo modelo) = ${soloModelo} · c (solo sistema) = ${soloSistema} · ` +
    `p = ${pMcNemar.toFixed(6)}`,
);
console.log(
  pMcNemar < 0.05
    ? "   → La diferencia entre las dos variantes es estadísticamente significativa (p < 0,05)."
    : "   → No hay evidencia de diferencia significativa entre las dos variantes (p ≥ 0,05).",
);

// --- CSV de resultados -------------------------------------------------------

const filasSalida = resultados.map((r) => ({
  id: r.id,
  texto: r.texto,
  oro: r.oro,
  pred_modelo: r.predModelo,
  conf_modelo: r.confModelo.toFixed(6),
  pred_sistema: r.predSistema,
  origen_sistema: r.origenSistema,
  acierta_modelo: String(r.predModelo === r.oro),
  acierta_sistema: String(r.predSistema === r.oro),
}));

await Deno.writeTextFile(
  ARCHIVO_SALIDA,
  stringify(filasSalida, {
    columns: [
      "id",
      "texto",
      "oro",
      "pred_modelo",
      "conf_modelo",
      "pred_sistema",
      "origen_sistema",
      "acierta_modelo",
      "acierta_sistema",
    ],
  }),
);

console.log(separador);
console.log(`Resultados por pregunta escritos en ${ARCHIVO_SALIDA.pathname}`);
console.log(linea);

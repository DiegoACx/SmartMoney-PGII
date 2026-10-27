// ============================================================================
// SmartMoney · Chat IA · pedir_consejo
// ----------------------------------------------------------------------------
// Da 2 o 3 pasos concretos usando el contexto real del usuario: su perfil
// financiero (ingreso, gasto, excedente, ahorro y metas), los hallazgos del
// motor de los últimos 7 días y los dos grupos donde más gasta.
//
// Regla central: el CÓDIGO arma el contexto y las cifras permitidas; Gemini
// solo redacta los pasos con esas cifras. Nada de bancos, productos ni
// inversiones por su nombre. Si Gemini falla, hay una plantilla con dos
// consejos armados con sus propios datos.
//
// Dos casos especiales:
//   - Tema concreto: si la pregunta nombra un concepto del glosario (por ejemplo
//     un CDT), la respuesta habla de ESE tema y lo relaciona con sus datos.
//   - Distribución del dinero ("¿cómo divido mi plata?", "¿qué porcentaje para
//     cada cosa?"): el código calcula la referencia 50/30/20 con sus datos y
//     Gemini solo la redacta con esas cifras.
// ============================================================================

import {
  cifrasEnTexto,
  formatoBloques,
  formatearCOP,
  generarConGemini,
  validarTextoLLM,
} from "../_shared/gemini.ts";
import type { ClasificadorGrupos } from "./clasificadores.ts";
import { buscarGlosario, buscarLeccion, type EntradaGlosario } from "./conocimiento.ts";
import { esDecision } from "./decision.ts";
import { hoyEnBogota, inicioDelDiaBogota, sumarDias } from "./fechas.ts";
import { extraerMontos, minusculasSinTildes } from "./montos.ts";
import {
  leerPerfilFinanciero,
  type MetaPerfil,
  type PerfilFinanciero,
} from "./perfil_financiero.ts";
import type { FilaHallazgo, FilaLeccion, RepositorioChat } from "./repositorio.ts";
import { fraseMargen, gruposMayorGasto } from "./simular_escenario.ts";
import type { Accion, RespuestaIntencion } from "./tipos.ts";

/** Tope de caracteres del texto redactado por Gemini en esta intención. */
export const LLM_MAX_CARACTERES_CONSEJO = 650;

/** Se agrega a toda respuesta de la intención (el usuario lo ve en la app). */
export const AVISO_CONSEJO =
  "Es una orientación general; no es asesoría financiera profesional.";

/** Días hacia atrás de los hallazgos que se usan como contexto. */
export const DIAS_HALLAZGOS = 7;

const INSTRUCCION_CONSEJO =
  "Eres el asesor financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. Da 2 o 3 pasos concretos y aplicables, en español colombiano, tuteando y sin regaños. Usa esta estructura: una frase inicial que responda directo, de 2 a 3 viñetas que empiecen con \"- \" y una frase final corta; el texto, sin contar los símbolos de formato, debe quedar por debajo de 650 caracteres. La primera frase debe responder DIRECTAMENTE a la pregunta del usuario: si pregunta por un producto o un concepto (por ejemplo un CDT), habla de ese tema y relaciónalo con sus datos; no cambies de tema. Puedes poner en **negrita** las cifras clave. Usa SOLO las cifras del contexto y las que escribió el usuario, escritas igual; no inventes cifras, tasas ni plazos. Nunca nombres bancos, entidades, aplicaciones ni productos comerciales concretos: si te piden cuál elegir, explica cómo comparar (tasa efectiva anual, plazo y que la entidad esté vigilada por la Superintendencia Financiera). Si la decisión es entre productos financieros, da criterios generales: fondo de emergencia primero, pagar primero la deuda más cara y comparar la tasa efectiva anual. No menciones impuestos, la DIAN ni las centrales de riesgo salvo que el usuario pregunte por eso. Si el excedente es cero o negativo, el primer paso siempre es equilibrar los gastos con los ingresos. No uses títulos, enlaces, imágenes, tablas, código ni HTML. Responde solo con el texto, sin comillas ni emojis.";

const INSTRUCCION_DISTRIBUCION =
  "Eres el asesor financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. El usuario pregunta cómo repartir su dinero. Reescribe la explicación base en español colombiano, tuteando, más natural y cercana, pero conservando su estructura: una frase inicial, las mismas viñetas (que empiecen con \"- \") con los MISMOS porcentajes y montos en **negrita**, escritos exactamente igual, y una frase final que aclare que es una referencia general, no una regla fija. El texto, sin contar los símbolos de formato, debe quedar por debajo de 650 caracteres. No agregues cifras, tasas ni plazos nuevos. No nombres bancos ni productos comerciales. No menciones impuestos ni la DIAN. No uses títulos, enlaces, imágenes, tablas, código ni HTML. Responde solo con el texto, sin comillas ni emojis.";

/** El usuario pregunta por impuestos, la DIAN o centrales de riesgo. */
const RE_TEMA_IMPUESTOS =
  /\b(?:impuesto|impuestos|dian|renta|retencion|declarar|declaracion|tributari\w*|datacredito|centrales? de riesgo|reportad[oa])\b/;

/** Puntaje mínimo del glosario para tratar la pregunta como un tema concreto. */
export const UMBRAL_TEMA_CONSEJO = 0.8;

export interface DepsConsejo {
  repositorio: RepositorioChat;
  grupos: ClasificadorGrupos;
  fetchFn: typeof fetch;
  claveLLM?: string | null;
}

// --- Contexto -----------------------------------------------------------------

/**
 * Claves de `datos` de un hallazgo que son montos en pesos (las que usa el
 * motor de recomendaciones). Se listan aquí para no acoplar el chat al motor.
 */
const CLAVES_MONTO = [
  "gastado_mes",
  "proyeccion",
  "normal_mensual",
  "normal_personal_mensual",
  "monto",
  "mediana_monto",
  "aporte_sugerido",
  "ritmo_30_dias",
  "gasto_mes",
  "faltante",
];

const CLAVES_NOMBRE = [
  "nombre_grupo",
  "nombre_categoria",
  "nombre_meta",
  "titulo",
];

/** Montos (en pesos) que trae un hallazgo en `datos`. */
function montosDeHallazgo(hallazgo: FilaHallazgo): number[] {
  const datos = hallazgo.datos ?? {};
  const montos: number[] = [];
  for (const clave of CLAVES_MONTO) {
    const valor = datos[clave];
    if (typeof valor === "number" && Number.isFinite(valor)) montos.push(valor);
  }
  return montos;
}

/** Nombre propio del hallazgo (grupo, categoría, meta o título), o null. */
function nombreDeHallazgo(hallazgo: FilaHallazgo): string | null {
  const datos = hallazgo.datos ?? {};
  for (const clave of CLAVES_NOMBRE) {
    const valor = datos[clave];
    if (typeof valor === "string" && valor.length > 0) return valor;
  }
  return null;
}

/** La meta a la que le falta menos tiempo al ritmo actual. */
function metaMasCercana(perfil: PerfilFinanciero): MetaPerfil | null {
  const conPlazo = perfil.metas.filter((meta) =>
    meta.meses_al_ritmo_actual !== null
  );
  if (conPlazo.length === 0) return perfil.metas[0] ?? null;
  return conPlazo.reduce((mejor, meta) =>
    meta.meses_al_ritmo_actual! < mejor.meses_al_ritmo_actual! ? meta : mejor
  );
}

interface Contexto {
  lineas: string[];
  /** Cifras (ya en texto) que el LLM puede escribir. */
  cifras: string[];
  mayores: { nombre: string; monto: number }[];
}

/** Arma el contexto del consejo: perfil, dos grupos mayores y hallazgos. */
function construirContexto(
  perfil: PerfilFinanciero,
  hallazgos: FilaHallazgo[],
  grupos: ClasificadorGrupos,
): Contexto {
  const lineas: string[] = [];
  const cifras: string[] = [];
  const agregarMonto = (etiqueta: string, monto: number) => {
    const formateado = formatearCOP(monto);
    lineas.push(`${etiqueta}: ${formateado}`);
    cifras.push(...cifrasEnTexto(formateado));
  };

  if (perfil.ingreso_mensual !== null) {
    agregarMonto("Ingreso mensual", perfil.ingreso_mensual);
  }
  if (perfil.gasto_mensual > 0) {
    agregarMonto("Gasto mensual", perfil.gasto_mensual);
  }
  if (perfil.excedente_mensual !== null) {
    const excedente = perfil.excedente_mensual;
    lineas.push(
      excedente > 0
        ? `Excedente al mes: ${formatearCOP(excedente)}`
        : `Gastos por encima de los ingresos: ${formatearCOP(-excedente)}`,
    );
    cifras.push(...cifrasEnTexto(formatearCOP(-excedente)));
  }
  if (perfil.ahorro_mensual > 0) {
    agregarMonto("Ahorro al mes en metas", perfil.ahorro_mensual);
  }

  const mayores = gruposMayorGasto(perfil, grupos);
  mayores.forEach((grupo, indice) => {
    const etiqueta = indice === 0
      ? "Grupo donde más gastas"
      : "Segundo grupo donde más gastas";
    agregarMonto(`${etiqueta} ("${grupo.nombre}")`, grupo.monto);
  });

  const meta = metaMasCercana(perfil);
  if (meta !== null) {
    agregarMonto(`Meta ("${meta.nombre}") le falta`, meta.falta);
    if (meta.meses_al_ritmo_actual !== null) {
      lineas.push(
        `Meta ("${meta.nombre}") al ritmo actual: ${meta.meses_al_ritmo_actual} meses`,
      );
      cifras.push(String(meta.meses_al_ritmo_actual));
    }
  }

  for (const hallazgo of hallazgos) {
    const partes = [`Hallazgo ${hallazgo.tipo}`];
    const nombre = nombreDeHallazgo(hallazgo);
    if (nombre !== null) partes.push(`"${nombre}"`);
    for (const monto of montosDeHallazgo(hallazgo)) {
      const formateado = formatearCOP(monto);
      partes.push(formateado);
      cifras.push(...cifrasEnTexto(formateado));
    }
    lineas.push(partes.join(": "));
  }

  return { lineas, cifras, mayores };
}

// --- Lección relacionada ------------------------------------------------------

/**
 * Lección que se puede ofrecer: la más parecida al mensaje y, si ninguna
 * alcanza el umbral, la que el motor ya había sugerido en un hallazgo.
 */
function accionDeLeccion(
  mensaje: string,
  hallazgos: FilaHallazgo[],
  lecciones: FilaLeccion[],
): Accion | null {
  const porSimilitud = buscarLeccion(mensaje, lecciones);
  if (porSimilitud !== null) {
    return { tipo: "abrir_leccion", escalon_id: porSimilitud.leccion.id };
  }

  const idsValidos = new Set(lecciones.map((leccion) => leccion.id));
  for (const hallazgo of hallazgos) {
    if (hallazgo.tipo !== "leccion_sugerida") continue;
    const escalonId = hallazgo.datos?.["escalon_id"];
    if (typeof escalonId === "string" && idsValidos.has(escalonId)) {
      return { tipo: "abrir_leccion", escalon_id: escalonId };
    }
  }
  return null;
}

// --- Distribución del dinero (cálculo puro) ----------------------------------

/**
 * Pregunta por cómo repartir el dinero: "dividir", "distribuir", "repartir",
 * "presupuesto", "plan para el mes", "cuánto para cada cosa", "cómo organizo mi
 * plata". "porcentaje" solo cuenta acompañado de "cada", "destinar", "dividir"
 * o "repartir" (así "si ahorro el 15 %" o "qué porcentaje se me va en deudas"
 * no entran). Se aplica sobre el texto en minúsculas y sin tildes.
 */
export const RE_DISTRIBUCION = new RegExp(
  [
    String.raw`\b(?:dividir|divido|distribuir|distribuyo|repartir|reparto|presupuesto|presupuestar)\b`,
    String.raw`\bplan\b[^.!?]{0,40}\bmes\b`,
    String.raw`\badministr(?:ar|o)\b[^.!?]{0,40}\b(?:mes|quincena)\b`,
    String.raw`\bcuanto\s+(?:para|a|le\s+pongo\s+a|le\s+doy\s+a)\s+cada\b`,
    String.raw`\b(?:organizo|organizar|reparto|divido|distribuyo)\s+(?:mi|mis)\s+(?:plata|dinero|sueldo|salario|ingresos?)\b`,
    String.raw`\bporcentajes?\b[\s\S]*\b(?:cada|destinar|destino|dividir|repartir)\b`,
    String.raw`\b(?:cada|destinar|destino|dividir|repartir)\b[\s\S]*\bporcentajes?\b`,
  ].join("|"),
);

/** true si el mensaje pide cómo repartir el dinero. */
export function esDistribucion(mensaje: string): boolean {
  return RE_DISTRIBUCION.test(minusculasSinTildes(mensaje));
}

/**
 * Grupos de gasto que cuentan como NECESIDADES en la referencia 50/30/20:
 * Mercado (1), Vivienda y servicios (4), Hogar (5), Salud (6), Transporte (7),
 * Celular e internet (8), Educación (10) y Obligaciones y transferencias (13).
 * El resto (licor, ropa, entretenimiento, comidas fuera, otros) son gustos.
 */
export const GRUPOS_NECESIDADES = new Set([1, 4, 5, 6, 7, 8, 10, 13]);

export interface ParteDistribucion {
  nombre: "Necesidades" | "Gustos" | "Ahorro";
  porcentaje: number;
  /** Monto sobre la base; null si no hay base (sin ingresos ni monto). */
  monto: number | null;
  ejemplos: string;
}

export interface Distribucion {
  /** Monto que se reparte; null si no hay ingresos ni monto en el mensaje. */
  base: number | null;
  /** De dónde salió la base. */
  origen_base: "mensaje" | "ingreso" | null;
  /** Referencia 50/30/20 sobre la base. */
  partes: ParteDistribucion[];
  /** Necesidades actuales como % del ingreso; null si no hay ingreso o gasto. */
  necesidades_actual_pct: number | null;
  necesidades_actual_monto: number | null;
  /** Reparto ajustado si las necesidades ya pasan del 50 %; null si no hace falta. */
  ajuste: { necesidades: number; gustos: number; ahorro: number } | null;
  /**
   * true si las necesidades ya se comen casi todo el ingreso (más del
   * MAX_NECESIDADES_AJUSTE %): ahí no tiene sentido proponer un reparto, toca
   * bajar gastos o subir ingresos.
   */
  necesidades_criticas: boolean;
  /** Excedente mensual del perfil (para avisar si hay que equilibrar). */
  excedente: number | null;
}

/** Por encima de este % de necesidades no se propone un reparto ajustado. */
export const MAX_NECESIDADES_AJUSTE = 85;

/** Monto de una parte: a miles cerrados si la base es de $100.000 o más. */
function montoParte(base: number, porcentaje: number): number {
  const exacto = (base * porcentaje) / 100;
  return base >= 100_000 ? Math.round(exacto / 1000) * 1000 : Math.round(exacto);
}

/** Redondea hacia arriba a múltiplos de 5. */
function arribaA5(valor: number): number {
  return Math.min(100, Math.ceil(valor / 5) * 5);
}

/** Redondea al múltiplo de 5 más cercano. */
function cercanoA5(valor: number): number {
  return Math.round(valor / 5) * 5;
}

/**
 * Monto que el usuario menciona para repartir ("mis 300", "1.200.000"). Un
 * número pequeño sin unidad se entiende en miles ("300" → $300.000). Se ignora
 * si es absurdo frente al ingreso (más de 10 veces).
 */
export function baseMencionada(
  mensaje: string,
  ingreso: number | null,
): number | null {
  const montos = extraerMontos(mensaje).map((monto) =>
    monto.valor > 0 && monto.valor < 10_000 ? monto.valor * 1000 : monto.valor
  ).filter((valor) => valor >= 10_000);
  if (montos.length === 0) return null;
  const valor = Math.max(...montos);
  if (ingreso !== null && ingreso > 0 && valor > ingreso * 10) return null;
  return valor;
}

/**
 * Referencia 50/30/20 (necesidades, gustos, ahorro) sobre el monto que el
 * usuario menciona o, si no menciona ninguno, sobre su ingreso mensual. Si sus
 * necesidades actuales ya pasan del 50 % del ingreso, propone un reparto
 * ajustado: necesidades en su nivel actual (redondeado a 5) y el resto 60/40
 * entre gustos y ahorro.
 */
export function calcularDistribucion(
  perfil: PerfilFinanciero,
  mensaje: string,
): Distribucion {
  const ingreso = perfil.ingreso_mensual;
  const mencionada = baseMencionada(mensaje, ingreso);
  const base = mencionada ?? (ingreso !== null && ingreso > 0 ? ingreso : null);
  const origen_base = mencionada !== null ? "mensaje" : base !== null ? "ingreso" : null;

  const referencia: [ParteDistribucion["nombre"], number, string][] = [
    ["Necesidades", 50, "mercado, vivienda, servicios, transporte y deudas"],
    ["Gustos", 30, "comida fuera, salidas, ropa y entretenimiento"],
    ["Ahorro", 20, "fondo de emergencia y metas"],
  ];
  const partes = referencia.map(([nombre, porcentaje, ejemplos]) => ({
    nombre,
    porcentaje,
    monto: base !== null ? montoParte(base, porcentaje) : null,
    ejemplos,
  }));

  let necesidadesMonto = 0;
  for (const [grupoId, monto] of perfil.gasto_mensual_por_grupo) {
    if (GRUPOS_NECESIDADES.has(grupoId)) necesidadesMonto += monto;
  }
  const necesidades_actual_pct = ingreso !== null && ingreso > 0 && necesidadesMonto > 0
    ? Math.round((necesidadesMonto / ingreso) * 100)
    : null;

  let ajuste: Distribucion["ajuste"] = null;
  const necesidades_criticas = necesidades_actual_pct !== null &&
    necesidades_actual_pct > MAX_NECESIDADES_AJUSTE;
  if (
    necesidades_actual_pct !== null && necesidades_actual_pct > 50 &&
    !necesidades_criticas
  ) {
    const necesidades = arribaA5(necesidades_actual_pct);
    const resto = 100 - necesidades;
    const ahorro = cercanoA5(resto * 0.4);
    ajuste = { necesidades, gustos: resto - ahorro, ahorro };
  }

  return {
    base,
    origen_base,
    partes,
    necesidades_actual_pct,
    necesidades_actual_monto: necesidades_actual_pct !== null
      ? Math.round(necesidadesMonto)
      : null,
    ajuste,
    necesidades_criticas,
    excedente: perfil.excedente_mensual,
  };
}

/** Texto de la distribución (plantilla y explicación base para Gemini). */
export function textoDistribucion(dist: Distribucion): string {
  const sobre = dist.base !== null
    ? dist.origen_base === "mensaje"
      ? ` sobre tus **${formatearCOP(dist.base)}**`
      : ` sobre tu ingreso de **${formatearCOP(dist.base)}** al mes`
    : "";
  const inicio = dist.excedente !== null && dist.excedente <= 0
    ? `Antes de repartir, ojo: hoy **${fraseMargen(dist.excedente)}**, así que lo primero es equilibrar. Como referencia, la regla 50/30/20${sobre} sería:`
    : `Una referencia útil es la regla 50/30/20${sobre}:`;

  const vinetas = dist.partes.map((parte) =>
    parte.monto !== null
      ? `**${parte.nombre} (${parte.porcentaje} %): ${formatearCOP(parte.monto)}**, para ${parte.ejemplos}`
      : `**${parte.nombre} (${parte.porcentaje} %)**, para ${parte.ejemplos}`
  );
  if (dist.necesidades_criticas && dist.necesidades_actual_monto !== null) {
    vinetas.push(
      `Hoy tus necesidades ya son el **${dist.necesidades_actual_pct} %** de tu ingreso (**${formatearCOP(dist.necesidades_actual_monto)}**): antes de repartir, toca bajar esos gastos o subir tus ingresos`,
    );
  } else if (dist.ajuste !== null && dist.necesidades_actual_monto !== null) {
    vinetas.push(
      `Hoy tus necesidades ya son el **${dist.necesidades_actual_pct} %** de tu ingreso (**${formatearCOP(dist.necesidades_actual_monto)}**); un reparto realista para empezar es **${dist.ajuste.necesidades} / ${dist.ajuste.gustos} / ${dist.ajuste.ahorro}**`,
    );
  }

  const cierre = dist.base === null
    ? "Registra tus ingresos y te digo cuánto sería en pesos. Es una referencia general, no una regla fija."
    : "Es una referencia general, no una regla fija: ajústala a tu realidad.";
  return formatoBloques(inicio, vinetas, cierre);
}

// --- Tema concreto (glosario) ------------------------------------------------

/** Productos de crédito: se comparan por costo, no por rendimiento. */
const RE_TEMA_CREDITO =
  /credito|tarjeta|leasing|avance|diferir|pago-minimo|cuota-manejo|usura|deuda/;

/** Pide que le recomienden cuál elegir ("¿en cuál?", "¿qué banco?"). */
const RE_PIDE_ENTIDAD =
  /\b(?:cual|cuales|que banco|que entidad|donde|en que banco|recomiendas|recomiendame|me recomiendas)\b/;

/** Primera frase de un texto. */
function primeraFrase(texto: string): string {
  const fin = texto.search(/[.!?](\s|$)/);
  return fin === -1 ? texto.trim() : texto.slice(0, fin + 1).trim();
}

/**
 * Plantilla cuando la pregunta nombra un concepto del glosario: qué es, cómo
 * encaja con su situación y cómo comparar, sin recomendar entidades.
 */
function plantillaTema(
  entrada: EntradaGlosario,
  mensaje: string,
  perfil: PerfilFinanciero,
): string {
  const pideEntidad = RE_PIDE_ENTIDAD.test(minusculasSinTildes(mensaje));
  const credito = RE_TEMA_CREDITO.test(entrada.id);
  const inicio = pideEntidad
    ? `Sobre el ${entrada.termino}: no te puedo recomendar una entidad en particular, pero sí cómo decidir.`
    : `Sobre el ${entrada.termino}, esto es lo que conviene mirar:`;

  const vinetas: string[] = [primeraFrase(entrada.definicion)];
  const excedente = perfil.excedente_mensual;
  if (excedente !== null && excedente <= 0) {
    vinetas.push(
      `antes de pensar en esto, equilibra tus gastos: hoy **${fraseMargen(excedente)}**`,
    );
  } else if (excedente !== null && !credito) {
    vinetas.push(
      `hoy te quedan **${formatearCOP(excedente)}** al mes; usa solo la plata que no necesites para tus gastos ni para emergencias`,
    );
  }
  vinetas.push(
    credito
      ? "compara la **tasa efectiva anual**, la cuota de manejo y que la cuota te quepa en el presupuesto"
      : "ten primero un fondo de emergencia y luego compara la **tasa efectiva anual**, el plazo y que la entidad esté vigilada por la Superintendencia Financiera",
  );
  return formatoBloques(
    inicio,
    vinetas,
    `Si quieres, te explico más sobre el ${entrada.termino}.`,
  );
}

/** Tema del glosario que nombra la pregunta, con un umbral más estricto. */
function temaDelMensaje(mensaje: string): EntradaGlosario | null {
  const coincidencia = buscarGlosario(mensaje);
  return coincidencia !== null && coincidencia.puntaje >= UMBRAL_TEMA_CONSEJO
    ? coincidencia.entrada
    : null;
}

// --- Plantilla de respaldo ----------------------------------------------------

/**
 * Plantilla de respaldo (sin LLM). Si es una decisión ("¿la meto a un CDT o
 * abono a la deuda?"), da criterios para decidir; si no, dos pasos armados con
 * los datos del usuario.
 */
function plantillaConsejo(
  perfil: PerfilFinanciero,
  mayores: { nombre: string; monto: number }[],
  decision: boolean,
  tema: EntradaGlosario | null = null,
  mensaje = "",
): string {
  // Si la pregunta nombra un concepto, la respuesta habla de ESE tema.
  if (tema !== null && !decision) return plantillaTema(tema, mensaje, perfil);

  const pasos: string[] = [];
  const excedente = perfil.excedente_mensual;
  const fraseEquilibrar = excedente !== null && excedente <= 0
    ? `equilibra primero tus gastos con tus ingresos: hoy **${
      fraseMargen(excedente)
    }**`
    : null;

  // Ante una decisión, el orden correcto de criterios para elegir.
  if (decision) {
    if (fraseEquilibrar !== null) pasos.push(fraseEquilibrar);
    pasos.push(
      "si la deuda tiene una tasa alta, abonar a esa deuda suele convenir más que lo que te rinda un ahorro",
    );
    pasos.push(
      "ten primero un fondo de emergencia para no volver a endeudarte sin necesidad",
    );
    pasos.push(
      "compara la tasa efectiva anual de la deuda con la que te ofrezca el ahorro y elige la más alta",
    );
    return formatoBloques(
      "Para decidir, mira estos criterios en orden:",
      pasos,
      "Con eso puedes comparar las opciones que te ofrezcan.",
    );
  }

  if (fraseEquilibrar !== null) pasos.push(fraseEquilibrar);

  if (mayores.length > 0) {
    pasos.push(
      `revisa "${mayores[0].nombre}", donde más gastas (**${
        formatearCOP(mayores[0].monto)
      }** al mes): ahí tienes el mayor margen para ajustar`,
    );
  }

  const meta = metaMasCercana(perfil);
  if (meta !== null) {
    const ritmo = meta.meses_al_ritmo_actual;
    pasos.push(
      `para "${meta.nombre}" te faltan **${formatearCOP(meta.falta)}**` +
        (ritmo !== null ? `; a tu ritmo actual llegarías en ${ritmo} meses` : ""),
    );
  }

  const elegidos = pasos.slice(0, 2);
  if (elegidos.length === 0) {
    return "Registra tus ingresos y tus gastos de este mes y con eso te doy pasos concretos.";
  }
  return formatoBloques(
    elegidos.length === 1
      ? "Un paso concreto para empezar:"
      : "Dos pasos concretos para empezar:",
    elegidos,
    "Empieza por el primero y me cuentas cómo te va.",
  );
}

// --- Respuesta ----------------------------------------------------------------

/**
 * Valida el texto del LLM y además rechaza que hable de impuestos o de la DIAN
 * cuando el usuario no preguntó por eso (pasaba: "recuerda consultar a la DIAN").
 */
function validarConsejo(
  texto: string,
  cifras: string[],
  mensaje: string,
) {
  const base = validarTextoLLM(texto, cifras, LLM_MAX_CARACTERES_CONSEJO);
  if (!base.valido) return base;
  const preguntaImpuestos = RE_TEMA_IMPUESTOS.test(minusculasSinTildes(mensaje));
  if (!preguntaImpuestos && RE_TEMA_IMPUESTOS.test(minusculasSinTildes(texto))) {
    return { valido: false, motivo: "tema_no_pedido" };
  }
  return base;
}

/** Cifras de la explicación base que deben aparecer tal cual en la redacción. */
function montosObligatorios(dist: Distribucion): string[] {
  return dist.partes
    .filter((parte) => parte.monto !== null)
    .map((parte) => formatearCOP(parte.monto!));
}

/** Respuesta del caso "distribución del dinero". */
async function responderDistribucion(
  mensaje: string,
  perfil: PerfilFinanciero,
  deps: DepsConsejo,
): Promise<RespuestaIntencion> {
  const dist = calcularDistribucion(perfil, mensaje);
  const base = textoDistribucion(dist);
  const obligatorios = montosObligatorios(dist);

  const resultado = await generarConGemini(
    {
      instruccion: INSTRUCCION_DISTRIBUCION,
      mensaje: `Pregunta del usuario: "${mensaje}"\nExplicación base:\n${base}`,
    },
    (texto) => {
      const validacion = validarConsejo(
        texto,
        [...cifrasEnTexto(base), ...cifrasEnTexto(mensaje)],
        mensaje,
      );
      if (!validacion.valido) return validacion;
      const faltante = obligatorios.find((cifra) => !texto.includes(cifra));
      return faltante === undefined
        ? validacion
        : { valido: false, motivo: "falta_cifra_obligatoria" };
    },
    deps.fetchFn,
    { clave: deps.claveLLM },
  );

  return {
    respuesta: resultado.texto !== null ? resultado.texto.trim() : base,
    origen: resultado.texto !== null ? "llm" : "plantilla",
    motivo: resultado.texto !== null
      ? "consejo:distribucion"
      : `consejo:distribucion:${resultado.motivo}`,
    aviso: AVISO_CONSEJO,
  };
}

/** Respuesta de la intención pedir_consejo. */
export async function responderConsejo(
  mensaje: string,
  usuarioId: string,
  deps: DepsConsejo,
  ahora: Date = new Date(),
): Promise<RespuestaIntencion> {
  const perfil = await leerPerfilFinanciero(usuarioId, deps.repositorio, ahora);

  // Distribución del dinero: el código calcula y Gemini solo redacta.
  if (esDistribucion(mensaje)) {
    return await responderDistribucion(mensaje, perfil, deps);
  }

  const desde = inicioDelDiaBogota(
    sumarDias(hoyEnBogota(ahora), -DIAS_HALLAZGOS),
  );
  const hallazgos = await deps.repositorio.leerHallazgosRecientes(
    usuarioId,
    desde,
  );
  const lecciones = await deps.repositorio.leerLeccionesValidas();
  const contexto = construirContexto(perfil, hallazgos, deps.grupos);
  const tema = temaDelMensaje(mensaje);
  const lineasTema = tema !== null
    ? `\nTema de la pregunta: ${tema.termino}. Qué es: ${primeraFrase(tema.definicion)}`
    : "";
  const notaImpuestos = RE_TEMA_IMPUESTOS.test(minusculasSinTildes(mensaje))
    ? "\nEl usuario pregunta por impuestos o centrales de riesgo: sugiere consultar a la DIAN o a la entidad."
    : "";

  const resultado = await generarConGemini(
    {
      instruccion: INSTRUCCION_CONSEJO,
      mensaje:
        `Pregunta del usuario (responde a esto primero): "${mensaje}"${lineasTema}${notaImpuestos}\nDatos del usuario:\n${contexto.lineas.join("\n")}`,
    },
    (texto) =>
      validarConsejo(
        texto,
        [
          ...contexto.cifras,
          ...cifrasEnTexto(mensaje),
          ...extraerMontos(mensaje).map((monto) => String(monto.valor)),
        ],
        mensaje,
      ),
    deps.fetchFn,
    { clave: deps.claveLLM },
  );

  const respuesta: RespuestaIntencion = {
    respuesta: resultado.texto !== null
      ? resultado.texto.trim()
      : plantillaConsejo(perfil, contexto.mayores, esDecision(mensaje), tema, mensaje),
    origen: resultado.texto !== null ? "llm" : "plantilla",
    motivo: resultado.texto !== null ? "consejo" : `consejo:${resultado.motivo}`,
    aviso: AVISO_CONSEJO,
  };

  const accion = accionDeLeccion(mensaje, hallazgos, lecciones);
  if (accion !== null) respuesta.accion = accion;
  return respuesta;
}

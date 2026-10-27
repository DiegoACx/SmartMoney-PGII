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
// ============================================================================

import {
  cifrasEnTexto,
  formatoBloques,
  formatearCOP,
  generarConGemini,
  validarTextoLLM,
} from "../_shared/gemini.ts";
import type { ClasificadorGrupos } from "./clasificadores.ts";
import { buscarLeccion } from "./conocimiento.ts";
import { esDecision } from "./decision.ts";
import { hoyEnBogota, inicioDelDiaBogota, sumarDias } from "./fechas.ts";
import { extraerMontos } from "./montos.ts";
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
  "Eres el asesor financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. Da 2 o 3 pasos concretos y aplicables, en español colombiano, tuteando y sin regaños. Usa esta estructura: una frase inicial que responda directo, de 2 a 3 viñetas que empiecen con \"- \" y una frase final corta; el texto, sin contar los símbolos de formato, debe quedar por debajo de 650 caracteres. Puedes poner en **negrita** las cifras clave. Usa SOLO las cifras del contexto y las que escribió el usuario, escritas igual; no inventes cifras, tasas ni plazos. No recomiendes bancos, productos financieros ni inversiones específicas. Si la decisión es entre productos financieros, da criterios generales: fondo de emergencia primero, pagar primero la deuda más cara y comparar la tasa efectiva anual. Si el tema son impuestos o reportes en centrales de riesgo, sugiere consultar a la DIAN o a la entidad. Si el excedente es cero o negativo, el primer paso siempre es equilibrar los gastos con los ingresos. No uses títulos, enlaces, imágenes, tablas, código ni HTML. Responde solo con el texto, sin comillas ni emojis.";

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
): string {
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

/** Respuesta de la intención pedir_consejo. */
export async function responderConsejo(
  mensaje: string,
  usuarioId: string,
  deps: DepsConsejo,
  ahora: Date = new Date(),
): Promise<RespuestaIntencion> {
  const perfil = await leerPerfilFinanciero(usuarioId, deps.repositorio, ahora);
  const desde = inicioDelDiaBogota(
    sumarDias(hoyEnBogota(ahora), -DIAS_HALLAZGOS),
  );
  const hallazgos = await deps.repositorio.leerHallazgosRecientes(
    usuarioId,
    desde,
  );
  const lecciones = await deps.repositorio.leerLeccionesValidas();
  const contexto = construirContexto(perfil, hallazgos, deps.grupos);

  const resultado = await generarConGemini(
    {
      instruccion: INSTRUCCION_CONSEJO,
      mensaje:
        `Pregunta del usuario: "${mensaje}"\nDatos del usuario:\n${contexto.lineas.join("\n")}`,
    },
    (texto) =>
      validarTextoLLM(
        texto,
        [
          ...contexto.cifras,
          ...cifrasEnTexto(mensaje),
          ...extraerMontos(mensaje).map((monto) => String(monto.valor)),
        ],
        LLM_MAX_CARACTERES_CONSEJO,
      ),
    deps.fetchFn,
    { clave: deps.claveLLM },
  );

  const respuesta: RespuestaIntencion = {
    respuesta: resultado.texto !== null
      ? resultado.texto.trim()
      : plantillaConsejo(perfil, contexto.mayores, esDecision(mensaje)),
    origen: resultado.texto !== null ? "llm" : "plantilla",
    motivo: resultado.texto !== null ? "consejo" : `consejo:${resultado.motivo}`,
    aviso: AVISO_CONSEJO,
  };

  const accion = accionDeLeccion(mensaje, hallazgos, lecciones);
  if (accion !== null) respuesta.accion = accion;
  return respuesta;
}

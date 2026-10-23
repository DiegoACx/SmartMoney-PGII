// ============================================================================
// SmartMoney · Chat IA · consultar_datos
// ----------------------------------------------------------------------------
// Responde con cifras reales del usuario (sin LLM, origen 'calculo'): totales
// del periodo, desglose por grupo o por categoría, o el avance de sus metas.
//
// Las consultas SIEMPRE se filtran por el usuario_id que salió del JWT. Las
// plantillas usan formatearCOP ($1.234.567).
// ============================================================================

import { normalizar } from "../_shared/clasificador_ngramas.ts";
import { formatearCOP } from "../_shared/gemini.ts";
import type { ClasificadorGrupos } from "./clasificadores.ts";
import {
  ETIQUETA_PERIODO,
  hoyEnBogota,
  interpretarPeriodo,
  interpretarTipo,
  PERIODO_PASADO,
  rangoDePeriodo,
  type Periodo,
} from "./fechas.ts";
import { fechaCorta, type FilaTransaccion, type RepositorioChat } from "./repositorio.ts";
import type { RespuestaIntencion } from "./tipos.ts";

/** Confianza mínima del clasificador de grupos para responder por un grupo. */
export const UMBRAL_GRUPO = 0.6;

export interface DepsConsultaDatos {
  repositorio: RepositorioChat;
  grupos: ClasificadorGrupos;
}

/** Palabras que no identifican un tema de gasto (solo hablan del total). */
const PALABRAS_GENERICAS = new Set([
  "cuanto", "cuanta", "cuantos", "cuantas", "llevo", "gaste", "gasto", "gastos",
  "gastado", "gastando", "he", "me", "mi", "mis", "en", "de", "del", "la", "el",
  "los", "las", "un", "una", "unos", "unas", "y", "o", "que", "este", "esta",
  "estos", "estas", "para", "por", "con", "sin", "mes", "meses", "semana",
  "semanas", "dia", "dias", "hoy", "ayer", "ano", "anio", "plata", "dinero",
  "lucas", "billete", "billetes", "presupuesto", "total", "mucho", "poco",
  "poca", "semanal", "mensual", "anual", "pasado", "pasada", "ultimo",
  "ultima", "recibido", "recibi", "gane", "ingreso", "ingresos", "egreso",
  "egresos", "movimiento", "movimientos", "plata", "es", "son", "vale", "van",
  "vamos", "mas", "menos", "tanto", "tan", "gracias",
]);

const RE_METAS = /\bmeta\b|\bmetas\b|ahorr|\bfalta\b|\bfaltan\b/;

/** ¿El mensaje aporta un tema de gasto concreto (no solo "gasto/plata")? */
function hayTemaEspecifico(mensajeNormalizado: string): boolean {
  return mensajeNormalizado
    .split(" ")
    .some((palabra) =>
      palabra.length > 2 && !PALABRAS_GENERICAS.has(palabra)
    );
}

/** Suma de los montos. */
function sumar(filas: FilaTransaccion[]): number {
  return filas.reduce((total, fila) => total + fila.monto, 0);
}

/** Montos por categoría, de mayor a menor. */
function porCategoria(
  filas: FilaTransaccion[],
  nombres: Map<string, string>,
): { nombre: string; monto: number }[] {
  const totales = new Map<string, number>();
  for (const fila of filas) {
    const id = fila.categoria_id ?? "sin-categoria";
    totales.set(id, (totales.get(id) ?? 0) + fila.monto);
  }
  return [...totales.entries()]
    .map(([id, monto]) => ({
      nombre: nombres.get(id) ?? "Sin categoría",
      monto,
    }))
    .sort((a, b) => b.monto - a.monto);
}

/** "A ($10), B ($5) y C ($3)" (o "A ($10)" si solo hay una). */
function listarTop(
  items: { nombre: string; monto: number }[],
  cuantos: number,
): string {
  const top = items.slice(0, cuantos).map((item) =>
    `${item.nombre} (${formatearCOP(item.monto)})`
  );
  if (top.length <= 1) return top.join("");
  return `${top.slice(0, -1).join(", ")} y ${top[top.length - 1]}`;
}

function respuestaSinDatos(periodo: Periodo, tipo: "ingreso" | "egreso"): string {
  const etiqueta = ETIQUETA_PERIODO[periodo].toLowerCase();
  const que = tipo === "ingreso" ? "ingresos" : "gastos";
  const verbo = tipo === "ingreso" ? "recibido" : "gastado";
  return `No veo ${que} tuyos ${etiqueta}. Cuando registres movimientos te muestro cuánto llevas ${verbo}.`;
}

/** Respuesta con el avance de las metas activas. */
async function responderMetas(
  usuarioId: string,
  deps: DepsConsultaDatos,
): Promise<RespuestaIntencion> {
  const metas = await deps.repositorio.leerMetasActivas(usuarioId);

  if (metas.length === 0) {
    return {
      respuesta:
        "Todavía no tienes metas de ahorro activas. Puedes crear una en la pestaña Metas y yo te ayudo a seguirla.",
      origen: "calculo",
      motivo: "metas_vacio",
      accion: { tipo: "ir_a", destino: "metas" },
    };
  }

  if (metas.length === 1) {
    const meta = metas[0];
    const faltante = Math.max(0, meta.monto_objetivo - meta.monto_actual);
    const porcentaje = meta.monto_objetivo > 0
      ? Math.round((meta.monto_actual / meta.monto_objetivo) * 100)
      : 0;
    const limite = meta.fecha_limite
      ? ` La fecha límite es el ${fechaCorta(meta.fecha_limite)}.`
      : "";
    return {
      respuesta:
        `En "${meta.nombre}" llevas ${formatearCOP(meta.monto_actual)} de ${formatearCOP(meta.monto_objetivo)}, o sea el ${porcentaje} %. Te faltan ${formatearCOP(faltante)}.${limite}`,
      origen: "calculo",
      motivo: "metas_una",
      accion: { tipo: "ir_a", destino: "metas" },
    };
  }

  const lineas = metas.map((meta) => {
    const porcentaje = meta.monto_objetivo > 0
      ? Math.round((meta.monto_actual / meta.monto_objetivo) * 100)
      : 0;
    const faltante = Math.max(0, meta.monto_objetivo - meta.monto_actual);
    return `• ${meta.nombre}: ${porcentaje} % (${formatearCOP(meta.monto_actual)} de ${formatearCOP(meta.monto_objetivo)}, faltan ${formatearCOP(faltante)}).`;
  });
  return {
    respuesta: `Así van tus metas de ahorro:\n${lineas.join("\n")}`,
    origen: "calculo",
    motivo: "metas_varias",
    accion: { tipo: "ir_a", destino: "metas" },
  };
}

/** Respuesta de la intención consultar_datos. */
export async function responderConsultaDatos(
  mensaje: string,
  usuarioId: string,
  deps: DepsConsultaDatos,
  ahora: Date = new Date(),
): Promise<RespuestaIntencion> {
  const normalizado = normalizar(mensaje);
  const periodo = interpretarPeriodo(normalizado);
  const tipo = interpretarTipo(normalizado);
  const hoy = hoyEnBogota(ahora);

  if (RE_METAS.test(normalizado)) {
    return await responderMetas(usuarioId, deps);
  }

  const { desde, hasta } = rangoDePeriodo(periodo, hoy);
  const [filas, categorias] = await Promise.all([
    deps.repositorio.leerTransacciones(usuarioId, desde, hasta, tipo),
    deps.repositorio.leerCategorias(usuarioId),
  ]);

  if (filas.length === 0) {
    return {
      respuesta: respuestaSinDatos(periodo, tipo),
      origen: "calculo",
      motivo: "sin_datos",
      accion: { tipo: "ir_a", destino: "movimientos" },
    };
  }

  const nombres = new Map(categorias.map((c) => [c.id, c.nombre]));
  const gruposPorCategoria = new Map(
    categorias.map((c) => [c.id, c.grupo_id]),
  );
  const total = sumar(filas);
  const etiqueta = ETIQUETA_PERIODO[periodo];
  const pasado = PERIODO_PASADO[periodo];

  // Grupo concreto solo si el mensaje habla de un tema y el modelo está seguro.
  let grupoNombre: string | null = null;
  let grupoMonto = 0;
  if (tipo === "egreso" && hayTemaEspecifico(normalizado)) {
    const prediccion = deps.grupos.predecir(mensaje);
    if (prediccion !== null && prediccion.confianza >= UMBRAL_GRUPO) {
      grupoNombre = deps.grupos.nombreGrupo(prediccion.grupo_id);
      grupoMonto = sumar(
        filas.filter((fila) =>
          fila.categoria_id !== null &&
          gruposPorCategoria.get(fila.categoria_id) === prediccion.grupo_id
        ),
      );
    }
  }

  const items = porCategoria(filas, nombres);

  if (tipo === "ingreso") {
    const detalle = items.length > 0
      ? ` Los principales: ${listarTop(items, 3)}.`
      : "";
    return {
      respuesta: `${etiqueta} recibiste ${formatearCOP(total)} en ingresos.${detalle}`,
      origen: "calculo",
      motivo: grupoNombre ?? "total_ingresos",
    };
  }

  if (grupoNombre !== null && grupoMonto > 0 && total > 0) {
    const porcentaje = Math.round((grupoMonto / total) * 100);
    return {
      respuesta:
        `${etiqueta} ${pasado ? "gastaste" : "llevas"} ${formatearCOP(total)} en gastos, el ${porcentaje} % en ${grupoNombre}.`,
      origen: "calculo",
      motivo: `grupo:${grupoNombre}`,
    };
  }

  const detalle = items.length > 0
    ? ` Lo que más pesa: ${listarTop(items, 3)}.`
    : "";
  return {
    respuesta:
      `${etiqueta} ${pasado ? "gastaste" : "llevas"} ${formatearCOP(total)} en gastos.${detalle}`,
    origen: "calculo",
    motivo: "total_egresos",
  };
}

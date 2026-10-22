// ============================================================================
// SmartMoney · Motor de recomendaciones · Plantillas de texto
// ----------------------------------------------------------------------------
// Textos en español colombiano, con tuteo ("tú"), cifras en pesos con separador
// de miles y sin jerga técnica. Funciones PURAS: solo reciben un hallazgo ya
// puntuado con sus datos y devuelven el texto.
// ============================================================================

import type { TipoHallazgo } from "./config.ts";
import type { HallazgoPuntuado } from "./puntaje.ts";

const MESES = [
  "enero",
  "febrero",
  "marzo",
  "abril",
  "mayo",
  "junio",
  "julio",
  "agosto",
  "septiembre",
  "octubre",
  "noviembre",
  "diciembre",
];

/** '$1.234.567' (redondeado al peso, separador de miles con punto). */
export function formatearCOP(valor: number): string {
  const redondeado = Math.round(Math.abs(valor));
  const conPuntos = String(redondeado).replace(/\B(?=(\d{3})+(?!\d))/g, ".");
  return `${valor < 0 ? "-" : ""}$${conPuntos}`;
}

/** '2026-10-12' → '12 de octubre'. */
export function formatearFecha(fecha: string): string {
  const anio = fecha.slice(0, 4);
  const mes = Number(fecha.slice(5, 7));
  const dia = Number(fecha.slice(8, 10));
  return `${dia} de ${MESES[mes - 1]} de ${anio}`;
}

/** '2026-10' → 'octubre de 2026'. */
export function formatearMes(mes: string): string {
  const anio = mes.slice(0, 4);
  const numero = Number(mes.slice(5, 7));
  return `${MESES[numero - 1]} de ${anio}`;
}

function numero(datos: Record<string, unknown>, clave: string): number {
  const valor = datos[clave];
  return typeof valor === "number" && Number.isFinite(valor) ? valor : 0;
}

function texto(datos: Record<string, unknown>, clave: string): string {
  const valor = datos[clave];
  return valor === null || valor === undefined ? "" : String(valor);
}

const PLANTILLAS: Record<TipoHallazgo, (h: HallazgoPuntuado) => string> = {
  sobregasto_categoria: (h) => {
    const grupo = texto(h.datos, "nombre_grupo");
    return `En ${grupo} llevas ${formatearCOP(numero(h.datos, "gastado_mes"))} este mes y al ritmo que vas cerrarías en ${formatearCOP(numero(h.datos, "proyeccion"))}, mientras que tu nivel normal es ${formatearCOP(numero(h.datos, "normal_mensual"))}. Bájale el ritmo en los ${numero(h.datos, "dias_restantes")} días que quedan del mes.`;
  },
  gasto_anomalo: (h) => {
    const categoria = texto(h.datos, "nombre_categoria");
    return `Registraste un gasto de ${formatearCOP(numero(h.datos, "monto"))} en ${categoria} el ${formatearFecha(texto(h.datos, "fecha"))}, bastante más alto de lo que sueles gastar ahí (${formatearCOP(numero(h.datos, "mediana_semanal"))} por semana). Revisa si fue un gasto puntual o si se te coló un registro repetido.`;
  },
  aporte_meta: (h) => {
    const meta = texto(h.datos, "nombre_meta");
    return `Para cumplir ${meta} antes del ${formatearFecha(texto(h.datos, "fecha_limite"))} te conviene apartar ${formatearCOP(numero(h.datos, "aporte_sugerido"))} al mes, y en los últimos 30 días apartaste ${formatearCOP(numero(h.datos, "ritmo_30_dias"))}. Intenta ponerte al día este mes.`;
  },
  leccion_sugerida: (h) => {
    const grupo = texto(h.datos, "nombre_grupo");
    const titulo = texto(h.datos, "titulo");
    if (texto(h.datos, "motivo") === "siguiente_en_ruta") {
      return `Para manejar mejor tus gastos en ${grupo}, sigue tu ruta de aprendizaje: tu próxima lección es «${titulo}».`;
    }
    return `Este mes vas por encima en ${grupo}. La lección «${titulo}» te puede ayudar a manejarlo.`;
  },
  logro: (h) => {
    const grupo = texto(h.datos, "nombre_grupo");
    const normal = numero(h.datos, "normal_mensual");
    const gasto = numero(h.datos, "gasto_mes");
    const porcentaje = normal > 0
      ? Math.round((1 - gasto / normal) * 100)
      : 0;
    return `¡Buen trabajo! En ${formatearMes(texto(h.datos, "mes"))} gastaste ${formatearCOP(gasto)} en ${grupo}, un ${porcentaje}% por debajo de lo normal para ti (${formatearCOP(normal)}). Sigue así.`;
  },
  riesgo_fin_de_mes: (h) => {
    return `Con lo que llevas gastado y tus ingresos del mes, si sigues a este ritmo te faltarían ${formatearCOP(numero(h.datos, "faltante"))} para terminar el mes. Baja el ritmo en estos ${numero(h.datos, "dias_restantes")} días.`;
  },
};

/** Texto de la recomendación según su tipo. */
export function textoRecomendacion(hallazgo: HallazgoPuntuado): string {
  return PLANTILLAS[hallazgo.tipo](hallazgo);
}

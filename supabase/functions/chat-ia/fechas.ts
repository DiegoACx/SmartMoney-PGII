// ============================================================================
// SmartMoney · Chat IA · Periodos y fechas (hora de Colombia)
// ----------------------------------------------------------------------------
// Traduce expresiones del mensaje ("esta semana", "el mes pasado"…) a un rango
// de fechas [desde, hasta] en la zona horaria America/Bogota, y detecta si el
// usuario habla de ingresos o de egresos.
//
// Este módulo no toca Supabase ni la red: se prueba con `deno test`.
// ============================================================================

import { normalizar } from "../_shared/clasificador_ngramas.ts";

/** Zona horaria de referencia. */
export const ZONA_HORARIA = "America/Bogota";

/**
 * Desplazamiento fijo de Colombia. No hay horario de verano, así que '−05:00'
 * es válido todo el año.
 */
const OFFSET_BOGOTA = "-05:00";

/** Periodos que entiende el chat. */
export type Periodo =
  | "hoy"
  | "ayer"
  | "esta_semana"
  | "semana_pasada"
  | "este_mes"
  | "mes_pasado"
  | "este_anio";

/** 'YYYY-MM-DD' del día actual en Bogotá. */
export function hoyEnBogota(ahora: Date = new Date()): string {
  return ahora.toLocaleDateString("en-CA", { timeZone: ZONA_HORARIA });
}

/** Medianoche de hoy en Bogotá, en ISO UTC (para filtrar creado_en). */
export function inicioDelDiaBogota(fecha: string): string {
  return new Date(`${fecha}T00:00:00${OFFSET_BOGOTA}`).toISOString();
}

/** Base UTC de una fecha 'YYYY-MM-DD' (sin arrastrar la zona del servidor). */
export function aFechaUTC(fecha: string): Date {
  const [anio, mes, dia] = fecha.split("-").map(Number);
  return new Date(Date.UTC(anio, mes - 1, dia));
}

export function aTextoFecha(fecha: Date): string {
  return fecha.toISOString().slice(0, 10);
}

export function sumarDias(fecha: string, dias: number): string {
  const resultado = aFechaUTC(fecha);
  resultado.setUTCDate(resultado.getUTCDate() + dias);
  return aTextoFecha(resultado);
}

/** Lunes de la semana a la que pertenece la fecha. */
export function lunesDeSemana(fecha: string): string {
  const dia = aFechaUTC(fecha).getUTCDay(); // 0 = domingo
  const desplazamiento = dia === 0 ? -6 : 1 - dia;
  return sumarDias(fecha, desplazamiento);
}

/** Mes anterior en formato 'YYYY-MM'. */
export function mesAnterior(mes: string): string {
  const anio = Number(mes.slice(0, 4));
  const numero = Number(mes.slice(5, 7));
  if (numero === 1) return `${anio - 1}-12`;
  return `${anio}-${String(numero - 1).padStart(2, "0")}`;
}

/** Último día ('YYYY-MM-DD') del mes 'YYYY-MM'. */
export function ultimoDiaDeMes(mes: string): string {
  const anio = Number(mes.slice(0, 4));
  const numero = Number(mes.slice(5, 7));
  const dia = new Date(Date.UTC(anio, numero, 0)).getUTCDate();
  return `${mes}-${String(dia).padStart(2, "0")}`;
}

/** Rango [desde, hasta] (ambos inclusive) del periodo pedido. */
export function rangoDePeriodo(
  periodo: Periodo,
  hoy: string,
): { desde: string; hasta: string } {
  switch (periodo) {
    case "hoy":
      return { desde: hoy, hasta: hoy };
    case "ayer": {
      const ayer = sumarDias(hoy, -1);
      return { desde: ayer, hasta: ayer };
    }
    case "esta_semana":
      return { desde: lunesDeSemana(hoy), hasta: hoy };
    case "semana_pasada": {
      const lunes = sumarDias(lunesDeSemana(hoy), -7);
      return { desde: lunes, hasta: sumarDias(lunes, 6) };
    }
    case "este_mes":
      return { desde: `${hoy.slice(0, 7)}-01`, hasta: hoy };
    case "mes_pasado": {
      const mes = mesAnterior(hoy.slice(0, 7));
      return { desde: `${mes}-01`, hasta: ultimoDiaDeMes(mes) };
    }
    case "este_anio":
      return { desde: `${hoy.slice(0, 4)}-01-01`, hasta: hoy };
  }
}

const RE_MES_PASADO = /\bmes pasado\b|\bmes anterior\b|\bultimo mes\b/;
const RE_SEMANA_PASADA = /\bsemana pasada\b|\bsemana anterior\b|\bultima semana\b/;
const RE_AYER = /\bayer\b/;
const RE_HOY = /\bhoy\b/;
const RE_ESTA_SEMANA = /\besta semana\b|\bsemana\b|\bsemanal\b/;
const RE_ESTE_ANIO = /\beste ano\b|\beste anio\b|\bano\b|\banio\b|\banual\b/;
const RE_ESTE_MES = /\beste mes\b|\bmes\b|\bmensual\b/;

/** Periodo al que se refiere el mensaje (por defecto: este mes). */
export function interpretarPeriodo(mensajeNormalizado: string): Periodo {
  if (RE_MES_PASADO.test(mensajeNormalizado)) return "mes_pasado";
  if (RE_SEMANA_PASADA.test(mensajeNormalizado)) return "semana_pasada";
  if (RE_AYER.test(mensajeNormalizado)) return "ayer";
  if (RE_HOY.test(mensajeNormalizado)) return "hoy";
  if (RE_ESTA_SEMANA.test(mensajeNormalizado)) return "esta_semana";
  if (RE_ESTE_ANIO.test(mensajeNormalizado)) return "este_anio";
  if (RE_ESTE_MES.test(mensajeNormalizado)) return "este_mes";
  return "este_mes";
}

const RE_INGRESO =
  /\bgane\b|\bgano\b|\bganancia\b|\bganancias\b|\brecibi\b|\brecibido\b|\brecibo\b|\bingreso\b|\bingresos\b|\bcobre\b|me entro|me entraron|\bentraron\b|me pagaron|\bme pago\b|me consignaron|\bconsignaron\b/;

/** Tipo de movimiento del que habla el mensaje: 'ingreso' o 'egreso'. */
export function interpretarTipo(mensajeNormalizado: string): "ingreso" | "egreso" {
  return RE_INGRESO.test(mensajeNormalizado) ? "ingreso" : "egreso";
}

/** Etiqueta del periodo para las plantillas de respuesta. */
export const ETIQUETA_PERIODO: Record<Periodo, string> = {
  hoy: "Hoy",
  ayer: "Ayer",
  esta_semana: "Esta semana",
  semana_pasada: "La semana pasada",
  este_mes: "Este mes",
  mes_pasado: "El mes pasado",
  este_anio: "Este año",
};

/** ¿El periodo ya terminó? (cambia el tiempo verbal de las plantillas). */
export const PERIODO_PASADO: Record<Periodo, boolean> = {
  hoy: false,
  ayer: true,
  esta_semana: false,
  semana_pasada: true,
  este_mes: false,
  mes_pasado: true,
  este_anio: false,
};

/** Normaliza y detecta el periodo (atajo para quien ya tiene el mensaje crudo). */
export function periodoDe(mensaje: string): Periodo {
  return interpretarPeriodo(normalizar(mensaje));
}

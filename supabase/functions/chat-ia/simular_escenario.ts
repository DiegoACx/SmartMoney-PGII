// ============================================================================
// SmartMoney · Chat IA · simular_escenario
// ----------------------------------------------------------------------------
// Regla central: el CÓDIGO calcula TODAS las cifras; Gemini solo redacta con
// las cifras que le pasamos (validarTextoLLM). Aquí no se calculan intereses,
// tasas ni rendimientos de productos: no tenemos las tasas reales.
//
// El trabajo se parte en dos:
//   · `simular` (PURO): reconoce el caso por palabras clave y calcula los
//     hechos. Se prueba sin red ni Supabase.
//   · `responderSimulacion`: lee el perfil financiero, llama a `simular` y pide
//     la redacción a Gemini (si falla, usa la plantilla).
//
// Casos:
//   capacidad_pago    · ¿me alcanza para una cuota de X? (o hasta cuánto cabe)
//   ahorro_periodico  · si ahorro X cada quincena…
//   meta_plazo        · ¿llego a X para diciembre? / ¿con lo que ahorro?
//   recorte           · si dejo de gastar en X
//   objetivo_plazo    · ¿cuánto debo ahorrar para tener X en N meses?
//   tasas             · intereses, tasas, CDT, crédito… (sin calcular intereses)
//   resumen           · ni encaja o faltan datos: perfil + pregunta
// ============================================================================

import {
  cifrasEnTexto,
  formatearCOP,
  generarConGemini,
  validarTextoLLM,
} from "../_shared/gemini.ts";
import type { ClasificadorGrupos } from "./clasificadores.ts";
import { UMBRAL_GRUPO } from "./consultar_datos.ts";
import { hoyEnBogota } from "./fechas.ts";
import {
  aMensual,
  analizarMontos,
  extraerMontos,
  mesMencionado,
  minusculasSinTildes,
  objetoDeCompra,
  type AnalisisMontos,
} from "./montos.ts";
import {
  leerPerfilFinanciero,
  type MetaPerfil,
  type PerfilFinanciero,
} from "./perfil_financiero.ts";
import type { RepositorioChat } from "./repositorio.ts";
import type { RespuestaIntencion } from "./tipos.ts";

/** Tope de caracteres del texto redactado por Gemini en esta intención. */
export const LLM_MAX_CARACTERES_SIMULACION = 450;

/** Se agrega a toda respuesta de la intención (el usuario lo ve en la app). */
export const AVISO_SIMULACION =
  "Es una estimación con tus registros; no es asesoría financiera profesional.";

const INSTRUCCION_SIMULACION =
  "Eres el asistente financiero de SmartMoney para trabajadores independientes y jóvenes adultos en Colombia. Responde primero directamente la pregunta y luego explica. Explica el resultado en máximo 3 frases, tuteando, en español colombiano, usando SOLO estas cifras escritas igual. No inventes cifras, tasas ni plazos. No recomiendes bancos ni productos específicos. Responde solo con el texto, sin comillas ni emojis.";

// --- Palabras clave de cada caso ---------------------------------------------

/**
 * El caso `tasas` solo aplica cuando de verdad se pregunta por el costo o el
 * rendimiento: una tasa, un interés, un rendimiento o cuánto se pagaría en
 * total. Que el mensaje nombre un CDT o un crédito NO basta (para eso está
 * `capacidad_pago`).
 */
const RE_TASAS =
  /\btasas?\b|\binteres(es)?\b|\brendimiento(s)?\b|\bfiduciari|\brinde\b|\bcuanto rinde\b|\bcuanto (?:pagaria|pago|pagar|termino|me cobran|me cobraria|sale|me dan|me pagan)\b/;
/** Productos financieros: sin pregunta de tasa, son contexto del mensaje. */
const RE_PRODUCTO_TASA =
  /\bcdt\b|\bcreditos?\b|\bprestamos?\b|\binversion(es)?\b|\bcuenta de ahorro\b|\bentidad financiera\b/;
/**
 * Un monto junto a estos productos es dinero que se VA A INVERTIR (o que ya
 * está ahorrado), nunca una cuota que se pague cada mes.
 */
const RE_MONTO_INVERSION =
  /\bcdt\b|\binversion(es)?\b|\brendimiento(s)?\b|\bcuenta de ahorro\b|\bfiduciari|\brinde\b|\bahorr\w*\b/;
/** "cuota" explícita: entonces el monto sí es una cuota de deuda. */
const RE_CUOTA_EXPLICITA = /\bcuotas?\b/;
const RE_RECORTE =
  /\bdejo de gastar\b|\bdejar de gastar\b|\bsi recorto\b|\brecorto\b|\brecortar\b|\bsi dejo de\b|\bdejando de\b|\breduzco\b|\breducir\b|\bdejo de\b/;
const RE_AHORRO_CONDICIONAL =
  /\bsi ahorr|\bsi guard|\bsi apart|\bsi destino\b|\bsi meto\b|\bahorrando\b|\bguardando\b|\bapartando\b/;
/** Habla del ahorro que ya tiene ("lo que ahorro", "a este ritmo"). */
const RE_RITMO_ACTUAL =
  /\blo que ahorro\b|\ba este ritmo\b|\bcomo voy\b|\bcon mi ahorro\b/;
const RE_OBJETIVO_PLAZO =
  /\bcuanto (debo|deberia|necesito|tengo que|hay que) ahorrar\b|\bcuanto ahorrar\b|\bpara tener\b|\bpara juntar\b|\bpara completar\b|\bpara lograr\b|\bnecesito ahorrar\b|\bdebo ahorrar\b|\btengo que ahorrar\b/;
const RE_META_PLAZO =
  /\bllego a\b|\bllegar a\b|\balcanzo a\b|\balcanzar a\b|\bvoy a llegar\b|\bcompleto\b|\bcompletar\b/;
const RE_CAPACIDAD =
  /\bpuedo pagar\b|\bpodre pagar\b|\bme alcanza\b|\balcanza para\b|\bcuotas?\b|\bpuedo asumir\b|\bme da para\b|\bpuedo cubrir\b|\bpuedo sostener\b|\bme aprobarian\b|\bme aprueban\b/;
/** Productos de deuda: dan pie a la capacidad de pago cuando no hay monto. */
const RE_ALCANCE_PRODUCTO =
  /\bcreditos?\b|\btarjetas?\b|\bcuotas?\b|\bleasing\b|\bprestamos?\b/;
/** "…y seguir ahorrando": lo que aparta para todas sus metas cuenta. */
const RE_SEGUIR_AHORRANDO =
  /\bseguir ahorrando\b|\bsin dejar de ahorrar\b|\bmantener (?:mi|el) ahorro\b|\bsin dejar mis? (?:metas?|ahorro)\b/;

/** Disparadores del recorte. */
const RE_DISPARADOR_RECORTE =
  /\brecort\w*\b|\breduzc\w*\b|\breducir\b|\bdej\w*\s+de\s+(?:gastar|pedir|comprar)\b|\bgastar menos\b/;
const RE_PREPOSICION = /\b(?:en|de|con)\b/;

/**
 * Fragmento del mensaje que dice EN QUÉ se recorta: lo que sigue a la primera
 * preposición ("en", "de", "con") después del disparador.
 * "si recorto lo que gasto en domicilios…" → "domicilios…".
 * Devuelve null cuando no se puede aislar y el llamador usa el mensaje entero.
 */
function fragmentoDeRecorte(mensaje: string): string | null {
  const texto = minusculasSinTildes(mensaje);
  const disparador = RE_DISPARADOR_RECORTE.exec(texto);
  if (disparador === null) return null;

  const cola = texto.slice(disparador.index + disparador[0].length);
  const preposicion = RE_PREPOSICION.exec(cola);
  if (preposicion === null) return null;

  const fragmento = cola
    .slice(preposicion.index + preposicion[0].length)
    .replace(/^[\s,;:.]+/, "")
    .replace(/[¿?¡!.,;:]+$/, "")
    .trim();
  return fragmento.length >= 3 ? fragmento : null;
}

/** Metas a las que se refiere el mensaje (por nombre o por "seguir ahorrando"). */
function metasMencionadas(
  mensaje: string,
  perfil: PerfilFinanciero,
): MetaPerfil[] {
  const texto = minusculasSinTildes(mensaje);
  const porNombre = perfil.metas.filter((meta) =>
    texto.includes(minusculasSinTildes(meta.nombre))
  );
  if (porNombre.length > 0) return porNombre;
  return RE_SEGUIR_AHORRANDO.test(texto) ? perfil.metas : [];
}

/** Casos que puede devolver la simulación. */
export type CasoSimulacion =
  | "capacidad_pago"
  | "ahorro_periodico"
  | "meta_plazo"
  | "recorte"
  | "objetivo_plazo"
  | "tasas"
  | "resumen";

/** Una cifra ya calculada por el código, lista para que Gemini la redacte. */
export interface Hecho {
  etiqueta: string;
  valor_formateado: string;
  /** Cifra principal del caso: el texto de Gemini debe contenerla. */
  obligatorio?: boolean;
}

/** Resultado puro de la simulación. */
export interface Simulacion {
  caso: CasoSimulacion;
  hechos: Hecho[];
  texto_plantilla: string;
  /** true cuando el caso no conoce el precio y no se puede concluir si alcanza. */
  requierePrecio?: boolean;
}

// --- Ayudas de presentación (nunca cifras negativas) -------------------------

/**
 * Hecho del margen mensual SIN signos: si el excedente es ≤ 0 se expresa como
 * lo que los gastos superan a los ingresos, siempre en positivo.
 */
function hechoExcedente(
  excedente: number,
  etiquetaPositiva = "Tu excedente al mes",
): Hecho {
  return excedente > 0
    ? { etiqueta: etiquetaPositiva, valor_formateado: formatearCOP(excedente) }
    : {
      etiqueta: "Gastos por encima de los ingresos",
      valor_formateado: formatearCOP(-excedente),
    };
}

/** Frase del margen mensual, siempre en positivo. (La reutiliza pedir_consejo.) */
export function fraseMargen(excedente: number): string {
  if (excedente > 0) return `te quedan ${formatearCOP(excedente)} al mes`;
  if (excedente === 0) return "tus ingresos y tus gastos están igualados";
  return `tus gastos superan tus ingresos en ${formatearCOP(-excedente)} al mes`;
}

/** Los grupos donde más gasta al mes, para sugerir por dónde recortar. */
export function gruposMayorGasto(
  perfil: PerfilFinanciero,
  grupos: ClasificadorGrupos,
  cuantos = 2,
): { nombre: string; monto: number }[] {
  return [...perfil.gasto_mensual_por_grupo.entries()]
    .filter(([, monto]) => monto > 0)
    .sort((a, b) => b[1] - a[1])
    .slice(0, cuantos)
    .map(([id, monto]) => ({ nombre: grupos.nombreGrupo(id), monto }));
}

// --- Casos (cálculo puro) ----------------------------------------------------

/** Perfil sin ingresos: resume lo que hay y pide el dato que falta. */
function resumen(perfil: PerfilFinanciero, pregunta: string | null): Simulacion {
  const hechos: Hecho[] = [];
  const partes: string[] = [];

  if (perfil.ingreso_mensual !== null) {
    hechos.push({
      etiqueta: "Ingreso mensual",
      valor_formateado: formatearCOP(perfil.ingreso_mensual),
    });
    partes.push(`tu ingreso mensual estimado es ${formatearCOP(perfil.ingreso_mensual)}`);
  } else {
    partes.push("todavía no tengo ingresos tuyos registrados");
  }

  if (perfil.gasto_mensual > 0) {
    hechos.push({
      etiqueta: "Gastos al mes",
      valor_formateado: formatearCOP(perfil.gasto_mensual),
    });
    partes.push(`tus gastos son ${formatearCOP(perfil.gasto_mensual)} al mes`);
  }

  if (perfil.excedente_mensual !== null) {
    hechos.push(hechoExcedente(perfil.excedente_mensual, "Excedente al mes"));
    partes.push(fraseMargen(perfil.excedente_mensual));
  }

  // La cifra principal del resumen es la primera que sí tengamos.
  if (hechos.length > 0) hechos[0].obligatorio = true;

  const cuerpo = `Con lo que tengo registrado: ${partes.join(", ")}.`;
  const cierre = pregunta ??
    "Dime una cuota, un monto o un plazo (por ejemplo «en 6 meses») y hago la simulación.";
  return { caso: "resumen", hechos, texto_plantilla: `${cuerpo} ${cierre}` };
}

/**
 * Capacidad cuando los gastos ya superan (o igualan) los ingresos: no hay
 * margen para ninguna cuota. Se muestra el desbalance y dónde se gasta más.
 */
function casoCapacidadSinMargen(
  cuota: number | null,
  perfil: PerfilFinanciero,
  grupos: ClasificadorGrupos,
): Simulacion {
  const excedente = perfil.excedente_mensual ?? 0;
  const deficit = -excedente;

  const hechos: Hecho[] = [];
  if (perfil.ingreso_mensual !== null) {
    hechos.push({
      etiqueta: "Tu ingreso mensual",
      valor_formateado: formatearCOP(perfil.ingreso_mensual),
    });
  }
  hechos.push({
    etiqueta: "Tus gastos al mes",
    valor_formateado: formatearCOP(perfil.gasto_mensual),
  });
  hechos.push({
    etiqueta: "Gastos por encima de los ingresos",
    valor_formateado: formatearCOP(deficit),
    obligatorio: true,
  });
  if (cuota !== null) {
    hechos.push({
      etiqueta: "Cuota que quieres pagar",
      valor_formateado: formatearCOP(cuota),
    });
  }
  const mayores = gruposMayorGasto(perfil, grupos);
  for (const grupo of mayores) {
    hechos.push({
      etiqueta: `En "${grupo.nombre}"`,
      valor_formateado: formatearCOP(grupo.monto),
    });
  }

  let texto = `Hoy ${fraseMargen(excedente)}, así que no te queda margen`;
  texto += cuota !== null
    ? ` para una cuota de ${formatearCOP(cuota)}.`
    : " para una cuota.";
  const cuentas = perfil.ingreso_mensual !== null
    ? ` Tu ingreso es ${formatearCOP(perfil.ingreso_mensual)} y tus gastos ${formatearCOP(perfil.gasto_mensual)}`
    : ` Tus gastos son ${formatearCOP(perfil.gasto_mensual)}`;
  texto +=
    `${cuentas}: para equilibrar tendrías que bajar ${formatearCOP(deficit)} al mes.`;
  if (mayores.length > 0) {
    const donde = mayores
      .map((grupo) => `"${grupo.nombre}" (${formatearCOP(grupo.monto)})`)
      .join(" y ");
    texto += ` Los grupos donde más gastas son ${donde}: ahí suele haber más para recortar.`;
  }

  return { caso: "capacidad_pago", hechos, texto_plantilla: texto };
}

/**
 * a) ¿Me alcanza para un crédito/tarjeta y sigo ahorrando? Sin monto solo se
 * puede decir hasta cuánto cabe: excedente − lo que aparta para sus metas.
 */
function casoCapacidadSinMonto(
  mensaje: string,
  perfil: PerfilFinanciero,
  grupos: ClasificadorGrupos,
): Simulacion {
  const excedente = perfil.excedente_mensual;
  const ingreso = perfil.ingreso_mensual;

  if (excedente === null || ingreso === null || ingreso <= 0) {
    return resumen(perfil, "¿De cuánto sería la cuota que quieres pagar?");
  }
  if (excedente <= 0) return casoCapacidadSinMargen(null, perfil, grupos);

  const metas = metasMencionadas(mensaje, perfil);
  const apartar = metas.reduce(
    (total, meta) => total + (meta.aporte_necesario_mes ?? 0),
    0,
  );
  const cuotaMaxima = Math.max(0, excedente - apartar);
  const topeGuia = Math.round(ingreso * 0.3);
  const nombres = metas.map((meta) => `"${meta.nombre}"`).join(" y ");

  const hechos: Hecho[] = [
    { etiqueta: "Tu excedente al mes", valor_formateado: formatearCOP(excedente) },
  ];
  if (apartar > 0) {
    hechos.push({
      etiqueta: "Lo que apartas para tus metas",
      valor_formateado: formatearCOP(apartar),
    });
  }
  hechos.push({
    etiqueta: "Cuota máxima que te cabría",
    valor_formateado: formatearCOP(cuotaMaxima),
    obligatorio: true,
  });
  hechos.push({
    etiqueta: "Guía general: deudas hasta el 30 % del ingreso",
    valor_formateado: `${formatearCOP(topeGuia)} (30 %)`,
  });

  let texto = `Con tu excedente de ${formatearCOP(excedente)} al mes`;
  if (apartar > 0) {
    texto += ` y los ${formatearCOP(apartar)} que necesitas apartar para ${nombres}`;
  }
  texto +=
    `, te cabría una cuota de hasta ${formatearCOP(cuotaMaxima)} al mes. Como guía general se dice que las cuotas de deudas no deberían pasar del 30 % de tu ingreso (${formatearCOP(topeGuia)}), pero eso no es una norma fija. Dime de cuánto sería la cuota que te ofrecen y la comparo con tu excedente.`;

  return { caso: "capacidad_pago", hechos, texto_plantilla: texto };
}

/** a) ¿Me alcanza para una cuota de X al mes? */
function casoCapacidad(
  mensaje: string,
  analisis: AnalisisMontos,
  perfil: PerfilFinanciero,
  grupos: ClasificadorGrupos,
): Simulacion {
  if (analisis.montos.length === 0) {
    if (RE_ALCANCE_PRODUCTO.test(minusculasSinTildes(mensaje))) {
      return casoCapacidadSinMonto(mensaje, perfil, grupos);
    }
    return resumen(perfil, "¿De cuánto sería la cuota que quieres pagar?");
  }

  const cuota = aMensual(analisis.montos[0].valor, analisis.periodicidad);
  const ingreso = perfil.ingreso_mensual;

  if (ingreso === null || ingreso <= 0) {
    return {
      caso: "capacidad_pago",
      hechos: [{
        etiqueta: "Cuota mensual",
        valor_formateado: formatearCOP(cuota),
        obligatorio: true,
      }],
      texto_plantilla:
        `No tengo tus ingresos registrados, así que no puedo comparar una cuota de ${formatearCOP(cuota)} al mes con lo que te queda libre. Registra tus ingresos y lo miramos.`,
    };
  }

  const excedente = perfil.excedente_mensual ?? 0;
  if (excedente <= 0) return casoCapacidadSinMargen(cuota, perfil, grupos);

  const libre = excedente - cuota;
  const porcentaje = Math.round((cuota / ingreso) * 100);
  const topeGuia = Math.round(ingreso * 0.3);

  const hechos: Hecho[] = [
    {
      etiqueta: "Cuota mensual",
      valor_formateado: formatearCOP(cuota),
      obligatorio: true,
    },
    { etiqueta: "Tu ingreso mensual", valor_formateado: formatearCOP(ingreso) },
    { etiqueta: "Porcentaje del ingreso de la cuota", valor_formateado: `${porcentaje} %` },
  ];
  // Nunca un "libre" negativo: si la cuota no cabe, se dice cuánto falta.
  hechos.push(
    libre >= 0
      ? {
        etiqueta: "Te quedaría libre al mes",
        valor_formateado: formatearCOP(libre),
      }
      : {
        etiqueta: "Te faltaría al mes",
        valor_formateado: formatearCOP(-libre),
      },
  );
  hechos.push({
    etiqueta: "Guía general: deudas hasta el 30 % del ingreso",
    valor_formateado: `${formatearCOP(topeGuia)} (30 %)`,
  });

  const cierre = libre >= 0
    ? `Con una cuota de ${formatearCOP(cuota)} al mes, que es el ${porcentaje} % de tu ingreso, te quedarían ${formatearCOP(libre)} libres.`
    : `Con una cuota de ${formatearCOP(cuota)} al mes, que es el ${porcentaje} % de tu ingreso, te faltarían ${formatearCOP(-libre)} al mes para cubrirla.`;

  return {
    caso: "capacidad_pago",
    hechos,
    texto_plantilla:
      `${cierre} Como guía general se dice que las cuotas de deudas no deberían pasar del 30 % de tu ingreso (${formatearCOP(topeGuia)}), pero eso no es una norma fija.`,
  };
}

/** b) Si ahorro X cada quincena… ¿cuánto junto y en cuánto llego a mis metas? */
function casoAhorro(
  analisis: AnalisisMontos,
  perfil: PerfilFinanciero,
): Simulacion {
  const porcentaje = analisis.porcentajes[0] ?? null;

  let ahorro: number | null = null;
  if (analisis.montos.length > 0) {
    ahorro = aMensual(analisis.montos[0].valor, analisis.periodicidad);
  } else if (porcentaje !== null) {
    if (perfil.ingreso_mensual === null) {
      return resumen(perfil, "¿De cuánto sería el ahorro al mes?");
    }
    ahorro = perfil.ingreso_mensual * (porcentaje / 100);
  }

  if (ahorro === null || ahorro <= 0) {
    return resumen(perfil, "¿Cuánto podrías ahorrar al mes?");
  }

  const objetivo = analisis.montos.length > 1 ? analisis.montos[1].valor : null;
  const hechos: Hecho[] = [
    {
      etiqueta: "Ahorro mensual",
      valor_formateado: formatearCOP(ahorro),
      obligatorio: true,
    },
    { etiqueta: "En 6 meses", valor_formateado: formatearCOP(ahorro * 6) },
    { etiqueta: "En 12 meses", valor_formateado: formatearCOP(ahorro * 12) },
  ];
  const partes = [
    `Si ahorras ${formatearCOP(ahorro)} al mes, en 6 meses tendrías ${formatearCOP(ahorro * 6)} y en 12 meses ${formatearCOP(ahorro * 12)}.`,
  ];

  // El escenario que pide se calcula igual, pero se advierte que hoy no cabe.
  const excedente = perfil.excedente_mensual;
  if (excedente !== null && excedente <= 0) {
    hechos.push(hechoExcedente(excedente));
    partes.push(
      `Ojo: hoy ${fraseMargen(excedente)}, así que ese ahorro te exigiría recortar gastos.`,
    );
  }

  if (objetivo !== null && objetivo > 0) {
    const meses = Math.ceil(objetivo / ahorro);
    hechos.push({
      etiqueta: "Meses para tu objetivo",
      valor_formateado: `${meses} meses`,
    });
    partes.push(
      `Para juntar ${formatearCOP(objetivo)} necesitarías ${meses} meses.`,
    );
  } else if (perfil.metas.length > 0) {
    for (const meta of perfil.metas) {
      const meses = Math.ceil(meta.falta / ahorro);
      hechos.push({
        etiqueta: `Falta para "${meta.nombre}"`,
        valor_formateado: formatearCOP(meta.falta),
      });
      hechos.push({
        etiqueta: `Meses para "${meta.nombre}"`,
        valor_formateado: `${meses} meses`,
      });
      partes.push(
        `A ese ritmo llegarías a "${meta.nombre}" en ${meses} meses (te faltan ${formatearCOP(meta.falta)}).`,
      );
    }
  } else {
    partes.push(
      "Cuando registres una meta en la app te digo en cuántos meses la alcanzarías a ese ritmo.",
    );
  }

  return { caso: "ahorro_periodico", hechos, texto_plantilla: partes.join(" ") };
}

/** c) ¿Llego a X para tal plazo? (ritmo actual vs aporte necesario) */
function casoMetaPlazo(
  mensaje: string,
  analisis: AnalisisMontos,
  perfil: PerfilFinanciero,
): Simulacion {
  // Solo cuenta la meta que el mensaje menciona: "llego a comprar un portátil"
  // no habla de la meta "Viaje" aunque sea la única registrada.
  const meta = metasMencionadas(mensaje, perfil)[0] ?? perfil.metas[0] ?? null;
  const objetivo = analisis.montos.length > 0
    ? analisis.montos[0].valor
    : metasMencionadas(mensaje, perfil)[0]?.falta ?? null;

  // Sin precio no se puede comparar: se proyecta con el ahorro actual y se pide.
  if (objetivo === null || objetivo <= 0) {
    return casoMetaConRitmo(mensaje, analisis, perfil);
  }
  const plazo = analisis.plazoMeses ?? meta?.meses_restantes ?? null;
  if (plazo === null || plazo <= 0) {
    return resumen(
      perfil,
      "¿Para cuándo quieres lograrlo? Dime el plazo, por ejemplo «en 6 meses» o «para diciembre».",
    );
  }

  const necesario = objetivo / plazo;
  const ritmo = meta !== null && meta.ritmo_mes > 0
    ? meta.ritmo_mes
    : perfil.ahorro_mensual;

  const hechos: Hecho[] = [
    { etiqueta: "Objetivo", valor_formateado: formatearCOP(objetivo) },
    { etiqueta: "Meses disponibles", valor_formateado: `${plazo} meses` },
    {
      etiqueta: "Aporte necesario al mes",
      valor_formateado: formatearCOP(necesario),
      obligatorio: true,
    },
    { etiqueta: "Tu ritmo de ahorro al mes", valor_formateado: formatearCOP(ritmo) },
  ];

  const faltaPorMes = necesario - ritmo;
  let texto =
    `Para juntar ${formatearCOP(objetivo)} en ${plazo} meses necesitas apartar ${formatearCOP(necesario)} al mes. Tu ritmo de ahorro es ${formatearCOP(ritmo)} al mes`;

  if (faltaPorMes > 0) {
    hechos.push({
      etiqueta: "Te falta por mes",
      valor_formateado: formatearCOP(faltaPorMes),
    });
    texto += `, así que te faltarían ${formatearCOP(faltaPorMes)} cada mes.`;
  } else {
    texto += ", que sí te alcanza.";
  }

  return { caso: "meta_plazo", hechos, texto_plantilla: texto };
}

/**
 * c bis) "¿Con lo que ahorro llego a tal fecha?" Proyecta el ahorro actual
 * (ahorro_mensual × meses del plazo) y, si el mensaje menciona una meta, le
 * suma lo que ya lleva en ella. Se proyecta igual aunque el excedente del mes
 * sea negativo: lo que cuenta son los aportes reales a metas.
 *
 * Si no da el precio del objetivo se responde SOLO con la plantilla (sin
 * Gemini) y se marca `requierePrecio`: sin precio no se puede concluir si
 * alcanza o no.
 */
function casoMetaConRitmo(
  mensaje: string,
  analisis: AnalisisMontos,
  perfil: PerfilFinanciero,
): Simulacion {
  const plazo = analisis.plazoMeses;
  if (plazo === null || plazo <= 0) {
    return resumen(
      perfil,
      "¿Para cuándo quieres lograrlo? Dime el plazo, por ejemplo «en 6 meses» o «en diciembre».",
    );
  }

  const ritmo = perfil.ahorro_mensual;
  if (ritmo <= 0) {
    return resumen(
      perfil,
      "Todavía no tengo tus aportes a metas registrados, así que no puedo proyectar nada: ¿cuánto podrías ahorrar al mes?",
    );
  }

  const proyectado = ritmo * plazo;
  const meta = metasMencionadas(mensaje, perfil)[0] ?? null;
  const yaLleva = meta?.monto_actual ?? 0;
  const total = proyectado + yaLleva;
  const objetivo = analisis.montos.length > 0 ? analisis.montos[0].valor : null;

  const hechos: Hecho[] = [
    { etiqueta: "Tu ahorro al mes", valor_formateado: formatearCOP(ritmo) },
    { etiqueta: "Meses hasta el plazo", valor_formateado: `${plazo} meses` },
  ];
  if (yaLleva > 0 && meta !== null) {
    hechos.push({
      etiqueta: `Lo que ya llevas en "${meta.nombre}"`,
      valor_formateado: formatearCOP(yaLleva),
    });
  }
  hechos.push({
    etiqueta: "Tendrías para esa fecha",
    valor_formateado: formatearCOP(total),
    obligatorio: true,
  });

  // Con precio sí se compara y lo redacta Gemini.
  if (objetivo !== null && objetivo > 0) {
    hechos.push({
      etiqueta: "Tu objetivo",
      valor_formateado: formatearCOP(objetivo),
    });
    const diferencia = objetivo - total;
    let texto =
      `A tu ritmo de ahorro de ${formatearCOP(ritmo)} al mes, en ${plazo} meses tendrías ${formatearCOP(total)}`;
    if (diferencia > 0) {
      hechos.push({
        etiqueta: "Te faltarían para ese objetivo",
        valor_formateado: formatearCOP(diferencia),
      });
      texto += ` Para llegar a ${formatearCOP(objetivo)} te faltarían ${formatearCOP(diferencia)}.`;
    } else {
      texto += ` Con eso cubrirías los ${formatearCOP(objetivo)} que necesitas.`;
    }
    return { caso: "meta_plazo", hechos, texto_plantilla: texto };
  }

  // Sin precio: plantilla determinista (no pasa por Gemini).
  const mes = mesMencionado(mensaje);
  const objeto = objetoDeCompra(mensaje);
  const cuando = mes !== null ? `para ${mes}` : `en ${plazo} meses`;
  let texto =
    `Con tu ritmo de ahorro de ${formatearCOP(ritmo)} al mes, ${cuando} tendrías unos ${formatearCOP(total)}`;
  if (yaLleva > 0 && meta !== null) {
    texto +=
      ` (incluyen los ${formatearCOP(yaLleva)} que ya llevas en "${meta.nombre}")`;
  }
  texto += ".";

  const excedente = perfil.excedente_mensual;
  if (excedente !== null && excedente <= 0) {
    hechos.push(hechoExcedente(excedente));
    texto += ` Ojo: hoy ${fraseMargen(excedente)}.`;
  }

  texto += objeto !== null
    ? ` ¿Cuánto cuesta el ${objeto}? Así te digo si alcanzas.`
    : " ¿Cuánto cuesta lo que quieres comprar? Así te digo si alcanzas.";

  return {
    caso: "meta_plazo",
    hechos,
    texto_plantilla: texto,
    // Sin el precio no se puede afirmar si alcanza o no.
    requierePrecio: true,
  };
}

/** d) Si dejo de gastar en X… ¿cuánto me ahorro y cuánto adelanto mis metas? */
function casoRecorte(
  mensaje: string,
  analisis: AnalisisMontos,
  perfil: PerfilFinanciero,
  grupos: ClasificadorGrupos,
): Simulacion {
  const porcentaje = analisis.porcentajes[0] ?? null;

  // El clasificador solo ve el fragmento que dice en qué se recorta
  // ("lo que gasto en domicilios" → "domicilios…"); si no se puede aislar,
  // se le pasa el mensaje completo.
  const fragmento = fragmentoDeRecorte(mensaje);
  const prediccion = grupos.predecir(fragmento ?? mensaje);
  const grupoId = prediccion !== null && prediccion.confianza >= UMBRAL_GRUPO
    ? prediccion.grupo_id
    : null;
  const grupoNombre = grupoId !== null ? grupos.nombreGrupo(grupoId) : null;
  const gastoGrupo = grupoId !== null
    ? perfil.gasto_mensual_por_grupo.get(grupoId) ?? 0
    : 0;

  // El grupo se identificó pero no tiene gastos en la ventana: se lo decimos y
  // sugerimos dónde sí hay. Nunca se vuelve a preguntar en qué quiere recortar
  // si el mensaje ya lo dijo.
  if (grupoNombre !== null && gastoGrupo === 0) {
    const mayores = gruposMayorGasto(perfil, grupos);
    const hechos: Hecho[] = [
      { etiqueta: "Grupo de gasto", valor_formateado: grupoNombre },
    ];
    let texto =
      `No tienes gastos registrados en ${grupoNombre} en los últimos 3 meses.`;
    if (mayores.length > 0) {
      const donde = mayores
        .map((grupo) => `"${grupo.nombre}" (${formatearCOP(grupo.monto)})`)
        .join(" y ");
      for (const grupo of mayores) {
        hechos.push({
          etiqueta: `En "${grupo.nombre}"`,
          valor_formateado: formatearCOP(grupo.monto),
        });
      }
      texto +=
        ` Los grupos donde más gastas son ${donde}: por ahí podrías recortar.`;
    } else {
      texto += " Todavía no tengo gastos tuyos por grupo registrados.";
    }
    return { caso: "recorte", hechos, texto_plantilla: texto };
  }

  let base: number | null = null;
  let dondeRecorta = "";
  if (gastoGrupo > 0 && grupoNombre !== null) {
    base = gastoGrupo;
    dondeRecorta = grupoNombre;
  } else if (porcentaje !== null && perfil.gasto_mensual > 0) {
    base = perfil.gasto_mensual;
    dondeRecorta = "tus gastos";
  }

  if (base === null || base <= 0) {
    return resumen(
      perfil,
      "¿En qué gasto quieres recortar o qué porcentaje piensas bajar?",
    );
  }

  const ahorroPotencial = porcentaje !== null ? base * (porcentaje / 100) : base;
  const hechos: Hecho[] = [{
    etiqueta: "Recorte mensual potencial",
    valor_formateado: formatearCOP(ahorroPotencial),
  }];
  if (grupoNombre !== null) {
    hechos.push({ etiqueta: "Grupo de gasto", valor_formateado: grupoNombre });
  }

  const partes: string[] = [];
  // UN solo ritmo para comparar los dos plazos: el ahorro mensual (ventana de
  // 90 días). Así "hoy" y "con recorte" salen de la misma base y el adelanto
  // nunca queda en 0 por mezclar el ritmo de 30 días con el de 90.
  const nuevoRitmo = perfil.ahorro_mensual + ahorroPotencial;
  // Con ahorro 0 hoy no hay "meses sin recorte": hay que decirlo tal cual.
  const hayRitmo = perfil.ahorro_mensual > 0;
  const recorte = formatearCOP(ahorroPotencial);

  for (const meta of perfil.metas) {
    const mesesCon = nuevoRitmo > 0 ? Math.ceil(meta.falta / nuevoRitmo) : null;
    if (mesesCon === null) continue;
    // Los hechos obligatorios son los meses SIN recorte y CON recorte: son la
    // comparación que el texto de Gemini tiene que repetir.
    hechos.push({
      etiqueta: `Meses para "${meta.nombre}"`,
      valor_formateado: `${mesesCon} meses`,
      obligatorio: true,
    });
    if (hayRitmo) {
      // Los meses de hoy también usan el ritmo de 90 días (nunca el de 30): así
      // el plazo con recorte siempre es menor o igual que el de hoy.
      const mesesSin = Math.ceil(meta.falta / perfil.ahorro_mensual);
      hechos.push({
        etiqueta: `Meses hoy para "${meta.nombre}"`,
        valor_formateado: `${mesesSin} meses`,
        obligatorio: true,
      });
      const antes = Math.max(mesesSin - mesesCon, 0);
      hechos.push({
        etiqueta: `Meses que adelantas en "${meta.nombre}"`,
        valor_formateado: `${antes} meses`,
      });
      partes.push(
        `Hoy, a tu ritmo de ${formatearCOP(perfil.ahorro_mensual)} al mes, llegarías a "${meta.nombre}" en ${mesesSin} meses; si recortas ${recorte} en ${dondeRecorta}, pasarías a ${mesesCon} meses (adelantas ${antes}).`,
      );
    } else {
      partes.push(
        `Hoy no tienes un ritmo de ahorro, así que no puedo decirte en cuántos meses llegarías a "${meta.nombre}"; si recortas ${recorte} en ${dondeRecorta}, pasarías a ${mesesCon} meses.`,
      );
    }
  }

  // Sin margen mensual, primero hay que cuadrar el mes.
  const excedente = perfil.excedente_mensual;
  if (excedente !== null && excedente <= 0) {
    hechos.push(hechoExcedente(excedente));
    partes.push(
      `Ojo: hoy ${fraseMargen(excedente)}, así que primero hay que equilibrar tus gastos con tus ingresos.`,
    );
  }

  return { caso: "recorte", hechos, texto_plantilla: partes.join(" ") };
}

/** e) ¿Cuánto debo ahorrar para tener X en N meses? */
function casoObjetivoPlazo(
  analisis: AnalisisMontos,
  perfil: PerfilFinanciero,
): Simulacion {
  if (analisis.montos.length === 0) {
    return resumen(perfil, "¿Cuánto quieres juntar y en cuánto tiempo?");
  }
  const objetivo = analisis.montos[0].valor;
  const plazo = analisis.plazoMeses;

  if (plazo === null || plazo <= 0) {
    return resumen(
      perfil,
      "¿En cuánto tiempo lo quieres lograr? Por ejemplo «en 6 meses» o «en 2 años».",
    );
  }

  const necesario = objetivo / plazo;
  const hechos: Hecho[] = [
    { etiqueta: "Objetivo", valor_formateado: formatearCOP(objetivo) },
    { etiqueta: "Plazo", valor_formateado: `${plazo} meses` },
    {
      etiqueta: "Ahorro necesario al mes",
      valor_formateado: formatearCOP(necesario),
      obligatorio: true,
    },
  ];
  let texto =
    `Para tener ${formatearCOP(objetivo)} en ${plazo} meses necesitas ahorrar ${formatearCOP(necesario)} al mes.`;

  const excedente = perfil.excedente_mensual;
  if (excedente === null) {
    texto +=
      " Todavía no tengo tu ingreso registrado, así que no puedo compararlo con tu excedente.";
  } else if (excedente <= 0) {
    // Nunca un excedente en negativo: se dice cuánto superan los gastos.
    hechos.push(hechoExcedente(excedente));
    texto +=
      ` Hoy ${fraseMargen(excedente)}, así que ese ahorro te exigiría recortar gastos antes de poder apartarlo.`;
  } else {
    hechos.push(hechoExcedente(excedente, "Tu excedente al mes"));
    const diferencia = necesario - excedente;
    if (diferencia <= 0) {
      texto +=
        ` Tu excedente estimado es ${formatearCOP(excedente)}, así que sí te alcanza.`;
    } else {
      hechos.push({
        etiqueta: "Te faltaría al mes",
        valor_formateado: formatearCOP(diferencia),
      });
      texto +=
        ` Tu excedente estimado es ${formatearCOP(excedente)}, así que te faltarían ${formatearCOP(diferencia)} al mes.`;
    }
  }

  return { caso: "objetivo_plazo", hechos, texto_plantilla: texto };
}

/**
 * f) Tasa, CDT, inversión o rendimiento: no se calculan intereses.
 *
 * El monto que aparece junto a un CDT, una inversión o un rendimiento es dinero
 * que se VA A INVERTIR (o que ya está ahorrado), nunca una cuota: no se compara
 * como cuota. Como dato propio solo se dice cuánto pesa ese monto frente al
 * ingreso mensual o si ya lo tiene ahorrado en sus metas.
 */
function casoTasas(
  mensaje: string,
  analisis: AnalisisMontos,
  perfil: PerfilFinanciero,
): Simulacion {
  const texto = minusculasSinTildes(mensaje);
  const monto = analisis.montos.length > 0 ? analisis.montos[0].valor : null;
  const esInversion = RE_MONTO_INVERSION.test(texto) &&
    !RE_CUOTA_EXPLICITA.test(texto);

  const hechos: Hecho[] = [];
  let respuesta =
    "No puedo calcular intereses ni rendimientos porque no tengo las tasas reales de las entidades: el resultado depende de la tasa que te ofrezcan, así que pídele a la entidad su simulación oficial.";

  if (monto !== null && esInversion) {
    hechos.push({
      etiqueta: "Monto a invertir",
      valor_formateado: formatearCOP(monto),
      obligatorio: true,
    });

    if (perfil.ingreso_mensual !== null && perfil.ingreso_mensual > 0) {
      hechos.push({
        etiqueta: "Tu ingreso mensual",
        valor_formateado: formatearCOP(perfil.ingreso_mensual),
      });
      // Un monto que supera el ingreso mensual se entiende mejor en meses de
      // ingreso que en un porcentaje enorme.
      if (monto > perfil.ingreso_mensual) {
        const meses = (monto / perfil.ingreso_mensual).toFixed(1).replace(".", ",");
        hechos.push({
          etiqueta: "Meses de tu ingreso que equivale",
          valor_formateado: `${meses} meses`,
        });
        respuesta +=
          ` Con tus datos: invertir ${formatearCOP(monto)} equivale a unos ${meses} meses de tu ingreso (${formatearCOP(perfil.ingreso_mensual)}).`;
      } else {
        const porcentaje = Math.round((monto / perfil.ingreso_mensual) * 100);
        hechos.push({
          etiqueta: "Porcentaje de tu ingreso mensual",
          valor_formateado: `${porcentaje} %`,
        });
        respuesta +=
          ` Con tus datos: invertir ${formatearCOP(monto)} es el ${porcentaje} % de tu ingreso mensual (${formatearCOP(perfil.ingreso_mensual)}).`;
      }
    }

    const ahorrado = perfil.metas.reduce(
      (total, meta) => total + meta.monto_actual,
      0,
    );
    if (ahorrado >= monto) {
      hechos.push({
        etiqueta: "Lo que ya tienes ahorrado en tus metas",
        valor_formateado: formatearCOP(ahorrado),
      });
      respuesta +=
        ` Ese monto ya lo tienes ahorrado en tus metas (${formatearCOP(ahorrado)}).`;
    }

    return { caso: "tasas", hechos, texto_plantilla: respuesta };
  }

  // Cuota de una deuda: aquí sí tiene sentido compararla con el excedente.
  const cuota = monto !== null
    ? aMensual(analisis.montos[0].valor, analisis.periodicidad)
    : null;
  if (cuota !== null) {
    hechos.push({
      etiqueta: "Cuota mensual",
      valor_formateado: formatearCOP(cuota),
      obligatorio: true,
    });
  }

  const excedente = perfil.excedente_mensual;
  if (excedente !== null) {
    hechos.push(hechoExcedente(excedente, "Tu excedente al mes"));
  }

  if (cuota !== null && excedente !== null) {
    if (excedente <= 0) {
      respuesta +=
        ` Lo que sí puedo mirar con tus datos: hoy ${fraseMargen(excedente)}, así que no te queda margen para una cuota de ${formatearCOP(cuota)} al mes.`;
    } else {
      respuesta += cuota <= excedente
        ? ` Lo que sí puedo mirar con tus datos: una cuota de ${formatearCOP(cuota)} al mes cabe en tu excedente de ${formatearCOP(excedente)}.`
        : ` Lo que sí puedo mirar con tus datos: una cuota de ${formatearCOP(cuota)} al mes no cabe en tu excedente de ${formatearCOP(excedente)}.`;
    }
  } else if (cuota !== null) {
    respuesta +=
      ` Tampoco tengo tus ingresos registrados para comparar una cuota de ${formatearCOP(cuota)} con tu excedente.`;
  }

  return { caso: "tasas", hechos, texto_plantilla: respuesta };
}

/**
 * Reconoce el caso del mensaje y calcula los hechos. Función PURA: recibe el
 * perfil ya leído y el clasificador de grupos.
 */
export function simular(
  mensaje: string,
  perfil: PerfilFinanciero,
  grupos: ClasificadorGrupos,
  hoy: string,
): Simulacion {
  const texto = minusculasSinTildes(mensaje);
  const analisis = analizarMontos(mensaje, hoy);

  if (RE_TASAS.test(texto)) return casoTasas(mensaje, analisis, perfil);
  if (RE_RECORTE.test(texto)) return casoRecorte(mensaje, analisis, perfil, grupos);
  if (RE_CAPACIDAD.test(texto)) {
    return casoCapacidad(mensaje, analisis, perfil, grupos);
  }
  if (RE_RITMO_ACTUAL.test(texto)) {
    return casoMetaConRitmo(mensaje, analisis, perfil);
  }
  // Un CDT o un crédito sin pregunta de tasa es contexto, no un caso de tasas.
  if (RE_PRODUCTO_TASA.test(texto)) return casoTasas(mensaje, analisis, perfil);
  if (RE_AHORRO_CONDICIONAL.test(texto)) return casoAhorro(analisis, perfil);
  if (RE_OBJETIVO_PLAZO.test(texto)) return casoObjetivoPlazo(analisis, perfil);
  if (RE_META_PLAZO.test(texto)) return casoMetaPlazo(mensaje, analisis, perfil);
  return resumen(perfil, null);
}

// --- Respuesta con redacción del LLM -----------------------------------------

/** Dependencias externas de la intención (inyectables en las pruebas). */
export interface DepsSimulacion {
  repositorio: RepositorioChat;
  grupos: ClasificadorGrupos;
  fetchFn: typeof fetch;
  claveLLM?: string | null;
}

/** ¿El caso habla de una meta? (para ofrecer el atajo a la pestaña Metas). */
function involucraMeta(caso: CasoSimulacion, perfil: PerfilFinanciero): boolean {
  if (caso === "meta_plazo") return true;
  if (caso === "ahorro_periodico" || caso === "recorte") {
    return perfil.metas.length > 0;
  }
  return false;
}

/** Deja dicho cuando hay pocos registros y sigue con lo que haya. */
function conHistorialInsuficiente(
  simulacion: Simulacion,
  perfil: PerfilFinanciero,
): Simulacion {
  if (!perfil.historial_insuficiente) return simulacion;
  return {
    caso: simulacion.caso,
    hechos: [
      ...simulacion.hechos,
      { etiqueta: "Historial", valor_formateado: "pocos registros" },
    ],
    texto_plantilla:
      `Todavía tengo pocos registros tuyos, así que esta estimación es gruesa. ${simulacion.texto_plantilla}`,
    requierePrecio: simulacion.requierePrecio,
  };
}

/**
 * Valida el texto de Gemini para esta intención: primero las reglas generales
 * (cifras permitidas, longitud y cierre) y después la regla del caso: el texto
 * debe repetir la cifra principal (los hechos obligatorios).
 *
 * Los casos sin precio no llegan aquí: se responden con la plantilla.
 */
function validarTextoSimulacion(
  texto: string,
  simulacion: Simulacion,
  cifrasPermitidas: string[],
): { valido: boolean; motivo: string } {
  const general = validarTextoLLM(
    texto,
    cifrasPermitidas,
    LLM_MAX_CARACTERES_SIMULACION,
  );
  if (!general.valido) return general;

  const cifras = new Set(cifrasEnTexto(texto));
  for (const hecho of simulacion.hechos) {
    if (hecho.obligatorio !== true) continue;
    const principales = cifrasEnTexto(hecho.valor_formateado);
    if (principales.length > 0 && !principales.some((cifra) => cifras.has(cifra))) {
      return { valido: false, motivo: "falta_cifra" };
    }
  }
  return { valido: true, motivo: "ok" };
}

/** Respuesta de la intención simular_escenario. */
export async function responderSimulacion(
  mensaje: string,
  usuarioId: string,
  deps: DepsSimulacion,
  ahora: Date = new Date(),
): Promise<RespuestaIntencion> {
  const hoy = hoyEnBogota(ahora);
  const perfil = await leerPerfilFinanciero(usuarioId, deps.repositorio, ahora);
  const simulacion = conHistorialInsuficiente(
    simular(mensaje, perfil, deps.grupos, hoy),
    perfil,
  );

  // Meta con plazo pero sin precio: se responde SOLO con la plantilla, sin
  // pedirle la redacción a Gemini (no hay cifra que redactar, solo preguntar).
  if (simulacion.requierePrecio === true) {
    const respuesta: RespuestaIntencion = {
      respuesta: simulacion.texto_plantilla,
      origen: "calculo",
      motivo: `simulacion:${simulacion.caso}:sin_precio`,
      aviso: AVISO_SIMULACION,
    };
    if (involucraMeta(simulacion.caso, perfil)) {
      respuesta.accion = { tipo: "ir_a", destino: "metas" };
    }
    return respuesta;
  }

  // Cifras permitidas: las de los hechos + las que el usuario escribió, tanto
  // tal cual ("1") como ya interpretadas ("1 millon" → 1000000), para que el
  // texto pueda repetir "$1.000.000", "1.000.000" o "1 millón".
  const cifrasPermitidas = [
    ...simulacion.hechos.flatMap((hecho) => cifrasEnTexto(hecho.valor_formateado)),
    ...cifrasEnTexto(mensaje),
    ...extraerMontos(mensaje).map((monto) => String(monto.valor)),
  ];

  const lineasHechos = simulacion.hechos
    .map((hecho) => `- ${hecho.etiqueta}: ${hecho.valor_formateado}`)
    .join("\n");

  const resultado = await generarConGemini(
    {
      instruccion: INSTRUCCION_SIMULACION,
      mensaje:
        `Mensaje del usuario: "${mensaje}"\nHechos calculados:\n${lineasHechos}\nExplicación base: ${simulacion.texto_plantilla}`,
    },
    (texto) => validarTextoSimulacion(texto, simulacion, cifrasPermitidas),
    deps.fetchFn,
    { clave: deps.claveLLM },
  );

  const respuesta: RespuestaIntencion = {
    respuesta: resultado.texto !== null
      ? resultado.texto.trim()
      : simulacion.texto_plantilla,
    origen: resultado.texto !== null ? "llm" : "calculo",
    motivo: resultado.texto !== null
      ? `simulacion:${simulacion.caso}`
      : `simulacion:${simulacion.caso}:${resultado.motivo}`,
    aviso: AVISO_SIMULACION,
  };
  if (involucraMeta(simulacion.caso, perfil)) {
    respuesta.accion = { tipo: "ir_a", destino: "metas" };
  }
  return respuesta;
}

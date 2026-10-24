// ============================================================================
// Pruebas de simular_escenario.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: `simular` es puro (perfil de prueba + clasificador de grupos falso)
// y `responderSimulacion` recibe un repositorio falso y un `fetch` falso.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import type { ClasificadorGrupos } from "./clasificadores.ts";
import type { PerfilFinanciero } from "./perfil_financiero.ts";
import type {
  FilaAporte,
  FilaCategoria,
  FilaMeta,
  FilaTransaccion,
  RepositorioChat,
} from "./repositorio.ts";
import {
  AVISO_SIMULACION,
  LLM_MAX_CARACTERES_SIMULACION,
  responderSimulacion,
  type Simulacion,
  simular,
} from "./simular_escenario.ts";

const AHORA = new Date("2026-10-21T15:00:00Z"); // 2026-10-21 en Bogotá
const HOY = "2026-10-21";

/** Perfil de prueba: ingreso 3.000.000, gasto 2.000.000, excedente 1.000.000. */
const PERFIL: PerfilFinanciero = {
  ingreso_mensual: 3_000_000,
  gasto_mensual: 2_000_000,
  gasto_trabajo_mensual: 200_000,
  excedente_mensual: 1_000_000,
  ahorro_mensual: 400_000,
  gasto_mensual_por_grupo: new Map([[11, 500_000], [7, 200_000]]),
  metas: [{
    nombre: "Viaje",
    monto_actual: 1_200_000,
    falta: 1_800_000,
    fecha_limite: "2027-04-30",
    meses_restantes: 6,
    aporte_necesario_mes: 300_000,
    ritmo_mes: 200_000,
    meses_al_ritmo_actual: 9,
  }],
  historial_insuficiente: false,
};

/** Clasificador de grupos de prueba: siempre el grupo 11. */
function gruposFalsos(confianza = 0.8): ClasificadorGrupos {
  return {
    predecir: () => ({
      grupo_id: 11,
      confianza,
      top3: [{ grupo_id: 11, prob: confianza }],
    }),
    nombreGrupo: () => "Comidas fuera y domicilios",
  };
}

/** Clasificador con nombres distintos por grupo (para los 2 grupos mayores). */
function gruposDistintos(): ClasificadorGrupos {
  const nombres: Record<number, string> = {
    11: "Comidas fuera y domicilios",
    7: "Transporte",
  };
  return {
    predecir: () => ({
      grupo_id: 11,
      confianza: 0.8,
      top3: [{ grupo_id: 11, prob: 0.8 }],
    }),
    nombreGrupo: (grupoId) => nombres[grupoId] ?? "Otros",
  };
}

/** Clasificador que siempre acierta un grupo SIN gastos en el perfil. */
function gruposSinGasto(): ClasificadorGrupos {
  const nombres: Record<number, string> = {
    11: "Comidas fuera y domicilios",
    7: "Transporte",
    99: "Mascotas",
  };
  return {
    predecir: () => ({
      grupo_id: 99,
      confianza: 0.9,
      top3: [{ grupo_id: 99, prob: 0.9 }],
    }),
    nombreGrupo: (grupoId) => nombres[grupoId] ?? "Otros",
  };
}

/** Perfil con los gastos por encima de los ingresos (excedente −500.000). */
const PERFIL_NEGATIVO: PerfilFinanciero = {
  ...PERFIL,
  ingreso_mensual: 2_000_000,
  gasto_mensual: 2_500_000,
  excedente_mensual: -500_000,
  ahorro_mensual: 100_000,
};

/** Valor formateado de un hecho del resultado, o null si no está. */
function hecho(simulacion: Simulacion, etiqueta: string): string | null {
  return simulacion.hechos.find((item) => item.etiqueta === etiqueta)
    ?.valor_formateado ?? null;
}

// --- Casos a) a g) con el perfil de prueba -----------------------------------

Deno.test("caso a) capacidad de pago: compara la cuota con el ingreso", () => {
  const resultado = simular(
    "¿me alcanza para una cuota de 400 mil al mes?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "capacidad_pago");
  assertEquals(hecho(resultado, "Cuota mensual"), "$400.000");
  assertEquals(hecho(resultado, "Tu ingreso mensual"), "$3.000.000");
  assertEquals(hecho(resultado, "Porcentaje del ingreso de la cuota"), "13 %");
  assertEquals(hecho(resultado, "Te quedaría libre al mes"), "$600.000");
  assertEquals(hecho(resultado, "Guía general: deudas hasta el 30 % del ingreso"), "$900.000 (30 %)");
  assert(resultado.texto_plantilla.includes("$400.000"));
  assert(resultado.texto_plantilla.includes("13 %"));
  assert(resultado.texto_plantilla.includes("$600.000"));
  assert(resultado.texto_plantilla.includes("no es una norma fija"));
});

Deno.test("caso a) capacidad sin monto: pide la cuota y resume el perfil", () => {
  const resultado = simular("¿me alcanza este mes?", PERFIL, gruposFalsos(), HOY);

  assertEquals(resultado.caso, "resumen");
  assertEquals(hecho(resultado, "Excedente al mes"), "$1.000.000");
  assert(resultado.texto_plantilla.endsWith("¿De cuánto sería la cuota que quieres pagar?"));
});

Deno.test("caso b) ahorro periódico: quincenal, 6 y 12 meses y metas activas", () => {
  const resultado = simular(
    "si ahorro 300 mil cada quincena, ¿en cuánto llego a mi meta?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "ahorro_periodico");
  assertEquals(hecho(resultado, "Ahorro mensual"), "$600.000");
  assertEquals(hecho(resultado, "En 6 meses"), "$3.600.000");
  assertEquals(hecho(resultado, "En 12 meses"), "$7.200.000");
  assertEquals(hecho(resultado, 'Falta para "Viaje"'), "$1.800.000");
  assertEquals(hecho(resultado, 'Meses para "Viaje"'), "3 meses");
});

Deno.test("caso b) ahorro como porcentaje del ingreso", () => {
  const resultado = simular(
    "si ahorro el 10 % de mi ingreso cada mes",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "ahorro_periodico");
  assertEquals(hecho(resultado, "Ahorro mensual"), "$300.000");
  assertEquals(hecho(resultado, "En 12 meses"), "$3.600.000");
  assertEquals(hecho(resultado, 'Meses para "Viaje"'), "6 meses");
});

Deno.test("caso c) meta con plazo: ritmo actual vs aporte necesario", () => {
  const resultado = simular(
    "¿llego a 3 millones para diciembre?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "meta_plazo");
  assertEquals(hecho(resultado, "Objetivo"), "$3.000.000");
  assertEquals(hecho(resultado, "Meses disponibles"), "2 meses");
  assertEquals(hecho(resultado, "Aporte necesario al mes"), "$1.500.000");
  assertEquals(hecho(resultado, "Tu ritmo de ahorro al mes"), "$200.000");
  assertEquals(hecho(resultado, "Te falta por mes"), "$1.300.000");
  assert(resultado.texto_plantilla.includes("te faltarían $1.300.000 cada mes"));
});

Deno.test("caso c) meta con plazo: si el ritmo alcanza, lo dice", () => {
  const perfil: PerfilFinanciero = {
    ...PERFIL,
    metas: [{ ...PERFIL.metas[0], ritmo_mes: 2_000_000 }],
  };
  const resultado = simular("¿llego a 3 millones en 2 meses?", perfil, gruposFalsos(), HOY);

  assertEquals(resultado.caso, "meta_plazo");
  assertEquals(hecho(resultado, "Te falta por mes"), null);
  assert(resultado.texto_plantilla.includes("que sí te alcanza"));
});

Deno.test("caso d) recorte: grupo con el clasificador y adelanto de metas", () => {
  const resultado = simular(
    "si dejo de gastar en comida fuera",
    PERFIL,
    gruposFalsos(0.8),
    HOY,
  );

  assertEquals(resultado.caso, "recorte");
  assertEquals(hecho(resultado, "Recorte mensual potencial"), "$500.000");
  assertEquals(hecho(resultado, "Grupo de gasto"), "Comidas fuera y domicilios");
  assertEquals(hecho(resultado, 'Meses para "Viaje"'), "2 meses");
  assertEquals(hecho(resultado, 'Meses que adelantas en "Viaje"'), "7 meses");
});

Deno.test("caso d) recorte: clasifica el fragmento que sigue a la preposición", () => {
  // El clasificador de prueba solo acierta si recibe el fragmento ("domicilios…").
  let recibido = "";
  const clasificador: ClasificadorGrupos = {
    predecir: (texto) => {
      recibido = texto;
      return texto.includes("domicilios")
        ? {
          grupo_id: 11,
          confianza: 0.85,
          top3: [{ grupo_id: 11, prob: 0.85 }],
        }
        : null;
    },
    nombreGrupo: () => "Comidas fuera y domicilios",
  };

  const resultado = simular(
    "si recorto lo que gasto en domicilios cuanto mas rapido cumplo mi meta",
    PERFIL,
    clasificador,
    HOY,
  );

  assertEquals(resultado.caso, "recorte");
  assertEquals(recibido.startsWith("domicilios"), true);
  assertEquals(recibido.includes("recorto"), false);
  assertEquals(hecho(resultado, "Grupo de gasto"), "Comidas fuera y domicilios");
  assertEquals(hecho(resultado, "Recorte mensual potencial"), "$500.000");
  assertEquals(hecho(resultado, 'Meses para "Viaje"'), "2 meses");
});

Deno.test("caso d) recorte: sin preposición clasifica el mensaje completo", () => {
  let recibido = "";
  const clasificador: ClasificadorGrupos = {
    predecir: (texto) => {
      recibido = texto;
      return { grupo_id: 11, confianza: 0.8, top3: [{ grupo_id: 11, prob: 0.8 }] };
    },
    nombreGrupo: () => "Comidas fuera y domicilios",
  };

  const resultado = simular("si recorto el 20 %", PERFIL, clasificador, HOY);

  assertEquals(recibido, "si recorto el 20 %");
  // Con el grupo seguro (0.8) el 20 % se aplica al gasto del grupo ($500.000).
  assertEquals(hecho(resultado, "Recorte mensual potencial"), "$100.000");
});

Deno.test("caso d) recorte por porcentaje si el grupo no es seguro", () => {
  const resultado = simular(
    "si recorto el 20 % de mis gastos",
    PERFIL,
    gruposFalsos(0.4),
    HOY,
  );

  assertEquals(resultado.caso, "recorte");
  assertEquals(hecho(resultado, "Recorte mensual potencial"), "$400.000");
  assertEquals(hecho(resultado, "Grupo de gasto"), null);
  assertEquals(hecho(resultado, 'Meses para "Viaje"'), "3 meses");
  assert(resultado.texto_plantilla.includes("en tus gastos"));
});

Deno.test("caso d) recorte: grupo identificado sin gastos sugiere dónde sí hay", () => {
  const resultado = simular(
    "si dejo de gastar en mascotas",
    PERFIL,
    gruposSinGasto(),
    HOY,
  );

  assertEquals(resultado.caso, "recorte");
  assertEquals(hecho(resultado, "Grupo de gasto"), "Mascotas");
  assert(
    resultado.texto_plantilla.includes(
      "No tienes gastos registrados en Mascotas en los últimos 3 meses",
    ),
  );
  assert(
    resultado.texto_plantilla.includes(
      '"Comidas fuera y domicilios" ($500.000) y "Transporte" ($200.000)',
    ),
  );
  // Nunca se vuelve a preguntar en qué quiere recortar si ya lo dijo.
  assertEquals(resultado.texto_plantilla.includes("¿En qué gasto"), false);
});

Deno.test("caso e) objetivo y plazo: ahorro necesario vs excedente", () => {
  const resultado = simular(
    "¿cuánto debo ahorrar para tener 6 millones en 12 meses?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "objetivo_plazo");
  assertEquals(hecho(resultado, "Objetivo"), "$6.000.000");
  assertEquals(hecho(resultado, "Plazo"), "12 meses");
  assertEquals(hecho(resultado, "Ahorro necesario al mes"), "$500.000");
  assertEquals(hecho(resultado, "Tu excedente al mes"), "$1.000.000");
  assert(resultado.texto_plantilla.includes("sí te alcanza"));
});

Deno.test("caso e) objetivo y plazo: dice cuánto falta al mes", () => {
  const resultado = simular(
    "¿cuánto debo ahorrar para tener 24 millones en 12 meses?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(hecho(resultado, "Ahorro necesario al mes"), "$2.000.000");
  assertEquals(hecho(resultado, "Te faltaría al mes"), "$1.000.000");
  assert(resultado.texto_plantilla.includes("te faltarían $1.000.000 al mes"));
});

Deno.test("caso f) tasas: no calcula intereses y remite a la entidad", () => {
  const resultado = simular(
    "¿me conviene un CDT al 10 %?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "tasas");
  assertEquals(hecho(resultado, "Cuota mensual"), null);
  assertEquals(hecho(resultado, "Tu excedente al mes"), "$1.000.000");
  assert(resultado.texto_plantilla.includes("No puedo calcular intereses"));
  assert(resultado.texto_plantilla.includes("simulación oficial"));
});

Deno.test("caso f) tasas con cuota: sí compara la cuota con el excedente", () => {
  const resultado = simular(
    "¿cuánto pagaría en total por un crédito con una cuota de 500 mil?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "tasas");
  assertEquals(hecho(resultado, "Cuota mensual"), "$500.000");
  assert(resultado.texto_plantilla.includes("cabe en tu excedente de $1.000.000"));
});

Deno.test("caso a) crédito sin monto: calcula la cuota máxima que le cabe", () => {
  const resultado = simular(
    "¿Me alcanza para pagar un crédito y seguir ahorrando para el viaje?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "capacidad_pago");
  assertEquals(hecho(resultado, "Tu excedente al mes"), "$1.000.000");
  assertEquals(hecho(resultado, "Lo que apartas para tus metas"), "$300.000");
  assertEquals(hecho(resultado, "Cuota máxima que te cabría"), "$700.000");
  assertEquals(
    hecho(resultado, "Guía general: deudas hasta el 30 % del ingreso"),
    "$900.000 (30 %)",
  );
  assert(resultado.texto_plantilla.includes("cuota de hasta $700.000 al mes"));
  assert(resultado.texto_plantilla.includes("Dime de cuánto sería la cuota"));
});

Deno.test("caso a) crédito con cuota y sin pregunta de tasa: capacidad de pago", () => {
  const resultado = simular(
    "un crédito con una cuota de 500 mil, ¿me alcanza?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "capacidad_pago");
  assertEquals(hecho(resultado, "Cuota mensual"), "$500.000");
  assertEquals(hecho(resultado, "Te quedaría libre al mes"), "$500.000");
});

Deno.test("caso c) con lo que ahorro: proyecta al plazo y pide el precio", () => {
  const resultado = simular(
    "ahorrando lo que ahorro ahora llego a comprar un portatil en diciembre?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "meta_plazo");
  assertEquals(resultado.requierePrecio, true);
  assertEquals(hecho(resultado, "Tu ahorro al mes"), "$400.000");
  assertEquals(hecho(resultado, "Meses hasta el plazo"), "2 meses");
  assertEquals(hecho(resultado, "Tendrías para esa fecha"), "$800.000");
  assert(
    resultado.texto_plantilla.includes(
      "Con tu ritmo de ahorro de $400.000 al mes, para diciembre tendrías unos $800.000.",
    ),
  );
  assert(resultado.texto_plantilla.includes("¿Cuánto cuesta el portatil?"));
});

Deno.test("caso c) con lo que ahorro: suma lo que ya lleva en la meta", () => {
  const resultado = simular(
    "con lo que ahorro llego a la meta de Viaje en 6 meses?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "meta_plazo");
  assertEquals(hecho(resultado, 'Lo que ya llevas en "Viaje"'), "$1.200.000");
  assertEquals(hecho(resultado, "Tendrías para esa fecha"), "$3.600.000");
  assert(resultado.texto_plantilla.includes('ya llevas en "Viaje"'));
});

Deno.test("caso c) con lo que ahorro y objetivo dado: dice cuánto le falta", () => {
  const resultado = simular(
    "a este ritmo llego a 5 millones en 6 meses?",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "meta_plazo");
  assertEquals(hecho(resultado, "Tu objetivo"), "$5.000.000");
  assertEquals(hecho(resultado, "Te faltarían para ese objetivo"), "$2.600.000");
});

Deno.test("caso g) sin caso claro: resume el perfil y pide un dato", () => {
  const resultado = simular("hola, ¿tienes ideas para mí?", PERFIL, gruposFalsos(), HOY);

  assertEquals(resultado.caso, "resumen");
  assert(
    resultado.texto_plantilla.includes(
      "tu ingreso mensual estimado es $3.000.000, tus gastos son $2.000.000 al mes, te quedan $1.000.000 al mes",
    ),
  );
  assert(resultado.texto_plantilla.includes("Dime una cuota, un monto o un plazo"));
});

Deno.test("caso g) sin ingresos registrados: resume lo que haya", () => {
  const perfil: PerfilFinanciero = {
    ...PERFIL,
    ingreso_mensual: null,
    excedente_mensual: null,
  };
  const resultado = simular("¿me alcanza?", perfil, gruposFalsos(), HOY);

  assert(resultado.texto_plantilla.includes("todavía no tengo ingresos tuyos registrados"));
  assert(resultado.texto_plantilla.includes("tus gastos son $2.000.000 al mes"));
});

// --- Excedente cero o negativo: ninguna cifra en negativo --------------------

Deno.test("caso a) excedente negativo: sin margen para la cuota y sin '-$'", () => {
  const resultado = simular(
    "¿me alcanza para una cuota de 400 mil al mes?",
    PERFIL_NEGATIVO,
    gruposDistintos(),
    HOY,
  );

  assertEquals(resultado.caso, "capacidad_pago");
  assertEquals(hecho(resultado, "Tu ingreso mensual"), "$2.000.000");
  assertEquals(hecho(resultado, "Tus gastos al mes"), "$2.500.000");
  assertEquals(hecho(resultado, "Gastos por encima de los ingresos"), "$500.000");
  assertEquals(hecho(resultado, "Cuota que quieres pagar"), "$400.000");
  assertEquals(hecho(resultado, 'En "Comidas fuera y domicilios"'), "$500.000");
  assertEquals(hecho(resultado, 'En "Transporte"'), "$200.000");
  assertEquals(hecho(resultado, "Cuota mensual"), null);
  assertEquals(hecho(resultado, "Cuota máxima que te cabría"), null);
  assert(resultado.texto_plantilla.includes("no te queda margen"));
  assert(resultado.texto_plantilla.includes("equilibrar"));
  assertEquals(resultado.texto_plantilla.includes("-$"), false);
});

Deno.test("caso a) excedente negativo sin monto: muestra los 2 grupos mayores", () => {
  const resultado = simular(
    "¿Me alcanza para un crédito?",
    PERFIL_NEGATIVO,
    gruposDistintos(),
    HOY,
  );

  assertEquals(resultado.caso, "capacidad_pago");
  assertEquals(hecho(resultado, "Gastos por encima de los ingresos"), "$500.000");
  assertEquals(hecho(resultado, 'En "Comidas fuera y domicilios"'), "$500.000");
  assertEquals(hecho(resultado, 'En "Transporte"'), "$200.000");
  assertEquals(resultado.texto_plantilla.includes("-$"), false);
});

Deno.test("caso b) excedente negativo: calcula el ahorro y advierte el desbalance", () => {
  const resultado = simular(
    "si ahorro 300 mil cada quincena",
    PERFIL_NEGATIVO,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "ahorro_periodico");
  assertEquals(hecho(resultado, "Ahorro mensual"), "$600.000");
  assertEquals(hecho(resultado, "Gastos por encima de los ingresos"), "$500.000");
  assert(
    resultado.texto_plantilla.includes(
      "tus gastos superan tus ingresos en $500.000 al mes",
    ),
  );
  assert(resultado.texto_plantilla.includes("recortar gastos"));
  assertEquals(resultado.texto_plantilla.includes("-$"), false);
});

Deno.test("caso e) excedente negativo: advierte que habría que recortar gastos", () => {
  const resultado = simular(
    "¿cuánto debo ahorrar para tener 6 millones en 12 meses?",
    PERFIL_NEGATIVO,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "objetivo_plazo");
  assertEquals(hecho(resultado, "Ahorro necesario al mes"), "$500.000");
  assertEquals(hecho(resultado, "Gastos por encima de los ingresos"), "$500.000");
  assert(resultado.texto_plantilla.includes("recortar gastos"));
  assertEquals(resultado.texto_plantilla.includes("-$"), false);
});

Deno.test("caso g) y f) excedente negativo: resumen y tasas sin '-$'", () => {
  const resumen = simular(
    "hola, ¿tienes ideas para mí?",
    PERFIL_NEGATIVO,
    gruposFalsos(),
    HOY,
  );
  assertEquals(resumen.caso, "resumen");
  assertEquals(hecho(resumen, "Gastos por encima de los ingresos"), "$500.000");
  assert(
    resumen.texto_plantilla.includes(
      "tus gastos superan tus ingresos en $500.000 al mes",
    ),
  );
  assertEquals(resumen.texto_plantilla.includes("-$"), false);

  const tasas = simular(
    "¿me conviene un CDT al 10 %?",
    PERFIL_NEGATIVO,
    gruposFalsos(),
    HOY,
  );
  assertEquals(tasas.caso, "tasas");
  assertEquals(hecho(tasas, "Tu excedente al mes"), null);
  assertEquals(hecho(tasas, "Gastos por encima de los ingresos"), "$500.000");
  assertEquals(tasas.texto_plantilla.includes("-$"), false);
});

// --- Meta con el ritmo actual: sin precio no se concluye ---------------------

Deno.test("caso c) sin precio: proyecta con el ahorro actual y marca requierePrecio", () => {
  const resultado = simular(
    "llego a comprar un portatil en diciembre",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "meta_plazo");
  assertEquals(resultado.requierePrecio, true);
  assertEquals(hecho(resultado, "Tu ahorro al mes"), "$400.000");
  assertEquals(hecho(resultado, "Tendrías para esa fecha"), "$800.000");
  assert(resultado.texto_plantilla.includes("tendrías unos $800.000"));
  assert(resultado.texto_plantilla.includes("¿Cuánto cuesta el portatil?"));
});

Deno.test("caso c) sin precio y excedente negativo: agrega la advertencia", () => {
  const resultado = simular(
    "llego a comprar un portatil en diciembre",
    PERFIL_NEGATIVO,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.requierePrecio, true);
  assertEquals(hecho(resultado, "Gastos por encima de los ingresos"), "$500.000");
  assert(
    resultado.texto_plantilla.includes(
      "tus gastos superan tus ingresos en $500.000 al mes",
    ),
  );
});

Deno.test("caso c) sin aportes registrados: lo dice y pide cuánto podría ahorrar", () => {
  const resultado = simular(
    "llego a comprar un portatil en diciembre",
    { ...PERFIL, ahorro_mensual: 0 },
    gruposFalsos(),
    HOY,
  );

  assert(resultado.texto_plantilla.includes("aportes a metas registrados"));
  assert(resultado.texto_plantilla.includes("¿cuánto podrías ahorrar al mes?"));
});

// --- Tasas: el monto de una inversión no es una cuota ------------------------

Deno.test("caso f) CDT: el monto es para invertir, no una cuota", () => {
  const resultado = simular(
    "cuanto me rinde un cdt de 1 millon",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "tasas");
  assertEquals(hecho(resultado, "Monto a invertir"), "$1.000.000");
  assertEquals(hecho(resultado, "Cuota mensual"), null);
  assertEquals(hecho(resultado, "Te quedaría libre al mes"), null);
  assert(resultado.texto_plantilla.includes("simulación oficial"));
  assertEquals(resultado.texto_plantilla.toLowerCase().includes("cuota"), false);
});

Deno.test("caso f) CDT con monto mayor al ingreso: lo expresa en meses de ingreso", () => {
  const resultado = simular(
    "cuanto me rinde un cdt de 5 millones",
    PERFIL,
    gruposFalsos(),
    HOY,
  );

  assertEquals(resultado.caso, "tasas");
  assertEquals(hecho(resultado, "Monto a invertir"), "$5.000.000");
  assertEquals(
    hecho(resultado, "Meses de tu ingreso que equivale"),
    "1,7 meses",
  );
  assert(
    resultado.texto_plantilla.includes(
      "equivale a unos 1,7 meses de tu ingreso ($3.000.000)",
    ),
  );
  // No se habla de porcentajes cuando el monto pasa del ingreso mensual.
  assertEquals(resultado.texto_plantilla.includes("%"), false);
});

// --- Respuesta: perfil + redacción -------------------------------------------

const TRANSACCIONES: FilaTransaccion[] = [
  { categoria_id: "c3", tipo: "ingreso", monto: 2_000_000, fecha: "2026-07-10" },
  { categoria_id: "c3", tipo: "ingreso", monto: 2_400_000, fecha: "2026-08-10" },
  { categoria_id: "c3", tipo: "ingreso", monto: 3_000_000, fecha: "2026-09-10" },
  { categoria_id: "c1", tipo: "egreso", monto: 600_000, fecha: "2026-08-15" },
  {
    categoria_id: "c2",
    tipo: "egreso",
    monto: 900_000,
    fecha: "2026-09-10",
    es_gasto_trabajo: true,
  },
  { categoria_id: "c1", tipo: "egreso", monto: 900_000, fecha: "2026-09-25" },
];

const APORTES: FilaAporte[] = [
  { meta_id: "m1", monto: 200_000, fecha: "2026-08-01" },
  { meta_id: "m1", monto: 400_000, fecha: "2026-09-01" },
  { meta_id: "m1", monto: 150_000, fecha: "2026-09-25" },
];

const METAS: FilaMeta[] = [{
  id: "m1",
  nombre: "Viaje",
  monto_objetivo: 3_000_000,
  monto_actual: 1_200_000,
  fecha_limite: "2027-04-30",
  cumplida: false,
}];

const CATEGORIAS: FilaCategoria[] = [
  { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
  { id: "c2", nombre: "Transporte", grupo_id: 7 },
  { id: "c3", nombre: "Salario", grupo_id: null },
];

/** Repositorio falso con 3 meses de historial (perfil: excedente 1.600.000). */
function repoConDatos(): RepositorioChat {
  return repoFalso({
    transacciones: TRANSACCIONES,
    aportes: APORTES,
    metas: METAS,
    categorias: CATEGORIAS,
  });
}

function repoFalso(datos: {
  transacciones?: FilaTransaccion[];
  aportes?: FilaAporte[];
  metas?: FilaMeta[];
  categorias?: FilaCategoria[];
} = {}): RepositorioChat {
  const transacciones = datos.transacciones ?? [];
  const aportes = datos.aportes ?? [];

  return {
    contarMensajesUsuario: async () => 0,
    ultimoMensajeAsistente: async () => null,
    insertarMensaje: async () => {},
    leerTransacciones: async (_usuarioId, desde, hasta, tipo) =>
      transacciones.filter((fila) =>
        fila.tipo === tipo && fila.fecha >= desde && fila.fecha <= hasta
      ),
    leerCategorias: async () => datos.categorias ?? [],
    leerMetasActivas: async () => datos.metas ?? [],
    leerAportes: async (_usuarioId, desde, hasta) =>
      aportes.filter((fila) =>
        fila.fecha >= desde && fila.fecha <= hasta
      ),
  };
}

/** `fetch` falso que responde 200 con el texto dado. */
function fetchQueResponde(texto: string): typeof fetch {
  return (async () =>
    new Response(
      JSON.stringify({ candidates: [{ content: { parts: [{ text: texto }] } }] }),
      { status: 200, headers: { "Content-Type": "application/json" } },
    )) as unknown as typeof fetch;
}

const MENSAJE_OBJETIVO = "¿cuánto debo ahorrar para tener 6 millones en 12 meses?";

Deno.test("respuesta: redacción válida de Gemini usa origen llm", async () => {
  const texto =
    "Necesitas apartar $500.000 al mes durante 12 meses; con tu excedente de $1.600.000 te alcanza.";
  const resultado = await responderSimulacion(
    MENSAJE_OBJETIVO,
    "usuario-1",
    {
      repositorio: repoConDatos(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde(texto),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.respuesta, texto);
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.motivo, "simulacion:objetivo_plazo");
  assertEquals(resultado.aviso, AVISO_SIMULACION);
  assertEquals(resultado.accion, undefined);
});

Deno.test("respuesta: Gemini con cifra inventada cae a la plantilla", async () => {
  const resultado = await responderSimulacion(
    MENSAJE_OBJETIVO,
    "usuario-1",
    {
      repositorio: repoConDatos(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("Te faltarían $700.000 al mes."),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.origen, "calculo");
  assertEquals(
    resultado.motivo,
    "simulacion:objetivo_plazo:validacion:cifra_no_permitida:700000",
  );
  assert(
    resultado.respuesta.includes(
      "Para tener $6.000.000 en 12 meses necesitas ahorrar $500.000 al mes.",
    ),
  );
});

Deno.test("respuesta: texto de Gemini demasiado largo cae a la plantilla", async () => {
  const largo = "a".repeat(LLM_MAX_CARACTERES_SIMULACION + 1);
  const resultado = await responderSimulacion(
    MENSAJE_OBJETIVO,
    "usuario-1",
    {
      repositorio: repoConDatos(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde(largo),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.motivo, "simulacion:objetivo_plazo:validacion:largo");
});

Deno.test("respuesta: sin clave de Gemini cae a la plantilla", async () => {
  const resultado = await responderSimulacion(
    MENSAJE_OBJETIVO,
    "usuario-1",
    {
      repositorio: repoConDatos(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.motivo, "simulacion:objetivo_plazo:sin_clave");
  assertEquals(resultado.aviso, AVISO_SIMULACION);
  assert(resultado.respuesta.includes("$6.000.000"));
});

Deno.test("respuesta: caso con meta agrega el aviso y la acción a metas", async () => {
  const resultado = await responderSimulacion(
    "¿llego a 3 millones para diciembre?",
    "usuario-1",
    {
      repositorio: repoConDatos(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assertEquals(resultado.accion, { tipo: "ir_a", destino: "metas" });
  assertEquals(resultado.aviso, AVISO_SIMULACION);
  assertEquals(resultado.motivo, "simulacion:meta_plazo:sin_clave");
  assert(resultado.respuesta.includes("$3.000.000"));
});

Deno.test("respuesta: P027 sin precio responde con la plantilla y sin llamar a Gemini", async () => {
  // La meta tiene plazo pero no precio: no hay cifra que redactar, solo
  // preguntar el precio, así que se responde con la plantilla y no se usa red.
  let llamado = false;
  const fetchQueFalla = (async () => {
    llamado = true;
    throw new Error("no debe llamarse");
  }) as unknown as typeof fetch;

  const resultado = await responderSimulacion(
    "ahorrando lo que ahorro ahora llego a comprar un portatil en diciembre?",
    "usuario-1",
    {
      repositorio: repoConDatos(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueFalla,
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(llamado, false);
  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.motivo, "simulacion:meta_plazo:sin_precio");
  assertEquals(resultado.aviso, AVISO_SIMULACION);
  assertEquals(resultado.accion, { tipo: "ir_a", destino: "metas" });
  assert(resultado.respuesta.includes("tendrías"));
  assert(resultado.respuesta.includes("¿Cuánto cuesta el portatil?"));
});

Deno.test("respuesta: texto cortado de Gemini cae a la plantilla", async () => {
  const resultado = await responderSimulacion(
    MENSAJE_OBJETIVO,
    "usuario-1",
    {
      repositorio: repoConDatos(),
      grupos: gruposFalsos(),
      // Termina a mitad de la frase: no cierra con . ! ? » " )
      fetchFn: fetchQueResponde(
        "Necesitas apartar $500.000 al mes durante 12 meses; con tu excedente",
      ),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.origen, "calculo");
  assertEquals(
    resultado.motivo,
    "simulacion:objetivo_plazo:validacion:truncado",
  );
  assert(
    resultado.respuesta.includes(
      "Para tener $6.000.000 en 12 meses necesitas ahorrar $500.000 al mes.",
    ),
  );
});

Deno.test("respuesta: historial insuficiente lo advierte y usa lo que haya", async () => {
  const resultado = await responderSimulacion(
    "¿me alcanza para una cuota de 400 mil al mes?",
    "usuario-1",
    {
      repositorio: repoFalso(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assert(resultado.respuesta.startsWith("Todavía tengo pocos registros tuyos"));
  assert(resultado.respuesta.includes("$400.000"));
  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.motivo, "simulacion:capacidad_pago:sin_clave");
  assertEquals(resultado.aviso, AVISO_SIMULACION);
  assertEquals(resultado.accion, undefined);
});

Deno.test("respuesta: el recorte usa un gasto de domicilios solo del mes actual", async () => {
  const repositorio = repoFalso({
    // Único egreso, y es de este mes: solo entra por la ventana de 90 días.
    transacciones: [
      { categoria_id: "c1", tipo: "egreso", monto: 300_000, fecha: "2026-10-10" },
    ],
    categorias: CATEGORIAS,
  });

  const resultado = await responderSimulacion(
    "si dejo de gastar en domicilios",
    "usuario-1",
    {
      repositorio,
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.motivo, "simulacion:recorte:sin_clave");
  assert(resultado.respuesta.includes("Comidas fuera y domicilios"));
  assert(resultado.respuesta.includes("$100.000"));
});

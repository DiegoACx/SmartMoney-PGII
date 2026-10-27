// ============================================================================
// Pruebas de pedir_consejo.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red ni Supabase: repositorio falso con 3 meses de historial, clasificador
// de grupos falso y `fetch` falso. Se cubre el excedente positivo y negativo,
// los hallazgos del motor, el respaldo sin Gemini y el rechazo de cifras.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import type { ClasificadorGrupos } from "./clasificadores.ts";
import { formatearCOP } from "../_shared/gemini.ts";
import type { PerfilFinanciero } from "./perfil_financiero.ts";
import {
  AVISO_CONSEJO,
  baseMencionada,
  calcularDistribucion,
  esDistribucion,
  responderConsejo,
} from "./pedir_consejo.ts";
import type {
  FilaAporte,
  FilaCategoria,
  FilaHallazgo,
  FilaLeccion,
  FilaMeta,
  FilaTransaccion,
  RepositorioChat,
} from "./repositorio.ts";

const AHORA = new Date("2026-10-21T15:00:00Z"); // 2026-10-21 en Bogotá

const CATEGORIAS: FilaCategoria[] = [
  { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
  { id: "c2", nombre: "Transporte", grupo_id: 7 },
];

/** Historial con excedente positivo: ingreso 2.000.000 y gasto 1.000.000. */
const INGRESOS_POSITIVOS: FilaTransaccion[] = [
  { categoria_id: null, tipo: "ingreso", monto: 2_000_000, fecha: "2026-07-10" },
  { categoria_id: null, tipo: "ingreso", monto: 2_000_000, fecha: "2026-08-10" },
  { categoria_id: null, tipo: "ingreso", monto: 2_000_000, fecha: "2026-09-10" },
];

const EGRESOS: FilaTransaccion[] = [
  { categoria_id: "c1", tipo: "egreso", monto: 500_000, fecha: "2026-08-15" },
  { categoria_id: "c1", tipo: "egreso", monto: 500_000, fecha: "2026-09-10" },
  { categoria_id: "c2", tipo: "egreso", monto: 300_000, fecha: "2026-09-25" },
];

const APORTES: FilaAporte[] = [
  { meta_id: "m1", monto: 300_000, fecha: "2026-09-25" },
];

const METAS: FilaMeta[] = [{
  id: "m1",
  nombre: "Viaje",
  monto_objetivo: 3_000_000,
  monto_actual: 1_200_000,
  fecha_limite: "2027-04-30",
  cumplida: false,
}];

/** Clasificador falso con nombres por grupo. */
function gruposFalsos(): ClasificadorGrupos {
  const nombres: Record<number, string> = {
    11: "Comidas fuera y domicilios",
    7: "Transporte",
  };
  return {
    predecir: () => ({ grupo_id: 11, confianza: 0.8, top3: [] }),
    nombreGrupo: (grupoId) => nombres[grupoId] ?? "Otros",
  };
}

/** Repositorio falso del consejo. */
function repoConsejo(datos: {
  transacciones?: FilaTransaccion[];
  aportes?: FilaAporte[];
  metas?: FilaMeta[];
  hallazgos?: FilaHallazgo[];
  lecciones?: FilaLeccion[];
} = {}): RepositorioChat {
  const transacciones = datos.transacciones ?? [];
  const aportes = datos.aportes ?? [];
  return {
    contarMensajesUsuario: () => Promise.resolve(0),
    ultimoMensajeAsistente: () => Promise.resolve(null),
    insertarMensaje: () => Promise.resolve(),
    leerTransacciones: (_usuarioId, desde, hasta, tipo) =>
      Promise.resolve(
        transacciones.filter((fila) =>
          fila.tipo === tipo && fila.fecha >= desde && fila.fecha <= hasta
        ),
      ),
    leerCategorias: () => Promise.resolve(CATEGORIAS),
    leerMetasActivas: () => Promise.resolve(datos.metas ?? []),
    leerAportes: (_usuarioId, desde, hasta) =>
      Promise.resolve(
        aportes.filter((fila) => fila.fecha >= desde && fila.fecha <= hasta),
      ),
    leerLeccionesValidas: () => Promise.resolve(datos.lecciones ?? []),
    leerHallazgosRecientes: () => Promise.resolve(datos.hallazgos ?? []),
  };
}

/** Historial con los gastos por encima de los ingresos (excedente −500.000). */
function repoExcedenteNegativo(): RepositorioChat {
  // Ingreso solo del mes en curso: 500.000. Gastos de los 3 meses completos
  // (jul–sep): 1.000.000 al mes (3.000.000 ÷ 3), así que el excedente es
  // 500.000 − 1.000.000 = −500.000.
  const egresos: FilaTransaccion[] = [
    { categoria_id: "c1", tipo: "egreso", monto: 1_000_000, fecha: "2026-07-20" },
    { categoria_id: "c1", tipo: "egreso", monto: 1_000_000, fecha: "2026-08-15" },
    { categoria_id: "c1", tipo: "egreso", monto: 1_000_000, fecha: "2026-09-10" },
  ];
  return repoConsejo({
    transacciones: [
      { categoria_id: null, tipo: "ingreso", monto: 500_000, fecha: "2026-10-05" },
      ...egresos,
    ],
  });
}

/** `fetch` falso que responde 200 con el texto dado. */
function fetchQueResponde(texto: string): typeof fetch {
  return (() =>
    Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: texto }] } }] }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    )) as unknown as typeof fetch;
}

/** `fetch` falso que guarda el cuerpo enviado y responde con el texto dado. */
function fetchQueCaptura(texto: string, capturado: { cuerpo?: string }): typeof fetch {
  return ((_url: string, init?: { body?: string }) => {
    capturado.cuerpo = init?.body ?? "";
    return Promise.resolve(
      new Response(
        JSON.stringify({ candidates: [{ content: { parts: [{ text: texto }] } }] }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      ),
    );
  }) as unknown as typeof fetch;
}

/** `fetch` falso que responde 429 (cuota agotada) en cualquier modelo. */
const fetch429 = (() =>
  Promise.resolve(
    new Response(
      JSON.stringify({ error: { code: 429, status: "RESOURCE_EXHAUSTED" } }),
      { status: 429, headers: { "Content-Type": "application/json" } },
    ),
  )) as unknown as typeof fetch;

// --- Con Gemini ---------------------------------------------------------------

Deno.test("consejo con excedente positivo: usa Gemini y agrega el aviso", async () => {
  const texto =
    "Revisa primero tu fondo de emergencia y después ataca la deuda más cara. Compara siempre la tasa efectiva anual antes de decidir.";
  const resultado = await responderConsejo(
    "¿pago la deuda o invierto?",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
      }),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde(texto),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.respuesta, texto);
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.motivo, "consejo");
  assertEquals(resultado.aviso, AVISO_CONSEJO);
});

Deno.test("consejo: el contexto enviado incluye hallazgos y grupos de gasto", async () => {
  const capturado: { cuerpo?: string } = {};
  const hallazgos: FilaHallazgo[] = [{
    tipo: "sobregasto_categoria",
    datos: { nombre_categoria: "Comidas fuera y domicilios", gastado_mes: 250_000 },
    creado_en: "2026-10-20T10:00:00Z",
  }];

  await responderConsejo(
    "dame un consejo para mis finanzas",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
        hallazgos,
      }),
      grupos: gruposFalsos(),
      fetchFn: fetchQueCaptura("Revisa tu gasto y ajusta el presupuesto del mes.", capturado),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  // El cuerpo viaja como JSON, así que las comillas de los nombres llegan
  // escapadas (\"Viaje\"); se desescapan para comprobar el texto del prompt.
  const cuerpo = (capturado.cuerpo ?? "").replace(/\\"/g, '"');
  assert(cuerpo.includes("Hallazgo sobregasto_categoria"));
  assert(cuerpo.includes("Comidas fuera y domicilios"));
  assert(cuerpo.includes("$250.000"));
  assert(cuerpo.includes("Grupo donde más gastas"));
  assert(cuerpo.includes('Meta ("Viaje") le falta'));
});

Deno.test("consejo: rechaza cifras inventadas y cae a la plantilla", async () => {
  const resultado = await responderConsejo(
    "dame un consejo para mis finanzas",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
      }),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("Podrías ahorrar $9.999.999 el próximo mes."),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.origen, "plantilla");
  assertEquals(
    resultado.motivo,
    "consejo:validacion:cifra_no_permitida:9999999",
  );
  assertEquals(resultado.aviso, AVISO_CONSEJO);
  assert(resultado.respuesta.startsWith("Dos pasos concretos para empezar:"));
});

Deno.test("consejo: 429 de Gemini cae a la plantilla y el motivo lo deja claro", async () => {
  const resultado = await responderConsejo(
    "dame un consejo para mis finanzas",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
      }),
      grupos: gruposFalsos(),
      fetchFn: fetch429,
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.origen, "plantilla");
  assertEquals(resultado.motivo, "consejo:gemini_429_ambos_plantilla");
  assertEquals(resultado.aviso, AVISO_CONSEJO);
  assert(resultado.respuesta.startsWith("Dos pasos concretos para empezar:"));
});

Deno.test("consejo: acepta como válida una cifra del mensaje («1 millon» → $1.000.000)", async () => {
  const texto =
    "Con esa prima de $1.000.000, abonar a la deuda suele convenir más que un ahorro si su tasa es alta.";
  const resultado = await responderConsejo(
    "tengo una prima de 1 millon, la meto a un cdt o abono a la deuda?",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
      }),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde(texto),
      claveLLM: "clave-de-prueba",
    },
    AHORA,
  );

  assertEquals(resultado.respuesta, texto);
  assertEquals(resultado.origen, "llm");
  assertEquals(resultado.motivo, "consejo");
});

Deno.test("consejo sin Gemini y decisión: da criterios para decidir", async () => {
  const resultado = await responderConsejo(
    "tengo una prima de 1 millon, la meto a un cdt o abono a la deuda?",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
      }),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assertEquals(resultado.origen, "plantilla");
  assertEquals(resultado.motivo, "consejo:sin_clave");
  assertEquals(resultado.aviso, AVISO_CONSEJO);
  assert(resultado.respuesta.includes("tasa efectiva anual"));
  assert(resultado.respuesta.includes("fondo de emergencia"));
  assert(resultado.respuesta.includes("abonar a esa deuda"));
  // No son los pasos genéricos (grupo de gasto / meta).
  assertEquals(resultado.respuesta.includes("donde más gastas"), false);
});

// --- Sin Gemini: plantilla con los datos del usuario --------------------------

Deno.test("consejo sin Gemini: dos pasos con el mayor gasto y la meta", async () => {
  const resultado = await responderConsejo(
    "dame un consejo para mis finanzas",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
      }),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assertEquals(resultado.origen, "plantilla");
  assertEquals(resultado.motivo, "consejo:sin_clave");
  assertEquals(resultado.aviso, AVISO_CONSEJO);
  assert(resultado.respuesta.includes("- revisa"));
  assert(resultado.respuesta.includes("Comidas fuera y domicilios"));
  assert(resultado.respuesta.includes('"Viaje"'));
});

Deno.test("consejo con excedente negativo: el primer paso es equilibrar", async () => {
  const resultado = await responderConsejo(
    "dame un consejo para mis finanzas",
    "usuario-1",
    {
      repositorio: repoExcedenteNegativo(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assertEquals(resultado.origen, "plantilla");
  assert(resultado.respuesta.includes("- equilibra primero tus gastos con tus ingresos"));
  assert(
    resultado.respuesta.includes("tus gastos superan tus ingresos en $500.000 al mes"),
  );
  assertEquals(resultado.respuesta.includes("-$"), false);
});

// --- Lección sugerida por el motor -------------------------------------------

Deno.test("consejo: un hallazgo de lección sugerida ofrece abrir la lección", async () => {
  const resultado = await responderConsejo(
    "dame un consejo para mis finanzas",
    "usuario-1",
    {
      repositorio: repoConsejo({
        transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
        aportes: APORTES,
        metas: METAS,
        lecciones: [{
          id: "e12",
          titulo: "Separar la plata en sobres",
          contenido: "Separar la plata en sobres te ayuda a no gastar de más.",
        }],
        hallazgos: [{
          tipo: "leccion_sugerida",
          datos: { escalon_id: "e12", titulo: "Separar la plata en sobres" },
          creado_en: "2026-10-20T10:00:00Z",
        }],
      }),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se debe usar"),
      claveLLM: null,
    },
    AHORA,
  );

  assertEquals(resultado.accion, { tipo: "abrir_leccion", escalon_id: "e12" });
});

// --- Casos reales del piloto (pruebas de Juanjo) -----------------------------

const CASO_A =
  "estoy pensando en invertir en un cdt, en cual me recomiendas comenzar a invertir?";
const CASO_C1 = "como deberia dividir mi dinero, que deberia ir a cada punto ?";
const CASO_C2 = "pero cuanto para cada cosa ? que porcentaje?";
const CASO_D = "y como seria un buen plan para administrar mis 300 en todo el mes ?";

/** Repositorio con ingreso 2.000.000 y gastos en comidas y transporte. */
function repoPositivo(): RepositorioChat {
  return repoConsejo({
    transacciones: [...INGRESOS_POSITIVOS, ...EGRESOS],
    aportes: APORTES,
    metas: METAS,
  });
}

Deno.test("caso A sin Gemini: habla del CDT y no recomienda entidades", async () => {
  const r = await responderConsejo(CASO_A, "u1", {
    repositorio: repoPositivo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueResponde("no se usa"),
    claveLLM: null,
  }, AHORA);
  assertEquals(r.origen, "plantilla");
  assert(r.respuesta.includes("CDT"), r.respuesta);
  assert(r.respuesta.includes("no te puedo recomendar una entidad"), r.respuesta);
  assert(r.respuesta.includes("tasa efectiva anual"), r.respuesta);
  assert(r.respuesta.includes("Superintendencia Financiera"), r.respuesta);
  // Ya no responde con los "pasos con el mayor gasto" ignorando la pregunta.
  assert(!r.respuesta.includes("Dos pasos concretos"), r.respuesta);
  assert(!/DIAN/.test(r.respuesta), r.respuesta);
});

Deno.test("caso A con Gemini: el prompt lleva la pregunta y el tema CDT", async () => {
  const capturado: { cuerpo?: string } = {};
  const texto =
    "Un CDT puede servirte si la plata que inviertes no la vas a necesitar pronto.\n\n- Compara la **tasa efectiva anual** y el plazo.\n- Revisa que la entidad esté vigilada.\n\nAsí eliges con criterio.";
  const r = await responderConsejo(CASO_A, "u1", {
    repositorio: repoPositivo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueCaptura(texto, capturado),
    claveLLM: "clave",
  }, AHORA);
  assertEquals(r.origen, "llm");
  const cuerpo = capturado.cuerpo ?? "";
  assert(cuerpo.includes("responde a esto primero"), cuerpo);
  assert(cuerpo.includes("Tema de la pregunta: CDT"), cuerpo);
  assert(cuerpo.includes("Nunca nombres bancos"), cuerpo);
});

Deno.test("consejo: si Gemini menciona la DIAN sin que la pidan, cae a la plantilla", async () => {
  const texto =
    "Organiza tu plata con calma.\n\n- Ten un fondo de emergencia.\n- Si tienes dudas tributarias, consulta a la DIAN.\n\nVas bien.";
  const r = await responderConsejo("como puedo ahorrar más?", "u1", {
    repositorio: repoPositivo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueResponde(texto),
    claveLLM: "clave",
  }, AHORA);
  assertEquals(r.origen, "plantilla");
  assertEquals(r.motivo, "consejo:validacion:tema_no_pedido");
  assert(!/DIAN/.test(r.respuesta), r.respuesta);
});

Deno.test("consejo: si el usuario pregunta por impuestos, Gemini sí puede nombrar la DIAN", async () => {
  const texto =
    "Para saber si debes declarar, revisa los topes del año.\n\n- Consulta la DIAN o a un contador.\n\nAsí sales de dudas.";
  const r = await responderConsejo("tengo dudas con los impuestos, que hago?", "u1", {
    repositorio: repoPositivo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueResponde(texto),
    claveLLM: "clave",
  }, AHORA);
  assertEquals(r.origen, "llm");
});

Deno.test("esDistribucion: captura el reparto y no roba simulaciones ni consultas", () => {
  for (const sí of [CASO_C1, CASO_C2, CASO_D, "como reparto mi sueldo", "ayudame con un presupuesto"]) {
    assert(esDistribucion(sí), sí);
  }
  for (const no of [
    "si ahorro el 15% en vez del 5% cuanto antes llego a la meta",
    "¿Qué porcentaje de lo que gano se me va en deudas?",
    "Administrar en porcentajes",
    "Plan de ahorro",
    "cuanto gaste en comida",
  ]) {
    assert(!esDistribucion(no), no);
  }
});

Deno.test("baseMencionada: 'mis 300' son $300.000 y un monto absurdo se ignora", () => {
  assertEquals(baseMencionada(CASO_D, 2_000_000), 300_000);
  assertEquals(baseMencionada("tengo 1.200.000 para el mes", 2_000_000), 1_200_000);
  assertEquals(baseMencionada(CASO_C1, 2_000_000), null);
  assertEquals(baseMencionada("reparto 900 millones", 2_000_000), null);
});

Deno.test("calcularDistribucion: 50/30/20 sobre el ingreso y ajuste si las necesidades pasan del 50 %", () => {
  const perfil: PerfilFinanciero = {
    ingreso_mensual: 1_000_000,
    gasto_mensual: 800_000,
    gasto_trabajo_mensual: 0,
    excedente_mensual: 200_000,
    ahorro_mensual: 0,
    // Mercado (1) y Transporte (7) son necesidades; Comidas fuera (11), gusto.
    gasto_mensual_por_grupo: new Map([[1, 500_000], [7, 200_000], [11, 100_000]]),
    metas: [],
    historial_insuficiente: false,
  };
  const dist = calcularDistribucion(perfil, CASO_C1);
  assertEquals(dist.base, 1_000_000);
  assertEquals(dist.origen_base, "ingreso");
  assertEquals(dist.partes.map((p) => [p.nombre, p.porcentaje, p.monto]), [
    ["Necesidades", 50, 500_000],
    ["Gustos", 30, 300_000],
    ["Ahorro", 20, 200_000],
  ]);
  assertEquals(dist.necesidades_actual_pct, 70);
  assertEquals(dist.ajuste, { necesidades: 70, gustos: 20, ahorro: 10 });
});

Deno.test("caso C sin Gemini: responde con porcentajes y montos calculados", async () => {
  for (const mensaje of [CASO_C1, CASO_C2]) {
    const r = await responderConsejo(mensaje, "u1", {
      repositorio: repoPositivo(),
      grupos: gruposFalsos(),
      fetchFn: fetchQueResponde("no se usa"),
      claveLLM: null,
    }, AHORA);
    assertEquals(r.origen, "plantilla");
    assert(r.motivo.startsWith("consejo:distribucion"), r.motivo);
    // Ingreso de 2.000.000 → 1.000.000 / 600.000 / 400.000.
    assert(r.respuesta.includes(`Necesidades (50 %): ${formatearCOP(1_000_000)}`), r.respuesta);
    assert(r.respuesta.includes(`Gustos (30 %): ${formatearCOP(600_000)}`), r.respuesta);
    assert(r.respuesta.includes(`Ahorro (20 %): ${formatearCOP(400_000)}`), r.respuesta);
    assert(r.respuesta.includes("referencia general"), r.respuesta);
    assertEquals(r.aviso, AVISO_CONSEJO);
  }
});

Deno.test("caso C con Gemini: si omite una cifra calculada cae a la plantilla", async () => {
  const sinAhorro =
    "Te propongo repartir así.\n\n- **Necesidades (50 %): $1.000.000**\n- **Gustos (30 %): $600.000**\n\nEs una referencia general.";
  const r = await responderConsejo(CASO_C1, "u1", {
    repositorio: repoPositivo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueResponde(sinAhorro),
    claveLLM: "clave",
  }, AHORA);
  assertEquals(r.origen, "plantilla");
  assertEquals(r.motivo, "consejo:distribucion:validacion:falta_cifra_obligatoria");

  const completo =
    "Así podrías repartir tu ingreso.\n\n- **Necesidades (50 %): $1.000.000**\n- **Gustos (30 %): $600.000**\n- **Ahorro (20 %): $400.000**\n\nEs una referencia general, no una regla fija.";
  const ok = await responderConsejo(CASO_C1, "u1", {
    repositorio: repoPositivo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueResponde(completo),
    claveLLM: "clave",
  }, AHORA);
  assertEquals(ok.origen, "llm");
  assertEquals(ok.motivo, "consejo:distribucion");
});

Deno.test("caso D sin Gemini: reparte los $300.000 que menciona y no habla de la DIAN", async () => {
  const r = await responderConsejo(CASO_D, "u1", {
    repositorio: repoPositivo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueResponde("no se usa"),
    claveLLM: null,
  }, AHORA);
  assert(r.respuesta.includes(formatearCOP(300_000)), r.respuesta);
  assert(r.respuesta.includes(`Necesidades (50 %): ${formatearCOP(150_000)}`), r.respuesta);
  assert(r.respuesta.includes(`Gustos (30 %): ${formatearCOP(90_000)}`), r.respuesta);
  assert(r.respuesta.includes(`Ahorro (20 %): ${formatearCOP(60_000)}`), r.respuesta);
  assert(!/DIAN|impuesto/i.test(r.respuesta), r.respuesta);
});

Deno.test("distribución con gastos por encima de los ingresos: primero equilibrar", async () => {
  const r = await responderConsejo(CASO_C1, "u1", {
    repositorio: repoExcedenteNegativo(),
    grupos: gruposFalsos(),
    fetchFn: fetchQueResponde("no se usa"),
    claveLLM: null,
  }, AHORA);
  assert(r.respuesta.startsWith("Antes de repartir"), r.respuesta);
  assert(r.respuesta.includes("lo primero es equilibrar"), r.respuesta);
});

Deno.test("calcularDistribucion: si las necesidades se comen casi todo el ingreso no propone reparto", () => {
  const perfil: PerfilFinanciero = {
    ingreso_mensual: 413_527,
    gasto_mensual: 494_444,
    gasto_trabajo_mensual: 0,
    excedente_mensual: -80_917,
    ahorro_mensual: 0,
    gasto_mensual_por_grupo: new Map([[1, 222_000], [6, 200_000], [11, 41_000]]),
    metas: [],
    historial_insuficiente: false,
  };
  const dist = calcularDistribucion(perfil, "como divido mi plata");
  assertEquals(dist.necesidades_criticas, true);
  assertEquals(dist.ajuste, null);
  // Montos a miles cerrados: 413.527 → 207.000 / 124.000 / 83.000.
  assertEquals(dist.partes.map((p) => p.monto), [207_000, 124_000, 83_000]);
});

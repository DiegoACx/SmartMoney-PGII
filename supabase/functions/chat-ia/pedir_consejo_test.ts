// ============================================================================
// Pruebas de pedir_consejo.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red ni Supabase: repositorio falso con 3 meses de historial, clasificador
// de grupos falso y `fetch` falso. Se cubre el excedente positivo y negativo,
// los hallazgos del motor, el respaldo sin Gemini y el rechazo de cifras.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import type { ClasificadorGrupos } from "./clasificadores.ts";
import { AVISO_CONSEJO, responderConsejo } from "./pedir_consejo.ts";
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
  assert(resultado.respuesta.startsWith("1. "));
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
  assert(resultado.respuesta.startsWith("1. "));
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
  assert(resultado.respuesta.startsWith("1. revisa"));
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
  assert(resultado.respuesta.startsWith("1. equilibra primero tus gastos con tus ingresos"));
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

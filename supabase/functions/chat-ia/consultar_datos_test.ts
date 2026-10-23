// ============================================================================
// Pruebas de consultar_datos.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: se inyecta un repositorio falso y un clasificador de grupos falso.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import type { ClasificadorGrupos } from "./clasificadores.ts";
import { responderConsultaDatos, UMBRAL_GRUPO } from "./consultar_datos.ts";
import type {
  FilaCategoria,
  FilaMeta,
  FilaTransaccion,
  RepositorioChat,
} from "./repositorio.ts";

const AHORA = new Date("2026-10-21T15:00:00Z"); // miércoles en Bogotá

interface Datos {
  transacciones?: FilaTransaccion[];
  categorias?: FilaCategoria[];
  metas?: FilaMeta[];
}

function repoFalso(datos: Datos = {}): RepositorioChat {
  return {
    contarMensajesUsuario: async () => 0,
    ultimoMensajeAsistente: async () => null,
    insertarMensaje: async () => {},
    leerTransacciones: async () => datos.transacciones ?? [],
    leerCategorias: async () => datos.categorias ?? [],
    leerMetasActivas: async () => datos.metas ?? [],
  };
}

/** Clasificador de grupos de prueba: siempre el grupo 11 con la confianza dada. */
function gruposFalsos(confianza = 0.9): ClasificadorGrupos {
  return {
    predecir: () => ({
      grupo_id: 11,
      confianza,
      top3: [{ grupo_id: 11, prob: confianza }],
    }),
    nombreGrupo: () => "Comidas fuera y domicilios",
  };
}

Deno.test("el umbral de grupo es 0.6", () => {
  assertEquals(UMBRAL_GRUPO, 0.6);
});

Deno.test("total de la semana con las 3 categorías principales", async () => {
  const resultado = await responderConsultaDatos(
    "¿cuánto llevo gastado esta semana?",
    "usuario-1",
    {
      repositorio: repoFalso({
        transacciones: [
          { categoria_id: "c1", tipo: "egreso", monto: 50000, fecha: "2026-10-20" },
          { categoria_id: "c2", tipo: "egreso", monto: 35000, fecha: "2026-10-21" },
        ],
        categorias: [
          { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
          { id: "c2", nombre: "Transporte", grupo_id: 7 },
        ],
      }),
      grupos: gruposFalsos(),
    },
    AHORA,
  );

  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.motivo, "total_egresos");
  assert(resultado.respuesta.includes("Esta semana llevas $85.000 en gastos"));
  assert(resultado.respuesta.includes("$50.000"));
  assert(resultado.respuesta.includes("$35.000"));
  // Sin grupo concreto en un mensaje genérico → top 3 categorías y sin acción.
  assertEquals(resultado.accion, undefined);
});

Deno.test("desglose por grupo cuando el mensaje menciona un tema", async () => {
  const resultado = await responderConsultaDatos(
    "¿cuánto gasté en comida este mes?",
    "usuario-1",
    {
      repositorio: repoFalso({
        transacciones: [
          { categoria_id: "c1", tipo: "egreso", monto: 40000, fecha: "2026-10-10" },
          { categoria_id: "c2", tipo: "egreso", monto: 60000, fecha: "2026-10-11" },
        ],
        categorias: [
          { id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 },
          { id: "c2", nombre: "Mercado", grupo_id: 1 },
        ],
      }),
      grupos: gruposFalsos(0.9),
    },
    AHORA,
  );

  assertEquals(resultado.motivo, "grupo:Comidas fuera y domicilios");
  assert(
    resultado.respuesta.includes(
      "Este mes llevas $100.000 en gastos, el 40 % en Comidas fuera y domicilios.",
    ),
  );
});

Deno.test("con baja confianza de grupo se responde el total", async () => {
  const resultado = await responderConsultaDatos(
    "¿cuánto gasté en comida este mes?",
    "usuario-1",
    {
      repositorio: repoFalso({
        transacciones: [
          { categoria_id: "c1", tipo: "egreso", monto: 40000, fecha: "2026-10-10" },
        ],
        categorias: [{ id: "c1", nombre: "Comidas fuera y domicilios", grupo_id: 11 }],
      }),
      grupos: gruposFalsos(0.3), // por debajo de UMBRAL_GRUPO
    },
    AHORA,
  );

  assertEquals(resultado.motivo, "total_egresos");
});

Deno.test("ingresos: total recibido y principales fuentes", async () => {
  const resultado = await responderConsultaDatos(
    "¿cuánto recibí este mes?",
    "usuario-1",
    {
      repositorio: repoFalso({
        transacciones: [
          { categoria_id: "c1", tipo: "ingreso", monto: 500000, fecha: "2026-10-05" },
        ],
        categorias: [{ id: "c1", nombre: "Trabajo independiente", grupo_id: null }],
      }),
      grupos: gruposFalsos(),
    },
    AHORA,
  );

  assertEquals(resultado.motivo, "total_ingresos");
  assert(resultado.respuesta.includes("Este mes recibiste $500.000 en ingresos"));
  assert(resultado.respuesta.includes("Trabajo independiente ($500.000)"));
});

Deno.test("metas: una meta muestra porcentaje y cuánto falta", async () => {
  const resultado = await responderConsultaDatos(
    "¿cómo van mis metas?",
    "usuario-1",
    {
      repositorio: repoFalso({
        metas: [
          {
            id: "m1",
            nombre: "Viaje a Cartagena",
            monto_objetivo: 1000000,
            monto_actual: 500000,
            fecha_limite: "2026-12-31",
            cumplida: false,
          },
        ],
      }),
      grupos: gruposFalsos(),
    },
    AHORA,
  );

  assertEquals(resultado.motivo, "metas_una");
  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.accion, { tipo: "ir_a", destino: "metas" });
  assert(resultado.respuesta.includes("el 50 %"));
  assert(resultado.respuesta.includes("$500.000"));
  assert(resultado.respuesta.includes("31/12/2026"));
});

Deno.test("metas: sin metas activas invita a crearlas", async () => {
  const resultado = await responderConsultaDatos(
    "¿cómo van mis metas?",
    "usuario-1",
    { repositorio: repoFalso({ metas: [] }), grupos: gruposFalsos() },
    AHORA,
  );

  assertEquals(resultado.motivo, "metas_vacio");
  assert(resultado.respuesta.includes("no tienes metas de ahorro activas"));
  assertEquals(resultado.accion, { tipo: "ir_a", destino: "metas" });
});

Deno.test("sin datos: mensaje amable que invita a registrar", async () => {
  const resultado = await responderConsultaDatos(
    "¿cuánto gasté hoy?",
    "usuario-1",
    { repositorio: repoFalso(), grupos: gruposFalsos() },
    AHORA,
  );

  assertEquals(resultado.motivo, "sin_datos");
  assertEquals(resultado.origen, "calculo");
  assertEquals(resultado.accion, { tipo: "ir_a", destino: "movimientos" });
  assert(resultado.respuesta.includes("No veo gastos tuyos hoy"));
});

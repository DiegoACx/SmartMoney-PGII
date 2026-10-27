// ============================================================================
// Pruebas de bandido.ts  (deno test)
// ----------------------------------------------------------------------------
// Todo con semilla fija (mulberry32): resultados reproducibles, sin red.
// ============================================================================

import { assert, assertAlmostEquals, assertEquals } from "jsr:@std/assert@1";

import { M_PRIOR, MU_DISENO, PESO_TIPO_CONTROL } from "./config.ts";
import {
  type Conteos,
  conteosPoblacionSinUsuario,
  grupoExperimento,
  mediaPoblacion,
  muestraBeta,
  mulberry32,
  parametrosUsuario,
  pesosParaUsuario,
} from "./bandido.ts";

/** Conteos de utilidad de un tipo a partir de sus conteos crudos. */
function conteos(tipo: string, utiles: number, noUtiles: number): Conteos {
  return { [tipo]: { utiles, no_utiles: noUtiles } };
}

// --- Distribuciones ----------------------------------------------------------

Deno.test("muestraBeta(2, 8) promedia ≈ 0,2 y siempre cae en (0,1)", () => {
  const rng = mulberry32(12345);
  const muestras: number[] = [];
  for (let i = 0; i < 5000; i++) {
    const valor = muestraBeta(2, 8, rng);
    assert(valor > 0 && valor < 1, `muestra fuera de (0,1): ${valor}`);
    muestras.push(valor);
  }
  const promedio = muestras.reduce((a, b) => a + b, 0) / muestras.length;
  assertAlmostEquals(promedio, 0.2, 0.02);
});

Deno.test("muestraBeta con forma < 1 no devuelve NaN", () => {
  const rng = mulberry32(7);
  for (let i = 0; i < 1000; i++) {
    const valor = muestraBeta(0.5, 0.5, rng);
    assert(Number.isFinite(valor), `valor no finito: ${valor}`);
    assert(valor >= 0 && valor <= 1, `valor fuera de [0,1]: ${valor}`);
  }
});

// --- Prior jerárquico --------------------------------------------------------

Deno.test("mediaPoblacion sin datos es exactamente μ_diseño", () => {
  assertAlmostEquals(mediaPoblacion("logro", {}), MU_DISENO.logro, 1e-12);
  assertAlmostEquals(
    mediaPoblacion("sobregasto_categoria", {}),
    MU_DISENO.sobregasto_categoria,
    1e-12,
  );
});

Deno.test("mediaPoblacion con muchos útiles tiende a la tasa observada", () => {
  // Tasa observada 1,0 con 10.000 respuestas positivas.
  assertAlmostEquals(
    mediaPoblacion("gasto_anomalo", conteos("gasto_anomalo", 10000, 0)),
    1,
    0.01,
  );
  // Tasa observada 0,75 con volumen suficiente.
  assertAlmostEquals(
    mediaPoblacion("gasto_anomalo", conteos("gasto_anomalo", 300, 100)),
    0.75,
    0.02,
  );
});

Deno.test("parametrosUsuario sin clics arranca del prior (α+β = M_PRIOR)", () => {
  const mu = mediaPoblacion("logro", {});
  const { alfa, beta } = parametrosUsuario("logro", {}, mu);
  assertAlmostEquals(alfa + beta, M_PRIOR, 1e-12);
  assertAlmostEquals(alfa / (alfa + beta), mu, 1e-12);
});

Deno.test("parametrosUsuario con 10 útiles y 0 no útiles sube sobre la población", () => {
  const mu = mediaPoblacion("logro", {});
  const { alfa, beta } = parametrosUsuario("logro", conteos("logro", 10, 0), mu);
  assert(alfa / (alfa + beta) > mu, "la media del usuario debe superar la de la población");
});

Deno.test("leave-one-out: si solo respondió el propio usuario, μ_poblacion = μ_diseño", () => {
  const usuario = conteos("logro", 3, 1);
  // Los globales son exactamente sus propias respuestas.
  const poblacion = conteosPoblacionSinUsuario(usuario, usuario);
  assertEquals(poblacion["logro"], { utiles: 0, no_utiles: 0 });
  assertAlmostEquals(mediaPoblacion("logro", poblacion), MU_DISENO.logro, 1e-12);

  // Y el prior del usuario arranca de μ_diseño más sus clics.
  const { alfa, beta } = parametrosUsuario(
    "logro",
    usuario,
    mediaPoblacion("logro", poblacion),
  );
  assertAlmostEquals(alfa, M_PRIOR * MU_DISENO.logro + 3, 1e-12);
  assertAlmostEquals(beta, M_PRIOR * (1 - MU_DISENO.logro) + 1, 1e-12);
});

Deno.test("leave-one-out: nunca resta por debajo de cero", () => {
  const poblacion = conteosPoblacionSinUsuario(
    conteos("logro", 1, 0),
    conteos("logro", 5, 4),
  );
  assertEquals(poblacion["logro"], { utiles: 0, no_utiles: 0 });
});

// --- A/B ---------------------------------------------------------------------

Deno.test("grupoExperimento es determinístico y reparte cerca de 50/50", () => {
  assertEquals(grupoExperimento("abc"), grupoExperimento("abc"));
  assertEquals(grupoExperimento("abc"), grupoExperimento("abc"));

  const rng = mulberry32(2026);
  let bandido = 0;
  const total = 1000;
  for (let i = 0; i < total; i++) {
    let uuid = "";
    for (let j = 0; j < 32; j++) {
      uuid += Math.floor(rng() * 16).toString(16);
    }
    if (grupoExperimento(uuid) === "bandido") bandido++;
  }
  assert(
    bandido > total * 0.4 && bandido < total * 0.6,
    `reparto desbalanceado: ${bandido}/${total} en bandido`,
  );
});

// --- Pesos -------------------------------------------------------------------

Deno.test("pesosParaUsuario en 'control' devuelve los pesos de diseño", () => {
  const resultado = pesosParaUsuario("control", {}, {}, mulberry32(1));
  assertEquals(resultado.grupo, "control");
  assertEquals(resultado.pesos, PESO_TIPO_CONTROL);
});

Deno.test("pesosParaUsuario en 'bandido' usa Beta(α, β) y deja α/β trazables", () => {
  const usuario = conteos("aporte_meta", 4, 1);
  const globales = conteos("aporte_meta", 40, 10);
  const resultado = pesosParaUsuario("bandido", usuario, globales, mulberry32(99));

  assertEquals(resultado.grupo, "bandido");
  const esperado = parametrosUsuario(
    "aporte_meta",
    usuario,
    mediaPoblacion(
      "aporte_meta",
      conteosPoblacionSinUsuario(globales, usuario),
    ),
  );
  assertAlmostEquals(resultado.alfa["aporte_meta"], esperado.alfa, 1e-12);
  assertAlmostEquals(resultado.beta["aporte_meta"], esperado.beta, 1e-12);
  assert(resultado.pesos["aporte_meta"] > 0 && resultado.pesos["aporte_meta"] < 1);
});

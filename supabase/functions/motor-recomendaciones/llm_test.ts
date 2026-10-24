// ============================================================================
// Pruebas de llm.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: la llamada a Gemini se sustituye por un fetch falso y la clave se
// inyecta por parámetro, así que no hace falta --allow-env ni --allow-net.
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import {
  GEMINI_MODELO,
  GEMINI_MODELO_RESPALDO,
  LLM_MAX_CARACTERES,
  type TipoHallazgo,
} from "./config.ts";
import {
  type ResultadoLLM,
  cifrasPermitidas,
  redactarConGemini,
  validarTextoLLM,
} from "./llm.ts";
import { textoRecomendacion } from "./plantillas.ts";
import type { HallazgoPuntuado } from "./puntaje.ts";

const CLAVE = "clave-de-prueba";

function hallazgo(
  tipo: TipoHallazgo,
  datos: Record<string, unknown>,
  objetivo = "grupo:1",
): HallazgoPuntuado {
  return {
    tipo,
    datos,
    severidad: 1,
    impacto: 1,
    p: 1,
    objetivo,
    confianza: 1,
    repeticion: 1,
    peso_tipo_usado: 1,
    puntaje: 1,
  };
}

// --- Validación del texto del LLM --------------------------------------------

Deno.test("validarTextoLLM acepta un texto con las cifras permitidas", () => {
  const texto =
    "En Mercado llevas $206.000 y vas un 15 % por debajo de tu promedio. Sigue así.";

  const resultado = validarTextoLLM(texto, ["$206.000", "15 %"]);
  assertEquals(resultado.valido, true);
  assertEquals(resultado.motivo, "ok");
});

Deno.test("validarTextoLLM quita las comillas envolventes antes de validar", () => {
  const texto = '"Te conviene apartar $206.000 este mes."';
  assertEquals(validarTextoLLM(texto, ["$206.000"]).valido, true);
});

Deno.test("validarTextoLLM rechaza una cifra inventada", () => {
  const texto = "En Mercado llevas $206.000 y cerrarías en $999.000. Bájale el ritmo.";

  const resultado = validarTextoLLM(texto, ["$206.000", "$310.000"]);
  assertEquals(resultado.valido, false);
  assertEquals(resultado.motivo, "cifra_no_permitida:999000");
});

Deno.test("validarTextoLLM rechaza un texto de más de 280 caracteres", () => {
  const texto = "a".repeat(LLM_MAX_CARACTERES + 1);
  assertEquals(validarTextoLLM(texto, []), { valido: false, motivo: "largo" });
});

Deno.test("validarTextoLLM rechaza un texto con URL", () => {
  const texto = "Revisa tu gasto en https://ejemplo.com y bájale el ritmo.";
  assertEquals(validarTextoLLM(texto, []), { valido: false, motivo: "url" });
});

Deno.test("validarTextoLLM rechaza un texto vacío", () => {
  assertEquals(validarTextoLLM("", []), { valido: false, motivo: "vacio" });
  assertEquals(validarTextoLLM("   ", []), { valido: false, motivo: "vacio" });
  assertEquals(validarTextoLLM('""', []), { valido: false, motivo: "vacio" });
});

Deno.test("validarTextoLLM rechaza un texto que no cierra la frase", () => {
  const texto = "En Mercado llevas $206.000 y vas bien, pero";
  assertEquals(validarTextoLLM(texto, ["$206.000"]), {
    valido: false,
    motivo: "truncado",
  });
});

// --- Cifras que se le envían al modelo ---------------------------------------

Deno.test("cifrasPermitidas arma las cifras por tipo de hallazgo", () => {
  assertEquals(
    cifrasPermitidas(hallazgo("sobregasto_categoria", {
      gastado_mes: 206000,
      proyeccion: 310000,
      normal_mensual: 250000,
      dias_restantes: 9,
    })),
    ["$206.000", "$310.000", "$250.000", "9"],
  );

  assertEquals(
    cifrasPermitidas(hallazgo("logro", {
      gasto_mes: 170000,
      normal_personal_mensual: 200000,
    }, "grupo:1")),
    ["$170.000", "$200.000", "15 %"],
  );
});

// --- Llamada a Gemini --------------------------------------------------------

const HALLAZGO = hallazgo("sobregasto_categoria", {
  grupo_id: 1,
  nombre_grupo: "Mercado",
  gastado_mes: 206000,
  dia_actual: 21,
  dias_mes: 30,
  dias_restantes: 9,
  proyeccion: 310000,
  normal_mensual: 250000,
});
const PLANTILLA = textoRecomendacion(HALLAZGO);

/** Respuesta de Gemini con un texto candidato. */
function conTexto(texto: string): unknown {
  return { candidates: [{ content: { parts: [{ text: texto }] } }] };
}

interface Paso {
  status: number;
  cuerpo: unknown;
}

interface Llamada {
  modelo: string;
  cuerpo: Record<string, unknown>;
}

/**
 * Fetch falso que sirve una secuencia de respuestas por modelo. El guion se
 * consume en orden: la primera llamada a un modelo recibe su primer paso, y así.
 */
function fetchGuion(
  guion: Record<string, Paso[]>,
  llamadas: Llamada[],
): typeof fetch {
  const indices = new Map<string, number>();
  return ((input: RequestInfo | URL, init?: RequestInit) => {
    const url = String(input);
    const modelo = Object.keys(guion).find((nombre) =>
      url.includes(`models/${nombre}:`)
    ) ?? "desconocido";

    const indice = indices.get(modelo) ?? 0;
    indices.set(modelo, indice + 1);
    const paso = guion[modelo]?.[indice] ?? {
      status: 500,
      cuerpo: { error: { code: 500, status: "INTERNAL" } },
    };

    llamadas.push({
      modelo,
      cuerpo: JSON.parse(String(init?.body ?? "{}")) as Record<string, unknown>,
    });

    return Promise.resolve(
      new Response(JSON.stringify(paso.cuerpo), {
        status: paso.status,
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as unknown as typeof fetch;
}

function configDe(llamada: Llamada): Record<string, unknown> {
  return llamada.cuerpo["generationConfig"] as Record<string, unknown>;
}

Deno.test("redactarConGemini devuelve el texto con una respuesta válida", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 200,
      cuerpo: conTexto("En Mercado llevas $206.000 este mes."),
    }],
  }, llamadas);

  const resultado: ResultadoLLM = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "ok");
  assertEquals(resultado.texto, "En Mercado llevas $206.000 este mes.");
  assertEquals(llamadas.length, 1);
  // Gemini 3.x razona: tope holgado y nivel de razonamiento más bajo.
  assertEquals(configDe(llamadas[0])["maxOutputTokens"], 1024);
  assertEquals(configDe(llamadas[0])["thinkingConfig"], { thinkingLevel: "low" });
});

Deno.test("redactarConGemini usa el respaldo una vez ante un 503", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 503,
      cuerpo: { error: { code: 503, status: "UNAVAILABLE" } },
    }],
    [GEMINI_MODELO_RESPALDO]: [{
      status: 200,
      cuerpo: conTexto("Bájale el ritmo en Mercado y no pases de $206.000."),
    }],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.modelo, GEMINI_MODELO_RESPALDO);
  assertEquals(resultado.motivo, "ok");
  assertEquals(resultado.texto, "Bájale el ritmo en Mercado y no pases de $206.000.");
  assertEquals(llamadas.map((llamada) => llamada.modelo), [
    GEMINI_MODELO,
    GEMINI_MODELO_RESPALDO,
  ]);
});

Deno.test("redactarConGemini usa el respaldo ante un 404 y reporta su fallo", async () => {
  const llamadas: Llamada[] = [];
  const noEncontrado: Paso = {
    status: 404,
    cuerpo: { error: { code: 404, status: "NOT_FOUND" } },
  };
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [noEncontrado],
    [GEMINI_MODELO_RESPALDO]: [noEncontrado],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO_RESPALDO);
  assertEquals(resultado.motivo, "error_http:404:NOT_FOUND");
  assertEquals(llamadas.map((llamada) => llamada.modelo), [
    GEMINI_MODELO,
    GEMINI_MODELO_RESPALDO,
  ]);
});

Deno.test("redactarConGemini NO usa el respaldo ante un 429", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 429,
      cuerpo: { error: { code: 429, status: "RESOURCE_EXHAUSTED" } },
    }],
    [GEMINI_MODELO_RESPALDO]: [{
      status: 200,
      cuerpo: conTexto("En Mercado llevas $206.000 este mes."),
    }],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "error_http:429:RESOURCE_EXHAUSTED");
  assertEquals(llamadas.map((llamada) => llamada.modelo), [GEMINI_MODELO]);
});

Deno.test("redactarConGemini devuelve null y motivo timeout si tarda de más", async () => {
  const llamadas: Llamada[] = [];
  const fetchLento = ((input: RequestInfo | URL, init?: RequestInit) => {
    llamadas.push({ modelo: "lento", cuerpo: {} });
    return new Promise<Response>((_resolver, rechazar) => {
      init?.signal?.addEventListener("abort", () =>
        rechazar(new DOMException("Aborted", "AbortError")));
    });
  }) as unknown as typeof fetch;

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchLento,
    { clave: CLAVE, timeoutMs: 20 },
  );

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "timeout");
  // Sin respaldo: no se alarga la espera.
  assertEquals(llamadas.length, 1);
});

Deno.test("redactarConGemini clasifica como truncado un finishReason MAX_TOKENS", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 200,
      cuerpo: {
        candidates: [{ content: { parts: [] }, finishReason: "MAX_TOKENS" }],
      },
    }],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "validacion:truncado");
});

Deno.test("redactarConGemini clasifica como truncado un texto cortado", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 200,
      // Respuesta cortada a mitad de frase (sin cierre).
      cuerpo: conTexto("En Mercado llevas $206.000 este mes y todavía te queda"),
    }],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "validacion:truncado");
});

Deno.test("redactarConGemini clasifica como vacio una respuesta sin texto", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 200,
      cuerpo: { candidates: [{ content: { parts: [] }, finishReason: "STOP" }] },
    }],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "validacion:vacio");
});

Deno.test("redactarConGemini reintenta sin thinkingConfig si el 400 lo rechaza", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [
      {
        status: 400,
        cuerpo: {
          error: {
            code: 400,
            status: "INVALID_ARGUMENT",
            message: 'Unknown name "thinkingConfig"',
          },
        },
      },
      {
        status: 200,
        cuerpo: conTexto("En Mercado llevas $206.000 este mes."),
      },
    ],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: CLAVE },
  );

  assertEquals(resultado.motivo, "ok");
  assertEquals(resultado.texto, "En Mercado llevas $206.000 este mes.");
  assertEquals(llamadas.length, 2);
  assertEquals(configDe(llamadas[0])["thinkingConfig"], { thinkingLevel: "low" });
  assertEquals(configDe(llamadas[1])["thinkingConfig"], undefined);
});

Deno.test("redactarConGemini no llama a la red si falta la clave", async () => {
  const llamadas: Llamada[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{ status: 200, cuerpo: conTexto("texto") }],
  }, llamadas);

  const resultado = await redactarConGemini(
    HALLAZGO,
    PLANTILLA,
    fetchFalso,
    { clave: null },
  );

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "sin_clave");
  assertEquals(llamadas.length, 0);
});

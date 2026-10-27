// ============================================================================
// Pruebas de gemini.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: la llamada a Gemini se sustituye por un fetch falso y la clave viaja
// por parámetro, así que no hace falta --allow-env ni --allow-net. Se cubre,
// sobre todo, qué pasa ante un 429 (cuota agotada): que caiga al modelo de
// respaldo una sola vez y que el motivo deje rastro.
// ============================================================================

import { assert, assertEquals } from "jsr:@std/assert@1";

import {
  GEMINI_MODELO,
  GEMINI_MODELO_RESPALDO,
  generarConGemini,
  limpiarMarkdownNoPermitido,
  longitudSinSimbolos,
  sinSimbolosMarkdown,
  validarTextoLLM,
} from "./gemini.ts";

const CLAVE = "clave-de-prueba";

const SOLICITUD = {
  instruccion: "instrucción de prueba",
  mensaje: "mensaje de prueba",
};

/** Validador real: texto que cierra la frase y no trae cifras. */
const VALIDADOR = (texto: string) => validarTextoLLM(texto, []);

/** Respuesta de Gemini con un texto candidato. */
function conTexto(texto: string): unknown {
  return { candidates: [{ content: { parts: [{ text: texto }] } }] };
}

interface Paso {
  status: number;
  cuerpo: unknown;
}

/** Un paso 429 como el que devuelve Google al agotar la cuota. */
const PASO_429: Paso = {
  status: 429,
  cuerpo: { error: { code: 429, status: "RESOURCE_EXHAUSTED" } },
};

/**
 * Fetch falso que sirve una secuencia de respuestas por modelo. El guion se
 * consume en orden por modelo y registra el orden de las llamadas.
 */
function fetchGuion(
  guion: Record<string, Paso[]>,
  llamadas: string[],
): typeof fetch {
  const indices = new Map<string, number>();
  return ((input: RequestInfo | URL) => {
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

    llamadas.push(modelo);
    return Promise.resolve(
      new Response(JSON.stringify(paso.cuerpo), {
        status: paso.status,
        headers: { "Content-Type": "application/json" },
      }),
    );
  }) as unknown as typeof fetch;
}

Deno.test("429 en ambos modelos cae a plantilla y lo deja en el motivo", async () => {
  const llamadas: string[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [PASO_429],
    [GEMINI_MODELO_RESPALDO]: [PASO_429],
  }, llamadas);

  const resultado = await generarConGemini(SOLICITUD, VALIDADOR, fetchFalso, {
    clave: CLAVE,
  });

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO_RESPALDO);
  assertEquals(resultado.motivo, "gemini_429_ambos_plantilla");
  // Un intento por modelo: el principal y, tras el 429, el respaldo.
  assertEquals(llamadas, [GEMINI_MODELO, GEMINI_MODELO_RESPALDO]);
});

Deno.test("429 solo en el principal: el respaldo redacta y se usa", async () => {
  const llamadas: string[] = [];
  const texto = "Con tus datos, aparta algo cada mes y cierra el mes tranquila.";
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [PASO_429],
    [GEMINI_MODELO_RESPALDO]: [{ status: 200, cuerpo: conTexto(texto) }],
  }, llamadas);

  const resultado = await generarConGemini(SOLICITUD, VALIDADOR, fetchFalso, {
    clave: CLAVE,
  });

  assertEquals(resultado.texto, texto);
  assertEquals(resultado.modelo, GEMINI_MODELO_RESPALDO);
  assertEquals(resultado.motivo, "gemini_429_principal_respaldo_ok");
  assertEquals(llamadas, [GEMINI_MODELO, GEMINI_MODELO_RESPALDO]);
});

Deno.test("429 en el principal y texto inválido en el respaldo: cae a plantilla", async () => {
  const llamadas: string[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [PASO_429],
    // Texto cortado a mitad de frase: no pasa el validador.
    [GEMINI_MODELO_RESPALDO]: [{
      status: 200,
      cuerpo: conTexto("Esto quedó a medias y no cierra"),
    }],
  }, llamadas);

  const resultado = await generarConGemini(SOLICITUD, VALIDADOR, fetchFalso, {
    clave: CLAVE,
  });

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO_RESPALDO);
  assertEquals(resultado.motivo, "gemini_429_ambos_plantilla");
  assertEquals(llamadas, [GEMINI_MODELO, GEMINI_MODELO_RESPALDO]);
});

Deno.test("el motivo del 429 se distingue de sin_clave", async () => {
  const llamadas: string[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [PASO_429],
    [GEMINI_MODELO_RESPALDO]: [PASO_429],
  }, llamadas);

  const sinClave = await generarConGemini(SOLICITUD, VALIDADOR, fetchFalso, {
    clave: null,
  });
  assertEquals(sinClave.texto, null);
  assertEquals(sinClave.motivo, "sin_clave");
  // Sin clave ni siquiera se llama a Gemini.
  assertEquals(llamadas, []);

  const con429 = await generarConGemini(SOLICITUD, VALIDADOR, fetchFalso, {
    clave: CLAVE,
  });
  assertEquals(con429.motivo, "gemini_429_ambos_plantilla");
});

Deno.test("500 en el principal NO usa el respaldo (sin cambios)", async () => {
  const llamadas: string[] = [];
  const fetchFalso = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 500,
      cuerpo: { error: { code: 500, status: "INTERNAL" } },
    }],
    [GEMINI_MODELO_RESPALDO]: [{ status: 200, cuerpo: conTexto("No se usa.") }],
  }, llamadas);

  const resultado = await generarConGemini(SOLICITUD, VALIDADOR, fetchFalso, {
    clave: CLAVE,
  });

  assertEquals(resultado.texto, null);
  assertEquals(resultado.modelo, GEMINI_MODELO);
  assertEquals(resultado.motivo, "error_http:500:INTERNAL");
  assertEquals(llamadas, [GEMINI_MODELO]);
});

Deno.test("404 y 503 siguen cayendo al respaldo como antes", async () => {
  const llamadas504: string[] = [];
  const fetch404 = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 404,
      cuerpo: { error: { code: 404, status: "NOT_FOUND" } },
    }],
    [GEMINI_MODELO_RESPALDO]: [{
      status: 404,
      cuerpo: { error: { code: 404, status: "NOT_FOUND" } },
    }],
  }, llamadas504);
  const por404 = await generarConGemini(SOLICITUD, VALIDADOR, fetch404, {
    clave: CLAVE,
  });
  assertEquals(por404.motivo, "error_http:404:NOT_FOUND");
  assertEquals(por404.modelo, GEMINI_MODELO_RESPALDO);
  assertEquals(llamadas504, [GEMINI_MODELO, GEMINI_MODELO_RESPALDO]);

  const llamadas503: string[] = [];
  const fetch503 = fetchGuion({
    [GEMINI_MODELO]: [{
      status: 503,
      cuerpo: { error: { code: 503, status: "UNAVAILABLE" } },
    }],
    [GEMINI_MODELO_RESPALDO]: [{
      status: 200,
      cuerpo: conTexto("El respaldo responde bien."),
    }],
  }, llamadas503);
  const por503 = await generarConGemini(SOLICITUD, VALIDADOR, fetch503, {
    clave: CLAVE,
  });
  assertEquals(por503.motivo, "ok");
  assertEquals(por503.modelo, GEMINI_MODELO_RESPALDO);
  assertEquals(llamadas503, [GEMINI_MODELO, GEMINI_MODELO_RESPALDO]);
});

// --- Formato en bloques, limpieza y medición sin símbolos ---------------------

Deno.test("limpiarMarkdownNoPermitido deja solo negrita, viñetas y saltos", () => {
  const sucio = [
    "# Título que sobra",
    "",
    "Mira esto: ![grafico](https://x.com/i.png) y este [enlace](https://x.com).",
    "",
    "| Concepto | Valor |",
    "| --- | --- |",
    "| Deuda | $500.000 |",
    "",
    "<div>algo de HTML</div><!-- comentario -->",
    "",
    "`codigo` y ```bloque```",
    "",
    "- dato **importante**",
    "***mucho***",
  ].join("\n");

  const limpio = limpiarMarkdownNoPermitido(sucio);

  // Títulos, HTML, comentarios, imágenes, tablas y código: fuera.
  assertEquals(limpio.includes("#"), false);
  assertEquals(limpio.includes("<div>"), false);
  assertEquals(limpio.includes("comentario"), false);
  assertEquals(limpio.includes("![grafico]"), false);
  assertEquals(limpio.includes("|"), false);
  assertEquals(limpio.includes("`"), false);
  // El enlace conserva su texto, la tabla su dato y la negrita se mantiene.
  assertEquals(limpio.includes("enlace"), true);
  assertEquals(limpio.includes("$500.000"), true);
  assertEquals(limpio.includes("**importante**"), true);
  assertEquals(limpio.includes("***mucho***"), false);
});

Deno.test("validarTextoLLM acepta cifras en negrita dentro de viñetas", () => {
  const texto = "Con tu excedente te cabría una cuota.\n\n" +
    "- cuota de **$500.000** al mes\n" +
    "- te quedarían **$500.000** libres\n\n" +
    "Empieza por ahí.";
  assertEquals(validarTextoLLM(texto, ["$500.000"]), {
    valido: true,
    motivo: "ok",
  });
});

Deno.test("validarTextoLLM mide el largo sin los símbolos de Markdown", () => {
  // Viñetas con negrita: el texto con símbolos es más largo que el que ve la
  // persona, así que el tope se aplica sobre el texto plano.
  const texto = "Cierre.\n\n" +
    ["uno", "dos", "tres", "cuatro", "cinco"]
      .map(() => "- **$100.000** de gasto fijo.")
      .join("\n");

  assert(longitudSinSimbolos(texto) < texto.length);
  // Con el tope exacto del texto plano, cabe.
  assertEquals(
    validarTextoLLM(texto, ["$100.000"], longitudSinSimbolos(texto)),
    { valido: true, motivo: "ok" },
  );
  // Una letra menos en el tope ya lo rechaza.
  assertEquals(
    validarTextoLLM(texto, ["$100.000"], longitudSinSimbolos(texto) - 1),
    { valido: false, motivo: "largo" },
  );
});

Deno.test("validarTextoLLM acepta que el último bloque sea una viñeta", () => {
  const texto = "Estos son los pasos:\n\n" +
    "- registra tus gastos.\n" +
    "- aparta algo cada mes.";
  assertEquals(validarTextoLLM(texto, []), { valido: true, motivo: "ok" });
});

Deno.test("sinSimbolosMarkdown quita la negrita y la viñeta, no el texto", () => {
  assertEquals(sinSimbolosMarkdown("- **$500.000** al mes"), "$500.000 al mes");
});

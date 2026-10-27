// ============================================================================
// Pruebas de manejador.ts  (deno test)
// ----------------------------------------------------------------------------
// Solo se prueban los rechazos previos a cualquier acceso a datos: no hacen
// falta credenciales ni tocar Supabase.
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import { manejarPeticion } from "./manejador.ts";

const URL_FUNCION = "http://localhost/functions/v1/eliminar-cuenta";

Deno.test("sin Authorization responde 401", async () => {
  const respuesta = await manejarPeticion(
    new Request(URL_FUNCION, { method: "POST" }),
  );

  assertEquals(respuesta.status, 401);
  const cuerpo = await respuesta.json();
  assertEquals(typeof cuerpo.error, "string");
});

Deno.test("un Authorization que no es Bearer responde 401", async () => {
  const respuesta = await manejarPeticion(
    new Request(URL_FUNCION, {
      method: "POST",
      headers: { Authorization: "Basic abc123" },
    }),
  );

  assertEquals(respuesta.status, 401);
});

Deno.test("un método distinto de POST responde 405", async () => {
  const respuesta = await manejarPeticion(
    new Request(URL_FUNCION, {
      method: "GET",
      headers: { Authorization: "Bearer token" },
    }),
  );

  assertEquals(respuesta.status, 405);
});

Deno.test("OPTIONS responde con las cabeceras CORS", async () => {
  const respuesta = await manejarPeticion(
    new Request(URL_FUNCION, { method: "OPTIONS" }),
  );

  assertEquals(respuesta.headers.get("Access-Control-Allow-Origin"), "*");
  assertEquals(
    respuesta.headers.get("Access-Control-Allow-Methods"),
    "POST, OPTIONS",
  );
});

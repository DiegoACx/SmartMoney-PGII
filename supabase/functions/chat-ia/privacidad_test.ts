// ============================================================================
// Pruebas de privacidad.ts  (deno test)
// ----------------------------------------------------------------------------
// Sin red: solo funciones puras sobre el texto del mensaje.
// ============================================================================

import { assertEquals } from "jsr:@std/assert@1";

import { MARCADOR_DATO_OCULTO, ocultarDatosPersonales } from "./privacidad.ts";

Deno.test("oculta una cédula de 8 o más dígitos", () => {
  assertEquals(
    ocultarDatosPersonales("mi cedula es 1020456789"),
    `mi cedula es ${MARCADOR_DATO_OCULTO}`,
  );
});

Deno.test("oculta un número de tarjeta escrito con espacios", () => {
  assertEquals(
    ocultarDatosPersonales("mi tarjeta es 4111 1111 1111 1111"),
    `mi tarjeta es ${MARCADOR_DATO_OCULTO}`,
  );
});

Deno.test("oculta un número de cuenta escrito con guiones", () => {
  assertEquals(
    ocultarDatosPersonales("cuenta 1234-5678-9012"),
    `cuenta ${MARCADOR_DATO_OCULTO}`,
  );
});

Deno.test("oculta un correo electrónico", () => {
  assertEquals(
    ocultarDatosPersonales("escribeme a juan.perez@correo.com por favor"),
    `escribeme a ${MARCADOR_DATO_OCULTO} por favor`,
  );
});

Deno.test("oculta cédula y correo en el mismo mensaje", () => {
  assertEquals(
    ocultarDatosPersonales("soy 1020456789 y mi correo es ana@mail.co"),
    `soy ${MARCADOR_DATO_OCULTO} y mi correo es ${MARCADOR_DATO_OCULTO}`,
  );
});

Deno.test("NO oculta montos en palabras ni con puntos de miles", () => {
  assertEquals(ocultarDatosPersonales("gaste 300 mil"), "gaste 300 mil");
  assertEquals(
    ocultarDatosPersonales("recibi $1.200.000"),
    "recibi $1.200.000",
  );
  assertEquals(
    ocultarDatosPersonales("debo 250.000 pesos"),
    "debo 250.000 pesos",
  );
});

Deno.test("no deja rastro de los dígitos ocultos", () => {
  const texto = ocultarDatosPersonales("cuenta 1234567890");
  assertEquals(texto.includes("1234"), false);
});

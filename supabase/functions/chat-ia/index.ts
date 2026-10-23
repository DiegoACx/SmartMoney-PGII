// ============================================================================
// SmartMoney · Chat IA (Edge Function)
// ----------------------------------------------------------------------------
// POST /functions/v1/chat-ia  (verify_jwt activado, valor por defecto)
//   Cabecera: Authorization: Bearer <JWT del usuario>
//   Body: { "mensaje": string }
//
// La lógica vive en manejador.ts para poder probarla sin levantar el servidor.
// ============================================================================

import { manejarPeticion } from "./manejador.ts";

Deno.serve(manejarPeticion);

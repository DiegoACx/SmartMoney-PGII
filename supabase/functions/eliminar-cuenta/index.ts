// ============================================================================
// SmartMoney · Eliminar cuenta (Edge Function)
// ----------------------------------------------------------------------------
// POST /functions/v1/eliminar-cuenta  (verify_jwt activado, valor por defecto)
//
// La lógica vive en manejador.ts para poder probarla sin levantar el servidor.
// ============================================================================

import { manejarPeticion } from "./manejador.ts";

Deno.serve(manejarPeticion);

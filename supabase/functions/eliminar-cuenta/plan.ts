// ============================================================================
// SmartMoney · Eliminar cuenta · Plan de borrado (puro, sin E/S)
// ----------------------------------------------------------------------------
// El orden es obligatorio y no se puede reordenar:
//   · educacion_progreso no tiene llave foránea hacia el usuario, así que su
//     borrado explícito es obligatorio.
//   · transacciones va ANTES que categorias por el RESTRICT de
//     fk_transactions_categoria.
//   · aportes_meta va antes que metas_ahorro: se borra explícitamente para no
//     depender de que la cascada de la llave foránea esté configurada.
//   · categorias solo borra las filas propias: las predeterminadas tienen
//     usuario_id NULL y son de todos los usuarios.
//   · usuarios va antes del borrado en Supabase Auth.
// ============================================================================

/** Paso de borrado: tabla, columna de filtro y si solo afecta filas propias. */
export interface PasoBorrado {
  tabla: string;
  columna: string;
  /** true → nunca tocar filas ajenas (por ejemplo, categorías por defecto). */
  soloPropias?: boolean;
}

/** Último paso del proceso: borrado del usuario en Supabase Auth. */
export const PASO_AUTH = "auth.users";

/** Plan de borrado en el orden exacto en que debe ejecutarse. */
export const PLAN_BORRADO: readonly PasoBorrado[] = [
  { tabla: "educacion_progreso", columna: "usuario_id" },
  { tabla: "transacciones", columna: "usuario_id" },
  { tabla: "aportes_meta", columna: "usuario_id" },
  { tabla: "metas_ahorro", columna: "usuario_id" },
  { tabla: "mensajes_ia", columna: "usuario_id" },
  { tabla: "recomendaciones", columna: "usuario_id" },
  { tabla: "hallazgos", columna: "usuario_id" },
  { tabla: "preferencias_recomendacion", columna: "usuario_id" },
  { tabla: "linea_base_usuario", columna: "usuario_id" },
  { tabla: "categorias", columna: "usuario_id", soloPropias: true },
  { tabla: "usuarios", columna: "id" },
];

/** Orden completo de borrado, incluido el paso final en Auth. */
export function ordenDeBorrado(): string[] {
  return [...PLAN_BORRADO.map((paso) => paso.tabla), PASO_AUTH];
}

/** Posición de una tabla en el orden de borrado (-1 si no está en el plan). */
export function posicionDe(tabla: string): number {
  return ordenDeBorrado().indexOf(tabla);
}

/** true si `antes` se borra estrictamente antes que `despues`. */
export function precedeA(antes: string, despues: string): boolean {
  const i = posicionDe(antes);
  const j = posicionDe(despues);
  if (i < 0 || j < 0) return false;
  return i < j;
}

/** true si el borrado en Auth es el último paso del proceso. */
export function authEsUltimoPaso(): boolean {
  const orden = ordenDeBorrado();
  return orden.length > 0 && orden[orden.length - 1] === PASO_AUTH;
}

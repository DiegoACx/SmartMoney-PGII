// ============================================================================
// SmartMoney · Chat IA · Acceso a datos
// ----------------------------------------------------------------------------
// Interfaz mínima que necesita el chat y su implementación con el cliente
// service_role. SIEMPRE se filtra por el usuario_id que salió del JWT.
//
// La interfaz permite inyectar un doble en las pruebas (sin Supabase ni red).
// ============================================================================

import type { SupabaseClient } from "jsr:@supabase/supabase-js@2";

import { sumarDias } from "./fechas.ts";

export interface FilaTransaccion {
  categoria_id: string | null;
  tipo: string;
  monto: number;
  fecha: string;
}

export interface FilaCategoria {
  id: string;
  nombre: string;
  grupo_id: number | null;
}

export interface FilaMeta {
  id: string;
  nombre: string;
  monto_objetivo: number;
  monto_actual: number;
  fecha_limite: string | null;
  cumplida: boolean | null;
}

export interface MensajeNuevo {
  usuario_id: string;
  rol: "usuario" | "asistente";
  contenido: string;
  intencion: string | null;
  confianza: number | null;
  origen: string | null;
  accion: unknown | null;
}

export interface RepositorioChat {
  /** Nº de mensajes del usuario creados entre las dos marcas ISO (desde incl., hasta excl.). */
  contarMensajesUsuario(
    usuarioId: string,
    desdeIso: string,
    hastaIso: string,
  ): Promise<number>;
  /** Contenido del último mensaje del asistente, o null si no hay ninguno. */
  ultimoMensajeAsistente(usuarioId: string): Promise<string | null>;
  /** Inserta un mensaje en mensajes_ia. */
  insertarMensaje(mensaje: MensajeNuevo): Promise<void>;
  /** Movimientos del usuario entre dos fechas 'YYYY-MM-DD' (ambas inclusive). */
  leerTransacciones(
    usuarioId: string,
    desde: string,
    hasta: string,
    tipo: "ingreso" | "egreso",
  ): Promise<FilaTransaccion[]>;
  /** Categorías visibles para el usuario (propias y por defecto). */
  leerCategorias(usuarioId: string): Promise<FilaCategoria[]>;
  /** Metas de ahorro no cumplidas del usuario. */
  leerMetasActivas(usuarioId: string): Promise<FilaMeta[]>;
}

function texto(valor: unknown): string {
  return typeof valor === "string" ? valor : String(valor ?? "");
}

/** Implementación con el cliente service_role (ya autenticado como servidor). */
export function crearRepositorioSupabase(
  admin: SupabaseClient,
): RepositorioChat {
  return {
    async contarMensajesUsuario(usuarioId, desdeIso, hastaIso) {
      const { count, error } = await admin
        .from("mensajes_ia")
        .select("id", { count: "exact", head: true })
        .eq("usuario_id", usuarioId)
        .eq("rol", "usuario")
        .gte("creado_en", desdeIso)
        .lt("creado_en", hastaIso);
      if (error) {
        throw new Error(`No se pudieron contar los mensajes: ${error.message}`);
      }
      return count ?? 0;
    },

    async ultimoMensajeAsistente(usuarioId) {
      const { data, error } = await admin
        .from("mensajes_ia")
        .select("contenido")
        .eq("usuario_id", usuarioId)
        .eq("rol", "asistente")
        .order("creado_en", { ascending: false })
        .limit(1);
      if (error) {
        throw new Error(`No se pudo leer el último mensaje: ${error.message}`);
      }
      const fila = (data ?? [])[0] as Record<string, unknown> | undefined;
      if (fila === undefined) return null;
      const contenido = texto(fila["contenido"]);
      return contenido.length > 0 ? contenido : null;
    },

    async insertarMensaje(mensaje) {
      const { error } = await admin.from("mensajes_ia").insert(mensaje);
      if (error) {
        throw new Error(`No se pudo guardar el mensaje: ${error.message}`);
      }
    },

    async leerTransacciones(usuarioId, desde, hasta, tipo) {
      const { data, error } = await admin
        .from("transacciones")
        .select("categoria_id, tipo, monto, fecha")
        .eq("usuario_id", usuarioId)
        .eq("tipo", tipo)
        .gte("fecha", desde)
        .lt("fecha", sumarDias(hasta, 1));
      if (error) {
        throw new Error(`No se pudieron leer los movimientos: ${error.message}`);
      }
      return ((data ?? []) as Record<string, unknown>[]).map((fila) => ({
        categoria_id: fila["categoria_id"] === null
          ? null
          : String(fila["categoria_id"]),
        tipo: texto(fila["tipo"]),
        monto: Number(fila["monto"] ?? 0),
        fecha: texto(fila["fecha"]).slice(0, 10),
      }));
    },

    async leerCategorias(usuarioId) {
      const { data, error } = await admin
        .from("categorias")
        .select("id, nombre, grupo_id")
        .or(`usuario_id.is.null,usuario_id.eq.${usuarioId}`);
      if (error) {
        throw new Error(`No se pudieron leer las categorías: ${error.message}`);
      }
      return ((data ?? []) as Record<string, unknown>[]).map((fila) => ({
        id: texto(fila["id"]),
        nombre: texto(fila["nombre"]),
        grupo_id: fila["grupo_id"] === null || fila["grupo_id"] === undefined
          ? null
          : Number(fila["grupo_id"]),
      }));
    },

    async leerMetasActivas(usuarioId) {
      const { data, error } = await admin
        .from("metas_ahorro")
        .select("id, nombre, monto_objetivo, monto_actual, fecha_limite, cumplida")
        .eq("usuario_id", usuarioId);
      if (error) {
        throw new Error(`No se pudieron leer las metas: ${error.message}`);
      }
      const metas: FilaMeta[] = [];
      for (const fila of (data ?? []) as Record<string, unknown>[]) {
        if (fila["cumplida"] === true) continue;
        const fechaLimite = fila["fecha_limite"];
        metas.push({
          id: texto(fila["id"]),
          nombre: texto(fila["nombre"]) || "tu meta",
          monto_objetivo: Number(fila["monto_objetivo"] ?? 0),
          monto_actual: Number(fila["monto_actual"] ?? 0),
          fecha_limite: typeof fechaLimite === "string" && fechaLimite.length > 0
            ? fechaLimite.slice(0, 10)
            : null,
          cumplida: fila["cumplida"] === true,
        });
      }
      return metas;
    },
  };
}

/** Formatea una fecha 'YYYY-MM-DD' como 'DD/MM/YYYY' (para las plantillas). */
export function fechaCorta(fecha: string): string {
  if (!/^\d{4}-\d{2}-\d{2}/.test(fecha)) return fecha;
  return `${fecha.slice(8, 10)}/${fecha.slice(5, 7)}/${fecha.slice(0, 4)}`;
}

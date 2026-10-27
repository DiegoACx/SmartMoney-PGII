import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Error de negocio del chat con un mensaje ya listo para mostrar al usuario.
///
/// La capa `logic` lo captura y lo convierte en un resultado con error; nunca
/// llega a la interfaz como excepción.
class ErrorChat implements Exception {
  final String mensaje;
  final int? estado;

  const ErrorChat(this.mensaje, {this.estado});

  @override
  String toString() => 'ErrorChat(estado: $estado, mensaje: $mensaje)';
}

/// Traduce el error que devuelve la Edge Function `chat-ia` a un mensaje
/// legible. La función responde `{ "error": "..." }` en los 400 (mensaje vacío
/// o de más de 500 caracteres) y 429 (límite diario), y ese texto se muestra
/// tal cual.
String mensajeDeErrorChat(FunctionException excepcion) {
  final detalles = excepcion.details;

  String? mensaje;
  if (detalles is Map) {
    mensaje = detalles['error']?.toString();
  } else if (detalles is String && detalles.isNotEmpty) {
    try {
      final decodificado = jsonDecode(detalles);
      if (decodificado is Map) mensaje = decodificado['error']?.toString();
    } catch (_) {
      mensaje = null;
    }
  }
  if (mensaje != null && mensaje.trim().isNotEmpty) return mensaje.trim();

  // Sin cuerpo útil: mensajes genéricos por tipo de fallo.
  if (excepcion.status == 0) {
    return 'No pudimos contactar al asistente. Revisa tu conexión a internet.';
  }
  return 'El asistente no está disponible en este momento (error ${excepcion.status}).';
}

/// Acceso a la Edge Function `chat-ia` y a la tabla `mensajes_ia`.
///
/// `functions.invoke` envía el JWT del usuario automáticamente, así que la
/// función resuelve el usuario a partir del token. Las lecturas y escrituras
/// del historial están protegidas por RLS (el usuario solo ve sus filas).
class ChatRepository {
  // Getter (y no campo) para poder sustituir el repositorio en las pruebas
  // sin inicializar Supabase.
  SupabaseClient get _client => Supabase.instance.client;

  /// Envía un mensaje al asistente. Devuelve
  /// `{ respuesta, intencion, confianza, origen, accion? }`.
  ///
  /// Lanza [ErrorChat] con un mensaje legible si la función responde con error.
  Future<Map<String, dynamic>> enviarMensaje(String texto) async {
    try {
      final respuesta = await _client.functions.invoke(
        'chat-ia',
        body: {'mensaje': texto},
      );
      return _comoMapa(respuesta.data);
    } on FunctionException catch (e) {
      throw ErrorChat(mensajeDeErrorChat(e), estado: e.status);
    }
  }

  /// Devuelve los últimos [limite] mensajes del usuario en orden cronológico
  /// (del más antiguo al más reciente), listos para pintar el chat.
  Future<List<Map<String, dynamic>>> cargarHistorial({int limite = 50}) async {
    final usuarioId = _client.auth.currentUser?.id;
    if (usuarioId == null) return [];

    final filas = await _client
        .from('mensajes_ia')
        .select()
        .eq('usuario_id', usuarioId)
        .order('creado_en', ascending: false)
        .limit(limite);

    final lista = List<Map<String, dynamic>>.from(filas);
    return lista.reversed.toList();
  }

  /// Registra el 👍/👎 del usuario sobre una respuesta del asistente.
  Future<void> calificar(String id, bool util) async {
    await _client.from('mensajes_ia').update({
      'util': util,
      'respondido_en': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
  }

  /// Borra toda la conversación del usuario.
  Future<void> borrarHistorial() async {
    final usuarioId = _client.auth.currentUser?.id;
    if (usuarioId == null) return;
    await _client.from('mensajes_ia').delete().eq('usuario_id', usuarioId);
  }

  Map<String, dynamic> _comoMapa(dynamic dato) {
    if (dato is Map) return Map<String, dynamic>.from(dato);
    if (dato is String && dato.isNotEmpty) {
      try {
        final decodificado = jsonDecode(dato);
        if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }
}

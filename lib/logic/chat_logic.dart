import 'package:flutter/foundation.dart';

import '../data/chat_repository.dart';

/// Resultado de enviar un mensaje al asistente: los datos de la respuesta o un
/// error ya legible para mostrar en pantalla.
class ResultadoChat {
  final Map<String, dynamic>? datos;
  final String? error;

  const ResultadoChat.exito(this.datos) : error = null;
  const ResultadoChat.error(this.error) : datos = null;

  bool get exito => error == null;

  String get respuesta => (datos?['respuesta'] as String?) ?? '';
  String? get intencion => datos?['intencion'] as String?;
  String? get origen => datos?['origen'] as String?;
  double get confianza => (datos?['confianza'] as num?)?.toDouble() ?? 0;

  /// Acción sugerida por la Edge Function, o null si no hay.
  /// Ejemplos: `{ tipo: 'abrir_leccion', escalon_id: '...' }` o
  /// `{ tipo: 'ir_a', destino: 'metas' }`.
  Map<String, dynamic>? get accion {
    final valor = datos?['accion'];
    if (valor is Map) return Map<String, dynamic>.from(valor);
    return null;
  }
}

/// Lógica del chat del asistente.
///
/// Valida el texto antes de llamar a la red y **nunca lanza** hacia la
/// interfaz: todo error se devuelve como [ResultadoChat] con mensaje legible.
class ChatLogic {
  ChatLogic({ChatRepository? repositorio})
      : _repositorio = repositorio ?? ChatRepository();

  final ChatRepository _repositorio;

  /// Longitud máxima del mensaje, igual que la valida la Edge Function.
  static const int largoMaximo = 500;

  /// Devuelve el error de validación del texto, o null si es válido.
  String? validarTexto(String texto) {
    final limpio = texto.trim();
    if (limpio.isEmpty) return 'Escríbeme algo y con gusto te ayudo.';
    if (limpio.length > largoMaximo) {
      return 'Tu mensaje es muy largo. Resúmelo en $largoMaximo caracteres o menos.';
    }
    return null;
  }

  Future<ResultadoChat> enviarMensaje(String texto) async {
    final errorValidacion = validarTexto(texto);
    if (errorValidacion != null) return ResultadoChat.error(errorValidacion);

    try {
      final datos = await _repositorio.enviarMensaje(texto.trim());
      return ResultadoChat.exito(datos);
    } on ErrorChat catch (e) {
      // 400 / 429 / red: el mensaje del servidor se muestra tal cual.
      return ResultadoChat.error(e.mensaje);
    } catch (e) {
      debugPrint('ERROR AL ENVIAR MENSAJE AL ASISTENTE: $e');
      return const ResultadoChat.error(
        'No pudimos contactar al asistente. Intenta de nuevo.',
      );
    }
  }

  /// Historial del usuario (vacío si algo falla), en orden cronológico.
  Future<List<Map<String, dynamic>>> cargarHistorial({int limite = 50}) async {
    try {
      return await _repositorio.cargarHistorial(limite: limite);
    } catch (e) {
      debugPrint('ERROR AL CARGAR HISTORIAL DEL CHAT: $e');
      return [];
    }
  }

  /// Califica una respuesta. Devuelve false si no se pudo guardar.
  Future<bool> calificar(String id, bool util) async {
    try {
      await _repositorio.calificar(id, util);
      return true;
    } catch (e) {
      debugPrint('ERROR AL CALIFICAR MENSAJE IA: $e');
      return false;
    }
  }

  /// Borra la conversación. Devuelve false si no se pudo.
  Future<bool> borrarHistorial() async {
    try {
      await _repositorio.borrarHistorial();
      return true;
    } catch (e) {
      debugPrint('ERROR AL BORRAR HISTORIAL DEL CHAT: $e');
      return false;
    }
  }
}

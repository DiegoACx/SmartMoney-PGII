import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso a las recomendaciones del motor de IA.
///
/// La Edge Function `motor-recomendaciones` recibe el JWT del usuario
/// automáticamente mediante `functions.invoke` y devuelve:
///
/// {
///   "recalculado": bool,
///   "recomendaciones": [
///     {
///       "id": String,
///       "tipo": String,
///       "texto": String,
///       "prioridad": num,
///       "creado_en": String,
///       "datos": { ...jsonb del hallazgo... }
///     }
///   ]
/// }
///
/// `datos` ya viene embebido desde la tabla `hallazgos`, por lo que no hace
/// falta consultarla por separado.
class RecomendacionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> obtenerRecomendaciones({
    bool forzar = false,
  }) async {
    final respuesta = await _client.functions.invoke(
      'motor-recomendaciones',
      body: {'forzar': forzar},
    );

    final cuerpo = _comoMapa(respuesta.data);
    final lista = cuerpo['recomendaciones'];
    if (lista is! List) return [];

    return lista
        .whereType<Map>()
        .map((fila) => Map<String, dynamic>.from(fila))
        .toList();
  }

  /// Marca `mostrada_en` solo si aún no estaba marcada.
  Future<void> marcarMostrada(String id) async {
    await _client
        .from('recomendaciones')
        .update({'mostrada_en': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .isFilter('mostrada_en', null);
  }

  /// Registra la respuesta del usuario: `util` y `respondido_en`.
  Future<void> responder(String id, bool util) async {
    await _client.from('recomendaciones').update({
      'util': util,
      'respondido_en': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', id);
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

import 'package:flutter/foundation.dart';

import '../data/recomendaciones_repository.dart';

/// Lógica de las recomendaciones del motor de IA.
///
/// Delega en el repositorio y absorbe los errores: nunca lanza hacia la UI.
class RecomendacionesLogic {
  final RecomendacionesRepository _repository = RecomendacionesRepository();

  /// Recomendaciones vigentes del usuario. Ante cualquier error devuelve [].
  Future<List<Map<String, dynamic>>> obtenerRecomendaciones({
    bool forzar = false,
  }) async {
    try {
      return await _repository.obtenerRecomendaciones(forzar: forzar);
    } catch (e) {
      debugPrint('ERROR AL OBTENER RECOMENDACIONES: $e');
      return [];
    }
  }

  Future<void> marcarMostrada(String id) async {
    try {
      await _repository.marcarMostrada(id);
    } catch (e) {
      debugPrint('ERROR AL MARCAR RECOMENDACION COMO MOSTRADA: $e');
    }
  }

  Future<void> responder(String id, bool util) async {
    try {
      await _repository.responder(id, util);
    } catch (e) {
      debugPrint('ERROR AL RESPONDER RECOMENDACION: $e');
    }
  }
}

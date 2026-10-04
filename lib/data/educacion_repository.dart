import 'package:supabase_flutter/supabase_flutter.dart';

class EducacionRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> obtenerNiveles() async {
    final data = await _client
        .from('educacion_niveles')
        .select()
        .order('orden', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> obtenerEscalonesPorNivel(String nivelId) async {
    final data = await _client
        .from('educacion_escalones')
        .select()
        .eq('nivel_id', nivelId)
        .order('orden', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> obtenerPreguntas(String escalonId) async {
    final data = await _client
        .from('educacion_preguntas')
        .select()
        .eq('escalon_id', escalonId)
        .order('orden', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> obtenerProgreso(String usuarioId) async {
    final data = await _client
        .from('educacion_progreso')
        .select()
        .eq('usuario_id', usuarioId);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>?> obtenerProgresoEscalon({
    required String usuarioId,
    required String escalonId,
  }) async {
    final data = await _client
        .from('educacion_progreso')
        .select()
        .eq('usuario_id', usuarioId)
        .eq('escalon_id', escalonId)
        .maybeSingle();

    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  Future<void> guardarProgreso({
    required String usuarioId,
    required String escalonId,
    required bool completado,
    double? puntaje,
  }) async {
    final payload = <String, dynamic>{
      'usuario_id': usuarioId,
      'escalon_id': escalonId,
      'completado': completado,
      'puntaje': puntaje,
    };

    if (completado) {
      payload['fecha_completado'] = DateTime.now().toIso8601String();
    }

    await _client.from('educacion_progreso').upsert(
          payload,
          onConflict: 'usuario_id,escalon_id',
        );
  }
}

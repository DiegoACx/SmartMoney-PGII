import 'package:supabase_flutter/supabase_flutter.dart';

class MetasRepository {
  final SupabaseClient _client = Supabase.instance.client;

  Future<Map<String, dynamic>> crearMeta({
    required String nombre,
    required double montoObjetivo,
    DateTime? fechaLimite,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay usuario autenticado');
    }

    final data = await _client
        .from('metas_ahorro')
        .insert({
          'usuario_id': userId,
          'nombre': nombre,
          'monto_objetivo': montoObjetivo,
          'monto_actual': 0,
          'fecha_limite': fechaLimite != null
              ? fechaLimite.toIso8601String().split('T')[0]
              : null,
          'cumplida': false,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(data as Map);
  }

  Future<List<Map<String, dynamic>>> obtenerMetas(String usuarioId) async {
    final data = await _client
        .from('metas_ahorro')
        .select()
        .eq('usuario_id', usuarioId)
        .order('cumplida', ascending: true)
        .order('fecha_creacion', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> obtenerMetaPorId(String metaId) async {
    final data = await _client
        .from('metas_ahorro')
        .select()
        .eq('id', metaId)
        .single();

    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> editarMeta({
    required String metaId,
    String? nombre,
    double? montoObjetivo,
    DateTime? fechaLimite,
  }) async {
    final updates = <String, dynamic>{};
    if (nombre != null) updates['nombre'] = nombre;
    if (montoObjetivo != null) updates['monto_objetivo'] = montoObjetivo;
    if (fechaLimite != null) {
      updates['fecha_limite'] = fechaLimite.toIso8601String().split('T')[0];
    }

    if (updates.isEmpty) return;

    await _client.from('metas_ahorro').update(updates).eq('id', metaId);
  }

  Future<Map<String, dynamic>> actualizarProgreso({
    required String metaId,
    required double nuevoMontoActual,
    required bool cumplida,
  }) async {
    final data = await _client
        .from('metas_ahorro')
        .update({
          'monto_actual': nuevoMontoActual,
          'cumplida': cumplida,
        })
        .eq('id', metaId)
        .select()
        .single();

    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> eliminarMeta(String metaId) async {
    await _client.from('metas_ahorro').delete().eq('id', metaId);
  }

  Future<void> crearAporte({
    required String metaId,
    required double monto,
    required DateTime fecha,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay usuario autenticado');
    }

    await _client.from('aportes_meta').insert({
      'meta_id': metaId,
      'usuario_id': userId,
      'monto': monto,
      'fecha': fecha.toIso8601String().split('T')[0],
    });
  }

  Future<List<Map<String, dynamic>>> obtenerAportesDeMeta(String metaId) async {
    final data = await _client
        .from('aportes_meta')
        .select()
        .eq('meta_id', metaId)
        .order('fecha', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }
}

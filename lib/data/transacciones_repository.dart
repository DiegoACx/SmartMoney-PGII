import 'package:supabase_flutter/supabase_flutter.dart';

class TransaccionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Crea una nueva transacción para el usuario autenticado.
  /// [grupoSugeridoId], [confianzaSugerencia], [categoriaCorregida] y
  /// [versionModelo] son los metadatos de la sugerencia del clasificador;
  /// van en null cuando no hubo sugerencia.
  Future<void> crearTransaccion({
    required String tipo,
    required double monto,
    required String categoriaId,
    String? descripcion,
    required DateTime fecha,
    required String metodoPago,
    required bool esGastoTrabajo,
    int? grupoSugeridoId,
    double? confianzaSugerencia,
    bool? categoriaCorregida,
    String? versionModelo,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay usuario autenticado');
    }

    await _client.from('transacciones').insert({
      'usuario_id': userId,
      'categoria_id': categoriaId,
      'tipo': tipo,
      'monto': monto,
      'descripcion': descripcion,
      'fecha': fecha.toIso8601String().split('T')[0],
      'metodo_pago': metodoPago,
      'es_gasto_trabajo': esGastoTrabajo,
      'grupo_sugerido_id': grupoSugeridoId,
      'confianza_sugerencia': confianzaSugerencia,
      'categoria_corregida': categoriaCorregida,
      'version_modelo': versionModelo,
    });
  }

  /// Trae todas las transacciones de un usuario específico.
  Future<List<Map<String, dynamic>>> obtenerTransacciones(String usuarioId) async {
    final data = await _client
        .from('transacciones')
        .select('*, categorias(nombre)')
        .eq('usuario_id', usuarioId)
        .order('fecha', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  /// Trae TODAS las transacciones de un usuario (join con categorías).
  /// Ordena primero por fecha (desc) y, para desempatar, por fecha_creacion
  /// (desc) — la misma fecha de la transacción, la más recientemente creada
  /// aparece primero.
  Future<List<Map<String, dynamic>>> obtenerTodasLasTransacciones(
      String usuarioId) async {
    final data = await _client
        .from('transacciones')
        .select('*, categorias(nombre)')
        .eq('usuario_id', usuarioId)
        .order('fecha', ascending: false)
        .order('fecha_creacion', ascending: false);

    return List<Map<String, dynamic>>.from(data);
  }

  /// Edita una transacción existente por su id.
  /// Los metadatos de la sugerencia solo se envían cuando
  /// [escribirMetadatosSugerencia] es true: en ese caso se escriben los cuatro
  /// tal cual (con null explícito si no hubo sugerencia). Si es false, no se
  /// envían y se conservan los que ya estaban guardados.
  Future<void> editarTransaccion({
    required String transaccionId,
    String? tipo,
    double? monto,
    String? categoriaId,
    String? descripcion,
    DateTime? fecha,
    String? metodoPago,
    bool? esGastoTrabajo,
    int? grupoSugeridoId,
    double? confianzaSugerencia,
    bool? categoriaCorregida,
    String? versionModelo,
    bool escribirMetadatosSugerencia = false,
  }) async {
    final updates = <String, dynamic>{};
    if (tipo != null) updates['tipo'] = tipo;
    if (monto != null) updates['monto'] = monto;
    if (categoriaId != null) updates['categoria_id'] = categoriaId;
    if (descripcion != null) updates['descripcion'] = descripcion;
    if (fecha != null) updates['fecha'] = fecha.toIso8601String().split('T')[0];
    if (metodoPago != null) updates['metodo_pago'] = metodoPago;
    if (esGastoTrabajo != null) updates['es_gasto_trabajo'] = esGastoTrabajo;
    if (escribirMetadatosSugerencia) {
      updates['grupo_sugerido_id'] = grupoSugeridoId;
      updates['confianza_sugerencia'] = confianzaSugerencia;
      updates['categoria_corregida'] = categoriaCorregida;
      updates['version_modelo'] = versionModelo;
    }

    if (updates.isEmpty) return;

    await _client.from('transacciones').update(updates).eq('id', transaccionId);
  }

  /// Elimina una transacción por su id.
  Future<void> eliminarTransaccion(String transaccionId) async {
    await _client.from('transacciones').delete().eq('id', transaccionId);
  }
}
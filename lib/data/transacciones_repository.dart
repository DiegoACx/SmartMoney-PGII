import 'package:supabase_flutter/supabase_flutter.dart';

class TransaccionesRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Trae todas las transacciones del usuario actualmente autenticado.
  Future<List<Map<String, dynamic>>> obtenerTransacciones() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay usuario autenticado');
    }

    final data = await _client
        .from('transacciones')
        .select()
        .eq('usuario_id', userId);

    return List<Map<String, dynamic>>.from(data);
  }
}
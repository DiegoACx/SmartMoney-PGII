import 'package:supabase_flutter/supabase_flutter.dart';

class CategoriasRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Trae todas las categorías visibles para el usuario autenticado:
  /// sus propias categorías más las predeterminadas (usuario_id IS NULL).
  /// El filtro real lo aplica la política RLS de Supabase, no este código.
  Future<List<Map<String, dynamic>>> obtenerCategorias() async {
    final data = await _client
        .from('categorias')
        .select()
        .order('nombre', ascending: true);

    return List<Map<String, dynamic>>.from(data);
  }
}
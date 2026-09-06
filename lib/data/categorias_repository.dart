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

  /// Crea una nueva categoría personalizada para el usuario autenticado.
  /// Retorna la fila recién creada con su id generado.
  /// Lanza una excepción si no hay usuario autenticado.
  Future<Map<String, dynamic>> crearCategoria({
    required String nombre,
    required String tipo,
  }) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay usuario autenticado');
    }

    final data = await _client
        .from('categorias')
        .insert({
          'nombre': nombre,
          'tipo': tipo,
          'usuario_id': userId,
          'es_predeterminada': false,
        })
        .select()
        .single();

    return Map<String, dynamic>.from(data as Map);
  }
}
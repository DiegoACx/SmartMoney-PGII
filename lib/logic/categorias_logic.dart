import '../data/categorias_repository.dart';

/// Resultado de la operación de crear categoría:
/// exito=true con la categoría creada, o error con mensaje.
class ResultadoCrearCategoria {
  final bool exito;
  final Map<String, dynamic>? categoria;
  final String? mensajeError;

  const ResultadoCrearCategoria.exito(this.categoria)
      : exito = true,
        mensajeError = null;

  const ResultadoCrearCategoria.error(this.mensajeError)
      : exito = false,
        categoria = null;
}

class CategoriasLogic {
  final CategoriasRepository _repository = CategoriasRepository();

  Future<List<Map<String, dynamic>>> obtenerCategoriasDisponibles() async {
    return await _repository.obtenerCategorias();
  }

  /// Valida y crea una nueva categoría.
  /// Retorna [ResultadoCrearCategoria.exito] con la categoría creada,
  /// o [ResultadoCrearCategoria.error] con un mensaje legible.
  Future<ResultadoCrearCategoria> crearCategoria({
    required String nombre,
    required String tipo,
  }) async {
    // Validación local, sin tocar el repositorio
    final nombreLimpio = nombre.trim();
    if (nombreLimpio.isEmpty) {
      return const ResultadoCrearCategoria.error(
        'El nombre de la categoría no puede estar vacío',
      );
    }
    if (tipo != 'ingreso' && tipo != 'egreso') {
      return const ResultadoCrearCategoria.error(
        'Tipo de categoría inválido',
      );
    }

    try {
      final creada = await _repository.crearCategoria(
        nombre: nombreLimpio,
        tipo: tipo,
      );
      return ResultadoCrearCategoria.exito(creada);
    } catch (e) {
      if (e.toString().contains('No hay usuario autenticado')) {
        return const ResultadoCrearCategoria.error(
          'No hay usuario autenticado. Inicia sesión para continuar.',
        );
      }
      return const ResultadoCrearCategoria.error(
        'Ocurrió un error al crear la categoría. Intenta de nuevo.',
      );
    }
  }
}

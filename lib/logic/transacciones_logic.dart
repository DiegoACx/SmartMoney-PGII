import '../data/transacciones_repository.dart';

/// Resultado de una validación: indica si es válida y, si no, por qué.
class ResultadoValidacion {
  final bool esValido;
  final String? mensajeError;

  const ResultadoValidacion.valido()
      : esValido = true,
        mensajeError = null;

  const ResultadoValidacion.invalido(String mensaje)
      : esValido = false,
        mensajeError = mensaje;
}

class TransaccionesLogic {
  final TransaccionesRepository _repository = TransaccionesRepository();

  /// Valida que el monto sea positivo y que la categoría exista
  /// dentro de la lista de categorías válidas del usuario.
  ResultadoValidacion validarTransaccion({
    required double monto,
    required String categoriaId,
    required List<String> categoriasValidas,
  }) {
    if (monto <= 0) {
      return const ResultadoValidacion.invalido(
        'El monto debe ser mayor que cero',
      );
    }

    if (!categoriasValidas.contains(categoriaId)) {
      return const ResultadoValidacion.invalido(
        'La categoría seleccionada no existe',
      );
    }

    return const ResultadoValidacion.valido();
  }

  /// Calcula la utilidad (ingresos - egresos) de las transacciones
  /// cuya fecha cae dentro del rango [fechaInicio, fechaFin] (ambos inclusive).
  /// No sabe de dónde vienen las transacciones, solo recibe la lista y calcula.
  double calcularUtilidadPeriodo(
    List<Map<String, dynamic>> transacciones, {
    required DateTime fechaInicio,
    required DateTime fechaFin,
  }) {
    double utilidad = 0;

    for (final t in transacciones) {
      final fecha = DateTime.parse(t['fecha'] as String);

      final dentroDelRango = !fecha.isBefore(fechaInicio) &&
          !fecha.isAfter(fechaFin);

      if (!dentroDelRango) continue;

      final monto = (t['monto'] as num).toDouble();
      final tipo = t['tipo'] as String;

      if (tipo == 'ingreso') {
        utilidad += monto;
      } else if (tipo == 'egreso') {
        utilidad -= monto;
      }
    }

    return utilidad;
  }

  /// Obtiene las transacciones más recientes de un usuario,
  /// limitadas a [limite] elementos. La lista ya viene ordenada
  /// por fecha descendente desde el repositorio.
  Future<List<Map<String, dynamic>>> obtenerTransaccionesRecientes(
    String usuarioId, {
    int limite = 10,
  }) async {
    final todas = await _repository.obtenerTransacciones(usuarioId);
    return todas.take(limite).toList();
  }

  /// Valida y registra una nueva transacción.
  /// Retorna null si todo sale bien, o un String con el mensaje de error.
  Future<String?> registrarTransaccion({
    required double monto,
    required String tipo,
    required String categoriaId,
    required DateTime fecha,
    String? nota,
    required List<String> categoriasValidas,
  }) async {
    // Primero validamos sin tocar el repositorio
    final validacion = validarTransaccion(
      monto: monto,
      categoriaId: categoriaId,
      categoriasValidas: categoriasValidas,
    );
    if (!validacion.esValido) {
      return validacion.mensajeError;
    }

    try {
      await _repository.crearTransaccion(
        tipo: tipo,
        monto: monto,
        categoriaId: categoriaId,
        descripcion: nota,
        fecha: fecha,
      );
      return null;
    } catch (e) {
      if (e.toString().contains('No hay usuario autenticado')) {
        return 'No hay usuario autenticado. Inicia sesión para continuar.';
      }
      return 'Ocurrió un error al guardar la transacción. Intenta de nuevo.';
    }
  }
}
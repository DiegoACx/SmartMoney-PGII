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
}
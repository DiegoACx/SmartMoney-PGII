class FinanzasLogic {
  /// Calcula el total neto (ingresos - egresos) a partir de una lista de transacciones.
  /// No sabe de dónde vienen los datos, solo recibe una lista y calcula.
  double calcularTotalNeto(List<Map<String, dynamic>> transacciones) {
    double total = 0;

    for (final t in transacciones) {
      final monto = (t['monto'] as num).toDouble();
      final tipo = t['tipo'] as String;

      if (tipo == 'ingreso') {
        total += monto;
      } else if (tipo == 'egreso') {
        total -= monto;
      }
    }

    return total;
  }
}
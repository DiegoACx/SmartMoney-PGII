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

/// Totales calculados sobre un periodo de tiempo.
/// [diferencia] = [totalIngresos] - [totalEgresos].
class TotalesPeriodo {
  final double totalIngresos;
  final double totalEgresos;
  final double diferencia;

  const TotalesPeriodo({
    required this.totalIngresos,
    required this.totalEgresos,
  }) : diferencia = totalIngresos - totalEgresos;
}

/// Periodos predefinidos para los cálculos del dashboard.
enum PeriodoDashboard {
  mesActual,
  mesPasado,
  ultimos3Meses,
  ultimos5Meses,
  anual,
}

/// Periodo de agrupación temporal para análisis de consumo.
enum PeriodoAgrupacion { semana, mes }

String _claveMes(DateTime fecha) =>
    '${fecha.year}-${fecha.month.toString().padLeft(2, '0')}';

String _claveSemana(DateTime fecha) {
  final lunes = fecha.subtract(Duration(days: fecha.weekday - 1));
  return '${lunes.year}-${lunes.month.toString().padLeft(2, '0')}-'
      '${lunes.day.toString().padLeft(2, '0')}';
}

DateTime _primerDiaDeMesesAtras(int mesesAtras) {
  final ahora = DateTime.now();
  return DateTime(ahora.year, ahora.month - mesesAtras, 1);
}

class TransaccionesLogic {
  final TransaccionesRepository _repository = TransaccionesRepository();

  // ===== MÉTODOS EXISTENTES (SIN MODIFICAR) =====

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

  // ===== MÉTODOS NUEVOS =====

  /// Dado un periodo del dashboard, retorna (fechaInicio, fechaFin)
  /// correspondiente, en hora local.
  (DateTime, DateTime) obtenerRangoFechas(PeriodoDashboard periodo) {
    final ahora = DateTime.now();
    switch (periodo) {
      case PeriodoDashboard.mesActual:
        return (DateTime(ahora.year, ahora.month, 1), ahora);
      case PeriodoDashboard.mesPasado:
        final primerDiaMesActual = DateTime(ahora.year, ahora.month, 1);
        final ultimoDiaMesPasado =
            primerDiaMesActual.subtract(const Duration(days: 1));
        return (
          DateTime(ultimoDiaMesPasado.year, ultimoDiaMesPasado.month, 1),
          ultimoDiaMesPasado,
        );
      case PeriodoDashboard.ultimos3Meses:
        return (DateTime(ahora.year, ahora.month - 3, ahora.day), ahora);
      case PeriodoDashboard.ultimos5Meses:
        return (DateTime(ahora.year, ahora.month - 5, ahora.day), ahora);
      case PeriodoDashboard.anual:
        return (DateTime(ahora.year, 1, 1), ahora);
    }
  }

  /// Calcula los totales (ingresos / egresos / diferencia) de un periodo
  /// sobre una lista de transacciones ya cargada en memoria.
  TotalesPeriodo calcularTotalesPeriodo(
    List<Map<String, dynamic>> transacciones,
    PeriodoDashboard periodo,
  ) {
    final (fechaInicio, fechaFin) = obtenerRangoFechas(periodo);
    double ingresos = 0;
    double egresos = 0;
    for (final t in transacciones) {
      final fecha = DateTime.parse(t['fecha'] as String);
      if (fecha.isBefore(fechaInicio) || fecha.isAfter(fechaFin)) continue;
      final monto = (t['monto'] as num).toDouble();
      final tipo = t['tipo'] as String;
      if (tipo == 'ingreso') {
        ingresos += monto;
      } else if (tipo == 'egreso') {
        egresos += monto;
      }
    }
    return TotalesPeriodo(totalIngresos: ingresos, totalEgresos: egresos);
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
    required String metodoPago,
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
    if (metodoPago != 'efectivo' && metodoPago != 'transferencia') {
      return 'Selecciona un método de pago válido';
    }

    try {
      await _repository.crearTransaccion(
        tipo: tipo,
        monto: monto,
        categoriaId: categoriaId,
        descripcion: nota,
        fecha: fecha,
        metodoPago: metodoPago,
      );
      return null;
    } catch (e) {
      if (e.toString().contains('No hay usuario autenticado')) {
        return 'No hay usuario autenticado. Inicia sesión para continuar.';
      }
      return 'Ocurrió un error al guardar la transacción. Intenta de nuevo.';
    }
  }

  /// Valida y edita una transacción existente.
  /// Retorna null si todo sale bien, o un String con el mensaje de error.
  Future<String?> editarTransaccion({
    required String transaccionId,
    required double monto,
    required String tipo,
    required String categoriaId,
    required DateTime fecha,
    String? nota,
    required List<String> categoriasValidas,
    required String metodoPago,
  }) async {
    final validacion = validarTransaccion(
      monto: monto,
      categoriaId: categoriaId,
      categoriasValidas: categoriasValidas,
    );
    if (!validacion.esValido) {
      return validacion.mensajeError;
    }
    if (metodoPago != 'efectivo' && metodoPago != 'transferencia') {
      return 'Selecciona un método de pago válido';
    }

    try {
      await _repository.editarTransaccion(
        transaccionId: transaccionId,
        tipo: tipo,
        monto: monto,
        categoriaId: categoriaId,
        descripcion: nota,
        fecha: fecha,
        metodoPago: metodoPago,
      );
      return null;
    } catch (e) {
      return 'Ocurrió un error al actualizar la transacción. Intenta de nuevo.';
    }
  }

  /// Elimina una transacción existente.
  /// Retorna null si todo sale bien, o un String con el mensaje de error.
  Future<String?> eliminarTransaccion(String transaccionId) async {
    try {
      await _repository.eliminarTransaccion(transaccionId);
      return null;
    } catch (e) {
      return 'Ocurrió un error al eliminar la transacción. Intenta de nuevo.';
    }
  }

  /// Calcula el total neto (ingresos - egresos) sobre TODA la lista
  /// recibida, sin filtrar por fecha.
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

  // ===== Filtros y agrupaciones (síncronos, sobre lista en memoria) =====

  /// Deja solo las transacciones cuyo [tipo] coincide ('ingreso' / 'egreso').
  List<Map<String, dynamic>> filtrarPorTipo(
    List<Map<String, dynamic>> transacciones,
    String tipo,
  ) {
    return transacciones.where((t) => t['tipo'] == tipo).toList();
  }

  /// Agrupa las transacciones por **nombre de categoría**.
  /// El Map resultante incluye también las categorías que no tienen
  /// transacciones (con una lista vacía), en el orden de [todasLasCategorias].
  Map<String, List<Map<String, dynamic>>> agruparPorCategoria(
    List<Map<String, dynamic>> transacciones,
    List<Map<String, dynamic>> todasLasCategorias,
  ) {
    final Map<String, List<Map<String, dynamic>>> resultado = {
      for (final c in todasLasCategorias) c['nombre'].toString(): [],
    };
    for (final t in transacciones) {
      final nombreCategoria = (t['categorias'] is Map)
          ? (t['categorias'] as Map)['nombre']?.toString() ?? 'Sin categoría'
          : 'Sin categoría';
      resultado.putIfAbsent(nombreCategoria, () => []).add(t);
    }
    return resultado;
  }

  /// Agrupa las transacciones por fecha (string 'YYYY-MM-DD'), tal cual
  /// vienen en el campo de la tabla.
  Map<String, List<Map<String, dynamic>>> agruparPorFecha(
    List<Map<String, dynamic>> transacciones,
  ) {
    final Map<String, List<Map<String, dynamic>>> resultado = {};
    for (final t in transacciones) {
      final fecha = t['fecha'] as String; // ya viene como 'YYYY-MM-DD'
      resultado.putIfAbsent(fecha, () => []).add(t);
    }
    return resultado;
  }

  /// Obtiene todas las transacciones de un usuario (sin límite).
  Future<List<Map<String, dynamic>>> obtenerTodasLasTransacciones(
    String usuarioId,
  ) async {
    return await _repository.obtenerTodasLasTransacciones(usuarioId);
  }

  /// Agrupa transacciones por periodo (semana o mes) y, dentro de cada
  /// periodo, por categoría, sumando los montos. Por defecto solo considera
  /// egresos (tipo: 'egreso'), ya que esta función alimenta el análisis de
  /// patrones de consumo/gasto. Pasa tipo: null si necesitas incluir ambos
  /// tipos, o tipo: 'ingreso' para solo ingresos.
  Map<String, Map<String, double>> agruparPorCategoriaYPeriodo(
    List<Map<String, dynamic>> transacciones,
    PeriodoAgrupacion periodo, {
    String? tipo = 'egreso',
  }) {
    final Map<String, Map<String, double>> resultado = {};
    for (final t in transacciones) {
      if (tipo != null && t['tipo'] != tipo) continue;
      final fecha = DateTime.parse(t['fecha'] as String);
      final clavePeriodo = periodo == PeriodoAgrupacion.mes
          ? _claveMes(fecha)
          : _claveSemana(fecha);
      final cat = t['categorias'];
      final nombreCategoria = (cat is Map)
          ? (cat['nombre']?.toString() ?? 'Sin categoría')
          : 'Sin categoría';
      final monto = (t['monto'] as num).toDouble();
      resultado.putIfAbsent(clavePeriodo, () => {});
      resultado[clavePeriodo]!.update(
        nombreCategoria,
        (v) => v + monto,
        ifAbsent: () => monto,
      );
    }
    return resultado;
  }

  /// Calcula, para el mes de [mes] (se usa solo year/month, se ignora el
  /// día), qué porcentaje representa el gasto de cada categoría respecto al
  /// ingreso TOTAL de ese mismo mes. Si no hay ningún ingreso registrado en
  /// el mes (totalIngresoMes <= 0), retorna un mapa vacío, ya que no se
  /// puede calcular un porcentaje sin una base de ingreso.
  Map<String, double> calcularPorcentajeGastoPorCategoria(
    List<Map<String, dynamic>> transacciones,
    DateTime mes,
  ) {
    final inicioMes = DateTime(mes.year, mes.month, 1);
    final finMes = DateTime(mes.year, mes.month + 1, 0);
    double totalIngresoMes = 0;
    final Map<String, double> gastoPorCategoria = {};

    for (final t in transacciones) {
      final fecha = DateTime.parse(t['fecha'] as String);
      if (fecha.isBefore(inicioMes) || fecha.isAfter(finMes)) continue;
      final monto = (t['monto'] as num).toDouble();
      final tipo = t['tipo'] as String;
      if (tipo == 'ingreso') {
        totalIngresoMes += monto;
      } else if (tipo == 'egreso') {
        final cat = t['categorias'];
        final nombreCategoria = (cat is Map)
            ? (cat['nombre']?.toString() ?? 'Sin categoría')
            : 'Sin categoría';
        gastoPorCategoria.update(
          nombreCategoria,
          (v) => v + monto,
          ifAbsent: () => monto,
        );
      }
    }

    if (totalIngresoMes <= 0) return {};

    return gastoPorCategoria.map(
      (categoria, gasto) =>
          MapEntry(categoria, (gasto / totalIngresoMes) * 100),
    );
  }

  /// Retorna una lista ordenada cronológicamente (más antiguo primero) con
  /// los últimos [meses] meses, cada uno con su total de ingresos y egresos.
  /// Siempre incluye TODOS los meses del rango, aunque no tengan
  /// transacciones (con totales en 0), para que el eje X de la gráfica sea
  /// consistente.
  List<Map<String, dynamic>> obtenerTotalesMensuales(
    List<Map<String, dynamic>> transacciones, {
    int meses = 6,
  }) {
    final Map<String, Map<String, double>> acumulado = {};
    final List<DateTime> mesesRango = [];
    for (int i = meses - 1; i >= 0; i--) {
      final mes = _primerDiaDeMesesAtras(i);
      final clave = _claveMes(mes);
      mesesRango.add(mes);
      acumulado[clave] = {'ingresos': 0, 'egresos': 0};
    }
    for (final t in transacciones) {
      final fecha = DateTime.parse(t['fecha'] as String);
      final clave = _claveMes(fecha);
      if (!acumulado.containsKey(clave)) continue;
      final monto = (t['monto'] as num).toDouble();
      final tipo = t['tipo'] as String;
      if (tipo == 'ingreso') {
        acumulado[clave]!['ingresos'] = acumulado[clave]!['ingresos']! + monto;
      } else if (tipo == 'egreso') {
        acumulado[clave]!['egresos'] = acumulado[clave]!['egresos']! + monto;
      }
    }
    return mesesRango.map((mes) {
      final clave = _claveMes(mes);
      return {
        'mes': mes,
        'ingresos': acumulado[clave]!['ingresos']!,
        'egresos': acumulado[clave]!['egresos']!,
      };
    }).toList();
  }

  /// Retorna, para los últimos [meses] meses, tanto el neto de cada mes
  /// (ingresos - egresos de ESE mes) como el saldo acumulado (la suma
  /// corrida de los netos hasta ese mes, incluido). Reutiliza
  /// obtenerTotalesMensuales() para no duplicar el cálculo de totales.
  List<Map<String, dynamic>> obtenerFlujoCajaMensual(
    List<Map<String, dynamic>> transacciones, {
    int meses = 6,
  }) {
    final totalesMensuales = obtenerTotalesMensuales(transacciones, meses: meses);
    double acumulado = 0;
    return totalesMensuales.map((m) {
      final neto = (m['ingresos'] as double) - (m['egresos'] as double);
      acumulado += neto;
      return {
        'mes': m['mes'],
        'neto': neto,
        'acumulado': acumulado,
      };
    }).toList();
  }

  /// Retorna el monto total gastado (egresos) por categoría, dentro del mes
  /// de [mes] (se usa solo year/month). Solo incluye categorías con gasto
  /// mayor a 0 en ese mes (no incluye categorías vacías, a diferencia de
  /// agruparPorCategoria).
  Map<String, double> obtenerDistribucionGastosPorCategoria(
    List<Map<String, dynamic>> transacciones,
    DateTime mes,
  ) {
    final inicioMes = DateTime(mes.year, mes.month, 1);
    final finMes = DateTime(mes.year, mes.month + 1, 0);
    final Map<String, double> resultado = {};
    for (final t in transacciones) {
      if (t['tipo'] != 'egreso') continue;
      final fecha = DateTime.parse(t['fecha'] as String);
      if (fecha.isBefore(inicioMes) || fecha.isAfter(finMes)) continue;
      final cat = t['categorias'];
      final nombreCategoria = (cat is Map)
          ? (cat['nombre']?.toString() ?? 'Sin categoría')
          : 'Sin categoría';
      final monto = (t['monto'] as num).toDouble();
      resultado.update(
        nombreCategoria,
        (v) => v + monto,
        ifAbsent: () => monto,
      );
    }
    return resultado;
  }
}

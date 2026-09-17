import '../data/metas_repository.dart';

class ResultadoTiempoEstimado {
  final bool yaCumplida;
  final bool sinDatosSuficientes;
  final int? diasEstimados;
  final DateTime? fechaEstimada;

  const ResultadoTiempoEstimado.cumplida()
      : yaCumplida = true,
        sinDatosSuficientes = false,
        diasEstimados = null,
        fechaEstimada = null;

  const ResultadoTiempoEstimado.sinDatos()
      : yaCumplida = false,
        sinDatosSuficientes = true,
        diasEstimados = null,
        fechaEstimada = null;

  const ResultadoTiempoEstimado.estimado(this.diasEstimados, this.fechaEstimada)
      : yaCumplida = false,
        sinDatosSuficientes = false;
}

class MetasLogic {
  final MetasRepository _repository = MetasRepository();

  double calcularPorcentajeAvance(Map<String, dynamic> meta) {
    final montoActual = (meta['monto_actual'] as num).toDouble();
    final montoObjetivo = (meta['monto_objetivo'] as num).toDouble();

    if (montoObjetivo <= 0) return 0;

    final porcentaje = (montoActual / montoObjetivo) * 100;
    return porcentaje.clamp(0, 100);
  }

  Future<ResultadoTiempoEstimado> calcularTiempoEstimado(
    Map<String, dynamic> meta,
  ) async {
    if (meta['cumplida'] == true) {
      return const ResultadoTiempoEstimado.cumplida();
    }

    try {
      final aportes =
          await _repository.obtenerAportesDeMeta(meta['id'].toString());

      final ahora = DateTime.now();
      final limite30Dias = DateTime(ahora.year, ahora.month, ahora.day)
          .subtract(const Duration(days: 30));

      final aportesUltimos30Dias = aportes.where((a) {
        final fechaAporte = DateTime.parse(a['fecha'] as String);
        return !fechaAporte.isBefore(limite30Dias);
      }).toList();

      if (aportesUltimos30Dias.isEmpty) {
        return const ResultadoTiempoEstimado.sinDatos();
      }

      double totalAportadoUltimos30Dias = 0;
      for (final a in aportesUltimos30Dias) {
        totalAportadoUltimos30Dias += (a['monto'] as num).toDouble();
      }

      final ritmoDiario = totalAportadoUltimos30Dias / 30;

      final montoActual = (meta['monto_actual'] as num).toDouble();
      final montoObjetivo = (meta['monto_objetivo'] as num).toDouble();
      final montoRestante = montoObjetivo - montoActual;

      if (montoRestante <= 0) {
        return const ResultadoTiempoEstimado.cumplida();
      }

      final diasEstimados = (montoRestante / ritmoDiario).ceil();
      final fechaEstimada = DateTime.now().add(Duration(days: diasEstimados));

      return ResultadoTiempoEstimado.estimado(diasEstimados, fechaEstimada);
    } catch (e) {
      return const ResultadoTiempoEstimado.sinDatos();
    }
  }
}

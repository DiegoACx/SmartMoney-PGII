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

class ResultadoCrearMeta {
  final String? error;
  final Map<String, dynamic>? metaCreada;

  ResultadoCrearMeta.error(this.error) : metaCreada = null;
  ResultadoCrearMeta.exito(this.metaCreada) : error = null;

  bool get exito => error == null;
}

class ResultadoRegistrarAporte {
  final String? error;
  final Map<String, dynamic>? metaActualizada;

  ResultadoRegistrarAporte.error(this.error) : metaActualizada = null;
  ResultadoRegistrarAporte.exito(this.metaActualizada) : error = null;

  bool get exito => error == null;
}

class MetasLogic {
  final MetasRepository _repository = MetasRepository();

  double calcularPorcentajeAvance(Map<String, dynamic> meta) {
    final montoActual = (meta['monto_actual'] as num?)?.toDouble() ?? 0;
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

      if (ritmoDiario <= 0) {
        return const ResultadoTiempoEstimado.sinDatos();
      }

      final montoActual = (meta['monto_actual'] as num?)?.toDouble() ?? 0;
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

  /// Valida y crea una meta. Retorna ResultadoCrearMeta con error o la meta
  /// creada (incluyendo su id). Usa validaciones locales antes de tocar el
  /// repositorio, y try/catch para errores de la BD.
  Future<ResultadoCrearMeta> crearMeta({
    required String nombre,
    required double montoObjetivo,
    DateTime? fechaLimite,
  }) async {
    if (nombre.trim().isEmpty) {
      return ResultadoCrearMeta.error('Ingresa un nombre para la meta');
    }
    if (montoObjetivo <= 0) {
      return ResultadoCrearMeta.error(
        'El monto objetivo debe ser mayor que cero',
      );
    }
    if (fechaLimite != null) {
      final hoy = DateTime.now();
      final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);
      final soloLimite =
          DateTime(fechaLimite.year, fechaLimite.month, fechaLimite.day);
      if (soloLimite.isBefore(soloHoy)) {
        return ResultadoCrearMeta.error(
          'La fecha límite debe ser una fecha futura',
        );
      }
    }

    try {
      final creada = await _repository.crearMeta(
        nombre: nombre.trim(),
        montoObjetivo: montoObjetivo,
        fechaLimite: fechaLimite,
      );
      return ResultadoCrearMeta.exito(creada);
    } catch (e) {
      return ResultadoCrearMeta.error(
        'No se pudo crear la meta. Inténtalo nuevamente.',
      );
    }
  }

  Future<String?> editarMeta({
    required String metaId,
    String? nombre,
    double? montoObjetivo,
    DateTime? fechaLimite,
    bool quitarFecha = false,
  }) async {
    if (nombre != null && nombre.trim().isEmpty) {
      return 'Ingresa un nombre para la meta';
    }
    if (montoObjetivo != null && montoObjetivo <= 0) {
      return 'El monto objetivo debe ser mayor que cero';
    }
    if (!quitarFecha && fechaLimite != null) {
      final hoy = DateTime.now();
      final soloHoy = DateTime(hoy.year, hoy.month, hoy.day);
      final soloLimite =
          DateTime(fechaLimite.year, fechaLimite.month, fechaLimite.day);
      if (soloLimite.isBefore(soloHoy)) {
        return 'La fecha límite debe ser una fecha futura';
      }
    }

    try {
      await _repository.editarMeta(
        metaId: metaId,
        nombre: nombre?.trim(),
        montoObjetivo: montoObjetivo,
        fechaLimite: fechaLimite,
        quitarFecha: quitarFecha,
      );
      return null;
    } catch (e) {
      return 'No se pudo actualizar la meta. Inténtalo nuevamente.';
    }
  }

  Future<String?> eliminarMeta(String metaId) async {
    try {
      await _repository.eliminarMeta(metaId);
      return null;
    } catch (e) {
      return 'No se pudo eliminar la meta. Inténtalo nuevamente.';
    }
  }

  /// Registra un movimiento sobre el monto acumulado de una meta.
  /// [delta] positivo = aporte (suma), negativo = retiro (resta). El
  /// monto acumulado nunca puede quedar por debajo de 0.
  ///
  /// NOTA: actualizarProgreso() y crearAporte() son 2 operaciones separadas
  /// contra Supabase (no una transacción atómica). En el caso borde de
  /// que la segunda falle después de que la primera funcionó, el
  /// monto_actual quedaría actualizado sin su registro correspondiente
  /// en el historial de aportes_meta. Limitación conocida y aceptada para
  /// el alcance de este proyecto.
  Future<ResultadoRegistrarAporte> registrarMovimientoMeta({
    required Map<String, dynamic> meta,
    required double delta,
  }) async {
    if (delta == 0) {
      return ResultadoRegistrarAporte.error(
        'El monto debe ser distinto de cero',
      );
    }

    final montoActual = (meta['monto_actual'] as num?)?.toDouble() ?? 0;
    final montoObjetivo = (meta['monto_objetivo'] as num).toDouble();
    final metaId = meta['id'].toString();

    final nuevoMontoActual = montoActual + delta;
    if (nuevoMontoActual < 0) {
      return ResultadoRegistrarAporte.error(
        'No puedes retirar más de lo que tienes ahorrado en esta meta.',
      );
    }

    final cumplida = nuevoMontoActual >= montoObjetivo;

    try {
      final actualizada = await _repository.actualizarProgreso(
        metaId: metaId,
        nuevoMontoActual: nuevoMontoActual,
        cumplida: cumplida,
      );
      await _repository.crearAporte(
        metaId: metaId,
        monto: delta,
        fecha: DateTime.now(),
      );
      return ResultadoRegistrarAporte.exito(actualizada);
    } catch (e) {
      return ResultadoRegistrarAporte.error(
        'No se pudo registrar el movimiento. Inténtalo nuevamente.',
      );
    }
  }

  /// Wrapper de obtenerMetas del repositorio.
  Future<List<Map<String, dynamic>>> obtenerMetas(String usuarioId) async {
    return _repository.obtenerMetas(usuarioId);
  }

  /// Calcula la fecha para un recordatorio N días ANTES de la fecha límite.
  /// Si no hay fecha límite, o la fecha calculada ya pasó, retorna null.
  DateTime? calcularFechaRecordatorio(
    DateTime? fechaLimite, {
    int diasAntes = 3,
  }) {
    if (fechaLimite == null) return null;
    final fecha = fechaLimite.subtract(Duration(days: diasAntes));
    final ahora = DateTime.now();
    final hoySinHora = DateTime(ahora.year, ahora.month, ahora.day);
    if (fecha.isBefore(hoySinHora)) return null;
    return fecha;
  }
}

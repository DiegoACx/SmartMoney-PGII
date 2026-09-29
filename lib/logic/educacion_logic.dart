import '../data/educacion_repository.dart';

class EscalonConEstado {
  final Map<String, dynamic> escalon;
  final bool desbloqueado;
  final bool completado;
  final double? puntaje;

  const EscalonConEstado({
    required this.escalon,
    required this.desbloqueado,
    required this.completado,
    this.puntaje,
  });

  String get id => escalon['id'].toString();
  String get tipo => escalon['tipo'].toString();
  String get titulo => escalon['titulo'].toString();
  bool get esEvaluacion => tipo == 'evaluacion';
  bool get disponible => escalon['disponible'] == true;
}

class NivelConEstado {
  final Map<String, dynamic> nivel;
  final bool desbloqueado;
  final List<EscalonConEstado> escalones;

  const NivelConEstado({
    required this.nivel,
    required this.desbloqueado,
    required this.escalones,
  });

  String get id => nivel['id'].toString();
  String get nombre => nivel['nombre'].toString();
  String get colorHex => nivel['color_hex'].toString();
  String get mensajeBienvenida => nivel['mensaje_bienvenida'].toString();

  double get porcentajeProgreso {
    if (escalones.isEmpty) return 0;
    final completados = escalones.where((e) => e.completado).length;
    return (completados / escalones.length) * 100;
  }
}

class ResultadoEvaluacion {
  final bool aprobado;
  final double puntaje;
  final int correctas;
  final int total;

  const ResultadoEvaluacion({
    required this.aprobado,
    required this.puntaje,
    required this.correctas,
    required this.total,
  });
}

class EducacionLogic {
  final EducacionRepository _repository = EducacionRepository();

  Future<List<NivelConEstado>> cargarArbolCompleto(String usuarioId) async {
    final niveles = await _repository.obtenerNiveles();

    final Map<String, List<Map<String, dynamic>>> escalonesPorNivel = {};
    for (final nivel in niveles) {
      final nivelId = nivel['id'].toString();
      escalonesPorNivel[nivelId] =
          await _repository.obtenerEscalonesPorNivel(nivelId);
    }
    final progreso = await _repository.obtenerProgreso(usuarioId);

    final Map<String, Map<String, dynamic>> progresoPorEscalon = {
      for (final p in progreso) p['escalon_id'].toString(): p,
    };

    final List<Map<String, dynamic>> cadenaGlobal = [];
    for (final nivel in niveles) {
      cadenaGlobal.addAll(escalonesPorNivel[nivel['id'].toString()]!);
    }

    final Map<String, EscalonConEstado> estadoPorEscalon = {};
    bool anteriorCompletado = true;
    for (final escalon in cadenaGlobal) {
      final escalonId = escalon['id'].toString();
      final filaProgreso = progresoPorEscalon[escalonId];
      final completado = filaProgreso?['completado'] == true;
      final puntaje = (filaProgreso?['puntaje'] as num?)?.toDouble();

      estadoPorEscalon[escalonId] = EscalonConEstado(
        escalon: escalon,
        desbloqueado: anteriorCompletado,
        completado: completado,
        puntaje: puntaje,
      );

      anteriorCompletado = completado;
    }

    return niveles.map((nivel) {
      final nivelId = nivel['id'].toString();
      final escalonesDelNivel = escalonesPorNivel[nivelId]!
          .map((e) => estadoPorEscalon[e['id'].toString()]!)
          .toList();
      final nivelDesbloqueado =
          escalonesDelNivel.isEmpty ? false : escalonesDelNivel.first.desbloqueado;

      return NivelConEstado(
        nivel: nivel,
        desbloqueado: nivelDesbloqueado,
        escalones: escalonesDelNivel,
      );
    }).toList();
  }

  Future<void> marcarLeccionCompletada({
    required String usuarioId,
    required String escalonId,
  }) async {
    await _repository.guardarProgreso(
      usuarioId: usuarioId,
      escalonId: escalonId,
      completado: true,
    );
  }

  Future<ResultadoEvaluacion> registrarResultadoEvaluacion({
    required String usuarioId,
    required String escalonId,
    required int correctas,
    required int total,
  }) async {
    final puntaje = total == 0 ? 0.0 : (correctas / total) * 100;
    final aprobado = puntaje >= 70;

    await _repository.guardarProgreso(
      usuarioId: usuarioId,
      escalonId: escalonId,
      completado: aprobado,
      puntaje: puntaje,
    );

    return ResultadoEvaluacion(
      aprobado: aprobado,
      puntaje: puntaje,
      correctas: correctas,
      total: total,
    );
  }

  Future<List<Map<String, dynamic>>> obtenerPreguntas(String escalonId) async {
    return _repository.obtenerPreguntas(escalonId);
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/auth_logic.dart';
import '../logic/educacion_logic.dart';
import '../logic/formato_utils.dart';
import 'widgets/indicador_progreso_escalones.dart';

class _CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 60);
    final firstControl = Offset(size.width * 0.25, size.height + 20);
    final firstEnd = Offset(size.width * 0.5, size.height - 30);
    path.quadraticBezierTo(
      firstControl.dx,
      firstControl.dy,
      firstEnd.dx,
      firstEnd.dy,
    );
    final secondControl = Offset(size.width * 0.75, size.height - 80);
    final secondEnd = Offset(size.width, size.height - 40);
    path.quadraticBezierTo(
      secondControl.dx,
      secondControl.dy,
      secondEnd.dx,
      secondEnd.dy,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class EscalonDetalleScreen extends StatefulWidget {
  final EscalonConEstado escalon;
  final NivelConEstado nivel;

  const EscalonDetalleScreen({
    super.key,
    required this.escalon,
    required this.nivel,
  });

  @override
  State<EscalonDetalleScreen> createState() => _EscalonDetalleScreenState();
}

class _EscalonDetalleScreenState extends State<EscalonDetalleScreen> {
  final _educacionLogic = EducacionLogic();
  final _authLogic = AuthLogic();

  bool _isLoading = false;
  bool _navegando = false;

  // ——— Estado de la evaluación ———
  bool _evalCargando = true;
  List<Map<String, dynamic>> _preguntas = [];
  final Map<String, String> _respuestasSeleccionadas = {};
  bool _evalEnviada = false;
  ResultadoEvaluacion? _resultadoEvaluacion;
  bool _mostrarModalInicio = true;

  @override
  void initState() {
    super.initState();
    if (widget.escalon.esEvaluacion) {
      _cargarPreguntas();
    }
  }

  Future<void> _cargarPreguntas() async {
    setState(() => _evalCargando = true);
    try {
      final lista =
          await _educacionLogic.obtenerPreguntas(widget.escalon.id);
      if (!mounted) return;
      setState(() {
        _preguntas = lista;
        _evalCargando = false;
      });
      if (lista.isNotEmpty && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _mostrarModalInicio) {
            _mostrarModalAvisoInicioEvaluacion();
          }
        });
      }
    } catch (e) {
      debugPrint('ERROR CARGAR PREGUNTAS: $e');
      if (!mounted) return;
      setState(() => _evalCargando = false);
    }
  }

  Future<void> _mostrarModalAvisoInicioEvaluacion() async {
    final colorNivel = colorFromHex(widget.nivel.colorHex);
    final cerrarModal = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorNivel.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.menu_book,
                  color: colorNivel,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Antes de empezar',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _bullet(
              icon: Icons.quiz,
              texto:
                  'Esta evaluación tiene ${_preguntas.length} ${_preguntas.length == 1 ? 'pregunta' : 'preguntas'} de opción múltiple.',
            ),
            const SizedBox(height: 10),
            _bullet(
              icon: Icons.trending_up,
              texto:
                  'Debes obtener mínimo el 70% para aprobar y desbloquear el siguiente contenido.',
            ),
            const SizedBox(height: 10),
            _bullet(
              icon: Icons.autorenew,
              texto:
                  'Si no apruebas, puedes repetir la evaluación cuando quieras — solo se guardará tu mejor resultado.',
            ),
            const SizedBox(height: 10),
            _bullet(
              icon: Icons.visibility,
              texto:
                  'Al finalizar verás tus respuestas y la explicación de cada pregunta.',
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              Navigator.pop(context);
            },
            child: Text(
              'Cancelar',
              style: GoogleFonts.poppins(
                color: const Color(0xFF8C8474),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(
            width: 170,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorNivel,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Empezar evaluación',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() {
      _mostrarModalInicio = false;
    });
    if (cerrarModal == false) {
      if (mounted) Navigator.pop(context);
    }
  }

  Widget _bullet({required IconData icon, required String texto}) {
    final colorNivel = colorFromHex(widget.nivel.colorHex);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 2),
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: colorNivel.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: colorNivel),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texto,
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF2B2B2B),
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  int _obtenerPosicionEscalon() {
    return widget.nivel.escalones.indexWhere(
          (e) => e.id == widget.escalon.id,
        ) +
        1;
  }

  Future<void> _mostrarMensajeMotivacional(String mensaje) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.auto_awesome,
              size: 44,
              color: Color(0xFFF5A623),
            ),
            const SizedBox(height: 16),
            Text(
              '¡Excelente!',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF2B2B2B),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              mensaje,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF2B2B2B),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: 160,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorFromHex(widget.nivel.colorHex),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Continuar',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _esUltimoEscalonDelNivel() {
    final escalones = widget.nivel.escalones;
    if (escalones.isEmpty) return false;
    final ordenes = escalones
        .map((e) {
          final raw = e.escalon['orden'];
          return raw is num ? raw.toInt() : int.tryParse(raw.toString()) ?? 0;
        })
        .toList();
    final maxOrden = ordenes.reduce((a, b) => a > b ? a : b);
    final ordenActualRaw = widget.escalon.escalon['orden'];
    final ordenActual = ordenActualRaw is num
        ? ordenActualRaw.toInt()
        : int.tryParse(ordenActualRaw.toString()) ?? 0;
    return ordenActual == maxOrden;
  }

  Future<void> _manejarFinalizacionExitosaUltimoEscalon() async {
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) {
      if (!mounted) return;
      Navigator.pop(context, true);
      return;
    }

    List<NivelConEstado> arbolActualizado = [];
    try {
      arbolActualizado =
          await _educacionLogic.cargarArbolCompleto(usuarioId);
    } catch (e) {
      debugPrint('ERROR RECARGAR ARBOL POST-COMPLETADO: $e');
    }

    if (!mounted) return;

    final ordenNivelActualRaw = widget.nivel.nivel['orden'];
    final ordenNivelActual = ordenNivelActualRaw is num
        ? ordenNivelActualRaw.toInt()
        : int.tryParse(ordenNivelActualRaw.toString()) ?? 0;

    NivelConEstado? nivelSiguiente;
    for (final n in arbolActualizado) {
      final ordenRaw = n.nivel['orden'];
      final orden = ordenRaw is num
          ? ordenRaw.toInt()
          : int.tryParse(ordenRaw.toString()) ?? 0;
      if (orden == ordenNivelActual + 1) {
        nivelSiguiente = n;
        break;
      }
    }

    if (nivelSiguiente != null && nivelSiguiente.desbloqueado) {
      final NivelConEstado nivelSiguienteOK = nivelSiguiente;
      final colorNivelActual = colorFromHex(widget.nivel.colorHex);
      final colorNivelSiguiente = colorFromHex(nivelSiguienteOK.colorHex);
      final colorClaroSiguiente =
          Color.lerp(colorNivelSiguiente, Colors.white, 0.35) ??
              colorNivelSiguiente;
      final primerEscalonSiguiente = nivelSiguienteOK.escalones.first;

      final accionElegida = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: colorNivelActual.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.celebration,
                  size: 32,
                  color: colorNivelActual,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '¡Nivel completado!',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2B2B2B),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Completaste el nivel ${widget.nivel.nombre}. ¿Quieres continuar directo con el nivel ${nivelSiguienteOK.nombre}?',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF2B2B2B),
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'cancelar'),
              child: Text(
                'Ahora no',
                style: GoogleFonts.poppins(
                  color: const Color(0xFF8C8474),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 160,
              height: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [colorNivelSiguiente, colorClaroSiguiente],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, 'continuar'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'Sí, continuar',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );

      if (!mounted) return;

      if (accionElegida == 'continuar') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EscalonDetalleScreen(
              escalon: primerEscalonSiguiente,
              nivel: nivelSiguienteOK,
            ),
          ),
        );
      } else {
        Navigator.pop(context, true);
      }
      return;
    }

    final colorNivelActual = colorFromHex(widget.nivel.colorHex);
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: colorNivelActual.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.celebration,
                size: 32,
                color: colorNivelActual,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '¡Felicidades!',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF2B2B2B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Completaste TODA la educación financiera. Eres todo un experto en finanzas.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF2B2B2B),
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          SizedBox(
            width: 160,
            height: 44,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: colorNivelActual,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'Continuar',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );

    if (!mounted) return;
    Navigator.pop(context, true);
  }

  Future<void> _completarLeccion() async {
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) return;

    setState(() => _isLoading = true);

    try {
      await _educacionLogic.marcarLeccionCompletada(
        usuarioId: usuarioId,
        escalonId: widget.escalon.id,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('¡Lección completada!'),
          backgroundColor: const Color(0xFF7A9B6C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );

      final mensajeMotivacional =
          widget.escalon.escalon['mensaje_motivacional']?.toString();
      if (mensajeMotivacional != null && mensajeMotivacional.trim().isNotEmpty) {
        await _mostrarMensajeMotivacional(mensajeMotivacional.trim());
      } else {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      if (!mounted) return;

      if (_esUltimoEscalonDelNivel()) {
        await _manejarFinalizacionExitosaUltimoEscalon();
      } else {
        await _continuarAlSiguienteEscalon();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo guardar el progreso. Inténtalo nuevamente.',
          ),
          backgroundColor: const Color(0xFFC0392B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.escalon.esEvaluacion) {
      return _buildPantallaEvaluacion();
    }

    return _buildPantallaLeccion();
  }

  bool _todasLasPreguntasRespondidas() {
    return _preguntas
        .every((p) => _respuestasSeleccionadas.containsKey(p['id'].toString()));
  }

  int _contarCorrectas() {
    int c = 0;
    for (final p in _preguntas) {
      final id = p['id'].toString();
      final sel = _respuestasSeleccionadas[id];
      final correcta = p['respuesta_correcta']?.toString();
      if (sel != null && correcta != null && sel == correcta) c++;
    }
    return c;
  }

  Future<void> _enviarEvaluacion() async {
    if (_evalEnviada) return;
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) return;

    final correctas = _contarCorrectas();
    setState(() => _isLoading = true);
    try {
      final resultado =
          await _educacionLogic.registrarResultadoEvaluacion(
        usuarioId: usuarioId,
        escalonId: widget.escalon.id,
        correctas: correctas,
        total: _preguntas.length,
      );
      if (!mounted) return;
      setState(() {
        _evalEnviada = true;
        _resultadoEvaluacion = resultado;
        _isLoading = false;
      });

      if (resultado.aprobado) {
        final mensajeMotivacional =
            widget.escalon.escalon['mensaje_motivacional']?.toString();
        if (mensajeMotivacional != null &&
            mensajeMotivacional.trim().isNotEmpty) {
          await _mostrarMensajeMotivacional(mensajeMotivacional.trim());
        }

        if (!mounted) return;
        if (_esUltimoEscalonDelNivel()) {
          await _manejarFinalizacionExitosaUltimoEscalon();
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'No se pudo guardar la evaluación. Inténtalo nuevamente.',
          ),
          backgroundColor: const Color(0xFFC0392B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  void _reiniciarEvaluacion() {
    setState(() {
      _respuestasSeleccionadas.clear();
      _evalEnviada = false;
      _resultadoEvaluacion = null;
    });
  }

  Widget _buildPantallaEvaluacion() {
    final colorNivel = colorFromHex(widget.nivel.colorHex);
    final colorClaro = Color.lerp(colorNivel, Colors.white, 0.35) ?? colorNivel;
    final posicion = _obtenerPosicionEscalon();
    final total = widget.nivel.escalones.length;
    final todasRespondidas = _todasLasPreguntasRespondidas();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.25,
                width: double.infinity,
                child: ClipPath(
                  clipper: _CurvedHeaderClipper(),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [colorNivel, colorClaro],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Align(
                              alignment: Alignment.topLeft,
                              child: IconButton(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(
                                  Icons.arrow_back_ios_new,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Spacer(flex: 1),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.menu_book,
                                          size: 14,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Evaluación',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                widget.escalon.titulo,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                            ),
                            const Spacer(flex: 2),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$posicion de $total',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF8C8474),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.center,
                            child: IndicadorProgresoEscalones(
                              escalones: widget.nivel.escalones,
                              colorNivel: colorNivel,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (_evalCargando)
                      const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF58774B),
                        ),
                      )
                    else if (_preguntas.isEmpty)
                      _buildSinPreguntas(colorNivel)
                    else ...[
                      if (_evalEnviada && _resultadoEvaluacion != null)
                        _buildTarjetaResultado(colorNivel),
                      const SizedBox(height: 20),
                      for (int i = 0; i < _preguntas.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: _buildTarjetaPregunta(
                            _preguntas[i],
                            i + 1,
                            colorNivel,
                          ),
                        ),
                      const SizedBox(height: 12),
                      if (!_evalEnviada)
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [colorNivel, colorClaro],
                              ),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: ElevatedButton(
                              onPressed: (_isLoading || !todasRespondidas)
                                  ? null
                                  : _enviarEvaluacion,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2.5,
                                      ),
                                    )
                                  : Text(
                                      todasRespondidas
                                          ? 'Enviar respuestas'
                                          : 'Faltan ${_preguntas.length - _respuestasSeleccionadas.length} por responder',
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        )
                      else ...[
                        Row(
                          children: [
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: OutlinedButton(
                                  onPressed: _reiniciarEvaluacion,
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: colorNivel,
                                      width: 1.5,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: Text(
                                    'Repetir evaluación',
                                    style: GoogleFonts.poppins(
                                      color: colorNivel,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SizedBox(
                                height: 52,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [colorNivel, colorClaro],
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: ElevatedButton(
                                    onPressed: (_resultadoEvaluacion
                                                    ?.aprobado ==
                                                true &&
                                            !_esUltimoEscalonDelNivel() &&
                                            _navegando)
                                        ? null
                                        : () async {
                                            final aprobado =
                                                _resultadoEvaluacion
                                                        ?.aprobado ??
                                                    false;
                                            if (aprobado) {
                                              if (_esUltimoEscalonDelNivel()) {
                                                Navigator.pop(context, true);
                                              } else {
                                                await _continuarAlSiguienteEscalon();
                                              }
                                            } else {
                                              Navigator.pop(context, false);
                                            }
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(16),
                                      ),
                                    ),
                                    child: (_resultadoEvaluacion?.aprobado ==
                                                true &&
                                            !_esUltimoEscalonDelNivel() &&
                                            _navegando)
                                        ? const SizedBox(
                                            height: 22,
                                            width: 22,
                                            child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2.5,
                                            ),
                                          )
                                        : Text(
                                            _resultadoEvaluacion?.aprobado ==
                                                    true
                                                ? 'Continuar'
                                                : 'Regresar',
                                            style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSinPreguntas(Color colorNivel) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                color: colorNivel.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.quiz,
                size: 42,
                color: colorNivel,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Esta evaluación no tiene preguntas disponibles.',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF8C8474),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTarjetaResultado(Color colorNivel) {
    final r = _resultadoEvaluacion!;
    final colorEstado = r.aprobado ? const Color(0xFF7A9B6C) : const Color(0xFFC0392B);
    final colorFondo = r.aprobado
        ? const Color(0xFF7A9B6C).withValues(alpha: 0.08)
        : const Color(0xFFC0392B).withValues(alpha: 0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colorFondo,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorEstado.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: Icon(
              r.aprobado ? Icons.celebration : Icons.error_outline,
              color: colorEstado,
              size: 28,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.aprobado ? '¡Evaluación aprobada!' : 'No alcanzaste el mínimo',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colorEstado,
                  ),
                ),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w400,
                      color: const Color(0xFF2B2B2B),
                    ),
                    children: [
                      TextSpan(
                        text:
                            '${r.correctas} de ${r.total} correctas — ',
                      ),
                      TextSpan(
                        text: '${r.puntaje.toStringAsFixed(0)}%',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (!r.aprobado)
                        const TextSpan(
                          text: ' (mínimo 70%)',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTarjetaPregunta(
    Map<String, dynamic> pregunta,
    int numero,
    Color colorNivel,
  ) {
    final id = pregunta['id'].toString();
    final seleccionada = _respuestasSeleccionadas[id];
    final correcta = pregunta['respuesta_correcta']?.toString();

    final Color colorFondoBase = Colors.white;
    final Color colorBordeBase = const Color(0xFFE8E4D8);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorFondoBase,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorBordeBase, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: colorNivel.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '$numero',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colorNivel,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  pregunta['pregunta']?.toString() ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2B2B2B),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...['a', 'b', 'c', 'd'].map((letra) {
            final texto = pregunta['opcion_$letra']?.toString() ?? '';
            if (texto.isEmpty) return const SizedBox.shrink();

            final estaSeleccionada = seleccionada == letra;
            final esCorrecta = letra == correcta;
            final Color colorBoton;
            final Color colorFondoBoton;
            final Color colorTextoBoton;
            final bool mostrarIndicador = _evalEnviada;

            if (!mostrarIndicador) {
              colorBoton = estaSeleccionada
                  ? colorNivel
                  : const Color(0xFFD9D5CB);
              colorFondoBoton = estaSeleccionada
                  ? colorNivel.withValues(alpha: 0.08)
                  : Colors.transparent;
              colorTextoBoton = estaSeleccionada
                  ? colorNivel
                  : const Color(0xFF2B2B2B);
            } else {
              if (esCorrecta) {
                colorBoton = const Color(0xFF7A9B6C);
                colorFondoBoton =
                    const Color(0xFF7A9B6C).withValues(alpha: 0.1);
                colorTextoBoton = const Color(0xFF7A9B6C);
              } else if (estaSeleccionada && !esCorrecta) {
                colorBoton = const Color(0xFFC0392B);
                colorFondoBoton =
                    const Color(0xFFC0392B).withValues(alpha: 0.1);
                colorTextoBoton = const Color(0xFFC0392B);
              } else {
                colorBoton = const Color(0xFFD9D5CB);
                colorFondoBoton = Colors.transparent;
                colorTextoBoton = const Color(0xFF8C8474);
              }
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _evalEnviada
                      ? null
                      : () {
                          setState(() {
                            _respuestasSeleccionadas[id] = letra;
                          });
                        },
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: colorFondoBoton,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorBoton, width: 1.3),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: estaSeleccionada ||
                                    (mostrarIndicador && esCorrecta) ||
                                    (mostrarIndicador &&
                                        estaSeleccionada &&
                                        !esCorrecta)
                                ? colorBoton
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(color: colorBoton, width: 1.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            letra.toUpperCase(),
                            style: GoogleFonts.poppins(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: (estaSeleccionada ||
                                      (mostrarIndicador && esCorrecta) ||
                                      (mostrarIndicador &&
                                          estaSeleccionada &&
                                          !esCorrecta))
                                  ? Colors.white
                                  : colorTextoBoton,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            texto,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: colorTextoBoton,
                              height: 1.35,
                            ),
                          ),
                        ),
                        if (mostrarIndicador && esCorrecta)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.check_circle,
                              size: 18,
                              color: Color(0xFF7A9B6C),
                            ),
                          )
                        else if (mostrarIndicador &&
                            estaSeleccionada &&
                            !esCorrecta)
                          const Padding(
                            padding: EdgeInsets.only(left: 6),
                            child: Icon(
                              Icons.cancel,
                              size: 18,
                              color: Color(0xFFC0392B),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          if (_evalEnviada)
            _buildExplicacion(pregunta, colorNivel),
        ],
      ),
    );
  }

  Widget _buildExplicacion(Map<String, dynamic> pregunta, Color colorNivel) {
    final explicacion = pregunta['explicacion']?.toString();
    if (explicacion == null || explicacion.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorNivel.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorNivel.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.info_outline,
                size: 18,
                color: colorNivel,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                explicacion.trim(),
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF2B2B2B),
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _continuarAlSiguienteEscalon() async {
    if (_navegando) return;
    setState(() => _navegando = true);

    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) {
      if (mounted) {
        setState(() => _navegando = false);
      }
      return;
    }

    List<NivelConEstado> arbolRecargado = [];
    try {
      arbolRecargado =
          await _educacionLogic.cargarArbolCompleto(usuarioId);
    } catch (e) {
      debugPrint('ERROR RECARGAR ARBOL SIGUIENTE ESCALON: $e');
    }

    if (!mounted) return;

    final idNivelActual = widget.nivel.id;
    NivelConEstado? nivelRecargado;
    for (final n in arbolRecargado) {
      if (n.id == idNivelActual) {
        nivelRecargado = n;
        break;
      }
    }
    if (nivelRecargado == null) {
      setState(() => _navegando = false);
      return;
    }

    final ordenActualRaw = widget.escalon.escalon['orden'];
    final ordenActual = ordenActualRaw is num
        ? ordenActualRaw.toInt()
        : int.tryParse(ordenActualRaw.toString()) ?? 0;

    EscalonConEstado? siguienteEscalon;
    for (final e in nivelRecargado.escalones) {
      final ordenRaw = e.escalon['orden'];
      final orden = ordenRaw is num
          ? ordenRaw.toInt()
          : int.tryParse(ordenRaw.toString()) ?? 0;
      if (orden == ordenActual + 1) {
        siguienteEscalon = e;
        break;
      }
    }

    if (siguienteEscalon == null) {
      await _manejarFinalizacionExitosaUltimoEscalon();
      return;
    }

    if (!siguienteEscalon.desbloqueado || !siguienteEscalon.disponible) {
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              const Text('El siguiente contenido estará disponible pronto'),
          backgroundColor: const Color(0xFF8C8474),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    final nivelOK = nivelRecargado;
    final escalonOK = siguienteEscalon;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 350),
        reverseTransitionDuration: const Duration(milliseconds: 350),
        transitionsBuilder: (ctx, anim, secAnim, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.12),
              end: Offset.zero,
            ).animate(curved),
            child: FadeTransition(
              opacity: curved,
              child: child,
            ),
          );
        },
        pageBuilder: (ctx, anim, secAnim) => EscalonDetalleScreen(
          escalon: escalonOK,
          nivel: nivelOK,
        ),
      ),
    );
  }

  Widget _buildPantallaLeccion() {
    final colorNivel = colorFromHex(widget.nivel.colorHex);
    final colorClaro = Color.lerp(colorNivel, Colors.white, 0.35) ?? colorNivel;
    final posicion = _obtenerPosicionEscalon();
    final total = widget.nivel.escalones.length;

    final contenidoRaw = widget.escalon.escalon['contenido']?.toString() ?? '';
    final partes = contenidoRaw.split('\n\n');
    final textoPrincipal = partes.isNotEmpty ? partes[0].trim() : '';
    final textoEjemplo = partes.length > 1 ? partes[1].trim() : '';

    final yaCompletado = widget.escalon.completado;

    final hslOscuro = HSLColor.fromColor(colorNivel);
    final colorTextoOscuro = hslOscuro
        .withLightness(hslOscuro.lightness > 0.38 ? 0.38 : hslOscuro.lightness)
        .toColor();

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    SizedBox(
                      height: MediaQuery.of(context).size.height * 0.25,
                      width: double.infinity,
                      child: ClipPath(
                        clipper: _CurvedHeaderClipper(),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [colorNivel, colorClaro],
                            ),
                          ),
                          child: SafeArea(
                            bottom: false,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Align(
                                    alignment: Alignment.topLeft,
                                    child: IconButton(
                                      onPressed: () => Navigator.pop(context),
                                      icon: const Icon(
                                        Icons.arrow_back_ios_new,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const Spacer(flex: 2),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                    ),
                                    child: Text(
                                      widget.escalon.titulo,
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        height: 1.2,
                                      ),
                                    ),
                                  ),
                                  const Spacer(flex: 3),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$posicion de $total',
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF8C8474),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.center,
                                  child: IndicadorProgresoEscalones(
                                    escalones: widget.nivel.escalones,
                                    colorNivel: colorNivel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 28),
                          if (textoPrincipal.isNotEmpty)
                            Text(
                              textoPrincipal,
                              style: GoogleFonts.poppins(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: const Color(0xFF2B2B2B),
                                height: 1.7,
                              ),
                            ),
                          if (textoPrincipal.isNotEmpty && textoEjemplo.isNotEmpty)
                            const SizedBox(height: 24),
                          if (textoEjemplo.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: colorNivel.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorNivel.withValues(alpha: 0.25),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: colorNivel.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.lightbulb_outline,
                                      color: colorNivel,
                                      size: 22,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      textoEjemplo,
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w400,
                                        color: const Color(0xFF2B2B2B),
                                        height: 1.6,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 24),
                          if (yaCompletado)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: colorNivel.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorNivel.withValues(alpha: 0.3),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_circle,
                                    color: colorNivel,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Ya completaste esta sección',
                                    style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorTextoOscuro,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 12),
                decoration: const BoxDecoration(
                  color: Color(0xFFFAF6EA),
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 12,
                      offset: Offset(0, -3),
                    ),
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colorNivel, colorClaro],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: ElevatedButton(
                      onPressed: (_isLoading || _navegando)
                          ? null
                          : (yaCompletado
                              ? _continuarAlSiguienteEscalon
                              : _completarLeccion),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: (!yaCompletado && _isLoading) || _navegando
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  yaCompletado
                                      ? 'Ir al siguiente escalón'
                                      : 'Completar y continuar',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                if (yaCompletado) ...[
                                  const SizedBox(width: 8),
                                  const Icon(
                                    Icons.arrow_forward_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/auth_logic.dart';
import '../logic/educacion_logic.dart';
import '../logic/formato_utils.dart';
import 'escalon_detalle_screen.dart';
import 'widgets/indicador_progreso_escalones.dart';

const double _altoEscalonWidget = 110;
const double _altoIntermedio = 36;
const double _anchoCirculo = 64;
const double _anchoEscalonBox = 140;

class _CaminoNivel extends CustomPainter {
  final List<Offset> centrosCirculos;
  final Color colorNivel;
  final bool nivelBloqueado;

  const _CaminoNivel({
    required this.centrosCirculos,
    required this.colorNivel,
    required this.nivelBloqueado,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (centrosCirculos.length < 2) return;

    final path = Path();
    path.moveTo(centrosCirculos.first.dx, centrosCirculos.first.dy);

    for (int i = 0; i < centrosCirculos.length - 1; i++) {
      final p0 = centrosCirculos[i];
      final p1 = centrosCirculos[i + 1];

      final midY = (p0.dy + p1.dy) / 2;
      final cp1 = Offset(p0.dx, midY);
      final cp2 = Offset(p1.dx, midY);

      path.cubicTo(cp1.dx, cp1.dy, cp2.dx, cp2.dy, p1.dx, p1.dy);
    }

    final paintAsfalto = Paint()
      ..color = nivelBloqueado
          ? const Color(0xFFD9D5CB)
          : colorNivel.withValues(alpha: 0.25)
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    canvas.drawPath(path, paintAsfalto);

    final paintGuion = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final metrics = path.computeMetrics().toList();
    for (final metric in metrics) {
      final total = metric.length;
      double cursor = 0;
      const guion = 14.0;
      const espacio = 10.0;
      while (cursor < total) {
        final finGuion = cursor + guion;
        if (finGuion > total) break;
        final segmento = metric.extractPath(cursor, finGuion);
        canvas.drawPath(segmento, paintGuion);
        cursor = finGuion + espacio;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CaminoNivel oldDelegate) {
    return oldDelegate.colorNivel != colorNivel ||
        oldDelegate.nivelBloqueado != nivelBloqueado ||
        oldDelegate.centrosCirculos.length != centrosCirculos.length ||
        (oldDelegate.centrosCirculos.asMap().entries.any((e) =>
            centrosCirculos[e.key] != e.value));
  }
}

class EducacionFinancieraScreen extends StatefulWidget {
  const EducacionFinancieraScreen({super.key});

  @override
  State<EducacionFinancieraScreen> createState() =>
      _EducacionFinancieraScreenState();
}

class _EducacionFinancieraScreenState extends State<EducacionFinancieraScreen> {
  final _educacionLogic = EducacionLogic();
  final _authLogic = AuthLogic();

  bool _cargando = true;
  List<NivelConEstado> _niveles = [];
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  @override
  void dispose() {
    _scrollOffset.dispose();
    super.dispose();
  }

  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) {
      if (!mounted) return;
      setState(() {
        _niveles = [];
        _cargando = false;
      });
      return;
    }

    List<NivelConEstado> lista = [];
    try {
      lista = await _educacionLogic.cargarArbolCompleto(usuarioId);
    } catch (e) {
      debugPrint('ERROR CARGAR EDUCACION: $e');
    }
    if (!mounted) return;
    setState(() {
      _niveles = lista;
      _cargando = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: Stack(
        children: [
          ValueListenableBuilder<double>(
            valueListenable: _scrollOffset,
            builder: (_, offset, _) {
              final t = (offset.clamp(0, 40) / 40).toDouble();
              return Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: 160,
                child: _buildFranjaCielo(t),
              );
            },
          ),
          SafeArea(
            child: RefreshIndicator(
              color: const Color(0xFF58774B),
              onRefresh: _cargarDatos,
              child: NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollUpdateNotification) {
                    final px = notification.metrics.pixels;
                    if (px != _scrollOffset.value) {
                      _scrollOffset.value = px;
                    }
                  }
                  return false;
                },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: Column(
                    children: [
                      const SizedBox(height: 110),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _cargando
                            ? const Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF58774B),
                                ),
                              )
                            : _niveles.isEmpty
                                ? _buildEstadoVacio()
                                : Column(
                                    children: [
                                      for (final nivel in _niveles)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 28),
                                          child: _buildNivel(context, nivel),
                                        ),
                                    ],
                                  ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFranjaCielo(double progress) {
    final sigma = progress * 15.0;
    final alphaFondo = progress * 0.55;

    final child = Stack(
      children: [
        if (alphaFondo < 1)
          Positioned.fill(
            child: Opacity(
              opacity: 1 - alphaFondo,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFFBEE3F8), Color(0xFFFAF6EA)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
        if (alphaFondo > 0)
          Positioned.fill(
            child: Opacity(
              opacity: alphaFondo,
              child: Container(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),
        Positioned(
          top: 30,
          left: 20,
          child: Container(
            width: 80,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(50),
            ),
          ),
        ),
        Positioned(
          top: 55,
          right: 30,
          child: Container(
            width: 60,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(50),
            ),
          ),
        ),
        Positioned(
          top: 75,
          left: 80,
          child: Container(
            width: 100,
            height: 45,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(50),
            ),
          ),
        ),
        Positioned(
          top: 20,
          right: 100,
          child: Container(
            width: 70,
            height: 35,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(50),
            ),
          ),
        ),
        Center(
          child: Text(
            'Educación Financiera',
            style: GoogleFonts.poppins(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2B2B2B),
            ),
          ),
        ),
      ],
    );

    if (sigma <= 0) {
      return child;
    }

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }

  Widget _buildEstadoVacio() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF58774B).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.school,
                size: 56,
                color: Color(0xFF58774B),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No hay contenidos disponibles',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B2B2B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Desliza hacia abajo para recargar.',
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

  Widget _buildNivel(BuildContext context, NivelConEstado nivel) {
    final colorNivel = colorFromHex(nivel.colorHex);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorNivel.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorNivel, width: 1.5),
      ),
      child: Column(
        children: [
          if (!nivel.desbloqueado)
            _buildEncabezadoBloqueado(nivel, colorNivel)
          else ...[
            _buildEncabezadoDesbloqueado(nivel, colorNivel),
            const SizedBox(height: 20),
            _buildEscalonesDeNivel(context, nivel, colorNivel),
          ],
        ],
      ),
    );
  }

  Widget _buildEncabezadoBloqueado(NivelConEstado nivel, Color colorNivel) {
    return Column(
      children: [
        const Icon(
          Icons.lock,
          size: 32,
          color: Color(0xFF8C8474),
        ),
        const SizedBox(height: 12),
        Text(
          nivel.nombre,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF8C8474),
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Completa el nivel anterior para desbloquear',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w400,
            color: const Color(0xFF8C8474),
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildEncabezadoDesbloqueado(NivelConEstado nivel, Color colorNivel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          nivel.nombre,
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: colorNivel,
          ),
        ),
        const SizedBox(height: 12),
        IndicadorProgresoEscalones(
          escalones: nivel.escalones,
          colorNivel: colorNivel,
        ),
      ],
    );
  }

  Widget _buildEscalonesDeNivel(
    BuildContext context,
    NivelConEstado nivel,
    Color colorNivel,
  ) {
    final escalones = nivel.escalones;
    if (escalones.isEmpty) return const SizedBox.shrink();

    final total = escalones.length;
    final altoStack =
        total * _altoEscalonWidget + (total - 1) * _altoIntermedio;

    return LayoutBuilder(
      builder: (context, constraints) {
        final anchoBloque = constraints.maxWidth;
        final margenLado = anchoBloque * 0.15;

        final centrosCirculos = <Offset>[];
        for (int i = 0; i < total; i++) {
          final yWidgetTop = i * (_altoEscalonWidget + _altoIntermedio);
          final yCentroCirculo = yWidgetTop + (_anchoCirculo / 2);
          final centroBox = _anchoEscalonBox / 2;
          final xCirculo = i % 2 == 0
              ? margenLado + centroBox
              : (anchoBloque - margenLado) - centroBox;
          centrosCirculos.add(Offset(xCirculo, yCentroCirculo));
        }

        return SizedBox(
          width: anchoBloque,
          height: altoStack,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _CaminoNivel(
                    centrosCirculos: centrosCirculos,
                    colorNivel: colorNivel,
                    nivelBloqueado: !nivel.desbloqueado,
                  ),
                ),
              ),
              for (int i = 0; i < total; i++)
                Positioned(
                  top: i * (_altoEscalonWidget + _altoIntermedio),
                  left: i % 2 == 0 ? margenLado : null,
                  right: i % 2 == 1 ? margenLado : null,
                  child: _buildEscalon(
                    context,
                    escalones[i],
                    nivel,
                    colorNivel,
                    i,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEscalon(
    BuildContext context,
    EscalonConEstado escalon,
    NivelConEstado nivel,
    Color colorNivel,
    int indiceEnNivel,
  ) {
    final tocable = escalon.desbloqueado && escalon.disponible;

    IconData icono;
    Color colorIcono;
    Color fondoCirculo;
    Color? colorBorde;
    double grosorBorde = 0;

    if (escalon.completado) {
      icono = escalon.esEvaluacion ? Icons.menu_book : Icons.check;
      colorIcono = Colors.white;
      fondoCirculo = colorNivel;
    } else if (escalon.desbloqueado && escalon.disponible) {
      if (escalon.esEvaluacion) {
        icono = Icons.menu_book;
      } else {
        switch (indiceEnNivel % 3) {
          case 0:
            icono = Icons.savings;
            break;
          case 1:
            icono = Icons.payments;
            break;
          default:
            icono = Icons.inventory_2;
        }
      }
      colorIcono = colorNivel;
      fondoCirculo = Colors.white;
      colorBorde = colorNivel;
      grosorBorde = 2.5;
    } else if (escalon.desbloqueado && !escalon.disponible) {
      icono = Icons.construction;
      colorIcono = const Color(0xFF8C8474);
      fondoCirculo = const Color(0xFFECECEC);
    } else {
      icono = Icons.lock;
      colorIcono = const Color(0xFF8C8474);
      fondoCirculo = const Color(0xFFECECEC);
    }

    final colorTitulo =
        (escalon.desbloqueado && escalon.disponible) || escalon.completado
            ? const Color(0xFF2B2B2B)
            : const Color(0xFF8C8474);

    return GestureDetector(
      onTap: tocable
          ? () async {
              final result = await Navigator.push<bool>(
                context,
                MaterialPageRoute(
                  builder: (_) => EscalonDetalleScreen(
                    escalon: escalon,
                    nivel: nivel,
                  ),
                ),
              );
              if (result == true) {
                _cargarDatos();
              }
            }
          : null,
      child: SizedBox(
        width: _anchoEscalonBox,
        height: _altoEscalonWidget,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _anchoCirculo,
              height: _anchoCirculo,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: fondoCirculo,
                border: colorBorde != null
                    ? Border.all(color: colorBorde, width: grosorBorde)
                    : null,
              ),
              child: Icon(
                icono,
                size: 30,
                color: colorIcono,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                escalon.titulo,
                maxLines: 3,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: colorTitulo,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

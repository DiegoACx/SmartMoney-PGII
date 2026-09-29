import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/auth_logic.dart';
import '../logic/educacion_logic.dart';
import '../logic/formato_utils.dart';
import 'escalon_detalle_screen.dart';

class _LineaConectora extends CustomPainter {
  final Color color;
  final bool izquierdaADerecha;

  const _LineaConectora({
    required this.color,
    required this.izquierdaADerecha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final inicio = izquierdaADerecha
        ? const Offset(0, 0)
        : Offset(size.width, 0);
    final fin = izquierdaADerecha
        ? Offset(size.width, size.height)
        : Offset(0, size.height);
    canvas.drawLine(inicio, fin, paint);
  }

  @override
  bool shouldRepaint(covariant _LineaConectora oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.izquierdaADerecha != izquierdaADerecha;
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

  @override
  void initState() {
    super.initState();
    _cargarDatos();
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
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 160,
            child: _buildFranjaCielo(),
          ),
          SafeArea(
            child: RefreshIndicator(
              color: const Color(0xFF58774B),
              onRefresh: _cargarDatos,
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
        ],
      ),
    );
  }

  Widget _buildFranjaCielo() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFBEE3F8), Color(0xFFFAF6EA)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
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
    final progreso = nivel.porcentajeProgreso;
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
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progreso / 100,
                  backgroundColor: colorNivel.withValues(alpha: 0.2),
                  color: colorNivel,
                  minHeight: 8,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${progreso.toStringAsFixed(0)}% completado',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8C8474),
              ),
            ),
          ],
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

    final anchoPantalla = MediaQuery.of(context).size.width;
    final margenLado = anchoPantalla * 0.15;

    return Column(
      children: [
        for (int i = 0; i < escalones.length; i++) ...[
          Align(
            alignment: i % 2 == 0
                ? Alignment.centerLeft
                : Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(
                left: i % 2 == 0 ? margenLado : 0,
                right: i % 2 == 1 ? margenLado : 0,
              ),
              child: _buildEscalon(
                context,
                escalones[i],
                nivel,
                colorNivel,
                i,
              ),
            ),
          ),
          if (i < escalones.length - 1)
            SizedBox(
              height: 36,
              width: double.infinity,
              child: CustomPaint(
                painter: _LineaConectora(
                  color: (escalones[i].desbloqueado &&
                          escalones[i + 1].desbloqueado)
                      ? colorNivel
                      : const Color(0xFFD9D5CB),
                  izquierdaADerecha: i % 2 == 0,
                ),
              ),
            ),
        ],
      ],
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
        width: 120,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
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
            Text(
              escalon.titulo,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorTitulo,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

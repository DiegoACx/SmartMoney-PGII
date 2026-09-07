import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/auth_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/transacciones_logic.dart';

/// Clipper curvo para el header decorativo superior, idéntico al usado en
/// las pantallas de autenticación.
class _CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 40);
    final controlPoint = Offset(size.width / 2, size.height + 20);
    final endPoint = Offset(size.width, size.height - 40);
    path.quadraticBezierTo(
        controlPoint.dx, controlPoint.dy, endPoint.dx, endPoint.dy);
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Dashboard principal: selector de periodo + 3 tarjetas de totales
/// (Ingresos / Egresos / Diferencia) + placeholder de gráficas.
///
/// La carga de transacciones se hace **una sola vez** con
/// `obtenerTodasLasTransacciones`; al cambiar de periodo solo se recalcula
/// en memoria (`calcularTotalesPeriodo`) sin volver a consultar Supabase.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _transaccionesLogic = TransaccionesLogic();
  final _authLogic = AuthLogic();

  bool _cargando = true;
  List<Map<String, dynamic>> _transacciones = [];
  PeriodoDashboard _periodo = PeriodoDashboard.mesActual;

  // ===== Label visible por periodo (para el selector) =====
  static const Map<PeriodoDashboard, String> _labelsPeriodo = {
    PeriodoDashboard.mesActual: 'Mes actual',
    PeriodoDashboard.mesPasado: 'Mes pasado',
    PeriodoDashboard.ultimos3Meses: 'Últimos 3 meses',
    PeriodoDashboard.ultimos5Meses: 'Últimos 5 meses',
    PeriodoDashboard.anual: 'Anual',
  };

  @override
  void initState() {
    super.initState();
    cargarTransacciones();
  }

  // ===== Carga inicial y recarga manual/pull-to-refresh =====
  Future<void> cargarTransacciones() async {
    setState(() => _cargando = true);
    try {
      final usuarioId = _authLogic.obtenerUsuarioId();
      if (usuarioId == null) {
        if (!mounted) return;
        setState(() {
          _transacciones = [];
          _cargando = false;
        });
        return;
      }
      final data =
          await _transaccionesLogic.obtenerTodasLasTransacciones(usuarioId);
      if (!mounted) return;
      setState(() {
        _transacciones = data;
        _cargando = false;
      });
    } catch (e) {
      debugPrint('ERROR AL CARGAR TRANSACCIONES: $e');
      if (!mounted) return;
      setState(() {
        _transacciones = [];
        _cargando = false;
      });
    }
  }

  // ===== Cerrar sesión =====
  void _cerrarSesion() async {
    await _authLogic.cerrarSesion();
    // No hace falta navegar manualmente: AuthGate escucha el cambio de
    // sesión (StreamBuilder) y muestra LoginScreen automáticamente al
    // detectar el logout.
  }

  @override
  Widget build(BuildContext context) {
    final totales =
        _transaccionesLogic.calcularTotalesPeriodo(_transacciones, _periodo);
    final signoDif = totales.diferencia >= 0 ? '+' : '-';
    final colorDif =
        totales.diferencia >= 0 ? const Color(0xFF58774B) : const Color(0xFFC0392B);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6EA),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout, size: 18, color: Color(0xFFC0392B)),
            label: Text(
              'Cerrar sesión',
              style: GoogleFonts.poppins(
                color: const Color(0xFFC0392B),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF58774B),
          onRefresh: cargarTransacciones,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ===== Header decorativo =====
                ClipPath(
                  clipper: _CurvedHeaderClipper(),
                  child: Container(
                    height: 140,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF58774B), Color(0xFF7A9B6C)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        'SmartMoney',
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // ===== Selector de periodo =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: PeriodoDashboard.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final p = PeriodoDashboard.values[i];
                        final seleccionado = p == _periodo;
                        return GestureDetector(
                          onTap: () => setState(() => _periodo = p),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              gradient: seleccionado
                                  ? const LinearGradient(colors: [
                                      Color(0xFF58774B),
                                      Color(0xFF7A9B6C),
                                    ])
                                  : null,
                              color: seleccionado ? null : Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: seleccionado
                                  ? null
                                  : [
                                      const BoxShadow(
                                        color: Color(0x0D000000),
                                        blurRadius: 4,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                              border: Border.all(
                                color: seleccionado
                                    ? Colors.transparent
                                    : const Color(0xFFECECEC),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              _labelsPeriodo[p]!,
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: seleccionado
                                    ? Colors.white
                                    : const Color(0xFF2B2B2B),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                if (_cargando)
                  const Padding(
                    padding: EdgeInsets.only(top: 48),
                    child: Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF58774B),
                      ),
                    ),
                  )
                else ...[
                  // ===== Tarjetas de totales =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _TarjetaTotal(
                      titulo: 'Ingresos',
                      monto: totales.totalIngresos,
                      signo: '+',
                      color: const Color(0xFF58774B),
                      icon: Icons.arrow_upward_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _TarjetaTotal(
                      titulo: 'Egresos',
                      monto: totales.totalEgresos,
                      signo: '-',
                      color: const Color(0xFFC0392B),
                      icon: Icons.arrow_downward_rounded,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _TarjetaTotal(
                      titulo: 'Diferencia',
                      monto: totales.diferencia.abs(),
                      signo: signoDif,
                      color: colorDif,
                      icon: totales.diferencia >= 0
                          ? Icons.trending_up_rounded
                          : Icons.trending_down_rounded,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // ===== Placeholder gráficas =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFE5E5E5),
                          width: 1.2,
                          style: BorderStyle.solid,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x0A000000),
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 84,
                            height: 84,
                            decoration: BoxDecoration(
                              color:
                                  const Color(0xFF58774B).withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.bar_chart_rounded,
                              color: Color(0xFF58774B),
                              size: 42,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Próximamente: gráficas de tus finanzas',
                            style: GoogleFonts.poppins(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFF2B2B2B),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Visualiza tus gastos e ingresos por categoría.',
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF8C8474),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ===== Widget auxiliar: tarjeta de totales =====
class _TarjetaTotal extends StatelessWidget {
  final String titulo;
  final double monto;
  final String signo;
  final Color color;
  final IconData icon;

  const _TarjetaTotal({
    required this.titulo,
    required this.monto,
    required this.signo,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      color: Colors.white,
      shadowColor: const Color(0x0D000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: const Color(0xFF8C8474),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$signo ${FormatoUtils.moneda.format(monto)}',
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

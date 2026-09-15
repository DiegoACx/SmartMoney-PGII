import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/auth_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/transacciones_logic.dart';

const List<Color> _paletteCategorias = [
  Color(0xFF58774B),
  Color(0xFF7A9B6C),
  Color(0xFFC0392B),
  Color(0xFFE0A458),
  Color(0xFF8C8474),
  Color(0xFF4C6B5F),
  Color(0xFFB98B73),
  Color(0xFF6B8E76),
  Color(0xFFC9C2B0),
  Color(0xFFD9B48F),
];

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
  List<MapEntry<String, double>> _categoriasEnAlerta = [];
  PeriodoDashboard _periodo = PeriodoDashboard.mesActual;
  String _modoFlujoCaja = 'acumulado';

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
      final alertas = _transaccionesLogic.calcularPorcentajeGastoPorCategoria(
        data,
        DateTime.now(),
      );
      final categoriasEnAlerta = alertas.entries
          .where((e) => e.value >= 40)
          .toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      if (!mounted) return;
      setState(() {
        _transacciones = data;
        _categoriasEnAlerta = categoriasEnAlerta;
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

                // ===== Tarjeta de alerta de gasto excesivo =====
                if (_categoriasEnAlerta.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC0392B).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color:
                              const Color(0xFFC0392B).withValues(alpha: 0.30),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_outlined,
                            color: Color(0xFFC0392B),
                            size: 22,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Builder(
                              builder: (_) {
                                final children = <Widget>[];
                                final max = _categoriasEnAlerta.length > 2
                                    ? 2
                                    : _categoriasEnAlerta.length;
                                for (int i = 0; i < max; i++) {
                                  children.add(
                                    Text(
                                      "Tu gasto en '${_categoriasEnAlerta[i].key}' representa el ${_categoriasEnAlerta[i].value.toStringAsFixed(0)}% de tu ingreso este mes",
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: const Color(0xFF2B2B2B),
                                      ),
                                    ),
                                  );
                                  final esUltimaVisible = i == max - 1;
                                  final hayMas =
                                      _categoriasEnAlerta.length > 2;
                                  if (!esUltimaVisible || hayMas) {
                                    children.add(const SizedBox(height: 6));
                                  }
                                }
                                if (_categoriasEnAlerta.length > 2) {
                                  children.add(
                                    Text(
                                      '+ ${_categoriasEnAlerta.length - 2} categoría(s) más',
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        color: const Color(0xFF8C8474),
                                      ),
                                    ),
                                  );
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: children,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_categoriasEnAlerta.isNotEmpty)
                  const SizedBox(height: 16),

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

                  // ===== TARJETA 1: Gráfico de barras (Ingresos vs Egresos) =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildTarjetaBarChart(_transacciones),
                  ),
                  const SizedBox(height: 16),

                  // ===== TARJETA 2: Gráfico de torta (Gastos por categoría) =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildTarjetaPieChart(_transacciones),
                  ),
                  const SizedBox(height: 16),

                  // ===== TARJETA 3: Gráfico de línea (Flujo de caja) =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildTarjetaLineChart(_transacciones),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ================================================================
  // TARJETA 1 — Gráfico de barras: Ingresos vs Egresos (6 meses)
  // ================================================================
  Widget _buildTarjetaBarChart(List<Map<String, dynamic>> transacciones) {
    final totalesMensuales = _transaccionesLogic.obtenerTotalesMensuales(
      transacciones,
      meses: 6,
    );
    final hayDatos = totalesMensuales.any(
      (m) => (m['ingresos'] as double) > 0 || (m['egresos'] as double) > 0,
    );

    return _buildTarjetaGraficaBase(
      titulo: 'Ingresos vs Egresos',
      subtitulo: 'Últimos 6 meses',
      altura: 240,
      child: hayDatos
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF58774B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Ingresos',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFF2B2B2B),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFFC0392B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Egresos',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: const Color(0xFF2B2B2B),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8, right: 8),
                    child: BarChart(
                      BarChartData(
                        alignment: BarChartAlignment.spaceAround,
                        maxY: _maxYParaBars(totalesMensuales),
                        groupsSpace: 12,
                        barTouchData: BarTouchData(enabled: false),
                        titlesData: FlTitlesData(
                          show: true,
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          leftTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 24,
                              getTitlesWidget: (value, meta) {
                                final idx = value.toInt();
                                if (idx < 0 || idx >= totalesMensuales.length) {
                                  return const SizedBox.shrink();
                                }
                                final mes = totalesMensuales[idx]['mes'] as DateTime;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Text(
                                    _mesAbrev(mes),
                                    style: GoogleFonts.poppins(
                                      fontSize: 10,
                                      color: const Color(0xFF8C8474),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: const FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        barGroups: [
                          for (int i = 0; i < totalesMensuales.length; i++)
                            BarChartGroupData(
                              x: i,
                              barsSpace: 4,
                              barRods: [
                                BarChartRodData(
                                  toY: totalesMensuales[i]['ingresos'] as double,
                                  color: const Color(0xFF58774B),
                                  width: 10,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                BarChartRodData(
                                  toY: totalesMensuales[i]['egresos'] as double,
                                  color: const Color(0xFFC0392B),
                                  width: 10,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            )
          : _buildEstadoVacio(
              'Aún no hay suficientes datos para esta gráfica',
            ),
    );
  }

  double _maxYParaBars(List<Map<String, dynamic>> totalesMensuales) {
    double max = 0;
    for (final m in totalesMensuales) {
      if ((m['ingresos'] as double) > max) max = m['ingresos'] as double;
      if ((m['egresos'] as double) > max) max = m['egresos'] as double;
    }
    if (max == 0) return 10;
    return max * 1.15;
  }

  // ================================================================
  // TARJETA 2 — Gráfico de torta: Distribución de gastos por categoría
  // ================================================================
  Widget _buildTarjetaPieChart(List<Map<String, dynamic>> transacciones) {
    final distribucion =
        _transaccionesLogic.obtenerDistribucionGastosPorCategoria(
      transacciones,
      DateTime.now(),
    );
    final entradas = distribucion.entries.toList();

    return _buildTarjetaGraficaBase(
      titulo: 'Gastos por categoría',
      subtitulo: 'Mes actual',
      altura: 320,
      child: entradas.isNotEmpty
          ? Column(
              children: [
                SizedBox(
                  height: 180,
                  child: PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 32,
                      sections: [
                        for (int i = 0; i < entradas.length; i++)
                          PieChartSectionData(
                            value: entradas[i].value,
                            color: _paletteCategorias[
                                i % _paletteCategorias.length],
                            radius: 48,
                            title: '',
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 6,
                    children: [
                      for (int i = 0; i < entradas.length; i++)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: _paletteCategorias[
                                    i % _paletteCategorias.length],
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text(
                              entradas[i].key,
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: const Color(0xFF2B2B2B),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              FormatoUtils.moneda.format(entradas[i].value),
                              style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: const Color(0xFF8C8474),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            )
          : _buildEstadoVacio(
              'Aún no tienes gastos registrados este mes',
            ),
    );
  }

  // ================================================================
  // TARJETA 3 — Gráfico de línea: Flujo de caja + toggle
  // ================================================================
  Widget _buildTarjetaLineChart(List<Map<String, dynamic>> transacciones) {
    final flujo = _transaccionesLogic.obtenerFlujoCajaMensual(
      transacciones,
      meses: 6,
    );
    final hayDatos = flujo.any((m) {
      final v = _modoFlujoCaja == 'acumulado'
          ? (m['acumulado'] as double)
          : (m['neto'] as double);
      return v != 0;
    });

    return Card(
      elevation: 1,
      color: Colors.white,
      shadowColor: const Color(0x0D000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Flujo de caja',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF2B2B2B),
                        ),
                      ),
                      Text(
                        'Últimos 6 meses',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: const Color(0xFF8C8474),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildToggleFlujo(),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 220,
              child: hayDatos
                  ? Padding(
                      padding: const EdgeInsets.only(right: 8, top: 8),
                      child: LineChart(
                        LineChartData(
                          gridData: FlGridData(
                            show: true,
                            drawVerticalLine: false,
                            horizontalInterval: null,
                            getDrawingHorizontalLine: (_) => const FlLine(
                              color: Color(0x1A8C8474),
                              strokeWidth: 0.8,
                            ),
                          ),
                          titlesData: FlTitlesData(
                            show: true,
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            leftTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                getTitlesWidget: (value, meta) {
                                  final idx = value.toInt();
                                  if (idx < 0 || idx >= flujo.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final mes = flujo[idx]['mes'] as DateTime;
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 6),
                                    child: Text(
                                      _mesAbrev(mes),
                                      style: GoogleFonts.poppins(
                                        fontSize: 10,
                                        color: const Color(0xFF8C8474),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          lineTouchData: LineTouchData(
                            handleBuiltInTouches: true,
                            touchTooltipData: LineTouchTooltipData(
                              getTooltipColor: (_) => const Color(0xFF2B2B2B),
                              tooltipBorderRadius: BorderRadius.circular(8),
                              fitInsideHorizontally: true,
                              fitInsideVertically: true,
                              getTooltipItems: (spots) {
                                return spots.map((spot) {
                                  final valor = FormatoUtils.moneda.format(spot.y);
                                  return LineTooltipItem(
                                    valor,
                                    GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  );
                                }).toList();
                              },
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (int i = 0; i < flujo.length; i++)
                                  FlSpot(
                                    i.toDouble(),
                                    (_modoFlujoCaja == 'acumulado'
                                        ? flujo[i]['acumulado'] as double
                                        : flujo[i]['neto'] as double),
                                  ),
                              ],
                              isCurved: true,
                              curveSmoothness: 0.2,
                              color: const Color(0xFF58774B),
                              barWidth: 2.5,
                              dotData: FlDotData(show: true),
                              belowBarData: BarAreaData(
                                show: true,
                                color:
                                    const Color(0xFF58774B).withValues(alpha: 0.08),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : _buildEstadoVacio(
                      'Aún no hay suficientes datos para esta gráfica',
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleFlujo() {
    final activo = _modoFlujoCaja;
    Widget boton(String valor, String texto) {
      final seleccionado = activo == valor;
      return GestureDetector(
        onTap: () => setState(() => _modoFlujoCaja = valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            gradient: seleccionado
                ? const LinearGradient(colors: [
                    Color(0xFF58774B),
                    Color(0xFF7A9B6C),
                  ])
                : null,
            color: seleccionado ? null : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: seleccionado
                  ? Colors.transparent
                  : const Color(0xFFECECEC),
            ),
            boxShadow: seleccionado
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x0D000000),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ],
          ),
          child: Text(
            texto,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: seleccionado ? Colors.white : const Color(0xFF8C8474),
            ),
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        boton('acumulado', 'Acumulado'),
        const SizedBox(width: 6),
        boton('porPeriodo', 'Por mes'),
      ],
    );
  }

  // ================================================================
  // Helpers comunes
  // ================================================================
  Widget _buildTarjetaGraficaBase({
    required String titulo,
    required String subtitulo,
    required double altura,
    required Widget child,
  }) {
    return Card(
      elevation: 1,
      color: Colors.white,
      shadowColor: const Color(0x0D000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              titulo,
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B2B2B),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitulo,
              style: GoogleFonts.poppins(
                fontSize: 12,
                color: const Color(0xFF8C8474),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(height: altura, child: child),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoVacio(String texto) {
    return Center(
      child: Text(
        texto,
        style: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w400,
          color: const Color(0xFF8C8474),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  String _mesAbrev(DateTime mes) {
    final s = DateFormat('MMM', 'es').format(mes);
    return s[0].toUpperCase() + s.substring(1).replaceAll('.', '');
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

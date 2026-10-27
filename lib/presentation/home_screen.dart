import 'dart:async';

import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/auth_logic.dart';
import '../logic/educacion_logic.dart';
import '../logic/flujo_caja_view_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/metas_logic.dart';
import '../logic/transacciones_logic.dart';
import 'educacion_financiera_screen.dart';
import 'registro_meta_screen.dart';
import 'utils/abrir_leccion.dart';
import 'widgets/boton_asistente.dart';
import 'widgets/indicador_progreso_escalones.dart';
import 'widgets/tarjeta_recomendaciones.dart';

/// Texto mostrado en lugar de una gráfica cuando no hay datos que dibujar.
const String _textoSinDatosGrafica = 'Aún no hay movimientos para graficar';

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
  const HomeScreen({super.key, this.onCambiarPestana});

  /// Cambia de pestaña en el `MainShell` (2 = Educación, 4 = Metas).
  final ValueChanged<int>? onCambiarPestana;

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _transaccionesLogic = TransaccionesLogic();
  final _authLogic = AuthLogic();
  final _metasLogic = MetasLogic();
  final _educacionLogic = EducacionLogic();
  final _recomendacionesKey = GlobalKey<TarjetaRecomendacionesState>();

  bool _cargando = true;
  List<Map<String, dynamic>> _transacciones = [];
  List<MapEntry<String, double>> _categoriasEnAlerta = [];
  PeriodoDashboard _periodo = PeriodoDashboard.mesActual;
  String _modoFlujoCaja = 'acumulado';

  List<Map<String, dynamic>> _metas = [];
  final _metasPageController = PageController();
  int _metaActualIndex = 0;
  Timer? _metaAutoTimer;
  Timer? _metaResumeTimer;

  List<NivelConEstado> _nivelesEducacion = [];

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

  @override
  void dispose() {
    _metaAutoTimer?.cancel();
    _metaResumeTimer?.cancel();
    _metasPageController.dispose();
    super.dispose();
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

    _cargarMetas();
    _cargarEducacion();
  }

  /// Abre la lección sugerida por el motor; si no se puede abrir directamente
  /// (no está desbloqueada o no está disponible), va a la pestaña de Educación.
  void _verLeccionDesdeRecomendacion(String escalonId) {
    abrirLeccion(
      context: context,
      escalonId: escalonId,
      niveles: _nivelesEducacion,
      onCambiarPestana: widget.onCambiarPestana,
    );
  }

  Future<void> _cargarMetas() async {
    try {
      final usuarioId = _authLogic.obtenerUsuarioId();
      if (usuarioId == null) return;
      final lista = await _metasLogic.obtenerMetas(usuarioId);
      if (!mounted) return;

      final necesitaReset = _metaActualIndex >= lista.length;

      setState(() {
        _metas = lista;
        _metaActualIndex = necesitaReset ? 0 : _metaActualIndex;
      });

      if (necesitaReset && _metasPageController.hasClients) {
        _metasPageController.jumpToPage(0);
      }

      _iniciarAutoAvanceMetas();
    } catch (e) {
      debugPrint('ERROR AL CARGAR METAS EN DASHBOARD: $e');
    }
  }

  Future<void> _cargarEducacion() async {
    try {
      final usuarioId = _authLogic.obtenerUsuarioId();
      if (usuarioId == null) return;
      final lista = await _educacionLogic.cargarArbolCompleto(usuarioId);
      if (!mounted) return;
      setState(() {
        _nivelesEducacion = lista;
      });
    } catch (e) {
      debugPrint('ERROR AL CARGAR EDUCACION EN DASHBOARD: $e');
    }
  }

  NivelConEstado? _nivelActual() {
    for (final nivel in _nivelesEducacion) {
      if (nivel.desbloqueado && nivel.porcentajeProgreso < 100) {
        return nivel;
      }
    }
    return null;
  }

  void _iniciarAutoAvanceMetas() {
    _metaAutoTimer?.cancel();
    _metaResumeTimer?.cancel();
    if (_metas.length <= 1) return;

    _metaAutoTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final siguiente = (_metaActualIndex + 1) % _metas.length;
      _metasPageController.animateToPage(
        siguiente,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
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
      floatingActionButton: fabAsistente(
        heroTag: 'fab_asistente_inicio',
        onCambiarPestana: widget.onCambiarPestana,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF58774B),
          onRefresh: () async {
            await cargarTransacciones();
            await _recomendacionesKey.currentState?.recargar(forzar: true);
          },
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            // Espacio extra para que el FAB del asistente no tape el último
            // contenido (etiquetas del eje X, última tarjeta, etc.).
            padding: const EdgeInsets.only(bottom: 88),
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

                // ===== Recomendaciones del motor de IA =====
                TarjetaRecomendaciones(
                  key: _recomendacionesKey,
                  onVerLeccion: _verLeccionDesdeRecomendacion,
                  onVerMeta: () => widget.onCambiarPestana?.call(4),
                ),

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
                  const SizedBox(height: 16),

                  // ===== TARJETA 4: Resumen de metas de ahorro =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildTarjetaMetas(),
                  ),
                  const SizedBox(height: 16),

                  // ===== TARJETA 5: Progreso de educación financiera =====
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: _buildTarjetaEducacion(),
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
          : _buildEstadoVacio(_textoSinDatosGrafica),
    );
  }

  double _maxYParaBars(List<Map<String, dynamic>> totalesMensuales) {
    double max = 0;
    for (final m in totalesMensuales) {
      final ingresos = m['ingresos'] as double;
      final egresos = m['egresos'] as double;
      if (ingresos > max) max = ingresos;
      if (egresos > max) max = egresos;
    }
    return _maxYValido(max) * 1.15;
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
    final total = entradas.fold<double>(0, (acc, e) => acc + e.value);
    final hayDatos = entradas.isNotEmpty && total.isFinite && total > 0;

    return _buildTarjetaGraficaBase(
      titulo: 'Gastos por categoría',
      subtitulo: 'Mes actual',
      child: hayDatos
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
                const SizedBox(height: 12),
                _buildLeyendaTorta(entradas),
              ],
            )
          : _buildEstadoVacio(_textoSinDatosGrafica),
    );
  }

  /// Leyenda de la torta. En pantallas angostas (menos de 400 px) usa una sola
  /// columna con el nombre completo y el monto alineado a la derecha; en
  /// pantallas anchas mantiene las dos columnas. Los ítems van de mayor a menor
  /// monto y muestran su porcentaje sobre el total.
  Widget _buildLeyendaTorta(List<MapEntry<String, double>> entradas) {
    final total = entradas.fold<double>(0, (acc, e) => acc + e.value);
    // Se ordena de mayor a menor monto conservando el índice original, para que
    // el color del punto siga coincidiendo con su porción de la torta.
    final items = <({String nombre, double valor, int colorIndex})>[
      for (int i = 0; i < entradas.length; i++)
        (nombre: entradas[i].key, valor: entradas[i].value, colorIndex: i),
    ]..sort((a, b) => b.valor.compareTo(a.valor));

    return LayoutBuilder(
      builder: (context, constraints) {
        // Angosto: una sola columna, así el nombre dispone de todo el ancho.
        if (constraints.maxWidth < 400) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 8),
                _buildItemLeyendaTorta(items[i], total),
              ],
            ],
          );
        }

        // Ancho: dos columnas con el ancho calculado para no desbordar.
        const double separacionHorizontal = 12;
        final anchoItem =
            (constraints.maxWidth - separacionHorizontal) / 2;
        return Wrap(
          spacing: separacionHorizontal,
          runSpacing: 8,
          children: [
            for (final item in items)
              SizedBox(
                width: anchoItem,
                child: _buildItemLeyendaTorta(item, total),
              ),
          ],
        );
      },
    );
  }

  /// Fila de la leyenda: punto de color, nombre (con ellipsis solo si aun así
  /// no cabe) y monto con su porcentaje alineado a la derecha.
  Widget _buildItemLeyendaTorta(
    ({String nombre, double valor, int colorIndex}) item,
    double total,
  ) {
    final porcentaje = total > 0 ? (item.valor / total * 100).round() : 0;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: _paletteCategorias[
                item.colorIndex % _paletteCategorias.length],
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            item.nombre,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: const Color(0xFF2B2B2B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '${FormatoUtils.moneda.format(item.valor)} · $porcentaje %',
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: const Color(0xFF8C8474),
          ),
        ),
      ],
    );
  }

  // ================================================================
  // TARJETA 3 — Flujo de caja: línea "Acumulado" / barras "Por mes"
  // ================================================================
  Widget _buildTarjetaLineChart(List<Map<String, dynamic>> transacciones) {
    final flujo = _transaccionesLogic.obtenerFlujoCajaMensual(
      transacciones,
      meses: 6,
    );
    final esAcumulado = _modoFlujoCaja == 'acumulado';
    final datos = FlujoCajaViewLogic.preparar(
      flujo: flujo,
      acumulado: esAcumulado,
    );

    return Card(
      elevation: 1,
      color: Colors.white,
      shadowColor: const Color(0x0D000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 18, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildEncabezadoFlujo(datos, esAcumulado),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 224,
              child: datos.hayDatos
                  ? AnimatedSwitcher(
                      duration: const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      child: KeyedSubtree(
                        key: ValueKey(_modoFlujoCaja),
                        child: esAcumulado
                            ? _buildGraficaAcumulado(datos)
                            : _buildGraficaPorMes(datos),
                      ),
                    )
                  : _buildEstadoVacio(_textoSinDatosGrafica),
            ),
          ],
        ),
      ),
    );
  }

  /// Vista "Acumulado": línea con área sombreada suave, sin sobrepasar los
  /// puntos (preventCurveOverShooting), para no inventar subidas ni bajadas.
  Widget _buildGraficaAcumulado(DatosGraficaFlujo datos) {
    return LineChart(
      LineChartData(
        minY: datos.minY,
        maxY: datos.maxY,
        gridData: _cuadriculaFlujo(datos),
        titlesData: _titulosFlujo(datos),
        extraLinesData: _lineaCeroFlujo(),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2B2B2B),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  _textoTooltipFlujo(datos, spot.x.round(), spot.y),
                  GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < datos.valores.length; i++)
                FlSpot(i.toDouble(), datos.valores[i]),
            ],
            isCurved: true,
            curveSmoothness: 0.25,
            preventCurveOverShooting: true,
            color: FlujoCajaViewLogic.colorPositivo,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3.2,
                color: Colors.white,
                strokeWidth: 2,
                strokeColor: FlujoCajaViewLogic.colorPositivo,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  FlujoCajaViewLogic.colorPositivo.withValues(alpha: 0.22),
                  FlujoCajaViewLogic.colorPositivo.withValues(alpha: 0.02),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Vista "Por mes": barras verdes si al mes le sobró y rojas si le faltó.
  Widget _buildGraficaPorMes(DatosGraficaFlujo datos) {
    return BarChart(
      BarChartData(
        minY: datos.minY,
        maxY: datos.maxY,
        alignment: BarChartAlignment.spaceEvenly,
        gridData: _cuadriculaFlujo(datos),
        titlesData: _titulosFlujo(datos),
        extraLinesData: _lineaCeroFlujo(),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF2B2B2B),
            tooltipBorderRadius: BorderRadius.circular(8),
            tooltipPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            maxContentWidth: 180,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                BarTooltipItem(
              _textoTooltipFlujo(datos, group.x, rod.toY),
              GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < datos.valores.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  fromY: 0,
                  toY: datos.valores[i],
                  color: datos.colores[i],
                  width: 18,
                  borderRadius: _radioBarra(datos.valores[i]),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// Texto del tooltip: mes y valor completo con signo (ej. "Sept · -$80.917").
  String _textoTooltipFlujo(DatosGraficaFlujo datos, int indice, double valor) {
    final etiqueta = indice >= 0 && indice < datos.etiquetas.length
        ? datos.etiquetas[indice]
        : '';
    return '$etiqueta · ${FormatoUtils.moneda.format(valor)}';
  }

  /// Redondea solo el extremo libre de la barra (arriba si sube, abajo si baja).
  BorderRadius _radioBarra(double valor) {
    if (valor >= 0) {
      return const BorderRadius.only(
        topLeft: Radius.circular(5),
        topRight: Radius.circular(5),
      );
    }
    return const BorderRadius.only(
      bottomLeft: Radius.circular(5),
      bottomRight: Radius.circular(5),
    );
  }

  /// Comparte los ejes entre las dos vistas: marcas del eje Y en formato corto
  /// y exactamente una etiqueta por mes en el eje X.
  FlTitlesData _titulosFlujo(DatosGraficaFlujo datos) {
    return FlTitlesData(
      show: true,
      topTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      rightTitles: const AxisTitles(
        sideTitles: SideTitles(showTitles: false),
      ),
      leftTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 58,
          interval: datos.intervalo,
          getTitlesWidget: (value, meta) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: Text(
              FlujoCajaViewLogic.formatoCortoPesos(value),
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.visible,
              style: GoogleFonts.poppins(
                fontSize: 9.5,
                color: const Color(0xFF8C8474),
              ),
            ),
          ),
        ),
      ),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 26,
          // Sin un interval fijo, fl_chart repite meses ("May May May May").
          interval: 1,
          getTitlesWidget: (value, meta) {
            final idx = value.round();
            final fueraDeRango = idx < 0 || idx >= datos.etiquetas.length;
            if (fueraDeRango || (value - idx).abs() > 0.01) {
              return const SizedBox.shrink();
            }
            return Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                datos.etiquetas[idx],
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF8C8474),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  FlGridData _cuadriculaFlujo(DatosGraficaFlujo datos) {
    return FlGridData(
      show: true,
      drawVerticalLine: false,
      horizontalInterval: datos.intervalo,
      getDrawingHorizontalLine: (_) => const FlLine(
        color: Color(0x148C8474),
        strokeWidth: 0.8,
      ),
    );
  }

  /// Línea horizontal punteada y sutil en el cero, visible en las dos vistas.
  ExtraLinesData _lineaCeroFlujo() {
    return ExtraLinesData(
      horizontalLines: [
        HorizontalLine(
          y: 0,
          color: const Color(0x668C8474),
          strokeWidth: 1,
          dashArray: const [4, 4],
        ),
      ],
    );
  }

  /// Encabezado de la tarjeta de flujo: en pantallas angostas (menos de 400 px)
  /// los botones van debajo del título/subtítulo ocupando el ancho completo,
  /// para que el título quede en una sola línea. En pantallas anchas se
  /// mantiene el título a la izquierda y los botones a la derecha.
  Widget _buildEncabezadoFlujo(DatosGraficaFlujo datos, bool esAcumulado) {
    final titulo = Column(
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
        const SizedBox(height: 2),
        // Explica qué mide la vista seleccionada.
        Text(
          esAcumulado
              ? 'Lo que llevas ahorrado en total desde ${datos.primerMesLargo}'
              : 'Lo que te sobró o faltó cada mes',
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: const Color(0xFF8C8474),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final angosto = constraints.maxWidth < 400;
        if (angosto) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titulo,
              const SizedBox(height: 10),
              _buildToggleFlujo(anchoCompleto: true),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: titulo),
            const SizedBox(width: 8),
            _buildToggleFlujo(),
          ],
        );
      },
    );
  }

  /// Control segmentado "Acumulado / Por mes". Con [anchoCompleto] los botones
  /// se reparten todo el ancho disponible.
  Widget _buildToggleFlujo({bool anchoCompleto = false}) {
    final activo = _modoFlujoCaja;
    Widget boton(String valor, String texto) {
      final seleccionado = activo == valor;
      return GestureDetector(
        onTap: () => setState(() => _modoFlujoCaja = valor),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
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
            maxLines: 1,
            softWrap: false,
            style: GoogleFonts.poppins(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: seleccionado ? Colors.white : const Color(0xFF8C8474),
            ),
          ),
        ),
      );
    }

    if (anchoCompleto) {
      return Row(
        children: [
          Expanded(child: boton('acumulado', 'Acumulado')),
          const SizedBox(width: 8),
          Expanded(child: boton('porPeriodo', 'Por mes')),
        ],
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
  // TARJETA 4 — Resumen de metas de ahorro (carrusel)
  // ================================================================
  Widget _buildTarjetaMetas() {
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
              'Tus metas de ahorro',
              style: GoogleFonts.poppins(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B2B2B),
              ),
            ),
            const SizedBox(height: 10),
            if (_metas.isEmpty)
              _buildEstadoVacioMetas()
            else
              NotificationListener<ScrollNotification>(
                onNotification: (notification) {
                  if (notification is ScrollStartNotification) {
                    _metaAutoTimer?.cancel();
                    _metaResumeTimer?.cancel();
                  } else if (notification is ScrollEndNotification) {
                    _metaResumeTimer = Timer(
                      const Duration(seconds: 3),
                      _iniciarAutoAvanceMetas,
                    );
                  }
                  return false;
                },
                child: SizedBox(
                  height: 100,
                  child: PageView.builder(
                    controller: _metasPageController,
                    itemCount: _metas.length,
                    onPageChanged: (i) =>
                        setState(() => _metaActualIndex = i),
                    itemBuilder: (_, i) => _buildPaginaMeta(_metas[i]),
                  ),
                ),
              ),
            if (_metas.isNotEmpty) const SizedBox(height: 10),
            if (_metas.length > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (int i = 0; i < _metas.length; i++) ...[
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      height: 6,
                      width: i == _metaActualIndex ? 18 : 6,
                      decoration: BoxDecoration(
                        color: i == _metaActualIndex
                            ? const Color(0xFF58774B)
                            : const Color(0xFFC9C2B0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    if (i < _metas.length - 1) const SizedBox(width: 4),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstadoVacioMetas() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF58774B).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.flag,
              size: 26,
              color: Color(0xFF58774B),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Aún no tienes metas de ahorro',
            style: GoogleFonts.poppins(
              fontSize: 14,
              color: const Color(0xFF2B2B2B),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 36,
            child: ElevatedButton(
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const RegistroMetaScreen(),
                  ),
                );
                if (result == true) {
                  _cargarMetas();
                }
              },
              style: ElevatedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 0),
                backgroundColor: const Color(0xFF58774B),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Ink(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF58774B), Color(0xFF7A9B6C)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  alignment: Alignment.center,
                  constraints: const BoxConstraints(minWidth: 88),
                  child: Text(
                    'Crear meta',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaginaMeta(Map<String, dynamic> meta) {
    final nombre = meta['nombre'].toString();
    final montoActual = (meta['monto_actual'] as num?)?.toDouble() ?? 0;
    final montoObjetivo = (meta['monto_objetivo'] as num).toDouble();
    final porcentaje = _metasLogic.calcularPorcentajeAvance(meta);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  nombre,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2B2B2B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${porcentaje.toStringAsFixed(0)}%',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF58774B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: porcentaje / 100,
              backgroundColor: const Color(0xFFC9C2B0),
              color: const Color(0xFF58774B),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              children: [
                TextSpan(
                  text: FormatoUtils.moneda.format(montoActual),
                  style: const TextStyle(color: Color(0xFF2B2B2B)),
                ),
                TextSpan(
                  text: ' de ',
                  style: const TextStyle(color: Color(0xFF8C8474)),
                ),
                TextSpan(
                  text: FormatoUtils.moneda.format(montoObjetivo),
                  style: const TextStyle(color: Color(0xFF2B2B2B)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ================================================================
  // TARJETA 5 — Progreso de educación financiera
  // ================================================================
  Widget _buildTarjetaEducacion() {
    final nuncaEmpezo = _nivelesEducacion.isEmpty ||
        !_nivelesEducacion.any(
          (n) => n.escalones.any((e) => e.completado == true),
        );
    final todosCompletados = _nivelesEducacion.isNotEmpty &&
        _nivelesEducacion.every((n) => n.porcentajeProgreso == 100);
    final nivel = _nivelActual();

    Future<void> navegarYRecargar() async {
      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => const EducacionFinancieraScreen(),
        ),
      );
      if (result == true || mounted) {
        _cargarEducacion();
      }
    }

    return Card(
      elevation: 1,
      color: Colors.white,
      shadowColor: const Color(0x0D000000),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: navegarYRecargar,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Educación financiera',
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              const SizedBox(height: 10),

              // CASO A — Nunca ha empezado
              if (nuncaEmpezo)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF58774B).withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.school,
                          size: 26,
                          color: Color(0xFF58774B),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Aún no has empezado tu educación financiera',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: const Color(0xFF2B2B2B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 36,
                        child: ElevatedButton(
                          onPressed: navegarYRecargar,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 0),
                            backgroundColor: const Color(0xFF58774B),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF58774B), Color(0xFF7A9B6C)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Container(
                              alignment: Alignment.center,
                              constraints: const BoxConstraints(minWidth: 88),
                              child: Text(
                                'Empezar mi primera lección',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              // CASO B — CompletóTODO
              else if (todosCompletados)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE0A458).withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.emoji_events,
                          size: 26,
                          color: Color(0xFFE0A458),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '¡Completaste toda la educación financiera! Eres todo un experto en finanzas.',
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: const Color(0xFF2B2B2B),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              // CASO C — Hay un nivel actual en progreso
              else if (nivel != null)
                _buildCuerpoNivelActual(nivel),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCuerpoNivelActual(NivelConEstado nivel) {
    final colorNivel = colorFromHex(nivel.colorHex);
    final escalonesCompletados =
        nivel.escalones.where((e) => e.completado).length;
    final totalEscalones = nivel.escalones.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                nivel.nombre,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorNivel,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$escalonesCompletados / $totalEscalones',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF8C8474),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: nivel.porcentajeProgreso / 100,
            backgroundColor: const Color(0xFFC9C2B0),
            color: colorNivel,
            minHeight: 8,
          ),
        ),
        const SizedBox(height: 10),
        IndicadorProgresoEscalones(
          escalones: nivel.escalones,
          colorNivel: colorNivel,
        ),
      ],
    );
  }

  // ================================================================
  // Helpers comunes
  // ================================================================
  Widget _buildTarjetaGraficaBase({
    required String titulo,
    required String subtitulo,
    double? altura,
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
            // Si no se fija altura, la tarjeta crece con su contenido (útil
            // para la leyenda de la torta, que varía según las categorías).
            if (altura != null) SizedBox(height: altura, child: child) else child,
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

  /// Sanea el valor máximo del eje Y. Si es 0, negativo, NaN o infinito
  /// devuelve 1, evitando intervalos de cuadrícula nulos o infinitos que
  /// bloquean el renderizado de fl_chart.
  double _maxYValido(double valor) {
    if (valor.isNaN || valor.isInfinite || valor <= 0) return 1;
    return valor;
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

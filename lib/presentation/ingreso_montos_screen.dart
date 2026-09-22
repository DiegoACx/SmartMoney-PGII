import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/auth_logic.dart';
import '../logic/categorias_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/transacciones_logic.dart';
import 'detalle_movimientos_screen.dart';
import 'registro_transaccion_screen.dart';
import 'utils/transaccion_options.dart';
import 'widgets/tarjeta_transaccion.dart';

// ===== Clipper curvo idéntico al de home_screen =====
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

// ===== Opciones del filtro =====
enum _FiltroMovimientos {
  todos,
  ingresos,
  egresos,
  categoria,
  fecha,
}

const Map<_FiltroMovimientos, String> _labelsFiltro = {
  _FiltroMovimientos.todos: 'Todos',
  _FiltroMovimientos.ingresos: 'Ingresos',
  _FiltroMovimientos.egresos: 'Egresos',
  _FiltroMovimientos.categoria: 'Categoría',
  _FiltroMovimientos.fecha: 'Fecha',
};

// ===== Pantalla principal =====
class IngresoMontosScreen extends StatefulWidget {
  const IngresoMontosScreen({super.key});

  @override
  State<IngresoMontosScreen> createState() => _IngresoMontosScreenState();
}

class _IngresoMontosScreenState extends State<IngresoMontosScreen> {
  final _transaccionesLogic = TransaccionesLogic();
  final _authLogic = AuthLogic();
  final _categoriasLogic = CategoriasLogic();

  final _formatoDia = DateFormat('dd/MM/yyyy');
  final _formatoEncabezado = DateFormat("d 'de' MMMM 'de' y", 'es');

  bool _cargando = true;
  List<Map<String, dynamic>> _transacciones = [];
  List<Map<String, dynamic>> _categorias = [];
  _FiltroMovimientos _filtro = _FiltroMovimientos.todos;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  // ===== Carga de datos (transacciones + categorías) =====
  Future<void> _cargarDatos() async {
    setState(() => _cargando = true);
    try {
      final usuarioId = _authLogic.obtenerUsuarioId();
      if (usuarioId == null) {
        if (!mounted) return;
        setState(() {
          _transacciones = [];
          _categorias = [];
          _cargando = false;
        });
        return;
      }
      final resultados = await Future.wait([
        _transaccionesLogic.obtenerTodasLasTransacciones(usuarioId),
        _categoriasLogic.obtenerCategoriasDisponibles(),
      ]);
      if (!mounted) return;
      setState(() {
        _transacciones = List<Map<String, dynamic>>.from(resultados[0]);
        _categorias = List<Map<String, dynamic>>.from(resultados[1]);
        _cargando = false;
      });
    } catch (e) {
      debugPrint('ERROR CARGAR DATOS INGRESOS: $e');
      if (!mounted) return;
      setState(() {
        _transacciones = [];
        _categorias = [];
        _cargando = false;
      });
    }
  }

  // ===== Navegar a registro y recargar al volver =====
  Future<void> _irARegistro() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RegistroTransaccionScreen(),
      ),
    );
    if (!mounted) return;
    await _cargarDatos();
  }

  // ===== Helpers para extraer campos de la transacción =====
  String _nombreCategoria(Map<String, dynamic> t) {
    final cat = t['categorias'];
    if (cat is Map) {
      return cat['nombre']?.toString() ?? 'Sin categoría';
    }
    return 'Sin categoría';
  }

  String? _nota(Map<String, dynamic> t) {
    final d = t['descripcion'];
    if (d == null) return null;
    final s = d.toString().trim();
    return s.isEmpty ? null : s;
  }

  String? _metodoPago(Map<String, dynamic> t) {
    final mp = t['metodo_pago'];
    if (mp == null) return null;
    final s = mp.toString().trim();
    return s.isEmpty ? null : s;
  }

  double _monto(Map<String, dynamic> t) {
    return (t['monto'] as num).toDouble();
  }

  String _fechaDia(Map<String, dynamic> t) {
    return _formatoDia.format(DateTime.parse(t['fecha'] as String));
  }

  // ===== Widget: monto formateado con signo y color =====
  Widget _textoNeto(double monto, {double fontSize = 15}) {
    final signo = monto >= 0 ? '+' : '-';
    final color = monto >= 0
        ? const Color(0xFF58774B)
        : const Color(0xFFC0392B);
    return Text(
      '$signo ${FormatoUtils.moneda.format(monto.abs())}',
      style: GoogleFonts.poppins(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: color,
      ),
    );
  }

  // ===== Widget: botón "Ver más" =====
  Widget _verMasButton(VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Center(
        child: TextButton(
          onPressed: onTap,
          child: Text(
            'Ver más',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF58774B),
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ),
    );
  }

  // ===== Abrir bottom sheet con opciones de transacción =====
  Future<void> _mostrarOpcionesTransaccion(
      Map<String, dynamic> transaccion) async {
    await mostrarOpcionesTransaccion(
      context: context,
      transaccion: transaccion,
      nombreCategoria: _nombreCategoria(transaccion),
      monto: _monto(transaccion),
      onRecargar: _cargarDatos,
    );
  }

  // ===== Build principal =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_ingresos',
        onPressed: _irARegistro,
        backgroundColor: const Color(0xFF58774B),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF58774B),
          onRefresh: _cargarDatos,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 96),
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
                        'Tus movimientos',
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

                // ===== Selector de filtro =====
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    height: 44,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _FiltroMovimientos.values.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (_, i) {
                        final f = _FiltroMovimientos.values[i];
                        final seleccionado = f == _filtro;
                        return GestureDetector(
                          onTap: () => setState(() => _filtro = f),
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
                              _labelsFiltro[f]!,
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
                else
                  _buildContenido(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== Contenido según filtro =====
  Widget _buildContenido() {
    switch (_filtro) {
      case _FiltroMovimientos.todos:
        return _buildTodos();
      case _FiltroMovimientos.ingresos:
        return _buildListaPlana(
          _transaccionesLogic.filtrarPorTipo(_transacciones, 'ingreso'),
          tituloVerMas: 'Todos los ingresos',
          filtroTipo: 'ingreso',
        );
      case _FiltroMovimientos.egresos:
        return _buildListaPlana(
          _transaccionesLogic.filtrarPorTipo(_transacciones, 'egreso'),
          tituloVerMas: 'Todos los egresos',
          filtroTipo: 'egreso',
        );
      case _FiltroMovimientos.categoria:
        return _buildPorCategoria();
      case _FiltroMovimientos.fecha:
        return _buildPorFecha();
    }
  }

  // ===== Modo TODOS: Total general arriba + lista limitada 5 =====
  Widget _buildTodos() {
    final lista = _transacciones;
    if (lista.isEmpty) return _buildEstadoVacio();

    final total = _transaccionesLogic.calcularTotalNeto(lista);
    final signoTotal = total >= 0 ? '+' : '-';
    final colorTotal = total >= 0
        ? const Color(0xFF58774B)
        : const Color(0xFFC0392B);

    final limitada = lista.take(5).toList();
    final hayMas = lista.length > 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Total general
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  'Total',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF8C8474),
                  ),
                ),
                const Spacer(),
                Text(
                  '$signoTotal ${FormatoUtils.moneda.format(total.abs())}',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colorTotal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Lista limitada
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: limitada.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => TarjetaTransaccion(
              transaccion: limitada[i],
              nombreCategoria: _nombreCategoria(limitada[i]),
              nota: _nota(limitada[i]),
              metodoPago: _metodoPago(limitada[i]),
              monto: _monto(limitada[i]),
              fechaDia: _fechaDia(limitada[i]),
              onTap: () => _mostrarOpcionesTransaccion(limitada[i]),
            ),
          ),
          if (hayMas)
            _verMasButton(() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetalleMovimientosScreen(
                    titulo: 'Todos los movimientos',
                    transacciones: lista,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ===== Lista plana (Ingresos / Egresos): total arriba + límite 5 + Ver más =====
  Widget _buildListaPlana(
    List<Map<String, dynamic>> lista, {
    required String tituloVerMas,
    String? filtroTipo,
    String? filtroCategoriaId,
  }) {
    if (lista.isEmpty) return _buildEstadoVacio();

    final total = _transaccionesLogic.calcularTotalNeto(lista);
    final signoTotal = total >= 0 ? '+' : '-';
    final colorTotal = total >= 0
        ? const Color(0xFF58774B)
        : const Color(0xFFC0392B);

    final limitada = lista.take(5).toList();
    final hayMas = lista.length > 5;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
            ),
            child: Row(
              children: [
                Text(
                  'Total',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF8C8474),
                  ),
                ),
                const Spacer(),
                Text(
                  '$signoTotal ${FormatoUtils.moneda.format(total.abs())}',
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: colorTotal,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: limitada.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => TarjetaTransaccion(
              transaccion: limitada[i],
              nombreCategoria: _nombreCategoria(limitada[i]),
              nota: _nota(limitada[i]),
              metodoPago: _metodoPago(limitada[i]),
              monto: _monto(limitada[i]),
              fechaDia: _fechaDia(limitada[i]),
              onTap: () => _mostrarOpcionesTransaccion(limitada[i]),
            ),
          ),
          if (hayMas)
            _verMasButton(() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetalleMovimientosScreen(
                    titulo: tituloVerMas,
                    transacciones: lista,
                    filtroTipo: filtroTipo,
                    filtroCategoriaId: filtroCategoriaId,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ===== Modo POR CATEGORÍA: con movimientos primero, luego vacías =====
  Widget _buildPorCategoria() {
    final grupos =
        _transaccionesLogic.agruparPorCategoria(_transacciones, _categorias);

    // Reordenar: categorías CON movimientos primero (orden del Map),
    // luego categorías VACÍAS (orden del Map).
    final todasLasCategoriasOrdenadas = grupos.entries.toList();
    final conMovimientos =
        todasLasCategoriasOrdenadas.where((e) => e.value.isNotEmpty).toList();
    final vacias =
        todasLasCategoriasOrdenadas.where((e) => e.value.isEmpty).toList();
    final ordenado = [...conMovimientos, ...vacias];

    if (conMovimientos.isEmpty && vacias.isEmpty) return _buildEstadoVacio();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: ordenado.length,
        separatorBuilder: (_, _) => const SizedBox(height: 24),
        itemBuilder: (_, i) {
          final entry = ordenado[i];
          final nombreCategoria = entry.key;
          final transaccionesDeCategoria = entry.value;
          final esVacia = transaccionesDeCategoria.isEmpty;

          final total = esVacia
              ? 0.0
              : _transaccionesLogic.calcularTotalNeto(transaccionesDeCategoria);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Encabezado (nombre + total si no está vacía)
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      nombreCategoria,
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2B2B2B),
                      ),
                    ),
                  ),
                  if (!esVacia) _textoNeto(total),
                ],
              ),
              const SizedBox(height: 12),

              if (esVacia)
                Text(
                  'Aún no has ingresado montos por esta categoría',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF8C8474),
                    fontStyle: FontStyle.italic,
                  ),
                )
              else
                _buildBloqueTransaccionesConVerMas(
                  transaccionesDeCategoria,
                  () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DetalleMovimientosScreen(
                          titulo: nombreCategoria,
                          transacciones: transaccionesDeCategoria,
                          filtroCategoriaId: transaccionesDeCategoria
                              .first['categoria_id']
                              ?.toString(),
                        ),
                      ),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  // ===== Modo POR FECHA: máximo 5 transacciones EN TOTAL (sumando grupos) =====
  Widget _buildPorFecha() {
    final grupos = _transaccionesLogic.agruparPorFecha(_transacciones);
    if (grupos.isEmpty) return _buildEstadoVacio();

    // Calcular cuántos elementos (fecha entry + transacciones dentro) mostramos
    // respetando el límite de 5 transacciones TOTALES, y luego "Ver más".
    const limiteTotal = 5;
    int acumulado = 0;
    final gruposMostrados = <MapEntry<String, List<Map<String, dynamic>>>>[];
    final cortesPorGrupo = <int, int>{}; // índice grupo → cuántas transacciones
    for (int g = 0; g < grupos.length; g++) {
      final entry = grupos.entries.elementAt(g);
      final disponiblesEnGrupo = entry.value.length;
      final cupoRestante = limiteTotal - acumulado;
      if (cupoRestante <= 0) break;
      final mostrar = disponiblesEnGrupo > cupoRestante
          ? cupoRestante
          : disponiblesEnGrupo;
      gruposMostrados.add(entry);
      cortesPorGrupo[g] = mostrar;
      acumulado += mostrar;
      if (acumulado >= limiteTotal) break;
    }
    final hayMas = _transacciones.length > limiteTotal;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: gruposMostrados.length,
            separatorBuilder: (_, _) => const SizedBox(height: 24),
            itemBuilder: (_, i) {
              final entry = gruposMostrados[i];
              final fechaLegible =
                  _formatoEncabezado.format(DateTime.parse(entry.key));
              final mostrarCant = cortesPorGrupo[i]!;
              final totalDelDia =
                  _transaccionesLogic.calcularTotalNeto(entry.value);

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Encabezado fecha + total del día
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          fechaLegible,
                          style: GoogleFonts.poppins(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2B2B2B),
                          ),
                        ),
                      ),
                      _textoNeto(totalDelDia),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: mostrarCant,
                    separatorBuilder: (_, _) => const SizedBox(height: 12),
                    itemBuilder: (_, j) {
                      final t = entry.value[j];
                      return TarjetaTransaccion(
                        transaccion: t,
                        nombreCategoria: _nombreCategoria(t),
                        nota: _nota(t),
                        metodoPago: _metodoPago(t),
                        monto: _monto(t),
                        fechaDia: _fechaDia(t),
                        onTap: () => _mostrarOpcionesTransaccion(t),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          if (hayMas)
            _verMasButton(() {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => DetalleMovimientosScreen(
                    titulo: 'Todos los movimientos por fecha',
                    transacciones: _transacciones,
                    agruparPorFecha: true,
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // ===== Helper: bloque de transacciones limitado a 5 + botón "Ver más" =====
  Widget _buildBloqueTransaccionesConVerMas(
    List<Map<String, dynamic>> lista,
    VoidCallback onVerMas,
  ) {
    final limitada = lista.take(5).toList();
    final hayMas = lista.length > 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: limitada.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, j) {
            final t = limitada[j];
            return TarjetaTransaccion(
              transaccion: t,
              nombreCategoria: _nombreCategoria(t),
              nota: _nota(t),
              metodoPago: _metodoPago(t),
              monto: _monto(t),
              fechaDia: _fechaDia(t),
              onTap: () => _mostrarOpcionesTransaccion(t),
            );
          },
        ),
        if (hayMas) _verMasButton(onVerMas),
      ],
    );
  }

  // ===== Estado vacío =====
  Widget _buildEstadoVacio() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      child: Column(
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: const Color(0xFF58774B).withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.swap_horiz_rounded,
              color: Color(0xFF58774B),
              size: 42,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No hay movimientos aún',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2B2B2B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Pulsa el botón + para registrar tu primera transacción.',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w400,
              color: const Color(0xFF8C8474),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

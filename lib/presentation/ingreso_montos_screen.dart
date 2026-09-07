import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/auth_logic.dart';
import '../logic/categorias_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/transacciones_logic.dart';
import 'registro_transaccion_screen.dart';

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

  // ===== Build principal =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      floatingActionButton: FloatingActionButton(
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
        return _buildListaPlana(_transacciones);
      case _FiltroMovimientos.ingresos:
        return _buildListaPlana(
          _transaccionesLogic.filtrarPorTipo(_transacciones, 'ingreso'),
        );
      case _FiltroMovimientos.egresos:
        return _buildListaPlana(
          _transaccionesLogic.filtrarPorTipo(_transacciones, 'egreso'),
        );
      case _FiltroMovimientos.categoria:
        return _buildPorCategoria();
      case _FiltroMovimientos.fecha:
        return _buildPorFecha();
    }
  }

  // ===== Lista plana (Todos / Ingresos / Egresos) =====
  Widget _buildListaPlana(List<Map<String, dynamic>> lista) {
    if (lista.isEmpty) return _buildEstadoVacio();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: lista.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _TarjetaTransaccion(
          transaccion: lista[i],
          nombreCategoria: _nombreCategoria(lista[i]),
          nota: _nota(lista[i]),
          metodoPago: _metodoPago(lista[i]),
          monto: _monto(lista[i]),
          fechaDia: _fechaDia(lista[i]),
        ),
      ),
    );
  }

  // ===== Agrupado por categoría =====
  Widget _buildPorCategoria() {
    final grupos =
        _transaccionesLogic.agruparPorCategoria(_transacciones, _categorias);
    if (grupos.isEmpty) return _buildEstadoVacio();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: grupos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 24),
        itemBuilder: (_, i) {
          final entry = grupos.entries.elementAt(i);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.key,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              const SizedBox(height: 12),
              if (entry.value.isEmpty)
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
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: entry.value.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, j) {
                    final t = entry.value[j];
                    return _TarjetaTransaccion(
                      transaccion: t,
                      nombreCategoria: entry.key,
                      nota: _nota(t),
                      metodoPago: _metodoPago(t),
                      monto: _monto(t),
                      fechaDia: _fechaDia(t),
                    );
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  // ===== Agrupado por fecha =====
  Widget _buildPorFecha() {
    final grupos = _transaccionesLogic.agruparPorFecha(_transacciones);
    if (grupos.isEmpty) return _buildEstadoVacio();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: grupos.length,
        separatorBuilder: (_, _) => const SizedBox(height: 24),
        itemBuilder: (_, i) {
          final entry = grupos.entries.elementAt(i);
          final fechaLegible =
              _formatoEncabezado.format(DateTime.parse(entry.key));
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                fechaLegible,
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              const SizedBox(height: 12),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: entry.value.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, j) {
                  final t = entry.value[j];
                  return _TarjetaTransaccion(
                    transaccion: t,
                    nombreCategoria: _nombreCategoria(t),
                    nota: _nota(t),
                    metodoPago: _metodoPago(t),
                    monto: _monto(t),
                    fechaDia: _fechaDia(t),
                  );
                },
              ),
            ],
          );
        },
      ),
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

// ===== Widget auxiliar: tarjeta de transacción =====
class _TarjetaTransaccion extends StatelessWidget {
  final Map<String, dynamic> transaccion;
  final String nombreCategoria;
  final String? nota;
  final String? metodoPago;
  final double monto;
  final String fechaDia;

  const _TarjetaTransaccion({
    required this.transaccion,
    required this.nombreCategoria,
    required this.nota,
    required this.metodoPago,
    required this.monto,
    required this.fechaDia,
  });

  @override
  Widget build(BuildContext context) {
    final tipo = transaccion['tipo'] as String;
    final esIngreso = tipo == 'ingreso';
    final colorBorde =
        esIngreso ? const Color(0xFF58774B) : const Color(0xFFC0392B);
    final signo = esIngreso ? '+' : '-';
    final colorMonto =
        esIngreso ? const Color(0xFF58774B) : const Color(0xFFC0392B);

    final tieneNota = nota != null;
    final tieneMetodo = metodoPago != null;

    return Container(
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
        border: Border(
          left: BorderSide(color: colorBorde, width: 5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Categoría + fecha
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          nombreCategoria,
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF2B2B2B),
                          ),
                        ),
                      ),
                      Text(
                        fechaDia,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w400,
                          color: const Color(0xFF8C8474),
                        ),
                      ),
                    ],
                  ),
                  if (tieneNota) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.sticky_note_2_outlined,
                            size: 13,
                            color: Color(0xFFC9C2B0),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            nota!,
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w400,
                              color: const Color(0xFF8C8474),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (tieneMetodo) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          metodoPago == 'efectivo'
                              ? Icons.payments_outlined
                              : Icons.account_balance_outlined,
                          size: 14,
                          color: const Color(0xFFC9C2B0),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          metodoPago == 'efectivo' ? 'Efectivo' : 'Transferencia',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w400,
                            color: const Color(0xFF8C8474),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Text(
              '$signo ${FormatoUtils.moneda.format(monto)}',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: colorMonto,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

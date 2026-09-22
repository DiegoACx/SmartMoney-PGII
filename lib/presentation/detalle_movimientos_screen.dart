import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/auth_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/transacciones_logic.dart';
import 'utils/transaccion_options.dart';
import 'widgets/tarjeta_transaccion.dart';

// ===== Clipper curvo idéntico al de IngresoMontosScreen =====
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

class DetalleMovimientosScreen extends StatefulWidget {
  final String titulo;
  final List<Map<String, dynamic>> transacciones;
  final bool agruparPorFecha;
  final String? filtroTipo;
  final String? filtroCategoriaId;

  const DetalleMovimientosScreen({
    super.key,
    required this.titulo,
    required this.transacciones,
    this.agruparPorFecha = false,
    this.filtroTipo,
    this.filtroCategoriaId,
  });

  @override
  State<DetalleMovimientosScreen> createState() =>
      _DetalleMovimientosScreenState();
}

class _DetalleMovimientosScreenState extends State<DetalleMovimientosScreen> {
  final _transaccionesLogic = TransaccionesLogic();
  final _authLogic = AuthLogic();
  final _formatoDia = DateFormat('dd/MM/yyyy');
  final _formatoEncabezado = DateFormat("d 'de' MMMM 'de' y", 'es');
  final _dateFormatPicker = DateFormat('dd/MM/yyyy');

  final _desdeController = TextEditingController();
  final _hastaController = TextEditingController();
  DateTime? _desde;
  DateTime? _hasta;

  late List<Map<String, dynamic>> _listaTransacciones;

  @override
  void initState() {
    super.initState();
    _listaTransacciones = List.from(widget.transacciones);
  }

  Future<void> _recargarDatos() async {
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) return;
    try {
      final todas = await _transaccionesLogic
          .obtenerTodasLasTransacciones(usuarioId);
      if (!mounted) return;
      setState(() {
        var filtradas = todas;
        if (widget.filtroTipo != null) {
          filtradas = filtradas
              .where((t) => t['tipo'] == widget.filtroTipo)
              .toList();
        } else if (widget.filtroCategoriaId != null) {
          filtradas = filtradas
              .where((t) =>
                  t['categoria_id']?.toString() == widget.filtroCategoriaId)
              .toList();
        }
        _listaTransacciones = filtradas;
      });
    } catch (e) {
      debugPrint('ERROR RECARGAR DETALLE: $e');
    }
  }

  @override
  void dispose() {
    _desdeController.dispose();
    _hastaController.dispose();
    super.dispose();
  }

  // ===== Helpers (iguales a IngresoMontosScreen) =====
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

  // ===== Abrir bottom sheet con opciones de transacción =====
  Future<void> _mostrarOpcionesTransaccion(
      Map<String, dynamic> transaccion) async {
    await mostrarOpcionesTransaccion(
      context: context,
      transaccion: transaccion,
      nombreCategoria: _nombreCategoria(transaccion),
      monto: _monto(transaccion),
      onRecargar: _recargarDatos,
    );
  }

  // ===== Filtro de rango de fechas =====
  List<Map<String, dynamic>> get _transaccionesVisibles {
    if (_desde == null || _hasta == null) return _listaTransacciones;
    return _listaTransacciones.where((t) {
      final f = DateTime.parse(t['fecha'] as String);
      return !f.isBefore(_desde!) && !f.isAfter(_hasta!);
    }).toList();
  }

  Future<void> _seleccionarDesde() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _desde ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: _hasta ?? DateTime(2100),
      locale: const Locale('es', 'ES'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF58774B),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF2B2B2B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _desde = picked;
        _desdeController.text = _dateFormatPicker.format(picked);
      });
    }
  }

  Future<void> _seleccionarHasta() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _hasta ?? DateTime.now(),
      firstDate: _desde ?? DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'ES'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF58774B),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF2B2B2B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _hasta = picked;
        _hastaController.text = _dateFormatPicker.format(picked);
      });
    }
  }

  void _limpiarFiltro() {
    setState(() {
      _desde = null;
      _hasta = null;
      _desdeController.clear();
      _hastaController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final visibles = _transaccionesVisibles;
    final total = _transaccionesLogic.calcularTotalNeto(visibles);
    final signoTotal = total >= 0 ? '+' : '-';
    final colorTotal = total >= 0
        ? const Color(0xFF58774B)
        : const Color(0xFFC0392B);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ===== Header =====
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
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        widget.titulo,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ===== Selector de rango =====
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
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
                                'Desde',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF2B2B2B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Material(
                                elevation: 1,
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.transparent,
                                child: TextFormField(
                                  controller: _desdeController,
                                  readOnly: true,
                                  onTap: _seleccionarDesde,
                                  decoration: const InputDecoration(
                                    labelText: 'Desde',
                                    prefixIcon: Icon(
                                      Icons.calendar_today_outlined,
                                      color: Color(0xFFC9C2B0),
                                    ),
                                  ),
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFF2B2B2B),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hasta',
                                style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: const Color(0xFF2B2B2B),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Material(
                                elevation: 1,
                                borderRadius: BorderRadius.circular(14),
                                color: Colors.transparent,
                                child: TextFormField(
                                  controller: _hastaController,
                                  readOnly: true,
                                  onTap: _seleccionarHasta,
                                  decoration: const InputDecoration(
                                    labelText: 'Hasta',
                                    prefixIcon: Icon(
                                      Icons.calendar_today_outlined,
                                      color: Color(0xFFC9C2B0),
                                    ),
                                  ),
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFF2B2B2B),
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_desde != null || _hasta != null) ...[
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _limpiarFiltro,
                          child: Text(
                            'Limpiar filtro',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF8C8474),
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // ===== Total =====
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 14),
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
              ),
              const SizedBox(height: 20),

              if (visibles.isEmpty)
                _buildEstadoVacio()
              else if (widget.agruparPorFecha)
                _buildAgrupadoPorFecha(visibles)
              else
                _buildListaPlana(visibles),
            ],
          ),
        ),
      ),
    );
  }

  // ===== Lista plana =====
  Widget _buildListaPlana(List<Map<String, dynamic>> lista) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: lista.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (_, i) => TarjetaTransaccion(
          transaccion: lista[i],
          nombreCategoria: _nombreCategoria(lista[i]),
          nota: _nota(lista[i]),
          metodoPago: _metodoPago(lista[i]),
          monto: _monto(lista[i]),
          fechaDia: _fechaDia(lista[i]),
          onTap: () => _mostrarOpcionesTransaccion(lista[i]),
        ),
      ),
    );
  }

  // ===== Agrupado por fecha =====
  Widget _buildAgrupadoPorFecha(List<Map<String, dynamic>> lista) {
    final grupos = _transaccionesLogic.agruparPorFecha(lista);
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
            'No hay movimientos en este rango',
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: const Color(0xFF2B2B2B),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Prueba a limpiar el filtro de fechas.',
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

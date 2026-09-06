import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/auth_logic.dart';
import '../logic/transacciones_logic.dart';
import 'registro_transaccion_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = AuthLogic();
  final _transaccionesLogic = TransaccionesLogic();

  List<Map<String, dynamic>> _transacciones = [];
  bool _cargando = true;

  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _moneyFormat = NumberFormat.currency(
    locale: 'es_MX',
    symbol: '\$',
    decimalDigits: 2,
  );

  @override
  void initState() {
    super.initState();
    _cargarTransacciones();
  }

  Future<void> _cargarTransacciones() async {
    setState(() => _cargando = true);
    try {
      final usuarioId = _auth.obtenerUsuarioId();
      if (usuarioId == null) {
        if (!mounted) return;
        setState(() {
          _transacciones = [];
          _cargando = false;
        });
        return;
      }
      final lista = await _transaccionesLogic.obtenerTransaccionesRecientes(
        usuarioId,
        limite: 10,
      );
      if (!mounted) return;
      setState(() {
        _transacciones = lista;
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

  Future<void> _irARegistro() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const RegistroTransaccionScreen(),
      ),
    );
    // Al volver, refrescamos la lista para ver la transacción recién creada
    if (mounted) _cargarTransacciones();
  }

  // ===== Color de acento por tipo =====
  Color _colorPorTipo(String tipo) {
    if (tipo == 'ingreso') return const Color(0xFF58774B);
    return const Color(0xFFC0392B);
  }

  // ===== Signo por tipo =====
  String _signoPorTipo(String tipo) {
    return tipo == 'ingreso' ? '+' : '-';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      floatingActionButton: FloatingActionButton(
        onPressed: _irARegistro,
        backgroundColor: const Color(0xFF58774B),
        foregroundColor: Colors.white,
        elevation: 4,
        child: const Icon(Icons.add, size: 28),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF58774B),
          onRefresh: _cargarTransacciones,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 16,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ===== Saludo =====
                const SizedBox(height: 8),
                Text(
                  'Hola de nuevo',
                  style: GoogleFonts.poppins(
                    fontSize: 26,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2B2B2B),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tus movimientos recientes',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF787D7D),
                  ),
                ),
                const SizedBox(height: 24),

                // ===== Lista / Loading / Vacío =====
                _cargando
                    ? _buildLoading()
                    : _transacciones.isEmpty
                        ? _buildEstadoVacio()
                        : _buildLista(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ===== Indicador de carga =====
  Widget _buildLoading() {
    return const SizedBox(
      height: 300,
      child: Center(
        child: CircularProgressIndicator(
          color: Color(0xFF58774B),
          strokeWidth: 3,
        ),
      ),
    );
  }

  // ===== Estado vacío =====
  Widget _buildEstadoVacio() {
    return SizedBox(
      height: 380,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: const Color(0xFF58774B).withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 72,
                color: Color(0xFF58774B),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aún no tienes transacciones registradas',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF2B2B2B),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Toca el botón + para agregar tu primera transacción',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                color: const Color(0xFF787D7D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Lista de transacciones =====
  Widget _buildLista() {
    return Column(
      children: List.generate(_transacciones.length, (i) {
        final t = _transacciones[i];
        final tipo = (t['tipo'] as String).toLowerCase();
        final monto = (t['monto'] as num).toDouble();
        final fechaStr = t['fecha'] as String? ?? '';
        final fecha = DateTime.tryParse(fechaStr) ?? DateTime.now();
        final categoria =
            t['categorias'] != null && (t['categorias'] is Map)
                ? (t['categorias'] as Map)['nombre']?.toString() ??
                    'Sin categoría'
                : t['categoria_nombre']?.toString() ??
                    (t['categoria_id']?.toString() ?? 'Sin categoría');
        final acento = _colorPorTipo(tipo);

        return Padding(
          padding: EdgeInsets.only(
            bottom: i == _transacciones.length - 1 ? 80 : 12,
          ),
          child: Card(
            elevation: 1,
            shadowColor: Colors.black.withValues(alpha: 0.08),
            color: Colors.white,
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Row(
                children: [
                  // Barra de acento a la izquierda
                  Container(
                    width: 5,
                    height: 76,
                    color: acento,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          // Categoría + Fecha
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  categoria,
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: const Color(0xFF2B2B2B),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _dateFormat.format(fecha),
                                  style: GoogleFonts.poppins(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                    color: const Color(0xFF787D7D),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Monto
                          Text(
                            '${_signoPorTipo(tipo)} ${_moneyFormat.format(monto).replaceFirst('\$', '\$ ')}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: acento,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

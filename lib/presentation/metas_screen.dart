import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/auth_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/metas_logic.dart';
import '../services/notificaciones_service.dart';
import 'registro_meta_screen.dart';
import 'utils/meta_options.dart';

// ===== Header decorativo curvo =====
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

class MetasScreen extends StatefulWidget {
  const MetasScreen({super.key});

  @override
  State<MetasScreen> createState() => _MetasScreenState();
}

class _MetasScreenState extends State<MetasScreen> {
  final _metasLogic = MetasLogic();
  final _authLogic = AuthLogic();
  final _notificacionesService = NotificacionesService();
  final _dateFormat = DateFormat('dd/MM/yyyy');

  bool _cargando = true;
  List<Map<String, dynamic>> _metas = [];

  @override
  void initState() {
    super.initState();
    _cargarMetas();
  }

  Future<void> _cargarMetas() async {
    setState(() => _cargando = true);
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) {
      if (!mounted) return;
      setState(() {
        _metas = [];
        _cargando = false;
      });
      return;
    }

    List<Map<String, dynamic>> lista = [];
    try {
      lista = await _metasLogic.obtenerMetas(usuarioId);
    } catch (e) {
      debugPrint('ERROR CARGAR METAS: $e');
    }
    if (!mounted) return;
    setState(() {
      _metas = lista;
      _cargando = false;
    });

    _reprogramarRecordatorios(lista);
  }

  Future<void> _reprogramarRecordatorios(
    List<Map<String, dynamic>> lista,
  ) async {
    for (final meta in lista) {
      final cumplida = meta['cumplida'] == true;
      if (cumplida) continue;
      final fechaLimiteStr = meta['fecha_limite'] as String?;
      if (fechaLimiteStr == null) continue;
      final fechaLimite = DateTime.tryParse(fechaLimiteStr);
      if (fechaLimite == null) continue;
      final fechaRecordatorio =
          _metasLogic.calcularFechaRecordatorio(fechaLimite);
      if (fechaRecordatorio == null) continue;
      final metaId = meta['id'].toString();
      final nombre = meta['nombre'].toString();
      try {
        await _notificacionesService
            .programarRecordatorio(
              metaId: metaId,
              nombreMeta: nombre,
              fecha: fechaRecordatorio,
            )
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint(
          'ERROR PROGRAMAR NOTIFICACIÓN (meta $metaId): $e',
        );
      }
    }
  }

  DateTime? _parsearFecha(dynamic fechaStr) {
    if (fechaStr == null) return null;
    return DateTime.tryParse(fechaStr.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab_metas',
        onPressed: _cargando
            ? null
            : () async {
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
        backgroundColor: const Color(0xFF58774B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        child: const Icon(
          Icons.add,
          color: Colors.white,
          size: 28,
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF58774B),
          onRefresh: _cargarMetas,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                // ===== Header curvo =====
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.22,
                  width: double.infinity,
                  child: ClipPath(
                    clipper: _CurvedHeaderClipper(),
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF58774B), Color(0xFF7A9B6C)],
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'Tus metas de ahorro',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // ===== Contenido =====
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  child: _cargando
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF58774B),
                          ),
                        )
                      : _metas.isEmpty
                          ? _buildEstadoVacio()
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _metas.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 16),
                              itemBuilder: (_, i) =>
                                  _buildTarjetaMeta(_metas[i]),
                            ),
                ),
              ],
            ),
          ),
        ),
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
                Icons.flag,
                size: 56,
                color: Color(0xFF58774B),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Aún no tienes metas de ahorro',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2B2B2B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Toca el botón + para crear tu primera meta.',
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

  Widget _buildTarjetaMeta(Map<String, dynamic> meta) {
    final nombre = meta['nombre'].toString();
    final montoActual = (meta['monto_actual'] as num?)?.toDouble() ?? 0;
    final montoObjetivo = (meta['monto_objetivo'] as num).toDouble();
    final porcentaje = _metasLogic.calcularPorcentajeAvance(meta);
    final fechaLimite = _parsearFecha(meta['fecha_limite']);
    final cumplida = meta['cumplida'] == true;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => mostrarOpcionesMeta(
        context: context,
        meta: meta,
        onRecargar: _cargarMetas,
      ),
      child: Card(
        elevation: 1,
        color: Colors.white,
        shadowColor: const Color(0x0D000000),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      nombre,
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2B2B2B),
                      ),
                    ),
                  ),
                  if (cumplida)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Color(0xFF7A9B6C),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.check,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '¡Meta cumplida!',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF7A9B6C),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              const SizedBox(height: 10),
              RichText(
                text: TextSpan(
                  style: GoogleFonts.poppins(
                    fontSize: 14,
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
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: porcentaje / 100,
                        backgroundColor: const Color(0xFFC9C2B0),
                        color: const Color(0xFF58774B),
                        minHeight: 8,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${porcentaje.toStringAsFixed(0)}%',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF8C8474),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (!cumplida && fechaLimite != null)
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: Color(0xFFC9C2B0),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _dateFormat.format(fechaLimite),
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: const Color(0xFF8C8474),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../logic/recomendaciones_logic.dart';

const Color _verde = Color(0xFF58774B);
const Color _verdeClaro = Color(0xFF7A9B6C);
const Color _dorado = Color(0xFFE0A458);
const Color _gris = Color(0xFF8C8474);
const Color _texto = Color(0xFF2B2B2B);
const Color _borde = Color(0xFFECECEC);

/// Máximo de recomendaciones visibles en el Dashboard.
const int _maxVisibles = 2;

/// Tarjetas de recomendaciones del motor de IA para el Dashboard.
///
/// Se carga sola en segundo plano: mientras llega la respuesta muestra un
/// placeholder discreto y, si falla o no hay recomendaciones, no ocupa espacio.
class TarjetaRecomendaciones extends StatefulWidget {
  const TarjetaRecomendaciones({
    super.key,
    this.onVerLeccion,
    this.onVerMeta,
  });

  /// Abre la lección sugerida identificada por `escalon_id`.
  final void Function(String escalonId)? onVerLeccion;

  /// Navega a la pestaña de metas.
  final VoidCallback? onVerMeta;

  @override
  State<TarjetaRecomendaciones> createState() => TarjetaRecomendacionesState();
}

class TarjetaRecomendacionesState extends State<TarjetaRecomendaciones> {
  final _logic = RecomendacionesLogic();

  bool _cargando = true;
  List<Map<String, dynamic>> _visibles = [];

  /// Ids ya reportados con `marcarMostrada` (una sola vez por recomendación).
  final Set<String> _marcadas = {};

  /// Ids cuya animación de despedida ya terminó.
  final Set<String> _desvanecidas = {};

  @override
  void initState() {
    super.initState();
    recargar();
  }

  Future<void> recargar({bool forzar = false}) async {
    if (mounted) setState(() => _cargando = true);

    final lista = await _logic.obtenerRecomendaciones(forzar: forzar);
    if (!mounted) return;

    final visibles = _ordenar(lista).take(_maxVisibles).toList();
    setState(() {
      _visibles = visibles;
      _cargando = false;
    });

    for (final recomendacion in visibles) {
      final id = recomendacion['id']?.toString();
      if (id == null || _marcadas.contains(id)) continue;
      _marcadas.add(id);
      _logic.marcarMostrada(id);
    }
  }

  /// `riesgo_fin_de_mes` siempre primero; el resto conserva el orden recibido.
  List<Map<String, dynamic>> _ordenar(List<Map<String, dynamic>> lista) {
    const tipoRiesgo = 'riesgo_fin_de_mes';
    return [
      ...lista.where((r) => r['tipo'] == tipoRiesgo),
      ...lista.where((r) => r['tipo'] != tipoRiesgo),
    ];
  }

  void _desvanecer(String? id) {
    if (id == null || !mounted) return;
    setState(() => _desvanecidas.add(id));
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return _placeholder();

    final activas = _visibles
        .where((r) => !_desvanecidas.contains(r['id']?.toString()))
        .toList();
    if (activas.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Botón para forzar un recalculo. Solo existe cuando hay tarjetas.
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                onPressed: () => recargar(forzar: true),
                icon: const Icon(Icons.refresh, size: 18),
                color: _gris,
                tooltip: 'Actualizar',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ),
          ),
          for (final recomendacion in activas) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _TarjetaRecomendacionItem(
                key: ValueKey(recomendacion['id']?.toString() ?? ''),
                recomendacion: recomendacion,
                onResponder: (util) {
                  final id = recomendacion['id']?.toString();
                  if (id != null) _logic.responder(id, util);
                },
                onDesvanecida: () => _desvanecer(recomendacion['id']?.toString()),
                onVerLeccion: widget.onVerLeccion,
                onVerMeta: widget.onVerMeta,
              ),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _placeholder() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Container(
        height: 68,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(16),
        ),
      ),
    );
  }
}

class _TarjetaRecomendacionItem extends StatefulWidget {
  const _TarjetaRecomendacionItem({
    super.key,
    required this.recomendacion,
    required this.onResponder,
    required this.onDesvanecida,
    this.onVerLeccion,
    this.onVerMeta,
  });

  final Map<String, dynamic> recomendacion;
  final void Function(bool util) onResponder;
  final VoidCallback onDesvanecida;
  final void Function(String escalonId)? onVerLeccion;
  final VoidCallback? onVerMeta;

  @override
  State<_TarjetaRecomendacionItem> createState() =>
      _TarjetaRecomendacionItemState();
}

class _TarjetaRecomendacionItemState extends State<_TarjetaRecomendacionItem> {
  static const Duration _pausaGracias = Duration(milliseconds: 1400);
  static const Duration _duracionDesvanecido = Duration(milliseconds: 400);

  bool _respondida = false;
  double _opacidad = 1;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _tipo => widget.recomendacion['tipo']?.toString() ?? '';

  Map<String, dynamic> get _datos {
    final datos = widget.recomendacion['datos'];
    return datos is Map ? Map<String, dynamic>.from(datos) : {};
  }

  bool get _esAlerta => _tipo == 'riesgo_fin_de_mes';

  /// Color de error/advertencia del tema de la app.
  Color get _colorAdvertencia => Theme.of(context).colorScheme.error;

  Color get _color {
    switch (_tipo) {
      case 'riesgo_fin_de_mes':
      case 'sobregasto_categoria':
        return _colorAdvertencia;
      case 'gasto_anomalo':
        return _dorado;
      case 'aporte_meta':
      case 'leccion_sugerida':
        return _verde;
      case 'logro':
        return _verdeClaro;
      default:
        return _gris;
    }
  }

  IconData get _icono {
    switch (_tipo) {
      case 'riesgo_fin_de_mes':
        return Icons.warning_amber_outlined;
      case 'sobregasto_categoria':
        return Icons.trending_up_rounded;
      case 'gasto_anomalo':
        return Icons.report_problem_outlined;
      case 'aporte_meta':
        return Icons.flag_outlined;
      case 'leccion_sugerida':
        return Icons.school_outlined;
      case 'logro':
        return Icons.emoji_events_outlined;
      default:
        return Icons.lightbulb_outline;
    }
  }

  void _responder(bool util) {
    if (_respondida) return;
    setState(() => _respondida = true);
    widget.onResponder(util);
    _timer = Timer(_pausaGracias, () {
      if (!mounted) return;
      setState(() => _opacidad = 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacidad,
      duration: _duracionDesvanecido,
      onEnd: () {
        if (_opacidad == 0) widget.onDesvanecida();
      },
      child: _respondida ? _gracias() : _tarjeta(),
    );
  }

  Widget _gracias() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _borde),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_outline, color: _verdeClaro, size: 20),
          const SizedBox(width: 8),
          Text(
            '¡Gracias!',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _texto,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjeta() {
    final texto = widget.recomendacion['texto']?.toString() ?? '';
    final accion = _accion();
    final advertencia = _colorAdvertencia;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _esAlerta
            ? advertencia.withValues(alpha: 0.08)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _esAlerta
              ? advertencia.withValues(alpha: 0.30)
              : _borde,
        ),
        boxShadow: _esAlerta
            ? null
            : const [
                BoxShadow(
                  color: Color(0x0D000000),
                  blurRadius: 4,
                  offset: Offset(0, 1),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(_icono, color: _color, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  texto,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    height: 1.4,
                    color: _texto,
                  ),
                ),
              ),
            ],
          ),
          if (accion != null) ...[
            const SizedBox(height: 12),
            accion,
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              _botonRespuesta('Útil', '👍', true),
              const SizedBox(width: 8),
              _botonRespuesta('No útil', '👎', false),
            ],
          ),
        ],
      ),
    );
  }

  /// Botón de acción contextual: abrir la lección o ir a la meta.
  Widget? _accion() {
    if (_tipo == 'leccion_sugerida') {
      final escalonId = _datos['escalon_id']?.toString();
      final abrir = widget.onVerLeccion;
      if (escalonId == null || escalonId.isEmpty || abrir == null) return null;
      return _botonAccion('Ver lección', () => abrir(escalonId));
    }
    if (_tipo == 'aporte_meta') {
      final navegar = widget.onVerMeta;
      if (navegar == null) return null;
      return _botonAccion('Ver meta', navegar);
    }
    return null;
  }

  Widget _botonAccion(String etiqueta, VoidCallback onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: Color(0xFFDCE3D7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        etiqueta,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _verde,
        ),
      ),
    );
  }

  Widget _botonRespuesta(String etiqueta, String emoji, bool util) {
    return OutlinedButton.icon(
      onPressed: () => _responder(util),
      icon: Text(emoji, style: const TextStyle(fontSize: 13)),
      label: Text(
        etiqueta,
        style: GoogleFonts.poppins(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: _verde,
        ),
      ),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        side: const BorderSide(color: Color(0xFFDCE3D7)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

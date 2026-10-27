import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../logic/recorte_recorrido_logic.dart';
import '../../logic/recorrido_logic.dart';

// ===== Paleta del sistema de diseño =====
const Color _verde = Color(0xFF58774B);
const Color _verdeClaro = Color(0xFF7A9B6C);
const Color _texto = Color(0xFF2B2B2B);
const Color _secundario = Color(0xFF8C8474);
const Color _bordeOscuro = Color(0xFFD8DED1);

/// Duración del desplazamiento del scroll para dejar visible el elemento
/// resaltado.
const Duration _duracionDesplazamiento = Duration(milliseconds: 280);

/// Recorrido guiado (onboarding con "coach marks").
///
/// Oscurece el resto de la pantalla, resalta el elemento del paso actual con un
/// recorte redondeado y muestra una tarjeta con ícono, título, descripción,
/// progreso y los botones "Atrás", "Siguiente"/"¡Empezar!" y "Saltar".
///
/// No navega por su cuenta: los pasos que apuntan a una pestaña solo resaltan
/// su botón. El padre decide qué hacer al terminar ("¡Empezar!") o al saltar.
class RecorridoGuiado extends StatefulWidget {
  const RecorridoGuiado({
    super.key,
    required this.paso,
    required this.pasoActual,
    required this.totalPasos,
    required this.claves,
    required this.clavesDestinos,
    required this.onAnterior,
    required this.onSiguiente,
    required this.onSaltar,
    required this.onFinalizar,
  });

  final PasoTour paso;
  final int pasoActual;
  final int totalPasos;

  /// Claves de los elementos que se pueden resaltar (`'resumen'`, `'navbar'`,
  /// `'fab'`), tomadas de los `GlobalKey` que viven en el `MainShell`.
  final Map<String, GlobalKey> claves;

  /// Claves de los ítems de la barra inferior, en el orden de las pestañas.
  ///
  /// Se mide el `RenderBox` del propio ítem para que el recorte coincida
  /// exactamente con la pestaña (su ícono y su texto).
  final List<GlobalKey> clavesDestinos;

  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;
  final VoidCallback onSaltar;
  final VoidCallback onFinalizar;

  @override
  State<RecorridoGuiado> createState() => _RecorridoGuiadoState();
}

class _RecorridoGuiadoState extends State<RecorridoGuiado> {
  /// Recorte (en coordenadas de pantalla) del elemento resaltado, ya acotado
  /// al área visible. Es `null` en los pasos centrados.
  Rect? _recorte;

  /// Hasta no medir el elemento no se coloca la tarjeta junto a él.
  bool _medido = false;

  /// Reintento pendiente mientras el elemento resaltado aún no está montado.
  Timer? _reintento;

  /// El desplazamiento dentro del scroll se hace una sola vez por paso.
  bool _desplazado = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Aquí llegan la primera medición y los cambios de `MediaQuery`: tamaño de
    // la ventana, rotación de la pantalla o aparición del teclado.
    _medir();
  }

  @override
  void didUpdateWidget(covariant RecorridoGuiado oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pasoActual != widget.pasoActual) {
      // El recorte del paso anterior ya no aplica.
      _desplazado = false;
      _recorte = null;
      _medido = false;
      _medir();
    }
  }

  @override
  void dispose() {
    _reintento?.cancel();
    super.dispose();
  }

  /// El paso actual solo necesita esperar a una medición si debe resaltar algo.
  bool get _requiereResaltado =>
      widget.paso.clave != null || widget.paso.destinoNav != null;

  /// Margen del recorte: más pequeño para los ítems de la barra inferior.
  double get _margenRecorte => widget.paso.destinoNav != null
      ? RecorteRecorridoLogic.margenRecorteBarra
      : RecorteRecorridoLogic.margenRecorte;

  /// Mide el elemento del paso, lo recorta al área visible y, si no se ve
  /// completo y vive dentro de un scroll, lo desplaza y vuelve a medir.
  ///
  /// Reintenta unas cuantas veces por si el elemento aún no está montado (por
  /// ejemplo, las tarjetas del resumen mientras cargan los datos).
  void _medir({int intento = 0}) {
    _reintento?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final objetivo = _rectDelPaso();
      if (objetivo == null && _requiereResaltado && intento < 12) {
        _reintento = Timer(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          _medir(intento: intento + 1);
        });
        return;
      }

      _aplicar(objetivo);

      if (_desplazado || objetivo == null) return;
      _desplazado = true;
      if (await _desplazarSiHaceFalta(objetivo) && mounted) _medir();
    });
  }

  /// Guarda el recorte del paso acotado al área visible.
  void _aplicar(Rect? objetivo) {
    final area = _areaVisible();
    final recorte = objetivo == null
        ? null
        : RecorteRecorridoLogic.recorte(
            objetivo: objetivo,
            area: area,
            margen: _margenRecorte,
          );
    if (!mounted) return;
    setState(() {
      _recorte = recorte;
      _medido = true;
    });
  }

  /// Si el elemento no se ve completo y vive dentro de un área con scroll, lo
  /// desplaza hasta arriba (con animación corta) para que quede visible.
  Future<bool> _desplazarSiHaceFalta(Rect objetivo) async {
    if (RecorteRecorridoLogic.cabeCompleto(objetivo, _areaVisible())) {
      return false;
    }
    final contexto = _contextoDelPaso();
    if (contexto == null || Scrollable.maybeOf(contexto) == null) return false;

    await Scrollable.ensureVisible(
      contexto,
      alignment: 0.0,
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : _duracionDesplazamiento,
      curve: Curves.easeOutCubic,
    );
    return true;
  }

  /// Área visible del recorrido: respeta el área segura y termina donde empieza
  /// la barra inferior, salvo que el propio paso resalte algo que vive dentro
  /// de ella (la barra completa o uno de sus ítems).
  Rect _areaVisible() {
    final objetivo = _rectDelPaso();
    final barra = _rectDe(widget.claves['navbar']);
    return RecorteRecorridoLogic.areaVisible(
      pantalla: MediaQuery.sizeOf(context),
      safeArea: MediaQuery.paddingOf(context),
      barraInferior: barra,
      resaltaBarra:
          barra != null && objetivo != null && objetivo.bottom > barra.top,
    );
  }

  /// Rectángulo del elemento que resalta el paso, en coordenadas de pantalla.
  Rect? _rectDelPaso() {
    final destino = widget.paso.destinoNav;
    if (destino != null) {
      if (destino < 0 || destino >= widget.clavesDestinos.length) return null;
      return _rectDe(widget.clavesDestinos[destino]);
    }
    final clave = widget.paso.clave;
    if (clave == null) return null;
    return _rectDe(widget.claves[clave]);
  }

  /// Contexto del elemento resaltado, para saber si vive dentro de un scroll.
  BuildContext? _contextoDelPaso() {
    final clave = widget.paso.clave;
    if (clave == null) return null;
    return widget.claves[clave]?.currentContext;
  }

  /// Rectángulo de un elemento resaltado, o `null` si aún no está montado.
  Rect? _rectDe(GlobalKey? clave) {
    final contexto = clave?.currentContext;
    if (contexto == null) return null;
    final objeto = contexto.findRenderObject();
    if (objeto is! RenderBox || !objeto.hasSize) return null;
    return objeto.localToGlobal(Offset.zero) & objeto.size;
  }

  @override
  Widget build(BuildContext context) {
    final sinAnimaciones = MediaQuery.of(context).disableAnimations;
    final duracion =
        sinAnimaciones ? Duration.zero : const Duration(milliseconds: 260);
    final recorte = _medido ? _recorte : null;

    return Semantics(
      scopesRoute: true,
      explicitChildNodes: true,
      namesRoute: true,
      label: 'Recorrido guiado',
      child: Material(
        type: MaterialType.transparency,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tamano = Size(constraints.maxWidth, constraints.maxHeight);
            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(painter: _ScrimPainter(recorte: recorte)),
                ),
                // Absorbe los toques para que el resto de la app no reaccione
                // mientras dura el recorrido.
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {},
                  ),
                ),
                _posicionarTarjeta(tamano, recorte, duracion),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Coloca la tarjeta centrada (pasos sin resaltado) o arriba/abajo del
  /// recorte según el espacio libre, con 12 px de separación.
  Widget _posicionarTarjeta(Size tamano, Rect? recorte, Duration duracion) {
    const double margen = 16;
    const double anchoMaximo = 440;
    final anchoTarjeta = (tamano.width - margen * 2).clamp(0.0, anchoMaximo);
    final izquierda =
        ((tamano.width - anchoTarjeta) / 2).clamp(0.0, tamano.width);

    final tarjeta = _TarjetaPaso(
      paso: widget.paso,
      pasoActual: widget.pasoActual,
      totalPasos: widget.totalPasos,
      duracion: duracion,
      onAnterior: widget.onAnterior,
      onSiguiente: widget.onSiguiente,
      onSaltar: widget.onSaltar,
      onFinalizar: widget.onFinalizar,
    );

    if (recorte == null) {
      return Positioned.fill(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(margen),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: anchoMaximo),
              child: _animar(tarjeta, duracion),
            ),
          ),
        ),
      );
    }

    final area = _areaVisible();
    final debajo =
        RecorteRecorridoLogic.tarjetaDebajo(recorte: recorte, area: area);
    final posicion = RecorteRecorridoLogic.posicionTarjeta(
      recorte: recorte,
      area: area,
      altoPantalla: tamano.height,
      debajo: debajo,
      margenPantalla: margen,
    );

    return Positioned(
      left: izquierda,
      width: anchoTarjeta,
      top: debajo ? posicion : null,
      bottom: debajo ? null : posicion,
      child: _animar(tarjeta, duracion),
    );
  }

  /// Entrada suave de cada paso (se re-ejecuta al cambiar de paso).
  Widget _animar(Widget hijo, Duration duracion) {
    return TweenAnimationBuilder<double>(
      key: ValueKey<int>(widget.pasoActual),
      tween: Tween<double>(begin: 0, end: 1),
      duration: duracion,
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, (1 - t) * 12),
          child: child,
        ),
      ),
      child: hijo,
    );
  }
}

/// Oscurece toda la pantalla salvo el recorte ya calculado (que incluye su
/// margen y nunca se sale del área visible), bordeado en verde claro.
class _ScrimPainter extends CustomPainter {
  const _ScrimPainter({required this.recorte});

  final Rect? recorte;

  @override
  void paint(Canvas canvas, Size size) {
    final completo = Offset.zero & size;
    final velo = Paint()..color = const Color(0xB31B1B1B);

    final area = recorte;
    if (area == null) {
      canvas.drawRect(completo, velo);
      return;
    }

    final redondeado = RRect.fromRectAndRadius(area, const Radius.circular(16));

    // Se dibuja el velo y luego se "perfora" el recorte con BlendMode.clear.
    canvas.saveLayer(completo, Paint());
    canvas.drawRect(completo, velo);
    canvas.drawRRect(redondeado, Paint()..blendMode = BlendMode.clear);
    canvas.restore();

    canvas.drawRRect(
      redondeado,
      Paint()
        ..color = _verdeClaro
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant _ScrimPainter oldDelegate) =>
      oldDelegate.recorte != recorte;
}

/// Tarjeta explicativa de un paso: ícono, título, descripción, progreso con
/// puntos y botones de navegación.
class _TarjetaPaso extends StatelessWidget {
  const _TarjetaPaso({
    required this.paso,
    required this.pasoActual,
    required this.totalPasos,
    required this.duracion,
    required this.onAnterior,
    required this.onSiguiente,
    required this.onSaltar,
    required this.onFinalizar,
  });

  final PasoTour paso;
  final int pasoActual;
  final int totalPasos;
  final Duration duracion;
  final VoidCallback onAnterior;
  final VoidCallback onSiguiente;
  final VoidCallback onSaltar;
  final VoidCallback onFinalizar;

  @override
  Widget build(BuildContext context) {
    final esPrimerPaso = pasoActual == 0;
    final esUltimoPaso = pasoActual == totalPasos - 1;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2E000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _verde.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(paso.icono, size: 24, color: _verde),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  paso.titulo,
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _texto,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            paso.descripcion,
            style: GoogleFonts.poppins(
              fontSize: 13.5,
              height: 1.45,
              color: _secundario,
            ),
          ),
          const SizedBox(height: 16),
          _buildPuntos(),
          const SizedBox(height: 10),
          Row(
            children: [
              TextButton(
                onPressed: onSaltar,
                style: TextButton.styleFrom(
                  foregroundColor: _secundario,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Saltar',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: esPrimerPaso ? null : onAnterior,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _verde,
                  side: const BorderSide(color: _bordeOscuro),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Atrás',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: esUltimoPaso ? onFinalizar : onSiguiente,
                style: FilledButton.styleFrom(
                  backgroundColor: _verde,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  minimumSize: const Size(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  esUltimoPaso ? '¡Empezar!' : 'Siguiente',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Indicador de progreso: un punto por paso, alargado el actual.
  Widget _buildPuntos() {
    return Row(
      children: [
        for (int i = 0; i < totalPasos; i++) ...[
          AnimatedContainer(
            duration: duracion,
            curve: Curves.easeOut,
            height: 6,
            width: i == pasoActual ? 18 : 6,
            decoration: BoxDecoration(
              color: i == pasoActual ? _verde : _bordeOscuro,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          if (i < totalPasos - 1) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

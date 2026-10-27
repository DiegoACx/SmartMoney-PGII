import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../logic/asistente_burbuja_logic.dart';

// `PestanaAsistente` forma parte de la API de `FabAsistente` y `fabAsistente`
// (identifican a qué pestaña pertenece cada botón), así que se reexporta para
// que las pantallas que usan el botón no tengan que importar la lógica aparte.
export '../../logic/asistente_burbuja_logic.dart' show PestanaAsistente;

// ===== Paleta del sistema de diseño =====
const Color _verde = Color(0xFF58774B);
const Color _verdeClaro = Color(0xFF7A9B6C);
const Color _texto = Color(0xFF2B2B2B);
const Color _secundario = Color(0xFF8C8474);
const Color _borde = Color(0xFFD8DED1);

/// Sesión del asistente: decide *cuándo* y *dónde* se muestra el globo.
///
/// Vive una sola vez en el `MainShell` y se comparte con el botón de cada
/// pestaña a través de `AsistenteScope`, para que el máximo de 3 apariciones
/// por sesión y el intervalo de 90 s se cuenten globalmente y no por pantalla.
class AsistenteSesion extends ChangeNotifier {
  AsistenteSesion({AsistenteBurbujaLogic? logic})
      : logic = logic ?? AsistenteBurbujaLogic();

  /// Reloj lógico con las reglas puras de aparición del globo.
  final AsistenteBurbujaLogic logic;

  final DateTime _inicio = DateTime.now();

  /// Predicate que define si *ahora* se puede mostrar el globo (teclado
  /// abierto, diálogo/hoja abierta, recorrido activo...). Lo fija el
  /// `MainShell`, que conoce el contexto de la app.
  bool Function()? permitido;

  int _pestanaActiva = 0;
  bool _autoActivo = false;
  bool _pausado = false;
  String? _mensaje;
  PestanaAsistente? _pestanaMensaje;
  Timer? _timerMostrar;
  Timer? _timerOcultar;

  /// Índice de la pestaña actualmente visible.
  int get pestanaActiva => _pestanaActiva;

  /// Tiempo transcurrido desde el inicio de la sesión.
  Duration ahora() => DateTime.now().difference(_inicio);

  /// Mensaje que debe mostrar [pestana] ahora, o `null` si no le corresponde.
  String? mensajePara(PestanaAsistente pestana) =>
      (_mensaje != null && _pestanaMensaje == pestana) ? _mensaje : null;

  /// Activa (o reanuda) el auto-mostrado y programa la siguiente aparición.
  void activar() {
    _autoActivo = true;
    _programar();
  }

  /// Cambia la pestaña activa: oculta lo pendiente y reprograma en ella.
  void cambiarPestana(int indice) {
    if (indice == _pestanaActiva) return;
    _pestanaActiva = indice;
    _ocultar();
    _programar();
  }

  /// Pausa el globo (recorrido guiado activo, app en segundo plano...).
  void pausar() {
    _pausado = true;
    _ocultar();
  }

  /// Reanuda el globo tras una pausa.
  void reanudar() {
    _pausado = false;
    _programar();
  }

  /// El usuario cerró el globo con la X: no vuelve a salir en esta sesión.
  void descartar() {
    logic.descartar();
    _ocultar();
  }

  void _ocultar() {
    _timerMostrar?.cancel();
    _timerOcultar?.cancel();
    if (_mensaje == null) return;
    _mensaje = null;
    _pestanaMensaje = null;
    notifyListeners();
  }

  void _programar() {
    _timerMostrar?.cancel();
    _timerOcultar?.cancel();
    if (!_autoActivo || _pausado) return;
    if (logic.descartado || logic.sesionAgotada) return;

    final pestana = PestanaAsistente.values[_pestanaActiva];
    if (AsistenteBurbujaLogic.mensajesPara(pestana).isEmpty) return;

    // Respeta el intervalo de 90 s y, además, el retraso tras entrar a la
    // pestaña: nunca aparece antes de `retrasoInicial`.
    final restante = logic.restanteHastaSiguiente(ahora());
    final espera = restante > logic.retrasoInicial
        ? restante
        : logic.retrasoInicial;
    _timerMostrar = Timer(espera, _mostrar);
  }

  void _mostrar() {
    if (!_autoActivo || _pausado) return;

    if (permitido != null && !permitido!()) {
      // Reintenta cuando el contexto se libere (teclado/diálogo cerrado).
      _timerMostrar = Timer(const Duration(seconds: 2), _mostrar);
      return;
    }

    final pestana = PestanaAsistente.values[_pestanaActiva];
    final mensaje = logic.registrarAparicion(pestana, ahora());
    if (mensaje == null) return;

    _mensaje = mensaje;
    _pestanaMensaje = pestana;
    notifyListeners();

    _timerOcultar = Timer(logic.duracionVisible, () {
      if (_mensaje == null) return;
      _mensaje = null;
      _pestanaMensaje = null;
      notifyListeners();
      // Programa la siguiente aparición (respetando el intervalo de 90 s).
      _programar();
    });
  }

  @override
  void dispose() {
    _timerMostrar?.cancel();
    _timerOcultar?.cancel();
    super.dispose();
  }
}

/// Expone la [AsistenteSesion] a los botones del asistente de cada pestaña.
///
/// Fuera del `MainShell` (por ejemplo una pantalla empujada como ruta) no
/// existe, y el botón simplemente se dibuja sin globo.
class AsistenteScope extends InheritedNotifier<AsistenteSesion> {
  const AsistenteScope({
    super.key,
    required AsistenteSesion sesion,
    required super.child,
  }) : super(notifier: sesion);

  static AsistenteSesion? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AsistenteScope>()?.notifier;
}

/// Botón circular del asistente con su globo de mensajes.
///
/// [pestana] indica a qué pestaña pertenece, para saber qué mensajes puede
/// mostrar el globo. [heroTag] debe ser único por pantalla: el `MainShell`
/// mantiene todas las pestañas vivas a la vez dentro de un `IndexedStack`, así
/// que dos FAB con el mismo tag dispararían la aserción de `Hero`.
class FabAsistente extends StatefulWidget {
  const FabAsistente({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.pestana,
    this.claveBoton,
  });

  final String heroTag;
  final VoidCallback onPressed;
  final PestanaAsistente pestana;

  /// Clave aplicada al botón circular (no al globo), para que el recorrido
  /// guiado pueda resaltarlo sin incluir el espacio del globo.
  final Key? claveBoton;

  @override
  State<FabAsistente> createState() => _FabAsistenteState();
}

class _FabAsistenteState extends State<FabAsistente>
    with SingleTickerProviderStateMixin {
  /// Animación lenta de "respiración" del anillo (ida y vuelta).
  late final AnimationController _respiracion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  AsistenteSesion? _sesion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sesion = AsistenteScope.maybeOf(context);
    _ajustarRespiracion();
  }

  @override
  void dispose() {
    _respiracion.dispose();
    super.dispose();
  }

  /// Solo respira mientras su pestaña está visible y el sistema permite
  /// animaciones (`MediaQuery.disableAnimations`), para no distraer ni gastar
  /// recursos en las pestañas ocultas del `IndexedStack`.
  void _ajustarRespiracion() {
    if (!mounted) return;
    final sesion = _sesion;
    final activa =
        sesion == null || sesion.pestanaActiva == widget.pestana.index;
    final sinAnimaciones = MediaQuery.of(context).disableAnimations;

    if (activa && !sinAnimaciones) {
      if (!_respiracion.isAnimating) _respiracion.repeat(reverse: true);
    } else if (_respiracion.isAnimating) {
      _respiracion.stop();
      _respiracion.value = 0;
    }
  }

  /// El globo se calla si el teclado está abierto o si hay una ruta encima
  /// (un diálogo o una hoja inferior), igual que pide la experiencia.
  bool _puedeMostrarGlobo() {
    if (MediaQuery.viewInsetsOf(context).bottom > 0) return false;
    final ruta = ModalRoute.of(context);
    if (ruta != null && !ruta.isCurrent) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final sesion = _sesion;
    final mensaje = sesion?.mensajePara(widget.pestana);
    final mostrarGlobo = mensaje != null && _puedeMostrarGlobo();
    final sinAnimaciones = MediaQuery.of(context).disableAnimations;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _GloboAsistente(
          mensaje: mensaje,
          visible: mostrarGlobo,
          sinAnimaciones: sinAnimaciones,
          onAbrir: widget.onPressed,
          onCerrar: () => sesion?.descartar(),
        ),
        const SizedBox(height: 4),
        _BotonCircular(
          key: widget.claveBoton,
          heroTag: widget.heroTag,
          onPressed: widget.onPressed,
          respiracion: _respiracion,
          sinAnimaciones: sinAnimaciones,
        ),
      ],
    );
  }
}

/// FAB del asistente que cambia a la pestaña de IA (índice 1).
///
/// Devuelve `null` cuando la pantalla no tiene forma de cambiar de pestaña
/// (por ejemplo, cuando se abre como ruta independiente y no como pestaña),
/// para no dejar un botón sin efecto.
Widget? fabAsistente({
  required String heroTag,
  required ValueChanged<int>? onCambiarPestana,
  required PestanaAsistente pestana,
  Key? key,
  Key? claveBoton,
}) {
  if (onCambiarPestana == null) return null;
  return FabAsistente(
    key: key,
    heroTag: heroTag,
    pestana: pestana,
    claveBoton: claveBoton,
    onPressed: () => onCambiarPestana(1),
  );
}

/// Botón circular del asistente: fondo blanco, ícono verde y un anillo que
/// "respira" suavemente alrededor.
class _BotonCircular extends StatelessWidget {
  const _BotonCircular({
    super.key,
    required this.heroTag,
    required this.onPressed,
    required this.respiracion,
    required this.sinAnimaciones,
  });

  final String heroTag;
  final VoidCallback onPressed;
  final Animation<double> respiracion;
  final bool sinAnimaciones;

  @override
  Widget build(BuildContext context) {
    const double anillo = 66;
    return Semantics(
      button: true,
      label: 'Abrir asistente',
      child: SizedBox(
        width: anillo,
        height: anillo,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            if (sinAnimaciones)
              _anillo(0.45, 2)
            else
              AnimatedBuilder(
                animation: respiracion,
                builder: (_, _) {
                  final t = Curves.easeInOut.transform(respiracion.value);
                  return _anillo(0.25 + 0.45 * t, 2 + 1.6 * t);
                },
              ),
            FloatingActionButton(
              heroTag: heroTag,
              onPressed: onPressed,
              tooltip: 'Asistente',
              elevation: 3,
              backgroundColor: Colors.white,
              foregroundColor: _verde,
              shape: const CircleBorder(),
              child: const Icon(Icons.support_agent_rounded, size: 26),
            ),
          ],
        ),
      ),
    );
  }

  Widget _anillo(double opacidad, double grosor) {
    return IgnorePointer(
      child: Container(
        width: 66,
        height: 66,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: _verdeClaro.withValues(alpha: opacidad),
            width: grosor,
          ),
        ),
      ),
    );
  }
}

/// Globo de mensaje estilo cómic, con colita apuntando al botón.
///
/// Siempre está en el árbol (para que aparezca/desaparezca con una animación
/// suave sin saltos de layout) y se vuelve transparente e inerte al ocultarse.
class _GloboAsistente extends StatelessWidget {
  const _GloboAsistente({
    required this.mensaje,
    required this.visible,
    required this.sinAnimaciones,
    required this.onAbrir,
    required this.onCerrar,
  });

  final String? mensaje;
  final bool visible;
  final bool sinAnimaciones;
  final VoidCallback onAbrir;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    final anchoPantalla = MediaQuery.sizeOf(context).width;
    // Deja sitio al botón (a la derecha) y evita que el globo se salga a 360 px.
    final anchoGlobo = (anchoPantalla - 104).clamp(168.0, 264.0);
    final duracion =
        sinAnimaciones ? Duration.zero : const Duration(milliseconds: 240);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duracion,
        curve: Curves.easeOut,
        child: AnimatedScale(
          scale: visible ? 1 : 0.9,
          alignment: Alignment.bottomRight,
          duration: duracion,
          curve: Curves.easeOutBack,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: anchoGlobo),
                child: _TarjetaGlobo(
                  mensaje: mensaje ?? '',
                  onAbrir: onAbrir,
                  onCerrar: onCerrar,
                ),
              ),
              // Colita que apunta al botón (alineada sobre su centro).
              Padding(
                padding: const EdgeInsets.only(right: 22),
                child: Transform.translate(
                  offset: const Offset(0, -1),
                  child: const CustomPaint(
                    size: Size(18, 10),
                    painter: _ColitaPainter(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tarjeta blanca del globo: mensaje, ícono del asistente y botón de cerrar.
class _TarjetaGlobo extends StatelessWidget {
  const _TarjetaGlobo({
    required this.mensaje,
    required this.onAbrir,
    required this.onCerrar,
  });

  final String mensaje;
  final VoidCallback onAbrir;
  final VoidCallback onCerrar;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onAbrir,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _borde),
            boxShadow: const [
              BoxShadow(
                color: Color(0x14000000),
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.support_agent_rounded, size: 20, color: _verde),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  mensaje,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    height: 1.3,
                    color: _texto,
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Cerrar mensaje',
                child: InkResponse(
                  onTap: onCerrar,
                  radius: 18,
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: _secundario,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Dibuja la colita triangular del globo (rellena en blanco y con el borde
/// solo en los lados inclinados, para que la base quede "pegada" a la tarjeta).
class _ColitaPainter extends CustomPainter {
  const _ColitaPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final relleno = Paint()..color = Colors.white;
    final borde = Paint()
      ..color = _borde
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final camino = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    canvas.drawPath(camino, relleno);
    canvas.drawLine(Offset(0, 0), Offset(size.width / 2, size.height), borde);
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width / 2, size.height),
      borde,
    );
  }

  @override
  bool shouldRepaint(covariant _ColitaPainter oldDelegate) => false;
}

/// Pestañas de la app que pueden mostrar el globo del asistente.
///
/// El orden coincide con el `IndexedStack` del `MainShell`:
/// Inicio, IA, Educación, Ingresos, Metas, Perfil.
enum PestanaAsistente { inicio, ia, educacion, ingresos, metas, perfil }

/// Lógica **pura** del globo de mensajes del asistente.
///
/// Decide *cuándo* puede aparecer el globo (retraso tras entrar a la pestaña,
/// duración visible, intervalo mínimo de 90 s, máximo 3 por sesión) y *qué*
/// mensaje mostrar, rotando las opciones de cada pestaña. No usa timers ni
/// widgets: recibe el instante actual como `Duration` para poder probarse.
class AsistenteBurbujaLogic {
  AsistenteBurbujaLogic({
    this.retrasoInicial = const Duration(seconds: 3),
    this.duracionVisible = const Duration(seconds: 6),
    this.intervaloEntreApariciones = const Duration(seconds: 90),
    this.maxAparicionesPorSesion = 3,
  });

  /// Tiempo que se espera desde que se entra a una pestaña hasta que aparece.
  final Duration retrasoInicial;

  /// Tiempo que el globo permanece visible antes de ocultarse solo.
  final Duration duracionVisible;

  /// Tiempo mínimo entre dos apariciones mientras el usuario sigue en la app.
  final Duration intervaloEntreApariciones;

  /// Número máximo de apariciones por sesión.
  final int maxAparicionesPorSesion;

  /// Mensajes por pestaña. `ia` no tiene botón, por eso su lista está vacía.
  static const Map<PestanaAsistente, List<String>> mensajesPorPestana = {
    PestanaAsistente.inicio: [
      '¡Hola! Soy tu asistente. ¿Vemos en qué se te va la plata?',
      '¿Quieres saber cuánto llevas gastado este mes?',
    ],
    PestanaAsistente.ingresos: [
      '¿Te ayudo a entender tus gastos?',
      'Pregúntame en qué categoría gastas más.',
    ],
    PestanaAsistente.metas: [
      '¿Simulamos cuándo llegas a tu meta?',
      'Si ahorras un poco más, ¿cuánto antes llegas? Pregúntame.',
    ],
    PestanaAsistente.educacion: [
      '¿Te explico algún concepto financiero?',
      '¿Qué es un CDT? ¿Y la tasa de interés? Pregúntame.',
    ],
    PestanaAsistente.perfil: [
      '¿Tienes dudas sobre cómo usar la app? Te ayudo.',
    ],
    PestanaAsistente.ia: [],
  };

  int _apariciones = 0;
  bool _descartado = false;
  Duration? _ultimaAparicionEn;
  final Map<PestanaAsistente, int> _rotacionPorPestana = {};

  /// Apariciones mostradas en la sesión actual.
  int get apariciones => _apariciones;

  /// true si el usuario cerró el globo con la X (no vuelve a salir).
  bool get descartado => _descartado;

  /// true si ya se alcanzó el máximo de apariciones por sesión.
  bool get sesionAgotada => _apariciones >= maxAparicionesPorSesion;

  /// Mensajes configurados para [pestana] (lista vacía si no tiene).
  static List<String> mensajesPara(PestanaAsistente pestana) =>
      mensajesPorPestana[pestana] ?? const [];

  /// Devuelve el siguiente mensaje de [pestana] rotando la lista, o `null`
  /// si esa pestaña no tiene mensajes. Cada llamada avanza la rotación.
  String? siguienteMensaje(PestanaAsistente pestana) {
    final lista = mensajesPara(pestana);
    if (lista.isEmpty) return null;
    final indice = (_rotacionPorPestana[pestana] ?? 0) % lista.length;
    _rotacionPorPestana[pestana] = (indice + 1) % lista.length;
    return lista[indice];
  }

  /// Indica si en el instante [ahora] se puede volver a mostrar el globo.
  ///
  /// No se puede si el usuario lo descartó, si ya se agotó el máximo de la
  /// sesión o si no han pasado [intervaloEntreApariciones] desde la última.
  bool puedeMostrar(Duration ahora) {
    if (_descartado || sesionAgotada) return false;
    final ultima = _ultimaAparicionEn;
    if (ultima != null && ahora - ultima < intervaloEntreApariciones) {
      return false;
    }
    return true;
  }

  /// Tiempo que aún falta para poder volver a mostrar el globo en [ahora].
  ///
  /// Devuelve `Duration.zero` si nunca se ha mostrado o si el intervalo ya se
  /// cumplió. Sirve para reprogramar la siguiente aparición sin "adivinar".
  Duration restanteHastaSiguiente(Duration ahora) {
    final ultima = _ultimaAparicionEn;
    if (ultima == null) return Duration.zero;
    final restante = intervaloEntreApariciones - (ahora - ultima);
    return restante.isNegative ? Duration.zero : restante;
  }

  /// Registra una aparición en [ahora] y devuelve el mensaje que debe
  /// mostrarse, o `null` si aún no corresponde mostrarlo.
  String? registrarAparicion(PestanaAsistente pestana, Duration ahora) {
    if (!puedeMostrar(ahora)) return null;
    final mensaje = siguienteMensaje(pestana);
    if (mensaje == null) return null;
    _apariciones++;
    _ultimaAparicionEn = ahora;
    return mensaje;
  }

  /// El usuario cerró el globo: no vuelve a aparecer en esta sesión.
  void descartar() {
    _descartado = true;
  }

  /// Reinicia el estado para una nueva sesión (login).
  void reiniciarSesion() {
    _apariciones = 0;
    _descartado = false;
    _ultimaAparicionEn = null;
    _rotacionPorPestana.clear();
  }
}

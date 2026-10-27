import 'package:flutter/material.dart';

/// Un paso del recorrido guiado.
///
/// [clave] apunta a un elemento a resaltar dentro del mapa de `GlobalKey`s del
/// `MainShell` (por ejemplo `'resumen'`, `'navbar'`, `'fab'`). [destinoNav] es
/// el índice del destino de la barra de navegación a resaltar (las pestañas).
/// Cuando ambos son `null` el paso es **centrado** y no resalta nada.
class PasoTour {
  final String id;
  final IconData icono;
  final String titulo;
  final String descripcion;
  final String? clave;
  final int? destinoNav;

  const PasoTour({
    required this.id,
    required this.icono,
    required this.titulo,
    required this.descripcion,
    this.clave,
    this.destinoNav,
  });

  bool get centrado => clave == null && destinoNav == null;
}

/// Lógica **pura** del recorrido guiado (onboarding con "coach marks").
///
/// Guarda el paso actual y si el recorrido está visible, y resuelve la llave
/// de "ya visto" por usuario. La persistencia real (shared_preferences) vive
/// en `PreferenciasService`; aquí solo se calcula el nombre de la llave.
///
/// Extiende `ChangeNotifier` para que la vista del recorrido se reconstruya
/// sola cuando cambia el paso; no conoce widgets ni navegación.
class RecorridoLogic extends ChangeNotifier {
  /// Pasos del recorrido, en orden.
  static const List<PasoTour> pasos = [
    PasoTour(
      id: 'bienvenida',
      icono: Icons.waving_hand_rounded,
      titulo: '¡Bienvenido a SmartMoney!',
      descripcion:
          'Te mostramos en 1 minuto cómo sacarle provecho.',
    ),
    PasoTour(
      id: 'resumen',
      icono: Icons.insights_rounded,
      titulo: 'Tu resumen del periodo',
      descripcion:
          'Aquí ves cuánto entró, cuánto salió y cuánto te quedó en el '
          'periodo que elijas.',
      clave: 'resumen',
    ),
    PasoTour(
      id: 'navbar',
      icono: Icons.explore_rounded,
      titulo: 'Muévete por la app',
      descripcion: 'Desde aquí te mueves por toda la app.',
      clave: 'navbar',
    ),
    PasoTour(
      id: 'ia',
      icono: Icons.auto_awesome,
      titulo: 'Tu asistente',
      descripcion:
          'Pregúntale por tus gastos, simula ahorros o aprende conceptos.',
      destinoNav: 1,
    ),
    PasoTour(
      id: 'educacion',
      icono: Icons.school_rounded,
      titulo: 'Educación financiera',
      descripcion:
          'Lecciones cortas para mejorar tus finanzas, paso a paso.',
      destinoNav: 2,
    ),
    PasoTour(
      id: 'ingresos',
      icono: Icons.swap_horiz_rounded,
      titulo: 'Ingresos y gastos',
      descripcion:
          'Registra aquí tus ingresos y gastos. Al describir un gasto, te '
          'sugerimos la categoría.',
      destinoNav: 3,
    ),
    PasoTour(
      id: 'metas',
      icono: Icons.flag_rounded,
      titulo: 'Tus metas',
      descripcion: 'Crea metas de ahorro y sigue tu avance.',
      destinoNav: 4,
    ),
    PasoTour(
      id: 'perfil',
      icono: Icons.person_rounded,
      titulo: 'Tu perfil',
      descripcion:
          'Tu información, tu contraseña y las opciones de tu cuenta.',
      destinoNav: 5,
    ),
    PasoTour(
      id: 'asistente',
      icono: Icons.support_agent_rounded,
      titulo: 'El asistente siempre a mano',
      descripcion:
          'Y en cualquier pantalla, este botón te lleva al asistente.',
      clave: 'fab',
    ),
    PasoTour(
      id: 'cierre',
      icono: Icons.rocket_launch_rounded,
      titulo: '¡Listo!',
      descripcion: 'Empieza registrando tu primer movimiento.',
    ),
  ];

  int _pasoActual = 0;
  bool _visible = false;

  int get pasoActual => _pasoActual;
  PasoTour get paso => pasos[_pasoActual];
  bool get visible => _visible;
  int get totalPasos => pasos.length;
  bool get esPrimerPaso => _pasoActual == 0;
  bool get esUltimoPaso => _pasoActual == pasos.length - 1;

  /// Inicia el recorrido desde el primer paso.
  void iniciar() {
    _pasoActual = 0;
    _visible = true;
    notifyListeners();
  }

  /// Salta a un paso concreto (sin salir del rango válido).
  void irA(int indice) {
    if (indice < 0 || indice >= pasos.length) return;
    if (indice == _pasoActual) return;
    _pasoActual = indice;
    notifyListeners();
  }

  /// Avanza al siguiente paso (no hace nada en el último).
  void siguiente() => irA(_pasoActual + 1);

  /// Retrocede al paso anterior (no hace nada en el primero).
  void retroceder() => irA(_pasoActual - 1);

  /// Cierra el recorrido (botón "Saltar", cierre anticipado o botón atrás).
  void saltar() {
    if (!_visible) return;
    _visible = false;
    notifyListeners();
  }

  /// Cierra el recorrido al terminarlo ("¡Empezar!").
  void finalizar() => saltar();

  /// Llave de shared_preferences para saber si [usuarioId] ya vio el recorrido.
  static String claveVisto(String usuarioId) => 'recorrido_visto_$usuarioId';
}

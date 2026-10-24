import 'package:flutter/material.dart';

/// Botón flotante pequeño del asistente. Se usa en todas las pestañas menos
/// en la del propio asistente (IA).
///
/// [heroTag] debe ser único por pantalla: `MainShell` mantiene todas las
/// pestañas vivas a la vez dentro de un `IndexedStack`, así que dos FAB con el
/// mismo tag dispararían la aserción de `Hero`.
class FabAsistente extends StatelessWidget {
  const FabAsistente({
    super.key,
    required this.heroTag,
    required this.onPressed,
  });

  final String heroTag;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.small(
      heroTag: heroTag,
      onPressed: onPressed,
      tooltip: 'Asistente',
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF58774B),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Color(0xFFDCE3D7)),
      ),
      child: const Icon(Icons.chat_bubble_outline, size: 20),
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
}) {
  if (onCambiarPestana == null) return null;
  return FabAsistente(
    heroTag: heroTag,
    onPressed: () => onCambiarPestana(1),
  );
}

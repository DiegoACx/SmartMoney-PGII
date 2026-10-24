import 'package:flutter/material.dart';

import '../../logic/auth_logic.dart';
import '../../logic/educacion_logic.dart';
import '../escalon_detalle_screen.dart';

/// Abre la lección [escalonId] con la misma lógica que usa el Dashboard:
/// la busca en el árbol de educación y, si está desbloqueada y disponible,
/// abre `EscalonDetalleScreen`. Si no se puede abrir, cambia a la pestaña de
/// Educación mediante [onCambiarPestana] (índice 2).
///
/// Se extrajo a este helper para no duplicar código entre el Dashboard
/// (`home_screen.dart`) y el chat del asistente.
///
/// [niveles] es el árbol ya cargado cuando quien llama lo tiene a mano; si es
/// null, se consulta con `EducacionLogic`.
Future<void> abrirLeccion({
  required BuildContext context,
  required String escalonId,
  ValueChanged<int>? onCambiarPestana,
  List<NivelConEstado>? niveles,
}) async {
  var arbol = niveles;

  if (arbol == null) {
    try {
      final usuarioId = AuthLogic().obtenerUsuarioId();
      if (usuarioId != null) {
        arbol = await EducacionLogic().cargarArbolCompleto(usuarioId);
      }
    } catch (e) {
      debugPrint('ERROR AL CARGAR EDUCACION PARA ABRIR LA LECCION: $e');
    }
  }

  EscalonConEstado? escalonEncontrado;
  NivelConEstado? nivelEncontrado;
  for (final nivel in arbol ?? const <NivelConEstado>[]) {
    for (final escalon in nivel.escalones) {
      if (escalon.id == escalonId) {
        escalonEncontrado = escalon;
        nivelEncontrado = nivel;
        break;
      }
    }
    if (escalonEncontrado != null) break;
  }

  final escalon = escalonEncontrado;
  final nivel = nivelEncontrado;
  if (escalon != null &&
      nivel != null &&
      escalon.desbloqueado &&
      escalon.disponible) {
    if (!context.mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EscalonDetalleScreen(escalon: escalon, nivel: nivel),
      ),
    );
    return;
  }

  onCambiarPestana?.call(2);
}

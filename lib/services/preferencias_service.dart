import 'package:shared_preferences/shared_preferences.dart';

import '../logic/recorrido_logic.dart';

/// Preferencias del dispositivo del usuario (capa de servicios).
///
/// Solo lee/escribe valores locales; no contiene validaciones ni cálculos.
class PreferenciasService {
  static const String _claveNotificaciones = 'notificaciones_habilitadas';

  /// Indica si las notificaciones están habilitadas. Por defecto `true`.
  Future<bool> leerNotificacionesActivas() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_claveNotificaciones) ?? true;
  }

  /// Guarda la preferencia de notificaciones.
  Future<void> guardarNotificacionesActivas(bool activas) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_claveNotificaciones, activas);
  }

  /// Indica si [usuarioId] ya vio el recorrido guiado. Por defecto `false`.
  ///
  /// La llave incluye el id del usuario, así el recorrido se muestra una sola
  /// vez por persona aunque compartan dispositivo.
  Future<bool> leerRecorridoVisto(String usuarioId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(RecorridoLogic.claveVisto(usuarioId)) ?? false;
  }

  /// Marca que [usuarioId] ya vio el recorrido guiado.
  Future<void> guardarRecorridoVisto(
    String usuarioId,
    bool visto,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(RecorridoLogic.claveVisto(usuarioId), visto);
  }
}

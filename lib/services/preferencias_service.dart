import 'package:shared_preferences/shared_preferences.dart';

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
}

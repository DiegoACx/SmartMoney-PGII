import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

import 'preferencias_service.dart';

class NotificacionesService {
  /// Id fijo de la notificación inmediata de prueba (fuera del rango de los
  /// ids derivados de las metas).
  static const int _idNotificacionPrueba = 1000000;

  final _plugin = FlutterLocalNotificationsPlugin();
  final _preferencias = PreferenciasService();

  Future<void> inicializar() async {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Bogota'));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings();
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _plugin.initialize(settings: settings);

    await solicitarPermiso();
  }

  /// Pide el permiso del sistema para mostrar notificaciones.
  /// Devuelve `true` si quedó concedido.
  Future<bool> solicitarPermiso() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final concedidoAndroid = await android?.requestNotificationsPermission();

    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);

    // En Android devuelve null si la versión no lo requiere.
    return concedidoAndroid ?? true;
  }

  int _idParaMeta(String metaId) => metaId.hashCode & 0x7fffffff;

  /// Programa (o reprograma) el recordatorio de una meta para [fecha].
  ///
  /// No programa nada en web (no hay notificaciones programadas), ni si el
  /// usuario desactivó las notificaciones, ni si [fecha] ya pasó. Cualquier
  /// fallo del sistema se registra y se ignora: un problema de notificaciones
  /// nunca debe romper el guardado de la meta.
  Future<void> programarRecordatorio({
    required String metaId,
    required String nombreMeta,
    required DateTime fecha,
  }) async {
    if (kIsWeb) return;
    if (!fecha.isAfter(DateTime.now())) return;

    try {
      final activas = await _preferencias.leerNotificacionesActivas();
      if (!activas) return;

      const androidDetails = AndroidNotificationDetails(
        'metas_recordatorios',
        'Recordatorios de metas',
        channelDescription:
            'Notificaciones sobre el progreso de tus metas de ahorro',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
      );
      const details = NotificationDetails(android: androidDetails);

      await _plugin.zonedSchedule(
        id: _idParaMeta(metaId),
        scheduledDate: tz.TZDateTime.from(fecha, tz.local),
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: 'Recordatorio de tu meta',
        body:
            "Tu meta '$nombreMeta' se acerca a su fecha límite. ¡Sigue ahorrando!",
      );
    } catch (e) {
      debugPrint('ERROR AL PROGRAMAR RECORDATORIO (meta $metaId): $e');
    }
  }

  /// Muestra una notificación inmediata de prueba.
  ///
  /// No se programa para más tarde: aparece al instante para que el usuario
  /// compruebe que el sistema de notificaciones funciona.
  Future<void> mostrarNotificacionDePrueba() async {
    if (kIsWeb) return;

    const androidDetails = AndroidNotificationDetails(
      'prueba_notificaciones',
      'Pruebas de notificaciones',
      channelDescription: 'Aviso inmediato para comprobar las notificaciones',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(android: androidDetails);

    await _plugin.show(
      id: _idNotificacionPrueba,
      title: 'SmartMoney',
      body: '¡Las notificaciones de SmartMoney funcionan!',
      notificationDetails: details,
    );
  }

  Future<void> cancelarRecordatorio(String metaId) async {
    await _plugin.cancel(id: _idParaMeta(metaId));
  }

  /// Cancela todos los recordatorios programados.
  Future<void> cancelarTodos() async {
    await _plugin.cancelAll();
  }
}

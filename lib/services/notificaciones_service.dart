import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;

class NotificacionesService {
  final _plugin = FlutterLocalNotificationsPlugin();

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

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(alert: true, badge: true, sound: true);
  }

  int _idParaMeta(String metaId) => metaId.hashCode & 0x7fffffff;

  Future<void> programarRecordatorio({
    required String metaId,
    required String nombreMeta,
    required DateTime fecha,
  }) async {
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
  }

  Future<void> cancelarRecordatorio(String metaId) async {
    await _plugin.cancel(id: _idParaMeta(metaId));
  }
}

import 'package:flutter/foundation.dart';

import '../data/perfil_repository.dart';
import '../services/notificaciones_service.dart';
import '../services/preferencias_service.dart';
import 'auth_logic.dart';
import 'educacion_logic.dart';
import 'metas_logic.dart';
import 'transacciones_logic.dart';

/// Tiempo máximo que se espera a cada paso de notificaciones para que un
/// fallo del sistema nunca bloquee la interfaz.
const Duration _timeoutNotificaciones = Duration(seconds: 5);

/// Resultado de una operación del perfil: éxito o error con mensaje
/// en español. Sigue el patrón de resultados del proyecto.
class ResultadoPerfil {
  final String? error;

  const ResultadoPerfil.exito() : error = null;
  const ResultadoPerfil.error(this.error);

  bool get exito => error == null;
}

/// Resumen de actividad del usuario para la tarjeta principal del perfil.
class ResumenActividad {
  final int totalMovimientos;
  final int metasActivas;
  final int metasCumplidas;
  final int leccionesCompletadas;
  final int totalLecciones;
  final String? nivelActualNombre;
  final String? nivelActualColorHex;

  const ResumenActividad({
    required this.totalMovimientos,
    required this.metasActivas,
    required this.metasCumplidas,
    required this.leccionesCompletadas,
    required this.totalLecciones,
    required this.nivelActualNombre,
    required this.nivelActualColorHex,
  });
}

/// Lógica de la pestaña PERFIL: validaciones, iniciales y resumen de
/// actividad. No importa `supabase_flutter`; delega los datos en los
/// repositorios y reutiliza la lógica existente de otras áreas.
class PerfilLogic {
  late final PerfilRepository _repository = PerfilRepository();
  late final AuthLogic _authLogic = AuthLogic();
  late final TransaccionesLogic _transaccionesLogic = TransaccionesLogic();
  late final MetasLogic _metasLogic = MetasLogic();
  late final EducacionLogic _educacionLogic = EducacionLogic();
  late final PreferenciasService _preferenciasService = PreferenciasService();
  late final NotificacionesService _notificacionesService =
      NotificacionesService();

  /// Valida el nombre: no vacío, entre 2 y 50 caracteres y sin espacios
  /// al inicio ni al final. Devuelve null si es válido.
  String? validarNombre(String nombre) {
    if (nombre.trim().isEmpty) {
      return 'El nombre no puede estar vacío';
    }
    if (nombre != nombre.trim()) {
      return 'El nombre no puede tener espacios al inicio ni al final';
    }
    final longitud = nombre.trim().length;
    if (longitud < 2) {
      return 'El nombre debe tener al menos 2 caracteres';
    }
    if (longitud > 50) {
      return 'El nombre no puede superar los 50 caracteres';
    }
    return null;
  }

  /// Valida un cambio de contraseña. La nueva cumple las mismas reglas del
  /// registro (mínimo 8 caracteres), debe ser distinta de la actual y la
  /// confirmación debe coincidir. Devuelve null si es válido.
  String? validarCambioContrasena({
    required String actual,
    required String nueva,
    required String confirmacion,
  }) {
    if (actual.isEmpty) {
      return 'Ingresa tu contraseña actual';
    }
    if (nueva.isEmpty) {
      return 'La nueva contraseña no puede estar vacía';
    }
    if (nueva.length < 8) {
      return 'La nueva contraseña debe tener al menos 8 caracteres';
    }
    if (nueva == actual) {
      return 'La nueva contraseña debe ser diferente a la actual';
    }
    if (confirmacion != nueva) {
      return 'Las contraseñas no coinciden';
    }
    return null;
  }

  /// Devuelve hasta 2 iniciales en mayúscula a partir del nombre.
  /// Si el nombre está vacío, usa la primera letra del correo. Si tampoco
  /// hay correo, devuelve cadena vacía.
  String obtenerIniciales(String? nombre, {String? correo}) {
    final limpio = (nombre ?? '').trim();
    if (limpio.isNotEmpty) {
      final palabras = limpio
          .split(RegExp(r'\s+'))
          .where((p) => p.isNotEmpty)
          .take(2)
          .toList();
      return palabras.map((p) => p[0].toUpperCase()).join();
    }

    final correoLimpio = (correo ?? '').trim();
    if (correoLimpio.isNotEmpty) {
      return correoLimpio[0].toUpperCase();
    }
    return '';
  }

  /// Obtiene el nombre y el correo del usuario autenticado.
  /// Ante cualquier error devuelve valores vacíos para no romper la UI.
  Future<Map<String, dynamic>> obtenerPerfil() async {
    try {
      return await _repository.obtenerPerfil();
    } catch (e) {
      debugPrint('ERROR AL OBTENER PERFIL: $e');
      return {'nombre': '', 'correo': ''};
    }
  }

  /// Conteo de actividad del usuario: movimientos, metas y lecciones, además
  /// del nivel actual. Reutiliza las lógicas existentes sin duplicar consultas.
  /// Devuelve null si no hay sesión o si falla alguna consulta (nunca ceros
  /// falsos).
  Future<ResumenActividad?> obtenerResumenActividad() async {
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) return null;

    try {
      final transacciones =
          await _transaccionesLogic.obtenerTodasLasTransacciones(usuarioId);
      final metas = await _metasLogic.obtenerMetas(usuarioId);
      final niveles = await _educacionLogic.cargarArbolCompleto(usuarioId);

      final metasCumplidas = metas.where((m) => m['cumplida'] == true).length;
      final metasActivas = metas.length - metasCumplidas;

      final escalones = [for (final n in niveles) ...n.escalones];
      final lecciones = escalones.where((e) => e.tipo == 'leccion').toList();
      final leccionesCompletadas =
          lecciones.where((e) => e.completado).length;

      // Nivel actual: el del primer escalón desbloqueado y no completado en
      // orden lógico. Se ordenan niveles y escalones por su campo 'orden'
      // antes de recorrerlos. Si todo está completado, se usa el último nivel.
      final nivelesOrdenados = List<NivelConEstado>.from(niveles)
        ..sort((a, b) => _ordenNivel(a).compareTo(_ordenNivel(b)));

      NivelConEstado? nivelActual;
      for (final nivel in nivelesOrdenados) {
        final escalonesOrdenados = List<EscalonConEstado>.from(nivel.escalones)
          ..sort((a, b) => _ordenEscalon(a).compareTo(_ordenEscalon(b)));
        for (final escalon in escalonesOrdenados) {
          if (escalon.desbloqueado && !escalon.completado) {
            nivelActual = nivel;
            break;
          }
        }
        if (nivelActual != null) break;
      }
      nivelActual ??=
          nivelesOrdenados.isNotEmpty ? nivelesOrdenados.last : null;

      return ResumenActividad(
        totalMovimientos: transacciones.length,
        metasActivas: metasActivas,
        metasCumplidas: metasCumplidas,
        leccionesCompletadas: leccionesCompletadas,
        totalLecciones: lecciones.length,
        nivelActualNombre: nivelActual?.nombre,
        nivelActualColorHex: nivelActual?.colorHex,
      );
    } catch (e) {
      debugPrint('ERROR AL OBTENER RESUMEN DE ACTIVIDAD: $e');
      return null;
    }
  }

  /// Orden de un nivel según su campo 'orden' (num o texto parseable).
  int _ordenNivel(NivelConEstado n) {
    final raw = n.nivel['orden'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  /// Orden de un escalón según su campo 'orden' (num o texto parseable).
  int _ordenEscalon(EscalonConEstado e) {
    final raw = e.escalon['orden'];
    if (raw is num) return raw.toInt();
    return int.tryParse(raw.toString()) ?? 0;
  }

  /// Valida y actualiza el nombre del usuario autenticado.
  Future<ResultadoPerfil> cambiarNombre(String nombre) async {
    final error = validarNombre(nombre);
    if (error != null) return ResultadoPerfil.error(error);

    if (_authLogic.obtenerUsuarioId() == null) {
      return const ResultadoPerfil.error(
        'No hay una sesión activa. Inicia sesión de nuevo.',
      );
    }

    try {
      await _repository.actualizarNombre(nombre.trim());
      return const ResultadoPerfil.exito();
    } catch (e) {
      debugPrint('ERROR AL CAMBIAR NOMBRE: $e');
      if (e.toString().toLowerCase().contains('ninguna fila')) {
        return const ResultadoPerfil.error(
          'No se pudo guardar tu nombre. Cierra sesión, vuelve a ingresar e inténtalo de nuevo.',
        );
      }
      return const ResultadoPerfil.error(
        'No se pudo actualizar el nombre. Revisa tu conexión e inténtalo de nuevo.',
      );
    }
  }

  /// Valida y cambia la contraseña del usuario autenticado.
  Future<ResultadoPerfil> cambiarContrasena({
    required String actual,
    required String nueva,
    required String confirmacion,
  }) async {
    final error = validarCambioContrasena(
      actual: actual,
      nueva: nueva,
      confirmacion: confirmacion,
    );
    if (error != null) return ResultadoPerfil.error(error);

    if (_authLogic.obtenerUsuarioId() == null) {
      return const ResultadoPerfil.error(
        'No hay una sesión activa. Inicia sesión de nuevo.',
      );
    }

    try {
      await _repository.cambiarContrasena(
        contrasenaActual: actual,
        contrasenaNueva: nueva,
      );
      return const ResultadoPerfil.exito();
    } catch (e) {
      debugPrint('ERROR AL CAMBIAR CONTRASEÑA: $e');
      return ResultadoPerfil.error(_mensajeAmigableContrasena(e));
    }
  }

  /// Indica si el usuario tiene las notificaciones habilitadas.
  /// Ante cualquier fallo del dispositivo devuelve el valor por defecto.
  Future<bool> obtenerNotificacionesActivas() async {
    try {
      return await _preferenciasService
          .leerNotificacionesActivas()
          .timeout(_timeoutNotificaciones);
    } catch (e) {
      debugPrint('ERROR AL LEER PREFERENCIA DE NOTIFICACIONES: $e');
      return true;
    }
  }

  /// Guarda la preferencia de notificaciones y aplica el efecto:
  /// al desactivar cancela todos los recordatorios; al activar pide el
  /// permiso del sistema y reprograma los recordatorios de las metas activas
  /// con fecha límite futura. Cada paso va aislado y con timeout para no
  /// romper el flujo principal.
  Future<ResultadoPerfil> cambiarNotificaciones(bool activas) async {
    try {
      await _preferenciasService
          .guardarNotificacionesActivas(activas)
          .timeout(_timeoutNotificaciones);
    } catch (e) {
      debugPrint('ERROR AL GUARDAR PREFERENCIA DE NOTIFICACIONES: $e');
      return const ResultadoPerfil.error(
        'No se pudo guardar tu preferencia. Inténtalo de nuevo.',
      );
    }

    if (!activas) {
      try {
        await _notificacionesService
            .cancelarTodos()
            .timeout(_timeoutNotificaciones);
      } catch (e) {
        debugPrint('ERROR AL CANCELAR NOTIFICACIONES: $e');
      }
      return const ResultadoPerfil.exito();
    }

    // Se activaron: primero el permiso del sistema.
    bool permisoConcedido;
    try {
      permisoConcedido = await _notificacionesService
          .solicitarPermiso()
          .timeout(_timeoutNotificaciones);
    } catch (e) {
      debugPrint('ERROR AL PEDIR PERMISO DE NOTIFICACIONES: $e');
      permisoConcedido = false;
    }

    if (!permisoConcedido) {
      // Se revierte la preferencia: sin permiso no tiene sentido guardarla.
      try {
        await _preferenciasService
            .guardarNotificacionesActivas(false)
            .timeout(_timeoutNotificaciones);
      } catch (e) {
        debugPrint('ERROR AL REVERTIR PREFERENCIA DE NOTIFICACIONES: $e');
      }
      return const ResultadoPerfil.error(
        'Activa los permisos de notificaciones en los ajustes del sistema',
      );
    }

    await _reprogramarRecordatoriosDeMetas();
    return const ResultadoPerfil.exito();
  }

  /// Muestra una notificación inmediata de prueba para que el usuario
  /// compruebe que los avisos funcionan. Si el permiso del sistema no está
  /// concedido (Android 13+), lo pide antes. Nunca propaga errores.
  Future<ResultadoPerfil> enviarNotificacionDePrueba() async {
    bool permisoConcedido;
    try {
      permisoConcedido = await _notificacionesService
          .solicitarPermiso()
          .timeout(_timeoutNotificaciones);
    } catch (e) {
      debugPrint('ERROR AL PEDIR PERMISO DE NOTIFICACIONES: $e');
      permisoConcedido = false;
    }

    if (!permisoConcedido) {
      return const ResultadoPerfil.error(
        'Activa los permisos de notificaciones en los ajustes del sistema',
      );
    }

    try {
      await _notificacionesService
          .mostrarNotificacionDePrueba()
          .timeout(_timeoutNotificaciones);
    } catch (e) {
      debugPrint('ERROR AL MOSTRAR LA NOTIFICACIÓN DE PRUEBA: $e');
      return const ResultadoPerfil.error(
        'No se pudo mostrar la notificación de prueba',
      );
    }

    return const ResultadoPerfil.exito();
  }

  /// Reprograma el recordatorio de cada meta activa con fecha límite futura.
  /// Reutiliza el cálculo y la programación ya existentes en `MetasLogic` y
  /// `NotificacionesService`. Nunca propaga errores.
  Future<void> _reprogramarRecordatoriosDeMetas() async {
    final usuarioId = _authLogic.obtenerUsuarioId();
    if (usuarioId == null) return;

    List<Map<String, dynamic>> metas;
    try {
      metas = await _metasLogic
          .obtenerMetas(usuarioId)
          .timeout(_timeoutNotificaciones);
    } catch (e) {
      debugPrint('ERROR AL OBTENER METAS PARA RECORDATORIOS: $e');
      return;
    }

    for (final meta in metas) {
      if (meta['cumplida'] == true) continue;
      final fechaLimiteStr = meta['fecha_limite'] as String?;
      if (fechaLimiteStr == null) continue;
      final fechaLimite = DateTime.tryParse(fechaLimiteStr);
      if (fechaLimite == null) continue;

      final fechaRecordatorio =
          _metasLogic.calcularFechaRecordatorio(fechaLimite);
      if (fechaRecordatorio == null) continue;

      final metaId = meta['id'].toString();
      final nombre = meta['nombre'].toString();
      try {
        await _notificacionesService
            .programarRecordatorio(
              metaId: metaId,
              nombreMeta: nombre,
              fecha: fechaRecordatorio,
            )
            .timeout(_timeoutNotificaciones);
      } catch (e) {
        debugPrint('ERROR AL REPROGRAMAR RECORDATORIO (meta $metaId): $e');
      }
    }
  }

  /// Elimina la cuenta del usuario autenticado.
  ///
  /// Borra sus datos y su cuenta en el servidor y, si sale bien, cancela todos
  /// los recordatorios locales. No cierra sesión ni navega: eso lo decide la
  /// pantalla con [cerrarSesionTrasEliminar].
  Future<ResultadoPerfil> eliminarCuenta() async {
    if (_authLogic.obtenerUsuarioId() == null) {
      return const ResultadoPerfil.error(
        'No hay una sesión activa. Inicia sesión de nuevo.',
      );
    }

    try {
      await _repository.eliminarCuenta();
    } catch (e) {
      debugPrint('ERROR AL ELIMINAR CUENTA: $e');
      return ResultadoPerfil.error(_mensajeAmigableEliminarCuenta(e));
    }

    try {
      await _notificacionesService
          .cancelarTodos()
          .timeout(_timeoutNotificaciones);
    } catch (e) {
      debugPrint('ERROR AL CANCELAR NOTIFICACIONES: $e');
    }

    return const ResultadoPerfil.exito();
  }

  /// Cierra la sesión de este dispositivo después de eliminar la cuenta.
  /// Nunca propaga errores: si falla, el `AuthGate` igualmente acaba en el
  /// login la próxima vez que se evalúe la sesión.
  Future<void> cerrarSesionTrasEliminar() async {
    try {
      await _repository.cerrarSesionLocal();
    } catch (e) {
      debugPrint('ERROR AL CERRAR SESIÓN LOCAL: $e');
    }
  }

  /// Traduce las excepciones de Supabase a mensajes amigables sin exponer
  /// detalles técnicos al usuario.
  String _mensajeAmigableContrasena(Object e) {
    final texto = e.toString().toLowerCase();
    if (texto.contains('invalid login credentials') ||
        texto.contains('invalid credentials')) {
      return 'La contraseña actual es incorrecta';
    }
    if (texto.contains('network') ||
        texto.contains('socket') ||
        texto.contains('connection') ||
        texto.contains('failed host lookup') ||
        texto.contains('failed to fetch') ||
        texto.contains('clientexception')) {
      return 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
    }
    return 'No se pudo cambiar la contraseña. Inténtalo de nuevo.';
  }

  /// Mensaje amigable para el borrado de la cuenta: distingue los fallos de
  /// red del resto.
  String _mensajeAmigableEliminarCuenta(Object e) {
    final texto = e.toString().toLowerCase();
    if (texto.contains('network') ||
        texto.contains('socket') ||
        texto.contains('connection') ||
        texto.contains('failed host lookup') ||
        texto.contains('failed to fetch') ||
        texto.contains('clientexception')) {
      return 'Sin conexión. Revisa tu internet e inténtalo de nuevo.';
    }
    return 'No se pudo eliminar tu cuenta. Inténtalo de nuevo.';
  }
}

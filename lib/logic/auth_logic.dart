import '../data/usuario_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthLogic {
  final UsuarioRepository _repository = UsuarioRepository();

  /// Valida el formato de un correo electrónico.
  String? validarCorreo(String correo) {
    if (correo.trim().isEmpty) {
      return 'El correo no puede estar vacío';
    }
    final regexCorreo = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!regexCorreo.hasMatch(correo)) {
      return 'Ingresa un correo válido';
    }
    return null; // null significa que no hay error
  }

  /// Valida que la contraseña cumpla un mínimo de seguridad.
  String? validarContrasena(String contrasena) {
    if (contrasena.isEmpty) {
      return 'La contraseña no puede estar vacía';
    }
    if (contrasena.length < 6) {
      return 'La contraseña debe tener al menos 6 caracteres';
    }
    return null;
  }

  /// Valida el nombre del usuario.
  String? validarNombre(String nombre) {
    if (nombre.trim().isEmpty) {
      return 'El nombre no puede estar vacío';
    }
    return null;
  }

  /// Registra un usuario, validando los datos antes de llamar a Supabase.
  Future<String?> registrar({
    required String correo,
    required String contrasena,
    required String nombre,
  }) async {
    final errorCorreo = validarCorreo(correo);
    if (errorCorreo != null) return errorCorreo;

    final errorContrasena = validarContrasena(contrasena);
    if (errorContrasena != null) return errorContrasena;

    final errorNombre = validarNombre(nombre);
    if (errorNombre != null) return errorNombre;

    try {
      await _repository.registrarUsuario(
        correo: correo,
        contrasena: contrasena,
        nombre: nombre,
      );
      return null; // null significa que todo salió bien, sin errores
    } on AuthException catch (e) {
      return e.message; // Supabase devuelve mensajes como "User already registered"
    } catch (e) {
      return 'Ocurrió un error inesperado. Intenta de nuevo.';
    }
  }

  /// Inicia sesión, validando los datos antes de llamar a Supabase.
  Future<String?> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    final errorCorreo = validarCorreo(correo);
    if (errorCorreo != null) return errorCorreo;

    if (contrasena.isEmpty) return 'Ingresa tu contraseña';

    try {
      await _repository.iniciarSesion(correo: correo, contrasena: contrasena);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Ocurrió un error inesperado. Intenta de nuevo.';
    }
  }

  /// Envía el correo de recuperación de contraseña.
  Future<String?> recuperarContrasena(String correo) async {
    final errorCorreo = validarCorreo(correo);
    if (errorCorreo != null) return errorCorreo;

    try {
      await _repository.recuperarContrasena(correo);
      return null;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Ocurrió un error inesperado. Intenta de nuevo.';
    }
  }

  /// Cierra la sesión del usuario.
  Future<void> cerrarSesion() async {
    await _repository.cerrarSesion();
  }

  /// Verifica si hay una sesión activa en este momento.
  bool haySesionActiva() {
    return _repository.obtenerUsuarioActual() != null;
  }

  /// Devuelve el ID del usuario autenticado actualmente, o null si no hay sesión.
  String? obtenerUsuarioId() {
    return _repository.obtenerUsuarioActual()?.id;
  }

  /// Expone el stream de cambios de sesión para la sesión persistente.
  Stream<AuthState> escucharSesion() {
    return _repository.escucharCambiosDeSesion();
  }
}
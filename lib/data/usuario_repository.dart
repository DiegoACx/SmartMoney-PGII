import 'package:supabase_flutter/supabase_flutter.dart';

class UsuarioRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Registra un nuevo usuario con correo y contraseña.
  /// Devuelve la respuesta de Supabase Auth.
  Future<AuthResponse> registrarUsuario({
    required String correo,
    required String contrasena,
    required String nombre,
  }) async {
    final response = await _client.auth.signUp(
      email: correo,
      password: contrasena,
    );

    // Si el registro fue exitoso, creamos el perfil en la tabla 'usuarios'
    if (response.user != null) {
      await _client.from('usuarios').insert({
        'id': response.user!.id,
        'nombre': nombre,
        'email': correo,
      });
    }

    return response;
  }

  /// Inicia sesión con correo y contraseña.
  Future<AuthResponse> iniciarSesion({
    required String correo,
    required String contrasena,
  }) async {
    return await _client.auth.signInWithPassword(
      email: correo,
      password: contrasena,
    );
  }

  /// Cierra la sesión actual.
  Future<void> cerrarSesion() async {
    await _client.auth.signOut();
  }

  /// Envía un correo de recuperación de contraseña.
  Future<void> recuperarContrasena(String correo) async {
    await _client.auth.resetPasswordForEmail(correo);
  }

  /// Devuelve el usuario actualmente autenticado (o null si no hay sesión).
  User? obtenerUsuarioActual() {
    return _client.auth.currentUser;
  }

  /// Escucha cambios en el estado de autenticación (login/logout),
  /// esto es clave para la sesión persistente.
  Stream<AuthState> escucharCambiosDeSesion() {
    return _client.auth.onAuthStateChange;
  }
}
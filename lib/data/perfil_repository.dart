import 'dart:convert';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Acceso puro a Supabase para la pestaña PERFIL.
///
/// Solo trae/actualiza datos: no contiene validaciones ni cálculos.
class PerfilRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Devuelve los datos del perfil del usuario autenticado.
  /// El nombre se lee de la tabla `usuarios`; si esa fila aún no existe
  /// (o su nombre está vacío) se devuelve cadena vacía. El correo se toma
  /// primero de `usuarios.email` y, si falta, del correo de la sesión.
  Future<Map<String, dynamic>> obtenerPerfil() async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw Exception('No hay usuario autenticado');
    }

    final data = await _client
        .from('usuarios')
        .select('nombre, email')
        .eq('id', user.id)
        .maybeSingle();

    final fila = data == null
        ? <String, dynamic>{}
        : Map<String, dynamic>.from(data as Map);

    final emailDeTabla = fila['email']?.toString() ?? '';
    return {
      'nombre': fila['nombre']?.toString() ?? '',
      'correo': emailDeTabla.isNotEmpty ? emailDeTabla : (user.email ?? ''),
    };
  }

  /// Actualiza el nombre del usuario autenticado en la tabla `usuarios`.
  /// Verifica el resultado: si el `update` no devuelve ninguna fila, la fila
  /// no se encontró y el nombre no se guardó, así que lanza una excepción.
  Future<void> actualizarNombre(String nombre) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No hay usuario autenticado');
    }

    final filas = await _client
        .from('usuarios')
        .update({'nombre': nombre})
        .eq('id', userId)
        .select();

    if (filas.isEmpty) {
      throw Exception('No se actualizó ninguna fila del perfil');
    }
  }

  /// Cambia la contraseña del usuario autenticado.
  /// Primero reautentica con la contraseña actual (`signInWithPassword`) y
  /// luego aplica la nueva (`updateUser`). Si la actual es incorrecta,
  /// Supabase lanza una excepción de autenticación.
  Future<void> cambiarContrasena({
    required String contrasenaActual,
    required String contrasenaNueva,
  }) async {
    final correo = _client.auth.currentUser?.email;
    if (correo == null) {
      throw Exception('No hay usuario autenticado');
    }

    await _client.auth.signInWithPassword(
      email: correo,
      password: contrasenaActual,
    );
    await _client.auth.updateUser(UserAttributes(password: contrasenaNueva));
  }

  /// Elimina la cuenta del usuario autenticado invocando la Edge Function
  /// `eliminar-cuenta`. El JWT del usuario se adjunta solo con
  /// `functions.invoke`, así que el id nunca se envía en el cuerpo.
  /// Lanza una excepción si la respuesta no confirma el borrado.
  Future<void> eliminarCuenta() async {
    if (_client.auth.currentUser == null) {
      throw Exception('No hay usuario autenticado');
    }

    final respuesta = await _client.functions.invoke('eliminar-cuenta');

    final cuerpo = _comoMapa(respuesta.data);
    if (respuesta.status != 200 || cuerpo['ok'] != true) {
      throw Exception('No se pudo eliminar la cuenta');
    }
  }

  /// Cierra la sesión solo en este dispositivo (`SignOutScope.local`).
  ///
  /// Después de borrar la cuenta, el cierre global contra el servidor puede
  /// fallar porque el usuario ya no existe; el cierre local limpia igual la
  /// sesión guardada y deja que el `AuthGate` muestre el login.
  Future<void> cerrarSesionLocal() async {
    await _client.auth.signOut(scope: SignOutScope.local);
  }

  /// Normaliza la respuesta de una función a un mapa, venga ya decodificada
  /// o como texto JSON.
  Map<String, dynamic> _comoMapa(dynamic dato) {
    if (dato is Map) return Map<String, dynamic>.from(dato);
    if (dato is String && dato.isNotEmpty) {
      try {
        final decodificado = jsonDecode(dato);
        if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }
}

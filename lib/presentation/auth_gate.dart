import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../logic/auth_logic.dart';
import 'login_screen.dart';
import 'main_shell.dart';

/// "Portero" de la app: decide si mostrar el Login o el MainShell,
/// según si ya hay una sesión activa (sesión persistente).
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = AuthLogic();

    return StreamBuilder<AuthState>(
      // Escucha cualquier cambio de sesión en tiempo real
      // (login, logout, token renovado, etc.)
      stream: auth.escucharSesion(),
      builder: (context, snapshot) {
        final haySesion = auth.haySesionActiva();

        if (haySesion) {
          return const MainShell();
        }
        return const LoginScreen();
      },
    );
  }
}
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/auth_logic.dart';

/// Pantalla placeholder — sección "IA" del BottomNavigationBar.
class IaScreen extends StatelessWidget {
  const IaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // ===== Botón de cerrar sesión — conservado al estilo del dashboard =====
    void cerrarSesion() async {
      await AuthLogic().cerrarSesion();
      // No hace falta navegar manualmente: AuthGate escucha el cambio de
      // sesión (StreamBuilder) y muestra LoginScreen automáticamente al
      // detectar el logout.
    }

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFAF6EA),
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: cerrarSesion,
            icon: const Icon(Icons.logout, size: 18, color: Color(0xFFC0392B)),
            label: Text(
              'Cerrar sesión',
              style: GoogleFonts.poppins(
                color: const Color(0xFFC0392B),
                fontWeight: FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: const Color(0xFF58774B).withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.auto_awesome,
                    size: 56,
                    color: Color(0xFF58774B),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Uso de la IA',
                  style: GoogleFonts.poppins(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2B2B2B),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Estamos construyendo esta sección. ¡Vuelve pronto!',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF8C8474),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

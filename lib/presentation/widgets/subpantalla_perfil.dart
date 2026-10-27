import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Estructura compartida por las subpantallas del perfil: fondo, cabecera con
/// botón atrás circular y cuerpo desplazable con padding horizontal.
///
/// Solo presentación: no conoce datos ni lógica.
class SubpantallaPerfil extends StatelessWidget {
  const SubpantallaPerfil({
    super.key,
    required this.titulo,
    required this.child,
  });

  final String titulo;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x14000000),
                          blurRadius: 10,
                          offset: Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => Navigator.pop(context),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 18,
                            color: Color(0xFF2B2B2B),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      titulo,
                      style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF2B2B2B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

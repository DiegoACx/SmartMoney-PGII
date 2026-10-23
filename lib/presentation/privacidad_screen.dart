import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/subpantalla_perfil.dart';

// REVISAR: el equipo debe definir el correo de contacto antes del piloto
const String correoContacto = '';

const Color _texto = Color(0xFF2B2B2B);
const Color _secundario = Color(0xFF8C8474);

/// Pantalla de solo lectura con la política de privacidad y los términos.
class PrivacidadScreen extends StatelessWidget {
  const PrivacidadScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SubpantallaPerfil(
      titulo: 'Privacidad y términos',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          _seccion(
            '1) Quiénes somos',
            'SmartMoney es un proyecto de grado de Ingeniería de Sistemas de la '
                'Universidad Autónoma de Bucaramanga (UNAB), desarrollado por '
                'Diego Armando Castro Duarte y Juan José García Almeida. Es un '
                'prototipo académico, no un servicio financiero regulado. Al '
                'registrarte y usar la app, autorizas el tratamiento de tus '
                'datos en los términos de esta política.',
          ),
          _seccion(
            '2) Qué datos tratamos',
            'Tu nombre y correo; los movimientos que registras (monto, '
                'categoría, fecha, notas y método de pago); tus metas de ahorro '
                'y aportes; tu progreso en Educación financiera; tu interacción '
                'con las recomendaciones; y los mensajes que escribes en el '
                'asistente de IA. La app no accede a tus cuentas bancarias, '
                'contactos, ubicación, cámara ni micrófono: los movimientos los '
                'registras tú.',
          ),
          _seccion(
            '3) Para qué los usamos',
            'Ofrecerte las funciones de la app, generar recomendaciones '
                'personalizadas y, de forma agregada y sin identificarte, '
                'evaluar el proyecto académico (por ejemplo, en la prueba '
                'piloto).',
          ),
          _seccion(
            '4) Uso de inteligencia artificial',
            'Para redactar algunas recomendaciones y respuestas del asistente, '
                'la app envía la información necesaria a un proveedor externo '
                'de modelos de lenguaje. No vendemos tus datos. No usamos tus '
                'datos para publicidad.',
          ),
          _seccion(
            '5) Seguridad',
            'Tus datos viajan cifrados (HTTPS) y están protegidos por '
                'autenticación y reglas de acceso por fila: cada usuario solo '
                'puede acceder a su propia información.',
          ),
          _seccion(
            '6) Cuánto tiempo conservamos tus datos',
            'Conservamos tu información mientras tu cuenta esté activa. Si '
                'eliminas tu cuenta desde Perfil, borramos tu información de '
                'forma permanente.',
          ),
          _seccion(
            '7) Tus derechos (Ley 1581 de 2012)',
            'Puedes conocer, actualizar y rectificar tus datos, revocar tu '
                'autorización y solicitar su supresión. Puedes editar tu nombre '
                'y eliminar tu cuenta y todos tus datos desde Perfil.'
                '${correoContacto.isNotEmpty ? ' Contacto: $correoContacto' : ''}',
          ),
          _seccion(
            '8) Cambios a esta política',
            'Podemos actualizar este texto para reflejar mejoras de la app o '
                'cambios normativos. La fecha de la última actualización '
                'aparece al final de esta pantalla.',
          ),
          _seccion(
            '9) Términos de uso',
            'Las recomendaciones y la información educativa son orientativas y '
                'no constituyen asesoría financiera, legal ni de inversión; las '
                'decisiones son tu responsabilidad. Eres responsable de la '
                'veracidad de la información que registras y de mantener '
                'segura tu contraseña. Al ser un proyecto académico, la app '
                'puede presentar errores o interrupciones.',
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Última actualización: octubre de 2026',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(fontSize: 12, color: _secundario),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _seccion(String titulo, String cuerpo) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _texto,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              cuerpo,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: _texto,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

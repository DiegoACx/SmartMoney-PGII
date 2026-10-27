import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'widgets/subpantalla_perfil.dart';

/// Versión de la app. Debe coincidir con la línea `version:` de pubspec.yaml.
const String versionApp = '1.0.0+1';

const Color _verde = Color(0xFF58774B);
const Color _texto = Color(0xFF2B2B2B);
const Color _secundario = Color(0xFF8C8474);
const Color _borde = Color(0xFFC9C2B0);

/// Pantalla de ayuda: preguntas frecuentes (acordeón) y "Acerca de".
class AyudaScreen extends StatelessWidget {
  const AyudaScreen({super.key});

  static const List<List<String>> _preguntas = [
    [
      '¿Cómo registro un ingreso o un egreso?',
      'Ve a la pestaña Ingresos y toca el botón "+". Elige si es un ingreso o '
          'un egreso, escribe el monto (la app agrega los puntos de miles '
          'sola), selecciona la categoría y la fecha, y si quieres agrega una '
          'nota y el método de pago. En los egresos, al escribir la '
          'descripción la app puede sugerirte una categoría con la etiqueta '
          '"Sugerida": puedes aceptarla o elegir otra. Si no encuentras la '
          'categoría que necesitas, puedes crear una propia desde el mismo '
          'formulario.',
    ],
    [
      '¿Cómo edito o elimino un movimiento?',
      'Desde la lista de movimientos de la pestaña Ingresos puedes editar o '
          'eliminar cada uno. Antes de borrar, la app te pide confirmación '
          'para evitar errores. Si el movimiento que buscas no aparece entre '
          'los más recientes, usa "Ver más" y el rango de fechas (Desde / '
          'Hasta) para encontrarlo.',
    ],
    [
      '¿Cómo funcionan las metas de ahorro?',
      'En la pestaña Metas creas una meta con nombre, monto objetivo y fecha '
          'límite. Cada vez que ahorres, registra un aporte; si necesitas usar '
          'parte de ese dinero, registra un retiro (no puede ser mayor a lo '
          'que llevas ahorrado). La app calcula tu porcentaje de avance y '
          'estima cuánto tiempo te falta según tu ritmo de ahorro de los '
          'últimos 30 días. Si tienes las notificaciones activas, también te '
          'recordará cuando se acerque la fecha límite.',
    ],
    [
      '¿Qué muestran las gráficas y la alerta de gasto en Inicio?',
      'En Inicio ves el total de tus ingresos, tus egresos y la diferencia '
          'entre ambos según el periodo que elijas (Mes actual, Mes pasado, '
          'Últimos 3 meses, Últimos 5 meses o Anual). Debajo hay tres '
          'gráficas: barras que comparan ingresos y egresos de los últimos '
          'seis meses, una torta con la distribución de tus gastos por '
          'categoría y una línea con la evolución de tu flujo de caja. Si el '
          'gasto de una categoría alcanza o supera el 40 % de tus ingresos '
          'del mes, la app te avisa para que puedas ajustarlo a tiempo.',
    ],
    [
      '¿Cómo se desbloquean los niveles de Educación financiera?',
      'Los contenidos van en orden: cada lección se desbloquea al completar '
          'la anterior. En las evaluaciones necesitas 70 % o más para aprobar '
          'y avanzar; si no lo logras, puedes repetirlas las veces que '
          'quieras. Al aprobar puedes revisar tus respuestas y las '
          'explicaciones antes de continuar. Hay cuatro niveles: '
          'Principiante, Intermedio, Avanzado y Experto, y tu progreso se '
          'guarda en tu cuenta. Algunos contenidos de los niveles más altos '
          'aún están en construcción y se irán habilitando.',
    ],
    [
      '¿De dónde salen las recomendaciones?',
      'Se calculan con tus propios movimientos y metas: la app compara tu '
          'gasto con tu comportamiento habitual y con referencias de gasto '
          'por categoría, y detecta situaciones como gastos más altos de lo '
          'normal para ti o metas que necesitan atención. Mientras más '
          'movimientos registres, más personalizadas serán. Son orientativas '
          'y no reemplazan la asesoría de un profesional.',
    ],
    [
      '¿Cómo cambio mi nombre o mi contraseña?',
      'En Perfil toca "Editar perfil" para cambiar tu nombre (el correo no se '
          'puede modificar) y usa "Cambiar contraseña", en la sección '
          'Seguridad; te pedirá la contraseña actual y la nueva. Si olvidaste '
          'tu contraseña, en la pantalla de inicio de sesión toca "¿Olvidaste '
          'tu contraseña?".',
    ],
    [
      '¿Cómo elimino mi cuenta y mis datos?',
      'En Perfil, al final de la pantalla, toca "Eliminar cuenta" y escribe '
          'ELIMINAR para confirmar. Se borran de forma permanente tu cuenta y '
          'toda tu información: movimientos, categorías propias, metas, '
          'aportes, progreso de educación, recomendaciones y mensajes del '
          'asistente. Esta acción no se puede deshacer.',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return SubpantallaPerfil(
      titulo: 'Ayuda y acerca de',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Text(
            'Preguntas frecuentes',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _secundario,
            ),
          ),
          const SizedBox(height: 8),
          for (final p in _preguntas)
            _TarjetaPregunta(pregunta: p[0], respuesta: p[1]),
          const SizedBox(height: 16),
          Text(
            'Acerca de',
            style: GoogleFonts.poppins(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _secundario,
            ),
          ),
          const SizedBox(height: 8),
          _tarjetaAcercaDe(),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _tarjetaAcercaDe() {
    return Container(
      padding: const EdgeInsets.all(20),
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
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: _verde.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.savings_rounded, size: 36, color: _verde),
          ),
          const SizedBox(height: 16),
          Text(
            'SmartMoney',
            style: GoogleFonts.poppins(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: _texto,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Versión ${versionApp.split('+').first}',
            style: GoogleFonts.poppins(fontSize: 12, color: _secundario),
          ),
          const SizedBox(height: 16),
          Text(
            'Proyecto de grado — Ingeniería de Sistemas, UNAB',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: _texto,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Desarrollado por Diego Armando Castro Duarte y Juan José García '
            'Almeida',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: _texto,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Director: Feisar Enrique Moreno Corzo',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: _texto,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Tarjeta de pregunta frecuente que se expande/colapsa al tocar.
class _TarjetaPregunta extends StatefulWidget {
  const _TarjetaPregunta({required this.pregunta, required this.respuesta});

  final String pregunta;
  final String respuesta;

  @override
  State<_TarjetaPregunta> createState() => _TarjetaPreguntaState();
}

class _TarjetaPreguntaState extends State<_TarjetaPregunta> {
  bool _abierto = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
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
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: () => setState(() => _abierto = !_abierto),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.pregunta,
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: _texto,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _abierto ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: _borde,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: Alignment.topCenter,
              child: _abierto
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Text(
                        widget.respuesta,
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: _texto,
                          height: 1.5,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

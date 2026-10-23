import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/auth_logic.dart';
import '../logic/formato_utils.dart';
import '../logic/perfil_logic.dart';
import 'ayuda_screen.dart';
import 'cambiar_contrasena_screen.dart';
import 'privacidad_screen.dart';
import 'widgets/curved_header_clipper.dart';

// ===== Paleta del sistema de diseño =====
const Color _verde = Color(0xFF58774B);
const Color _verdeClaro = Color(0xFF7A9B6C);
const Color _texto = Color(0xFF2B2B2B);
const Color _secundario = Color(0xFF8C8474);
const Color _borde = Color(0xFFC9C2B0);
const Color _error = Color(0xFFC0392B);
const Color _exito = Color(0xFF7A9B6C);

/// Estilo común de las tarjetas blancas del perfil.
BoxDecoration _decoracionTarjeta() => BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    );

/// Pantalla principal de la pestaña PERFIL.
///
/// Solo usa la capa `logic` (`PerfilLogic` para datos/acciones y
/// `AuthLogic` para cerrar sesión); nunca toca `data/` ni Supabase.
class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => PerfilScreenState();
}

class PerfilScreenState extends State<PerfilScreen> {
  final _perfilLogic = PerfilLogic();
  final _authLogic = AuthLogic();

  bool _cargando = true;
  ResumenActividad? _resumen;
  String _nombre = '';
  String _correo = '';
  bool _notificacionesActivas = true;
  bool _procesando = false;
  bool _cambiandoNotificaciones = false;

  @override
  void initState() {
    super.initState();
    _cargarPerfil(inicial: true);
  }

  /// Carga el perfil, el resumen de actividad y la preferencia de
  /// notificaciones en paralelo.
  ///
  /// Con [inicial] en true muestra el estado de carga (solo la primera vez,
  /// cuando aún no hay datos). En una recarga silenciosa no se reemplaza el
  /// contenido por un spinner y, si el resumen llega `null`, se conserva el
  /// anterior para no perder la información ya visible: el estado de error
  /// solo aparece si nunca hubo datos.
  Future<void> _cargarPerfil({required bool inicial}) async {
    if (inicial) {
      setState(() => _cargando = true);
    }

    final resultados = await Future.wait<dynamic>([
      _perfilLogic.obtenerPerfil(),
      _perfilLogic.obtenerResumenActividad(),
      _perfilLogic.obtenerNotificacionesActivas(),
    ]);
    final perfil = resultados[0] as Map<String, dynamic>;
    final resumen = resultados[1] as ResumenActividad?;
    final notificaciones = resultados[2] as bool;

    if (!mounted) return;

    setState(() {
      _nombre = perfil['nombre']?.toString() ?? '';
      _correo = perfil['correo']?.toString() ?? '';
      if (resumen != null || _resumen == null) {
        _resumen = resumen;
      }
      _notificacionesActivas = notificaciones;
      _cargando = false;
    });
  }

  /// Recarga solicitada desde el `MainShell` al entrar a la pestaña.
  /// Refresca en silencio para no parpadear el contenido ya visible.
  Future<void> recargar() => _cargarPerfil(inicial: false);

  // ===== Acciones =====

  Future<void> _abrirEditarNombre() async {
    if (_procesando) return;

    final actualizado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditarNombreSheet(
        nombreActual: _nombre,
        correo: _correo,
      ),
    );

    if (actualizado != true) return;
    if (!mounted) return;

    await _cargarPerfil(inicial: false);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Nombre actualizado',
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: _exito,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  Future<void> _confirmarCerrarSesion() async {
    if (_procesando) return;

    final confirmado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          '¿Cerrar sesión?',
          style: GoogleFonts.poppins(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: _texto,
          ),
        ),
        content: Text(
          'Tendrás que ingresar de nuevo con tu correo y contraseña.',
          style: GoogleFonts.poppins(fontSize: 14, color: _secundario),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.poppins(
                color: _secundario,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Cerrar sesión',
              style: GoogleFonts.poppins(
                color: _error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true) return;
    if (!mounted) return;

    setState(() => _procesando = true);
    try {
      // El AuthGate reacciona al cambio de sesión; no se navega manualmente.
      await _authLogic.cerrarSesion();
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  /// Abre la confirmación de borrado de cuenta. Si la eliminación sale bien,
  /// el sheet se cierra con su propio `pop` y aquí solo se cierra la sesión
  /// local: el `AuthGate` se encarga de mostrar el login (no se navega).
  Future<void> _abrirEliminarCuenta() async {
    if (_procesando) return;

    final eliminada = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const _EliminarCuentaSheet(),
    );

    if (eliminada != true) return;

    await _perfilLogic.cerrarSesionTrasEliminar();
  }

  /// Muestra un SnackBar informativo con la paleta del perfil.
  void _mostrarMensaje(String mensaje, {required Color color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          mensaje,
          style: GoogleFonts.poppins(color: Colors.white),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  /// Cambia la preferencia de notificaciones con actualización optimista:
  /// si algo falla o se deniega el permiso, el switch vuelve a su valor
  /// anterior y se explica al usuario qué hacer.
  Future<void> _cambiarNotificaciones(bool activas) async {
    if (_cambiandoNotificaciones) return;

    final anterior = _notificacionesActivas;
    setState(() {
      _notificacionesActivas = activas;
      _cambiandoNotificaciones = true;
    });

    final resultado = await _perfilLogic.cambiarNotificaciones(activas);

    if (!mounted) return;

    setState(() {
      _cambiandoNotificaciones = false;
      if (!resultado.exito) {
        _notificacionesActivas = anterior;
      }
    });

    if (!resultado.exito) {
      _mostrarMensaje(
        resultado.error ??
            'Activa los permisos de notificaciones en los ajustes del sistema',
        color: _error,
      );
    }
  }

  Future<void> _abrirCambiarContrasena() async {
    final actualizada = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CambiarContrasenaScreen()),
    );

    if (actualizada != true) return;
    if (!mounted) return;

    _mostrarMensaje('Contraseña actualizada', color: _exito);
  }

  void _abrirPrivacidad() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PrivacidadScreen()),
    );
  }

  void _abrirAyuda() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AyudaScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCabecera(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 20),
                  _buildActividad(),
                  const SizedBox(height: 24),
                  _buildSeccion(
                    'Preferencias',
                    [
                      _FilaConfig(
                        icono: Icons.notifications_none_rounded,
                        titulo: 'Notificaciones',
                        subtitulo: 'Recordatorios y avisos de la app',
                        trailing: Switch(
                          value: _notificacionesActivas,
                          activeThumbColor: Colors.white,
                          activeTrackColor: _verde,
                          onChanged: _cambiarNotificaciones,
                        ),
                        onTap: () =>
                            _cambiarNotificaciones(!_notificacionesActivas),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSeccion(
                    'Seguridad',
                    [
                      _FilaConfig(
                        icono: Icons.lock_outline_rounded,
                        titulo: 'Cambiar contraseña',
                        subtitulo: 'Actualiza tu contraseña de acceso',
                        onTap: _abrirCambiarContrasena,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  _buildSeccion(
                    'Información',
                    [
                      _FilaConfig(
                        icono: Icons.privacy_tip_outlined,
                        titulo: 'Privacidad y términos',
                        subtitulo: 'Cómo tratamos tus datos',
                        onTap: _abrirPrivacidad,
                      ),
                      _FilaConfig(
                        icono: Icons.help_outline_rounded,
                        titulo: 'Ayuda y acerca de',
                        subtitulo: 'Soporte y versión de la app',
                        onTap: _abrirAyuda,
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  _buildCerrarSesion(),
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: _abrirEliminarCuenta,
                      child: Text(
                        'Eliminar cuenta',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _error.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===== Cabecera con gradiente y ola =====

  Widget _buildCabecera() {
    final topPadding = MediaQuery.of(context).padding.top;
    return SizedBox(
      height: topPadding + 292,
      width: double.infinity,
      child: ClipPath(
        clipper: CurvedHeaderClipper(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_verde, _verdeClaro],
            ),
          ),
          child: Padding(
            padding: EdgeInsets.only(
              top: topPadding + 12,
              left: 24,
              right: 24,
            ),
            child: Column(
              children: [
                _buildAvatar(),
                const SizedBox(height: 12),
                Text(
                  _nombre.trim().isEmpty ? 'Tu nombre' : _nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _correo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: Colors.white.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _procesando ? null : _abrirEditarNombre,
                  icon: const Icon(Icons.edit_rounded, size: 16),
                  label: Text(
                    'Editar perfil',
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white, width: 1.2),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 8,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar() {
    final iniciales =
        _perfilLogic.obtenerIniciales(_nombre, correo: _correo).trim();
    return Container(
      width: 92,
      height: 92,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: iniciales.isEmpty
          ? const Icon(Icons.person_rounded, size: 44, color: _verde)
          : Text(
              iniciales,
              style: GoogleFonts.poppins(
                fontSize: 32,
                fontWeight: FontWeight.w600,
                color: _verde,
              ),
            ),
    );
  }

  // ===== Tarjeta "Mi actividad" =====

  Widget _buildActividad() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion('Mi actividad'),
        const SizedBox(height: 8),
        Container(
          decoration: _decoracionTarjeta(),
          padding: const EdgeInsets.all(16),
          child: _buildContenidoActividad(),
        ),
      ],
    );
  }

  Widget _buildContenidoActividad() {
    if (_cargando) {
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: _miniStatCargando()),
              const SizedBox(width: 16),
              Expanded(child: _miniStatCargando()),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _miniStatCargando()),
              const SizedBox(width: 16),
              Expanded(child: _miniStatCargando()),
            ],
          ),
        ],
      );
    }

    final resumen = _resumen;
    if (resumen == null) {
      return Column(
        children: [
          const SizedBox(height: 8),
          Text(
            'No pudimos cargar tu actividad',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(fontSize: 14, color: _texto),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => _cargarPerfil(inicial: true),
            child: Text(
              'Reintentar',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _verde,
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _miniStat(
                Icons.receipt_long_rounded,
                '${resumen.totalMovimientos}',
                'Movimientos',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _miniStat(
                Icons.flag_rounded,
                '${resumen.metasActivas}',
                'Metas activas',
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: _miniStat(
                Icons.emoji_events_rounded,
                '${resumen.metasCumplidas}',
                'Metas cumplidas',
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _miniStat(
                Icons.menu_book_rounded,
                '${resumen.leccionesCompletadas}/${resumen.totalLecciones}',
                'Lecciones',
              ),
            ),
          ],
        ),
        if (resumen.nivelActualNombre != null) ...[
          const SizedBox(height: 18),
          const Divider(
            height: 1,
            thickness: 1,
            color: Color(0x66C9C2B0),
          ),
          const SizedBox(height: 14),
          _buildNivelActual(resumen),
        ],
      ],
    );
  }

  Widget _buildNivelActual(ResumenActividad resumen) {
    final colorNivel = colorFromHex(resumen.nivelActualColorHex ?? '58774B');
    final total = resumen.totalLecciones;
    final progreso = total > 0
        ? (resumen.leccionesCompletadas / total).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'Nivel actual',
              style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _secundario,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: colorNivel.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                resumen.nivelActualNombre ?? '',
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorNivel,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progreso,
            minHeight: 6,
            backgroundColor: _borde.withValues(alpha: 0.3),
            valueColor: AlwaysStoppedAnimation<Color>(colorNivel),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${resumen.leccionesCompletadas} de $total lecciones completadas',
          style: GoogleFonts.poppins(fontSize: 12, color: _secundario),
        ),
      ],
    );
  }

  Widget _miniStat(IconData icono, String valor, String etiqueta) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _verde.withValues(alpha: 0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(icono, size: 20, color: _verde),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                valor,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: _texto,
                ),
              ),
              Text(
                etiqueta,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: _secundario,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStatCargando() {
    Widget caja(double ancho, double alto) => Container(
          width: ancho,
          height: alto,
          decoration: BoxDecoration(
            color: _borde.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(6),
          ),
        );

    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _borde.withValues(alpha: 0.3),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              caja(40, 18),
              const SizedBox(height: 8),
              caja(84, 12),
            ],
          ),
        ),
      ],
    );
  }

  // ===== Secciones de configuración =====

  Widget _tituloSeccion(String texto) {
    return Text(
      texto,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _secundario,
      ),
    );
  }

  Widget _buildSeccion(String titulo, List<_FilaConfig> filas) {
    final hijos = <Widget>[];
    for (var i = 0; i < filas.length; i++) {
      if (i > 0) {
        hijos.add(
          const Divider(
            height: 1,
            thickness: 1,
            indent: 68,
            endIndent: 16,
            color: Color(0x66C9C2B0),
          ),
        );
      }
      hijos.add(filas[i]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tituloSeccion(titulo),
        const SizedBox(height: 8),
        Container(
          decoration: _decoracionTarjeta(),
          clipBehavior: Clip.antiAlias,
          child: Column(children: hijos),
        ),
      ],
    );
  }

  // ===== Cierre de sesión =====

  Widget _buildCerrarSesion() {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _procesando ? null : _confirmarCerrarSesion,
        icon: _procesando
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _error,
                ),
              )
            : const Icon(Icons.logout_rounded, size: 20),
        label: Text(
          'Cerrar sesión',
          style: GoogleFonts.poppins(
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: _error,
          side: const BorderSide(color: _error),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}

/// Fila de una sección de configuración: ícono en círculo, título,
/// subtítulo opcional, elemento final (chevron o switch) y acción de toque.
class _FilaConfig extends StatelessWidget {
  const _FilaConfig({
    required this.icono,
    required this.titulo,
    this.subtitulo,
    this.trailing,
    this.onTap,
  });

  final IconData icono;
  final String titulo;
  final String? subtitulo;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _verde.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: Icon(icono, size: 20, color: _verde),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titulo,
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: _texto,
                      ),
                    ),
                    if (subtitulo != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitulo!,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _secundario,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              trailing ??
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: _borde,
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hoja inferior para editar el nombre. Mantiene sus propios
/// `TextEditingController` (y los libera en `dispose`). Devuelve `true`
/// por `pop` solo si el nombre se guardó correctamente.
class _EditarNombreSheet extends StatefulWidget {
  const _EditarNombreSheet({
    required this.nombreActual,
    required this.correo,
  });

  final String nombreActual;
  final String correo;

  @override
  State<_EditarNombreSheet> createState() => _EditarNombreSheetState();
}

class _EditarNombreSheetState extends State<_EditarNombreSheet> {
  final _perfilLogic = PerfilLogic();
  late final TextEditingController _controller =
      TextEditingController(text: widget.nombreActual);
  String? _error;
  bool _guardando = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _puedeGuardar =>
      !_guardando && _perfilLogic.validarNombre(_controller.text.trim()) == null;

  void _onCambio(String valor) {
    // Se valida siempre sobre el texto recortado para que escribir espacios
    // (al inicio, al final o entre palabras) no marque un error falso.
    setState(() {
      _error = _perfilLogic.validarNombre(valor.trim());
    });
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final nombre = _controller.text.trim();
    final error = _perfilLogic.validarNombre(nombre);
    if (error != null) {
      setState(() => _error = error);
      return;
    }

    setState(() {
      _guardando = true;
      _error = null;
    });

    final resultado = await _perfilLogic.cambiarNombre(nombre);

    if (!mounted) return;

    if (resultado.exito) {
      // Único pop del sheet: la acción (recargar + SnackBar) ocurre fuera.
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _error = resultado.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _borde,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Editar nombre',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _texto,
              ),
            ),
            const SizedBox(height: 18),
            Material(
              elevation: 1,
              borderRadius: BorderRadius.circular(14),
              color: Colors.transparent,
              child: TextField(
                controller: _controller,
                maxLength: 50,
                textInputAction: TextInputAction.done,
                onChanged: _onCambio,
                decoration: InputDecoration(
                  labelText: 'Nombre',
                  prefixIcon: const Icon(
                    Icons.person_outline,
                    color: _borde,
                  ),
                  errorText: _error,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF6EA),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _borde.withValues(alpha: 0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, size: 18, color: _borde),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.correo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: _texto,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'El correo no se puede modificar',
              style: GoogleFonts.poppins(fontSize: 12, color: _secundario),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _puedeGuardar ? _guardar : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _verde,
                  disabledBackgroundColor: _verde.withValues(alpha: 0.4),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _guardando
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        'Guardar',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hoja modal de confirmación para eliminar la cuenta y todos sus datos.
///
/// El borrado lo hace `PerfilLogic`; la hoja solo muestra el error (sin
/// cerrarse) o, si sale bien, se cierra con un único `pop(context, true)`.
class _EliminarCuentaSheet extends StatefulWidget {
  const _EliminarCuentaSheet();

  @override
  State<_EliminarCuentaSheet> createState() => _EliminarCuentaSheetState();
}

class _EliminarCuentaSheetState extends State<_EliminarCuentaSheet> {
  /// Texto exacto que el usuario debe escribir para habilitar el borrado.
  static const String _palabraConfirmacion = 'ELIMINAR';

  static const List<String> _consecuencias = [
    'tus movimientos y categorías',
    'tus metas y aportes',
    'tu progreso en Educación financiera',
    'tus recomendaciones y mensajes del asistente de IA',
    'tu cuenta y tu acceso',
  ];

  final _perfilLogic = PerfilLogic();
  final _controller = TextEditingController();

  bool _eliminando = false;
  String? _mensajeError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// El botón se habilita solo si el texto recortado es exactamente ELIMINAR.
  bool get _puedeEliminar =>
      !_eliminando &&
      _controller.text.trim() == _palabraConfirmacion;

  Future<void> _eliminar() async {
    if (!_puedeEliminar) return;

    setState(() {
      _eliminando = true;
      _mensajeError = null;
    });

    final resultado = await _perfilLogic.eliminarCuenta();

    if (!mounted) return;

    if (resultado.exito) {
      // Único pop del sheet: la sesión la cierra la pantalla de perfil.
      Navigator.pop(context, true);
      return;
    }

    setState(() {
      _eliminando = false;
      _mensajeError = resultado.error;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_eliminando,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: _error.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 36,
                    color: _error,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: Text(
                  'Eliminar cuenta',
                  style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: _texto,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Esta acción es permanente y no se puede deshacer. Se borrarán:',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: _texto,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              for (final consecuencia in _consecuencias)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '•',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          color: _secundario,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          consecuencia,
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: _texto,
                            height: 1.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Material(
                elevation: 1,
                borderRadius: BorderRadius.circular(14),
                color: Colors.transparent,
                child: TextField(
                  controller: _controller,
                  enabled: !_eliminando,
                  textCapitalization: TextCapitalization.characters,
                  textInputAction: TextInputAction.done,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Escribe ELIMINAR para confirmar',
                    prefixIcon: Icon(
                      Icons.warning_amber_rounded,
                      color: _borde,
                    ),
                  ),
                ),
              ),
              if (_mensajeError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _mensajeError!,
                  style: GoogleFonts.poppins(fontSize: 13, color: _error),
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _puedeEliminar ? _eliminar : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _error,
                    disabledBackgroundColor: _error.withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _eliminando
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(
                          'Eliminar definitivamente',
                          style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: _eliminando ? null : () => Navigator.pop(context),
                child: Text(
                  'Cancelar',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: _secundario,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

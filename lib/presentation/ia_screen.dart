import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/auth_logic.dart';
import '../logic/chat_logic.dart';
import 'utils/abrir_leccion.dart';

const Color _verde = Color(0xFF58774B);
const Color _verdeClaro = Color(0xFF7A9B6C);
const Color _gris = Color(0xFF8C8474);
const Color _texto = Color(0xFF2B2B2B);
const Color _fondo = Color(0xFFFAF6EA);
const Color _borde = Color(0xFFECECEC);

/// Aviso fijo de privacidad mostrado arriba de la conversación.
const String _avisoPrivacidad =
    'No compartas datos personales como cédula o números de cuenta. '
    'Tus preguntas se procesan con IA (Google Gemini).';

/// Sugerencias del estado vacío: al tocarlas se envían como mensaje.
const List<String> _sugerencias = [
  '¿Cuánto gasté este mes?',
  '¿Cómo voy con mi meta?',
  '¿Qué es un CDT?',
  '¿Qué puedes hacer?',
];

/// Pestaña "IA": chat con el asistente de SmartMoney.
class IaScreen extends StatefulWidget {
  const IaScreen({super.key, this.onCambiarPestana});

  /// Cambia de pestaña en el `MainShell`
  /// (2 = Educación, 3 = Movimientos, 4 = Metas, 5 = Perfil).
  final ValueChanged<int>? onCambiarPestana;

  @override
  State<IaScreen> createState() => _IaScreenState();
}

class _IaScreenState extends State<IaScreen> {
  final _chatLogic = ChatLogic();
  final _controlador = TextEditingController();
  final _scrollController = ScrollController();

  static const int _limiteHistorial = 50;

  List<Map<String, dynamic>> _mensajes = [];
  bool _cargandoHistorial = true;
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _cargarHistorial();
  }

  @override
  void dispose() {
    _controlador.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ===== Historial =====
  Future<void> _cargarHistorial() async {
    final historial =
        await _chatLogic.cargarHistorial(limite: _limiteHistorial);
    if (!mounted) return;
    setState(() {
      _mensajes = historial;
      _cargandoHistorial = false;
    });
    _desplazarAlFinal();
  }

  void _desplazarAlFinal() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ===== Envío =====
  Future<void> _enviar([String? textoFijo]) async {
    if (_enviando) return;

    final texto = (textoFijo ?? _controlador.text).trim();
    final errorValidacion = _chatLogic.validarTexto(texto);
    if (errorValidacion != null) {
      setState(() => _mensajes.add(_mensajeSistema(errorValidacion)));
      _desplazarAlFinal();
      return;
    }

    FocusScope.of(context).unfocus();
    _controlador.clear();
    setState(() {
      _mensajes.add({'rol': 'usuario', 'contenido': texto, 'util': null});
      _enviando = true;
    });
    _desplazarAlFinal();

    final resultado = await _chatLogic.enviarMensaje(texto);
    if (!mounted) return;

    setState(() {
      _enviando = false;
      if (resultado.exito) {
        _mensajes.add({
          'rol': 'asistente',
          'contenido': resultado.respuesta,
          'accion': resultado.accion,
          'aviso': resultado.aviso,
          'util': null,
        });
      } else {
        _mensajes.add(
          _mensajeSistema(resultado.error ?? 'Algo salió mal. Intenta de nuevo.'),
        );
      }
    });
    _desplazarAlFinal();

    if (!resultado.exito) return;

    // La Edge Function guarda los dos mensajes: recargamos para tener sus ids
    // reales y poder calificar (👍/👎) las respuestas.
    final historial = await _chatLogic.cargarHistorial(limite: _limiteHistorial);
    if (!mounted || historial.isEmpty) return;
    setState(() => _mensajes = historial);
    _desplazarAlFinal();
  }

  Map<String, dynamic> _mensajeSistema(String texto) => {
        'rol': 'sistema',
        'contenido': texto,
        'util': null,
      };

  // ===== Calificar =====
  Future<void> _calificar(int indice, bool util) async {
    final id = _mensajes[indice]['id']?.toString();
    if (id == null || id.isEmpty) return;

    final guardado = await _chatLogic.calificar(id, util);
    if (!mounted || !guardado) return;
    setState(() => _mensajes[indice]['util'] = util);
  }

  // ===== Borrar conversación =====
  Future<void> _confirmarBorrado() async {
    final confirmado = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(
          '¿Borrar la conversación?',
          style: GoogleFonts.poppins(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: _texto,
          ),
        ),
        content: Text(
          'Se eliminarán todos tus mensajes con el asistente. Esta acción no '
          'se puede deshacer.',
          style: GoogleFonts.poppins(fontSize: 14, color: _gris),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _gris,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Borrar',
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFFC0392B),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmado != true || !mounted) return;

    final borrado = await _chatLogic.borrarHistorial();
    if (!mounted) return;
    if (borrado) {
      setState(() => _mensajes = []);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'No pudimos borrar la conversación. Intenta de nuevo.',
          style: GoogleFonts.poppins(fontSize: 13),
        ),
        backgroundColor: const Color(0xFF2B2B2B),
      ),
    );
  }

  // ===== Acciones sugeridas por la respuesta =====
  String? _etiquetaAccion(Map<String, dynamic>? accion) {
    if (accion == null) return null;
    switch (accion['tipo']) {
      case 'abrir_leccion':
        return 'Ver lección';
      case 'ir_a':
        switch (accion['destino']) {
          case 'metas':
            return 'Ir a Metas';
          case 'movimientos':
            return 'Ir a Movimientos';
          case 'perfil':
            return 'Ir a Perfil';
        }
    }
    return null;
  }

  void _ejecutarAccion(Map<String, dynamic> accion) {
    FocusScope.of(context).unfocus();

    if (accion['tipo'] == 'abrir_leccion') {
      final escalonId = accion['escalon_id']?.toString() ?? '';
      if (escalonId.isEmpty) {
        widget.onCambiarPestana?.call(2);
        return;
      }
      abrirLeccion(
        context: context,
        escalonId: escalonId,
        onCambiarPestana: widget.onCambiarPestana,
      );
      return;
    }

    if (accion['tipo'] == 'ir_a') {
      switch (accion['destino']) {
        case 'metas':
          widget.onCambiarPestana?.call(4);
          return;
        case 'movimientos':
          widget.onCambiarPestana?.call(3);
          return;
        case 'perfil':
          widget.onCambiarPestana?.call(5);
          return;
      }
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _fondo,
      appBar: AppBar(
        backgroundColor: _fondo,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: _verde.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 18, color: _verde),
            ),
            const SizedBox(width: 10),
            Text(
              'Asistente',
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _texto,
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Opciones',
            icon: const Icon(Icons.more_vert, color: _gris),
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            onSelected: (valor) {
              if (valor == 'borrar') _confirmarBorrado();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'borrar',
                child: Row(
                  children: [
                    const Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: Color(0xFFC0392B),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Borrar conversación',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        color: _texto,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          TextButton.icon(
            onPressed: () async {
              await AuthLogic().cerrarSesion();
              // AuthGate escucha el cambio de sesión y muestra LoginScreen.
            },
            icon: const Icon(Icons.logout, size: 18, color: Color(0xFFC0392B)),
            label: Text(
              'Salir',
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
        top: false,
        child: Column(
          children: [
            _buildAvisoPrivacidad(),
            Expanded(child: _buildConversacion()),
            _buildEntrada(),
          ],
        ),
      ),
    );
  }

  Widget _buildAvisoPrivacidad() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE0A458).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0A458).withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lock_outline, size: 14, color: _gris),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _avisoPrivacidad,
              style: GoogleFonts.poppins(
                fontSize: 11,
                height: 1.35,
                color: _gris,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversacion() {
    if (_cargandoHistorial) {
      return const Center(
        child: CircularProgressIndicator(color: _verde),
      );
    }

    final hayContenido = _mensajes.isNotEmpty || _enviando;

    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      children: [
        if (!hayContenido) _buildEstadoVacio(),
        for (int i = 0; i < _mensajes.length; i++) _buildMensaje(i),
        if (_enviando) _buildPensando(),
      ],
    );
  }

  Widget _buildEstadoVacio() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          '¡Hola! Soy tu asistente financiero.',
          style: GoogleFonts.poppins(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: _texto,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Puedo revisar tus movimientos, contarte cómo vas con tus metas o '
          'explicarte conceptos de finanzas. ¿Por dónde empezamos?',
          style: GoogleFonts.poppins(
            fontSize: 13,
            height: 1.4,
            color: _gris,
          ),
        ),
        const SizedBox(height: 20),
        for (final sugerencia in _sugerencias) ...[
          _buildSugerencia(sugerencia),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildSugerencia(String texto) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _enviar(texto),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _borde),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  texto,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: _verde,
                  ),
                ),
              ),
              const Icon(Icons.arrow_forward, size: 16, color: _verdeClaro),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMensaje(int indice) {
    final mensaje = _mensajes[indice];
    final rol = mensaje['rol']?.toString() ?? 'asistente';
    final contenido = mensaje['contenido']?.toString() ?? '';

    if (rol == 'sistema') return _buildBurbujaSistema(contenido);
    if (rol == 'usuario') return _buildBurbujaUsuario(contenido);
    return _buildBurbujaAsistente(indice, mensaje, contenido);
  }

  /// Estilo del Markdown de las respuestas del asistente: Poppins, los colores
  /// de la app y viñetas cuidadas. Los enlaces y las imágenes no se dibujan.
  MarkdownStyleSheet _estiloMarkdown() {
    final base = GoogleFonts.poppins(fontSize: 14, height: 1.4, color: _texto);
    return MarkdownStyleSheet(
      p: base,
      strong: base.copyWith(fontWeight: FontWeight.w600),
      em: base.copyWith(fontStyle: FontStyle.italic),
      listBullet: base.copyWith(fontWeight: FontWeight.w600, color: _verde),
      listIndent: 18,
      blockSpacing: 8,
      // Los enlaces están desactivados: se muestran como texto normal.
      a: base,
      code: base,
    );
  }

  Widget _buildBurbujaUsuario(String contenido) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, left: 40),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: const BoxDecoration(
          color: _verde,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(4),
          ),
        ),
        child: Text(
          contenido,
          style: GoogleFonts.poppins(
            fontSize: 14,
            height: 1.35,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildBurbujaAsistente(
    int indice,
    Map<String, dynamic> mensaje,
    String contenido,
  ) {
    final accion = mensaje['accion'] is Map
        ? Map<String, dynamic>.from(mensaje['accion'] as Map)
        : null;
    final etiqueta = _etiquetaAccion(accion);
    final util = mensaje['util'];
    final aviso = mensaje['aviso']?.toString().trim() ?? '';

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 6, right: 32),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
                bottomRight: Radius.circular(16),
              ),
              border: Border.all(color: _borde),
            ),
            child: MarkdownBody(
              data: contenido,
              selectable: false,
              // Un salto de línea en el texto del asistente se respeta tal cual.
              softLineBreak: true,
              styleSheet: _estiloMarkdown(),
              // Sin enlaces ni imágenes: el asistente solo escribe texto.
              onTapLink: (texto, enlace, titulo) {},
              imageBuilder: (uri, titulo, alt) => const SizedBox.shrink(),
            ),
          ),
          if (aviso.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, right: 32, left: 2),
              child: Text(
                aviso,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  height: 1.3,
                  fontStyle: FontStyle.italic,
                  color: _gris,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 12, left: 2),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _buildBotonCalificar(
                  indice: indice,
                  esUtil: true,
                  seleccionado: util == true,
                ),
                _buildBotonCalificar(
                  indice: indice,
                  esUtil: false,
                  seleccionado: util == false,
                ),
                if (etiqueta != null && accion != null)
                  OutlinedButton(
                    onPressed: () => _ejecutarAccion(accion),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _verde,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      side: const BorderSide(color: Color(0xFFDCE3D7)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: Text(
                      etiqueta,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _verde,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBotonCalificar({
    required int indice,
    required bool esUtil,
    required bool seleccionado,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: seleccionado ? null : () => _calificar(indice, esUtil),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: seleccionado
              ? _verde.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: seleccionado ? const Color(0xFFDCE3D7) : Colors.transparent,
          ),
        ),
        child: Text(
          esUtil ? '👍' : '👎',
          style: TextStyle(
            fontSize: 13,
            color: seleccionado ? _texto : _gris,
          ),
        ),
      ),
    );
  }

  Widget _buildBurbujaSistema(String contenido) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12, left: 16, right: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFECECEC).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, size: 14, color: _gris),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              contenido,
              style: GoogleFonts.poppins(
                fontSize: 12,
                height: 1.35,
                color: _gris,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPensando() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12, right: 32),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _borde),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _verde),
            ),
            const SizedBox(width: 10),
            Text(
              'SmartMoney está pensando…',
              style: GoogleFonts.poppins(fontSize: 13, color: _gris),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEntrada() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      decoration: const BoxDecoration(
        color: _fondo,
        border: Border(top: BorderSide(color: _borde)),
      ),
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: _controlador,
        builder: (context, valor, _) {
          final texto = valor.text.trim();
          final puedeEnviar = !_enviando && texto.isNotEmpty;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controlador,
                      maxLength: ChatLogic.largoMaximo,
                      maxLines: 4,
                      minLines: 1,
                      textInputAction: TextInputAction.newline,
                      style: GoogleFonts.poppins(fontSize: 14, color: _texto),
                      decoration: InputDecoration(
                        hintText: 'Escribe tu pregunta…',
                        hintStyle:
                            GoogleFonts.poppins(fontSize: 14, color: _gris),
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        filled: true,
                        fillColor: Colors.white,
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _borde),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(color: _verde),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Material(
                      color: puedeEnviar ? _verde : const Color(0xFFD9D5CB),
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: puedeEnviar ? () => _enviar() : null,
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 4),
                child: Text(
                  '${valor.text.characters.length}/${ChatLogic.largoMaximo}',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: valor.text.characters.length >= ChatLogic.largoMaximo
                        ? const Color(0xFFC0392B)
                        : _gris,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

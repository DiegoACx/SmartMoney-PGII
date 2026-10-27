import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../logic/perfil_logic.dart';
import 'widgets/subpantalla_perfil.dart';

const Color _verde = Color(0xFF58774B);
const Color _secundario = Color(0xFF8C8474);
const Color _borde = Color(0xFFC9C2B0);
const Color _error = Color(0xFFC0392B);

/// Campo de contraseña al que puede pertenecer el error de validación.
enum _CampoContrasena { actual, nueva, confirmar }

/// Pantalla para cambiar la contraseña. Solo usa `PerfilLogic`.
class CambiarContrasenaScreen extends StatefulWidget {
  const CambiarContrasenaScreen({super.key});

  @override
  State<CambiarContrasenaScreen> createState() =>
      _CambiarContrasenaScreenState();
}

class _CambiarContrasenaScreenState extends State<CambiarContrasenaScreen> {
  final _perfilLogic = PerfilLogic();

  final _actualController = TextEditingController();
  final _nuevaController = TextEditingController();
  final _confirmarController = TextEditingController();

  bool _verActual = false;
  bool _verNueva = false;
  bool _verConfirmar = false;

  bool _tocoActual = false;
  bool _tocoNueva = false;
  bool _tocoConfirmar = false;

  bool _guardando = false;
  String? _errorServidor;

  @override
  void dispose() {
    _actualController.dispose();
    _nuevaController.dispose();
    _confirmarController.dispose();
    super.dispose();
  }

  String? get _errorValidacion => _perfilLogic.validarCambioContrasena(
        actual: _actualController.text,
        nueva: _nuevaController.text,
        confirmacion: _confirmarController.text,
      );

  bool get _puedeGuardar => !_guardando && _errorValidacion == null;

  /// Devuelve el error correspondiente a un campo, solo si el usuario ya
  /// escribió en él (validación en vivo sin marcar campos intactos).
  String? _errorDeCampo(_CampoContrasena campo) {
    final error = _errorValidacion;
    if (error == null) return null;

    switch (campo) {
      case _CampoContrasena.actual:
        if (!_tocoActual) return null;
        return error == 'Ingresa tu contraseña actual' ? error : null;
      case _CampoContrasena.nueva:
        if (!_tocoNueva) return null;
        const erroresNueva = {
          'La nueva contraseña no puede estar vacía',
          'La nueva contraseña debe tener al menos 8 caracteres',
          'La nueva contraseña debe ser diferente a la actual',
        };
        return erroresNueva.contains(error) ? error : null;
      case _CampoContrasena.confirmar:
        if (!_tocoConfirmar) return null;
        return error == 'Las contraseñas no coinciden' ? error : null;
    }
  }

  Future<void> _guardar() async {
    if (_guardando) return;

    final error = _errorValidacion;
    if (error != null) {
      setState(() {
        _tocoActual = true;
        _tocoNueva = true;
        _tocoConfirmar = true;
      });
      return;
    }

    setState(() {
      _guardando = true;
      _errorServidor = null;
    });

    final resultado = await _perfilLogic.cambiarContrasena(
      actual: _actualController.text,
      nueva: _nuevaController.text,
      confirmacion: _confirmarController.text,
    );

    if (!mounted) return;

    if (resultado.exito) {
      // Único pop: el SnackBar de éxito lo muestra perfil_screen.
      Navigator.pop(context, true);
    } else {
      setState(() {
        _guardando = false;
        _errorServidor = resultado.error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubpantallaPerfil(
      titulo: 'Cambiar contraseña',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Container(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _campo(
                  controller: _actualController,
                  etiqueta: 'Contraseña actual',
                  campo: _CampoContrasena.actual,
                  visible: _verActual,
                  onToggle: () => setState(() => _verActual = !_verActual),
                  onChanged: () => setState(() {
                    _tocoActual = true;
                    _errorServidor = null;
                  }),
                ),
                const SizedBox(height: 16),
                _campo(
                  controller: _nuevaController,
                  etiqueta: 'Nueva contraseña',
                  campo: _CampoContrasena.nueva,
                  visible: _verNueva,
                  onToggle: () => setState(() => _verNueva = !_verNueva),
                  onChanged: () => setState(() {
                    _tocoNueva = true;
                    _errorServidor = null;
                  }),
                ),
                const SizedBox(height: 6),
                Text(
                  'Mínimo 8 caracteres',
                  style: GoogleFonts.poppins(fontSize: 12, color: _secundario),
                ),
                const SizedBox(height: 16),
                _campo(
                  controller: _confirmarController,
                  etiqueta: 'Confirmar nueva contraseña',
                  campo: _CampoContrasena.confirmar,
                  visible: _verConfirmar,
                  onToggle: () =>
                      setState(() => _verConfirmar = !_verConfirmar),
                  onChanged: () => setState(() {
                    _tocoConfirmar = true;
                    _errorServidor = null;
                  }),
                ),
                if (_errorServidor != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _errorServidor!,
                    style: GoogleFonts.poppins(fontSize: 13, color: _error),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
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
                      'Actualizar contraseña',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _campo({
    required TextEditingController controller,
    required String etiqueta,
    required _CampoContrasena campo,
    required bool visible,
    required VoidCallback onToggle,
    required VoidCallback onChanged,
  }) {
    return Material(
      elevation: 1,
      shadowColor: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      color: Colors.transparent,
      child: TextField(
        controller: controller,
        obscureText: !visible,
        onChanged: (_) => onChanged(),
        decoration: InputDecoration(
          labelText: etiqueta,
          prefixIcon: const Icon(Icons.lock_outline, color: _borde),
          errorText: _errorDeCampo(campo),
          errorStyle: GoogleFonts.poppins(fontSize: 12, color: _error),
          suffixIcon: IconButton(
            onPressed: onToggle,
            icon: Icon(
              visible ? Icons.visibility : Icons.visibility_off,
              color: _borde,
            ),
          ),
        ),
      ),
    );
  }
}

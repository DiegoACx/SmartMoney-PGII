import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/metas_logic.dart';
import '../logic/formato_utils.dart';
import '../services/notificaciones_service.dart';

// ===== Header decorativo curvo =====
class _CurvedHeaderClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, size.height - 60);
    final firstControl = Offset(size.width * 0.25, size.height + 20);
    final firstEnd = Offset(size.width * 0.5, size.height - 30);
    path.quadraticBezierTo(
      firstControl.dx,
      firstControl.dy,
      firstEnd.dx,
      firstEnd.dy,
    );
    final secondControl = Offset(size.width * 0.75, size.height - 80);
    final secondEnd = Offset(size.width, size.height - 40);
    path.quadraticBezierTo(
      secondControl.dx,
      secondControl.dy,
      secondEnd.dx,
      secondEnd.dy,
    );
    path.lineTo(size.width, 0);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

class RegistroMetaScreen extends StatefulWidget {
  final Map<String, dynamic>? metaExistente;

  const RegistroMetaScreen({
    super.key,
    this.metaExistente,
  });

  @override
  State<RegistroMetaScreen> createState() => _RegistroMetaScreenState();
}

class _RegistroMetaScreenState extends State<RegistroMetaScreen> {
  bool get _esModoEdicion => widget.metaExistente != null;

  final _formKey = GlobalKey<FormState>();
  final _nombreController = TextEditingController();
  final _montoController = TextEditingController();
  final _fechaController = TextEditingController();

  DateTime? _fechaLimiteSeleccionada;
  bool _isLoading = false;
  bool _fechaFueModificada = false;

  final _metasLogic = MetasLogic();
  final _notificacionesService = NotificacionesService();
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _formatoMiles = NumberFormat.decimalPattern('es_CO');

  @override
  void initState() {
    super.initState();
    if (_esModoEdicion) {
      _prellenarDesdeMetaExistente();
    }
  }

  void _prellenarDesdeMetaExistente() {
    final m = widget.metaExistente!;
    final nombre = m['nombre']?.toString() ?? '';
    final montoObjetivo = (m['monto_objetivo'] as num).toDouble();
    final montoInt = montoObjetivo.toInt();
    final fechaLimiteStr = m['fecha_limite'] as String?;

    setState(() {
      _nombreController.text = nombre;
      _montoController.text = _formatoMiles.format(montoInt);
      if (fechaLimiteStr != null) {
        final fecha = DateTime.tryParse(fechaLimiteStr);
        if (fecha != null) {
          _fechaLimiteSeleccionada = fecha;
          _fechaController.text = _dateFormat.format(fecha);
        }
      }
    });
  }

  @override
  void dispose() {
    _nombreController.dispose();
    _montoController.dispose();
    _fechaController.dispose();
    super.dispose();
  }

  // ===== Crear meta =====
  Future<void> _crearMeta() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final montoStr = _montoController.text.trim().replaceAll('.', '');
    final monto = double.parse(montoStr);
    final nombre = _nombreController.text.trim();

    final resultado = await _metasLogic.crearMeta(
      nombre: nombre,
      montoObjetivo: monto,
      fechaLimite: _fechaLimiteSeleccionada,
    );

    if (!mounted) return;

    if (resultado.exito) {
      final meta = resultado.metaCreada!;
      final metaId = meta['id'].toString();

      if (_fechaLimiteSeleccionada != null) {
        final fechaRecordatorio =
            _metasLogic.calcularFechaRecordatorio(_fechaLimiteSeleccionada);
        if (fechaRecordatorio != null) {
          try {
            await _notificacionesService
                .programarRecordatorio(
                  metaId: metaId,
                  nombreMeta: nombre,
                  fecha: fechaRecordatorio,
                )
                .timeout(const Duration(seconds: 5));
          } catch (e) {
            debugPrint(
              'ERROR PROGRAMAR NOTIFICACIÓN (meta nueva $metaId): $e',
            );
          }
        }
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('¡Meta creada!'),
          backgroundColor: const Color(0xFF7A9B6C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() => _isLoading = false);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(resultado.error!),
          backgroundColor: const Color(0xFFC0392B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ===== Editar meta =====
  Future<void> _editarMeta() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final metaId = widget.metaExistente!['id'].toString();
    final montoStr = _montoController.text.trim().replaceAll('.', '');
    final monto = double.parse(montoStr);
    final nombre = _nombreController.text.trim();

    final error = await _metasLogic.editarMeta(
      metaId: metaId,
      nombre: nombre,
      montoObjetivo: monto,
      fechaLimite: _fechaLimiteSeleccionada,
      quitarFecha: _fechaFueModificada && _fechaLimiteSeleccionada == null,
    );

    if (!mounted) return;

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cambios guardados'),
          backgroundColor: const Color(0xFF7A9B6C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      setState(() => _isLoading = false);
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context, true);
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: const Color(0xFFC0392B),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    }
  }

  // ===== Selector de fecha =====
  Future<void> _seleccionarFecha() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 7)),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('es', 'ES'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF58774B),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Color(0xFF2B2B2B),
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _fechaLimiteSeleccionada = picked;
        _fechaController.text = _dateFormat.format(picked);
        _fechaFueModificada = true;
      });
    }
  }

  void _quitarFecha() {
    setState(() {
      _fechaLimiteSeleccionada = null;
      _fechaController.clear();
      _fechaFueModificada = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final titulo = _esModoEdicion ? 'Editar meta' : 'Nueva meta';
    final textoBoton = _esModoEdicion ? 'Guardar cambios' : 'Crear meta';
    final onPressedBoton = _isLoading
        ? null
        : (_esModoEdicion ? _editarMeta : _crearMeta);

    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            children: [
              // ===== Encabezado decorativo =====
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.22,
                width: double.infinity,
                child: ClipPath(
                  clipper: _CurvedHeaderClipper(),
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF58774B),
                          Color(0xFF7A9B6C),
                        ],
                      ),
                    ),
                    child: Center(
                      child: Text(
                        titulo,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ===== Contenido del formulario =====
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ===== Campo Nombre =====
                      Text(
                        'Nombre',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF2B2B2B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Material(
                        elevation: 1,
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.transparent,
                        child: TextFormField(
                          controller: _nombreController,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Ingresa un nombre para la meta';
                            }
                            return null;
                          },
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF2B2B2B),
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Nombre',
                            labelStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: const Icon(
                              Icons.label_outline,
                              color: Color(0xFFC9C2B0),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ===== Campo Monto objetivo =====
                      Text(
                        'Monto objetivo',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF2B2B2B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Material(
                        elevation: 1,
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.transparent,
                        child: TextFormField(
                          controller: _montoController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [MilesInputFormatter()],
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Ingresa un monto objetivo';
                            }
                            final digitsOnly = value
                                .trim()
                                .replaceAll(RegExp(r'[^0-9]'), '');
                            if (digitsOnly.isEmpty) return 'Ingresa un monto';
                            final n = double.tryParse(digitsOnly);
                            if (n == null || n <= 0) {
                              return 'El monto debe ser mayor a 0';
                            }
                            return null;
                          },
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF2B2B2B),
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Monto objetivo',
                            labelStyle: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: const Icon(
                              Icons.savings_outlined,
                              color: Color(0xFFC9C2B0),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // ===== Campo Fecha límite (opcional) =====
                      Text(
                        'Fecha límite (opcional)',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF2B2B2B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Material(
                        elevation: 1,
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.transparent,
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _fechaController,
                                readOnly: true,
                                onTap: _seleccionarFecha,
                                decoration: InputDecoration(
                                  labelText: 'Fecha límite',
                                  prefixIcon: const Icon(
                                    Icons.calendar_today_outlined,
                                    color: Color(0xFFC9C2B0),
                                  ),
                                ),
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFF2B2B2B),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (_fechaLimiteSeleccionada != null)
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8),
                                child: TextButton.icon(
                                  onPressed: _quitarFecha,
                                  icon: const Icon(
                                    Icons.close,
                                    size: 16,
                                    color: Color(0xFFC0392B),
                                  ),
                                  label: Text(
                                    'Quitar fecha',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFFC0392B),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),

                      // ===== Botón principal =====
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [
                                Color(0xFF58774B),
                                Color(0xFF7A9B6C),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: ElevatedButton(
                            onPressed: onPressedBoton,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : Text(
                                    textoBoton,
                                    style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
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

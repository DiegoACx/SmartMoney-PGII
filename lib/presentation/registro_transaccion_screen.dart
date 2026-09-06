import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../logic/transacciones_logic.dart';
import '../logic/categorias_logic.dart';

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

class RegistroTransaccionScreen extends StatefulWidget {
  const RegistroTransaccionScreen({super.key});

  @override
  State<RegistroTransaccionScreen> createState() =>
      _RegistroTransaccionScreenState();
}

class _RegistroTransaccionScreenState
    extends State<RegistroTransaccionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _montoController = TextEditingController();
  final _fechaController = TextEditingController();
  final _notaController = TextEditingController();

  DateTime _fechaSeleccionada = DateTime.now();
  String? _tipoSeleccionado; // 'ingreso' o 'egreso'
  String? _categoriaSeleccionadaId;

  List<Map<String, dynamic>> _categorias = [];
  bool _cargandoCategorias = true;
  bool _errorCategorias = false;
  bool _isLoading = false;

  final _transaccionesLogic = TransaccionesLogic();
  final _categoriasLogic = CategoriasLogic();
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void initState() {
    super.initState();
    _fechaController.text = _dateFormat.format(_fechaSeleccionada);
    _cargarCategorias();
  }

  @override
  void dispose() {
    _montoController.dispose();
    _fechaController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  // ===== Carga de categorías =====
  Future<void> _cargarCategorias() async {
    setState(() {
      _cargandoCategorias = true;
      _errorCategorias = false;
    });
    try {
      final lista = await _categoriasLogic.obtenerCategoriasDisponibles();
      if (!mounted) return;
      setState(() {
        _categorias = lista;
        _cargandoCategorias = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _errorCategorias = true;
        _cargandoCategorias = false;
      });
    }
  }

  // ===== Validación custom de tipo y categoría =====
  String? _errorTipo;
  String? _errorCategoria;

  bool _validarAntesDeEnviar() {
    setState(() {
      _errorTipo = _tipoSeleccionado == null ? 'Selecciona un tipo' : null;
      _errorCategoria =
          _categoriaSeleccionadaId == null ? 'Selecciona una categoría' : null;
    });
    return _formKey.currentState!.validate() &&
        _errorTipo == null &&
        _errorCategoria == null;
  }

  // ===== Guardar transacción =====
  Future<void> _guardar() async {
    if (!_validarAntesDeEnviar()) return;

    final categoriasIds = _categorias
        .map((c) => c['id'].toString())
        .toList();

    setState(() => _isLoading = true);

    final error = await _transaccionesLogic.registrarTransaccion(
      monto: double.parse(_montoController.text.trim()),
      tipo: _tipoSeleccionado!,
      categoriaId: _categoriaSeleccionadaId!,
      fecha: _fechaSeleccionada,
      nota: _notaController.text.trim().isEmpty
          ? null
          : _notaController.text.trim(),
      categoriasValidas: categoriasIds,
    );

    if (!mounted) return;

    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('¡Transacción guardada!'),
          backgroundColor: const Color(0xFF7A9B6C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      // Limpiar formulario
      _formKey.currentState!.reset();
      _montoController.clear();
      _notaController.clear();
      setState(() {
        _tipoSeleccionado = null;
        _categoriaSeleccionadaId = null;
        _fechaSeleccionada = DateTime.now();
        _fechaController.text = _dateFormat.format(_fechaSeleccionada);
        _isLoading = false;
      });
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      Navigator.pop(context);
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
      initialDate: _fechaSeleccionada,
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
        _fechaSeleccionada = picked;
        _fechaController.text = _dateFormat.format(picked);
      });
    }
  }

  // ===== Diálogo para crear categoría nueva =====
  Future<void> _mostrarDialogCrearCategoria() async {
    final nombreCtrl = TextEditingController();
    String? tipoCat;
    String? errorMsg;
    bool creando = false;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFFFAF6EA),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Nueva categoría',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF2B2B2B),
                ),
              ),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Campo Nombre
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
                          controller: nombreCtrl,
                          autovalidateMode:
                              AutovalidateMode.onUserInteraction,
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) {
                              return 'Ingresa un nombre';
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
                              color: Color(0xFF787D7D),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Selector Tipo
                      Text(
                        'Tipo',
                        style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF2B2B2B),
                        ),
                      ),
                      const SizedBox(height: 6),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment<String>(
                            value: 'ingreso',
                            label: Text('Ingreso'),
                            icon: Icon(Icons.arrow_upward),
                          ),
                          ButtonSegment<String>(
                            value: 'egreso',
                            label: Text('Egreso'),
                            icon: Icon(Icons.arrow_downward),
                          ),
                        ],
                        emptySelectionAllowed: true,
                        selected: {tipoCat}.whereType<String>().toSet(),
                        onSelectionChanged: creando
                            ? null
                            : (s) {
                                setDialogState(() {
                                  tipoCat = s.isEmpty ? null : s.first;
                                  errorMsg = null;
                                });
                              },
                        style: ButtonStyle(
                          foregroundColor:
                              WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected)
                                ? Colors.white
                                : const Color(0xFF787D7D),
                          ),
                          backgroundColor:
                              WidgetStateProperty.resolveWith(
                            (s) => s.contains(WidgetState.selected)
                                ? const Color(0xFF58774B)
                                : Colors.white,
                          ),
                          side: WidgetStatePropertyAll(
                            BorderSide(
                              color: errorMsg != null && tipoCat == null
                                  ? const Color(0xFFC0392B)
                                  : const Color(0xFFE0E0E0),
                            ),
                          ),
                          shape: WidgetStatePropertyAll(
                            RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          textStyle: WidgetStatePropertyAll(
                            GoogleFonts.poppins(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ),

                      // Mensaje de error inline
                      if (errorMsg != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 16,
                                color: Color(0xFFC0392B),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  errorMsg!,
                                  style: GoogleFonts.poppins(
                                    color: const Color(0xFFC0392B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Botones
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: creando
                                  ? null
                                  : () => Navigator.pop(ctx, null),
                              child: Text(
                                'Cancelar',
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFF787D7D),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
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
                                  onPressed: creando
                                      ? null
                                      : () async {
                                          // Validación local
                                          if (!formKey.currentState!
                                              .validate()) {
                                            setDialogState(() =>
                                                errorMsg =
                                                    'Completa todos los campos');
                                            return;
                                          }
                                          if (tipoCat == null) {
                                            setDialogState(() =>
                                                errorMsg =
                                                    'Selecciona un tipo');
                                            return;
                                          }
                                          setDialogState(() {
                                            creando = true;
                                            errorMsg = null;
                                          });
                                          final resultado =
                                              await _categoriasLogic
                                                  .crearCategoria(
                                            nombre: nombreCtrl.text,
                                            tipo: tipoCat!,
                                          );
                                          if (!ctx.mounted) return;
                                          if (resultado.exito) {
                                            Navigator.pop(
                                                ctx, resultado.categoria);
                                          } else {
                                            setDialogState(() {
                                              creando = false;
                                              errorMsg =
                                                  resultado.mensajeError;
                                            });
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.transparent,
                                    shadowColor: Colors.transparent,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: creando
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child:
                                              CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2.5,
                                          ),
                                        )
                                      : Text(
                                          'Crear',
                                          style: GoogleFonts.poppins(
                                            color: Colors.white,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    // Si el diálogo retornó la categoría creada
    if (result != null && mounted) {
      setState(() {
        _categorias.add(result);
        _categoriaSeleccionadaId = result['id'].toString();
        _errorCategoria = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Categoría creada'),
          backgroundColor: const Color(0xFF7A9B6C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF6EA),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF58774B),
          onRefresh: _cargarCategorias,
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
                          'Nueva transacción',
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
                        // ===== Campo Monto =====
                        Text(
                          'Monto',
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
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Ingresa un monto';
                              }
                              final n = double.tryParse(value.trim());
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
                              labelText: 'Monto',
                              labelStyle: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                              prefixIcon: const Icon(
                                Icons.attach_money,
                                color: Color(0xFF787D7D),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ===== Selector Tipo =====
                        Text(
                          'Tipo',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF2B2B2B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment<String>(
                              value: 'ingreso',
                              label: Text('Ingreso'),
                              icon: Icon(Icons.arrow_upward),
                            ),
                            ButtonSegment<String>(
                              value: 'egreso',
                              label: Text('Egreso'),
                              icon: Icon(Icons.arrow_downward),
                            ),
                          ],
                          emptySelectionAllowed: true,
                          selected: {
                            _tipoSeleccionado,
                          }.whereType<String>().toSet(),
                          onSelectionChanged: (s) {
                            setState(() {
                              _tipoSeleccionado = s.first;
                              _errorTipo = null;
                            });
                          },
                          style: ButtonStyle(
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.selected)
                                  ? Colors.white
                                  : const Color(0xFF787D7D),
                            ),
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (s) => s.contains(WidgetState.selected)
                                  ? const Color(0xFF58774B)
                                  : Colors.white,
                            ),
                            side: WidgetStatePropertyAll(
                              BorderSide(
                                color: _errorTipo != null
                                    ? const Color(0xFFC0392B)
                                    : const Color(0xFFE0E0E0),
                              ),
                            ),
                            shape: WidgetStatePropertyAll(
                              RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            textStyle: WidgetStatePropertyAll(
                              GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                        if (_errorTipo != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4),
                            child: Text(
                              _errorTipo!,
                              style: GoogleFonts.poppins(
                                color: const Color(0xFFC0392B),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),

                        // ===== Selector Categoría =====
                        Text(
                          'Categoría',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF2B2B2B),
                          ),
                        ),
                        const SizedBox(height: 6),
                        _cargandoCategorias
                            ? Container(
                                width: double.infinity,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                          alpha: 0.05),
                                      blurRadius: 2,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Center(
                                  child: SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Color(0xFF58774B),
                                    ),
                                  ),
                                ),
                              )
                            : _errorCategorias
                                ? Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFC0392B)
                                          .withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(
                                        color: const Color(0xFFC0392B)
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(
                                              Icons.warning_amber_outlined,
                                              color: Color(0xFFC0392B),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'No se pudieron cargar las categorías, desliza hacia abajo para reintentar',
                                                style: GoogleFonts.poppins(
                                                  color: const Color(0xFF2B2B2B),
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  )
                                : Material(
                                    elevation: 1,
                                    borderRadius: BorderRadius.circular(14),
                                    color: Colors.transparent,
                                    child: DropdownButtonFormField<String>(
                                      // ignore: deprecated_member_use
                                      value: _categoriaSeleccionadaId,
                                      autovalidateMode: AutovalidateMode
                                          .onUserInteraction,
                                      validator: (_) => _errorCategoria,
                                      decoration: InputDecoration(
                                        labelText: 'Categoría',
                                        prefixIcon: const Icon(
                                          Icons.category_outlined,
                                          color: Color(0xFF787D7D),
                                        ),
                                        errorStyle: GoogleFonts.poppins(
                                          color: const Color(0xFFC0392B),
                                          fontSize: 12,
                                        ),
                                      ),
                                      items: [
                                        ..._categorias.map((c) {
                                          return DropdownMenuItem<String>(
                                            value: c['id'].toString(),
                                            child: Text(
                                              c['nombre'].toString(),
                                              style: GoogleFonts.poppins(
                                                color:
                                                    const Color(0xFF2B2B2B),
                                                fontSize: 14,
                                              ),
                                            ),
                                          );
                                        }),
                                        DropdownMenuItem<String>(
                                          value: '__crear_nueva__',
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.add,
                                                color: Color(0xFF58774B),
                                                size: 18,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Crear nueva categoría',
                                                style: GoogleFonts.poppins(
                                                  color:
                                                      const Color(0xFF58774B),
                                                  fontSize: 14,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                      onChanged: (v) {
                                        if (v == '__crear_nueva__') {
                                          // No actualizamos _categoriaSeleccionadaId,
                                          // abrimos el diálogo y al cerrar
                                          // la selección queda intacta
                                          _mostrarDialogCrearCategoria();
                                        } else {
                                          setState(() {
                                            _categoriaSeleccionadaId = v;
                                            _errorCategoria = null;
                                          });
                                        }
                                      },
                                      borderRadius: BorderRadius.circular(14),
                                      style: GoogleFonts.poppins(
                                        color: const Color(0xFF2B2B2B),
                                        fontSize: 14,
                                      ),
                                      icon: const Icon(
                                        Icons.keyboard_arrow_down,
                                        color: Color(0xFF787D7D),
                                      ),
                                    ),
                                  ),
                        if (_errorCategoria != null && !_errorCategorias)
                          Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4),
                            child: Text(
                              _errorCategoria!,
                              style: GoogleFonts.poppins(
                                color: const Color(0xFFC0392B),
                                fontSize: 12,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),
                        const SizedBox(height: 20),

                        // ===== Campo Fecha =====
                        Text(
                          'Fecha',
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
                            controller: _fechaController,
                            readOnly: true,
                            onTap: _seleccionarFecha,
                            decoration: InputDecoration(
                              labelText: 'Fecha',
                              prefixIcon: const Icon(
                                Icons.calendar_today_outlined,
                                color: Color(0xFF787D7D),
                              ),
                            ),
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF2B2B2B),
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // ===== Campo Nota =====
                        Text(
                          'Nota (opcional)',
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
                            controller: _notaController,
                            maxLines: 3,
                            minLines: 2,
                            decoration: InputDecoration(
                              labelText: 'Nota',
                              prefixIcon: const Padding(
                                padding: EdgeInsets.only(bottom: 40),
                                child: Icon(
                                  Icons.edit_note,
                                  color: Color(0xFF787D7D),
                                ),
                              ),
                              alignLabelWithHint: true,
                            ),
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF2B2B2B),
                              fontSize: 14,
                            ),
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
                              onPressed: _isLoading || _errorCategorias
                                  ? null
                                  : _guardar,
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
                                      'Guardar transacción',
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
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../data/clasificador_repository.dart';
import '../logic/registro_transaccion_logic.dart';
import '../logic/transacciones_logic.dart';
import '../logic/categorias_logic.dart';
import '../logic/formato_utils.dart';

// ===== Paleta del sistema de diseño =====
const Color _verde = Color(0xFF58774B);
const Color _verdeClaro = Color(0xFF7A9B6C);
const Color _crema = Color(0xFFFAF6EA);
const Color _grisTexto = Color(0xFF8C8474);
const Color _tinta = Color(0xFF2B2B2B);
const Color _rojo = Color(0xFFC0392B);
const Color _grisIcono = Color(0xFFC9C2B0);
const Color _bordeSuave = Color(0xFFEDE7D8);
const Color _sombraSutil = Color(0x12000000);

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
  final Map<String, dynamic>? transaccionExistente;

  const RegistroTransaccionScreen({
    super.key,
    this.transaccionExistente,
  });

  @override
  State<RegistroTransaccionScreen> createState() =>
      _RegistroTransaccionScreenState();
}

class _RegistroTransaccionScreenState extends State<RegistroTransaccionScreen> {
  bool get _esModoEdicion => widget.transaccionExistente != null;

  final _montoController = TextEditingController();
  final _fechaController = TextEditingController();
  final _notaController = TextEditingController();

  DateTime _fechaSeleccionada = DateTime.now();
  String? _tipoSeleccionado; // 'ingreso' o 'egreso'
  String? _categoriaSeleccionadaId;
  String? _metodoPagoSeleccionado; // 'efectivo' o 'transferencia'
  bool _esGastoTrabajo = false;

  List<Map<String, dynamic>> _categorias = [];
  List<Map<String, dynamic>> _gruposReferencia = [];
  bool _cargandoCategorias = true;
  bool _errorCategorias = false;
  bool _isLoading = false;

  // ===== Errores de validación (texto rojo bajo cada campo, sin fondo) =====
  String? _errorMonto;
  String? _errorTipo;
  String? _errorMetodoPago;
  String? _errorDescripcion;
  String? _errorCategoria;

  // ===== Sugerencia del clasificador (solo egresos) =====
  SugerenciaCategoria? _sugerencia;
  bool _consultandoSugerencia = false;
  bool _sugerenciaResuelta = false;
  bool _categoriaElegidaManualmente = false;
  bool _categoriaSugeridaAplicada = false;
  bool _descripcionModificada = false;
  String _descripcionOriginal = '';
  Timer? _debounceClasificador;
  int _peticionClasificador = 0;

  final _transaccionesLogic = TransaccionesLogic();
  final _categoriasLogic = CategoriasLogic();
  final _clasificadorRepository = ClasificadorRepository();
  final _registroLogic = RegistroTransaccionLogic();
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final _formatoMiles = NumberFormat.decimalPattern('es_CO');

  @override
  void initState() {
    super.initState();
    _fechaController.text = _dateFormat.format(_fechaSeleccionada);
    _cargarCategorias();
  }

  @override
  void dispose() {
    _debounceClasificador?.cancel();
    _montoController.dispose();
    _fechaController.dispose();
    _notaController.dispose();
    super.dispose();
  }

  // ===== Visibilidad y estado derivados =====

  /// El campo Categoría solo aparece cuando la descripción del egreso ya
  /// tiene contenido (2 caracteres útiles). Para ingresos siempre está.
  bool get _mostrarCampoCategoria => _registroLogic.mostrarCategoria(
        tipo: _tipoSeleccionado,
        descripcion: _notaController.text,
      );

  /// Nota que acompaña a la descripción mientras la categoría está oculta.
  bool get _mostrarNotaSugerenciaAutomatica =>
      _tipoSeleccionado == 'egreso' && !_mostrarCampoCategoria;

  /// La categoría seleccionada vino de la sugerencia y sigue vigente.
  bool get _mostrarChipSugerida {
    final sugerencia = _sugerencia;
    return _categoriaSugeridaAplicada &&
        sugerencia != null &&
        sugerencia.categoriaId != null &&
        _categoriaSeleccionadaId == sugerencia.categoriaId;
  }

  /// Se consultó al clasificador y no hay ninguna categoría que ofrecer.
  bool get _sinSugerenciaDisponible =>
      _tipoSeleccionado == 'egreso' &&
      _mostrarCampoCategoria &&
      !_consultandoSugerencia &&
      _sugerenciaResuelta &&
      _categoriaSeleccionadaId == null;

  /// Sugerencia aplicable en modo edición: hay que tocarla para aceptarla.
  /// Es null si no se cambió la descripción, si no hay sugerencia, si no pasa
  /// el umbral (`preseleccionar`), si coincide con la categoría actual o si esa
  /// categoría no está disponible.
  SugerenciaCategoria? get _sugerenciaEdicion {
    final sugerencia = _sugerencia;
    if (!_esModoEdicion || !_descripcionModificada) return null;
    if (sugerencia == null || sugerencia.categoriaId == null) return null;
    if (!sugerencia.preseleccionar) return null;
    if (sugerencia.categoriaId == _categoriaSeleccionadaId) return null;
    final existe = _categoriasVisibles.any(
      (c) => c['id'].toString() == sugerencia.categoriaId,
    );
    return existe ? sugerencia : null;
  }

  /// Categorías ofrecidas según el tipo.
  /// - Ingreso: como antes (propias + predeterminadas de ingreso).
  /// - Egreso: solo las 14 predeterminadas (usuario_id null). Si se está
  ///   editando un movimiento con categoría propia, esa se incluye para no
  ///   perder la selección guardada.
  /// - Sin tipo elegido: todas (el tipo se elige antes que la categoría).
  List<Map<String, dynamic>> get _categoriasVisibles {
    final tipo = _tipoSeleccionado;
    if (tipo == null) return _categorias;
    if (tipo == 'ingreso') {
      return _categorias.where((c) => c['tipo'] == 'ingreso').toList();
    }
    return _categorias
        .where((c) =>
            c['tipo'] == 'egreso' &&
            (c['usuario_id'] == null ||
                c['id'].toString() == _categoriaSeleccionadaId))
        .toList();
  }

  // ===== Carga de categorías y grupos de referencia =====
  Future<void> _cargarCategorias() async {
    setState(() {
      _cargandoCategorias = true;
      _errorCategorias = false;
    });

    // 1) Categorías: carga crítica del formulario. Su fallo sí bloquea el
    //    registro (sin categorías no se puede guardar un movimiento).
    List<Map<String, dynamic>> lista = [];
    var errorCategorias = false;
    try {
      lista = await _categoriasLogic.obtenerCategoriasDisponibles();
    } catch (e) {
      debugPrint('DEBUG ERROR categorias: $e');
      errorCategorias = true;
    }

    // 2) Grupos de referencia: carga auxiliar (solo para el desplegable
    //    "Grupo" al crear una categoría propia). Su fallo NO debe impedir
    //    cargar las categorías ni registrar movimientos.
    List<Map<String, dynamic>> grupos = [];
    try {
      grupos = await _categoriasLogic.obtenerGruposReferencia();
    } catch (e) {
      debugPrint('DEBUG ERROR grupos_referencia: $e');
    }

    if (!mounted) return;
    setState(() {
      _categorias = lista;
      _gruposReferencia = grupos;
      _errorCategorias = errorCategorias;
      _cargandoCategorias = false;
    });
    if (_esModoEdicion) {
      _prellenarDesdeTransaccionExistente(lista);
    }
  }

  void _prellenarDesdeTransaccionExistente(
      List<Map<String, dynamic>> categoriasCargadas) {
    final t = widget.transaccionExistente!;
    final monto = (t['monto'] as num).toDouble();
    final montoInt = monto.toInt();
    setState(() {
      _montoController.text = _formatoMiles.format(montoInt);
      _tipoSeleccionado = t['tipo'] as String?;
      _fechaSeleccionada = DateTime.parse(t['fecha'] as String);
      _fechaController.text = _dateFormat.format(_fechaSeleccionada);
      _metodoPagoSeleccionado = t['metodo_pago'] as String?;
      // El interruptor ya no se muestra: se conserva el valor guardado.
      _esGastoTrabajo = t['es_gasto_trabajo'] == true;
      final desc = t['descripcion'];
      if (desc != null && desc.toString().trim().isNotEmpty) {
        _notaController.text = desc.toString().trim();
      }
      _descripcionOriginal = _notaController.text.trim();
      final catId = t['categoria_id']?.toString();
      if (catId != null) {
        final existe = categoriasCargadas
            .any((c) => c['id'].toString() == catId);
        if (existe) {
          _categoriaSeleccionadaId = catId;
        }
      }
    });
  }

  // ===== Sugerencia de categoría (clasificador, solo egresos) =====

  /// Grupo de referencia de una categoría cargada (null si no se encuentra).
  int? _grupoDeCategoria(String categoriaId) {
    for (final c in _categorias) {
      if (c['id'].toString() == categoriaId) {
        final grupo = c['grupo_id'];
        return grupo is num ? grupo.toInt() : null;
      }
    }
    return null;
  }

  /// Se dispara con cada cambio de la descripción: espera 600 ms sin teclas
  /// nuevas antes de consultar, y descarta cualquier respuesta anterior.
  void _onDescripcionCambiada(String texto) {
    final limpio = texto.trim();

    if (_tipoSeleccionado != 'egreso') {
      if (_errorDescripcion != null) {
        setState(() => _errorDescripcion = null);
      }
      return;
    }

    // En edición: si la descripción sigue igual a la guardada, no se consulta
    // ni se pierde la categoría que ya tenía.
    if (_esModoEdicion) {
      _descripcionModificada = limpio != _descripcionOriginal;
      if (!_descripcionModificada) {
        _debounceClasificador?.cancel();
        _peticionClasificador++;
        setState(() {
          _errorDescripcion = null;
          _sugerencia = null;
          _consultandoSugerencia = false;
          _sugerenciaResuelta = false;
          _categoriaSugeridaAplicada = false;
        });
        return;
      }
    }

    _debounceClasificador?.cancel();
    _peticionClasificador++;

    if (limpio.length < 2) {
      setState(() {
        _errorDescripcion = null;
        _sugerencia = null;
        _consultandoSugerencia = false;
        _sugerenciaResuelta = false;
        _categoriaSugeridaAplicada = false;
      });
      return;
    }

    // Hace visible el campo Categoría de inmediato (sin esperar al servidor).
    setState(() {
      _errorDescripcion = null;
      _sugerenciaResuelta = false;
    });

    _debounceClasificador = Timer(
      const Duration(milliseconds: 600),
      () => _consultarSugerencia(limpio),
    );
  }

  Future<void> _consultarSugerencia(String descripcion) async {
    final peticion = ++_peticionClasificador;
    if (mounted) setState(() => _consultandoSugerencia = true);

    final sugerencia =
        await _clasificadorRepository.sugerirCategoria(descripcion);

    // Respuesta vieja: ya hay una consulta más reciente en curso.
    if (!mounted || peticion != _peticionClasificador) return;

    setState(() {
      _consultandoSugerencia = false;
      _sugerenciaResuelta = true;
      _sugerencia = sugerencia;

      final categoriaId = sugerencia?.categoriaId;
      final categoriaExiste = categoriaId != null &&
          _categoriasVisibles.any((c) => c['id'].toString() == categoriaId);

      final aplicar = _registroLogic.categoriaTrasSugerencia(
        categoriaSugeridaId: categoriaId,
        preseleccionar: sugerencia?.preseleccionar == true,
        categoriaExiste: categoriaExiste,
        elegidaManualmente: _categoriaElegidaManualmente,
        categoriaActualId: _categoriaSeleccionadaId,
      );

      // En edición nunca se reemplaza sola la categoría ya guardada.
      if (_esModoEdicion || aplicar == null) return;

      _categoriaSeleccionadaId = aplicar;
      _errorCategoria = null;
      _categoriaSugeridaAplicada = true;
    });
  }

  /// Acepta la sugerencia en edición: cuenta como elección del usuario.
  void _aplicarSugerenciaEdicion(String categoriaId) {
    setState(() {
      _categoriaElegidaManualmente = true;
      _categoriaSeleccionadaId = categoriaId;
      _categoriaSugeridaAplicada = false;
      _errorCategoria = null;
    });
  }

  // ===== Acciones del formulario =====

  void _onTipoCambiado(Set<String> seleccion) {
    setState(() {
      _tipoSeleccionado = seleccion.first;
      _errorTipo = null;
      if (_tipoSeleccionado != 'egreso') {
        _debounceClasificador?.cancel();
        _peticionClasificador++;
        _sugerencia = null;
        _consultandoSugerencia = false;
        _sugerenciaResuelta = false;
        _categoriaSugeridaAplicada = false;
        _categoriaElegidaManualmente = false;
      }
      // Si la categoría elegida no pertenece al nuevo tipo, se limpia.
      if (_categoriaSeleccionadaId != null &&
          !_categorias.any((c) =>
              c['id'].toString() == _categoriaSeleccionadaId &&
              c['tipo'] == _tipoSeleccionado)) {
        _categoriaSeleccionadaId = null;
        _errorCategoria = null;
      }
    });
    // Si pasa a egreso con una descripción ya escrita (por ejemplo una nota
    // de ingreso), se clasifica de una vez.
    if (_tipoSeleccionado == 'egreso') {
      _onDescripcionCambiada(_notaController.text);
    }
  }

  void _onCategoriaCambiada(String? valor) {
    if (valor == null) return;
    // El usuario tocó el desplegable: la sugerencia ya no manda sobre ella.
    _categoriaElegidaManualmente = true;
    if (valor == '__crear_nueva__') {
      _mostrarDialogCrearCategoria();
      return;
    }
    setState(() {
      _categoriaSeleccionadaId = valor;
      _categoriaSugeridaAplicada = false;
      _errorCategoria = null;
    });
  }

  // ===== Validación (orden: Monto → Tipo → Método de pago → Descripción →
  // Categoría) =====

  String? _errorDe(ErrorFormulario? error, CampoFormulario campo) =>
      error?.campo == campo ? error!.mensaje : null;

  bool _validarAntesDeEnviar() {
    final error = _registroLogic.validar(
      montoTexto: _montoController.text,
      tipo: _tipoSeleccionado,
      metodoPago: _metodoPagoSeleccionado,
      descripcion: _notaController.text,
      categoriaVisible: _mostrarCampoCategoria,
      categoriaId: _categoriaSeleccionadaId,
    );
    setState(() {
      _errorMonto = _errorDe(error, CampoFormulario.monto);
      _errorTipo = _errorDe(error, CampoFormulario.tipo);
      _errorMetodoPago = _errorDe(error, CampoFormulario.metodoPago);
      _errorDescripcion = _errorDe(error, CampoFormulario.descripcion);
      _errorCategoria = _errorDe(error, CampoFormulario.categoria);
    });
    return error == null;
  }

  // ===== Guardar transacción =====
  Future<void> _guardar() async {
    FocusScope.of(context).unfocus();
    if (!_validarAntesDeEnviar()) return;

    final categoriasIds =
        _categorias.map((c) => c['id'].toString()).toList();

    setState(() => _isLoading = true);

    final monto = double.parse(_montoController.text.trim().replaceAll('.', ''));
    final tipo = _tipoSeleccionado!;
    final categoriaId = _categoriaSeleccionadaId!;
    final fecha = _fechaSeleccionada;
    final notaTexto = _notaController.text.trim();
    final nota = notaTexto.isEmpty ? null : notaTexto;
    final metodoPago = _metodoPagoSeleccionado!;
    // "Gasto de trabajo" ya no se edita aquí: al crear se envía su valor por
    // defecto (false) y al editar se conserva el valor guardado.
    final esGastoTrabajo = tipo == 'egreso' ? _esGastoTrabajo : false;

    // ===== Metadatos de la sugerencia (solo egresos) =====
    // En edición solo cuentan si el usuario cambió la descripción; si no, se
    // conservan los valores ya guardados. Si la descripción cambió y no hubo
    // sugerencia, se escriben en NULL explícito.
    final escribirMetadatosSugerencia =
        tipo == 'egreso' && (!_esModoEdicion || _descripcionModificada);
    final sugerencia = escribirMetadatosSugerencia ? _sugerencia : null;
    int? grupoSugeridoId;
    String? categoriaSugeridaId;
    double? confianzaSugerencia;
    String? versionModelo;
    bool? categoriaCorregida;
    if (sugerencia != null) {
      grupoSugeridoId = sugerencia.grupoId;
      categoriaSugeridaId = sugerencia.categoriaId;
      confianzaSugerencia = sugerencia.confianza;
      versionModelo = sugerencia.versionModelo;
      // Se comparan GRUPOS de referencia, no ids de categoría.
      final grupoFinal = _grupoDeCategoria(categoriaId);
      categoriaCorregida = grupoFinal == null || grupoFinal != grupoSugeridoId;
    }

    String? error;
    if (_esModoEdicion) {
      final transaccionId = widget.transaccionExistente!['id'].toString();
      error = await _transaccionesLogic.editarTransaccion(
        transaccionId: transaccionId,
        monto: monto,
        tipo: tipo,
        categoriaId: categoriaId,
        fecha: fecha,
        nota: nota,
        categoriasValidas: categoriasIds,
        metodoPago: metodoPago,
        esGastoTrabajo: esGastoTrabajo,
        grupoSugeridoId: grupoSugeridoId,
        categoriaSugeridaId: categoriaSugeridaId,
        confianzaSugerencia: confianzaSugerencia,
        categoriaCorregida: categoriaCorregida,
        versionModelo: versionModelo,
        escribirMetadatosSugerencia: escribirMetadatosSugerencia,
      );
    } else {
      error = await _transaccionesLogic.registrarTransaccion(
        monto: monto,
        tipo: tipo,
        categoriaId: categoriaId,
        fecha: fecha,
        nota: nota,
        categoriasValidas: categoriasIds,
        metodoPago: metodoPago,
        esGastoTrabajo: esGastoTrabajo,
        grupoSugeridoId: grupoSugeridoId,
        categoriaSugeridaId: categoriaSugeridaId,
        confianzaSugerencia: confianzaSugerencia,
        categoriaCorregida: categoriaCorregida,
        versionModelo: versionModelo,
      );
    }

    if (!mounted) return;

    if (error == null) {
      final mensajeExito =
          _esModoEdicion ? 'Cambios guardados' : '¡Transacción guardada!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mensajeExito),
          backgroundColor: _verdeClaro,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
      if (_esModoEdicion) {
        setState(() => _isLoading = false);
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.pop(context, true);
      } else {
        // Limpiar formulario
        _montoController.clear();
        _notaController.clear();
        _debounceClasificador?.cancel();
        _peticionClasificador++;
        setState(() {
          _tipoSeleccionado = null;
          _categoriaSeleccionadaId = null;
          _metodoPagoSeleccionado = null;
          _esGastoTrabajo = false;
          _fechaSeleccionada = DateTime.now();
          _fechaController.text = _dateFormat.format(_fechaSeleccionada);
          _sugerencia = null;
          _consultandoSugerencia = false;
          _sugerenciaResuelta = false;
          _categoriaElegidaManualmente = false;
          _categoriaSugeridaAplicada = false;
          _descripcionModificada = false;
          _errorMonto = null;
          _errorTipo = null;
          _errorMetodoPago = null;
          _errorDescripcion = null;
          _errorCategoria = null;
          _isLoading = false;
        });
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        Navigator.pop(context);
      }
    } else {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error),
          backgroundColor: _rojo,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
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
              primary: _verde,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: _tinta,
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

  // ===== Diálogo para crear categoría nueva (solo ingresos) =====
  Future<void> _mostrarDialogCrearCategoria() async {
    final nombreCtrl = TextEditingController();
    String? errorMsg;
    bool creando = false;
    int? grupoSeleccionadoId;
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<Map<String, dynamic>?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: _crema,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: Text(
                'Nueva categoría',
                style: GoogleFonts.poppins(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: _tinta,
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
                          color: _tinta,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Material(
                        elevation: 1,
                        shadowColor: Colors.transparent,
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
                            color: _tinta,
                            fontSize: 14,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Ej: Mercado',
                            prefixIcon: const Icon(
                              Icons.label_outline,
                              color: _grisIcono,
                            ),
                          ),
                        ),
                      ),

                      // Desplegable Grupo (solo para categorías de egreso)
                      if (_tipoSeleccionado == 'egreso') ...[
                        const SizedBox(height: 20),
                        Text(
                          'Grupo',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: _tinta,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Material(
                          elevation: 1,
                          shadowColor: Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          color: Colors.transparent,
                          child: DropdownButtonFormField<int>(
                            // ignore: deprecated_member_use
                            value: grupoSeleccionadoId,
                            autovalidateMode:
                                AutovalidateMode.onUserInteraction,
                            validator: (v) => v == null
                                ? 'Selecciona un grupo para la categoría de egreso'
                                : null,
                            decoration: InputDecoration(
                              hintText: 'Selecciona un grupo',
                              prefixIcon: const Icon(
                                Icons.category_outlined,
                                color: _grisIcono,
                              ),
                            ),
                            items: _gruposReferencia.map((g) {
                              return DropdownMenuItem<int>(
                                value: g['id'] as int,
                                child: Text(
                                  g['nombre'].toString(),
                                  style: GoogleFonts.poppins(
                                    color: _tinta,
                                    fontSize: 14,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (v) {
                              setDialogState(() => grupoSeleccionadoId = v);
                            },
                            borderRadius: BorderRadius.circular(14),
                            style: GoogleFonts.poppins(
                              color: _tinta,
                              fontSize: 14,
                            ),
                            icon: const Icon(
                              Icons.keyboard_arrow_down,
                              color: _grisIcono,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),

                      // Mensaje de error inline
                      if (errorMsg != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                size: 16,
                                color: _rojo,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  errorMsg!,
                                  style: GoogleFonts.poppins(
                                    color: _rojo,
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
                              onPressed:
                                  creando ? null : () => Navigator.pop(ctx, null),
                              child: Text(
                                'Cancelar',
                                style: GoogleFonts.poppins(
                                  color: _grisTexto,
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
                                    colors: [_verde, _verdeClaro],
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
                                            setDialogState(() => errorMsg =
                                                'Completa todos los campos');
                                            return;
                                          }
                                          if (_tipoSeleccionado == null) {
                                            setDialogState(() => errorMsg =
                                                'Selecciona un tipo de transacción antes');
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
                                            tipo: _tipoSeleccionado!,
                                            grupoId: _tipoSeleccionado ==
                                                    'egreso'
                                                ? grupoSeleccionadoId
                                                : null,
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
                                          child: CircularProgressIndicator(
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
        _categoriaElegidaManualmente = true;
        _categoriaSugeridaAplicada = false;
        _errorCategoria = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Categoría creada'),
          backgroundColor: _verdeClaro,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ===== Piezas visuales reutilizables =====

  TextStyle get _estiloEtiqueta => GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: _tinta,
        letterSpacing: 0.1,
      );

  Widget _etiqueta(String texto) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(texto, style: _estiloEtiqueta),
      );

  /// Tarjeta blanca con borde y sombra sutiles que envuelve un campo.
  Widget _tarjetaCampo({required Widget child, bool hayError = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hayError ? _rojo.withValues(alpha: 0.55) : _bordeSuave,
        ),
        boxShadow: const [
          BoxShadow(color: _sombraSutil, blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: child,
    );
  }

  /// Decoración sin relleno ni borde propios: el fondo lo pone la tarjeta.
  InputDecoration _decoracionCampo({
    String? hint,
    IconData? icono,
  }) {
    return InputDecoration(
      filled: false,
      isDense: true,
      hintText: hint,
      hintStyle: GoogleFonts.poppins(color: _grisIcono, fontSize: 14),
      prefixIcon:
          icono == null ? null : Icon(icono, color: _grisIcono, size: 20),
      prefixIconConstraints: const BoxConstraints(minWidth: 46),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    );
  }

  /// Error de validación: texto rojo pequeño bajo el campo, sin fondo.
  Widget _textoError(String texto) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 6),
        child: Text(
          texto,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _rojo,
          ),
        ),
      );

  /// Nota de ayuda bajo un campo (gris, discreta).
  Widget _textoAyuda(String texto) => Padding(
        padding: const EdgeInsets.only(top: 6, left: 6, right: 6),
        child: Text(
          texto,
          style: GoogleFonts.poppins(
            fontSize: 11,
            color: _grisTexto,
            height: 1.35,
          ),
        ),
      );

  ButtonStyle _estiloSegmento({required bool hayError}) {
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : _grisTexto,
      ),
      backgroundColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? _verde : Colors.white,
      ),
      side: WidgetStatePropertyAll(
        BorderSide(color: hayError ? _rojo : _bordeSuave),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textStyle: WidgetStatePropertyAll(
        GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14),
      ),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(vertical: 14),
      ),
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
    );
  }

  // ===== Bloques del formulario =====

  Widget _encabezado() {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.24,
      width: double.infinity,
      child: ClipPath(
        clipper: _CurvedHeaderClipper(),
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_verde, _verdeClaro],
            ),
          ),
          child: Align(
            alignment: const Alignment(0, -0.35),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.receipt_long_outlined,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _esModoEdicion ? 'Editar transacción' : 'Nueva transacción',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _esModoEdicion
                      ? 'Actualiza los datos del movimiento'
                      : 'Registra tu movimiento en segundos',
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bloqueMonto() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('Monto'),
        _tarjetaCampo(
          hayError: _errorMonto != null,
          child: TextField(
            controller: _montoController,
            keyboardType: TextInputType.number,
            inputFormatters: [MilesInputFormatter()],
            onChanged: (_) {
              if (_errorMonto != null) setState(() => _errorMonto = null);
            },
            style: GoogleFonts.poppins(
              color: _tinta,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
            decoration: _decoracionCampo(
              hint: '0',
              icono: Icons.attach_money,
            ),
          ),
        ),
        if (_errorMonto != null) _textoError(_errorMonto!),
      ],
    );
  }

  Widget _bloqueTipo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('Tipo'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'ingreso',
              label: Text('Ingreso'),
              icon: Icon(Icons.arrow_upward_rounded),
            ),
            ButtonSegment<String>(
              value: 'egreso',
              label: Text('Egreso'),
              icon: Icon(Icons.arrow_downward_rounded),
            ),
          ],
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          selected: {_tipoSeleccionado}.whereType<String>().toSet(),
          onSelectionChanged: _onTipoCambiado,
          style: _estiloSegmento(hayError: _errorTipo != null),
        ),
        if (_errorTipo != null) _textoError(_errorTipo!),
      ],
    );
  }

  Widget _bloqueMetodoPago() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('Método de pago'),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment<String>(
              value: 'efectivo',
              label: Text('Efectivo'),
              icon: Icon(Icons.payments_outlined),
            ),
            ButtonSegment<String>(
              value: 'transferencia',
              label: Text('Transferencia'),
              icon: Icon(Icons.account_balance_outlined),
            ),
          ],
          emptySelectionAllowed: true,
          showSelectedIcon: false,
          selected: {_metodoPagoSeleccionado}.whereType<String>().toSet(),
          onSelectionChanged: (s) {
            setState(() {
              _metodoPagoSeleccionado = s.first;
              _errorMetodoPago = null;
            });
          },
          style: _estiloSegmento(hayError: _errorMetodoPago != null),
        ),
        if (_errorMetodoPago != null) _textoError(_errorMetodoPago!),
      ],
    );
  }

  Widget _bloqueFecha() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta('Fecha'),
        _tarjetaCampo(
          child: TextField(
            controller: _fechaController,
            readOnly: true,
            onTap: _seleccionarFecha,
            style: GoogleFonts.poppins(color: _tinta, fontSize: 15),
            decoration: _decoracionCampo(
              icono: Icons.calendar_today_outlined,
            ),
          ),
        ),
      ],
    );
  }

  Widget _bloqueDescripcion() {
    final esEgreso = _tipoSeleccionado == 'egreso';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _etiqueta(esEgreso ? 'Descripción' : 'Nota (opcional)'),
        _tarjetaCampo(
          hayError: _errorDescripcion != null,
          child: TextField(
            controller: _notaController,
            maxLines: 3,
            minLines: 2,
            onChanged: _onDescripcionCambiada,
            style: GoogleFonts.poppins(color: _tinta, fontSize: 15),
            decoration: InputDecoration(
              filled: false,
              isDense: true,
              hintText: esEgreso
                  ? 'Ej: almuerzo, pasaje, recarga'
                  : 'Ej: quincena, venta, honorarios',
              hintStyle: GoogleFonts.poppins(color: _grisIcono, fontSize: 14),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              errorBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            ),
          ),
        ),
        if (_errorDescripcion != null) _textoError(_errorDescripcion!),
        if (_mostrarNotaSugerenciaAutomatica)
          _textoAyuda(
            'Describe tu gasto y te sugeriremos la categoría automáticamente.',
          ),
      ],
    );
  }

  /// La categoría aparece con una microanimación suave (alto + opacidad).
  Widget _bloqueCategoriaAnimado() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SizeTransition(
          sizeFactor: animation,
          alignment: Alignment.topCenter,
          child: child,
        ),
      ),
      child: _mostrarCampoCategoria
          ? KeyedSubtree(
              key: const ValueKey('categoria-visible'),
              child: _bloqueCategoria(),
            )
          : const SizedBox.shrink(key: ValueKey('categoria-oculta')),
    );
  }

  Widget _bloqueCategoria() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Text('Categoría', style: _estiloEtiqueta),
                if (_mostrarChipSugerida) ...[
                  const SizedBox(width: 8),
                  _chipSugerida(),
                ],
              ],
            ),
          ),
          if (_cargandoCategorias)
            _tarjetaCampo(
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _verde,
                    ),
                  ),
                ),
              ),
            )
          else if (_errorCategorias)
            _tarjetaErrorCategorias()
          else
            _tarjetaCampo(
              hayError: _errorCategoria != null,
              child: _dropdownCategoria(),
            ),
          if (_consultandoSugerencia) _filaSugiriendo(),
          if (_mostrarChipSugerida)
            _textoAyuda('¿No es la correcta? Puedes cambiarla.'),
          if (_sugerenciaEdicion != null) _filaSugerenciaEdicion(),
          if (_sinSugerenciaDisponible)
            _textoAyuda('No pudimos sugerir una categoría; elígela tú.'),
          if (_errorCategoria != null && !_errorCategorias)
            _textoError(_errorCategoria!),
        ],
      ),
    );
  }

  Widget _dropdownCategoria() {
    // Cada opción del desplegable: nombre + ejemplos (texto de la app).
    final opciones = <({String id, String nombre, String? ejemplo, bool crear})>[
      for (final c in _categoriasVisibles)
        (
          id: c['id'].toString(),
          nombre: c['nombre'].toString(),
          ejemplo: ejemplosCategoria[c['nombre'].toString()],
          crear: false,
        ),
      if (_tipoSeleccionado == 'ingreso')
        (
          id: '__crear_nueva__',
          nombre: 'Crear nueva categoría',
          ejemplo: null,
          crear: true,
        ),
    ];

    return DropdownButtonFormField<String>(
      // ignore: deprecated_member_use
      value: _categoriasVisibles.any(
        (c) => c['id'].toString() == _categoriaSeleccionadaId,
      )
          ? _categoriaSeleccionadaId
          : null,
      isExpanded: true,
      itemHeight: 60,
      hint: Text(
        'Elige una categoría',
        style: GoogleFonts.poppins(fontSize: 14, color: _grisIcono),
      ),
      decoration: const InputDecoration(
        filled: false,
        isDense: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        errorBorder: InputBorder.none,
        disabledBorder: InputBorder.none,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _grisIcono),
      borderRadius: BorderRadius.circular(14),
      style: GoogleFonts.poppins(
        color: _tinta,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      selectedItemBuilder: (context) => [
        for (final o in opciones)
          SizedBox(
            height: 22,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                o.crear ? '' : o.nombre,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  color: o.crear ? _verde : _tinta,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
      items: [
        for (final o in opciones)
          DropdownMenuItem<String>(
            value: o.id,
            child: o.crear
                ? Row(
                    children: [
                      const Icon(Icons.add_rounded, color: _verde, size: 18),
                      const SizedBox(width: 6),
                      Text(
                        'Crear nueva categoría',
                        style: GoogleFonts.poppins(
                          color: _verde,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        o.nombre,
                        style: GoogleFonts.poppins(
                          color: _tinta,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (o.ejemplo != null)
                        Text(
                          o.ejemplo!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: _grisTexto,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
          ),
      ],
      onChanged: _onCategoriaCambiada,
    );
  }

  Widget _chipSugerida() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _verde.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _verde.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.auto_awesome, size: 12, color: _verde),
          const SizedBox(width: 4),
          Text(
            'Sugerida',
            style: GoogleFonts.poppins(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _verde,
            ),
          ),
        ],
      ),
    );
  }

  /// Indicador no bloqueante mientras el clasificador responde.
  Widget _filaSugiriendo() {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 6),
      child: Row(
        children: [
          const SizedBox(
            height: 12,
            width: 12,
            child: CircularProgressIndicator(strokeWidth: 1.8, color: _verde),
          ),
          const SizedBox(width: 8),
          Text(
            'Sugiriendo categoría…',
            style: GoogleFonts.poppins(fontSize: 11, color: _grisTexto),
          ),
        ],
      ),
    );
  }

  Widget _filaSugerenciaEdicion() {
    final sugerencia = _sugerenciaEdicion!;
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 6),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _aplicarSugerenciaEdicion(sugerencia.categoriaId!),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.auto_awesome, size: 13, color: _verde),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                'Sugerida: ${sugerencia.categoriaNombre ?? ''} · tocar para usarla',
                style: GoogleFonts.poppins(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _verde,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tarjetaErrorCategorias() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _rojo.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _rojo.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: _rojo),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No se pudieron cargar las categorías, desliza hacia abajo para reintentar',
              style: GoogleFonts.poppins(
                color: _tinta,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _botonGuardar() {
    final habilitado = !_isLoading && !_errorCategorias;
    return SizedBox(
      width: double.infinity,
      height: 54,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: habilitado ? const [_verde, _verdeClaro] : const [
              _grisIcono,
              _grisIcono,
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: habilitado
              ? [
                  BoxShadow(
                    color: _verde.withValues(alpha: 0.32),
                    blurRadius: 14,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: ElevatedButton(
          onPressed: habilitado ? _guardar : null,
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
                  _esModoEdicion ? 'Guardar cambios' : 'Guardar transacción',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _crema,
      body: SafeArea(
        child: RefreshIndicator(
          color: _verde,
          onRefresh: _cargarCategorias,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              children: [
                _encabezado(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 1) Monto
                      _bloqueMonto(),
                      const SizedBox(height: 22),
                      // 2) Tipo
                      _bloqueTipo(),
                      const SizedBox(height: 22),
                      // 3) Método de pago
                      _bloqueMetodoPago(),
                      const SizedBox(height: 22),
                      // 4) Fecha
                      _bloqueFecha(),
                      const SizedBox(height: 22),
                      // 5) Descripción
                      _bloqueDescripcion(),
                      // 6) Categoría (aparece con microanimación)
                      _bloqueCategoriaAnimado(),
                      const SizedBox(height: 34),
                      _botonGuardar(),
                      const SizedBox(height: 16),
                    ],
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

/// Ejemplos de uso de cada categoría de egreso. Es solo texto de la app:
/// NO cambia los nombres de las categorías en la base de datos (el
/// clasificador, el chat y el motor de recomendaciones dependen de ellos).
const Map<String, String> ejemplosCategoria = {
  'Celular e internet': 'plan, recargas, internet de la casa…',
  'Comidas fuera y domicilios':
      'restaurantes, corrientazo, comida rápida, domicilios por app…',
  'Educación': 'matrícula, cursos, libros, fotocopias, útiles…',
  'Entretenimiento': 'cine, salidas, streaming, videojuegos, conciertos…',
  'Hogar': 'aseo, utensilios, muebles, arreglos de la casa…',
  'Licor y cigarrillos': 'cerveza, trago, cigarrillos, vapeador…',
  'Mercado': 'supermercado, tienda de barrio, plaza, carnicería…',
  'Obligaciones y transferencias':
      'cuotas de créditos, tarjeta de crédito, préstamos, plata enviada a familia…',
  'Otros gastos': 'lo que no encaja en ninguna categoría',
  'Ropa': 'ropa, zapatos, accesorios…',
  'Salud': 'medicamentos, citas médicas, odontólogo, exámenes, gafas…',
  'Servicios públicos': 'agua, luz, gas, aseo…',
  'Transporte':
      'bus, taxi, gasolina, parqueadero, mantenimiento de la moto o el carro…',
  'Vivienda': 'arriendo, cuota de vivienda, administración…',
};

/// Campos del formulario "Nueva transacción" en el orden visual en que se
/// validan: Monto → Tipo → Método de pago → Descripción → Categoría.
enum CampoFormulario { monto, tipo, metodoPago, descripcion, categoria }

/// Primer error de validación encontrado, con el campo que lo originó.
class ErrorFormulario {
  final CampoFormulario campo;
  final String mensaje;

  const ErrorFormulario(this.campo, this.mensaje);
}

/// Lógica pura del formulario de registro/edición de transacciones.
/// No depende de Flutter ni de Supabase: concentra las decisiones que se
/// pueden probar de forma aislada (qué se muestra, qué se valida y cuándo
/// la sugerencia del clasificador manda sobre la elección del usuario).
class RegistroTransaccionLogic {
  /// Mínimo de caracteres útiles para una descripción de egreso.
  static const int largoMinimoDescripcion = 2;

  /// Texto sin espacios: mide el contenido real de la descripción.
  static String textoUtil(String texto) => texto.replaceAll(RegExp(r'\s+'), '');

  /// ¿Debe verse el campo Categoría?
  /// - Egreso: solo cuando la descripción ya tiene al menos 2 caracteres
  ///   útiles. Antes de eso el usuario no puede elegir categoría.
  /// - Ingreso (o sin tipo elegido todavía): siempre visible.
  bool mostrarCategoria({required String? tipo, required String descripcion}) {
    if (tipo != 'egreso') return true;
    return textoUtil(descripcion).length >= largoMinimoDescripcion;
  }

  /// Categoría que debe quedar seleccionada tras responder el clasificador.
  /// Devuelve null cuando la selección actual NO debe cambiar: no hubo
  /// sugerencia, quedó por debajo del umbral (`preseleccionar`), la categoría
  /// no existe en la lista, ya estaba seleccionada o el usuario ya eligió
  /// manualmente (su elección nunca se sobrescribe).
  String? categoriaTrasSugerencia({
    required String? categoriaSugeridaId,
    required bool preseleccionar,
    required bool categoriaExiste,
    required bool elegidaManualmente,
    required String? categoriaActualId,
  }) {
    if (categoriaSugeridaId == null) return null;
    if (!preseleccionar) return null;
    if (!categoriaExiste) return null;
    if (elegidaManualmente) return null;
    if (categoriaSugeridaId == categoriaActualId) return null;
    return categoriaSugeridaId;
  }

  /// Primer error del formulario en el orden visual de los campos.
  /// [categoriaVisible] es false cuando el campo Categoría está oculto
  /// (egreso sin descripción): en ese caso no se valida la categoría.
  ErrorFormulario? validar({
    required String montoTexto,
    required String? tipo,
    required String? metodoPago,
    required String descripcion,
    required bool categoriaVisible,
    required String? categoriaId,
  }) {
    final montoDigits = montoTexto.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (montoDigits.isEmpty) {
      return const ErrorFormulario(CampoFormulario.monto, 'Ingresa un monto');
    }
    final monto = double.tryParse(montoDigits);
    if (monto == null || monto <= 0) {
      return const ErrorFormulario(
        CampoFormulario.monto,
        'El monto debe ser mayor a 0',
      );
    }

    if (tipo == null) {
      return const ErrorFormulario(
        CampoFormulario.tipo,
        'Selecciona un tipo',
      );
    }

    if (metodoPago == null) {
      return const ErrorFormulario(
        CampoFormulario.metodoPago,
        'Selecciona un método de pago',
      );
    }

    if (tipo == 'egreso' &&
        textoUtil(descripcion).length < largoMinimoDescripcion) {
      return const ErrorFormulario(
        CampoFormulario.descripcion,
        'Ingresa una descripción de al menos 2 caracteres',
      );
    }

    if (categoriaVisible && categoriaId == null) {
      return const ErrorFormulario(
        CampoFormulario.categoria,
        'Selecciona una categoría',
      );
    }

    return null;
  }
}

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/// Utilidades de formato reutilizables en toda la capa presentation.
///
/// Usamos un solo lugar para centralizar cómo se ven los montos y las fechas,
/// así cambiamos locale/símbolo en un único sitio.
class FormatoUtils {
  /// Formato de moneda: pesos colombianos, sin decimales, con separador
  /// de miles y símbolo `$ `.
  static final NumberFormat moneda = NumberFormat.currency(
    locale: 'es_CO',
    symbol: r'$ ',
    decimalDigits: 0,
  );
}

/// Formateador de entrada que agrega separadores de miles en tiempo real
/// usando el patrón decimal colombiano (`es_CO`).
///
/// Elimina todo lo que no sea dígito, formatea el número resultante y
/// mantiene el cursor al final del texto. Diseñado para campos de monto
/// entero (sin decimales), coherente con `FormatoUtils.moneda`.
class MilesInputFormatter extends TextInputFormatter {
  final NumberFormat _formatter = NumberFormat.decimalPattern('es_CO');

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.isEmpty) return const TextEditingValue();
    final numero = int.parse(digitsOnly);
    final textoFormateado = _formatter.format(numero);
    return TextEditingValue(
      text: textoFormateado,
      selection: TextSelection.collapsed(offset: textoFormateado.length),
    );
  }
}

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Una marca del eje Y: su valor numérico y la etiqueta corta ya formateada.
class MarcaEjeY {
  final double valor;
  final String etiqueta;

  const MarcaEjeY({required this.valor, required this.etiqueta});

  @override
  String toString() => 'MarcaEjeY($valor, "$etiqueta")';
}

/// Todo lo que la tarjeta "Flujo de caja" necesita para pintarse, ya
/// calculado y sin depender del widget ni de fl_chart.
class DatosGraficaFlujo {
  /// Exactamente una etiqueta por mes, en orden cronológico (May, Jun, ...).
  final List<String> etiquetas;

  /// Un valor por mes: el neto o el acumulado, según la vista elegida.
  final List<double> valores;

  /// Color por mes para la vista de barras (verde si >= 0, rojo si < 0).
  final List<Color> colores;

  /// Marcas del eje Y (4-5), siempre incluyendo el cero cuando hay negativos.
  final List<MarcaEjeY> marcasEjeY;

  /// Extremos del eje Y (coinciden con la primera y la última marca).
  final double minY;
  final double maxY;

  /// Separación entre marcas del eje Y: sirve para la cuadrícula horizontal.
  final double intervalo;

  /// Primer mes del rango en nombre largo y minúscula (ej. "mayo").
  final String primerMesLargo;

  /// true si al menos un mes tiene un valor distinto de cero.
  final bool hayDatos;

  const DatosGraficaFlujo({
    required this.etiquetas,
    required this.valores,
    required this.colores,
    required this.marcasEjeY,
    required this.minY,
    required this.maxY,
    required this.intervalo,
    required this.primerMesLargo,
    required this.hayDatos,
  });
}

/// Lógica **pura** de presentación para la gráfica "Flujo de caja" del Inicio.
///
/// No calcula ingresos, egresos ni acumulados: solo transforma la lista que ya
/// devuelve `TransaccionesLogic.obtenerFlujoCajaMensual` en etiquetas, valores,
/// colores, rango y marcas de eje listos para dibujar. Al ser pura se puede
/// probar sin Flutter, sin Supabase y sin la librería de gráficas.
class FlujoCajaViewLogic {
  FlujoCajaViewLogic._();

  /// Verde de la paleta: meses con saldo positivo o en cero.
  static const Color colorPositivo = Color(0xFF58774B);

  /// Rojo suave (color de error de la app): meses con saldo negativo.
  static const Color colorNegativo = Color(0xFFC0392B);

  /// Cantidad de marcas deseadas en el eje Y.
  static const int minMarcasEjeY = 4;
  static const int maxMarcasEjeY = 5;

  /// Formato para la parte decimal corta (ej. 1,5). El separador decimal es la
  /// coma porque usamos el patrón colombiano.
  static final NumberFormat _cortoFmt = NumberFormat('#,##0.#', 'es_CO');

  /// Abreviatura del mes con la primera letra en mayúscula (May, Jun, Sept).
  static String mesAbrev(DateTime mes) {
    final s = DateFormat('MMM', 'es').format(mes);
    return s[0].toUpperCase() + s.substring(1).replaceAll('.', '');
  }

  /// Nombre largo del mes en minúscula (mayo, septiembre).
  static String mesLargo(DateTime mes) =>
      DateFormat('MMMM', 'es').format(mes).toLowerCase();

  /// Formato corto de pesos colombianos para el eje Y:
  /// `$0`, `$250 mil`, `$500 mil`, `$1 M`, `-$200 mil`.
  ///
  /// Se mantiene corto a propósito para que las etiquetas no se corten en
  /// pantallas angostas (celulares de 360 px).
  static String formatoCortoPesos(double valor) {
    final seguro = valor.isFinite ? valor : 0.0;
    final abs = seguro.abs().roundToDouble();
    final signo = seguro < 0 ? '-' : '';

    if (abs < 1000) return '$signo\$${abs.toInt()}';
    if (abs < 1000000) {
      final miles = abs / 1000;
      if (miles.round() < 1000) return '$signo\$${_corto(miles)} mil';
    }
    return '$signo\$${_corto(abs / 1000000)} M';
  }

  /// Color de la barra según el signo del mes: verde si sobró, rojo si faltó.
  static Color colorPorSigno(double valor) =>
      valor < 0 ? colorNegativo : colorPositivo;

  /// Calcula 4-5 marcas para el eje Y a partir de los valores dibujados.
  ///
  /// Reglas:
  /// - Si todos los valores son positivos, el eje empieza en 0.
  /// - Si hay negativos, el eje se extiende por debajo y **siempre** incluye
  ///   el cero (para que la línea del cero quede visible).
  /// - Sin datos, devuelve una única marca en cero.
  static List<MarcaEjeY> calcularMarcasEjeY(List<double> valores) {
    final finitos = valores.where((v) => v.isFinite).toList();

    double minValor = 0;
    double maxValor = 0;
    if (finitos.isNotEmpty) {
      minValor = finitos.reduce(min);
      maxValor = finitos.reduce(max);
    }

    final minEje = minValor < 0 ? minValor : 0.0;
    final maxEje = maxValor > 0 ? maxValor : 0.0;

    // Todo en cero: el widget muestra el estado vacío, no hace falta un eje.
    if (minEje == 0 && maxEje == 0) {
      return const [MarcaEjeY(valor: 0, etiqueta: r'$0')];
    }

    final rango = maxEje - minEje;

    var paso = _pasoBonito(rango, maxMarcasEjeY - 1);
    var minMarca = (minEje / paso).floorToDouble() * paso;
    var maxMarca = (maxEje / paso).ceilToDouble() * paso;

    // Ajusta el paso para caer dentro de 4-5 marcas cuando sea posible.
    for (final divisiones in const [4, 3, 5, 2, 6]) {
      final candidato = _pasoBonito(rango, divisiones);
      final minCandidato = (minEje / candidato).floorToDouble() * candidato;
      final maxCandidato = (maxEje / candidato).ceilToDouble() * candidato;
      final cantidad = ((maxCandidato - minCandidato) / candidato).round() + 1;
      if (cantidad >= minMarcasEjeY && cantidad <= maxMarcasEjeY) {
        paso = candidato;
        minMarca = minCandidato;
        maxMarca = maxCandidato;
        break;
      }
    }

    final total = ((maxMarca - minMarca) / paso).round() + 1;
    final marcas = <MarcaEjeY>[];
    for (var i = 0; i < total; i++) {
      var valor = minMarca + paso * i;
      // Evita "-0.0" y el ruido de punto flotante alrededor del cero.
      if (valor.abs() < paso / 1000) valor = 0;
      marcas.add(MarcaEjeY(valor: valor, etiqueta: formatoCortoPesos(valor)));
    }
    return marcas;
  }

  /// Prepara todos los datos visuales de la tarjeta.
  ///
  /// [flujo] es la salida de `TransaccionesLogic.obtenerFlujoCajaMensual`
  /// (cada elemento trae `mes`, `neto` y `acumulado`). [acumulado] elige cuál
  /// de los dos valores se dibuja.
  static DatosGraficaFlujo preparar({
    required List<Map<String, dynamic>> flujo,
    required bool acumulado,
  }) {
    final etiquetas = <String>[];
    final valores = <double>[];
    final colores = <Color>[];

    for (final mes in flujo) {
      final fecha = mes['mes'] as DateTime;
      etiquetas.add(mesAbrev(fecha));
      final valor =
          ((acumulado ? mes['acumulado'] : mes['neto']) as num).toDouble();
      valores.add(valor);
      colores.add(colorPorSigno(valor));
    }

    final marcas = calcularMarcasEjeY(valores);
    final primero = flujo.isEmpty ? null : flujo.first['mes'] as DateTime;

    return DatosGraficaFlujo(
      etiquetas: etiquetas,
      valores: valores,
      colores: colores,
      marcasEjeY: marcas,
      minY: marcas.first.valor,
      maxY: marcas.last.valor,
      intervalo: marcas.length > 1 ? marcas[1].valor - marcas[0].valor : 1,
      primerMesLargo: primero == null ? '' : mesLargo(primero),
      hayDatos: valores.any((v) => v != 0),
    );
  }

  /// Redondea un número a un paso "bonito" (1, 2, 2.5, 5 o 10 por potencia de
  /// diez) para que las marcas del eje queden en cifras legibles.
  static double _pasoBonito(double rango, int divisiones) {
    if (rango <= 0 || divisiones <= 0) return 1;
    final crudo = rango / divisiones;
    final magnitud = pow(10, (log(crudo) / ln10).floor()).toDouble();
    final normalizado = crudo / magnitud;

    double factor;
    if (normalizado <= 1) {
      factor = 1;
    } else if (normalizado <= 2) {
      factor = 2;
    } else if (normalizado <= 2.5) {
      factor = 2.5;
    } else if (normalizado <= 5) {
      factor = 5;
    } else {
      factor = 10;
    }

    final resultado = factor * magnitud;
    // Los montos son pesos enteros: nunca hace falta un paso menor a 1.
    return resultado < 1 ? 1 : resultado;
  }

  /// Texto corto de una cifra sin decimales relevantes (250, 1,5, 12,3).
  static String _corto(double numero) {
    if ((numero - numero.roundToDouble()).abs() < 0.05) {
      return numero.round().toString();
    }
    return _cortoFmt.format(numero);
  }
}

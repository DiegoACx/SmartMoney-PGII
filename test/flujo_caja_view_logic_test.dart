import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:smartmoney_pgii/logic/flujo_caja_view_logic.dart';

/// Construye un elemento con la misma forma que devuelve
/// `TransaccionesLogic.obtenerFlujoCajaMensual`.
Map<String, dynamic> _mes(int anio, int mes, double neto, double acumulado) => {
      'mes': DateTime(anio, mes, 1),
      'neto': neto,
      'acumulado': acumulado,
    };

void main() {
  setUpAll(() async {
    // Los datos de locale no se cargan solos en las pruebas unitarias.
    await initializeDateFormatting('es');
  });

  group('etiquetas del eje X', () {
    test('hay exactamente una etiqueta por mes, en orden y sin repetir', () {
      final flujo = [
        _mes(2026, 5, 120000, 120000),
        _mes(2026, 6, -40000, 80000),
        _mes(2026, 7, 90000, 170000),
        _mes(2026, 8, 0, 170000),
        _mes(2026, 9, -80917, 89083),
        _mes(2026, 10, 250000, 339083),
      ];

      final datos = FlujoCajaViewLogic.preparar(
        flujo: flujo,
        acumulado: false,
      );

      expect(datos.etiquetas.length, flujo.length);
      expect(datos.etiquetas, ['May', 'Jun', 'Jul', 'Ago', 'Sept', 'Oct']);
      expect(datos.etiquetas.toSet().length, flujo.length);
    });

    test('los meses sin movimientos se conservan con valor 0', () {
      final flujo = [
        _mes(2026, 5, 0, 0),
        _mes(2026, 6, 150000, 150000),
      ];

      final datos = FlujoCajaViewLogic.preparar(
        flujo: flujo,
        acumulado: false,
      );

      expect(datos.etiquetas, ['May', 'Jun']);
      expect(datos.valores, [0.0, 150000.0]);
    });

    test('el primer mes se expone en nombre largo para el subtítulo', () {
      final datos = FlujoCajaViewLogic.preparar(
        flujo: [_mes(2026, 9, -80917, -80917)],
        acumulado: false,
      );

      expect(datos.primerMesLargo, 'septiembre');
    });
  });

  group('marcas del eje Y', () {
    test('incluyen el cero cuando hay valores negativos', () {
      final datos = FlujoCajaViewLogic.preparar(
        flujo: [
          _mes(2026, 5, 200000, 200000),
          _mes(2026, 6, -80917, 119083),
          _mes(2026, 7, 150000, 269083),
          _mes(2026, 8, -50000, 219083),
          _mes(2026, 9, 300000, 519083),
          _mes(2026, 10, 0, 519083),
        ],
        acumulado: false,
      );

      final marcas = datos.marcasEjeY;
      expect(marcas.any((m) => m.valor == 0), isTrue);
      expect(marcas.first.valor, lessThanOrEqualTo(-80917));
      expect(marcas.last.valor, greaterThanOrEqualTo(300000));
      expect(marcas.length, inInclusiveRange(4, 5));
      expect(datos.minY, marcas.first.valor);
      expect(datos.maxY, marcas.last.valor);
      expect(datos.intervalo, greaterThan(0));
    });

    test('el eje empieza en cero cuando todos los valores son positivos', () {
      final datos = FlujoCajaViewLogic.preparar(
        flujo: [
          _mes(2026, 9, 50000, 50000),
          _mes(2026, 10, 70000, 120000),
        ],
        acumulado: true,
      );

      expect(datos.minY, 0);
      expect(datos.marcasEjeY.first.valor, 0);
      expect(datos.marcasEjeY.first.etiqueta, r'$0');
      expect(datos.marcasEjeY.last.valor, greaterThanOrEqualTo(120000));
    });

    test('el acumulado negativo también arrastra el eje por debajo de cero',
        () {
      final datos = FlujoCajaViewLogic.preparar(
        flujo: [
          _mes(2026, 9, -80917, -80917),
          _mes(2026, 10, -40000, -120917),
        ],
        acumulado: true,
      );

      expect(datos.valores, [-80917.0, -120917.0]);
      expect(datos.marcasEjeY.any((m) => m.valor == 0), isTrue);
      expect(datos.minY, lessThanOrEqualTo(-120917));
      expect(datos.marcasEjeY.length, inInclusiveRange(4, 5));
    });

    test('sin movimientos devuelve una sola marca en cero', () {
      final datos = FlujoCajaViewLogic.preparar(
        flujo: [_mes(2026, 9, 0, 0), _mes(2026, 10, 0, 0)],
        acumulado: false,
      );

      expect(datos.hayDatos, isFalse);
      expect(datos.marcasEjeY.length, 1);
      expect(datos.marcasEjeY.single.valor, 0);
      expect(datos.marcasEjeY.single.etiqueta, r'$0');
    });

    test('sin transacciones no falla y no marca hayDatos', () {
      final datos = FlujoCajaViewLogic.preparar(
        flujo: const [],
        acumulado: false,
      );

      expect(datos.etiquetas, isEmpty);
      expect(datos.valores, isEmpty);
      expect(datos.hayDatos, isFalse);
      expect(datos.primerMesLargo, '');
      expect(datos.minY, 0);
    });
  });

  group('color por signo', () {
    test('verde para cero y positivos, rojo para negativos', () {
      expect(
        FlujoCajaViewLogic.colorPorSigno(150000),
        FlujoCajaViewLogic.colorPositivo,
      );
      expect(
        FlujoCajaViewLogic.colorPorSigno(0),
        FlujoCajaViewLogic.colorPositivo,
      );
      expect(
        FlujoCajaViewLogic.colorPorSigno(-1),
        FlujoCajaViewLogic.colorNegativo,
      );
    });

    test('preparar asigna un color por mes según su signo', () {
      final datos = FlujoCajaViewLogic.preparar(
        flujo: [
          _mes(2026, 9, -80917, -80917),
          _mes(2026, 10, 150000, 69083),
        ],
        acumulado: false,
      );

      expect(datos.colores, [
        FlujoCajaViewLogic.colorNegativo,
        FlujoCajaViewLogic.colorPositivo,
      ]);
    });
  });

  group('formato corto de pesos', () {
    test('usa los ejemplos pedidos', () {
      expect(FlujoCajaViewLogic.formatoCortoPesos(0), r'$0');
      expect(FlujoCajaViewLogic.formatoCortoPesos(250000), r'$250 mil');
      expect(FlujoCajaViewLogic.formatoCortoPesos(500000), r'$500 mil');
      expect(FlujoCajaViewLogic.formatoCortoPesos(1000000), r'$1 M');
      expect(FlujoCajaViewLogic.formatoCortoPesos(-200000), r'-$200 mil');
    });

    test('redondea valores pequeños y negativos no enteros', () {
      expect(FlujoCajaViewLogic.formatoCortoPesos(999), r'$999');
      expect(FlujoCajaViewLogic.formatoCortoPesos(-999), r'-$999');
      expect(FlujoCajaViewLogic.formatoCortoPesos(1250000), r'$1,3 M');
    });

    test('los valores no finitos no rompen el formato', () {
      expect(FlujoCajaViewLogic.formatoCortoPesos(double.nan), r'$0');
      expect(FlujoCajaViewLogic.formatoCortoPesos(double.infinity), r'$0');
    });
  });

  group('elección de la vista', () {
    test('acumulado usa el saldo corrido y por mes usa el neto', () {
      final flujo = [
        _mes(2026, 9, -80917, -80917),
        _mes(2026, 10, 100000, 19083),
      ];

      final porMes = FlujoCajaViewLogic.preparar(
        flujo: flujo,
        acumulado: false,
      );
      final acumulado = FlujoCajaViewLogic.preparar(
        flujo: flujo,
        acumulado: true,
      );

      expect(porMes.valores, [-80917.0, 100000.0]);
      expect(acumulado.valores, [-80917.0, 19083.0]);
    });
  });
}

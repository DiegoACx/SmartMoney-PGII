import 'package:flutter_test/flutter_test.dart';

import 'package:smartmoney_pgii/logic/metas_logic.dart';

void main() {
  final logic = MetasLogic();
  final ahora = DateTime.now();
  final hoy = DateTime(ahora.year, ahora.month, ahora.day);

  group('calcularFechaRecordatorio', () {
    test('usa las 9:00 a. m. del día correcto (límite menos 3 días)', () {
      final limite = hoy.add(const Duration(days: 30));

      final resultado = logic.calcularFechaRecordatorio(limite);

      expect(
        resultado,
        DateTime(limite.year, limite.month, limite.day - 3, 9),
      );
      expect(resultado!.hour, 9);
      expect(resultado.minute, 0);
    });

    test('con menos de 3 días de margen programa para dentro de 1 minuto', () {
      final limite = hoy.add(const Duration(days: 1));
      final antes = DateTime.now();

      final resultado = logic.calcularFechaRecordatorio(limite);

      expect(resultado, isNotNull);
      // Nunca se programa en el pasado.
      expect(resultado!.isAfter(antes), isTrue);
      expect(
        resultado.difference(DateTime.now()).inMinutes,
        lessThanOrEqualTo(1),
      );
    });

    test('el día mismo de la fecha límite tampoco programa en el pasado', () {
      final resultado = logic.calcularFechaRecordatorio(hoy);

      expect(resultado, isNotNull);
      expect(resultado!.isAfter(DateTime.now()), isTrue);
    });

    test('una meta sin fecha límite no tiene recordatorio', () {
      expect(logic.calcularFechaRecordatorio(null), isNull);
    });

    test('una meta con la fecha límite vencida no tiene recordatorio', () {
      final vencida = hoy.subtract(const Duration(days: 10));

      expect(logic.calcularFechaRecordatorio(vencida), isNull);
    });
  });
}

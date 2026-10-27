import 'package:flutter_test/flutter_test.dart';
import 'package:smartmoney_pgii/logic/perfil_logic.dart';

void main() {
  final logic = PerfilLogic();

  group('validarNombre', () {
    test('acepta un nombre válido', () {
      expect(logic.validarNombre('Juan Pérez'), isNull);
    });

    test('rechaza un nombre vacío', () {
      expect(logic.validarNombre(''), isNotNull);
    });

    test('rechaza un nombre con solo espacios', () {
      expect(logic.validarNombre('   '), isNotNull);
    });

    test('rechaza espacios al inicio o al final', () {
      expect(logic.validarNombre(' Juan'), isNotNull);
      expect(logic.validarNombre('Juan '), isNotNull);
    });

    test('rechaza nombres de menos de 2 caracteres', () {
      expect(logic.validarNombre('A'), isNotNull);
    });

    test('rechaza nombres de más de 50 caracteres', () {
      final largo = 'a' * 51;
      expect(logic.validarNombre(largo), isNotNull);
    });

    test('acepta un nombre de exactamente 50 caracteres', () {
      final limite = 'a' * 50;
      expect(logic.validarNombre(limite), isNull);
    });
  });

  group('validarCambioContrasena', () {
    test('acepta un cambio válido', () {
      expect(
        logic.validarCambioContrasena(
          actual: 'vieja123',
          nueva: 'nueva123',
          confirmacion: 'nueva123',
        ),
        isNull,
      );
    });

    test('rechaza contraseña actual vacía', () {
      expect(
        logic.validarCambioContrasena(
          actual: '',
          nueva: 'nueva123',
          confirmacion: 'nueva123',
        ),
        isNotNull,
      );
    });

    test('rechaza nueva contraseña de menos de 8 caracteres', () {
      expect(
        logic.validarCambioContrasena(
          actual: 'vieja123',
          nueva: '1234567',
          confirmacion: '1234567',
        ),
        isNotNull,
      );
    });

    test('rechaza una nueva contraseña igual a la actual', () {
      expect(
        logic.validarCambioContrasena(
          actual: 'igual123',
          nueva: 'igual123',
          confirmacion: 'igual123',
        ),
        isNotNull,
      );
    });

    test('rechaza confirmación que no coincide', () {
      expect(
        logic.validarCambioContrasena(
          actual: 'vieja123',
          nueva: 'nueva123',
          confirmacion: 'otra123',
        ),
        isNotNull,
      );
    });
  });

  group('obtenerIniciales', () {
    test('usa las iniciales de las dos primeras palabras', () {
      expect(logic.obtenerIniciales('Juan Pérez'), 'JP');
    });

    test('usa una sola inicial cuando hay una sola palabra', () {
      expect(logic.obtenerIniciales('juan'), 'J');
    });

    test('ignora espacios sobrantes', () {
      expect(logic.obtenerIniciales('  ana   maría  lópez '), 'AM');
    });

    test('usa la primera letra del correo si no hay nombre', () {
      expect(logic.obtenerIniciales('', correo: 'ana@correo.com'), 'A');
      expect(logic.obtenerIniciales(null, correo: 'ana@correo.com'), 'A');
    });

    test('devuelve cadena vacía si no hay nombre ni correo', () {
      expect(logic.obtenerIniciales(''), '');
      expect(logic.obtenerIniciales(null), '');
    });
  });
}

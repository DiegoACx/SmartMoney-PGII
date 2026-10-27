import 'package:flutter_test/flutter_test.dart';
import 'package:smartmoney_pgii/logic/recorrido_logic.dart';

void main() {
  group('definición de pasos', () {
    test('hay 10 pasos en el orden esperado', () {
      expect(RecorridoLogic.pasos.length, 10);
      expect(
        RecorridoLogic.pasos.map((p) => p.id).toList(),
        [
          'bienvenida',
          'resumen',
          'navbar',
          'ia',
          'educacion',
          'ingresos',
          'metas',
          'perfil',
          'asistente',
          'cierre',
        ],
      );
    });

    test('bienvenida y cierre son pasos centrados (sin resaltado)', () {
      expect(RecorridoLogic.pasos.first.centrado, isTrue);
      expect(RecorridoLogic.pasos.last.centrado, isTrue);
    });

    test('los pasos de pestañas apuntan al destino correcto de la barra', () {
      final porId = {for (final p in RecorridoLogic.pasos) p.id: p};
      expect(porId['ia']!.destinoNav, 1);
      expect(porId['educacion']!.destinoNav, 2);
      expect(porId['ingresos']!.destinoNav, 3);
      expect(porId['metas']!.destinoNav, 4);
      expect(porId['perfil']!.destinoNav, 5);
      for (final p in RecorridoLogic.pasos.where((p) => p.destinoNav != null)) {
        expect(p.centrado, isFalse);
      }
    });

    test('resumen, navbar y fab usan sus claves', () {
      final porId = {for (final p in RecorridoLogic.pasos) p.id: p};
      expect(porId['resumen']!.clave, 'resumen');
      expect(porId['navbar']!.clave, 'navbar');
      expect(porId['asistente']!.clave, 'fab');
    });
  });

  group('navegación entre pasos', () {
    test('iniciar deja el recorrido visible en el primer paso', () {
      final logic = RecorridoLogic();
      expect(logic.visible, isFalse);

      logic.iniciar();
      expect(logic.visible, isTrue);
      expect(logic.pasoActual, 0);
      expect(logic.esPrimerPaso, isTrue);
      expect(logic.esUltimoPaso, isFalse);
      expect(logic.paso.id, 'bienvenida');
    });

    test('siguiente avanza y no se pasa del último', () {
      final logic = RecorridoLogic()..iniciar();
      logic.siguiente();
      expect(logic.pasoActual, 1);
      expect(logic.esPrimerPaso, isFalse);

      for (var i = 0; i < 20; i++) {
        logic.siguiente();
      }
      expect(logic.pasoActual, 9);
      expect(logic.esUltimoPaso, isTrue);
      expect(logic.paso.id, 'cierre');
    });

    test('retroceder no se pasa del primero', () {
      final logic = RecorridoLogic()..iniciar();
      logic.retroceder();
      expect(logic.pasoActual, 0);

      logic.siguiente();
      logic.siguiente();
      expect(logic.pasoActual, 2);
      logic.retroceder();
      expect(logic.pasoActual, 1);
    });

    test('saltar y finalizar ocultan el recorrido', () {
      final logic = RecorridoLogic()..iniciar();
      logic.siguiente();
      logic.saltar();
      expect(logic.visible, isFalse);
      // El paso se conserva para poder reanudarlo si hiciera falta.
      expect(logic.pasoActual, 1);

      logic.iniciar();
      logic.finalizar();
      expect(logic.visible, isFalse);
    });

    test('irA ignora índices fuera de rango', () {
      final logic = RecorridoLogic()..iniciar();
      logic.irA(-1);
      expect(logic.pasoActual, 0);
      logic.irA(99);
      expect(logic.pasoActual, 0);
      logic.irA(5);
      expect(logic.pasoActual, 5);
    });
  });

  group('marcar como visto por usuario', () {
    test('la llave incluye el id del usuario', () {
      expect(RecorridoLogic.claveVisto('abc-123'), 'recorrido_visto_abc-123');
    });

    test('usuarios distintos no comparten la llave', () {
      expect(
        RecorridoLogic.claveVisto('u1'),
        isNot(RecorridoLogic.claveVisto('u2')),
      );
    });
  });
}

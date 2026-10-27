import 'package:flutter_test/flutter_test.dart';
import 'package:smartmoney_pgii/logic/asistente_burbuja_logic.dart';

void main() {
  const d = Duration(seconds: 1);

  group('configuración por defecto', () {
    test('los tiempos base son 3 s, 6 s, 90 s y máximo 3 por sesión', () {
      final logic = AsistenteBurbujaLogic();
      expect(logic.retrasoInicial, const Duration(seconds: 3));
      expect(logic.duracionVisible, const Duration(seconds: 6));
      expect(logic.intervaloEntreApariciones, const Duration(seconds: 90));
      expect(logic.maxAparicionesPorSesion, 3);
    });
  });

  group('mensajes por pestaña', () {
    test('Inicio tiene dos mensajes y rotan', () {
      expect(AsistenteBurbujaLogic.mensajesPara(PestanaAsistente.inicio), [
        '¡Hola! Soy tu asistente. ¿Vemos en qué se te va la plata?',
        '¿Quieres saber cuánto llevas gastado este mes?',
      ]);

      final logic = AsistenteBurbujaLogic();
      expect(
        logic.siguienteMensaje(PestanaAsistente.inicio),
        '¡Hola! Soy tu asistente. ¿Vemos en qué se te va la plata?',
      );
      expect(
        logic.siguienteMensaje(PestanaAsistente.inicio),
        '¿Quieres saber cuánto llevas gastado este mes?',
      );
      // Vuelve a empezar cuando se agota la lista.
      expect(
        logic.siguienteMensaje(PestanaAsistente.inicio),
        '¡Hola! Soy tu asistente. ¿Vemos en qué se te va la plata?',
      );
    });

    test('cada pestaña tiene los textos pedidos', () {
      expect(AsistenteBurbujaLogic.mensajesPara(PestanaAsistente.ingresos), [
        '¿Te ayudo a entender tus gastos?',
        'Pregúntame en qué categoría gastas más.',
      ]);
      expect(AsistenteBurbujaLogic.mensajesPara(PestanaAsistente.metas), [
        '¿Simulamos cuándo llegas a tu meta?',
        'Si ahorras un poco más, ¿cuánto antes llegas? Pregúntame.',
      ]);
      expect(AsistenteBurbujaLogic.mensajesPara(PestanaAsistente.educacion), [
        '¿Te explico algún concepto financiero?',
        '¿Qué es un CDT? ¿Y la tasa de interés? Pregúntame.',
      ]);
      expect(AsistenteBurbujaLogic.mensajesPara(PestanaAsistente.perfil), [
        '¿Tienes dudas sobre cómo usar la app? Te ayudo.',
      ]);
    });

    test('la pestaña de IA no tiene mensajes y nunca muestra globo', () {
      final logic = AsistenteBurbujaLogic();
      expect(AsistenteBurbujaLogic.mensajesPara(PestanaAsistente.ia), isEmpty);
      expect(logic.siguienteMensaje(PestanaAsistente.ia), isNull);
      expect(
        logic.registrarAparicion(PestanaAsistente.ia, Duration.zero),
        isNull,
      );
      expect(logic.apariciones, 0);
    });
  });

  group('programación del globo', () {
    test('la primera aparición es posible de inmediato', () {
      final logic = AsistenteBurbujaLogic();
      expect(logic.puedeMostrar(Duration.zero), isTrue);
      expect(
        logic.registrarAparicion(PestanaAsistente.inicio, Duration.zero),
        isNotNull,
      );
      expect(logic.apariciones, 1);
    });

    test('respeta el intervalo mínimo de 90 s entre apariciones', () {
      final logic = AsistenteBurbujaLogic();
      logic.registrarAparicion(PestanaAsistente.inicio, Duration.zero);

      expect(logic.puedeMostrar(const Duration(seconds: 89)), isFalse);
      expect(
        logic.registrarAparicion(
          PestanaAsistente.inicio,
          const Duration(seconds: 89),
        ),
        isNull,
      );
      expect(logic.apariciones, 1);

      // Justo a los 90 s ya se permite.
      expect(logic.puedeMostrar(const Duration(seconds: 90)), isTrue);
      expect(
        logic.registrarAparicion(
          PestanaAsistente.inicio,
          const Duration(seconds: 90),
        ),
        isNotNull,
      );
      expect(logic.apariciones, 2);
    });

    test('como máximo 3 apariciones por sesión', () {
      final logic = AsistenteBurbujaLogic();
      expect(logic.registrarAparicion(PestanaAsistente.inicio, d * 0),
          isNotNull);
      expect(logic.registrarAparicion(PestanaAsistente.inicio, d * 90),
          isNotNull);
      expect(logic.registrarAparicion(PestanaAsistente.inicio, d * 180),
          isNotNull);
      expect(logic.apariciones, 3);
      expect(logic.sesionAgotada, isTrue);

      // Ya no se muestra aunque pase mucho tiempo.
      expect(logic.puedeMostrar(d * 1000), isFalse);
      expect(logic.registrarAparicion(PestanaAsistente.inicio, d * 1000),
          isNull);
      expect(logic.apariciones, 3);
    });

    test('tras cerrarlo con la X no vuelve a salir en la sesión', () {
      final logic = AsistenteBurbujaLogic();
      logic.registrarAparicion(PestanaAsistente.inicio, Duration.zero);
      logic.descartar();

      expect(logic.descartado, isTrue);
      expect(logic.puedeMostrar(const Duration(seconds: 300)), isFalse);
      expect(
        logic.registrarAparicion(
          PestanaAsistente.perfil,
          const Duration(seconds: 300),
        ),
        isNull,
      );
    });

    test('no cuenta la aparición si el mensaje no existe', () {
      final logic = AsistenteBurbujaLogic();
      logic.registrarAparicion(PestanaAsistente.ia, Duration.zero);
      expect(logic.apariciones, 0);
    });
  });

  group('reinicio de sesión', () {
    test('devuelve el estado a cero y limpia el descarte', () {
      final logic = AsistenteBurbujaLogic();
      logic.registrarAparicion(PestanaAsistente.inicio, Duration.zero);
      logic.descartar();

      logic.reiniciarSesion();

      expect(logic.apariciones, 0);
      expect(logic.descartado, isFalse);
      expect(logic.sesionAgotada, isFalse);
      expect(logic.puedeMostrar(Duration.zero), isTrue);
      // La rotación vuelve al primer mensaje.
      expect(
        logic.siguienteMensaje(PestanaAsistente.inicio),
        '¡Hola! Soy tu asistente. ¿Vemos en qué se te va la plata?',
      );
    });
  });
}

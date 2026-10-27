import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartmoney_pgii/logic/recorte_recorrido_logic.dart';

void main() {
  // Pantalla típica de referencia (360x800), con una barra inferior de 64 px.
  const pantalla = Size(360, 800);
  const barra = Rect.fromLTRB(0, 736, 360, 800);

  group('areaVisible', () {
    test('sin barra termina en el borde inferior del área segura', () {
      final area = RecorteRecorridoLogic.areaVisible(
        pantalla: pantalla,
        safeArea: const EdgeInsets.only(top: 24, bottom: 16),
      );
      expect(area, const Rect.fromLTRB(0, 24, 360, 784));
    });

    test('con barra termina donde empieza la barra inferior', () {
      final area = RecorteRecorridoLogic.areaVisible(
        pantalla: pantalla,
        barraInferior: barra,
      );
      expect(area.bottom, barra.top);
    });

    test('resaltando la barra llega hasta el borde de la pantalla', () {
      final area = RecorteRecorridoLogic.areaVisible(
        pantalla: pantalla,
        safeArea: const EdgeInsets.only(bottom: 16),
        barraInferior: barra,
        resaltaBarra: true,
      );
      expect(area.bottom, pantalla.height);
    });

    test('el área segura nunca produce un área invertida', () {
      final area = RecorteRecorridoLogic.areaVisible(
        pantalla: pantalla,
        safeArea: const EdgeInsets.only(top: 900, bottom: 900),
      );
      expect(area.top, lessThanOrEqualTo(area.bottom));
    });
  });

  group('recorte', () {
    test('expande el objetivo con su margen cuando hay espacio', () {
      final recorte = RecorteRecorridoLogic.recorte(
        objetivo: const Rect.fromLTRB(40, 100, 320, 200),
        area: const Rect.fromLTRB(0, 0, 360, 720),
      );
      expect(recorte, const Rect.fromLTRB(34, 94, 326, 206));
    });

    test('acota un objetivo más alto que el área visible', () {
      final recorte = RecorteRecorridoLogic.recorte(
        objetivo: const Rect.fromLTRB(24, 100, 336, 900),
        area: const Rect.fromLTRB(0, 0, 360, 720),
      );
      expect(recorte, isNotNull);
      expect(recorte!.top, 94);
      expect(recorte.bottom, 720);
      expect(recorte.left, 18);
      expect(recorte.right, 342);
    });

    test('nunca baja de la barra inferior cuando corresponde', () {
      const area = Rect.fromLTRB(0, 0, 360, 736);
      final recorte = RecorteRecorridoLogic.recorte(
        objetivo: const Rect.fromLTRB(0, 700, 360, 800),
        area: area,
      );
      expect(recorte, isNotNull);
      expect(recorte!.bottom, lessThanOrEqualTo(barra.top));
    });

    test('devuelve null si el objetivo queda fuera del área', () {
      final recorte = RecorteRecorridoLogic.recorte(
        objetivo: const Rect.fromLTRB(0, 760, 360, 800),
        area: const Rect.fromLTRB(0, 0, 360, 736),
      );
      expect(recorte, isNull);
    });

    test('el recorte de una pestaña cabe en la pantalla con margen de 4 px', () {
      const pestana = Rect.fromLTRB(60, 736, 120, 800);
      final area = RecorteRecorridoLogic.areaVisible(
        pantalla: pantalla,
        barraInferior: barra,
        resaltaBarra: true,
      );
      final recorte = RecorteRecorridoLogic.recorte(
        objetivo: pestana,
        area: area,
        margen: RecorteRecorridoLogic.margenRecorteBarra,
      );
      expect(recorte, isNotNull);
      expect(recorte!.left, 56);
      expect(recorte.right, 124);
      expect(recorte.top, 732);
      expect(recorte.bottom, pantalla.height);
      expect(recorte.left, greaterThanOrEqualTo(0));
      expect(recorte.right, lessThanOrEqualTo(pantalla.width));
      expect(recorte.bottom, lessThanOrEqualTo(pantalla.height));
    });
  });

  group('cabeCompleto', () {
    test('detecta si el objetivo entra entero en el área', () {
      const area = Rect.fromLTRB(0, 0, 360, 720);
      expect(
        RecorteRecorridoLogic.cabeCompleto(
          const Rect.fromLTRB(0, 10, 360, 700),
          area,
        ),
        isTrue,
      );
      expect(
        RecorteRecorridoLogic.cabeCompleto(
          const Rect.fromLTRB(0, 10, 360, 760),
          area,
        ),
        isFalse,
      );
    });
  });

  group('tarjeta', () {
    const area = Rect.fromLTRB(0, 0, 360, 800);

    test('prefiere colocarse debajo cuando el recorte está arriba', () {
      expect(
        RecorteRecorridoLogic.tarjetaDebajo(
          recorte: const Rect.fromLTRB(0, 100, 360, 200),
          area: area,
        ),
        isTrue,
      );
    });

    test('se coloca arriba cuando el recorte está al fondo', () {
      expect(
        RecorteRecorridoLogic.tarjetaDebajo(
          recorte: const Rect.fromLTRB(0, 560, 360, 700),
          area: area,
        ),
        isFalse,
      );
    });

    test('debajo deja 12 px de separación respecto al recorte', () {
      final top = RecorteRecorridoLogic.posicionTarjeta(
        recorte: const Rect.fromLTRB(0, 100, 360, 200),
        area: area,
        altoPantalla: 800,
        debajo: true,
      );
      expect(top, 212);
    });

    test('arriba deja 12 px de separación respecto al recorte', () {
      final bottom = RecorteRecorridoLogic.posicionTarjeta(
        recorte: const Rect.fromLTRB(0, 600, 360, 700),
        area: area,
        altoPantalla: 800,
        debajo: false,
      );
      expect(bottom, 212);
      expect(800 - bottom, lessThanOrEqualTo(600 - 12));
    });

    test('nunca se sale por el borde inferior de la pantalla', () {
      final top = RecorteRecorridoLogic.posicionTarjeta(
        recorte: const Rect.fromLTRB(0, 700, 360, 760),
        area: area,
        altoPantalla: 800,
        debajo: true,
      );
      expect(
        top + RecorteRecorridoLogic.altoEstimadoTarjeta,
        lessThanOrEqualTo(800),
      );
    });

    test('nunca se sale por el borde superior de la pantalla', () {
      final bottom = RecorteRecorridoLogic.posicionTarjeta(
        recorte: const Rect.fromLTRB(0, 40, 360, 90),
        area: area,
        altoPantalla: 800,
        debajo: false,
      );
      expect(bottom, greaterThanOrEqualTo(16));
      expect(
        800 - bottom - RecorteRecorridoLogic.altoEstimadoTarjeta,
        greaterThanOrEqualTo(0),
      );
    });
  });
}

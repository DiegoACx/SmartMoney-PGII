import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartmoney_pgii/logic/recorrido_logic.dart';
import 'package:smartmoney_pgii/presentation/widgets/recorrido_guiado.dart';

void main() {
  testWidgets(
    'el paso de bienvenida se monta sin lanzar excepciones',
    (tester) async {
      // Se activa el árbol de semántica porque ahí se valida la combinación
      // `scopesRoute` / `explicitChildNodes`.
      final semantica = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RecorridoGuiado(
              paso: RecorridoLogic.pasos.first,
              pasoActual: 0,
              totalPasos: RecorridoLogic.pasos.length,
              claves: const <String, GlobalKey>{},
              clavesDestinos: const <GlobalKey>[],
              onAnterior: () {},
              onSiguiente: () {},
              onSaltar: () {},
              onFinalizar: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('¡Bienvenido a SmartMoney!'), findsOneWidget);
      expect(find.text('Siguiente'), findsOneWidget);

      semantica.dispose();
    },
  );
}

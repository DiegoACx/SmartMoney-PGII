import 'package:flutter_test/flutter_test.dart';

import 'package:smartmoney_pgii/logic/registro_transaccion_logic.dart';

void main() {
  final logic = RegistroTransaccionLogic();

  group('ejemplosCategoria', () {
    test('cubre las 14 categorías de egreso con su texto de ejemplo', () {
      expect(ejemplosCategoria.length, 14);
      expect(
        ejemplosCategoria['Celular e internet'],
        'plan, recargas, internet de la casa…',
      );
      expect(
        ejemplosCategoria['Comidas fuera y domicilios'],
        'restaurantes, corrientazo, comida rápida, domicilios por app…',
      );
      expect(ejemplosCategoria['Mercado'],
          'supermercado, tienda de barrio, plaza, carnicería…');
      expect(ejemplosCategoria['Otros gastos'],
          'lo que no encaja en ninguna categoría');
      expect(ejemplosCategoria['Vivienda'],
          'arriendo, cuota de vivienda, administración…');
    });
  });

  group('textoUtil', () {
    test('ignora espacios, saltos de línea y tabulaciones', () {
      expect(RegistroTransaccionLogic.textoUtil('  a b\n\tc '), 'abc');
      expect(RegistroTransaccionLogic.textoUtil('      '), '');
    });
  });

  group('mostrarCategoria', () {
    test('egreso con descripción vacía u holgada oculta la categoría', () {
      expect(
        logic.mostrarCategoria(tipo: 'egreso', descripcion: ''),
        isFalse,
      );
      expect(
        logic.mostrarCategoria(tipo: 'egreso', descripcion: '   '),
        isFalse,
      );
      expect(
        logic.mostrarCategoria(tipo: 'egreso', descripcion: 'a'),
        isFalse,
      );
    });

    test('egreso con 2 caracteres útiles muestra la categoría', () {
      expect(
        logic.mostrarCategoria(tipo: 'egreso', descripcion: 'ab'),
        isTrue,
      );
      expect(
        logic.mostrarCategoria(tipo: 'egreso', descripcion: ' a b '),
        isTrue,
      );
    });

    test('ingreso o sin tipo elegido siempre muestra la categoría', () {
      expect(
        logic.mostrarCategoria(tipo: 'ingreso', descripcion: ''),
        isTrue,
      );
      expect(
        logic.mostrarCategoria(tipo: null, descripcion: ''),
        isTrue,
      );
    });
  });

  group('validar (orden Monto → Tipo → Método → Descripción → Categoría)', () {
    ErrorFormulario? validar({
      String montoTexto = '50000',
      String? tipo = 'ingreso',
      String? metodoPago = 'efectivo',
      String descripcion = 'venta',
      bool categoriaVisible = true,
      String? categoriaId = 'cat-1',
    }) {
      return logic.validar(
        montoTexto: montoTexto,
        tipo: tipo,
        metodoPago: metodoPago,
        descripcion: descripcion,
        categoriaVisible: categoriaVisible,
        categoriaId: categoriaId,
      );
    }

    test('sin monto: devuelve el error de Monto primero', () {
      final error = validar(
        montoTexto: '',
        tipo: null,
        metodoPago: null,
        categoriaId: null,
      );
      expect(error?.campo, CampoFormulario.monto);
      expect(error?.mensaje, 'Ingresa un monto');
    });

    test('monto en 0 o inválido: error de Monto', () {
      expect(validar(montoTexto: '0')?.campo, CampoFormulario.monto);
      expect(
        validar(montoTexto: '0')?.mensaje,
        'El monto debe ser mayor a 0',
      );
    });

    test('con monto válido, el siguiente error es Tipo', () {
      final error = validar(tipo: null, metodoPago: null, categoriaId: null);
      expect(error?.campo, CampoFormulario.tipo);
      expect(error?.mensaje, 'Selecciona un tipo');
    });

    test('con monto y tipo, el siguiente error es Método de pago', () {
      final error = validar(metodoPago: null, categoriaId: null);
      expect(error?.campo, CampoFormulario.metodoPago);
      expect(error?.mensaje, 'Selecciona un método de pago');
    });

    test('egreso con descripción corta: error de Descripción antes de Categoría',
        () {
      final error = validar(
        tipo: 'egreso',
        descripcion: 'a',
        categoriaVisible: false,
        categoriaId: null,
      );
      expect(error?.campo, CampoFormulario.descripcion);
      expect(
        error?.mensaje,
        'Ingresa una descripción de al menos 2 caracteres',
      );
    });

    test('categoría visible sin selección: error de Categoría', () {
      final error = validar(categoriaVisible: true, categoriaId: null);
      expect(error?.campo, CampoFormulario.categoria);
      expect(error?.mensaje, 'Selecciona una categoría');
    });

    test('categoría oculta (egreso sin descripción): no se valida', () {
      // La descripción ya tiene 2 caracteres, pero forzamos el campo oculto.
      final error = validar(
        tipo: 'egreso',
        descripcion: 'ab',
        categoriaVisible: false,
        categoriaId: null,
      );
      expect(error, isNull);
    });

    test('ingreso no exige descripción', () {
      final error = validar(
        tipo: 'ingreso',
        descripcion: '',
        categoriaVisible: true,
        categoriaId: 'cat-1',
      );
      expect(error, isNull);
    });

    test('formulario completo y válido no devuelve error', () {
      expect(validar(), isNull);
    });
  });

  group('categoriaTrasSugerencia', () {
    String? aplicar({
      String? categoriaSugeridaId = 'cat-sug',
      bool preseleccionar = true,
      bool categoriaExiste = true,
      bool elegidaManualmente = false,
      String? categoriaActualId,
    }) {
      return logic.categoriaTrasSugerencia(
        categoriaSugeridaId: categoriaSugeridaId,
        preseleccionar: preseleccionar,
        categoriaExiste: categoriaExiste,
        elegidaManualmente: elegidaManualmente,
        categoriaActualId: categoriaActualId,
      );
    }

    test('aplica la sugerencia cuando el usuario no ha elegido', () {
      expect(aplicar(), 'cat-sug');
    });

    test('NO sobrescribe una elección manual del usuario', () {
      expect(aplicar(elegidaManualmente: true), isNull);
    });

    test('no aplica si el clasificador no preselecciona (baja confianza)', () {
      expect(aplicar(preseleccionar: false), isNull);
    });

    test('no aplica si no hubo sugerencia', () {
      expect(aplicar(categoriaSugeridaId: null), isNull);
    });

    test('no aplica si la categoría sugerida no existe en la lista', () {
      expect(aplicar(categoriaExiste: false), isNull);
    });

    test('no aplica si ya es la categoría seleccionada', () {
      expect(aplicar(categoriaActualId: 'cat-sug'), isNull);
    });
  });
}

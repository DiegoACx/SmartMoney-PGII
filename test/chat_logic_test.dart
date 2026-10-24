import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:smartmoney_pgii/data/chat_repository.dart';
import 'package:smartmoney_pgii/logic/chat_logic.dart';

/// Repositorio falso: nunca inicializa ni toca Supabase.
class _RepoFalso extends ChatRepository {
  _RepoFalso({this.respuesta, this.error});

  final Map<String, dynamic>? respuesta;
  final ErrorChat? error;
  final List<String> enviados = [];

  @override
  Future<Map<String, dynamic>> enviarMensaje(String texto) async {
    enviados.add(texto);
    final fallo = error;
    if (fallo != null) throw fallo;
    return respuesta ?? <String, dynamic>{};
  }

  @override
  Future<List<Map<String, dynamic>>> cargarHistorial({int limite = 50}) async {
    return [];
  }
}

void main() {
  group('ChatLogic.validarTexto', () {
    final logic = ChatLogic(repositorio: _RepoFalso());

    test('rechaza un texto vacío', () {
      expect(logic.validarTexto(''), isNotNull);
      expect(logic.validarTexto('   '), isNotNull);
    });

    test('acepta un texto normal', () {
      expect(logic.validarTexto('¿Cuánto gasté este mes?'), isNull);
    });

    test('acepta exactamente 500 caracteres', () {
      expect(logic.validarTexto('a' * 500), isNull);
    });

    test('rechaza más de 500 caracteres', () {
      expect(logic.validarTexto('a' * 501), isNotNull);
    });
  });

  group('ChatLogic.enviarMensaje', () {
    test('no llama a la red si el texto no es válido', () async {
      final repo = _RepoFalso();
      final logic = ChatLogic(repositorio: repo);

      final resultado = await logic.enviarMensaje('   ');

      expect(resultado.exito, isFalse);
      expect(resultado.error, isNotNull);
      expect(repo.enviados, isEmpty);
    });

    test('no llama a la red si el texto supera los 500 caracteres', () async {
      final repo = _RepoFalso();
      final logic = ChatLogic(repositorio: repo);

      final resultado = await logic.enviarMensaje('a' * 501);

      expect(resultado.exito, isFalse);
      expect(repo.enviados, isEmpty);
    });

    test('recorta el texto antes de enviarlo', () async {
      final repo = _RepoFalso(respuesta: {'respuesta': 'ok'});
      final logic = ChatLogic(repositorio: repo);

      await logic.enviarMensaje('  hola  ');

      expect(repo.enviados, ['hola']);
    });

    test('devuelve la respuesta del asistente cuando todo va bien', () async {
      final repo = _RepoFalso(respuesta: {
        'respuesta': 'Este mes llevas \$250.000 en gastos.',
        'intencion': 'consultar_datos',
        'confianza': 0.91,
        'origen': 'calculo',
      });
      final logic = ChatLogic(repositorio: repo);

      final resultado = await logic.enviarMensaje('¿Cuánto gasté este mes?');

      expect(resultado.exito, isTrue);
      expect(resultado.respuesta, 'Este mes llevas \$250.000 en gastos.');
      expect(resultado.intencion, 'consultar_datos');
      expect(resultado.origen, 'calculo');
      expect(resultado.confianza, 0.91);
      expect(resultado.accion, isNull);
    });

    test('muestra tal cual el mensaje del servidor en un 429', () async {
      const mensajeServidor =
          'Por hoy ya alcanzaste el límite de 40 mensajes. Mañana seguimos '
          'revisando tus finanzas.';
      final repo = _RepoFalso(
        error: const ErrorChat(mensajeServidor, estado: 429),
      );
      final logic = ChatLogic(repositorio: repo);

      final resultado = await logic.enviarMensaje('hola');

      expect(resultado.exito, isFalse);
      expect(resultado.error, mensajeServidor);
    });

    test('nunca propaga un error inesperado del repositorio', () async {
      final logic = ChatLogic(repositorio: _RepoQueRompe());

      final resultado = await logic.enviarMensaje('hola');

      expect(resultado.exito, isFalse);
      expect(resultado.error, isNotNull);
    });
  });

  group('ResultadoChat.accion', () {
    test('arma la acción de abrir una lección', () async {
      final logic = ChatLogic(
        repositorio: _RepoFalso(respuesta: {
          'respuesta': 'Te recomiendo esta lección.',
          'intencion': 'aprender_concepto',
          'confianza': 0.8,
          'origen': 'llm',
          'accion': {'tipo': 'abrir_leccion', 'escalon_id': 'n1-e2'},
        }),
      );

      final resultado = await logic.enviarMensaje('enséñame algo');
      final accion = resultado.accion;

      expect(accion, isNotNull);
      expect(accion!['tipo'], 'abrir_leccion');
      expect(accion['escalon_id'], 'n1-e2');
    });

    test('arma la acción de ir a otra pestaña', () async {
      final logic = ChatLogic(
        repositorio: _RepoFalso(respuesta: {
          'respuesta': 'Vamos a tus metas.',
          'intencion': 'consultar_datos',
          'confianza': 0.7,
          'origen': 'calculo',
          'accion': {'tipo': 'ir_a', 'destino': 'metas'},
        }),
      );

      final resultado = await logic.enviarMensaje('¿cómo voy con mi meta?');
      final accion = resultado.accion;

      expect(accion, isNotNull);
      expect(accion!['tipo'], 'ir_a');
      expect(accion['destino'], 'metas');
    });

    test('devuelve null cuando la respuesta no trae acción', () async {
      final logic = ChatLogic(
        repositorio: _RepoFalso(respuesta: {
          'respuesta': 'Un CDT es…',
          'intencion': 'aprender_concepto',
          'confianza': 0.9,
          'origen': 'llm',
        }),
      );

      final resultado = await logic.enviarMensaje('¿qué es un CDT?');

      expect(resultado.accion, isNull);
    });
  });

  group('mensajeDeErrorChat', () {
    test('lee el mensaje del cuerpo en un 429', () {
      final mensaje = mensajeDeErrorChat(
        const FunctionException(
          status: 429,
          details: {
            'error': 'Por hoy ya alcanzaste el límite de 40 mensajes.',
          },
        ),
      );

      expect(mensaje, 'Por hoy ya alcanzaste el límite de 40 mensajes.');
    });

    test('lee el mensaje del cuerpo en un 400', () {
      final mensaje = mensajeDeErrorChat(
        const FunctionException(
          status: 400,
          details: {
            'error': 'Tu mensaje es muy largo. Resúmelo en 500 caracteres o '
                'menos.',
          },
        ),
      );

      expect(
        mensaje,
        'Tu mensaje es muy largo. Resúmelo en 500 caracteres o menos.',
      );
    });

    test('usa un mensaje de conexión cuando falla el transporte', () {
      final mensaje = mensajeDeErrorChat(
        const FunctionsFetchException(details: 'Failed host lookup'),
      );

      expect(mensaje, contains('conexión'));
    });

    test('usa un mensaje genérico si el cuerpo no trae texto útil', () {
      final mensaje = mensajeDeErrorChat(
        const FunctionException(status: 500, details: null),
      );

      expect(mensaje, contains('500'));
    });
  });
}

/// Repositorio que lanza un error no controlado para comprobar que la lógica
/// absorbe todo y nunca lanza hacia la interfaz.
class _RepoQueRompe extends ChatRepository {
  @override
  Future<Map<String, dynamic>> enviarMensaje(String texto) async {
    throw StateError('fallo inesperado');
  }
}

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Grupo probable devuelto en `top3` por la Edge Function.
class GrupoProbable {
  final int grupoId;
  final double prob;

  const GrupoProbable({required this.grupoId, required this.prob});

  factory GrupoProbable.fromJson(Map<String, dynamic> json) {
    return GrupoProbable(
      grupoId: (json['grupo_id'] as num?)?.toInt() ?? 0,
      prob: (json['prob'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Sugerencia de categoría para la descripción de un egreso.
///
/// La Edge Function `clasificar-movimiento` recibe el JWT del usuario
/// automáticamente mediante `functions.invoke` y responde:
///
/// {
///   "sugerencia": {
///     "grupo_id": int,
///     "grupo_nombre": String,
///     "confianza": num,
///     "categoria_id": String?,
///     "categoria_nombre": String?,
///     "preseleccionar": bool,
///     "version_modelo": String,
///     "top3": [ { "grupo_id": int, "prob": num } ]
///   }
/// }
class SugerenciaCategoria {
  final int grupoId;
  final String grupoNombre;
  final double confianza;
  final String? categoriaId;
  final String? categoriaNombre;
  final bool preseleccionar;
  final String versionModelo;
  final List<GrupoProbable> top3;

  const SugerenciaCategoria({
    required this.grupoId,
    required this.grupoNombre,
    required this.confianza,
    required this.categoriaId,
    required this.categoriaNombre,
    required this.preseleccionar,
    required this.versionModelo,
    required this.top3,
  });

  factory SugerenciaCategoria.fromJson(Map<String, dynamic> json) {
    return SugerenciaCategoria(
      grupoId: (json['grupo_id'] as num?)?.toInt() ?? 0,
      grupoNombre: json['grupo_nombre']?.toString() ?? '',
      confianza: (json['confianza'] as num?)?.toDouble() ?? 0,
      categoriaId: json['categoria_id']?.toString(),
      categoriaNombre: json['categoria_nombre']?.toString(),
      preseleccionar: json['preseleccionar'] == true,
      versionModelo: json['version_modelo']?.toString() ?? '',
      top3: (json['top3'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => GrupoProbable.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }
}

/// Cliente del clasificador de movimientos.
///
/// Es un servicio auxiliar del formulario: nunca lanza hacia la UI ni muestra
/// mensajes. Ante error, timeout o falta de conexión devuelve null en
/// silencio, para que el usuario pueda seguir registrando el movimiento a mano.
class ClasificadorRepository {
  final SupabaseClient _client = Supabase.instance.client;

  /// Tiempo máximo de espera de la Edge Function.
  static const Duration _timeout = Duration(seconds: 3);

  /// Longitud mínima de la descripción para consultar al clasificador.
  static const int _largoMinimo = 2;

  Future<SugerenciaCategoria?> sugerirCategoria(String descripcion) async {
    final texto = descripcion.trim();
    if (texto.length < _largoMinimo) return null;

    try {
      final respuesta = await _client.functions
          .invoke('clasificar-movimiento', body: {'descripcion': texto})
          .timeout(_timeout);

      final cuerpo = _comoMapa(respuesta.data);
      final sugerencia = cuerpo['sugerencia'];
      if (sugerencia is! Map) return null;

      return SugerenciaCategoria.fromJson(
        Map<String, dynamic>.from(sugerencia),
      );
    } catch (e) {
      // Sin conexión, timeout o error del servidor: el formulario sigue igual.
      debugPrint('CLASIFICADOR: sin sugerencia ($e)');
      return null;
    }
  }

  Map<String, dynamic> _comoMapa(dynamic dato) {
    if (dato is Map) return Map<String, dynamic>.from(dato);
    if (dato is String && dato.isNotEmpty) {
      try {
        final decodificado = jsonDecode(dato);
        if (decodificado is Map) return Map<String, dynamic>.from(decodificado);
      } catch (_) {
        return <String, dynamic>{};
      }
    }
    return <String, dynamic>{};
  }
}

import 'package:flutter/painting.dart';

/// Geometría **pura** del recorrido guiado.
///
/// No conoce widgets ni navegación, solo rectángulos: calcula el área visible
/// donde puede dibujarse el recorte (respetando el área segura y la barra
/// inferior), acota el elemento resaltado a esa área y decide dónde colocar la
/// tarjeta del paso. Así el recorte nunca se sale de la pantalla.
class RecorteRecorridoLogic {
  const RecorteRecorridoLogic._();

  /// Margen del recorte alrededor del elemento resaltado.
  static const double margenRecorte = 6;

  /// Margen del recorte para los ítems de la barra inferior.
  static const double margenRecorteBarra = 4;

  /// Separación entre el recorte y la tarjeta del recorrido.
  static const double separacionTarjeta = 12;

  /// Alto aproximado de la tarjeta (solo sirve para elegir arriba o abajo).
  static const double altoEstimadoTarjeta = 216;

  /// Holgura al comparar rectángulos (evita fallos por subpíxeles).
  static const double _holgura = 1;

  /// Área visible donde puede caer el recorte.
  ///
  /// Empieza en el borde superior del área segura y termina en el inferior,
  /// pero se detiene donde empieza la barra de navegación salvo que el propio
  /// paso la resalte ([resaltaBarra]); en ese caso llega hasta el borde de la
  /// pantalla, porque la barra ya vive fuera del área segura.
  static Rect areaVisible({
    required Size pantalla,
    EdgeInsets safeArea = EdgeInsets.zero,
    Rect? barraInferior,
    bool resaltaBarra = false,
  }) {
    final alto = pantalla.height;
    final arriba = safeArea.top.clamp(0.0, alto);
    var abajo = (alto - safeArea.bottom).clamp(0.0, alto);
    if (resaltaBarra) {
      abajo = alto;
    } else if (barraInferior != null) {
      abajo = barraInferior.top.clamp(0.0, abajo);
    }
    if (abajo < arriba) abajo = arriba;
    return Rect.fromLTRB(0, arriba, pantalla.width, abajo);
  }

  /// Recorte del paso actual: [objetivo] con su margen, acotado a [area].
  ///
  /// Nunca devuelve un rectángulo fuera de [area]: si el elemento es más alto
  /// (o más ancho) que el espacio visible, el recorte se queda con la parte
  /// visible. Devuelve `null` si no hay intersección con el área.
  static Rect? recorte({
    required Rect objetivo,
    required Rect area,
    double margen = margenRecorte,
  }) {
    final deseado = objetivo.inflate(margen);
    final izquierda = deseado.left > area.left ? deseado.left : area.left;
    final arriba = deseado.top > area.top ? deseado.top : area.top;
    final derecha = deseado.right < area.right ? deseado.right : area.right;
    final abajo = deseado.bottom < area.bottom ? deseado.bottom : area.bottom;
    if (derecha <= izquierda || abajo <= arriba) return null;
    return Rect.fromLTRB(izquierda, arriba, derecha, abajo);
  }

  /// `true` si [objetivo] se ve completo dentro de [area].
  static bool cabeCompleto(Rect objetivo, Rect area) {
    return objetivo.top >= area.top - _holgura &&
        objetivo.bottom <= area.bottom + _holgura &&
        objetivo.left >= area.left - _holgura &&
        objetivo.right <= area.right + _holgura;
  }

  /// Espacio libre por encima del recorte dentro del área.
  static double espacioArriba(Rect recorte, Rect area) =>
      (recorte.top - area.top).clamp(0.0, double.infinity);

  /// Espacio libre por debajo del recorte dentro del área.
  static double espacioAbajo(Rect recorte, Rect area) =>
      (area.bottom - recorte.bottom).clamp(0.0, double.infinity);

  /// `true` si la tarjeta debe ir **debajo** del recorte.
  ///
  /// Se prefiere el lado donde quepa entera; si no cabe en ninguno, el que
  /// tenga más espacio libre.
  static bool tarjetaDebajo({
    required Rect recorte,
    required Rect area,
    double altoTarjeta = altoEstimadoTarjeta,
    double separacion = separacionTarjeta,
  }) {
    final abajo = espacioAbajo(recorte, area) - separacion;
    final arriba = espacioArriba(recorte, area) - separacion;
    if (abajo >= altoTarjeta) return true;
    if (arriba >= altoTarjeta) return false;
    return abajo >= arriba;
  }

  /// Posición vertical de la tarjeta sin salirse de la pantalla.
  ///
  /// Si la tarjeta va debajo se devuelve su `top`; si va arriba, la distancia
  /// desde el borde inferior (`bottom`), que es lo que usa `Positioned` y no
  /// necesita conocer el alto real de la tarjeta.
  static double posicionTarjeta({
    required Rect recorte,
    required Rect area,
    required double altoPantalla,
    required bool debajo,
    double altoTarjeta = altoEstimadoTarjeta,
    double separacion = separacionTarjeta,
    double margenPantalla = 16,
  }) {
    // La tarjeta nunca puede sobresalir por el borde inferior.
    final tope = altoPantalla - margenPantalla - altoTarjeta;
    if (debajo) {
      final top = recorte.bottom + separacion;
      return top.clamp(area.top, tope > area.top ? tope : area.top);
    }
    final bottom = altoPantalla - recorte.top + separacion;
    return bottom.clamp(
      margenPantalla,
      tope > margenPantalla ? tope : margenPantalla,
    );
  }
}

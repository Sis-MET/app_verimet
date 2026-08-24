/// Area de planta del cliente (almacen, produccion, laboratorio, despacho).
///
/// Es la unidad por la que el jefe de calidad mira el parque: el recuento por
/// estado es lo que decide a donde ir primero.
class Area {
  const Area({
    required this.nombre,
    required this.resumen,
    required this.conformes,
    required this.observados,
    required this.noConformes,
  });

  final String nombre;

  /// Linea de contexto ya redactada ("6 equipos · 1 alerta").
  final String resumen;

  final int conformes;
  final int observados;
  final int noConformes;

  int get total => conformes + observados + noConformes;
}

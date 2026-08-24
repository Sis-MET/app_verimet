/// Espejo en Dart de `packages/shared-contracts/src/test-types.ts`.
///
/// Los nombres coinciden con el contrato de la API a proposito: lo que viaja
/// por el cable y lo que se pinta en pantalla deben poder compararse sin
/// traducir.
library;

/// Las tres pruebas de una verificacion intermedia.
enum TestType {
  eccentricity('eccentricity', 'Excentricidad'),
  repeatability('repeatability', 'Repetibilidad'),
  linearity('linearity', 'Linealidad');

  const TestType(this.wireName, this.label);

  final String wireName;
  final String label;
}

/// Resultado de una prueba frente a la tolerancia definida para el instrumento.
enum TestVerdict {
  pass('pass', 'Conforme'),
  fail('fail', 'No conforme'),
  pending('pending', 'Pendiente');

  const TestVerdict(this.wireName, this.label);

  final String wireName;
  final String label;

  bool get isPass => this == TestVerdict.pass;
  bool get isFail => this == TestVerdict.fail;
}

/// Estado de un registro en la cola de sincronizacion offline-first.
enum SyncStatus {
  pending('pending', 'En cola'),
  inProgress('in_progress', 'Enviando'),
  synced('synced', 'Enviada'),
  failed('failed', 'Fallo el envio');

  const SyncStatus(this.wireName, this.label);

  final String wireName;
  final String label;
}

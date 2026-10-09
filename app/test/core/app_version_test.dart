import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ivmet/core/constants/app_config.dart';

void main() {
  // La versión que se graba en cada verificación y se muestra en Ajustes tiene
  // que ser la que se compila: subir la de pubspec.yaml exige subir esta.
  test('AppConfig.version coincide con pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(AppConfig.version, declared);
  });
}

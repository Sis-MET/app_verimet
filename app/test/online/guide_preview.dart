// Vista local de la guía de inicio con transporte sintético. Nunca compilar
// como aplicación productiva: corre en debug o profile, no en release.
// Ingresar con «operador» / «fixture-password».
//
// `?rol=operador` muestra la del operador; `?rol=metrica`, la del jefe de una
// empresa que gestiona Métrica.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/features/online/mobile_session.dart';

import 'guide_fakes.dart';

void main() {
  if (kReleaseMode) {
    throw StateError('Los fixtures no se ejecutan en una compilación release.');
  }
  final role = Uri.base.queryParameters['rol'];
  final server = GuideServer(
    role: role == 'operador' ? 'cliente_operador' : 'cliente_jefe_calidad',
    selfService: role == null,
    setup: const {
      'plants': 1,
      'areas': 2,
      'patterns': 1,
      'tracedPatterns': 0,
      'equipment': 3,
      'validated': 3,
      'configured': 1,
      'assigned': 0,
      'operators': 0,
      'verifications': 0,
    },
  );
  runApp(
    ProviderScope(
      overrides: [
        mobileApiProvider.overrideWithValue(server.api),
        draftRecoveryProvider.overrideWithValue(server.recovery),
      ],
      child: const Center(child: SizedBox(width: 430, child: IvmetApp())),
    ),
  );
}

// Vista local con transporte sintético. Nunca compilar como aplicación productiva.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ivmet/app/app.dart';
import 'package:ivmet/features/online/mobile_session.dart';
import 'customer_fakes.dart';

void main() {
  if (!kDebugMode) throw StateError('Los fixtures solo se ejecutan en debug.');
  final server = CustomerFixtureServer();
  server.user['role'] = 'cliente_jefe_calidad';
  runApp(
    ProviderScope(
      overrides: [mobileApiProvider.overrideWithValue(server.api)],
      child: const Center(child: SizedBox(width: 430, child: IvmetApp())),
    ),
  );
}

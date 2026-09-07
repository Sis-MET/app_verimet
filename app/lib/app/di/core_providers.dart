import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/storage/token_storage.dart';

/// Inyeccion de dependencias transversales.
///
/// Es la raiz del grafo: providers escritos a mano, no generados. Cada feature
/// declara los suyos en `features/<feature>/presentation/providers/` y toma de
/// aca lo que necesite.
///
/// Aqui vivia tambien el cliente HTTP contra la API antigua de Metrica
/// (`api.metrica.local`, por VPN). La app habla con Supabase desde
/// `features/online/mobile_api.dart`, asi que ese stack se retiro; lo unico
/// transversal que queda es donde se guarda el token de sesion.

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    aOptions: SecureTokenStorage.androidOptions,
    iOptions: SecureTokenStorage.iosOptions,
  );
});

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return SecureTokenStorage(ref.watch(secureStorageProvider));
});

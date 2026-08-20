import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/session_user.dart';

/// Estado de la sesion.
///
/// DEMO: la autenticacion real vive detras de `POST /api/ivmet/v1/auth/login` y de
/// `TokenStorage`. Mientras esa capa no exista, cualquier credencial abre
/// sesion con el usuario de referencia del diseno. El resto de la app ya
/// depende solo de este provider, asi que sustituirlo por el caso de uso real
/// no toca ninguna pantalla.
class AuthNotifier extends Notifier<SessionUser?> {
  @override
  SessionUser? build() => null;

  static const SessionUser _demoUser = SessionUser(
    id: 'usr-001',
    nombre: 'Javier Morales',
    email: 'j.morales@embol.bo',
    role: UserRole.jefeCalidad,
    empresaId: 'emp-001',
    empresaNombre: 'Embol S.A. — Planta Santa Cruz',
  );

  Future<void> signIn({required String email, required String password}) async {
    state = _demoUser;
  }

  void signOut() => state = null;
}

final authProvider = NotifierProvider<AuthNotifier, SessionUser?>(AuthNotifier.new);

/// `true` mientras haya sesion. Lo consume el redirect del router.
final isSignedInProvider = Provider<bool>((ref) => ref.watch(authProvider) != null);

/// Nombre del cliente para los encabezados. Sin sesion devuelve vacio.
final clienteNombreProvider = Provider<String>(
  (ref) => ref.watch(authProvider)?.empresaNombre ?? '',
);

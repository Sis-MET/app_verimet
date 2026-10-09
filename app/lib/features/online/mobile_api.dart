import 'dart:convert';

import 'package:dio/dio.dart';

import '../../core/storage/token_storage.dart';

typedef Json = Map<String, dynamic>;
Json object(Object? value) => Map<String, dynamic>.from(value as Map);
List<Json> objects(Object? value) =>
    (value as List? ?? []).map(object).toList();

class MobileConfiguration {
  const MobileConfiguration(this.url, this.publicKey);
  const MobileConfiguration.environment()
    : url = const String.fromEnvironment('SUPABASE_URL'),
      publicKey = const String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  final String url;
  final String publicKey;

  /// `android/app/build.gradle.kts` replica estas reglas para no compilar un
  /// APK sin configuración: si cambian aquí, cambiarlas también allí.
  String? get error {
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path != '' && uri.path != '/')) {
      return 'Falta configurar una URL HTTPS válida de Supabase.';
    }
    if (publicKey.startsWith('sb_publishable_') && publicKey.length > 20) {
      return null;
    }
    try {
      final claims = object(
        jsonDecode(
          utf8.decode(
            base64Url.decode(base64Url.normalize(publicKey.split('.')[1])),
          ),
        ),
      );
      if (claims['role'] == 'anon') return null;
    } catch (_) {
      /* Nunca se acepta una clave de servidor en el móvil. */
    }
    return 'Configura únicamente una clave pública publishable o anon. No uses service_role ni secret.';
  }
}

class MobileFailure implements Exception {
  const MobileFailure(this.code, {this.status});
  final String code;
  final int? status;
  bool get offline => code == 'NETWORK_UNAVAILABLE';
  bool get unauthorized => status == 401 || code == 'SESSION_CHANGED';

  /// El plan de la empresa no admite la operación: se ofrece uno superior.
  bool get planLimit =>
      code.startsWith('PLAN_LIMIT_') || code.startsWith('PLAN_FEATURE_');
  String get message => switch (code) {
    'INVALID_CREDENTIALS' => 'Usuario o contraseña incorrectos.',
    'NETWORK_UNAVAILABLE' =>
      'Sin conexión. Esto necesita internet; las verificaciones que capturas se guardan en el teléfono y se envían solas.',
    'OFFLINE_NOT_COPIED' =>
      'Sin conexión, y esto no está en la copia del teléfono. Ábrelo cuando tengas señal; después quedará disponible sin conexión.',
    'INVALID_CAPTURE_TIME' =>
      'La fecha y hora del teléfono no son válidas. Corrígelas en los ajustes del teléfono.',
    'ROW_VERSION_CONFLICT' =>
      'El registro cambió en otro dispositivo. Vuelve a abrirlo antes de guardar.',
    'IDEMPOTENCY_CONFLICT' =>
      'La solicitud ya existe con contenido diferente. Vuelve a abrir el registro.',
    'OMISSION_REASON_REQUIRED' => 'Justifica cada prueba omitida.',
    'INVALID_DECIMAL_STRING' =>
      'Usa decimales de hasta 9 cifras, sin separadores de miles.',
    'PLAN_NOT_ASSIGNED' =>
      'El plan ya no está asignado al equipo. Actualiza su ficha.',
    'CERTIFICATE_NOT_ACCESSIBLE' =>
      'Un certificado ya no está disponible para esta planta.',
    'DRAFT_EXPIRED' => 'El borrador venció. Inicia uno nuevo.',
    'INCOMPLETE_TEST' =>
      'Completa las cargas utilizadas y las indicaciones de cada prueba ejecutada.',
    'LOAD_OUT_OF_CAPACITY' =>
      'La carga debe estar entre cero y la capacidad máxima de la balanza.',
    'POSITIVE_LOAD_REQUIRED' =>
      'Utiliza una carga mayor que cero para excentricidad y repetibilidad.',
    'DISTINCT_LOADS_REQUIRED' =>
      'Registra al menos dos cargas diferentes para evaluar la linealidad.',
    'GROUP_LOAD_MISMATCH' =>
      'Cada grupo debe repetir la misma carga utilizada.',
    'INVALID_PLATFORM_POSITIONS' =>
      'Revisa la forma de la plataforma y la cantidad de posiciones.',
    'INVALID_READING_COUNT' || 'INVALID_READING_ORDER' =>
      'Revisa la cantidad y el orden de las mediciones.',
    'INVALID_TEST_SETUP' => 'Revisa la configuración de esta prueba.',
    'SUBSTITUTION_REFERENCE_REQUIRED' =>
      'La sustitución requiere una carga base y una referencia anteriores completas.',
    'INVALID_SUBSTITUTION' => 'Revisa los datos de la carga por sustitución.',
    'SUBSTITUTION_PENDING' =>
      'Completa o descarta la sustitución pendiente antes de finalizar.',
    'CAPTURE_VERSION_MISMATCH' =>
      'Este borrador requiere la versión de la app con la que fue creado. Actualiza la app para recuperarlo.',
    'ALL_TESTS_OMITTED' => 'Debes ejecutar al menos una prueba.',
    'FINALIZATION_CONFLICT' =>
      'La finalización ya fue utilizada con otros datos. Vuelve a abrir el borrador.',
    'INVALID_FINALIZATION' =>
      'No se pudo validar la solicitud de finalización. Vuelve a abrir el borrador.',
    'OFFICIAL_ENGINE_NOT_RELEASED' =>
      'Este plan no utiliza un perfil normativo habilitado. El jefe de calidad debe publicar una nueva versión.',
    'OIML_EQUIPMENT_DATA_REQUIRED' =>
      'Faltan la clase o el intervalo de verificación necesarios para calcular el límite OIML.',
    'DECISION_RULE_INVALID' =>
      'La regla de decisión requiere una incertidumbre válida.',
    'MOBILE_ACCESS_DENIED' =>
      'Tu acceso cambió. Comprueba la licencia y las plantas asignadas.',
    'PASSWORD_CHANGE_FAILED' =>
      'No se pudo cambiar la contraseña. Usa una diferente de al menos 12 caracteres.',
    'PROFILE_UPDATE_FAILED' =>
      'La contraseña cambió, pero falta habilitar el perfil. Contacta con Métrica.',
    'SHARE_PREVIEW_CHANGED' =>
      'El expediente cambió. Revisa una nueva vista previa antes de compartir.',
    'SESSION_CHANGED' => 'La sesión cambió. Ingresa nuevamente.',
    'QUALITY_MANAGER_REQUIRED' =>
      'Esta operación corresponde al jefe de calidad de tu empresa.',
    'OFFICIAL_PROCEDURE_REQUIRED' =>
      'El plan debe usar uno de los perfiles de verificación intermedia controlados por IvMET.',
    'NORMATIVE_PROFILE_REQUIRED' =>
      'Selecciona un perfil de verificación intermedia habilitado.',
    'NORMATIVE_METHOD_REQUIRED' =>
      'La prueba no está disponible en el perfil seleccionado.',
    'NORMATIVE_METHOD_MISMATCH' =>
      'El método del plan no coincide con el perfil controlado. Crea una nueva versión.',
    'NORMATIVE_POINTS_REQUIRED' =>
      'El perfil requiere otra cantidad de puntos. Revisa el plan.',
    'REPEATABILITY_ONE_LOAD_REQUIRED' =>
      'Las repeticiones deben usar la misma carga y el mismo grupo.',
    'ECCENTRICITY_REFERENCE_REQUIRED' =>
      'La prueba de excentricidad necesita una única lectura de referencia.',
    'EQUIPMENT_VALIDATION_REQUIRED' =>
      'Primero revisa y valida la ficha de esta balanza.',
    'NO_EQUIPMENT_CORRECTIONS' =>
      'La ficha no tiene correcciones nuevas para compartir con Métrica.',
    'CATALOG_CHANGED' =>
      'Métrica actualizó el catálogo. Abre nuevamente la ficha para revisar esos cambios.',
    'AREA_ALREADY_EXISTS' => 'Ya existe un área equivalente en esta planta.',
    'AREA_INACTIVE' =>
      'El área ya existe, pero está inactiva. Actívala desde Áreas.',
    'AREA_IN_USE' =>
      'Esta área tiene balanzas asignadas. Reasígnalas antes de desactivarla.',
    'PATTERN_ALL_PLANTS_REQUIRED' =>
      'Necesitas acceso a todas las plantas del patrón para editarlo.',
    'EXACT_DECIMAL_REQUIRED' =>
      'Usa cadenas decimales con punto y hasta 9 decimales.',
    'INVALID_PLAN_TEST' =>
      'Revisa unidad, puntos y frecuencia. El aviso debe ser menor que la frecuencia.',
    'INVALID_CHECK_CONFIGURATION' =>
      'Revisa las pruebas y periodicidades seleccionadas.',
    'DUPLICATE_CHECK_TYPE' =>
      'Cada tipo de verificación solo puede aparecer una vez.',
    'INVALID_CHECK_TOLERANCE' =>
      'Cada verificación necesita un límite mayor que cero.',
    'INVALID_CHECK_LOADS' => 'Revisa las cargas y el número de mediciones.',
    'CHECK_LOAD_OUT_OF_RANGE' => 'Una carga supera la capacidad de la balanza.',
    'EQUIPMENT_RANGES_REQUIRED' =>
      'La balanza no tiene capacidad y división válidas. Solicita revisar el catálogo.',
    'LEGACY_PLAN_MANAGEMENT_DISABLED' =>
      'Configura las verificaciones desde la ficha de cada balanza.',
    'EXPLICIT_CONSENT_REQUIRED' =>
      'Revisa la información y confirma expresamente que deseas compartirla.',
    'EQUIPMENT_CODE_REQUIRED' => 'Escribe el código interno de la balanza.',
    'EQUIPMENT_CODE_EXISTS' =>
      'Ya hay una balanza con ese código interno en esta planta.',
    'EQUIPMENT_SERIAL_EXISTS' =>
      'Ya hay una balanza de esa marca con el mismo número de serie.',
    'INVALID_EQUIPMENT_DATA' =>
      'Revisa los datos de la balanza: tipo, unidad, clase y largo de cada campo.',
    'INVALID_EQUIPMENT_RANGES' =>
      'Revisa los rangos: cada capacidad supera a la anterior, la división es menor que la capacidad y e no es menor que la división.',
    'AREA_REQUIRED' => 'Elige un área o escribe el nombre de una nueva.',
    'INVALID_AREA' => 'Revisa el nombre del área.',
    'PLANT_SCOPE_INVALID' => 'No tienes acceso a esa planta.',
    'EQUIPMENT_NOT_ACCESSIBLE' =>
      'La balanza ya no está disponible para ti. Actualiza el catálogo o consulta al jefe de calidad si te la asignó.',
    'INVALID_CHECK_SCHEDULE' =>
      'Revisa la periodicidad: intervalo, días elegidos y primera fecha.',
    'OPERATOR_NOT_IN_PLANT' =>
      'Ese operador no trabaja en esta planta. Métrica habilita las plantas de cada usuario en RimMET.',
    'INVALID_ASSIGNMENT' => 'Revisa los operadores y balanzas elegidos.',
    'INVALID_AGENDA_RANGE' => 'La agenda muestra hasta dos meses a la vez.',
    'INVALID_AGENDA_FILTER' => 'Revisa los filtros de la agenda.',
    'EQUIPMENT_IN_USE' =>
      'La balanza ya tiene capturas o verificaciones: sus datos técnicos no se pueden cambiar.',
    'EQUIPMENT_HAS_OPEN_DRAFTS' =>
      'Hay capturas sin finalizar de esta balanza. Finalízalas antes de darla de baja.',
    'REGISTERED_EQUIPMENT_REQUIRED' =>
      'Esta acción es solo para balanzas registradas por tu empresa.',
    'REGISTERED_EQUIPMENT_USES_EDIT' =>
      'Tu empresa registró esta balanza: corrígela desde Editar balanza.',
    'REGISTRATION_ALREADY_SHARED' =>
      'Métrica ya recibió estos datos de la balanza.',
    'MESSAGE_REQUIRED' => 'Escribe un mensaje para Métrica.',
    'REASON_REQUIRED' => 'Indica el motivo.',
    'EMAIL_ALREADY_REGISTERED' =>
      'Ese correo ya tiene una cuenta en IvMET. Ingresa con tu correo y contraseña, o recupera la contraseña.',
    'INVALID_EMAIL' => 'Revisa el correo electrónico.',
    'INVALID_SIGNUP' =>
      'Revisa los datos: el nombre de la empresa y el tuyo deben tener al menos 2 caracteres.',
    'TERMS_REQUIRED' => 'Acepta las condiciones de uso para crear la cuenta.',
    'INVALID_CODE' =>
      'El código no es válido o ya venció. Revisa tu correo o pide uno nuevo.',
    'CODE_RATE_LIMITED' =>
      'Ya enviamos un código hace poco. Espera un minuto antes de pedir otro.',
    'EMAIL_UNAVAILABLE' =>
      'No se pudo enviar el correo. Inténtalo de nuevo en unos minutos.',
    'SELF_SERVICE_UNAVAILABLE' =>
      'El registro de empresas está pausado. Inténtalo más tarde.',
    'AUTH_UNAVAILABLE' =>
      'El servicio de acceso no responde. Inténtalo de nuevo en unos minutos.',
    'ACCOUNT_DISABLED' =>
      'La cuenta está deshabilitada. Consulta con el jefe de calidad de tu empresa.',
    'PASSWORD_POLICY_FAILED' => 'Usa una contraseña de al menos 12 caracteres.',
    'PLAN_LIMIT_PLANTS' => 'Tu plan no admite más plantas.',
    'PLAN_LIMIT_EQUIPMENT' => 'Tu plan no admite más balanzas.',
    'PLAN_LIMIT_USERS' => 'Tu plan no tiene más cupos de usuario.',
    'PLAN_LIMIT_VERIFICATIONS' =>
      'Tu plan ya usó las verificaciones de este mes.',
    'PLAN_LIMIT_PATTERNS' => 'Tu plan no admite más pesas patrón activas.',
    'PLAN_FEATURE_CUSTOM_SCHEDULES' =>
      'Tu plan usa las periodicidades predefinidas. La periodicidad a medida está en planes superiores.',
    'SELF_SERVICE_REQUIRED' =>
      'Métrica gestiona las plantas y los usuarios de tu empresa en RimMET.',
    'USERNAME_EXISTS' =>
      'Ese usuario ya existe en IvMET. Prueba con otro, por ejemplo agregando el nombre de tu empresa.',
    'INVALID_USERNAME' =>
      'El usuario lleva de 3 a 50 letras minúsculas, números, punto o guion, sin espacios ni @.',
    'INVALID_MEMBER' => 'Revisa el nombre y el rol del usuario.',
    'SELF_CHANGE_NOT_ALLOWED' =>
      'No puedes quitarte el rol de jefe de calidad, desactivar tu cuenta ni restablecer tu propia contraseña.',
    'USER_NOT_FOUND' => 'El usuario ya no está disponible.',
    'INVALID_PLANT' =>
      'Revisa el nombre, la ciudad y la dirección de la planta.',
    'PLANT_HAS_EQUIPMENT' =>
      'La planta tiene balanzas activas. Dalas de baja antes de desactivarla.',
    'LAST_PLANT' => 'Tu empresa necesita al menos una planta activa.',
    'UPGRADE_REQUEST_OPEN' =>
      'Ya tienes una solicitud abierta. Métrica te contactará.',
    'UPGRADE_REQUEST_NOT_OPEN' => 'La solicitud ya fue atendida o cancelada.',
    'PLAN_NOT_AVAILABLE' =>
      'Ese plan ya no está disponible. Actualiza la pantalla.',
    'CONTACT_REQUIRED' =>
      'Deja un teléfono para que Métrica pueda contactarte.',
    'INVALID_UPGRADE_REQUEST' => 'Revisa los datos de la solicitud.',
    'SUBSCRIPTION_NOT_ACTIVE' =>
      'El plan de tu empresa no está vigente. Revisa Mi plan.',
    'LAST_QUALITY_MANAGER' =>
      'Eres el único jefe de calidad de la empresa. Nombra a otro jefe en Ajustes › Usuarios o elimina la empresa completa.',
    'ACCOUNT_NOT_FOUND' => 'La cuenta ya no existe o ya fue eliminada.',
    _ when status == 401 => 'La sesión venció. Ingresa nuevamente.',
    _ when status == 429 =>
      'Demasiados intentos. Espera antes de volver a intentar.',
    _ => 'No se pudo completar la operación. Actualiza e inténtalo nuevamente.',
  };
  @override
  String toString() => message;
}

/// No registra cuerpos ni tokens. Serializa la rotación y descarta respuestas
/// que pertenecen a una sesión anterior, incluso si llegan después del logout.
class MobileApi {
  MobileApi(this.configuration, this.storage, {Dio? dio})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: configuration.url.replaceFirst(RegExp(r'/$'), ''),
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 20),
            ),
          );
  final MobileConfiguration configuration;
  final TokenStorage storage;
  final Dio _dio;
  void Function(MobileFailure failure)? onFailure;
  String? _access;
  String? _refresh;
  int _epoch = 0;
  Future<void>? _refreshing;
  Future<void> _storageQueue = Future.value();
  bool get hasSession => _refresh != null;
  int get epoch => _epoch;

  Future<void> _persist(Future<void> Function() action) {
    final next = _storageQueue.then((_) => action());
    _storageQueue = next.catchError((Object _) {});
    return next;
  }

  Future<Json> _request(String path, Json data, {String? token}) async {
    try {
      final response = await _dio.post<Object?>(
        path,
        data: data,
        options: Options(
          followRedirects: false,
          validateStatus: (_) => true,
          headers: {
            'apikey': configuration.publicKey,
            'Content-Type': 'application/json',
            if (token != null) 'Authorization': 'Bearer $token',
          },
        ),
      );
      if ((response.statusCode ?? 500) >= 300) {
        final body = response.data is Map
            ? object(response.data)
            : <String, dynamic>{};
        throw MobileFailure(
          (body['message'] ?? body['error'] ?? body['code'] ?? 'REQUEST_FAILED')
              .toString(),
          status: response.statusCode,
        );
      }
      return response.data == null || response.data == ''
          ? {}
          : object(response.data);
    } on DioException {
      throw const MobileFailure('NETWORK_UNAVAILABLE');
    }
  }

  Future<void> restore() async {
    final generation = _epoch;
    final access = await storage.readAccessToken();
    final refresh = await storage.readRefreshToken();
    if (_epoch != generation) return;
    _access = access;
    _refresh = refresh;
  }

  Future<void> login(String username, String password) async {
    await clear();
    final generation = _epoch;
    final data = await _request('/functions/v1/ivmet-login', {
      'username': username.trim(),
      'password': password,
    });
    await _accept(
      data['accessToken'] as String,
      data['refreshToken'] as String,
      generation,
    );
  }

  Future<void> _accept(String access, String refresh, int generation) async {
    if (generation != _epoch) throw const MobileFailure('SESSION_CHANGED');
    await _persist(() async {
      if (generation != _epoch) throw const MobileFailure('SESSION_CHANGED');
      await storage.saveTokens(accessToken: access, refreshToken: refresh);
    });
    if (generation != _epoch) throw const MobileFailure('SESSION_CHANGED');
    _access = access;
    _refresh = refresh;
  }

  Future<void> _rotate(int generation) async {
    if (generation != _epoch || _refresh == null) {
      throw const MobileFailure('SESSION_CHANGED');
    }
    final data = await _request('/auth/v1/token?grant_type=refresh_token', {
      'refresh_token': _refresh,
    });
    await _accept(
      data['access_token'] as String,
      data['refresh_token'] as String,
      generation,
    );
  }

  Future<Json> authorized(String path, Json body) async {
    final generation = _epoch;
    final token = _access;
    if (token == null) throw const MobileFailure('SESSION_CHANGED');
    Json result;
    try {
      result = await _request(path, body, token: token);
    } on MobileFailure catch (error) {
      if (error.status != 401) rethrow;
      if (generation != _epoch) throw const MobileFailure('SESSION_CHANGED');
      if (_access == token) {
        final rotation = _refreshing ??= _rotate(generation);
        try {
          await rotation;
        } on MobileFailure catch (failure) {
          if (!failure.offline && generation == _epoch) await clear();
          rethrow;
        } finally {
          if (identical(_refreshing, rotation)) _refreshing = null;
        }
      }
      if (generation != _epoch) throw const MobileFailure('SESSION_CHANGED');
      result = await _request(path, body, token: _access);
    }
    if (generation != _epoch) throw const MobileFailure('SESSION_CHANGED');
    return result;
  }

  Future<Json> rpc(String name, [Json body = const {}]) async {
    final generation = _epoch;
    try {
      return await authorized('/rest/v1/rpc/$name', body);
    } on MobileFailure catch (failure) {
      if (generation == _epoch || !hasSession) onFailure?.call(failure);
      rethrow;
    }
  }

  Future<Json> read(String section, [Json filters = const {}]) =>
      rpc('ivmet_mobile_read', {'section': section, 'filters': filters});

  /// Alta de una empresa. `start` envia el codigo al correo; `complete` lo
  /// verifica, crea la empresa y abre la sesion como [login].
  Future<void> signupStart(Json data) =>
      _request('/functions/v1/ivmet-signup', {...data, 'action': 'start'});

  Future<void> signupComplete(Json data) =>
      _openWith('/functions/v1/ivmet-signup', {...data, 'action': 'complete'});

  /// Recuperar la contraseña con un codigo al correo. Solo las cuentas cuyo
  /// usuario es su correo; `start` responde igual exista o no.
  Future<void> passwordResetStart(String email) => _request(
    '/functions/v1/ivmet-password-reset',
    {'action': 'start', 'email': email.trim()},
  );

  Future<void> passwordResetComplete(
    String email,
    String code,
    String password,
  ) => _openWith('/functions/v1/ivmet-password-reset', {
    'action': 'complete',
    'email': email.trim(),
    'code': code.trim(),
    'password': password,
  });

  Future<void> _openWith(String path, Json body) async {
    await clear();
    final generation = _epoch;
    final data = await _request(path, body);
    await _accept(
      data['accessToken'] as String,
      data['refreshToken'] as String,
      generation,
    );
  }

  /// Elimina la propia cuenta (`account`) o la empresa autoregistrada
  /// (`company`). Pide la contraseña: es lo que confirma quien la elimina.
  Future<void> deleteAccount({
    required String scope,
    required String username,
    required String password,
  }) => _request('/functions/v1/ivmet-account-delete', {
    'action': 'delete',
    'origin': 'app',
    'scope': scope,
    'username': username,
    'password': password,
  });

  /// Cuentas del equipo de una empresa autoregistrada: `create` o `reset`,
  /// con la contraseña temporal que el jefe de calidad entrega.
  Future<Json> teamAccount(Json body) =>
      authorized('/functions/v1/ivmet-team-account', body);
  Future<void> changePassword(String password) async {
    await authorized('/functions/v1/ivmet-change-password', {
      'password': password,
    });
  }

  Future<void> clear() async {
    _epoch++;
    _access = null;
    _refresh = null;
    _refreshing = null;
    await _persist(storage.clear);
  }

  Future<bool> logout() async {
    final token = _access;
    await clear();
    if (token == null) return true;
    try {
      await _request('/auth/v1/logout?scope=local', {}, token: token);
      return true;
    } catch (_) {
      return false;
    }
  }

  void dispose() => _dio.close(force: true);
}

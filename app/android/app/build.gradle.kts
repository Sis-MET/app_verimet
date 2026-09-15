import groovy.json.JsonSlurper
import java.net.URI
import java.util.Base64
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release. key.properties esta ignorado por git y apunta a un keystore
// guardado fuera del repo: ver docs/app-install-guide.md.
val keystorePropertiesFile: File = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.isFile) keystorePropertiesFile.inputStream().use { load(it) }
    }

android {
    namespace = "bo.metrica.ivmet"
    // flutter_secure_storage 11 exige compilar contra la API 37, y Flutter
    // todavia propone 36 en flutter.compileSdkVersion. compileSdk solo habilita
    // APIs nuevas en tiempo de compilacion: no cambia en que dispositivos se
    // instala (minSdk) ni a que comportamientos se adhiere (targetSdk).
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "bo.metrica.ivmet"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.isFile) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Nunca la clave debug de este equipo: Android no actualiza una app
            // firmada con otra clave sin desinstalarla, y eso borra los
            // borradores guardados en el telefono.
            signingConfig = signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Flutter incrusta la conexion a Supabase al compilar (String.fromEnvironment) y
// se la entrega a Gradle en dart-defines. Un APK sin ella abre con el ingreso
// deshabilitado, asi que no se genera. Replica MobileConfiguration.error de
// lib/features/online/mobile_api.dart: si cambian esas reglas, cambiar estas.
fun supabaseConfigurationError(encodedDefines: String?): String? {
    val defines =
        encodedDefines
            .orEmpty()
            .split(',')
            .mapNotNull { runCatching { String(Base64.getDecoder().decode(it), Charsets.UTF_8) }.getOrNull() }
            .associate { it.substringBefore('=') to it.substringAfter('=', "") }
    val url = runCatching { URI(defines["SUPABASE_URL"].orEmpty()) }.getOrNull()
    if (url == null ||
        url.scheme != "https" ||
        url.host.isNullOrEmpty() ||
        url.userInfo != null ||
        url.query != null ||
        url.fragment != null ||
        url.path.orEmpty() !in setOf("", "/")
    ) {
        return "Falta configurar una URL HTTPS valida de Supabase."
    }
    val key = defines["SUPABASE_PUBLISHABLE_KEY"].orEmpty()
    if (key.startsWith("sb_publishable_") && key.length > 20) return null
    val role =
        runCatching {
            val claims = String(Base64.getUrlDecoder().decode(key.split('.')[1]), Charsets.UTF_8)
            (JsonSlurper().parseText(claims) as Map<*, *>)["role"]
        }.getOrNull()
    if (role == "anon") return null
    return "Configura unicamente una clave publica publishable o anon. No uses service_role ni secret."
}

fun releaseSigningError(): String? {
    if (!keystorePropertiesFile.isFile) return "falta app/android/key.properties."
    val missing =
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            .filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) return "faltan ${missing.joinToString()} en app/android/key.properties."
    val keystore = file(keystoreProperties.getProperty("storeFile"))
    return if (keystore.isFile) null else "no existe el keystore $keystore."
}

val supabaseProblem =
    supabaseConfigurationError(findProperty("dart-defines")?.toString())?.let {
        """
        Supabase: $it
        Flutter incrusta esa configuracion al compilar; sin ella la app abre con el ingreso deshabilitado.
        Compila desde la raiz con pnpm app:run, pnpm app:apk o pnpm app:aab, o pasa a flutter
        --dart-define-from-file=config/supabase.local.json (supabase.prod.json para distribuir).
        """.trimIndent()
    }
val signingProblem =
    releaseSigningError()?.let {
        """
        Firma: $it
        La version release se firma siempre con el keystore de IvMET, nunca con la clave debug de este equipo.
        """.trimIndent()
    }

// Se comprueba al ejecutar y no al configurar: sincronizar el proyecto en el IDE
// no recibe dart-defines ni necesita la firma.
tasks.configureEach {
    val problems =
        when {
            name == "preReleaseBuild" -> listOfNotNull(supabaseProblem, signingProblem)
            name.startsWith("compileFlutterBuild") -> listOfNotNull(supabaseProblem)
            else -> emptyList()
        }
    if (problems.isNotEmpty()) {
        val message = (problems + "Ver docs/app-install-guide.md.").joinToString("\n\n")
        doFirst { throw GradleException(message) }
    }
}

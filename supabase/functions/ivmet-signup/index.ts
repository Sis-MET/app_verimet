import { createClient } from "supabase";
import {
  corsHeaders,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  normalizedEmail,
  otpFailure,
  sessionResponse,
  validCode,
  validPassword,
} from "../_shared/session.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SB_PUBLISHABLE_KEY");

// Versión de los términos que la app muestra al registrarse. Cambiarla aquí
// exige cambiarla en `ivmet_signup_complete` y en la app.
const termsVersion = "ivmet-terms-v1";

// Errores de `ivmet_signup_complete` que la app sabe explicar.
const signupErrors: Record<string, number> = {
  EMAIL_ALREADY_REGISTERED: 409,
  INVALID_SIGNUP: 422,
  TERMS_REQUIRED: 422,
  SELF_SERVICE_UNAVAILABLE: 503,
};

type SignupBody = Record<string, unknown>;

const clean = (value: unknown) =>
  typeof value === "string" ? value.trim().replace(/\s+/g, " ") : "";

/// Datos de la empresa: los mismos límites que valida Supabase al crearla.
function companyData(body: SignupBody) {
  const data = {
    company: clean(body.company),
    name: clean(body.name),
    plantName: clean(body.plantName),
    phone: clean(body.phone),
    city: clean(body.city),
    country: clean(body.country),
  };
  const valid = data.company.length >= 2 && data.company.length <= 100 &&
    data.name.length >= 2 && data.name.length <= 200 &&
    data.plantName.length <= 100 && data.phone.length <= 40 &&
    data.city.length <= 100 && data.country.length <= 100;
  return valid ? data : null;
}

/// Contraseña de relleno para la cuenta Auth mientras no se verifica el
/// correo: nadie la conoce y la reemplaza la que se elige al completar.
function placeholderPassword() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes));
}

// Alta de una empresa desde la app, en dos pasos:
// `start` envía un código al correo y `complete` lo verifica, fija la
// contraseña, crea la empresa y devuelve la sesión como `ivmet-login`.
// Los registros públicos de Auth siguen cerrados: la cuenta la crea el
// servidor y el código la confirma.
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return methodNotAllowed();
  if (!supabaseUrl || !serviceRoleKey || !publishableKey) {
    console.error("IvMET signup is missing Supabase environment variables.");
    return jsonResponse({ error: "AUTH_CONFIGURATION_ERROR" }, 500);
  }

  let body: SignupBody;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }
  if (body?.action !== "start" && body?.action !== "complete") {
    return jsonResponse({ error: "INVALID_REQUEST" }, 400);
  }
  const email = normalizedEmail(body.email);
  if (!email) return jsonResponse({ error: "INVALID_EMAIL" }, 422);
  const data = companyData(body);
  if (!data) return jsonResponse({ error: "INVALID_SIGNUP" }, 422);
  if (body.acceptTerms !== true || body.termsVersion !== termsVersion) {
    return jsonResponse({ error: "TERMS_REQUIRED" }, 422);
  }
  if (body.action === "complete") {
    if (!validCode(body.code)) {
      return jsonResponse({ error: "INVALID_CODE" }, 422);
    }
    if (!validPassword(body.password)) {
      return jsonResponse({ error: "PASSWORD_POLICY_FAILED" }, 422);
    }
  }

  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const admin = createClient(supabaseUrl, serviceRoleKey, options);
  const auth = createClient(supabaseUrl, publishableKey, options);
  const { data: status, error: statusError } = await admin.rpc(
    "ivmet_signup_status",
    { target_email: email },
  );
  if (statusError) {
    console.error("Could not check IvMET signup.", statusError.message);
    return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  }
  // Una cuenta ya creada entra por el login, también si se perdió la
  // respuesta del alta.
  if (status?.registered) {
    return jsonResponse({ error: "EMAIL_ALREADY_REGISTERED" }, 409);
  }

  if (body.action === "start") {
    if (!status?.authUserId) {
      const { error } = await admin.auth.admin.createUser({
        email,
        email_confirm: true,
        password: placeholderPassword(),
        app_metadata: { ivmet_signup: "pending" },
      });
      if (error) {
        // Otro intento simultáneo pudo crearla: basta con que exista.
        const { data: again } = await admin.rpc("ivmet_signup_status", {
          target_email: email,
        });
        if (!again?.authUserId) {
          console.error("Could not create IvMET signup account.", error.message);
          return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
        }
      }
    }
    const { error } = await auth.auth.signInWithOtp({
      email,
      options: { shouldCreateUser: false },
    });
    if (error) return otpFailure(error);
    return jsonResponse({ sent: true });
  }

  const { data: verified, error: verifyError } = await auth.auth.verifyOtp({
    email,
    token: body.code as string,
    type: "email",
  });
  if (verifyError || !verified.session || !verified.user) {
    return jsonResponse({ error: "INVALID_CODE" }, 422);
  }
  const userId = verified.user.id;
  const { error: passwordError } = await admin.auth.admin.updateUserById(
    userId,
    {
      password: body.password as string,
      app_metadata: { ivmet_signup: "completed" },
    },
  );
  if (passwordError) {
    return passwordError.status === 422
      ? jsonResponse({ error: "PASSWORD_POLICY_FAILED" }, 422)
      : jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  }
  const { error: signupError } = await admin.rpc("ivmet_signup_complete", {
    target_user: userId,
    data: { ...data, email, acceptTerms: true, termsVersion },
  });
  if (signupError) {
    const known = signupErrors[signupError.message];
    if (!known) console.error("IvMET signup failed.", signupError.message);
    return jsonResponse(
      { error: known ? signupError.message : "AUTH_UNAVAILABLE" },
      known ?? 503,
    );
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    global: {
      headers: { Authorization: `Bearer ${verified.session.access_token}` },
    },
    ...options,
  });
  return sessionResponse(userClient, verified.session, userId);
});

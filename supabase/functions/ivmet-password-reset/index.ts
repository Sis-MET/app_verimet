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

// Recuperar la contraseña con un código al correo. Solo sirve para las cuentas
// cuyo usuario es su correo (las que crea una empresa al registrarse). Las
// demás tienen un correo interno: las restablece su jefe de calidad o Métrica.
// `start` responde igual exista o no la cuenta.
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return methodNotAllowed();
  if (!supabaseUrl || !serviceRoleKey || !publishableKey) {
    console.error("IvMET reset is missing Supabase environment variables.");
    return jsonResponse({ error: "AUTH_CONFIGURATION_ERROR" }, 500);
  }

  let body: Record<string, unknown>;
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
  const { data: target, error: targetError } = await admin.rpc(
    "ivmet_password_reset_target",
    { target_email: email },
  );
  if (targetError) {
    console.error("Could not resolve IvMET reset.", targetError.message);
    return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  }

  if (body.action === "start") {
    if (target) {
      const { error } = await auth.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: false },
      });
      if (error) return otpFailure(error);
    }
    return jsonResponse({ sent: true });
  }

  if (!target) return jsonResponse({ error: "INVALID_CODE" }, 422);
  const { data: verified, error: verifyError } = await auth.auth.verifyOtp({
    email,
    token: body.code as string,
    type: "email",
  });
  if (
    verifyError || !verified.session || verified.user?.id !== target
  ) {
    return jsonResponse({ error: "INVALID_CODE" }, 422);
  }
  const { error: passwordError } = await admin.auth.admin.updateUserById(
    target,
    { password: body.password as string },
  );
  if (passwordError) {
    return passwordError.status === 422
      ? jsonResponse({ error: "PASSWORD_POLICY_FAILED" }, 422)
      : jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  }
  const { error: profileError } = await admin.rpc(
    "complete_ivmet_password_change",
    { target_user_id: target },
  );
  if (profileError) {
    console.error("Password reset but profile completion failed.", profileError.message);
    return jsonResponse({ error: "PROFILE_UPDATE_FAILED" }, 500);
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    global: {
      headers: { Authorization: `Bearer ${verified.session.access_token}` },
    },
    ...options,
  });
  return sessionResponse(userClient, verified.session, target);
});

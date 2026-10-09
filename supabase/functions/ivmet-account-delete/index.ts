import { createClient } from "supabase";
import {
  corsHeaders,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import {
  normalizedEmail,
  otpFailure,
  validCode,
} from "../_shared/session.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SB_PUBLISHABLE_KEY");

// Errores de `ivmet_account_delete` que la app y la página saben explicar.
const deleteErrors: Record<string, number> = {
  LAST_QUALITY_MANAGER: 409,
  QUALITY_MANAGER_REQUIRED: 403,
  SELF_SERVICE_REQUIRED: 403,
  ACCOUNT_NOT_FOUND: 404,
};

function placeholderPassword() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);
  return btoa(String.fromCharCode(...bytes));
}

// Eliminar la cuenta o la empresa, desde la app o desde la página web que pide
// Google Play. Quien la pide se identifica con su usuario y contraseña o, si su
// usuario es su correo, con un código enviado a ese correo (`code`).
//
// Supabase anonimiza los datos y deja la constancia; esta función bloquea
// después las cuentas Auth y les pone un correo interno, para que el correo
// real quede libre y nadie vuelva a entrar con ellas.
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return methodNotAllowed();
  if (!supabaseUrl || !serviceRoleKey || !publishableKey) {
    console.error("IvMET deletion is missing Supabase environment variables.");
    return jsonResponse({ error: "AUTH_CONFIGURATION_ERROR" }, 500);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }
  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const admin = createClient(supabaseUrl, serviceRoleKey, options);
  const auth = createClient(supabaseUrl, publishableKey, options);

  // Bloquea las cuentas Auth de una constancia y, si todas quedaron
  // bloqueadas, la cierra. Una falla la deja abierta para el siguiente intento.
  const closeAccounts = async (deletionId: string, users: string[]) => {
    let closed = true;
    for (const id of users) {
      const { error } = await admin.auth.admin.updateUserById(id, {
        email: `deleted.${id}@users.ivmet.invalid`,
        email_confirm: true,
        password: placeholderPassword(),
        ban_duration: "876000h",
        user_metadata: {},
        app_metadata: { ivmet_deleted: true },
      });
      if (error) {
        closed = false;
        console.error("Could not close a deleted IvMET account.", error.message);
      }
    }
    if (closed) {
      await admin.rpc("ivmet_account_deletion_done", { deletion_id: deletionId });
    }
  };

  if (body?.action === "code") {
    const email = normalizedEmail(body.email);
    if (!email) return jsonResponse({ error: "INVALID_EMAIL" }, 422);
    const { data: target, error } = await admin.rpc(
      "ivmet_password_reset_target",
      { target_email: email },
    );
    if (error) return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
    if (target) {
      const { error: otpError } = await auth.auth.signInWithOtp({
        email,
        options: { shouldCreateUser: false },
      });
      if (otpError) return otpFailure(otpError);
    }
    // Igual exista o no la cuenta.
    return jsonResponse({ sent: true });
  }

  if (body?.action !== "delete") {
    return jsonResponse({ error: "INVALID_REQUEST" }, 400);
  }
  const scope = body.scope === "company"
    ? "COMPANY"
    : body.scope === "account"
    ? "ACCOUNT"
    : null;
  const origin = body.origin === "web" ? "WEB" : body.origin === "app" ? "APP" : null;
  if (!scope || !origin) return jsonResponse({ error: "INVALID_REQUEST" }, 400);

  // Quién lo pide: con un código a su correo o con usuario y contraseña.
  let userId: string;
  if (body.code !== undefined) {
    const email = normalizedEmail(body.email);
    if (!email || !validCode(body.code)) {
      return jsonResponse({ error: "INVALID_CODE" }, 422);
    }
    const { data: target, error } = await admin.rpc(
      "ivmet_password_reset_target",
      { target_email: email },
    );
    if (error) return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
    if (!target) return jsonResponse({ error: "INVALID_CODE" }, 422);
    const { data: verified, error: verifyError } = await auth.auth.verifyOtp({
      email,
      token: body.code as string,
      type: "email",
    });
    if (verifyError || verified.user?.id !== target) {
      return jsonResponse({ error: "INVALID_CODE" }, 422);
    }
    userId = target as string;
  } else {
    const username = typeof body.username === "string"
      ? body.username.trim().toLowerCase()
      : "";
    const password = typeof body.password === "string" ? body.password : "";
    if (
      !username || !password || username.length > 100 || password.length > 200
    ) {
      return jsonResponse({ error: "INVALID_CREDENTIALS" }, 401);
    }
    const { data: aliases, error } = await admin.rpc(
      "resolve_ivmet_login_alias",
      { target_username: username },
    );
    if (error) return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
    const alias = Array.isArray(aliases) ? aliases[0] : null;
    if (!alias?.auth_email_interno) {
      return jsonResponse({ error: "INVALID_CREDENTIALS" }, 401);
    }
    const { data: signIn, error: signInError } = await auth.auth
      .signInWithPassword({ email: alias.auth_email_interno, password });
    if (signInError || !signIn.user) {
      return jsonResponse({ error: "INVALID_CREDENTIALS" }, 401);
    }
    userId = signIn.user.id;
  }

  const { data: deletion, error: deleteError } = await admin.rpc(
    "ivmet_account_delete",
    { target_user: userId, scope, origin },
  );
  if (deleteError) {
    const status = deleteErrors[deleteError.message];
    if (!status) console.error("IvMET deletion failed.", deleteError.message);
    return jsonResponse(
      { error: status ? deleteError.message : "AUTH_UNAVAILABLE" },
      status ?? 503,
    );
  }

  // Los datos ya no tienen dueño ni acceso. Si Auth falla aquí, la constancia
  // queda abierta y la siguiente eliminación la reintenta: no se le pide nada
  // más a quien eliminó su cuenta.
  await closeAccounts(deletion.deletionId, deletion.users ?? []);
  const { data: pending } = await admin.rpc("ivmet_account_deletions_pending", {
    max_rows: 5,
  });
  for (const earlier of Array.isArray(pending) ? pending : []) {
    if (earlier.id !== deletion.deletionId) {
      await closeAccounts(earlier.id, earlier.usuarios ?? []);
    }
  }
  return jsonResponse({ deleted: true, scope: scope.toLowerCase() });
});

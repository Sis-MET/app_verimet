import { createClient } from "supabase";
import {
  corsHeaders,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SB_PUBLISHABLE_KEY");

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return methodNotAllowed();
  if (!supabaseUrl || !publishableKey || !serviceRoleKey) {
    return jsonResponse({ error: "AUTH_CONFIGURATION_ERROR" }, 500);
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "UNAUTHORIZED" }, 401);
  }

  let password = "";
  try {
    const body = await request.json();
    password = typeof body?.password === "string" ? body.password : "";
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }
  if (password.length < 12 || password.length > 200) {
    return jsonResponse({ error: "PASSWORD_POLICY_FAILED" }, 422);
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(authorization.slice(7));
  if (authError || !authData.user) {
    return jsonResponse({ error: "UNAUTHORIZED" }, 401);
  }

  const { data: ownProfile, error: ownProfileError } = await userClient
    .from("perfiles").select("activo,rol").eq("id", authData.user.id).maybeSingle();
  if (ownProfileError || !ownProfile?.activo ||
      !["cliente_operador", "cliente_jefe_calidad"].includes(ownProfile.rol)) {
    return jsonResponse({ error: "PROFILE_DISABLED" }, 403);
  }

  // El cliente efímero de Edge no tiene una sesión local para updateUser().
  // Auth valida el JWT y aplica su política de contraseñas en este endpoint.
  let passwordResponse: Response;
  try {
    passwordResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      method: "PUT",
      headers: { Authorization: authorization, apikey: publishableKey, "Content-Type": "application/json" },
      body: JSON.stringify({ password }),
      signal: AbortSignal.timeout(15000),
    });
  } catch {
    return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  }
  if (!passwordResponse.ok) {
    return jsonResponse(
      { error: "PASSWORD_CHANGE_FAILED" },
      422,
    );
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: profile, error: profileError } = await admin
    .rpc("complete_ivmet_password_change", {
      target_user_id: authData.user.id,
    });
  if (profileError) {
    console.error(
      "Password changed but profile completion failed.",
      profileError.message,
    );
    return jsonResponse({ error: "PROFILE_UPDATE_FAILED" }, 500);
  }

  return jsonResponse({
    changed: true,
    mustChangePassword: profile.debe_cambiar_password,
  });
});

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

type LoginBody = {
  username?: unknown;
  password?: unknown;
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return methodNotAllowed();
  if (!supabaseUrl || !serviceRoleKey || !publishableKey) {
    console.error(
      "IvMET login is missing required Supabase environment variables.",
    );
    return jsonResponse({ error: "AUTH_CONFIGURATION_ERROR" }, 500);
  }

  let body: LoginBody;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }

  const username = typeof body.username === "string"
    ? body.username.trim().toLowerCase()
    : "";
  const password = typeof body.password === "string" ? body.password : "";
  if (
    !username || !password || username.length > 100 || password.length > 200
  ) {
    return jsonResponse({ error: "INVALID_CREDENTIALS" }, 401);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: aliases, error: aliasError } = await admin.rpc(
    "resolve_ivmet_login_alias",
    { target_username: username },
  );
  if (aliasError) {
    console.error("Could not resolve IvMET login alias.", aliasError.message);
    return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  }
  const alias = Array.isArray(aliases) ? aliases[0] : null;
  if (!alias?.auth_email_interno) {
    return jsonResponse({ error: "INVALID_CREDENTIALS" }, 401);
  }

  const authClient = createClient(supabaseUrl, publishableKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data: signIn, error: signInError } = await authClient.auth
    .signInWithPassword({ email: alias.auth_email_interno, password });
  if (signInError || !signIn.session || !signIn.user) {
    return jsonResponse({ error: "INVALID_CREDENTIALS" }, 401);
  }

  const userClient = createClient(supabaseUrl, publishableKey, {
    global: {
      headers: { Authorization: `Bearer ${signIn.session.access_token}` },
    },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const [
    { data: profile, error: profileError },
    { data: access, error: accessError },
  ] = await Promise.all([
    userClient.from("perfiles")
      .select("id,usuario,nombre,rol,cliente_id,activo,debe_cambiar_password")
      .eq("id", signIn.user.id)
      .single(),
    userClient.rpc("ivmet_access_status"),
  ]);

  if (profileError || !profile?.activo) {
    console.error(
      "Authenticated IvMET account has no active profile.",
      profileError?.message,
    );
    return jsonResponse({ error: "ACCOUNT_DISABLED" }, 403);
  }
  if (accessError) {
    console.error("Could not obtain IvMET access status.", accessError.message);
    return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  }

  return jsonResponse({
    accessToken: signIn.session.access_token,
    refreshToken: signIn.session.refresh_token,
    expiresIn: signIn.session.expires_in,
    tokenType: signIn.session.token_type,
    user: {
      id: profile.id,
      username: profile.usuario,
      name: profile.nombre,
      role: profile.rol,
      clientId: profile.cliente_id,
      mustChangePassword: profile.debe_cambiar_password,
    },
    access,
  });
});

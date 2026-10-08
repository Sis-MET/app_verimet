import { createClient } from "supabase";
import {
  corsHeaders,
  jsonResponse,
  methodNotAllowed,
} from "../_shared/http.ts";
import { validPassword } from "../_shared/session.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL");
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ??
  Deno.env.get("SB_PUBLISHABLE_KEY");

const uuidPattern = /^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$/i;

// Errores de `ivmet_team_account` que la app sabe explicar.
const teamErrors: Record<string, number> = {
  MOBILE_ACCESS_DENIED: 403,
  QUALITY_MANAGER_REQUIRED: 403,
  SELF_SERVICE_REQUIRED: 403,
  IDEMPOTENCY_CONFLICT: 409,
  USERNAME_EXISTS: 409,
  PLAN_LIMIT_USERS: 409,
  INVALID_USERNAME: 422,
  INVALID_MEMBER: 422,
  PLANT_SCOPE_INVALID: 422,
  SELF_CHANGE_NOT_ALLOWED: 422,
  USER_NOT_FOUND: 404,
  SUBSCRIPTION_NOT_ACTIVE: 403,
};

// El jefe de calidad de una empresa autoregistrada crea las cuentas de su
// equipo o les pone una contraseña temporal. Sigue el recorrido de RimMET:
// reservar el UUID, crear la cuenta Auth con correo interno y después el
// perfil. Reintentar con el mismo `requestId` recupera la cuenta reservada.
// La contraseña no se guarda ni se registra.
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return methodNotAllowed();
  if (!supabaseUrl || !serviceRoleKey || !publishableKey) {
    return jsonResponse({ error: "AUTH_CONFIGURATION_ERROR" }, 500);
  }
  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse({ error: "UNAUTHORIZED" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ error: "INVALID_JSON" }, 400);
  }
  const action = body?.action;
  const requestId = body?.requestId;
  if (
    (action !== "create" && action !== "reset") ||
    typeof requestId !== "string" || !uuidPattern.test(requestId)
  ) {
    return jsonResponse({ error: "INVALID_REQUEST" }, 400);
  }
  if (!validPassword(body.password)) {
    return jsonResponse({ error: "PASSWORD_POLICY_FAILED" }, 422);
  }
  const password = body.password;

  const options = { auth: { persistSession: false, autoRefreshToken: false } };
  const userClient = createClient(supabaseUrl, publishableKey, {
    global: { headers: { Authorization: authorization } },
    ...options,
  });
  const { data: authData, error: authError } = await userClient.auth.getUser(
    authorization.slice(7),
  );
  if (authError || !authData.user) {
    return jsonResponse({ error: "UNAUTHORIZED" }, 401);
  }
  const actor = authData.user.id;
  const admin = createClient(supabaseUrl, serviceRoleKey, options);
  const rpc = async (operation: string, payload: Record<string, unknown>) => {
    const { data, error } = await admin.rpc("ivmet_team_account", {
      actor,
      action: operation,
      payload,
      request_id: requestId,
    });
    if (error) {
      const status = teamErrors[error.message];
      if (!status) console.error("IvMET team account failed.", error.message);
      throw jsonResponse(
        { error: status ? error.message : "AUTH_UNAVAILABLE" },
        status ?? 503,
      );
    }
    return data as Record<string, string>;
  };

  try {
    if (action === "reset") {
      const userId = body.userId;
      if (typeof userId !== "string" || !uuidPattern.test(userId)) {
        return jsonResponse({ error: "INVALID_REQUEST" }, 400);
      }
      // Primero se exige el cambio de contraseña y después se cambia en Auth:
      // si Auth falla, el reintento con la misma solicitud es seguro.
      await rpc("reset", { userId });
      const { error } = await admin.auth.admin.updateUserById(userId, {
        password,
      });
      if (error) {
        return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
      }
      return jsonResponse({ id: userId });
    }

    const payload = {
      username: typeof body.username === "string" ? body.username : "",
      name: typeof body.name === "string" ? body.name : "",
      role: body.role,
      plantIds: body.plantIds,
    };
    const reserved = await rpc("reserve", payload);
    const existing = await admin.auth.admin.getUserById(reserved.id);
    if (existing.data?.user) {
      if (
        existing.data.user.email !== reserved.email ||
        existing.data.user.app_metadata?.ivmet_request !== requestId
      ) {
        return jsonResponse({ error: "IDEMPOTENCY_CONFLICT" }, 409);
      }
    } else {
      if (existing.error && existing.error.status !== 404) {
        return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
      }
      const created = await admin.auth.admin.createUser({
        id: reserved.id,
        email: reserved.email,
        password,
        email_confirm: true,
        app_metadata: { ivmet_request: requestId },
      });
      // Si Auth la creó pero la respuesta se perdió, el reintento la encuentra.
      if (created.error) {
        return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
      }
    }
    return jsonResponse(await rpc("create", payload));
  } catch (failure) {
    if (failure instanceof Response) return failure;
    throw failure;
  }
});

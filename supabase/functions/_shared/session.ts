import { jsonResponse } from "./http.ts";

// Lo mismo que devuelve `ivmet-login`, para entrar directamente después de
// verificar un código: crear la empresa o restablecer la contraseña.
type Session = {
  access_token: string;
  refresh_token: string;
  expires_in: number;
  token_type: string;
};

type UserClient = {
  from(table: string): {
    select(columns: string): {
      eq(column: string, value: string): {
        single(): PromiseLike<{ data: Record<string, unknown> | null; error: unknown }>;
      };
    };
  };
  rpc(name: string): PromiseLike<{ data: unknown; error: unknown }>;
};

export async function sessionResponse(
  userClient: UserClient,
  session: Session,
  userId: string,
): Promise<Response> {
  const [
    { data: profile, error: profileError },
    { data: access, error: accessError },
  ] = await Promise.all([
    userClient.from("perfiles")
      .select("id,usuario,nombre,rol,cliente_id,activo,debe_cambiar_password")
      .eq("id", userId)
      .single(),
    userClient.rpc("ivmet_access_status"),
  ]);
  if (profileError || !profile?.activo) {
    return jsonResponse({ error: "ACCOUNT_DISABLED" }, 403);
  }
  if (accessError) return jsonResponse({ error: "AUTH_UNAVAILABLE" }, 503);
  return jsonResponse({
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    expiresIn: session.expires_in,
    tokenType: session.token_type,
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
}

/// Correo que sirve de usuario: el mismo criterio que `private.valid_email`.
export function normalizedEmail(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const email = value.trim().toLowerCase();
  if (
    email.length < 6 || email.length > 100 ||
    !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.endsWith(".invalid")
  ) {
    return null;
  }
  return email;
}

export function validPassword(value: unknown): value is string {
  return typeof value === "string" && value.length >= 12 &&
    value.length <= 200;
}

export function validCode(value: unknown): value is string {
  return typeof value === "string" && /^[0-9]{6,10}$/.test(value);
}

/// Auth limita el envío de correos: dos pedidos seguidos esperan un minuto.
/// Cualquier otro fallo (SMTP, plantilla) queda en el registro de la función,
/// sin el correo de la persona.
export function otpFailure(
  error: { status?: number; code?: string; message?: string },
): Response {
  if (error.status === 429) {
    return jsonResponse({ error: "CODE_RATE_LIMITED" }, 429);
  }
  console.error(
    "Auth could not send the IvMET code.",
    error.status,
    error.code,
    error.message,
  );
  return jsonResponse({ error: "EMAIL_UNAVAILABLE" }, 503);
}

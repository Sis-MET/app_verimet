import type { UserRole } from './authenticated-user';

/** Claims que IvMET emite y espera dentro del access token. */
export interface AccessTokenPayload {
  sub: string;
  email: string;
  role: UserRole;
  empresa_id: string | null;
  iat?: number;
  exp?: number;
}

export interface RefreshTokenPayload {
  sub: string;
  jti: string;
  iat?: number;
  exp?: number;
}

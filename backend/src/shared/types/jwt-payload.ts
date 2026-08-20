import type { UserRole } from './authenticated-user';

/** Claims que IvMET emite y espera dentro del access token. */
export interface AccessTokenPayload {
  sub: string;
  username: string;
  name: string;
  role: UserRole;
  empresa_id: string | null;
  token_version: number;
  type: 'access';
  iat?: number;
  exp?: number;
}

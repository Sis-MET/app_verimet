import type { UserRole } from '@shared/types';

export interface StoredUser {
  id: string;
  username: string;
  normalizedUsername: string;
  name: string;
  email: string | null;
  passwordHash: string;
  role: UserRole;
  empresaId: string | null;
  status: 'ACTIVO' | 'INACTIVO';
  mustChangePassword: boolean;
  failedAttempts: number;
  lockedUntil: Date | null;
  tokenVersion: number;
}

export interface PlantAccess {
  id: string;
  code: string;
  name: string;
  address: string | null;
}

export interface UserProfile {
  id: string;
  username: string;
  name: string;
  email: string | null;
  role: UserRole;
  mustChangePassword: boolean;
  empresa: { id: string; name: string } | null;
  plants: PlantAccess[];
}

export interface SessionTokens {
  accessToken: string;
  accessExpiresIn: number;
  refreshToken: string;
  refreshExpiresAt: string;
}

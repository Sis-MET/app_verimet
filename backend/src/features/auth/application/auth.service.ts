import bcrypt from 'bcrypt';
import crypto from 'node:crypto';
import jwt, { type SignOptions } from 'jsonwebtoken';
import { env } from '@core/config';
import { TooManyRequestsError, UnauthorizedError, ValidationError } from '@core/errors';
import type { AccessTokenPayload } from '@shared/types';
import type { SessionTokens, StoredUser, UserProfile } from '../domain/auth.types';
import { authRepository, type AuthRepository } from '../infrastructure/auth.repository';

const MAX_FAILED_ATTEMPTS = 5;
const ACCESS_EXPIRES_SECONDS = 15 * 60;

function normalizeUsername(value: string): string {
  return value.normalize('NFKC').trim().toUpperCase();
}

function durationSeconds(value: string): number {
  const match = /^(\d+)([smhd])$/.exec(value.trim());
  if (!match) throw new Error(`Duracion JWT no soportada: ${value}`);
  const amount = Number(match[1]);
  const multiplier = { s: 1, m: 60, h: 3600, d: 86400 }[match[2] as 's' | 'm' | 'h' | 'd'];
  return amount * multiplier;
}

function createRefreshToken(): string {
  return crypto.randomBytes(48).toString('base64url');
}

export function hashRefreshToken(token: string): Buffer {
  return crypto.createHmac('sha256', env.JWT_REFRESH_SECRET).update(token, 'utf8').digest();
}

export class AuthService {
  constructor(private readonly repository: AuthRepository = authRepository) {}

  private issueAccessToken(user: StoredUser): string {
    const payload: AccessTokenPayload = {
      sub: user.id,
      username: user.username,
      name: user.name,
      role: user.role,
      empresa_id: user.empresaId,
      token_version: user.tokenVersion,
      type: 'access',
    };
    const options: SignOptions = {
      algorithm: 'HS256',
      expiresIn: env.JWT_ACCESS_EXPIRES_IN as SignOptions['expiresIn'],
      issuer: env.JWT_ISSUER,
      audience: env.JWT_AUDIENCE,
    };
    return jwt.sign(payload, env.JWT_SECRET, options);
  }

  private async issueSession(user: StoredUser, input: {
    deviceId: string;
    deviceName?: string;
    ip?: string;
  }): Promise<SessionTokens> {
    const refreshToken = createRefreshToken();
    const refreshSeconds = durationSeconds(env.JWT_REFRESH_EXPIRES_IN);
    const refreshExpiresAt = new Date(Date.now() + refreshSeconds * 1000);
    await this.repository.createRefreshSession({
      userId: user.id,
      tokenHash: hashRefreshToken(refreshToken),
      deviceId: input.deviceId,
      deviceName: input.deviceName,
      expiresAt: refreshExpiresAt,
      ip: input.ip,
    });
    return {
      accessToken: this.issueAccessToken(user),
      accessExpiresIn: durationSeconds(env.JWT_ACCESS_EXPIRES_IN) || ACCESS_EXPIRES_SECONDS,
      refreshToken,
      refreshExpiresAt: refreshExpiresAt.toISOString(),
    };
  }

  async login(input: {
    username: string;
    password: string;
    deviceId: string;
    deviceName?: string;
    ip?: string;
  }): Promise<{ user: UserProfile; tokens: SessionTokens }> {
    const user = await this.repository.findByNormalizedUsername(normalizeUsername(input.username));
    if (!user) {
      await bcrypt.hash(input.password, env.BCRYPT_SALT_ROUNDS);
      throw new UnauthorizedError('Usuario o contrasena incorrectos');
    }
    if (user.lockedUntil && user.lockedUntil > new Date()) {
      throw new TooManyRequestsError('Cuenta bloqueada temporalmente', {
        lockedUntil: user.lockedUntil.toISOString(),
      });
    }
    const valid = await bcrypt.compare(input.password, user.passwordHash);
    if (!valid) {
      await this.repository.recordFailedAttempt(user.id);
      if (user.failedAttempts + 1 >= MAX_FAILED_ATTEMPTS) {
        throw new TooManyRequestsError('Cuenta bloqueada durante 15 minutos');
      }
      throw new UnauthorizedError('Usuario o contrasena incorrectos');
    }
    if (user.status !== 'ACTIVO') throw new UnauthorizedError('Usuario inactivo');
    await this.repository.recordSuccessfulLogin(user.id, input.ip, input.deviceId);
    return {
      user: await this.repository.getProfile(user.id),
      tokens: await this.issueSession(user, input),
    };
  }

  async refresh(input: {
    refreshToken: string;
    deviceId: string;
    deviceName?: string;
    ip?: string;
  }): Promise<SessionTokens> {
    const nextToken = createRefreshToken();
    const refreshSeconds = durationSeconds(env.JWT_REFRESH_EXPIRES_IN);
    const expiresAt = new Date(Date.now() + refreshSeconds * 1000);
    const user = await this.repository.rotateRefreshSession({
      oldHash: hashRefreshToken(input.refreshToken),
      newHash: hashRefreshToken(nextToken),
      deviceId: input.deviceId,
      deviceName: input.deviceName,
      expiresAt,
      ip: input.ip,
    });
    return {
      accessToken: this.issueAccessToken(user),
      accessExpiresIn: durationSeconds(env.JWT_ACCESS_EXPIRES_IN),
      refreshToken: nextToken,
      refreshExpiresAt: expiresAt.toISOString(),
    };
  }

  async logout(refreshToken: string): Promise<void> {
    await this.repository.revokeRefreshSession(hashRefreshToken(refreshToken));
  }

  async getProfile(userId: string): Promise<UserProfile> {
    return this.repository.getProfile(userId);
  }

  async changePassword(userId: string, currentPassword: string, newPassword: string): Promise<void> {
    if (currentPassword === newPassword) {
      throw new ValidationError('La nueva contrasena debe ser diferente');
    }
    const user = await this.repository.findById(userId);
    if (!user || !(await bcrypt.compare(currentPassword, user.passwordHash))) {
      throw new UnauthorizedError('La contrasena actual es incorrecta');
    }
    const hash = await bcrypt.hash(newPassword, env.BCRYPT_SALT_ROUNDS);
    await this.repository.changePassword(userId, hash);
  }
}

export const authService = new AuthService();

import assert from 'node:assert/strict';
import test from 'node:test';
import bcrypt from 'bcrypt';

Object.assign(process.env, {
  NODE_ENV: 'test', DB_HOST: 'localhost', DB_NAME: 'test', DB_USER: 'test', DB_PASSWORD: 'test',
  JWT_SECRET: 'access-secret-for-tests-at-least-32-characters',
  JWT_REFRESH_SECRET: 'refresh-secret-for-tests-at-least-32-characters',
  JWT_ISSUER: 'servicemet-api', JWT_AUDIENCE: 'ivmet-mobile',
});

const storedUser = async () => ({
  id: '00000000-0000-4000-8000-000000000001', username: 'operador', normalizedUsername: 'OPERADOR',
  name: 'Operador', email: null, passwordHash: await bcrypt.hash('ClaveTemporal123', 8),
  role: 'cliente_operador' as const, empresaId: '10', status: 'ACTIVO' as const,
  mustChangePassword: true, failedAttempts: 0, lockedUntil: null, tokenVersion: 1,
});

test('login emite access corto, refresh opaco y conserva cambio obligatorio', async () => {
  const user = await storedUser();
  let storedHash: Buffer | undefined;
  const repository = {
    findByNormalizedUsername: async () => user,
    recordSuccessfulLogin: async () => undefined,
    recordFailedAttempt: async () => undefined,
    createRefreshSession: async (input: { tokenHash: Buffer }) => { storedHash = input.tokenHash; return 'session'; },
    getProfile: async () => ({ id: user.id, username: user.username, name: user.name, email: null,
      role: user.role, mustChangePassword: true, empresa: { id: '10', name: 'Cliente' }, plants: [] }),
  };
  const { AuthService } = await import('../src/features/auth/application/auth.service');
  const service = new AuthService(repository as never);
  const result = await service.login({ username: ' operador ', password: 'ClaveTemporal123', deviceId: 'phone-1' });
  assert.equal(result.user.mustChangePassword, true);
  assert.equal(result.tokens.accessExpiresIn, 900);
  assert.ok(result.tokens.refreshToken.length >= 32);
  assert.equal(storedHash?.length, 32);
  assert.notEqual(storedHash?.toString('hex'), Buffer.from(result.tokens.refreshToken).toString('hex'));
});

test('login registra el intento fallido sin revelar si el usuario existe', async () => {
  const user = await storedUser();
  let failed = 0;
  const repository = { findByNormalizedUsername: async () => user, recordFailedAttempt: async () => { failed += 1; } };
  const { AuthService } = await import('../src/features/auth/application/auth.service');
  const service = new AuthService(repository as never);
  await assert.rejects(service.login({ username: 'operador', password: 'incorrecta', deviceId: 'phone-1' }), /incorrectos/);
  assert.equal(failed, 1);
});

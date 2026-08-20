import { config as loadDotenv } from 'dotenv';
import { z } from 'zod';

loadDotenv();

/**
 * Esquema de variables de entorno. Se valida una sola vez al arrancar el
 * proceso: si falta algo o esta mal tipado, la API no levanta (fail fast).
 */
/**
 * `z.coerce.boolean()` no sirve para variables de entorno: cualquier string no
 * vacio (incluido "false") se convierte en `true`. Este helper lee el texto.
 */
const booleanFromEnv = (defaultValue: boolean) =>
  z
    .enum(['true', 'false', '1', '0'])
    .default(defaultValue ? 'true' : 'false')
    .transform((value) => value === 'true' || value === '1');

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  API_PREFIX: z.string().default('/api/ivmet/v1'),
  IVMET_ENABLED: booleanFromEnv(false),
  IVMET_SYNC_ENABLED: booleanFromEnv(false),
  IVMET_APPROVED_PROCEDURES: z.string().default(''),

  // SQL Server
  DB_HOST: z.string().min(1),
  DB_PORT: z.coerce.number().int().positive().default(1433),
  DB_NAME: z.string().min(1),
  DB_USER: z.string().min(1),
  DB_PASSWORD: z.string().min(1),
  DB_ENCRYPT: booleanFromEnv(true),
  DB_TRUST_SERVER_CERTIFICATE: booleanFromEnv(true),
  DATABASE_URL: z.string().min(1).optional(),

  // JWT
  JWT_SECRET: z.string().min(32),
  JWT_ACCESS_EXPIRES_IN: z.string().regex(/^\d+[smhd]$/).default('15m'),
  JWT_REFRESH_SECRET: z.string().min(32),
  JWT_REFRESH_EXPIRES_IN: z.string().regex(/^\d+[smhd]$/).default('30d'),
  JWT_ISSUER: z.string().default('servicemet-api'),
  JWT_AUDIENCE: z.string().default('ivmet-mobile'),

  // Seguridad / logging
  BCRYPT_SALT_ROUNDS: z.coerce.number().int().min(8).max(15).default(12),
  CORS_ORIGINS: z.string().default('*'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
}).superRefine((value, context) => {
  if (value.IVMET_SYNC_ENABLED && !value.IVMET_ENABLED) {
    context.addIssue({ code: 'custom', path: ['IVMET_SYNC_ENABLED'], message: 'No puede activarse si IVMET_ENABLED=false' });
  }
  if (value.IVMET_SYNC_ENABLED && !value.IVMET_APPROVED_PROCEDURES.trim()) {
    context.addIssue({ code: 'custom', path: ['IVMET_APPROVED_PROCEDURES'], message: 'Declare al menos un procedimiento aprobado antes de habilitar sync' });
  }
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  const detail = parsed.error.issues
    .map((issue) => `  - ${issue.path.join('.')}: ${issue.message}`)
    .join('\n');
  throw new Error(`Variables de entorno invalidas:\n${detail}`);
}

export const env = parsed.data;

export const isProduction = env.NODE_ENV === 'production';
export const isTest = env.NODE_ENV === 'test';

export const corsOrigins =
  env.CORS_ORIGINS === '*' ? '*' : env.CORS_ORIGINS.split(',').map((o) => o.trim());

export const approvedProcedures = new Set(
  env.IVMET_APPROVED_PROCEDURES.split(',').map((value) => value.trim()).filter(Boolean),
);

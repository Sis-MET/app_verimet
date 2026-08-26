import { config as loadDotenv } from 'dotenv';
import { z } from 'zod';

loadDotenv();

const booleanFromEnv = (defaultValue: boolean) =>
  z
    .enum(['true', 'false', '1', '0'])
    .default(defaultValue ? 'true' : 'false')
    .transform((value) => value === 'true' || value === '1');

const optionalUuid = z
  .string()
  .default('')
  .transform((value) => value.trim())
  .pipe(z.union([z.literal(''), z.string().uuid()]))
  .transform((value) => value || undefined);

const envSchema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']).default('development'),
  LOG_LEVEL: z.enum(['fatal', 'error', 'warn', 'info', 'debug', 'trace']).default('info'),
  WORKER_ID: z.string().trim().min(3).max(150),
  WORKER_ENABLED: booleanFromEnv(false),
  WORKER_SCOPE_ID: optionalUuid,
  WORKER_OUTBOX_BATCH_SIZE: z.coerce.number().int().min(1).max(500).default(50),
  WORKER_OUTBOX_POLL_SECONDS: z.coerce.number().int().min(1).max(3600).default(10),
  WORKER_CATALOG_INTERVAL_SECONDS: z.coerce.number().int().min(30).max(86400).default(300),
  WORKER_RETRY_SECONDS: z.coerce.number().int().min(1).max(86400).default(60),
  WORKER_LEASE_SECONDS: z.coerce.number().int().min(30).max(3600).default(300),

  DATAMET_DB_HOST: z.string().trim().min(1),
  DATAMET_DB_PORT: z.coerce.number().int().positive().default(1433),
  DATAMET_DB_NAME: z.string().trim().min(1).default('DataMET'),
  DATAMET_DB_USER: z.string().trim().min(1),
  DATAMET_DB_PASSWORD: z.string().min(1),
  DATAMET_DB_ENCRYPT: booleanFromEnv(false),
  DATAMET_DB_TRUST_SERVER_CERTIFICATE: booleanFromEnv(true),

  IVMET_DB_HOST: z.string().trim().min(1),
  IVMET_DB_PORT: z.coerce.number().int().positive().default(1433),
  IVMET_DB_NAME: z.literal('IvMET').default('IvMET'),
  IVMET_DB_USER: z.string().trim().min(1),
  IVMET_DB_PASSWORD: z.string().min(1),
  IVMET_DB_ENCRYPT: booleanFromEnv(false),
  IVMET_DB_TRUST_SERVER_CERTIFICATE: booleanFromEnv(true),

  SUPABASE_URL: z.string().url().refine((value) => value.startsWith('https://'), {
    message: 'debe usar HTTPS',
  }),
  SUPABASE_SERVICE_ROLE_KEY: z.string().min(40),
});

const parsed = envSchema.safeParse(process.env);

if (!parsed.success) {
  const detail = parsed.error.issues
    .map((issue) => `  - ${issue.path.join('.')}: ${issue.message}`)
    .join('\n');
  throw new Error(`Variables de entorno invalidas para IvMET Worker:\n${detail}`);
}

export const env = parsed.data;

export type SqlConnectionSettings = {
  host: string;
  port: number;
  database: string;
  user: string;
  password: string;
  encrypt: boolean;
  trustServerCertificate: boolean;
};

export const dataMetSqlSettings: SqlConnectionSettings = {
  host: env.DATAMET_DB_HOST,
  port: env.DATAMET_DB_PORT,
  database: env.DATAMET_DB_NAME,
  user: env.DATAMET_DB_USER,
  password: env.DATAMET_DB_PASSWORD,
  encrypt: env.DATAMET_DB_ENCRYPT,
  trustServerCertificate: env.DATAMET_DB_TRUST_SERVER_CERTIFICATE,
};

export const ivmetSqlSettings: SqlConnectionSettings = {
  host: env.IVMET_DB_HOST,
  port: env.IVMET_DB_PORT,
  database: env.IVMET_DB_NAME,
  user: env.IVMET_DB_USER,
  password: env.IVMET_DB_PASSWORD,
  encrypt: env.IVMET_DB_ENCRYPT,
  trustServerCertificate: env.IVMET_DB_TRUST_SERVER_CERTIFICATE,
};

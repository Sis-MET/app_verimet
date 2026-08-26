import pino from 'pino';
import { env } from './config';

export const logger = pino({
  level: env.LOG_LEVEL,
  base: {
    service: 'ivmet-worker',
    workerId: env.WORKER_ID,
  },
  redact: {
    paths: [
      'password',
      '*.password',
      'serviceRoleKey',
      '*.serviceRoleKey',
      'SUPABASE_SERVICE_ROLE_KEY',
    ],
    censor: '[REDACTED]',
  },
});

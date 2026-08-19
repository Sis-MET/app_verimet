import pino from 'pino';
import { env, isProduction } from '@core/config';

export const logger = pino({
  level: env.LOG_LEVEL,
  ...(isProduction
    ? {}
    : { transport: { target: 'pino-pretty', options: { colorize: true, translateTime: 'SYS:HH:MM:ss' } } }),
});

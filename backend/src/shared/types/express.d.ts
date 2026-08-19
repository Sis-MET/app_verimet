import type { AuthenticatedUser } from './authenticated-user';

declare global {
  namespace Express {
    interface Request {
      /** Poblado por `authenticate` (core/middlewares/auth.middleware.ts). */
      user?: AuthenticatedUser;
      /** Id de correlacion para trazar un request en los logs. */
      requestId?: string;
    }
  }
}

export {};

import { Router } from 'express';

/**
 * Autenticacion: login, refresh token, perfil del usuario.
 *
 * Ojo: a diferencia del resto de features, estas rutas son (en su mayoria)
 * PUBLICAS. El middleware `authenticate` se aplica ruta por ruta, no al router
 * completo (ej. `GET /auth/me` si lo lleva, `POST /auth/login` no).
 *
 * Scaffold: aun no hay endpoints implementados.
 */
export const authRouter = Router();

// TODO(IvMET): POST /login, POST /refresh, POST /logout, GET /me.

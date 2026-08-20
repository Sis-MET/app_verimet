import { Router } from 'express';
import { authenticate, validate } from '@core/middlewares';
import { asyncHandler } from '@shared/utils/async-handler';
import { changePassword, login, logout, me, refresh } from './auth.controller';
import { changePasswordDto, loginDto, logoutDto, refreshDto } from './dto/auth.dto';

/**
 * Autenticacion: login, refresh token, perfil del usuario.
 *
 * Ojo: a diferencia del resto de features, estas rutas son (en su mayoria)
 * PUBLICAS. El middleware `authenticate` se aplica ruta por ruta, no al router
 * completo (ej. `GET /auth/me` si lo lleva, `POST /auth/login` no).
 *
 */
export const authRouter = Router();

authRouter.post('/login', validate(loginDto), asyncHandler(login));
authRouter.post('/refresh', validate(refreshDto), asyncHandler(refresh));
authRouter.post('/logout', validate(logoutDto), asyncHandler(logout));
authRouter.get('/me', authenticate, asyncHandler(me));
authRouter.post('/change-password', authenticate, validate(changePasswordDto), asyncHandler(changePassword));

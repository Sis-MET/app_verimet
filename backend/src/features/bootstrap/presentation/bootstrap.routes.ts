import { Router } from 'express';
import { authenticate, requirePasswordChanged, requireRole } from '@core/middlewares';
import { asyncHandler } from '@shared/utils/async-handler';
import { authenticatedUser } from '@shared/security/access-control';
import { bootstrapService } from '../application/bootstrap.service';

export const bootstrapRouter = Router();
bootstrapRouter.get('/', authenticate, requirePasswordChanged, requireRole('cliente_operador', 'cliente_jefe_calidad'), asyncHandler(async (req, res) => {
  res.json(await bootstrapService.get(authenticatedUser(req)));
}));

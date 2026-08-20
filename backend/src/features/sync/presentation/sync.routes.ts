import { Router } from 'express';
import { authenticate, requirePasswordChanged, requireRole, validate } from '@core/middlewares';
import { asyncHandler } from '@shared/utils/async-handler';
import { uploadVerifications } from './sync.controller';
import { syncVerificationsDto } from './dto/sync.dto';

/**
 * Sincronizacion offline-first: ingesta por lotes de lo capturado en el celular.
 *
 */
export const syncRouter = Router();

syncRouter.post('/verifications', authenticate, requirePasswordChanged,
  requireRole('cliente_operador', 'cliente_jefe_calidad'), validate(syncVerificationsDto), asyncHandler(uploadVerifications));

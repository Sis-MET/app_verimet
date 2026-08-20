import { Router } from 'express';
import { authenticate, requirePasswordChanged, requireRole, validate } from '@core/middlewares';
import { asyncHandler } from '@shared/utils/async-handler';
import * as controller from './alerts.controller';
import * as dto from './dto/alerts.dto';

export const alertsRouter = Router();
alertsRouter.use(authenticate, requirePasswordChanged);
alertsRouter.get('/', validate(dto.listAlertsQueryDto, 'query'), asyncHandler(controller.list));
alertsRouter.post('/:alertId/share', requireRole('cliente_jefe_calidad'), validate(dto.alertParamsDto, 'params'), validate(dto.shareAlertDto), asyncHandler(controller.share));
alertsRouter.post('/:alertId/archive', requireRole('cliente_jefe_calidad'), validate(dto.alertParamsDto, 'params'), asyncHandler(controller.archive));
alertsRouter.post('/:alertId/acknowledge', requireRole('metrica_tecnico', 'metrica_admin'), validate(dto.alertParamsDto, 'params'), asyncHandler(controller.acknowledge));
alertsRouter.post('/:alertId/attend', requireRole('metrica_tecnico', 'metrica_admin'), validate(dto.alertParamsDto, 'params'), validate(dto.attendAlertDto), asyncHandler(controller.attend));

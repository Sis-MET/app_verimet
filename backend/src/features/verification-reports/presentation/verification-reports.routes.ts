import { Router } from 'express';
import { authenticate, requirePasswordChanged, requireRole, validate } from '@core/middlewares';
import { asyncHandler } from '@shared/utils/async-handler';
import * as controller from './verification-reports.controller';
import * as dto from './dto/verification-reports.dto';

/**
 * Reportes de verificacion intermedia (agrupan las tres pruebas) y su PDF.
 *
 */
export const verificationReportsRouter = Router();

verificationReportsRouter.use(authenticate, requirePasswordChanged);
verificationReportsRouter.get('/', validate(dto.listVerificationsQueryDto, 'query'), asyncHandler(controller.list));
verificationReportsRouter.get('/:id/report.pdf', validate(dto.verificationParamsDto, 'params'), asyncHandler(controller.reportPdf));
verificationReportsRouter.post('/:id/annul', requireRole('cliente_jefe_calidad'), validate(dto.verificationParamsDto, 'params'), validate(dto.annulVerificationDto), asyncHandler(controller.annul));
verificationReportsRouter.get('/:id', validate(dto.verificationParamsDto, 'params'), asyncHandler(controller.detail));

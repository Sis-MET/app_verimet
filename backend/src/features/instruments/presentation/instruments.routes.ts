import { Router } from 'express';
import { authenticate, requirePasswordChanged, requireRole, validate } from '@core/middlewares';
import { asyncHandler } from '@shared/utils/async-handler';
import { detail, history, list } from './instruments.controller';
import { instrumentHistoryQueryDto, instrumentParamsDto, listInstrumentsQueryDto } from './dto/instruments.dto';

/**
 * Instrumentos de pesaje (balanzas) del cliente: alta, listado, detalle, estado.
 *
 */
export const instrumentsRouter = Router();

instrumentsRouter.use(authenticate, requirePasswordChanged, requireRole('cliente_operador', 'cliente_jefe_calidad'));
instrumentsRouter.get('/', validate(listInstrumentsQueryDto, 'query'), asyncHandler(list));
instrumentsRouter.get('/:code/history', validate(instrumentParamsDto, 'params'), validate(instrumentHistoryQueryDto, 'query'), asyncHandler(history));
instrumentsRouter.get('/:code', validate(instrumentParamsDto, 'params'), asyncHandler(detail));

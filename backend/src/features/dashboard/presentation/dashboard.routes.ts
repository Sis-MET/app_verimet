import { Router } from 'express';
import { authenticate, requirePasswordChanged } from '@core/middlewares';
import { asyncHandler } from '@shared/utils/async-handler';
import { getDashboard } from './dashboard.controller';

/**
 * Vista interna de Metrica: estado de todas las balanzas de todos los clientes.
 *
 */
export const dashboardRouter = Router();

dashboardRouter.get('/', authenticate, requirePasswordChanged, asyncHandler(getDashboard));

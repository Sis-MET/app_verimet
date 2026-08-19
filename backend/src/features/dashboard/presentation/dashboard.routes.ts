import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Vista interna de Metrica: estado de todas las balanzas de todos los clientes.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const dashboardRouter = Router();

dashboardRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "dashboard".

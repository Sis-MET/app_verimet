import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Instrumentos de pesaje (balanzas) del cliente: alta, listado, detalle, estado.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const instrumentsRouter = Router();

instrumentsRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "instruments".

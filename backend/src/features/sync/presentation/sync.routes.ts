import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Sincronizacion offline-first: ingesta por lotes de lo capturado en el celular.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const syncRouter = Router();

syncRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "sync".

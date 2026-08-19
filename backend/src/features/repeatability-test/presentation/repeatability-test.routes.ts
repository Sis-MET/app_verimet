import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Prueba de repetibilidad: repeticiones de una misma carga.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const repeatabilityTestRouter = Router();

repeatabilityTestRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "repeatability-test".

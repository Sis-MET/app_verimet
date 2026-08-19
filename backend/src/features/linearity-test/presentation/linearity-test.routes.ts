import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Prueba de linealidad: barrido de cargas crecientes/decrecientes.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const linearityTestRouter = Router();

linearityTestRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "linearity-test".

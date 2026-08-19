import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Prueba de excentricidad: carga en distintas posiciones del receptor de carga.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const eccentricityTestRouter = Router();

eccentricityTestRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "eccentricity-test".

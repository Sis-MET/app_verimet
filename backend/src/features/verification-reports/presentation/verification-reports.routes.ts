import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Reportes de verificacion intermedia (agrupan las tres pruebas) y su PDF.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const verificationReportsRouter = Router();

verificationReportsRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "verification-reports".

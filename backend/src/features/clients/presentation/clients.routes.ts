import { Router } from 'express';
import { authenticate } from '@core/middlewares';

/**
 * Empresas cliente de Metrica (tenants) y sus sucursales/areas.
 *
 * Scaffold: aun no hay endpoints implementados.
 * Al implementar, el flujo por ruta es:
 *   router.<verbo>(path, validate(<Dto>), asyncHandler(<controller>))
 * y el controller delega en un caso de uso de application/.
 */
export const clientsRouter = Router();

clientsRouter.use(authenticate);

// TODO(IvMET): registrar endpoints de "clients".

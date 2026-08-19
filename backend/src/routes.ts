import { Router } from 'express';
import { authRouter } from '@features/auth/presentation/auth.routes';
import { instrumentsRouter } from '@features/instruments/presentation/instruments.routes';
import { eccentricityTestRouter } from '@features/eccentricity-test/presentation/eccentricity-test.routes';
import { repeatabilityTestRouter } from '@features/repeatability-test/presentation/repeatability-test.routes';
import { linearityTestRouter } from '@features/linearity-test/presentation/linearity-test.routes';
import { verificationReportsRouter } from '@features/verification-reports/presentation/verification-reports.routes';
import { clientsRouter } from '@features/clients/presentation/clients.routes';
import { dashboardRouter } from '@features/dashboard/presentation/dashboard.routes';
import { syncRouter } from '@features/sync/presentation/sync.routes';

/**
 * Unico punto donde se montan las features. El nombre de la ruta publica
 * refleja el dominio del negocio, igual que la carpeta.
 */
export const apiRouter = Router();

apiRouter.use('/auth', authRouter);
apiRouter.use('/instruments', instrumentsRouter);
apiRouter.use('/eccentricity-tests', eccentricityTestRouter);
apiRouter.use('/repeatability-tests', repeatabilityTestRouter);
apiRouter.use('/linearity-tests', linearityTestRouter);
apiRouter.use('/verification-reports', verificationReportsRouter);
apiRouter.use('/clients', clientsRouter);
apiRouter.use('/dashboard', dashboardRouter);
apiRouter.use('/sync', syncRouter);

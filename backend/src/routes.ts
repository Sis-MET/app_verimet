import { Router } from 'express';
import { authRouter } from '@features/auth/presentation/auth.routes';
import { instrumentsRouter } from '@features/instruments/presentation/instruments.routes';
import { verificationReportsRouter } from '@features/verification-reports/presentation/verification-reports.routes';
import { dashboardRouter } from '@features/dashboard/presentation/dashboard.routes';
import { syncRouter } from '@features/sync/presentation/sync.routes';
import { administrationRouter } from '@features/administration/presentation/administration.routes';
import { bootstrapRouter } from '@features/bootstrap/presentation/bootstrap.routes';
import { alertsRouter } from '@features/alerts/presentation/alerts.routes';

/**
 * Unico punto donde se montan las features. El nombre de la ruta publica
 * refleja el dominio del negocio, igual que la carpeta.
 */
export const apiRouter = Router();

apiRouter.use('/auth', authRouter);
apiRouter.use('/instruments', instrumentsRouter);
apiRouter.use('/verification-reports', verificationReportsRouter);
apiRouter.use('/verifications', verificationReportsRouter);
apiRouter.use('/dashboard', dashboardRouter);
apiRouter.use('/sync', syncRouter);
apiRouter.use('/admin', administrationRouter);
apiRouter.use('/bootstrap', bootstrapRouter);
apiRouter.use('/alerts', alertsRouter);

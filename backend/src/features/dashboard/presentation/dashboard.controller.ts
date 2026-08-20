import type { Request, Response } from 'express';
import { authenticatedUser } from '@shared/security/access-control';
import { dashboardService } from '../application/dashboard.service';

export async function getDashboard(req: Request, res: Response): Promise<void> {
  res.json(await dashboardService.get(authenticatedUser(req)));
}

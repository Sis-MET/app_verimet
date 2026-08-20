import type { Request, Response } from 'express';
import { authenticatedUser } from '@shared/security/access-control';
import { syncService } from '../application/sync.service';

export async function uploadVerifications(req: Request, res: Response): Promise<void> {
  const result = await syncService.upload(req.body.items, authenticatedUser(req));
  res.status(result.rejected > 0 ? 207 : 200).json(result);
}

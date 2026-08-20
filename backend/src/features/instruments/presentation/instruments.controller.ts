import type { Request, Response } from 'express';
import { authenticatedUser } from '@shared/security/access-control';
import { instrumentsService } from '../application/instruments.service';

export async function list(req: Request, res: Response): Promise<void> {
  res.json(await instrumentsService.list(authenticatedUser(req), req.query as never));
}
export async function detail(req: Request, res: Response): Promise<void> {
  res.json(await instrumentsService.detail(authenticatedUser(req), req.params.code!));
}
export async function history(req: Request, res: Response): Promise<void> {
  const query = req.query as unknown as { page: number; pageSize: number };
  res.json(await instrumentsService.history(authenticatedUser(req), req.params.code!, query.page, query.pageSize));
}

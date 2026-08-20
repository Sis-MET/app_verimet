import type { Request, Response } from 'express';
import { auditRequestMetadata } from '@shared/audit/audit';
import { authenticatedUser } from '@shared/security/access-control';
import { alertsService } from '../application/alerts.service';

export async function list(req: Request, res: Response): Promise<void> {
  res.json(await alertsService.list(authenticatedUser(req), req.query as never));
}
export async function share(req: Request, res: Response): Promise<void> {
  await alertsService.share(req.params.alertId!, req.body.message, authenticatedUser(req), auditRequestMetadata(req)); res.status(204).send();
}
export async function archive(req: Request, res: Response): Promise<void> {
  await alertsService.archive(req.params.alertId!, authenticatedUser(req), auditRequestMetadata(req)); res.status(204).send();
}
export async function acknowledge(req: Request, res: Response): Promise<void> {
  await alertsService.acknowledge(req.params.alertId!, authenticatedUser(req), auditRequestMetadata(req)); res.status(204).send();
}
export async function attend(req: Request, res: Response): Promise<void> {
  await alertsService.attend(req.params.alertId!, req.body.comment, authenticatedUser(req), auditRequestMetadata(req)); res.status(204).send();
}

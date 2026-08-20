import type { Request, Response } from 'express';
import { auditRequestMetadata } from '@shared/audit/audit';
import { authenticatedUser } from '@shared/security/access-control';
import { verificationPdfService } from '../application/verification-pdf.service';
import { verificationReportsService } from '../application/verification-reports.service';

export async function list(req: Request, res: Response): Promise<void> {
  res.json(await verificationReportsService.list(authenticatedUser(req), req.query as never));
}
export async function detail(req: Request, res: Response): Promise<void> {
  res.json(await verificationReportsService.detail(authenticatedUser(req), req.params.id!));
}
export async function annul(req: Request, res: Response): Promise<void> {
  await verificationReportsService.annul(authenticatedUser(req), req.params.id!, req.body.reason, auditRequestMetadata(req));
  res.status(204).send();
}
export async function reportPdf(req: Request, res: Response): Promise<void> {
  const detail = await verificationReportsService.detail(authenticatedUser(req), req.params.id!);
  const pdf = await verificationPdfService.generate(detail);
  res.setHeader('Content-Type', 'application/pdf');
  res.setHeader('Content-Disposition', `inline; filename="ivmet-${req.params.id}.pdf"`);
  res.setHeader('Content-Length', String(pdf.length));
  res.send(pdf);
}

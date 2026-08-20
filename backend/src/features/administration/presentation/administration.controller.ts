import type { Request, Response } from 'express';
import { auditRequestMetadata } from '@shared/audit/audit';
import { authenticatedUser } from '@shared/security/access-control';
import { administrationService } from '../application/administration.service';

export async function listClients(_req: Request, res: Response): Promise<void> { res.json({ items: await administrationService.listClients() }); }
export async function listPlants(req: Request, res: Response): Promise<void> { res.json({ items: await administrationService.listPlants(req.params.clientId!) }); }
export async function listAreas(req: Request, res: Response): Promise<void> { res.json({ items: await administrationService.listAreas(req.query) }); }
export async function listInstruments(req: Request, res: Response): Promise<void> { res.json({ items: await administrationService.listInstruments(req.query) }); }
export async function listPatterns(req: Request, res: Response): Promise<void> { res.json({ items: await administrationService.listPatterns(req.query) }); }
export async function listPlans(_req: Request, res: Response): Promise<void> { res.json({ items: await administrationService.listPlans() }); }
export async function getPlanVersion(req: Request, res: Response): Promise<void> { res.json(await administrationService.getPlanVersion(req.params.versionId!)); }
export async function listAssignments(req: Request, res: Response): Promise<void> { res.json({ items: await administrationService.listAssignments(req.query) }); }

export async function listUsers(req: Request, res: Response): Promise<void> {
  res.json({ items: await administrationService.listUsers(req.query) });
}
export async function createUser(req: Request, res: Response): Promise<void> {
  const id = await administrationService.createUser(req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(201).json({ id });
}
export async function updateUserStatus(req: Request, res: Response): Promise<void> {
  await administrationService.updateUserStatus(req.params.userId!, req.body.status, authenticatedUser(req), auditRequestMetadata(req));
  res.status(204).send();
}
export async function resetPassword(req: Request, res: Response): Promise<void> {
  await administrationService.resetPassword(req.params.userId!, req.body.temporaryPassword, authenticatedUser(req), auditRequestMetadata(req));
  res.status(204).send();
}
export async function assignUserPlants(req: Request, res: Response): Promise<void> {
  await administrationService.assignUserPlants(req.params.userId!, req.body.plantIds, authenticatedUser(req), auditRequestMetadata(req));
  res.status(204).send();
}
export async function createArea(req: Request, res: Response): Promise<void> {
  const id = await administrationService.createArea(req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(201).json({ id });
}
export async function enableInstrument(req: Request, res: Response): Promise<void> {
  await administrationService.enableInstrument(req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(204).send();
}
export async function updateInstrument(req: Request, res: Response): Promise<void> {
  await administrationService.updateInstrument(req.params.code!, req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(204).send();
}
export async function createPattern(req: Request, res: Response): Promise<void> {
  const id = await administrationService.createPattern(req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(201).json({ id });
}
export async function createCertificate(req: Request, res: Response): Promise<void> {
  const id = await administrationService.createCertificate(req.params.patternId!, req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(201).json({ id });
}
export async function createPlan(req: Request, res: Response): Promise<void> {
  const id = await administrationService.createPlan(req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(201).json({ id });
}
export async function createPlanVersion(req: Request, res: Response): Promise<void> {
  const id = await administrationService.createPlanVersion(req.params.planId!, req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(201).json({ id });
}
export async function publishPlanVersion(req: Request, res: Response): Promise<void> {
  await administrationService.publishPlanVersion(req.params.versionId!, authenticatedUser(req), auditRequestMetadata(req));
  res.status(204).send();
}
export async function retirePlanVersion(req: Request, res: Response): Promise<void> {
  await administrationService.retirePlanVersion(req.params.versionId!, authenticatedUser(req), auditRequestMetadata(req));
  res.status(204).send();
}
export async function assignPlan(req: Request, res: Response): Promise<void> {
  const id = await administrationService.assignPlan(req.body, authenticatedUser(req), auditRequestMetadata(req));
  res.status(201).json({ id });
}

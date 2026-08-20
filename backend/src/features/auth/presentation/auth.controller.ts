import type { Request, Response } from 'express';
import { UnauthorizedError } from '@core/errors';
import { authService } from '../application/auth.service';

function requestIp(req: Request): string | undefined {
  return req.ip || req.socket.remoteAddress || undefined;
}

export async function login(req: Request, res: Response): Promise<void> {
  const result = await authService.login({ ...req.body, ip: requestIp(req) });
  res.status(200).json(result);
}

export async function refresh(req: Request, res: Response): Promise<void> {
  const tokens = await authService.refresh({ ...req.body, ip: requestIp(req) });
  res.status(200).json({ tokens });
}

export async function logout(req: Request, res: Response): Promise<void> {
  await authService.logout(String(req.body.refreshToken));
  res.status(204).send();
}

export async function me(req: Request, res: Response): Promise<void> {
  if (!req.user) throw new UnauthorizedError();
  res.json({ user: await authService.getProfile(req.user.id) });
}

export async function changePassword(req: Request, res: Response): Promise<void> {
  if (!req.user) throw new UnauthorizedError();
  await authService.changePassword(req.user.id, req.body.currentPassword, req.body.newPassword);
  res.status(204).send();
}

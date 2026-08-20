import { z } from 'zod';

export const listVerificationsQueryDto = z.object({
  page: z.coerce.number().int().positive().default(1),
  pageSize: z.coerce.number().int().positive().max(100).default(25),
  equipmentCode: z.string().trim().max(100).optional(),
  plantId: z.string().trim().max(50).optional(),
  from: z.string().datetime({ offset: true }).optional(),
  to: z.string().datetime({ offset: true }).optional(),
});
export const verificationParamsDto = z.object({ id: z.string().uuid() });
export const annulVerificationDto = z.object({ reason: z.string().trim().min(5).max(1000) });

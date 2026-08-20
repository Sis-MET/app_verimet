import { z } from 'zod';

export const listAlertsQueryDto = z.object({
  page: z.coerce.number().int().positive().default(1),
  pageSize: z.coerce.number().int().positive().max(100).default(25),
  status: z.string().trim().max(30).optional(),
});
export const alertParamsDto = z.object({ alertId: z.string().uuid() });
export const shareAlertDto = z.object({ message: z.string().trim().min(3).max(1000) });
export const attendAlertDto = z.object({ comment: z.string().trim().min(3).max(1000) });

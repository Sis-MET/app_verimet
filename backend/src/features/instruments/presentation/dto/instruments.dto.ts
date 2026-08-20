import { z } from 'zod';

export const listInstrumentsQueryDto = z.object({
  page: z.coerce.number().int().positive().default(1),
  pageSize: z.coerce.number().int().positive().max(100).default(25),
  plantId: z.string().trim().max(50).optional(),
  areaId: z.string().uuid().optional(),
  search: z.string().trim().max(100).optional(),
});

export const instrumentParamsDto = z.object({ code: z.string().trim().min(1).max(100) });
export const instrumentHistoryQueryDto = z.object({
  page: z.coerce.number().int().positive().default(1),
  pageSize: z.coerce.number().int().positive().max(100).default(25),
});

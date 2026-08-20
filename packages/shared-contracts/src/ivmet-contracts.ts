import { z } from 'zod';

export const USER_ROLES = ['cliente_operador', 'cliente_jefe_calidad', 'metrica_tecnico', 'metrica_admin'] as const;
export const userRoleSchema = z.enum(USER_ROLES);
export type UserRole = z.infer<typeof userRoleSchema>;

export const TEST_EXECUTION_STATUSES = ['performed', 'omitted'] as const;
export const testExecutionStatusSchema = z.enum(TEST_EXECUTION_STATUSES);

export const TRACEABILITY_STATUSES = ['traceable', 'non_traceable'] as const;
export const traceabilityStatusSchema = z.enum(TRACEABILITY_STATUSES);

export const PLAN_VERSION_STATUSES = ['BORRADOR', 'PUBLICADO', 'RETIRADO'] as const;
export const planVersionStatusSchema = z.enum(PLAN_VERSION_STATUSES);

export const EVALUATION_METHODS = ['absolute_error', 'range', 'sample_standard_deviation'] as const;
export const evaluationMethodSchema = z.enum(EVALUATION_METHODS);

export const decimalStringSchema = z.string().regex(/^-?\d{1,10}(?:\.\d{1,9})?$/);
export const environmentalDecimalStringSchema = z.string().regex(/^-?\d{1,6}(?:\.\d{1,3})?$/);

export const syncVerificationSchema = z.object({
  clientUuid: z.string().uuid(), equipmentCode: z.string().min(1).max(100),
  planVersionId: z.string().uuid(), capturedByUserId: z.string().uuid().optional(),
  performedAt: z.string().datetime(), temperatureC: environmentalDecimalStringSchema.optional(),
  relativeHumidityPct: environmentalDecimalStringSchema.refine((value) => Number(value) >= 0 && Number(value) <= 100).optional(),
  observations: z.string().max(2000).optional(),
  appVersion: z.string().max(50).optional(), deviceId: z.string().min(1).max(200),
  standards: z.array(z.object({ patternId: z.string().uuid(), certificateId: z.string().uuid(), role: z.string().min(1).max(30) })).min(1),
  tests: z.array(z.discriminatedUnion('status', [
    z.object({ type: z.enum(['eccentricity', 'repeatability', 'linearity']), status: z.literal('performed'),
      readings: z.array(z.object({ pointId: z.string().uuid(), indication: decimalStringSchema,
        zeroReturn: decimalStringSchema.optional(), metadata: z.record(z.unknown()).optional() })).min(1),
      observations: z.string().max(1000).optional() }),
    z.object({ type: z.enum(['eccentricity', 'repeatability', 'linearity']), status: z.literal('omitted'),
      omissionReason: z.string().min(3).max(1000), observations: z.string().max(1000).optional() }),
  ])).min(1).max(3),
});
export type SyncVerification = z.infer<typeof syncVerificationSchema>;

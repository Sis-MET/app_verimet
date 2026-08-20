import { z } from 'zod';

const decimal = z.string().regex(/^-?\d{1,10}(?:\.\d{1,9})?$/, 'Use decimal(19,9) como cadena');
const environmentalDecimal = z.string().regex(/^-?\d{1,6}(?:\.\d{1,3})?$/, 'Use decimal(9,3) como cadena');

const readingDto = z.object({
  pointId: z.string().uuid(),
  indication: decimal,
  zeroReturn: decimal.optional(),
  metadata: z.record(z.unknown()).optional(),
});

const testDto = z.discriminatedUnion('status', [
  z.object({
    type: z.enum(['eccentricity', 'repeatability', 'linearity']), status: z.literal('performed'),
    readings: z.array(readingDto).min(1).max(500), observations: z.string().trim().max(1000).optional(),
  }),
  z.object({
    type: z.enum(['eccentricity', 'repeatability', 'linearity']), status: z.literal('omitted'),
    omissionReason: z.string().trim().min(3).max(1000), observations: z.string().trim().max(1000).optional(),
  }),
]);

const verificationDto = z.object({
  clientUuid: z.string().uuid(),
  equipmentCode: z.string().trim().min(1).max(100),
  planVersionId: z.string().uuid(),
  capturedByUserId: z.string().uuid().optional(),
  performedAt: z.string().datetime(),
  temperatureC: environmentalDecimal.optional(),
  relativeHumidityPct: environmentalDecimal.refine((value) => Number(value) >= 0 && Number(value) <= 100, 'Debe estar entre 0 y 100').optional(),
  observations: z.string().trim().max(2000).optional(),
  appVersion: z.string().trim().max(50).optional(),
  deviceId: z.string().trim().max(200),
  standards: z.array(z.object({
    patternId: z.string().uuid(), certificateId: z.string().uuid(), role: z.string().trim().min(1).max(30),
  })).min(1).max(100),
  tests: z.array(testDto).min(1).max(3),
}).superRefine((value, context) => {
  const types = value.tests.map((test) => test.type);
  if (new Set(types).size !== types.length) context.addIssue({ code: 'custom', path: ['tests'], message: 'No repita tipos de prueba' });
  const standards = value.standards.map((standard) => `${standard.patternId}:${standard.role}`);
  if (new Set(standards).size !== standards.length) context.addIssue({ code: 'custom', path: ['standards'], message: 'No repita el mismo patron y rol' });
  if (!value.tests.some((test) => test.status === 'performed')) context.addIssue({ code: 'custom', path: ['tests'], message: 'Al menos una prueba debe ejecutarse' });
});

export const syncVerificationsDto = z.object({ items: z.array(verificationDto).min(1).max(20) });
export type VerificationUpload = z.infer<typeof verificationDto>;

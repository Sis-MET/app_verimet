import { z } from 'zod';

const id = z.string().uuid();
const legacyId = z.string().trim().min(1).max(100);
const unsignedDecimal19_9 = z.string().regex(/^\d{1,10}(?:\.\d{1,9})?$/);
const password = z.string().min(12).max(200)
  .regex(/[a-z]/, 'Debe contener una minuscula')
  .regex(/[A-Z]/, 'Debe contener una mayuscula')
  .regex(/\d/, 'Debe contener un numero');

export const listUsersQueryDto = z.object({
  clientId: z.string().trim().max(50).optional(),
  status: z.enum(['ACTIVO', 'INACTIVO']).optional(),
});

export const createUserDto = z.object({
  username: z.string().trim().min(3).max(100),
  name: z.string().trim().min(2).max(200),
  email: z.string().email().max(254).optional(),
  temporaryPassword: password,
  role: z.enum(['cliente_operador', 'cliente_jefe_calidad', 'metrica_tecnico', 'metrica_admin']),
  clientId: z.string().trim().min(1).max(50).optional(),
  plantIds: z.array(z.string().trim().min(1).max(50)).max(100).default([]),
}).superRefine((value, context) => {
  const clientRole = value.role.startsWith('cliente_');
  if (clientRole && !value.clientId) context.addIssue({ code: 'custom', path: ['clientId'], message: 'Es obligatorio para usuarios de cliente' });
  if (clientRole && value.plantIds.length === 0) context.addIssue({ code: 'custom', path: ['plantIds'], message: 'Asigne al menos una planta' });
  if (!clientRole && (value.clientId || value.plantIds.length)) context.addIssue({ code: 'custom', path: ['clientId'], message: 'Los usuarios de Metrica no pertenecen a un cliente' });
});

export const userIdParamsDto = z.object({ userId: id });
export const updateUserStatusDto = z.object({ status: z.enum(['ACTIVO', 'INACTIVO']) });
export const resetPasswordDto = z.object({ temporaryPassword: password });
export const assignUserPlantsDto = z.object({ plantIds: z.array(z.string().trim().min(1).max(50)).min(1).max(100) });

export const createAreaDto = z.object({
  clientId: z.string().trim().min(1).max(50),
  plantId: z.string().trim().min(1).max(50),
  name: z.string().trim().min(1).max(150),
});
export const clientIdParamsDto = z.object({ clientId: z.string().trim().min(1).max(50) });
export const catalogScopeQueryDto = z.object({
  clientId: z.string().trim().max(50).optional(),
  plantId: z.string().trim().max(50).optional(),
});

export const enableInstrumentDto = z.object({
  equipmentCode: legacyId,
  clientId: z.string().trim().min(1).max(50),
  plantId: z.string().trim().min(1).max(50),
  areaId: id.optional(),
  enabled: z.boolean().default(true),
});

export const equipmentCodeParamsDto = z.object({ code: legacyId });
export const updateInstrumentDto = z.object({ areaId: id.nullable().optional(), enabled: z.boolean().optional() }).refine(
  (value) => value.areaId !== undefined || value.enabled !== undefined,
  'Debe enviar al menos un cambio',
);

export const createPatternDto = z.object({
  clientId: z.string().trim().min(1).max(50),
  code: z.string().trim().min(1).max(100),
  description: z.string().trim().min(1).max(300),
  type: z.string().trim().min(1).max(50),
  class: z.string().trim().max(50).optional(),
  unit: z.string().trim().max(20).optional(),
  capacity: unsignedDecimal19_9.optional(),
  plantIds: z.array(z.string().trim().min(1).max(50)).min(1).max(100),
});

export const patternIdParamsDto = z.object({ patternId: id });
export const createCertificateDto = z.object({
  number: z.string().trim().min(1).max(150),
  laboratory: z.string().trim().min(1).max(250),
  calibratedOn: z.string().date(),
  expiresOn: z.string().date(),
  documentReference: z.string().trim().max(500).optional(),
}).refine((value) => value.expiresOn >= value.calibratedOn, { path: ['expiresOn'], message: 'No puede ser anterior a la calibracion' });

export const createPlanDto = z.object({
  name: z.string().trim().min(1).max(200),
  description: z.string().trim().max(1000).optional(),
});
export const planIdParamsDto = z.object({ planId: id });
export const versionIdParamsDto = z.object({ versionId: id });

const planPointDto = z.object({
  group: z.number().int().positive().default(1),
  order: z.number().int().positive(),
  code: z.string().trim().min(1).max(100),
  label: z.string().trim().min(1).max(200),
  nominalLoad: unsignedDecimal19_9,
  tolerance: unsignedDecimal19_9,
  position: z.string().trim().max(100).optional(),
  direction: z.string().trim().max(30).optional(),
  metadata: z.record(z.unknown()).optional(),
});

const planTestDto = z.object({
  type: z.enum(['eccentricity', 'repeatability', 'linearity']),
  evaluationMethod: z.enum(['absolute_error', 'range', 'sample_standard_deviation']),
  unit: z.string().trim().min(1).max(20),
  frequencyDays: z.number().int().positive().max(3650),
  warningDays: z.number().int().nonnegative().max(3650).default(7),
  metadata: z.record(z.unknown()).optional(),
  points: z.array(planPointDto).min(1).max(500),
});

export const createPlanVersionDto = z.object({
  procedureReference: z.string().trim().min(1).max(300),
  notes: z.string().trim().max(1000).optional(),
  tests: z.array(planTestDto).min(1).max(3),
});

export const assignPlanDto = z.object({
  equipmentCode: legacyId,
  planVersionId: id,
  effectiveFrom: z.string().datetime({ offset: true }),
});

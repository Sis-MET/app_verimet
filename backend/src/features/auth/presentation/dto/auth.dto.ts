import { z } from 'zod';

const password = z
  .string()
  .min(12, 'La contrasena debe tener al menos 12 caracteres')
  .max(128)
  .regex(/[A-Z]/, 'Debe incluir una mayuscula')
  .regex(/[a-z]/, 'Debe incluir una minuscula')
  .regex(/[0-9]/, 'Debe incluir un numero');

export const loginDto = z.object({
  username: z.string().trim().min(1).max(100),
  password: z.string().min(1).max(128),
  deviceId: z.string().trim().min(1).max(200),
  deviceName: z.string().trim().max(200).optional(),
});

export const refreshDto = z.object({
  refreshToken: z.string().min(32).max(500),
  deviceId: z.string().trim().min(1).max(200),
  deviceName: z.string().trim().max(200).optional(),
});

export const logoutDto = z.object({
  refreshToken: z.string().min(32).max(500),
});

export const changePasswordDto = z.object({
  currentPassword: z.string().min(1).max(128),
  newPassword: password,
});

export { password as passwordSchema };

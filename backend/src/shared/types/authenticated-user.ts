/** Roles soportados por IvMET. */
export type UserRole =
  /** Usuario interno de Metrica: ve el dashboard global de todos los clientes. */
  | 'metrica_admin'
  /** Tecnico interno de Metrica. */
  | 'metrica_tecnico'
  /** Jefe de calidad del cliente: comparte alertas y anula registros. */
  | 'cliente_jefe_calidad'
  /** Operador del cliente que ejecuta las verificaciones intermedias. */
  | 'cliente_operador';

/**
 * Usuario resuelto desde el JWT. `empresaId` es la clave del multi-tenant:
 * TODA query de instrumentos/reportes debe filtrar por este valor y nunca por
 * un parametro que venga del request.
 */
export interface AuthenticatedUser {
  readonly id: string;
  readonly username: string;
  readonly name: string;
  readonly role: UserRole;
  /** null solo para usuarios internos de Metrica con alcance global. */
  readonly empresaId: string | null;
  readonly mustChangePassword: boolean;
  readonly tokenVersion: number;
}

/** true si el usuario puede ver datos de todas las empresas. */
export function isMetricaStaff(user: AuthenticatedUser): boolean {
  return user.role === 'metrica_admin' || user.role === 'metrica_tecnico';
}

/** Roles soportados por IvMET. */
export type UserRole =
  /** Usuario interno de Metrica: ve el dashboard global de todos los clientes. */
  | 'metrica_admin'
  /** Tecnico interno de Metrica. */
  | 'metrica_tecnico'
  /** Administrador del lado del cliente (ej. Embol). */
  | 'cliente_admin'
  /** Operador del cliente que ejecuta las verificaciones intermedias. */
  | 'cliente_operador';

/**
 * Usuario resuelto desde el JWT. `empresaId` es la clave del multi-tenant:
 * TODA query de instrumentos/reportes debe filtrar por este valor y nunca por
 * un parametro que venga del request.
 */
export interface AuthenticatedUser {
  readonly id: string;
  readonly email: string;
  readonly role: UserRole;
  /** null solo para usuarios internos de Metrica con alcance global. */
  readonly empresaId: string | null;
}

/** true si el usuario puede ver datos de todas las empresas. */
export function isMetricaStaff(user: AuthenticatedUser): boolean {
  return user.role === 'metrica_admin' || user.role === 'metrica_tecnico';
}

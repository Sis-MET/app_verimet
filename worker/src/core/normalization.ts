const CODE_PATTERN = /^\d{4}-\d{2}-\d{3}$/;

export function optionalText(value: unknown): string | null {
  if (value === null || value === undefined) return null;
  const normalized = String(value).trim();
  return normalized.length > 0 ? normalized : null;
}

export function requiredText(value: unknown, field: string): string {
  const normalized = optionalText(value);
  if (!normalized) throw new Error(`${field} es obligatorio`);
  return normalized;
}

export function canonicalEquipmentCode(value: unknown): string {
  const code = requiredText(value, 'cod_metrica');
  if (!CODE_PATTERN.test(code)) throw new Error(`cod_metrica invalido: ${code}`);
  return code;
}

export function plantCodeFromEquipment(code: string): string {
  return code.slice(0, 7);
}

export function isLegacyActive(value: unknown): boolean {
  return optionalText(value)?.toUpperCase() === 'ACTIVO';
}

export function decimalString(value: unknown): string | null {
  const normalized = optionalText(value);
  if (!normalized) return null;
  if (!/^-?\d+(?:\.\d+)?$/.test(normalized)) {
    throw new Error(`Decimal legado invalido: ${normalized}`);
  }
  return normalized;
}

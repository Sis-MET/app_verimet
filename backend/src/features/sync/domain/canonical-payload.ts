import crypto from 'node:crypto';

function canonicalize(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalize);
  if (value && typeof value === 'object') {
    return Object.fromEntries(Object.entries(value as Record<string, unknown>)
      .sort(([left], [right]) => left.localeCompare(right))
      .map(([key, nested]) => [key, canonicalize(nested)]));
  }
  return value;
}

export function canonicalPayloadJson(value: unknown): string {
  return JSON.stringify(canonicalize(value));
}

export function payloadHash(value: unknown): Buffer {
  return crypto.createHash('sha256').update(canonicalPayloadJson(value), 'utf8').digest();
}

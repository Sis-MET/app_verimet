import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const directory = path.dirname(fileURLToPath(import.meta.url));
const filename = path.resolve(directory, '../openapi/ivmet-v1.yaml');
const document = parse(fs.readFileSync(filename, 'utf8'));

if (document?.openapi !== '3.1.0' || !document.paths || !document.components) {
  throw new Error('El documento no contiene la estructura OpenAPI 3.1 esperada');
}

function resolveReference(reference) {
  if (!reference.startsWith('#/')) return;
  let current = document;
  for (const segment of reference.slice(2).split('/')) {
    current = current?.[segment.replaceAll('~1', '/').replaceAll('~0', '~')];
  }
  if (current === undefined) throw new Error(`Referencia OpenAPI inexistente: ${reference}`);
}

function visit(value) {
  if (Array.isArray(value)) return value.forEach(visit);
  if (!value || typeof value !== 'object') return;
  if (typeof value.$ref === 'string') resolveReference(value.$ref);
  Object.values(value).forEach(visit);
}

visit(document);
process.stdout.write(`OpenAPI valido: ${Object.keys(document.paths).length} rutas, referencias locales resueltas.\n`);

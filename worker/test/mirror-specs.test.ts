import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';
import {
  mirrorSpecs,
  privateEvidenceAggregates,
} from '../src/infrastructure/mirror-specs';

function read(relativePath: string): string {
  return readFileSync(resolve(process.cwd(), '..', relativePath), 'utf8');
}

test('every Supabase outbox aggregate has exactly one SQL mirror spec', () => {
  const migration = read(
    'supabase/migrations/202608240004_integration_outbox.sql',
  );
  const outboxTables = new Set(
    [...migration.matchAll(/^create trigger .+ on public\.([a-z_]+)$/gim)].map(
      (match) => `public.${match[1]}`,
    ),
  );

  assert.equal(outboxTables.size, 32);
  for (const name of privateEvidenceAggregates) outboxTables.delete(name);
  outboxTables.add('public.casos_compartidos');
  outboxTables.add('public.actualizaciones_compartidas');
  assert.deepEqual(new Set(Object.keys(mirrorSpecs)), outboxTables);
  for (const name of privateEvidenceAggregates)
    assert.equal(mirrorSpecs[name], undefined);
  const latest = read('supabase/migrations/202608280004_customer_configuration.sql');
  const allowed = latest.split('create or replace function private.ivmet_export_allowed')[1]!.split('$$;')[0]!;
  assert.deepEqual(new Set([...allowed.matchAll(/'public\.([a-z_]+)'/g)].map(m => `public.${m[1]}`)), new Set(Object.keys(mirrorSpecs)));
});

test('mirror specs match the columns created in SQL Server', () => {
  const sqlText = [
    read('sqlserver/003_mirror_catalog_commercial.sql'),
    read('sqlserver/004_mirror_metrology.sql'),
    read('sqlserver/009_shared_cases_privacy.sql'),
    read('sqlserver/011_customer_configuration_privacy.sql'),
  ].join('\n');
  const sqlColumns = new Map<string, Set<string>>();
  const tablePattern =
    /CREATE TABLE \[mirror\]\.\[([^\]]+)\] \(\r?\n([\s\S]*?)\r?\n    \);/g;

  for (const match of sqlText.matchAll(tablePattern)) {
    const table = match[1]!;
    const body = match[2]!;
    const columns = new Set(
      [...body.matchAll(/^ {8}\[([^\]]+)\]\s+/gm)].map(
        (columnMatch) => columnMatch[1]!,
      ),
    );
    sqlColumns.set(table, columns);
  }

  for (const match of sqlText.matchAll(
    /ALTER TABLE \[mirror\]\.\[([^\]]+)\] ADD \[([^\]]+)\]/g,
  ))
    sqlColumns.get(match[1]!)?.add(match[2]!);
  assert.equal(sqlColumns.size, 34);
  for (const [aggregate, spec] of Object.entries(mirrorSpecs)) {
    const expected = new Set([
      ...spec.columns.map((column) => column.target),
      'source_event_sequence',
      'mirrored_at',
    ]);
    assert.deepEqual(sqlColumns.get(spec.table), expected, aggregate);
    assert.equal(
      new Set(spec.columns.map((column) => column.target)).size,
      spec.columns.length,
    );
    for (const key of spec.keys) {
      assert.ok(expected.has(key), `${aggregate} key ${key} must be projected`);
    }
  }
});

test('every mirror source field exists in its Supabase table', () => {
  const postgresSql = [
    read('supabase/migrations/202608240001_foundation_catalog.sql'),
    read('supabase/migrations/202608240002_commercial_licensing.sql'),
    read('supabase/migrations/202608240003_metrology_online.sql'),
    read('supabase/migrations/202608280001_private_evidence_and_cases.sql'),
    read('supabase/migrations/202608280004_customer_configuration.sql'),
  ].join('\n');
  const postgresColumns = new Map<string, Set<string>>();
  const tablePattern =
    /create table public\.([a-z_]+) \(\r?\n([\s\S]*?)\r?\n\);/gi;

  for (const match of postgresSql.matchAll(tablePattern)) {
    const table = match[1]!;
    const body = match[2]!;
    const columns = new Set(
      [...body.matchAll(/^  ([a-z_][a-z0-9_]*)\s+/gm)]
        .map((columnMatch) => columnMatch[1]!)
        .filter((columnName) => columnName !== 'constraint'),
    );
    postgresColumns.set(table, columns);
  }

  const extension = read(
    'supabase/migrations/202608280002_management_operations.sql',
  );
  for (const name of [
    'published_by_external',
    'retired_by_external',
    'draft_revision',
  ]) {
    assert.ok(extension.includes(`column ${name}`));
    postgresColumns.get('plan_versiones')!.add(name);
  }
  for (const [aggregate, spec] of Object.entries(mirrorSpecs)) {
    const sourceColumns = postgresColumns.get(spec.table);
    assert.ok(sourceColumns, `${aggregate} must exist in Supabase migrations`);
    for (const column of spec.columns) {
      if (
        aggregate === 'public.casos_compartidos' &&
        column.source === 'eventos'
      )
        continue; // Proyección case_export.
      assert.ok(
        sourceColumns.has(column.source),
        `${aggregate}.${column.source} must exist`,
      );
    }
  }
});

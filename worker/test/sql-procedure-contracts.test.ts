import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import test from 'node:test';

function read(relativePath: string): string {
  return readFileSync(resolve(process.cwd(), '..', relativePath), 'utf8');
}

test('SQL procedure calls bind the exact deployed parameter names', () => {
  const repository = read('worker/src/infrastructure/ivmet.repository.ts');
  const procedures = read('sqlserver/005_sync_procedures.sql');
  const executions = [...repository.matchAll(/\.execute\('sync\.([a-z_]+)'\)/g)];

  assert.equal(executions.length, 7);

  for (const execution of executions) {
    const procedureName = execution[1]!;
    const executeIndex = execution.index!;
    const requestIndex = repository.lastIndexOf('.request()', executeIndex);
    assert.notEqual(requestIndex, -1, `request chain missing for ${procedureName}`);

    const requestChain = repository.slice(requestIndex, executeIndex);
    const boundParameters = [
      ...requestChain.matchAll(/\.(?:input|output)\(\s*'([a-z_]+)'/g),
    ].map((match) => match[1]!).sort();

    const procedurePattern = new RegExp(
      `CREATE OR ALTER PROCEDURE \\[sync\\]\\.\\[${procedureName}\\]([\\s\\S]*?)\\r?\\nAS\\r?\\n`,
      'i',
    );
    const procedure = procedures.match(procedurePattern);
    assert.ok(procedure, `SQL definition missing for ${procedureName}`);

    const declaredParameters = [...procedure[1]!.matchAll(/@([a-z_]+)/gi)]
      .map((match) => match[1]!.toLowerCase())
      .sort();

    assert.deepEqual(
      boundParameters,
      declaredParameters,
      `parameter contract mismatch for sync.${procedureName}`,
    );
  }
});

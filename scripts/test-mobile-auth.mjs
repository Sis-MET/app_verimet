import { readFile } from 'node:fs/promises';
import ts from 'typescript';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const stripTypeScriptTypes = (source) => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText;

// Evalúa el handler real con Auth y fetch sustituidos. No lee variables locales
// ni hace peticiones; los únicos valores de configuración son fixtures.
async function fixture(options = {}) {
  let handler;
  const calls = { auth: [], passwords: [], completed: [] };
  const userId = '00000000-0000-4000-8000-000000000001';
  const profile = { activo: true, rol: 'cliente_operador', ...options.profile };
  const client = {
    auth: { getUser: async (token) => {
      calls.auth.push(token);
      return { data: { user: options.invalidToken ? null : { id: userId } }, error: null };
    } },
    from(table) {
      assert.equal(table, 'perfiles');
      return { select() { return this; }, eq(field, id) { assert.equal(field, 'id'); assert.equal(id, userId); return this; },
        async maybeSingle() { return { data: profile, error: null }; } };
    },
    async rpc(name, args) {
      calls.completed.push({ name, args });
      return options.profileFailure ? { data: null, error: { message: 'fixture' } } : { data: { debe_cambiar_password: false }, error: null };
    },
  };
  const context = vm.createContext({
    Request, Response, Headers, AbortSignal,
    console: { error() {} },
    Deno: { env: { get(name) { return ({ SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-server-key', SUPABASE_ANON_KEY: 'fixture-public-key' })[name]; } },
      serve(fn) { handler = fn; } },
    fetch: async (url, init) => {
      assert.equal(url, 'https://fixture.invalid/auth/v1/user');
      calls.passwords.push({ url, init });
      if (options.offline) throw new Error('network fixture');
      return new Response('{}', { status: options.authStatus ?? 200 });
    },
  });
  const supabase = new vm.SyntheticModule(['createClient'], function () {
    this.setExport('createClient', () => client);
  }, { context });
  const shared = new vm.SourceTextModule(stripTypeScriptTypes(await readFile(new URL('../supabase/functions/_shared/http.ts', import.meta.url), 'utf8')), { context });
  const main = new vm.SourceTextModule(stripTypeScriptTypes(await readFile(new URL('../supabase/functions/ivmet-change-password/index.ts', import.meta.url), 'utf8')), { context });
  await main.link(specifier => specifier === 'supabase' ? supabase : shared);
  await main.evaluate();
  return { calls, userId, request: async (body = { password: 'fixture-new-password' }, token = 'Bearer fixture-access') =>
    handler(new Request('https://fixture.invalid/functions/v1/ivmet-change-password', {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: token } : {}) }, body: JSON.stringify(body),
    })) };
}

test('cambio exige JWT válido, perfil activo y contraseña aceptable', async () => {
  let f = await fixture();
  assert.equal((await f.request(undefined, '')).status, 401);
  assert.equal(f.calls.auth.length, 0);
  assert.equal((await f.request({ password: 'short' })).status, 422);
  f = await fixture({ invalidToken: true });
  assert.equal((await f.request()).status, 401);
  assert.equal(f.calls.passwords.length, 0);
  f = await fixture({ profile: { activo: false } });
  assert.equal((await f.request()).status, 403);
  assert.equal(f.calls.passwords.length, 0);
});

test('solo cambia el usuario del JWT y completa el perfil tras Auth', async () => {
  const f = await fixture();
  const result = await f.request({ password: 'fixture-new-password', target_user_id: 'otro-usuario' });
  assert.equal(result.status, 200);
  assert.equal((await result.json()).mustChangePassword, false);
  assert.deepEqual(f.calls.auth, ['fixture-access']);
  assert.equal(f.calls.passwords[0].init.method, 'PUT');
  assert.equal(f.calls.passwords[0].init.headers.Authorization, 'Bearer fixture-access');
  assert.equal(f.calls.passwords[0].init.headers.apikey, 'fixture-public-key');
  assert.equal(f.calls.completed[0].args.target_user_id, f.userId);
});

test('Auth rechazado o sin conexión no levanta el cambio obligatorio', async () => {
  for (const options of [{ authStatus: 422 }, { offline: true }]) {
    const f = await fixture(options);
    const result = await f.request();
    assert.equal(result.status, options.offline ? 503 : 422);
    assert.equal(f.calls.completed.length, 0);
    assert.ok(!(await result.text()).includes('fixture-new-password'));
  }
});

test('un fallo de perfil después de Auth no se presenta como éxito', async () => {
  const f = await fixture({ profileFailure: true });
  const result = await f.request();
  assert.equal(result.status, 500);
  assert.equal((await result.json()).error, 'PROFILE_UPDATE_FAILED');
});

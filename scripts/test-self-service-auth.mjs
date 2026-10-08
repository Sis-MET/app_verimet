import { readFile } from 'node:fs/promises';
import ts from 'typescript';
import vm from 'node:vm';
import assert from 'node:assert/strict';
import test from 'node:test';

const stripTypeScriptTypes = (source) => ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.ESNext, target: ts.ScriptTarget.ES2022 },
}).outputText;

const keys = { SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-server-key', SUPABASE_ANON_KEY: 'fixture-public-key' };
const ownerId = '00000000-0000-4000-8000-000000000001';
const memberId = '00000000-0000-4000-8000-000000000002';
const requestId = '00000000-0000-4000-8000-0000000000aa';
const session = { access_token: 'fixture-access', refresh_token: 'fixture-refresh', expires_in: 900, token_type: 'bearer' };

// Evalúa el handler real con Supabase sustituido. `options` decide qué
// responde cada llamada; `calls` registra lo que el handler pidió.
async function fixture(name, options = {}) {
  let handler;
  const calls = { rpc: [], createUser: [], updateUser: [], otp: [], verify: [], getUser: [], errors: [] };
  const result = (key, fallback) => (key in options ? options[key] : fallback);
  // Lo creado dentro del contexto vm tiene otro Object.prototype.
  const plain = (value) => JSON.parse(JSON.stringify(value));
  const admin = {
    async rpc(fn, args) {
      calls.rpc.push({ fn, args: plain(args) });
      const answer = options.rpc?.[fn]?.(args, calls);
      return answer ?? { data: null, error: null };
    },
    auth: { admin: {
      async createUser(input) { calls.createUser.push(plain(input)); return result('createUser', { data: { user: { id: input.id ?? ownerId } }, error: null }); },
      async updateUserById(id, input) { calls.updateUser.push({ id, input: plain(input) }); return result('updateUser', { data: {}, error: null }); },
      async getUserById(id) { calls.getUser.push(id); return result('getUserById', { data: { user: null }, error: { status: 404 } }); },
    } },
  };
  const user = {
    from() { return { select() { return this; }, eq() { return this; },
      async single() { return { data: { id: options.userId ?? ownerId, usuario: 'ana@acme.example', nombre: 'Ana', rol: 'cliente_jefe_calidad', cliente_id: 'c1', activo: true, debe_cambiar_password: false }, error: null }; } }; },
    async rpc() { return { data: { allowed: true, planName: 'Gratuito' }, error: null }; },
    auth: { async getUser(token) { calls.getUser.push(token); return options.invalidToken ? { data: { user: null }, error: { status: 401 } } : { data: { user: { id: ownerId } }, error: null }; } },
  };
  const publicAuth = { auth: {
    async signInWithOtp(input) { calls.otp.push(plain(input)); return result('otp', { data: {}, error: null }); },
    async verifyOtp(input) { calls.verify.push(plain(input)); return result('verify', { data: { session, user: { id: options.userId ?? ownerId } }, error: null }); },
  } };
  const context = vm.createContext({
    Request, Response, Headers, AbortSignal, crypto, btoa, Uint8Array, String,
    console: { error: (...args) => calls.errors.push(args.join(' ')) },
    Deno: { env: { get: (key) => keys[key] }, serve(fn) { handler = fn; } },
  });
  const supabase = new vm.SyntheticModule(['createClient'], function () {
    this.setExport('createClient', (_url, key, config) =>
      key === keys.SUPABASE_SERVICE_ROLE_KEY ? admin : config?.global?.headers?.Authorization ? user : publicAuth);
  }, { context });
  const load = async (path) => new vm.SourceTextModule(stripTypeScriptTypes(await readFile(new URL(path, import.meta.url), 'utf8')), { context });
  const modules = {
    http: await load('../supabase/functions/_shared/http.ts'),
    session: await load('../supabase/functions/_shared/session.ts'),
  };
  const main = await load(`../supabase/functions/${name}/index.ts`);
  const link = (specifier) => specifier === 'supabase' ? supabase
    : specifier.endsWith('session.ts') ? modules.session : modules.http;
  await main.link(link);
  await main.evaluate();
  return {
    calls,
    request: (body, headers = {}) => handler(new Request(`https://fixture.invalid/functions/v1/${name}`, {
      method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body),
    })),
  };
}

const company = { email: ' Ana@Acme.Example ', company: 'Acme  Alimentos', name: 'Ana Pérez', plantName: '', phone: '', city: 'Santa Cruz',
  country: 'Bolivia', acceptTerms: true, termsVersion: 'ivmet-terms-v1' };
const pending = { rpc: { ivmet_signup_status: () => ({ data: { registered: false, authUserId: null }, error: null }) } };

test('el alta envía un código solo a un correo nuevo, sin abrir los registros públicos', async () => {
  let f = await fixture('ivmet-signup', pending);
  assert.equal((await f.request({ ...company, action: 'start', email: 'ivmet.x@users.ivmet.invalid' })).status, 422);
  assert.equal((await f.request({ ...company, action: 'start', acceptTerms: false })).status, 422);
  assert.equal((await f.request({ ...company, action: 'start', company: 'A' })).status, 422);
  assert.equal(f.calls.rpc.length, 0, 'valida antes de consultar Supabase');

  const response = await f.request({ ...company, action: 'start' });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { sent: true });
  assert.equal(f.calls.createUser[0].email, 'ana@acme.example');
  assert.equal(f.calls.createUser[0].email_confirm, true);
  assert.ok(f.calls.createUser[0].password.length >= 40, 'contraseña de relleno que nadie conoce');
  assert.deepEqual(f.calls.otp[0], { email: 'ana@acme.example', options: { shouldCreateUser: false } });

  f = await fixture('ivmet-signup', { rpc: { ivmet_signup_status: () => ({ data: { registered: false, authUserId: ownerId }, error: null }) } });
  await f.request({ ...company, action: 'start' });
  assert.equal(f.calls.createUser.length, 0, 'un alta a medias reutiliza su cuenta');
  assert.equal(f.calls.otp.length, 1);

  f = await fixture('ivmet-signup', { rpc: { ivmet_signup_status: () => ({ data: { registered: true }, error: null }) } });
  const taken = await f.request({ ...company, action: 'start' });
  assert.equal(taken.status, 409);
  assert.equal((await taken.json()).error, 'EMAIL_ALREADY_REGISTERED');
  assert.equal(f.calls.otp.length, 0);

  f = await fixture('ivmet-signup', { ...pending, otp: { data: {}, error: { status: 429 } } });
  const limited = await f.request({ ...company, action: 'start' });
  assert.equal(limited.status, 429);
  assert.equal((await limited.json()).error, 'CODE_RATE_LIMITED');
});

test('completar verifica el código, fija la contraseña, crea la empresa y abre la sesión', async () => {
  let f = await fixture('ivmet-signup', pending);
  assert.equal((await f.request({ ...company, action: 'complete', code: '12', password: 'una-clave-larga-1' })).status, 422);
  assert.equal((await f.request({ ...company, action: 'complete', code: '123456', password: 'corta' })).status, 422);
  assert.equal(f.calls.verify.length, 0);

  f = await fixture('ivmet-signup', { ...pending, verify: { data: { session: null, user: null }, error: { status: 403 } } });
  const wrong = await f.request({ ...company, action: 'complete', code: '123456', password: 'una-clave-larga-1' });
  assert.equal(wrong.status, 422);
  assert.equal((await wrong.json()).error, 'INVALID_CODE');
  assert.equal(f.calls.updateUser.length, 0);

  f = await fixture('ivmet-signup', { rpc: { ...pending.rpc, ivmet_signup_complete: () => ({ data: { clientId: 'c1' }, error: null }) } });
  const done = await f.request({ ...company, action: 'complete', code: '123456', password: 'una-clave-larga-1' });
  assert.equal(done.status, 200);
  const body = await done.json();
  assert.equal(body.accessToken, 'fixture-access');
  assert.equal(body.user.username, 'ana@acme.example');
  assert.equal(body.access.planName, 'Gratuito');
  assert.deepEqual(f.calls.verify[0], { email: 'ana@acme.example', token: '123456', type: 'email' });
  assert.equal(f.calls.updateUser[0].input.password, 'una-clave-larga-1');
  const signup = f.calls.rpc.find(c => c.fn === 'ivmet_signup_complete').args;
  assert.equal(signup.target_user, ownerId);
  assert.deepEqual(signup.data, { company: 'Acme Alimentos', name: 'Ana Pérez', plantName: '', phone: '', city: 'Santa Cruz',
    country: 'Bolivia', email: 'ana@acme.example', acceptTerms: true, termsVersion: 'ivmet-terms-v1' });
  assert.ok(!JSON.stringify(signup).includes('una-clave-larga-1'), 'la contraseña no viaja a la base');

  f = await fixture('ivmet-signup', { rpc: { ...pending.rpc, ivmet_signup_complete: () => ({ data: null, error: { message: 'EMAIL_ALREADY_REGISTERED' } }) } });
  const raced = await f.request({ ...company, action: 'complete', code: '123456', password: 'una-clave-larga-1' });
  assert.equal(raced.status, 409);
  f = await fixture('ivmet-signup', { rpc: { ...pending.rpc, ivmet_signup_complete: () => ({ data: null, error: { message: 'relation x does not exist' } }) } });
  const broken = await f.request({ ...company, action: 'complete', code: '123456', password: 'una-clave-larga-1' });
  assert.equal(broken.status, 503);
  assert.equal((await broken.json()).error, 'AUTH_UNAVAILABLE', 'no expone errores internos');
});

test('recuperar la contraseña no revela cuentas y solo cambia la del código', async () => {
  const known = { rpc: { ivmet_password_reset_target: () => ({ data: ownerId, error: null }) } };
  let f = await fixture('ivmet-password-reset', { rpc: { ivmet_password_reset_target: () => ({ data: null, error: null }) } });
  const unknown = await f.request({ action: 'start', email: 'nadie@acme.example' });
  assert.deepEqual(await unknown.json(), { sent: true });
  assert.equal(f.calls.otp.length, 0);
  assert.equal((await f.request({ action: 'complete', email: 'nadie@acme.example', code: '123456', password: 'una-clave-larga-1' })).status, 422);

  f = await fixture('ivmet-password-reset', known);
  assert.deepEqual(await (await f.request({ action: 'start', email: 'ana@acme.example' })).json(), { sent: true });
  assert.equal(f.calls.otp.length, 1);

  f = await fixture('ivmet-password-reset', { ...known, userId: memberId });
  assert.equal((await f.request({ action: 'complete', email: 'ana@acme.example', code: '123456', password: 'una-clave-larga-1' })).status, 422);
  assert.equal(f.calls.updateUser.length, 0, 'el código de otra cuenta no cambia nada');

  f = await fixture('ivmet-password-reset', known);
  const done = await f.request({ action: 'complete', email: 'ana@acme.example', code: '123456', password: 'una-clave-larga-1' });
  assert.equal(done.status, 200);
  assert.equal((await done.json()).accessToken, 'fixture-access');
  assert.deepEqual(f.calls.updateUser[0], { id: ownerId, input: { password: 'una-clave-larga-1' } });
  assert.ok(f.calls.rpc.some(c => c.fn === 'complete_ivmet_password_change' && c.args.target_user_id === ownerId));
});

test('el jefe crea una cuenta reservada en Auth y la recupera al reintentar', async () => {
  const member = { action: 'create', requestId, username: 'operador.uno', name: 'Operador', role: 'cliente_operador',
    plantIds: ['p1'], password: 'temporal-12345' };
  const reserve = { id: memberId, email: `ivmet.${memberId}@users.ivmet.invalid` };
  const rpc = { ivmet_team_account: (args) => ({ data: args.action === 'reserve' ? reserve : { id: memberId }, error: null }) };
  let f = await fixture('ivmet-team-account', { rpc });
  assert.equal((await f.request(member)).status, 401);
  assert.equal((await f.request({ ...member, password: 'corta' }, { Authorization: 'Bearer t' })).status, 422);
  assert.equal((await f.request({ ...member, requestId: 'x' }, { Authorization: 'Bearer t' })).status, 400);

  const created = await f.request(member, { Authorization: 'Bearer fixture-access' });
  assert.equal(created.status, 200);
  assert.deepEqual(await created.json(), { id: memberId });
  assert.deepEqual(f.calls.rpc.map(c => [c.args.action, c.args.actor, c.args.request_id]),
    [['reserve', ownerId, requestId], ['create', ownerId, requestId]]);
  assert.ok(!JSON.stringify(f.calls.rpc).includes('temporal-12345'), 'la contraseña no viaja a la base');
  assert.deepEqual(f.calls.createUser[0], { id: memberId, email: reserve.email, password: 'temporal-12345', email_confirm: true,
    app_metadata: { ivmet_request: requestId } });

  f = await fixture('ivmet-team-account', { rpc, getUserById: { data: { user: { email: reserve.email, app_metadata: { ivmet_request: requestId } } }, error: null } });
  assert.equal((await f.request(member, { Authorization: 'Bearer fixture-access' })).status, 200);
  assert.equal(f.calls.createUser.length, 0, 'el reintento encuentra la cuenta ya creada');

  f = await fixture('ivmet-team-account', { rpc, getUserById: { data: { user: { email: reserve.email, app_metadata: { ivmet_request: 'otra' } } }, error: null } });
  assert.equal((await f.request(member, { Authorization: 'Bearer fixture-access' })).status, 409);

  f = await fixture('ivmet-team-account', { rpc: { ivmet_team_account: () => ({ data: null, error: { message: 'PLAN_LIMIT_USERS' } }) } });
  const full = await f.request(member, { Authorization: 'Bearer fixture-access' });
  assert.equal(full.status, 409);
  assert.equal((await full.json()).error, 'PLAN_LIMIT_USERS');
  assert.equal(f.calls.createUser.length, 0);
});

test('restablecer exige el cambio antes de tocar Auth', async () => {
  const f = await fixture('ivmet-team-account', { rpc: { ivmet_team_account: () => ({ data: { id: memberId }, error: null }) } });
  const done = await f.request({ action: 'reset', requestId, userId: memberId, password: 'temporal-12345' }, { Authorization: 'Bearer fixture-access' });
  assert.equal(done.status, 200);
  assert.equal(f.calls.rpc[0].args.action, 'reset');
  assert.deepEqual(f.calls.updateUser[0], { id: memberId, input: { password: 'temporal-12345' } });
});

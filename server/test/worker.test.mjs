import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { createWorker, digest, modelDecision, validateMatch } from '../src/worker.ts';

const source = { id: '00000000-0000-0000-0000-000000000001', name: 'בייצים' };
const candidate = { id: '00000000-0000-0000-0000-000000000002', name: 'ביצים' };
const input = { source, candidates: [candidate] };
const adminKey = 'a'.repeat(64);
function response(choice = candidate.id, probabilities = { [candidate.id]: .995, none: .003, uncertain: .002 }) {
  return { answers: { match: { type: 'choice', choice, probabilities, confidence: .99 } } };
}
function database() {
  const sqlite = new DatabaseSync(':memory:');
  sqlite.exec(readFileSync(new URL('../migrations/0001_access.sql', import.meta.url), 'utf8'));
  return { prepare(sql) {
    let values = [];
    const statement = {
      bind(...bound) { values = bound; return statement; },
      async first() { return sqlite.prepare(sql).get(...values) ?? null; },
      async run() { return sqlite.prepare(sql).run(...values); }
    };
    return statement;
  } };
}
function req(path, value, token) {
  return new Request('https://unit.workers.dev' + path, { method: 'POST',
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(value) });
}
async function setup(limit = '40') {
  let calls = 0;
  const worker = createWorker(async (url, options) => {
    calls++;
    assert.equal(url, 'https://api.inceptionlabs.ai/v1/decisions');
    const sent = JSON.parse(options.body);
    assert.deepEqual(sent.state, input);
    assert.equal(sent.model, 'mercury-decide');
    return Response.json(response());
  });
  const env = { DB: database(), ADMIN_KEY: adminKey, INCEPTION_API_KEY: 'provider-secret',
    DAILY_DEVICE_LIMIT: limit, AUTO_LINK_ENABLED: 'true' };
  const invite = await (await worker.fetch(req('/admin/invites', {}, adminKey), env)).json();
  const enrollment = await worker.fetch(req('/v1/enroll', { code: invite.code }), env);
  assert.equal(enrollment.status, 201);
  const device = await enrollment.json();
  return { worker, env, invite, device, calls: () => calls };
}

test('one-time pairing, authenticated matching, and revocation', async () => {
  const s = await setup();
  assert.equal((await s.worker.fetch(req('/v1/enroll', { code: s.invite.code }), s.env)).status, 401);
  assert.equal((await s.worker.fetch(req('/v1/match', input), s.env)).status, 401);
  const reply = await s.worker.fetch(req('/v1/match', input, s.device.token), s.env);
  assert.equal(reply.status, 200);
  const result = await reply.json();
  assert.equal(result.decision, 'same');
  assert.equal(result.targetID, candidate.id);
  assert.equal(result.learningEnabled, true);
  assert.equal(JSON.stringify(result).includes('provider-secret'), false);
  assert.equal(s.calls(), 1);
  await s.worker.fetch(req('/admin/revoke', { deviceID: s.device.deviceID }, adminKey), s.env);
  assert.equal((await s.worker.fetch(req('/v1/match', input, s.device.token), s.env)).status, 401);
  assert.equal(s.calls(), 1);
});

test('concurrent requests cannot exceed the persistent daily cap', async () => {
  const s = await setup('1');
  const replies = await Promise.all([1, 2, 3].map(() => s.worker.fetch(req('/v1/match', input, s.device.token), s.env)));
  assert.deepEqual(replies.map(r => r.status).sort(), [200, 429, 429]);
  assert.equal(s.calls(), 1);
});

test('expired invite is not redeemed; unknown credentials never reach Mercury', async () => {
  const s = await setup();
  const code = 'b'.repeat(64);
  await s.env.DB.prepare('INSERT INTO invites(code_hash,expires_at) VALUES (?,?)').bind(await digest(code), 1).run();
  assert.equal((await s.worker.fetch(req('/v1/enroll', { code }), s.env)).status, 401);
  assert.equal((await s.worker.fetch(req('/v1/match', input, code), s.env)).status, 401);
  assert.equal(s.calls(), 0);
});

test('reject arbitrary prompts, duplicate IDs, oversized bodies and too many candidates', async () => {
  assert.throws(() => validateMatch({ ...input, questions: { arbitrary: true } }));
  assert.throws(() => validateMatch({ source, candidates: [source] }));
  assert.throws(() => validateMatch({ source, candidates: Array(9).fill(candidate) }));
  const s = await setup();
  const reply = await s.worker.fetch(req('/v1/match', { source: { ...source, name: 'x'.repeat(9000) }, candidates: [candidate] }, s.device.token), s.env);
  assert.equal(reply.status, 413);
  assert.equal(s.calls(), 0);
});

test('uncertainty and conflicting units never become an accepted identity', () => {
  const uncertain = modelDecision(response('uncertain', { [candidate.id]: .2, none: .1, uncertain: .7 }), input, 'mercury-decide', true);
  assert.equal(uncertain.decision, 'uncertain');
  const units = { source: { ...source, unit: 'ק״ג' }, candidates: [{ ...candidate, unit: 'חבילות' }] };
  assert.equal(modelDecision(response(), units, 'mercury-decide', true).decision, 'uncertain');
  assert.throws(() => modelDecision(response('invented'), input, 'mercury-decide', true));
  assert.throws(() => modelDecision(response(candidate.id, { [candidate.id]: .99 }), input, 'mercury-decide', true));
  assert.equal(modelDecision(response(), input, 'mercury-decide', false).learningEnabled, false);
});

test('provider failures reveal no upstream body and do not fabricate a match', async () => {
  const s = await setup();
  const worker = createWorker(async () => new Response('private upstream data', { status: 500 }));
  const reply = await worker.fetch(req('/v1/match', input, s.device.token), s.env);
  assert.equal(reply.status, 502);
  assert.deepEqual(await reply.json(), { error: 'provider_unavailable' });
});

import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { spawn } from 'node:child_process';

const root = resolve(import.meta.dirname, '..');
const migrationsDir = resolve(root, 'supabase', 'migrations');
const workflowPath = resolve(root, '.github', 'workflows', 'supabase-validate.yml');
const packagePath = resolve(root, 'package.json');
const pgTapPath = resolve(root, 'supabase', 'tests', 'v43a2_consultation_lifecycle_test.sql');
const migrationFiles = readdirSync(migrationsDir)
  .filter(file => /^\d{14}_consultation_lifecycle_lease_v43\.sql$/.test(file));
const migrationPath = migrationFiles.length === 1
  ? resolve(migrationsDir, migrationFiles[0])
  : null;
const migration = migrationPath && existsSync(migrationPath)
  ? readFileSync(migrationPath, 'utf8')
  : '';
const workflow = readFileSync(workflowPath, 'utf8');
const packageJson = JSON.parse(readFileSync(packagePath, 'utf8'));
const pgTap = existsSync(pgTapPath) ? readFileSync(pgTapPath, 'utf8') : '';

const rpcSignatures = [
  ['get_consultation_lifecycle_constants_v43', []],
  ['create_my_consultation_v43', ['uuid', 'text', 'uuid', 'timestamp with time zone', 'text', 'smallint']],
  ['reschedule_my_consultation_v43', ['uuid', 'integer', 'timestamp with time zone', 'text', 'smallint']],
  ['acquire_my_consultation_lease_v43', ['uuid', 'text', 'text']],
  ['heartbeat_my_consultation_lease_v43', ['uuid', 'text', 'bigint']],
  ['takeover_my_consultation_lease_v43', ['uuid', 'text', 'text', 'bigint']],
  ['start_my_consultation_v43', ['uuid', 'text', 'bigint', 'bigint']],
  ['autosave_my_consultation_v43', ['uuid', 'text', 'bigint', 'bigint', 'uuid', 'jsonb']],
  ['pause_my_consultation_v43', ['uuid', 'text', 'bigint', 'bigint']],
  ['resume_my_consultation_v43', ['uuid', 'text', 'bigint']],
  ['cancel_my_consultation_v43', ['uuid', 'text', 'bigint', 'bigint', 'text']],
  ['cancel_my_finalized_consultation_v43', ['uuid', 'text']],
  ['mark_my_consultation_no_show_v43', ['uuid', 'text', 'bigint', 'bigint']],
  ['archive_my_consultation_v43', ['uuid', 'bigint']],
  ['discard_my_consultation_v43', ['uuid', 'text', 'bigint', 'bigint', 'text']],
  ['cleanup_my_revoked_consultation_v43', ['uuid', 'bigint']],
  ['finalize_my_consultation_v43', ['uuid', 'text', 'bigint', 'bigint']]
];

function functionDefinition(source, name) {
  return source.match(new RegExp(
    `create\\s+or\\s+replace\\s+function\\s+public\\.${name}\\s*\\([\\s\\S]*?\\n\\$\\$;`,
    'i'
  ))?.[0] || '';
}

function normalizedArgumentTypes(definition) {
  const argumentsSource = definition.match(/function\s+public\.[^(]+\(([\s\S]*?)\)\s*returns/i)?.[1] || '';
  if (!argumentsSource.trim()) return [];
  return argumentsSource.split(',').map(argument => argument
    .trim()
    .split(/\s+default\s+/i)[0]
    .trim()
    .split(/\s+/)
    .slice(1)
    .join(' '));
}

function runStaticContract() {
  const results = [];
  const check = (name, test) => {
    try {
      test();
      results.push({ name, passed: true });
    } catch (error) {
      results.push({ name, passed: false, error: error?.message || String(error) });
    }
  };

  check('A.2C migration exists exactly once with a complete transaction', () => {
    assert.equal(
      migrationFiles.length,
      1,
      `expected one *_consultation_lifecycle_lease_v43.sql migration; found: ${migrationFiles.join(', ') || 'none'}`
    );
    assert.match(basename(migrationPath), /^\d{14}_consultation_lifecycle_lease_v43\.sql$/);
    assert.match(migration, /^begin;[\s\S]*commit;\s*$/i);
  });

  check('approved editing constants are executable database contracts', () => {
    const constants = functionDefinition(migration, 'get_consultation_lifecycle_constants_v43');
    assert.match(constants, /'autosaveDebounceMs'\s*,\s*1200/i);
    assert.match(constants, /'leaseHeartbeatSeconds'\s*,\s*20/i);
    assert.match(constants, /'leaseExpirySeconds'\s*,\s*60/i);
    assert.match(constants, /'deviceLabelMaxCodePoints'\s*,\s*80/i);
    assert.match(constants, /security\s+definer/i);
    assert.match(constants, /set\s+search_path\s*=\s*''/i);
  });

  check('lease and save-receipt state are server controlled and content free', () => {
    for (const table of ['consultation_edit_leases', 'consultation_save_receipts']) {
      assert.match(migration, new RegExp(`create\\s+table\\s+public\\.${table}`, 'i'));
      assert.match(migration, new RegExp(`alter\\s+table\\s+public\\.${table}\\s+enable\\s+row\\s+level\\s+security`, 'i'));
      assert.match(migration, new RegExp(`alter\\s+table\\s+public\\.${table}\\s+force\\s+row\\s+level\\s+security`, 'i'));
      assert.match(migration, new RegExp(`revoke\\s+all(?:\\s+privileges)?\\s+on\\s+table\\s+public\\.${table}[\\s\\S]*?authenticated`, 'i'));
    }
    const leaseTable = migration.match(/create\s+table\s+public\.consultation_edit_leases\s*\([\s\S]*?\n\);/i)?.[0] || '';
    assert.match(leaseTable, /token_verifier\s+bytea/i);
    assert.doesNotMatch(leaseTable, /\braw_token\b|\blease_token\b/i);
    const receiptTable = migration.match(/create\s+table\s+public\.consultation_save_receipts\s*\([\s\S]*?\n\);/i)?.[0] || '';
    assert.doesNotMatch(receiptTable, /payload|patch|value|content|body/i);
  });

  check('public lifecycle RPC signatures contain no caller identity', () => {
    for (const [name, expectedTypes] of rpcSignatures) {
      const definition = functionDefinition(migration, name);
      assert.ok(definition, `${name} is absent`);
      assert.deepEqual(normalizedArgumentTypes(definition), expectedTypes, `${name} signature changed`);
      assert.match(definition, /security\s+definer/i, `${name} must be SECURITY DEFINER`);
      assert.match(definition, /set\s+search_path\s*=\s*''/i, `${name} must have empty search_path`);
      assert.doesNotMatch(
        definition.match(/function\s+public\.[^(]+\(([\s\S]*?)\)\s*returns/i)?.[1] || '',
        /(?:author|professional|student|client|holder|actor)_user_id/i,
        `${name} trusts caller identity`
      );
    }
  });

  check('authorization, provenance and lock ordering are centralized', () => {
    assert.match(migration, /assert_locked_consultation_write_entitlement_v43/i);
    assert.match(migration, /assert_consultation_relationship_subject_binding_v43/i);
    assert.match(migration, /subject\.account_user_id\s*=\s*relationship\.student_user_id/i);
    assert.match(migration, /relationship\.professional_user_id\s*=\s*consultation\.author_user_id/i);
    assert.match(migration, /relationship\.professional_type\s*=\s*consultation\.professional_type/i);
    assert.match(migration, /relationship\.organization_id\s+is\s+not\s+distinct\s+from\s+consultation\.organization_id/i);
    assert.match(pgTap, /relationship\s*(?:->|â†’|vs)\s*consultation\s*(?:->|â†’|vs)\s*lease/i);
  });

  check('stable bounded errors and exact-original preconditions are contractual', () => {
    for (const code of [
      'consultation_unauthorized',
      'consultation_invalid_lifecycle_state',
      'consultation_stale_lease',
      'consultation_expired_lease',
      'consultation_stale_revision',
      'consultation_lease_taken_over',
      'consultation_validation_failed',
      'consultation_relationship_revoked'
    ]) {
      assert.match(migration, new RegExp(code, 'i'), `${code} is absent`);
      assert.match(pgTap, new RegExp(code, 'i'), `${code} lacks a database regression`);
    }
    assert.match(migration, /expectedOriginalValue/);
    assert.match(pgTap, /expectedOriginalValue/);
  });

  check('relationship revocation extends the A.2B trigger atomically', () => {
    const hook = migration.match(/create\s+or\s+replace\s+function\s+private\.protect_consultation_relationship_authorization_v43\([\s\S]*?\n\$\$;/i)?.[0] || '';
    assert.match(hook, /old\.status\s*=\s*'active'/i);
    assert.match(hook, /new\.status\s*<>\s*'active'/i);
    assert.match(hook, /consultation_edit_leases/i);
    assert.match(hook, /professional_consultations/i);
    assert.match(hook, /relationship_revoked/i);
    assert.doesNotMatch(hook, /delete\s+from\s+public\.professional_consultations/i);
  });

  check('finalization reuses the approved canonicalizer and remains atomic', () => {
    const finalize = functionDefinition(migration, 'finalize_my_consultation_v43');
    assert.match(finalize, /private\.forja_canonical_json_v1_bytes|consultation_final_snapshots/i);
    assert.match(finalize, /consultation_final_snapshots/i);
    assert.doesNotMatch(finalize, /jsonb\s*::\s*text|canonical_payload\s*::\s*text/i);
  });

  check('source and database tests cover lifecycle, revocation, discard and six races', () => {
    assert.ok(pgTap.length > 20_000, 'focused lifecycle pgTAP suite is unexpectedly small');
    for (const contract of [
      'scheduled -> in_progress',
      'in_progress -> paused',
      'paused -> in_progress',
      'finalized -> archived',
      'relationship_revoked',
      'expectedOriginalValue',
      'consultation_subjects.account_user_id',
      'takeover',
      'discard',
      'finalize'
    ]) assert.match(pgTap, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));
    for (const race of [
      'editor A vs editor B save race',
      'save vs explicit takeover',
      'save vs discard',
      'heartbeat vs takeover',
      'relationship revocation vs save',
      'finalization vs save'
    ]) assert.match(readFileSync(import.meta.filename, 'utf8'), new RegExp(race, 'i'));
  });

  check('CI triggers and focused/full pgTAP enforcement are exact', () => {
    const lines = workflow.split(/\r?\n/).map(line => line.trim());
    assert.ok(lines.includes('- "scripts/test-consultation-authorization.mjs"'));
    assert.ok(lines.includes('- "scripts/test-consultation-lifecycle.mjs"'));
    assert.equal(lines.filter(line => line === 'run: pnpm exec supabase test db --local supabase/tests/v43a2_consultation_rls_test.sql').length, 1);
    assert.equal(lines.filter(line => line === 'run: pnpm exec supabase test db --local supabase/tests/v43a2_consultation_lifecycle_test.sql').length, 1);
    assert.equal(lines.filter(line => line === 'run: pnpm exec supabase test db').length, 1);
    for (const id of [
      'consultation_lifecycle_source',
      'consultation_lifecycle_pgtap',
      'consultation_lifecycle_races',
      'complete_pgtap'
    ]) assert.match(workflow, new RegExp(`steps\\.${id}\\.outcome`));
    assert.match(workflow, /actions\/upload-artifact@v4/);
    assert.match(workflow, /path: \$\{\{ runner\.temp \}\}\/database\.types\.ts/);
    assert.match(workflow, /retention-days: 1/);
  });

  check('package exposes focused lifecycle commands', () => {
    assert.equal(packageJson.scripts['test:consultation-lifecycle'], 'node scripts/test-consultation-lifecycle.mjs');
    assert.equal(
      packageJson.scripts['test:consultation-lifecycle-db'],
      'supabase test db --local supabase/tests/v43a2_consultation_lifecycle_test.sql'
    );
  });

  check('A.2C adds no frontend, offline, scheduler, remote or artifact path', () => {
    assert.doesNotMatch(migration, /localStorage|indexedDB|SyncQueue/i);
    assert.doesNotMatch(migration, /pg_cron|cron\.|schedule\s*\(/i);
    assert.doesNotMatch(migration, /storage\.|attachment|publication/i);
    assert.doesNotMatch(workflow, /supabase\s+(?:link|db push)|--linked/i);
    assert.match(workflow, /V4\.3A\.2C TEMPORARY/);
  });

  for (const result of results) {
    console.log(`${result.passed ? 'PASS' : 'FAIL'} ${result.name}${result.error ? ` â€” ${result.error}` : ''}`);
  }
  const failures = results.filter(result => !result.passed);
  console.log(`\n${results.length - failures.length}/${results.length} lifecycle source checks passed.`);
  if (failures.length) process.exitCode = 1;
}

function psql(container, sql) {
  return new Promise(resolvePromise => {
    const child = spawn('docker', [
      'exec', '-i', container,
      'psql', '-X', '-qAt', '-v', 'ON_ERROR_STOP=1', '-U', 'postgres', '-d', 'postgres'
    ], { stdio: ['pipe', 'pipe', 'pipe'] });
    let stdout = '';
    let stderr = '';
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('close', code => resolvePromise({ code, stdout: stdout.trim(), stderr: stderr.trim() }));
    child.stdin.end(sql);
  });
}

function actorSql(actorId, statement) {
  return `begin;
set local role authenticated;
select set_config('request.jwt.claim.sub', '${actorId}', true);
${statement}
commit;`;
}

function assertResultOk(result, label) {
  assert.equal(result.code, 0, `${label} failed: ${result.stderr || result.stdout}`);
}

async function exactlyOneCommits(name, first, second, acceptedFailurePattern) {
  const results = await Promise.all([first(), second()]);
  const successes = results.filter(result => result.code === 0);
  assert.equal(successes.length, 1, `${name}: expected one commit, got ${successes.length}; ${JSON.stringify(results)}`);
  const failure = results.find(result => result.code !== 0);
  assert.match(`${failure.stderr}\n${failure.stdout}`, acceptedFailurePattern, `${name}: unexpected losing outcome`);
  console.log(`PASS ${name}`);
  return results;
}

async function runDatabaseRaces() {
  const container = process.env.FORJA_A2C_DB_CONTAINER;
  assert.ok(container, 'FORJA_A2C_DB_CONTAINER is required for --database-races');
  const author = '45000000-0000-0000-0000-000000000001';
  const clients = Array.from({ length: 6 }, (_, index) => `45000000-0000-0000-0000-${String(101 + index).padStart(12, '0')}`);
  const relationships = Array.from({ length: 6 }, (_, index) => `45100000-0000-0000-0000-${String(index + 1).padStart(12, '0')}`);
  const plan = 'trainer_ci_v43a2c';
  const setup = `begin;
insert into auth.users (id, aud, role, email, created_at, updated_at)
values ('${author}', 'authenticated', 'authenticated', 'a2c-race-author@example.test', now(), now()),
${clients.map((id, index) => `('${id}', 'authenticated', 'authenticated', 'a2c-race-client-${index + 1}@example.test', now(), now())`).join(',\n')};
insert into public.account_plan_catalog (code, account_type, display_name, active_client_limit, is_free, is_active)
values ('${plan}', 'trainer', 'A2C race plan', 20, true, true);
insert into public.user_commercial_accounts (user_id, primary_account_type, plan_code, subscription_status, personal_use_enabled)
values ('${author}', 'trainer', '${plan}', 'active', true);
insert into public.user_account_modes (user_id, mode) values ('${author}', 'trainer');
insert into public.user_identity_details (user_id, birth_date, age_status, age_verified_at)
values ${clients.map(id => `('${id}', date '1990-01-01', 'adult', now())`).join(',\n')};
insert into public.professional_student_relationships
  (id, professional_user_id, student_user_id, professional_type, status, scopes)
values ${relationships.map((id, index) => `('${id}', '${author}', '${clients[index]}', 'trainer', 'active', '{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}')`).join(',\n')};
commit;`;
  assertResultOk(await psql(container, setup), 'race fixture setup');

  const fixtures = [];
  for (let index = 0; index < relationships.length; index += 1) {
    const create = await psql(container, actorSql(author,
      `select public.create_my_consultation_v43('${relationships[index]}', 'initial', null, null, null, null);`
    ));
    assertResultOk(create, `create race consultation ${index + 1}`);
    const consultationId = create.stdout.split(/\r?\n/).filter(Boolean).at(-1);
    const acquire = await psql(container, actorSql(author,
      `select public.acquire_my_consultation_lease_v43('${consultationId}', 'race-${index + 1}', 'edit');`
    ));
    assertResultOk(acquire, `acquire race lease ${index + 1}`);
    const lease = JSON.parse(acquire.stdout.split(/\r?\n/).filter(Boolean).at(-1));
    fixtures.push({ consultationId, relationshipId: relationships[index], ...lease });
  }

  const saveSql = (fixture, correlationId, value) => actorSql(author,
    `select public.autosave_my_consultation_v43('${fixture.consultationId}', '${fixture.leaseToken}', ${fixture.leaseVersion}, 0, '${correlationId}', '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"${value}"}}]'::jsonb);`
  );

  // editor A vs editor B save race
  await exactlyOneCommits(
    'editor A vs editor B save race',
    () => psql(container, saveSql(fixtures[0], '45200000-0000-0000-0000-000000000001', 'A')),
    () => psql(container, saveSql(fixtures[0], '45200000-0000-0000-0000-000000000002', 'B')),
    /consultation_stale_revision/i
  );

  // save vs explicit takeover
  await exactlyOneCommits(
    'save vs explicit takeover',
    () => psql(container, saveSql(fixtures[1], '45200000-0000-0000-0000-000000000003', 'save')),
    () => psql(container, actorSql(author,
      `select public.takeover_my_consultation_lease_v43('${fixtures[1].consultationId}', 'takeover', 'edit', 0);`
    )),
    /consultation_(?:stale_revision|lease_taken_over)/i
  );

  // save vs discard
  await exactlyOneCommits(
    'save vs discard',
    () => psql(container, saveSql(fixtures[2], '45200000-0000-0000-0000-000000000004', 'save')),
    () => psql(container, actorSql(author,
      `select public.discard_my_consultation_v43('${fixtures[2].consultationId}', '${fixtures[2].leaseToken}', ${fixtures[2].leaseVersion}, 0, 'author_discard');`
    )),
    /consultation_(?:stale_revision|stale_lease|unauthorized)/i
  );

  // heartbeat vs takeover
  const heartbeatTakeover = await Promise.all([
    psql(container, actorSql(author,
      `select public.heartbeat_my_consultation_lease_v43('${fixtures[3].consultationId}', '${fixtures[3].leaseToken}', ${fixtures[3].leaseVersion});`
    )),
    psql(container, actorSql(author,
      `select public.takeover_my_consultation_lease_v43('${fixtures[3].consultationId}', 'takeover', 'edit', 0);`
    ))
  ]);
  assert.ok(heartbeatTakeover.some(result => result.code === 0), 'heartbeat vs takeover produced no valid serialized outcome');
  const replay = await psql(container, actorSql(author,
    `select public.heartbeat_my_consultation_lease_v43('${fixtures[3].consultationId}', '${fixtures[3].leaseToken}', ${fixtures[3].leaseVersion});`
  ));
  assert.notEqual(replay.code, 0, 'old heartbeat token remained valid after takeover');
  assert.match(`${replay.stderr}\n${replay.stdout}`, /consultation_lease_taken_over/i);
  console.log('PASS heartbeat vs takeover');

  // relationship revocation vs save
  const revocationResults = await Promise.all([
    psql(container, saveSql(fixtures[4], '45200000-0000-0000-0000-000000000005', 'save')),
    psql(container, `update public.professional_student_relationships set status = 'revoked' where id = '${fixtures[4].relationshipId}';`)
  ]);
  assertResultOk(revocationResults[1], 'relationship revocation');
  const revokedState = await psql(container,
    `select status from public.professional_consultations where id = '${fixtures[4].consultationId}';`
  );
  assertResultOk(revokedState, 'read revoked race state');
  assert.equal(revokedState.stdout, 'cancelled');
  console.log('PASS relationship revocation vs save');

  const started = await psql(container, actorSql(author,
    `select public.start_my_consultation_v43('${fixtures[5].consultationId}', '${fixtures[5].leaseToken}', ${fixtures[5].leaseVersion}, 0);`
  ));
  assertResultOk(started, 'prepare finalization race');
  // finalization vs save
  await exactlyOneCommits(
    'finalization vs save',
    () => psql(container, saveSql(fixtures[5], '45200000-0000-0000-0000-000000000006', 'save')),
    () => psql(container, actorSql(author,
      `select public.finalize_my_consultation_v43('${fixtures[5].consultationId}', '${fixtures[5].leaseToken}', ${fixtures[5].leaseVersion}, 0);`
    )),
    /consultation_(?:stale_revision|stale_lease|invalid_lifecycle_state)/i
  );

  const cleanup = `begin;
set local session_replication_role = replica;
delete from public.consultation_save_receipts where author_user_id = '${author}';
delete from public.consultation_final_snapshots where consultation_id in (${fixtures.map(f => `'${f.consultationId}'`).join(',')});
delete from public.consultation_edit_leases where consultation_id in (${fixtures.map(f => `'${f.consultationId}'`).join(',')});
delete from public.consultation_items where consultation_id in (${fixtures.map(f => `'${f.consultationId}'`).join(',')});
delete from public.consultation_events where consultation_id in (${fixtures.map(f => `'${f.consultationId}'`).join(',')});
delete from public.professional_consultations where id in (${fixtures.map(f => `'${f.consultationId}'`).join(',')});
delete from public.consultation_subjects where account_user_id in (${clients.map(id => `'${id}'`).join(',')});
delete from public.professional_student_relationships where id in (${relationships.map(id => `'${id}'`).join(',')});
delete from public.user_identity_details where user_id in (${clients.map(id => `'${id}'`).join(',')});
delete from public.user_account_modes where user_id = '${author}';
delete from public.user_commercial_accounts where user_id = '${author}';
delete from public.account_plan_catalog where code = '${plan}' and account_type = 'trainer';
delete from auth.users where id in ('${author}', ${clients.map(id => `'${id}'`).join(',')});
commit;`;
  assertResultOk(await psql(container, cleanup), 'race fixture cleanup');
  console.log('6/6 separate-session race scenarios passed.');
}

if (process.argv.includes('--database-races')) {
  await runDatabaseRaces();
} else {
  runStaticContract();
}

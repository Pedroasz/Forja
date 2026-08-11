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
  ['acquire_my_revoked_consultation_cleanup_lease_v43', ['uuid', 'text', 'bigint']],
  ['cleanup_my_revoked_consultation_v43', ['uuid', 'text', 'bigint', 'bigint']],
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
    const authorityLocks = migration.match(/create\s+or\s+replace\s+function\s+private\.lock_consultation_authority_rows_v43\([\s\S]*?\n\$\$;/i)?.[0] || '';
    assert.doesNotMatch(authorityLocks, /for\s+update/i, 'shared authority rows must not serialize unrelated writers');
    assert.match(authorityLocks, /for\s+share/i);
    const entitlement = migration.match(/create\s+or\s+replace\s+function\s+private\.assert_locked_consultation_write_entitlement_v43\([\s\S]*?\n\$\$;/i)?.[0] || '';
    assert.match(entitlement, /professional_student_relationships[\s\S]*?for\s+share/i);
    assert.match(entitlement, /professional_consultations[\s\S]*?for\s+update/i);
  });

  check('cleanup issuance and takeover semantics are capability bounded', () => {
    const acquire = functionDefinition(migration, 'acquire_my_consultation_lease_v43');
    const takeover = functionDefinition(migration, 'takeover_my_consultation_lease_v43');
    assert.match(acquire, /target_purpose\s*=\s*'cleanup'[\s\S]*consultation_validation_failed/i);
    assert.match(takeover, /target_purpose\s*=\s*'cleanup'[\s\S]*consultation_validation_failed/i);
    const issuer = migration.match(/create\s+or\s+replace\s+function\s+private\.issue_consultation_lease_v43\([\s\S]*?\n\$\$;/i)?.[0] || '';
    assert.match(issuer, /target_takeover[\s\S]*not\s+lease_found[\s\S]*consultation_stale_lease/i);
    assert.match(issuer, /target_takeover[\s\S]*invalidated_at\s+is\s+not\s+null[\s\S]*consultation_stale_lease/i);
    assert.match(issuer, /target_takeover[\s\S]*expires_at\s*<=\s*issued_at[\s\S]*consultation_expired_lease/i);
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

  check('source and database tests cover lifecycle, revocation, discard and bounded concurrency', () => {
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
      'a discard lease cannot cross capabilities into autosave',
      'autosave rejects duplicate itemKey entries',
      'finalized -> cancelled -> archived',
      'scope-only revocation does not system-cancel',
      'cleanup lease',
      'finalize'
    ]) assert.match(pgTap, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'));
    for (const race of [
      'editor A vs editor B save race',
      'save vs explicit takeover',
      'save vs discard',
      'heartbeat vs takeover',
      'relationship revocation vs save',
      'finalization vs save',
      'subscription deactivation vs save',
      'organization membership suspension vs save',
      'organization suspension vs save',
      'independent consultations on shared authority rows do not block'
    ]) assert.match(readFileSync(import.meta.filename, 'utf8'), new RegExp(race, 'i'));
    assert.match(readFileSync(import.meta.filename, 'utf8'), /wait_event_type\s*=\s*'Lock'/i);
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
    assert.doesNotMatch(workflow, /actions\/upload-artifact/);
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
    assert.doesNotMatch(workflow, /actions\/upload-artifact/);
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

function actorSql(actorId, statement, applicationName = '') {
  return `begin;
set local statement_timeout = '10s';
set local lock_timeout = '5s';
${applicationName ? `set local application_name = '${applicationName}';` : ''}
set local role authenticated;
select set_config('request.jwt.claim.sub', '${actorId}', true);
${statement}
commit;`;
}

function rootSql(statement, applicationName) {
  return `begin;
set local statement_timeout = '10s';
set local lock_timeout = '5s';
set local application_name = '${applicationName}';
${statement}
commit;`;
}

function assertResultOk(result, label) {
  assert.equal(result.code, 0, `${label} failed: ${result.stderr || result.stdout}`);
}

async function waitForSessionState(container, applicationName, expectedState) {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    const state = await psql(container, `select coalesce((
      select case
        when wait_event = 'PgSleep' then 'sleep'
        when wait_event_type = 'Lock' then 'lock'
        else 'active'
      end
      from pg_catalog.pg_stat_activity
      where application_name = '${applicationName}'
      order by backend_start desc
      limit 1
    ), 'missing');`);
    assertResultOk(state, `inspect ${applicationName}`);
    if (state.stdout === expectedState) return;
    await new Promise(resolvePromise => setTimeout(resolvePromise, 50));
  }
  assert.fail(`${applicationName} never reached ${expectedState}`);
}

async function contendedExactlyOne(container, name, firstSql, secondSql, acceptedFailurePattern) {
  const raceId = name.toLowerCase().replace(/[^a-z0-9]+/g, '-').slice(0, 30);
  const firstApplication = `forja-a2c-${raceId}-first`;
  const secondApplication = `forja-a2c-${raceId}-second`;
  const firstPromise = psql(container, firstSql(firstApplication));
  await waitForSessionState(container, firstApplication, 'sleep');
  const secondPromise = psql(container, secondSql(secondApplication));
  await waitForSessionState(container, secondApplication, 'lock');
  const results = await Promise.all([firstPromise, secondPromise]);
  const successes = results.filter(result => result.code === 0);
  assert.equal(successes.length, 1, `${name}: expected one commit, got ${successes.length}; ${JSON.stringify(results)}`);
  const failure = results.find(result => result.code !== 0);
  assert.match(`${failure.stderr}\n${failure.stdout}`, acceptedFailurePattern, `${name}: unexpected losing outcome`);
  console.log(`PASS ${name} (observed a real blocked lock waiter)`);
  return results;
}

async function aggregateState(container, fixture) {
  const result = await psql(container, `select pg_catalog.json_build_object(
    'consultations',(select count(*) from public.professional_consultations where id='${fixture.consultationId}'),
    'status',(select status from public.professional_consultations where id='${fixture.consultationId}'),
    'revision',(select draft_revision from public.professional_consultations where id='${fixture.consultationId}'),
    'items',(select count(*) from public.consultation_items where consultation_id='${fixture.consultationId}'),
    'receipts',(select count(*) from public.consultation_save_receipts where consultation_id='${fixture.consultationId}'),
    'activeLeases',(select count(*) from public.consultation_edit_leases where consultation_id='${fixture.consultationId}' and invalidated_at is null),
    'snapshots',(select count(*) from public.consultation_final_snapshots where consultation_id='${fixture.consultationId}'),
    'tombstones',(select count(*) from public.consultation_discard_tombstones where discarded_consultation_id='${fixture.consultationId}')
  );`);
  assertResultOk(result, `read aggregate ${fixture.consultationId}`);
  return JSON.parse(result.stdout.split(/\r?\n/).filter(Boolean).at(-1));
}

async function runDatabaseRaces() {
  const container = process.env.FORJA_A2C_DB_CONTAINER;
  assert.ok(container, 'FORJA_A2C_DB_CONTAINER is required for --database-races');
  const author = '45000000-0000-0000-0000-000000000001';
  const clients = Array.from({ length: 9 }, (_, index) => `45000000-0000-0000-0000-${String(101 + index).padStart(12, '0')}`);
  const relationships = Array.from({ length: 9 }, (_, index) => `45100000-0000-0000-0000-${String(index + 1).padStart(12, '0')}`);
  const plan = 'trainer_ci_v43a2c';
  const organization = '45300000-0000-0000-0000-000000000001';
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
insert into public.organizations (id, name, slug, organization_type, owner_user_id, status)
values ('${organization}', 'A2C race organization', 'a2c-race-organization', 'academy', '${author}', 'active');
insert into public.organization_members (organization_id, user_id, role, status)
values ('${organization}', '${author}', 'trainer', 'active');
insert into public.professional_student_relationships
  (id, professional_user_id, student_user_id, professional_type, organization_id, status, scopes)
values ${relationships.map((id, index) => `('${id}', '${author}', '${clients[index]}', 'trainer', ${index >= 6 ? `'${organization}'` : 'null'}, 'active', '{"manage_workout_plan":false,"view_workout_executions":true,"manage_nutrition_plan":false,"view_nutrition_logs":false,"view_evolution":true,"manage_consultations":true,"view_shared_consultation_history":false}')`).join(',\n')};
commit;`;
  assertResultOk(await psql(container, setup), 'race fixture setup');

  const fixtures = [];
  try {
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

  const performThenHold = (statement, applicationName) => actorSql(author, `
${statement}
select pg_catalog.pg_sleep(2);`, applicationName);

  // editor A vs editor B save race
  await contendedExactlyOne(
    container,
    'editor A vs editor B save race',
    applicationName => performThenHold(
      `select public.autosave_my_consultation_v43('${fixtures[0].consultationId}', '${fixtures[0].leaseToken}', ${fixtures[0].leaseVersion}, 0, '45200000-0000-0000-0000-000000000001', '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"A"}}]'::jsonb);`,
      applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[0].consultationId}', '${fixtures[0].leaseToken}', ${fixtures[0].leaseVersion}, 0, '45200000-0000-0000-0000-000000000002', '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"B"}}]'::jsonb);`,
      applicationName),
    /consultation_stale_revision/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[0]), {
    consultations: 1, status: 'scheduled', revision: 1, items: 1,
    receipts: 1, activeLeases: 1, snapshots: 0, tombstones: 0
  }, 'save race left a partial aggregate');

  // save vs explicit takeover
  await contendedExactlyOne(
    container,
    'save vs explicit takeover',
    applicationName => performThenHold(
      `select public.takeover_my_consultation_lease_v43('${fixtures[1].consultationId}', 'takeover', 'edit', 0);`,
      applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[1].consultationId}', '${fixtures[1].leaseToken}', ${fixtures[1].leaseVersion}, 0, '45200000-0000-0000-0000-000000000003', '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"save"}}]'::jsonb);`,
      applicationName),
    /consultation_lease_taken_over/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[1]), {
    consultations: 1, status: 'scheduled', revision: 0, items: 0,
    receipts: 0, activeLeases: 1, snapshots: 0, tombstones: 0
  }, 'takeover race left save content or a receipt');

  // save vs discard
  await contendedExactlyOne(
    container,
    'save vs discard',
    applicationName => performThenHold(
      `select public.discard_my_consultation_v43('${fixtures[2].consultationId}', '${fixtures[2].leaseToken}', ${fixtures[2].leaseVersion}, 0, 'author_discard');`,
      applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[2].consultationId}', '${fixtures[2].leaseToken}', ${fixtures[2].leaseVersion}, 0, '45200000-0000-0000-0000-000000000004', '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"save"}}]'::jsonb);`,
      applicationName),
    /consultation_unauthorized/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[2]), {
    consultations: 0, status: null, revision: null, items: 0,
    receipts: 0, activeLeases: 0, snapshots: 0, tombstones: 1
  }, 'discard race left partial consultation state');

  // heartbeat vs takeover
  await contendedExactlyOne(
    container,
    'heartbeat vs takeover',
    applicationName => performThenHold(
      `select public.takeover_my_consultation_lease_v43('${fixtures[3].consultationId}', 'takeover', 'edit', 0);`,
      applicationName),
    applicationName => actorSql(author,
      `select public.heartbeat_my_consultation_lease_v43('${fixtures[3].consultationId}', '${fixtures[3].leaseToken}', ${fixtures[3].leaseVersion});`,
      applicationName),
    /consultation_lease_taken_over/i
  );
  const replay = await psql(container, actorSql(author,
    `select public.heartbeat_my_consultation_lease_v43('${fixtures[3].consultationId}', '${fixtures[3].leaseToken}', ${fixtures[3].leaseVersion});`
  ));
  assert.notEqual(replay.code, 0, 'old heartbeat token remained valid after takeover');
  assert.match(`${replay.stderr}\n${replay.stdout}`, /consultation_lease_taken_over/i);
  console.log('PASS heartbeat vs takeover');

  // relationship revocation vs save
  await contendedExactlyOne(
    container,
    'relationship revocation vs save',
    applicationName => rootSql(`
update public.professional_student_relationships set status='revoked' where id='${fixtures[4].relationshipId}';
select pg_catalog.pg_sleep(2);`, applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[4].consultationId}', '${fixtures[4].leaseToken}', ${fixtures[4].leaseVersion}, 0, '45200000-0000-0000-0000-000000000005', '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"save"}}]'::jsonb);`,
      applicationName),
    /consultation_relationship_revoked/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[4]), {
    consultations: 1, status: 'cancelled', revision: 0, items: 0,
    receipts: 0, activeLeases: 0, snapshots: 0, tombstones: 0
  }, 'revocation race left content or an active lease');

  const started = await psql(container, actorSql(author,
    `select public.start_my_consultation_v43('${fixtures[5].consultationId}', '${fixtures[5].leaseToken}', ${fixtures[5].leaseVersion}, 0);`
  ));
  assertResultOk(started, 'prepare finalization race');
  // finalization vs save
  await contendedExactlyOne(
    container,
    'finalization vs save',
    applicationName => performThenHold(
      `select public.finalize_my_consultation_v43('${fixtures[5].consultationId}', '${fixtures[5].leaseToken}', ${fixtures[5].leaseVersion}, 0);`,
      applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[5].consultationId}', '${fixtures[5].leaseToken}', ${fixtures[5].leaseVersion}, 0, '45200000-0000-0000-0000-000000000006', '[{"itemKey":"common.goal","itemKind":"text","value":{"text":"save"}}]'::jsonb);`,
      applicationName),
    /consultation_(?:stale_lease|invalid_lifecycle_state)/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[5]), {
    consultations: 1, status: 'finalized', revision: 0, items: 0,
    receipts: 0, activeLeases: 0, snapshots: 1, tombstones: 0
  }, 'finalization race left partial snapshot or save state');

  // Subscription deactivation vs autosave. The writer must visibly wait on
  // the mutable authority row, then reject after the deactivation commits.
  await contendedExactlyOne(
    container,
    'subscription deactivation vs save',
    applicationName => rootSql(`
update public.user_commercial_accounts set subscription_status='inactive' where user_id='${author}';
select pg_catalog.pg_sleep(2);`, applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[6].consultationId}', '${fixtures[6].leaseToken}', ${fixtures[6].leaseVersion}, 0, '45200000-0000-0000-0000-000000000007', '[]'::jsonb);`,
      applicationName),
    /consultation_professional_entitlement_inactive/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[6]), {
    consultations: 1, status: 'scheduled', revision: 0, items: 0,
    receipts: 0, activeLeases: 1, snapshots: 0, tombstones: 0
  }, 'subscription race committed a post-revocation save');
  assertResultOk(await psql(container, `update public.user_commercial_accounts set subscription_status='active' where user_id='${author}';`), 'restore subscription');

  // Independent consultations may share account, plan, organization and
  // membership authority rows. Their heartbeats must remain concurrent.
  {
    const firstApplication = 'forja-a2c-independent-first';
    const firstPromise = psql(container, performThenHold(
      `select public.heartbeat_my_consultation_lease_v43('${fixtures[7].consultationId}', '${fixtures[7].leaseToken}', ${fixtures[7].leaseVersion});`,
      firstApplication));
    await waitForSessionState(container, firstApplication, 'sleep');
    const secondPromise = psql(container, actorSql(author,
      `select public.heartbeat_my_consultation_lease_v43('${fixtures[8].consultationId}', '${fixtures[8].leaseToken}', ${fixtures[8].leaseVersion});`,
      'forja-a2c-independent-second'));
    const completion = await Promise.race([
      secondPromise.then(result => ({ result })),
      new Promise(resolvePromise => setTimeout(() => resolvePromise({ timedOut: true }), 1000))
    ]);
    const firstResult = await firstPromise;
    const secondResult = await secondPromise;
    assertResultOk(firstResult, 'first independent heartbeat');
    assertResultOk(secondResult, 'second independent heartbeat');
    assert.equal(completion.timedOut, undefined, 'independent consultations on shared authority rows do not block');
    console.log('PASS independent consultations on shared authority rows do not block');
  }

  await contendedExactlyOne(
    container,
    'organization membership suspension vs save',
    applicationName => rootSql(`
update public.organization_members set status='suspended' where organization_id='${organization}' and user_id='${author}';
select pg_catalog.pg_sleep(2);`, applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[7].consultationId}', '${fixtures[7].leaseToken}', ${fixtures[7].leaseVersion}, 0, '45200000-0000-0000-0000-000000000008', '[]'::jsonb);`,
      applicationName),
    /consultation_organization_entitlement_inactive/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[7]), {
    consultations: 1, status: 'scheduled', revision: 0, items: 0,
    receipts: 0, activeLeases: 1, snapshots: 0, tombstones: 0
  }, 'membership race committed a post-suspension save');
  assertResultOk(await psql(container, `update public.organization_members set status='active' where organization_id='${organization}' and user_id='${author}';`), 'restore membership');

  await contendedExactlyOne(
    container,
    'organization suspension vs save',
    applicationName => rootSql(`
update public.organizations set status='suspended' where id='${organization}';
select pg_catalog.pg_sleep(2);`, applicationName),
    applicationName => actorSql(author,
      `select public.autosave_my_consultation_v43('${fixtures[8].consultationId}', '${fixtures[8].leaseToken}', ${fixtures[8].leaseVersion}, 0, '45200000-0000-0000-0000-000000000009', '[]'::jsonb);`,
      applicationName),
    /consultation_organization_entitlement_inactive/i
  );
  assert.deepEqual(await aggregateState(container, fixtures[8]), {
    consultations: 1, status: 'scheduled', revision: 0, items: 0,
    receipts: 0, activeLeases: 1, snapshots: 0, tombstones: 0
  }, 'organization race committed a post-suspension save');
  console.log('9/9 separate-session race scenarios passed with observed lock contention.');

  } finally {
  const fixtureIds = fixtures.length
    ? fixtures.map(fixture => `'${fixture.consultationId}'`).join(',')
    : 'null';
  const cleanup = `begin;
set local session_replication_role = replica;
delete from public.consultation_save_receipts where author_user_id = '${author}';
delete from public.consultation_final_snapshots where consultation_id in (${fixtureIds});
delete from public.consultation_edit_leases where consultation_id in (${fixtureIds});
delete from public.consultation_items where consultation_id in (${fixtureIds});
delete from public.consultation_discard_tombstones where discarded_consultation_id in (${fixtureIds});
delete from public.consultation_events where consultation_id in (${fixtureIds});
delete from public.professional_consultations where id in (${fixtureIds});
delete from public.consultation_subjects where account_user_id in (${clients.map(id => `'${id}'`).join(',')});
delete from public.professional_student_relationships where id in (${relationships.map(id => `'${id}'`).join(',')});
delete from public.user_identity_details where user_id in (${clients.map(id => `'${id}'`).join(',')});
delete from public.organization_members where organization_id = '${organization}';
delete from public.organizations where id = '${organization}';
delete from public.user_account_modes where user_id = '${author}';
delete from public.user_commercial_accounts where user_id = '${author}';
delete from public.account_plan_catalog where code = '${plan}' and account_type = 'trainer';
delete from auth.users where id in ('${author}', ${clients.map(id => `'${id}'`).join(',')});
commit;`;
  assertResultOk(await psql(container, cleanup), 'race fixture cleanup');
  }
}

if (process.argv.includes('--database-races')) {
  await runDatabaseRaces();
} else {
  runStaticContract();
}

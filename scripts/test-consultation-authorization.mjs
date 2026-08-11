import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const migrationsDir = resolve(root, 'supabase', 'migrations');
const workflowPath = resolve(root, '.github', 'workflows', 'supabase-validate.yml');
const pgTapPath = resolve(root, 'supabase', 'tests', 'v43a2_consultation_rls_test.sql');
const migrationFiles = readdirSync(migrationsDir)
  .filter(file => /^\d{14}_consultation_authorization_v43\.sql$/.test(file));
const results = [];

function check(name, test) {
  try {
    test();
    results.push({ name, passed: true });
  } catch (error) {
    results.push({ name, passed: false, error: error?.message || String(error) });
  }
}

const workflow = readFileSync(workflowPath, 'utf8');
const pgTap = readFileSync(pgTapPath, 'utf8');
const migrationPath = migrationFiles.length === 1
  ? resolve(migrationsDir, migrationFiles[0])
  : null;
const migration = migrationPath && existsSync(migrationPath)
  ? readFileSync(migrationPath, 'utf8')
  : '';

check('focused A.2B pgTAP actor matrix exists', () => {
  assert.ok(pgTap.length > 10_000, 'focused actor matrix is unexpectedly small');
  for (const contract of [
    'request_my_consultation_authorization_v43',
    'decide_my_consultation_authorization_v43',
    'revoke_my_consultation_authorization_v43',
    'set_my_shared_consultation_history_consent_v43',
    'list_my_manageable_consultation_subjects_v43',
    'get_my_consultation_v43',
    'list_shared_consultation_history_v43'
  ]) {
    assert.match(pgTap, new RegExp(contract, 'i'));
  }
});

check('CI executes focused and complete local database suites', () => {
  const workflowLines = workflow.split(/\r?\n/).map(line => line.trim());
  assert.ok(
    workflowLines.includes('- "scripts/test-consultation-authorization.mjs"'),
    'authorization source changes must trigger Supabase validation'
  );
  assert.ok(
    workflowLines.includes('run: node scripts/test-consultation-authorization.mjs'),
    'authorization source contract must execute in Supabase validation'
  );
  assert.equal(
    workflowLines.filter(line => line === 'run: pnpm exec supabase test db --local supabase/tests/v43a2_consultation_rls_test.sql').length,
    1,
    'focused A.2B pgTAP command must be exact and unique'
  );
  assert.equal(
    workflowLines.filter(line => line === 'run: pnpm exec supabase test db').length,
    1,
    'complete pgTAP command must be exact, argument-free and unique'
  );
  assert.match(workflow, /Secret scan failed for generated or committed database types/);
  assert.doesNotMatch(workflow, /actions\/upload-artifact/);
  assert.doesNotMatch(workflow, /supabase\s+(?:link|db push)|--linked/i);
});

check('migration V4.3A.2B exists exactly once', () => {
  assert.equal(
    migrationFiles.length,
    1,
    `expected one *_consultation_authorization_v43.sql migration; found: ${migrationFiles.join(', ') || 'none'}`
  );
});

check('migration has an incremental name and complete transaction', () => {
  assert.ok(migrationPath, 'authorization migration is absent');
  assert.match(basename(migrationPath), /^\d{14}_consultation_authorization_v43\.sql$/);
  assert.match(migration, /^begin;[\s\S]*commit;\s*$/i);
});

check('relationship scope shape adds independent false defaults', () => {
  for (const scope of ['manage_consultations', 'view_shared_consultation_history']) {
    assert.match(migration, new RegExp(`'${scope}'\\s*,\\s*false`, 'i'));
  }
  assert.match(migration, /professional_student_relationships_scopes_check/i);
  assert.match(migration, /apply_default_professional_relationship_scopes_v41e1/i);
});

check('authorization state uses dedicated request and append-only history', () => {
  for (const table of [
    'consultation_authorization_text_versions',
    'consultation_authorization_requests',
    'consultation_authorization_events',
    'consultation_sharing_consents'
  ]) {
    assert.match(migration, new RegExp(`create\\s+table\\s+public\\.${table}`, 'i'));
  }
  assert.match(migration, /reject_immutable_consultation_authorization_history_v43/i);
  const eventTable = migration.match(
    /create\s+table\s+public\.consultation_authorization_events\s*\([\s\S]*?\n\);/i
  )?.[0] || '';
  assert.doesNotMatch(
    eventTable,
    /\b(?:payload|content|body|details|comment|filename)\b/i
  );
});

check('public authorization RPC signatures contain no caller identity', () => {
  const signatures = [
    ['request_my_consultation_authorization_v43', ['uuid', 'text']],
    ['decide_my_consultation_authorization_v43', ['uuid', 'uuid', 'text', 'text']],
    ['revoke_my_consultation_authorization_v43', ['uuid', 'text']],
    ['set_my_shared_consultation_history_consent_v43', ['uuid', 'text', 'boolean']],
    ['list_my_manageable_consultation_subjects_v43', ['integer', 'uuid']],
    ['get_my_consultation_v43', ['uuid']],
    ['list_shared_consultation_history_v43', ['uuid', 'integer']]
  ];
  for (const [name, expectedTypes] of signatures) {
    const signature = migration.match(
      new RegExp(`function\\s+public\\.${name}\\s*\\(([^)]*)\\)`, 'i')
    )?.[1];
    assert.ok(signature, `${name} signature is absent`);
    const actualTypes = signature.split(',').map(argument =>
      argument
        .trim()
        .split(/\s+default\s+/i)[0]
        .trim()
        .split(/\s+/)
        .at(-1)
    );
    assert.deepEqual(actualTypes, expectedTypes, `${name} argument types changed`);
  }
  assert.doesNotMatch(
    migration,
    /function\s+public\.(?:request|decide|revoke|set_my_shared|list_my_manageable|get_my_consultation|list_shared)[^(]*\([^)]*(?:professional|student|client|author)_user_id/i
  );
});

check('every public A.2B RPC is a locked-down definer', () => {
  for (const name of [
    'request_my_consultation_authorization_v43',
    'decide_my_consultation_authorization_v43',
    'revoke_my_consultation_authorization_v43',
    'set_my_shared_consultation_history_consent_v43',
    'list_my_manageable_consultation_subjects_v43',
    'get_my_consultation_v43',
    'list_shared_consultation_history_v43'
  ]) {
    const body = migration.match(
      new RegExp(`create\\s+(?:or\\s+replace\\s+)?function\\s+public\\.${name}\\([\\s\\S]*?\\$\\$;`, 'i')
    )?.[0] || '';
    assert.match(body, /security\s+definer/i, `${name} must be SECURITY DEFINER`);
    assert.match(body, /set\s+search_path\s*=\s*''/i, `${name} must use an empty search_path`);
    assert.match(body, /auth\.uid\(\)/i, `${name} must derive the caller`);
  }
});

check('internal predicates are centralized and unavailable to browser roles', () => {
  for (const helper of [
    'assert_consultation_relationship_entitlement_v43',
    'has_current_shared_consultation_history_consent_v43',
    'is_approved_shared_consultation_item_v43'
  ]) {
    assert.match(migration, new RegExp(`function\\s+private\\.${helper}`, 'i'));
  }
  assert.match(
    migration,
    /revoke\s+all\s+privileges\s+on\s+all\s+functions\s+in\s+schema\s+private\s+from\s+public\s*,\s*anon\s*,\s*authenticated/i
  );
});

check('browser roles receive no direct consultation table mutation', () => {
  const sensitiveTables = [
    'consultation_subjects',
    'professional_consultations',
    'consultation_items',
    'consultation_authorization_text_versions',
    'consultation_authorization_requests',
    'consultation_authorization_events',
    'consultation_sharing_consents'
  ];
  for (const table of sensitiveTables) {
    assert.match(
      migration,
      new RegExp(`revoke\\s+all(?:\\s+privileges)?\\s+on\\s+table\\s+public\\.${table}[\\s\\S]{0,120}from\\s+public\\s*,\\s*anon\\s*,\\s*authenticated`, 'i')
    );
  }
  assert.doesNotMatch(
    migration,
    /grant\s+(?:select|insert|update|delete|all)[\s\S]{0,100}on\s+(?:table\s+)?public\.(?:consultation_|professional_consultations)/i
  );
});

check('new authorization tables force RLS and index relationship lookups', () => {
  for (const table of [
    'consultation_authorization_text_versions',
    'consultation_authorization_requests',
    'consultation_authorization_events',
    'consultation_sharing_consents'
  ]) {
    assert.match(
      migration,
      new RegExp(`alter\\s+table\\s+public\\.${table}\\s+enable\\s+row\\s+level\\s+security`, 'i')
    );
    assert.match(
      migration,
      new RegExp(`alter\\s+table\\s+public\\.${table}\\s+force\\s+row\\s+level\\s+security`, 'i')
    );
  }
  assert.match(migration, /consultation_authorization_requests_relationship/i);
  assert.match(migration, /consultation_authorization_events_relationship/i);
  assert.match(migration, /consultation_sharing_consents_relationship/i);
});

check('relationship deactivation clears authorization without touching A.2C', () => {
  assert.match(migration, /protect_consultation_relationship_authorization_v43/i);
  assert.match(migration, /old\.status\s*=\s*'active'[\s\S]*new\.status\s*<>\s*'active'/i);
  assert.match(migration, /manage_consultations/i);
  assert.doesNotMatch(
    migration,
    /consultation_edit_leases|lease_token|draft_revision\s*=|relationship_revoked_cleanup/i
  );
});

check('shared history is conjunctive, current-versioned, and approved-only', () => {
  const projection = migration.match(
    /create\s+(?:or\s+replace\s+)?function\s+public\.list_shared_consultation_history_v43\([\s\S]*?\$\$;/i
  )?.[0] || '';
  const itemAllowlist = migration.match(
    /create\s+(?:or\s+replace\s+)?function\s+private\.is_approved_shared_consultation_item_v43\([\s\S]*?\$\$;/i
  )?.[0] || '';
  assert.match(projection, /view_shared_consultation_history/i);
  assert.match(projection, /has_current_shared_consultation_history_consent_v43/i);
  assert.match(projection, /consultation_final_snapshots/i);
  assert.match(projection, /is_approved_shared_consultation_item_v43/i);
  assert.doesNotMatch(projection, /like\s+'common\.%'/i);
  assert.match(itemAllowlist, /target_item_key\s+in\s*\(\s*'common\.goal'\s*\)/i);
  assert.doesNotMatch(projection, /trainer_private|nutritionist_private|author_private/i);
});

check('migration avoids remote operations, production credentials, and later checkpoints', () => {
  assert.doesNotMatch(migration, /\b(?:supabase\s+link|db\s+push|--linked)\b/i);
  assert.doesNotMatch(
    migration,
    /service_role|SUPABASE_SERVICE_ROLE_KEY|sb_secret_|sbp_|postgres(?:ql)?:\/\//i
  );
  assert.doesNotMatch(
    migration,
    /consultation_edit_leases|consultation_measurements|consultation_attachments|consultation_publications|consultation_reminders/i
  );
});

const failures = results.filter(result => !result.passed);
for (const result of results) {
  console.log(
    `${result.passed ? 'PASS' : 'FAIL'} ${result.name}${result.error ? ` - ${result.error}` : ''}`
  );
}
console.log(`\n${results.length - failures.length}/${results.length} checks passed.`);
if (failures.length) process.exitCode = 1;

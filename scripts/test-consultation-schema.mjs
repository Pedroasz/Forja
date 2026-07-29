import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { basename, resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const migrationsDir = resolve(root, 'supabase', 'migrations');
const migrationFiles = readdirSync(migrationsDir)
  .filter(file => /^\d{14}_consultation_core_v43\.sql$/.test(file));
const results = [];

function check(name, test) {
  try {
    test();
    results.push({ name, passed: true });
  } catch (error) {
    results.push({ name, passed: false, error: error?.message || String(error) });
  }
}

check('migration V4.3A.2A existe uma unica vez', () => {
  assert.equal(
    migrationFiles.length,
    1,
    `esperada uma migration *_consultation_core_v43.sql; encontradas: ${migrationFiles.join(', ') || 'nenhuma'}`
  );
});

const migrationPath = migrationFiles.length === 1
  ? resolve(migrationsDir, migrationFiles[0])
  : null;
const migration = migrationPath && existsSync(migrationPath)
  ? readFileSync(migrationPath, 'utf8')
  : '';

check('migration possui nome incremental e transacao completa', () => {
  assert.ok(migrationPath, 'migration ausente');
  assert.match(basename(migrationPath), /^\d{14}_consultation_core_v43\.sql$/);
  assert.match(migration, /^begin;[\s\S]*commit;\s*$/i);
});

const expectedTables = [
  'consultation_subjects',
  'professional_consultations',
  'consultation_items',
  'consultation_final_snapshots',
  'consultation_addenda',
  'consultation_discard_tombstones',
  'consultation_events'
];

check('migration cria somente as sete entidades relacionais de A.2A', () => {
  const createdTables = [...migration.matchAll(
    /\bcreate\s+table\s+public\.([a-z0-9_]+)/gi
  )].map(match => match[1]).sort();
  assert.deepEqual(createdTables, [...expectedTables].sort());
});

check('kind, lifecycle e agenda usam constraints explicitas', () => {
  assert.match(migration, /professional_consultations_kind_check/i);
  assert.match(migration, /initial[\s\S]*reassessment/i);
  for (const status of [
    'scheduled',
    'in_progress',
    'paused',
    'finalized',
    'cancelled',
    'no_show',
    'archived'
  ]) {
    assert.match(migration, new RegExp(`'${status}'`, 'i'));
  }
  assert.match(migration, /professional_consultations_schedule_all_or_none_check/i);
  assert.match(migration, /professional_consultations_schedule_revision_check/i);
  assert.match(migration, /enforce_consultation_schedule_revision_v43/i);
  assert.match(migration, /validate_consultation_predecessor_v43/i);
});

check('todas as entidades publicas iniciam com RLS forçada e sem policy de conteudo', () => {
  for (const table of expectedTables) {
    assert.match(
      migration,
      new RegExp(`alter\\s+table\\s+public\\.${table}\\s+enable\\s+row\\s+level\\s+security`, 'i')
    );
    assert.match(
      migration,
      new RegExp(`alter\\s+table\\s+public\\.${table}\\s+force\\s+row\\s+level\\s+security`, 'i')
    );
  }
  assert.doesNotMatch(migration, /\bcreate\s+policy\b/i);
});

check('browser roles nao recebem acesso direto ao conteudo', () => {
  for (const table of expectedTables) {
    assert.match(
      migration,
      new RegExp(
        `revoke\\s+all\\s+on\\s+table\\s+public\\.${table}\\s+from\\s+public\\s*,\\s*anon\\s*,\\s*authenticated`,
        'i'
      )
    );
  }
  assert.doesNotMatch(
    migration,
    /\bgrant\s+(?:select|insert|update|delete|all)[\s\S]{0,100}\bon\s+(?:table\s+)?public\.(?:consultation_|professional_consultations)/i
  );
});

check('resolver aceita relationship_id e deriva caller com seguranca', () => {
  const resolver = migration.match(
    /create\s+(?:or\s+replace\s+)?function\s+public\.resolve_account_consultation_subject_v43\([\s\S]*?\$\$;/i
  )?.[0] || '';
  assert.match(resolver, /target_relationship_id\s+uuid/i);
  assert.doesNotMatch(resolver, /\b(?:client|student|subject)_user_id\s+uuid/i);
  assert.match(resolver, /security\s+definer/i);
  assert.match(resolver, /set\s+search_path\s*=\s*''/i);
  assert.match(resolver, /auth\.uid\(\)/i);
  assert.match(resolver, /professional_user_id\s*=\s*caller_user_id/i);
  assert.match(resolver, /relationship\.status\s*=\s*'active'/i);
  assert.match(resolver, /identity\.age_status\s*=\s*'adult'/i);
  assert.match(resolver, /interval\s+'18 years'/i);
  assert.match(
    migration,
    /grant\s+execute\s+on\s+function\s+public\.resolve_account_consultation_subject_v43\(uuid\)\s+to\s+authenticated/i
  );
  assert.match(
    migration,
    /revoke\s+all\s+on\s+function\s+public\.resolve_account_consultation_subject_v43\(uuid\)\s+from\s+public\s*,\s*anon/i
  );
});

check('canonicalizacao e hash usam bytes versionados, nao jsonb text', () => {
  assert.match(migration, /forja\.canonical-json\.v1/);
  assert.match(migration, /normalize\(/i);
  assert.match(migration, /canonical_json_timestamp_requires_milliseconds_utc/i);
  assert.match(migration, /canonical_json_decimal_must_be_string/i);
  assert.match(migration, /canonical_json_decimal_not_minimal/i);
  assert.match(migration, /collate\s+"C"/i);
  assert.match(migration, /convert_to\([\s\S]*'UTF8'/i);
  assert.match(migration, /extensions\.digest\([\s\S]*'sha256'/i);
  assert.doesNotMatch(migration, /jsonb\s*::\s*text/i);
  assert.doesNotMatch(migration, /canonical_payload\s*::\s*text/i);
});

check('historico imutavel e cascades ficam limitados ao draft', () => {
  assert.match(migration, /reject_immutable_consultation_entity_v43/i);
  assert.match(migration, /protect_finalized_consultation_items_v43/i);
  assert.match(migration, /protect_finalized_consultation_provenance_v43/i);
  assert.match(
    migration,
    /consultation_items_consultation_id_fkey[\s\S]*on\s+delete\s+cascade/i
  );
  for (const constraint of [
    'professional_consultations_subject_id_fkey',
    'professional_consultations_relationship_id_fkey',
    'consultation_final_snapshots_consultation_id_fkey',
    'consultation_addenda_consultation_id_fkey'
  ]) {
    assert.match(
      migration,
      new RegExp(`${constraint}[\\s\\S]*on\\s+delete\\s+(?:restrict|no\\s+action)`, 'i')
    );
  }
});

check('tombstones e eventos sao content-free e sem foreign keys', () => {
  const tombstones = migration.match(
    /create\s+table\s+public\.consultation_discard_tombstones\s*\([\s\S]*?\n\);/i
  )?.[0] || '';
  const events = migration.match(
    /create\s+table\s+public\.consultation_events\s*\([\s\S]*?\n\);/i
  )?.[0] || '';
  assert.doesNotMatch(tombstones, /\breferences\b|\bjsonb\b|\btext\s*,?\s*--\s*content/i);
  assert.doesNotMatch(events, /\breferences\b|\bjsonb\b/);
  assert.doesNotMatch(`${tombstones}\n${events}`, /\b(payload|content|body|details|filename)\b/i);
});

check('migration nao antecipa A.2B ou checkpoints posteriores', () => {
  assert.doesNotMatch(
    migration,
    /\bcreate\s+table\s+public\.(?:consultation_edit_leases|consultation_measurements|consultation_calculation_snapshots|consultation_publications|consultation_attachments|consultation_reminders)\b/i
  );
  assert.doesNotMatch(migration, /\bmanage_consultations\b|\bview_shared_consultation_history\b/i);
  assert.doesNotMatch(migration, /\bcron\.schedule\b|\bretention_job\b|\bautomatic_retention\b/i);
});

check('migration nao contem conflitos, segredos ou caminhos pessoais', () => {
  assert.doesNotMatch(migration, /^(?:<{7}|={7}|>{7})/m);
  assert.doesNotMatch(
    migration,
    /service_role|SUPABASE_SERVICE_ROLE_KEY|sk_live_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]+|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i
  );
  assert.doesNotMatch(migration, /[A-Z]:\\Users\\|\/Users\/|\/home\//i);
});

const failures = results.filter(result => !result.passed);
for (const result of results) {
  console.log(
    `${result.passed ? 'PASS' : 'FAIL'} ${result.name}${result.error ? ` — ${result.error}` : ''}`
  );
}
console.log(`\n${results.length - failures.length}/${results.length} verificacoes aprovadas.`);
if (failures.length) process.exitCode = 1;

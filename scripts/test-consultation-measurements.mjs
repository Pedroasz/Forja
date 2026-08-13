import assert from 'node:assert/strict';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname, '..');
const migrationsDir = resolve(root, 'supabase', 'migrations');
const pgTapPath = resolve(root, 'supabase', 'tests', 'v43a2_consultation_measurements_test.sql');
const workflowPath = resolve(root, '.github', 'workflows', 'supabase-validate.yml');
const packagePath = resolve(root, 'package.json');

const pgTap = existsSync(pgTapPath) ? readFileSync(pgTapPath, 'utf8') : '';
const workflow = readFileSync(workflowPath, 'utf8');
const packageJson = JSON.parse(readFileSync(packagePath, 'utf8'));
const measurementMigrations = readdirSync(migrationsDir)
  .filter(file => /^\d{14}_consultation_measurements_v43\.sql$/.test(file));
const migration = measurementMigrations.length === 1
  ? readFileSync(resolve(migrationsDir, measurementMigrations[0]), 'utf8')
  : '';

const results = [];
const check = (name, test) => {
  try {
    test();
    results.push({ name, passed: true });
  } catch (error) {
    results.push({ name, passed: false, error: error?.message || String(error) });
  }
};

check('GREEN checkpoint has exactly one forward A.2D migration', () => {
  assert.equal(
    measurementMigrations.length,
    1,
    `expected one *_consultation_measurements_v43.sql: ${measurementMigrations.join(', ')}`
  );
  assert.match(migration, /^begin;[\s\S]*commit;\s*$/i);
  assert.doesNotMatch(migration, /--linked|supabase\s+(?:link|db push)|service_role/i);
});

check('GREEN migration implements the behavioral surface without formula scope', () => {
  for (const contract of [
    'consultation_measurement_definitions',
    'consultation_measurement_sessions',
    'consultation_measurements',
    'consultation_measurement_readings',
    'consultation_device_observations',
    'save_my_consultation_measurement_v43',
    'save_my_consultation_device_observation_v43',
    'reduce_consultation_measurement_v43',
    'normalize_consultation_measurement_unit_v43',
    'consultation_measurements_are_comparable_v43',
    'consultation_device_observations_are_comparable_v43',
    'finalized_consultation_measurements_are_immutable',
    'consultation_measurement_justification_required',
    'measurement_corrected',
    'canonical_payload'
  ]) assert.match(migration, new RegExp(contract, 'i'), `${contract} is absent from migration`);
  assert.doesNotMatch(migration, /formula_registry|calculation_method_definitions/i);
});

check('GREEN migration keeps measurement content RPC-only and RLS-forced', () => {
  for (const table of [
    'consultation_measurement_definitions',
    'consultation_measurement_sessions',
    'consultation_measurements',
    'consultation_measurement_readings',
    'consultation_device_observations'
  ]) {
    assert.match(migration, new RegExp(`alter table public\\.${table} enable row level security`, 'i'));
    assert.match(migration, new RegExp(`alter table public\\.${table} force row level security`, 'i'));
    assert.match(migration, new RegExp(`revoke all privileges on table public\\.${table}[\\s\\S]*?from public, anon, authenticated`, 'i'));
  }
  assert.match(migration, /security definer[\s\S]*set search_path = ''/i);
  assert.match(migration, /grant execute on function[\s\S]*save_my_consultation_measurement_v43[\s\S]*to authenticated/i);
});

check('focused A.2D pgTAP is behavioral and synthetic', () => {
  assert.ok(pgTap.length > 20_000, 'focused A.2D pgTAP is unexpectedly small');
  assert.match(pgTap, /^begin;[\s\S]*select\s+\*\s+from\s+finish\(\);[\s\S]*rollback;\s*$/i);
  assert.match(pgTap, /All fixture values are synthetic/i);
  assert.match(pgTap, /save_my_consultation_measurement_v43/i);
  assert.match(pgTap, /save_my_consultation_device_observation_v43/i);
  assert.match(pgTap, /finalize_my_consultation_v43/i);
  assert.match(pgTap, /set\s+local\s+role\s+authenticated/i);
  assert.match(pgTap, /set\s+local\s+role\s+anon/i);
  assert.doesNotMatch(pgTap, /--linked|supabase\s+link|db\s+push/i);
});

check('definition and observation contracts are complete', () => {
  for (const contract of [
    'consultation_measurement_definitions',
    'consultation_measurement_sessions',
    'consultation_measurements',
    'consultation_measurement_readings',
    'consultation_device_observations',
    'definition_version',
    'canonical_unit',
    'anatomical_point',
    'position',
    'instructions',
    'protocol_id',
    'protocol_version',
    'formula_eligible',
    'custom measurement remains formula-ineligible'
  ]) {
    assert.match(pgTap, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), `${contract} is absent`);
  }
});

check('status, reading and validation matrices are explicit', () => {
  for (const status of [
    'not_attempted',
    'client_declined',
    'could_not_obtain',
    'instrument_limit',
    'recorded',
    'invalid'
  ]) assert.match(pgTap, new RegExp(status, 'i'), `${status} is absent`);

  for (const contract of [
    'one reading is valid',
    'three readings are valid',
    'four readings are rejected',
    'duplicate reading ordinal is rejected',
    'recorded status requires readings',
    'non-recorded status rejects readings',
    'raw readings remain preserved',
    'silent raw-reading replacement is rejected',
    'structurally malformed values are rejected'
  ]) assert.match(pgTap, new RegExp(contract, 'i'), `${contract} is absent`);
});

check('reducers, units and quality warnings are deterministic', () => {
  for (const contract of [
    'deterministic mean',
    'deterministic median',
    'deterministic decimal rounding',
    'normalize_consultation_measurement_unit_v43',
    'incompatible units are rejected',
    'outlier warning does not autocorrect raw readings',
    'outlier finalization requires professional justification'
  ]) assert.match(pgTap, new RegExp(contract, 'i'), `${contract} is absent`);
});

check('A.2C authority and actor denials are regression protected', () => {
  for (const contract of [
    'caller identity derives from auth.uid()',
    'client cannot write measurements',
    'other linked professional cannot write measurements',
    'organization admin has no clinical authority',
    'unrelated user cannot write measurements',
    'anonymous cannot write measurements',
    'stale lease cannot write measurements',
    'stale revision cannot write measurements',
    'finalized measurement rows are immutable',
    'browser roles have no direct measurement table privileges'
  ]) assert.match(pgTap, new RegExp(contract.replace(/[.*+?^${}()|[\]\\]/g, '\\$&'), 'i'), `${contract} is absent`);
});

check('snapshot and provenance contracts remain reproducible', () => {
  for (const contract of [
    'forja.canonical-json.v1',
    'snapshot preserves definition and protocol version',
    'later definition version does not rewrite finalized measurement provenance',
    'non-recorded observation finalizes without invented numeric values',
    'dependent calculations remain ineligible',
    'device observation preserves original metrics and units',
    'different device or mode is not silently comparable',
    'custom measurements are not compared by label alone'
  ]) assert.match(pgTap, new RegExp(contract, 'i'), `${contract} is absent`);
});

check('package exposes the focused A.2D source and database commands', () => {
  assert.equal(
    packageJson.scripts?.['test:consultation-measurements'],
    'node scripts/test-consultation-measurements.mjs'
  );
  assert.equal(
    packageJson.scripts?.['test:consultation-measurements-db'],
    'supabase test db --local supabase/tests/v43a2_consultation_measurements_test.sql'
  );
});

check('Supabase CI triggers, runs and enforces focused A.2D validation', () => {
  const lines = workflow.split(/\r?\n/).map(line => line.trim());
  assert.ok(lines.includes('- "scripts/test-consultation-measurements.mjs"'));
  assert.equal(
    lines.filter(line => line === 'run: node scripts/test-consultation-measurements.mjs').length,
    1,
    'A.2D static contract must run exactly once'
  );
  assert.equal(
    lines.filter(line => line === 'run: pnpm exec supabase test db --local supabase/tests/v43a2_consultation_measurements_test.sql').length,
    1,
    'focused A.2D pgTAP must run exactly once'
  );
  assert.match(workflow, /id:\s*consultation_measurements_source[\s\S]*continue-on-error:\s*true/i);
  assert.match(workflow, /id:\s*consultation_measurements_pgtap[\s\S]*continue-on-error:\s*true/i);
  assert.match(workflow, /steps\.consultation_measurements_source\.outcome/i);
  assert.match(workflow, /steps\.consultation_measurements_pgtap\.outcome/i);
  assert.equal(
    lines.filter(line => line === 'run: pnpm exec supabase test db').length,
    1,
    'complete pgTAP command remains exact and argument-free'
  );
});

check('GREEN workflow remains runner-local and publishes no artifact', () => {
  assert.doesNotMatch(workflow, /actions\/upload-artifact/i);
  assert.doesNotMatch(workflow, /supabase\s+(?:link|db push)|--linked/i);
  assert.match(workflow, /supabase\s+start/i);
  assert.match(workflow, /supabase\s+test\s+db\s+--local/i);
});

const failures = results.filter(result => !result.passed);
for (const result of results) {
  console.log(`${result.passed ? 'PASS' : 'FAIL'} ${result.name}${result.error ? ` - ${result.error}` : ''}`);
}
console.log(`\n${results.length - failures.length}/${results.length} checks passed.`);
if (failures.length) process.exitCode = 1;

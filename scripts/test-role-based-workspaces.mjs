import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import vm from 'node:vm';

const root = resolve(import.meta.dirname, '..');
const indexPath = resolve(root, 'index.html');
const migrationPath = resolve(root, 'supabase/migrations/20260715200320_harden_role_based_workspace_access.sql');
const index = readFileSync(indexPath, 'utf8');
const migration = readFileSync(migrationPath, 'utf8');
const results = [];

function check(name, test) {
  try {
    test();
    results.push({ name, passed: true });
  } catch (error) {
    results.push({ name, passed: false, error: error?.message || String(error) });
  }
}

function extract(source, start, end) {
  const startIndex = source.indexOf(start);
  const endIndex = source.indexOf(end, startIndex);
  assert.notEqual(startIndex, -1, `inicio nao encontrado: ${start}`);
  assert.notEqual(endIndex, -1, `fim nao encontrado: ${end}`);
  return source.slice(startIndex, endIndex);
}

const storage = new Map();
const serviceSource = extract(index, 'const ALLOWED_ACCOUNT_MODES=', 'function mapInvitationError');
const serviceContext = {
  console,
  state: {
    accountModes: { values: [] },
    accessContext: { data: {} },
    assignedWorkoutPlans: { loaded: true, items: [], error: null },
    assignedNutritionPlans: { loaded: true, items: [], error: null },
    workspace: { loaded: false, active: 'individual', available: ['individual'] }
  },
  accountRegistrationContext: null,
  localStorage: {
    getItem: key => storage.has(key) ? storage.get(key) : null,
    setItem: (key, value) => storage.set(key, String(value)),
    removeItem: key => storage.delete(key)
  },
  createEmptyAccessContext: () => ({
    platformRoles: [], memberships: [], professionalRelationships: [],
    studentProfessionalRelationships: [], studentRelationships: [], commercialAccount: null
  }),
  normalizeProfessionalRelationship: (item = {}) => ({
    ...item,
    id: item.id || null,
    professionalType: ['trainer', 'nutritionist'].includes(String(item.professionalType || item.professional_type || '').toLowerCase())
      ? String(item.professionalType || item.professional_type).toLowerCase()
      : null,
    status: String(item.status || '').toLowerCase()
  }),
  getCurrentAuthUser: () => null,
  getLocalDateKey: () => '2026-07-15'
};
vm.createContext(serviceContext);
new vm.Script(`${serviceSource}\n;globalThis.__v42a={WORKSPACE_KEYS_V42A,WORKSPACE_NAVIGATION_V42A,getWorkspaceNavigationV42A,getWorkspaceDefaultRouteV42A,resolveWorkspaceRouteV42A,getRoleAccessSnapshotV42A,WorkspaceService,isCurrentAssignedWorkoutPrescriptionV42A,isCurrentAssignedNutritionPrescriptionV42A,getPrescriptionProtectionV42A,PermissionService};`, { filename: 'index.html#v42a-services' }).runInContext(serviceContext);
const {
  WORKSPACE_KEYS_V42A, WORKSPACE_NAVIGATION_V42A, getWorkspaceDefaultRouteV42A,
  resolveWorkspaceRouteV42A, WorkspaceService, getPrescriptionProtectionV42A,
  PermissionService, isCurrentAssignedWorkoutPrescriptionV42A
} = serviceContext.__v42a;

const emptyAccess = () => ({
  platformRoles: [], memberships: [], professionalRelationships: [],
  studentProfessionalRelationships: [], studentRelationships: [], commercialAccount: null
});
const snapshot = ({ primary = 'individual', modes = ['individual'], access = emptyAccess(), personalUseEnabled } = {}) =>
  WorkspaceService.getAccessSnapshot({
    accessContext: access,
    accountRegistration: { primaryAccountType: primary, ...(personalUseEnabled === undefined ? {} : { personalUseEnabled }) },
    accountModes: modes
  });
const unlocked = { workout: { active: false, uncertain: false }, nutrition: { active: false, uncertain: false } };
const lockedWorkout = { workout: { active: true, uncertain: false }, nutrition: { active: false, uncertain: false } };
const lockedNutrition = { workout: { active: false, uncertain: false }, nutrition: { active: true, uncertain: false } };
const lockedBoth = { workout: { active: true, uncertain: false }, nutrition: { active: true, uncertain: false } };
const caps = (roleSnapshot, workspace, protection = unlocked, authenticated = true) =>
  PermissionService.getCapabilities({ roleSnapshot, workspace, protection, authenticated });

check('01 independente', () => {
  const role = snapshot();
  assert.deepEqual([...WorkspaceService.getAvailableWorkspaces({ roleSnapshot: role })], ['individual']);
  assert.equal(WorkspaceService.getDefaultWorkspace({ roleSnapshot: role }), 'individual');
  assert.equal(caps(role, 'individual').canViewDashboard, true);
});

check('02 aluno com treinador', () => {
  const role = snapshot({ modes: ['individual', 'student'], access: { ...emptyAccess(), studentProfessionalRelationships: [{ id: 'r1', professionalType: 'trainer', status: 'active' }] } });
  const permissions = caps(role, 'student', lockedWorkout);
  assert.equal(role.hasStudentWorkspace, true);
  assert.equal(permissions.canEditWorkoutPrescription, false);
  assert.equal(permissions.canEditNutritionPrescription, true);
});

check('03 paciente com nutricionista', () => {
  const role = snapshot({ modes: ['individual', 'student'], access: { ...emptyAccess(), studentProfessionalRelationships: [{ id: 'r2', professionalType: 'nutritionist', status: 'active' }] } });
  const permissions = caps(role, 'student', lockedNutrition);
  assert.equal(role.hasStudentWorkspace, true);
  assert.equal(permissions.canEditWorkoutPrescription, true);
  assert.equal(permissions.canEditNutritionPrescription, false);
});

check('04 aluno e paciente com dois profissionais', () => {
  const role = snapshot({ modes: ['student'], access: { ...emptyAccess(), studentProfessionalRelationships: [{ id: 'r1', professionalType: 'trainer', status: 'active' }, { id: 'r2', professionalType: 'nutritionist', status: 'active' }] } });
  const permissions = caps(role, 'student', lockedBoth);
  assert.equal(permissions.canEditWorkoutPrescription, false);
  assert.equal(permissions.canEditNutritionPrescription, false);
});

check('05 treinador sem alunos', () => {
  const role = snapshot({ primary: 'trainer', modes: ['trainer'], personalUseEnabled: false });
  assert.equal(WorkspaceService.getDefaultWorkspace({ roleSnapshot: role }), 'trainer');
  assert.equal(caps(role, 'trainer').canCreateWorkoutTemplates, true);
});

check('06 treinador com alunos', () => {
  const role = snapshot({ primary: 'trainer', modes: ['trainer'], access: { ...emptyAccess(), professionalRelationships: [{ id: 'r1', professionalType: 'trainer', status: 'active' }] } });
  assert.equal(role.professionalRelationships.length, 1);
  assert.equal(caps(role, 'trainer').canManageStudents, true);
});

check('07 nutricionista sem pacientes', () => {
  const role = snapshot({ primary: 'nutritionist', modes: ['nutritionist'], personalUseEnabled: false });
  assert.equal(WorkspaceService.getDefaultWorkspace({ roleSnapshot: role }), 'nutritionist');
  assert.equal(caps(role, 'nutritionist').canCreateNutritionTemplates, true);
});

check('08 nutricionista com pacientes', () => {
  const role = snapshot({ primary: 'nutritionist', modes: ['nutritionist'], access: { ...emptyAccess(), professionalRelationships: [{ id: 'r2', professionalType: 'nutritionist', status: 'active' }] } });
  assert.equal(role.professionalRelationships.length, 1);
  assert.equal(caps(role, 'nutritionist').canManagePatients, true);
});

check('09 treinador e aluno multi-workspace', () => {
  const role = snapshot({ primary: 'trainer', modes: ['individual', 'student', 'trainer'] });
  const available = [...WorkspaceService.getAvailableWorkspaces({ roleSnapshot: role })];
  assert.equal(available.includes('trainer') && available.includes('student'), true);
  assert.equal(WorkspaceService.getDefaultWorkspace({ roleSnapshot: role }), 'trainer');
  assert.equal(caps(role, 'trainer').canSwitchWorkspace, true);
  assert.equal(caps(role, 'student').canCreateWorkoutTemplates, false);
  assert.equal(caps(role, 'student').canManageStudents, false);
});

check('10 nutricionista e paciente multi-workspace', () => {
  const role = snapshot({ primary: 'nutritionist', modes: ['individual', 'student', 'nutritionist'] });
  const available = [...WorkspaceService.getAvailableWorkspaces({ roleSnapshot: role })];
  assert.equal(available.includes('nutritionist') && available.includes('student'), true);
  assert.equal(WorkspaceService.getDefaultWorkspace({ roleSnapshot: role }), 'nutritionist');
});

check('11 administrador', () => {
  const role = snapshot({ access: { ...emptyAccess(), platformRoles: ['platform_admin'] } });
  assert.equal(role.hasAdminWorkspace, true);
  assert.equal(WorkspaceService.getDefaultWorkspace({ roleSnapshot: role }), 'admin');
  assert.equal(caps(role, 'admin').canViewDashboard, true);
});

check('12 papel invalido falha com seguranca', () => {
  const role = snapshot({ primary: 'coach', modes: ['coach'], access: { ...emptyAccess(), platformRoles: ['root'], memberships: [{ organization_id: 'org', role: 'superuser', status: 'active' }] }, personalUseEnabled: false });
  const available = [...WorkspaceService.getAvailableWorkspaces({ roleSnapshot: role })];
  const permissions = caps(role, available[0]);
  assert.deepEqual(available, ['individual']);
  assert.equal(role.hasTrainerWorkspace || role.hasNutritionistWorkspace || role.hasAdminWorkspace || role.hasManagerWorkspace, false);
  assert.equal(permissions.canCreateWorkoutTemplates || permissions.canCreateNutritionTemplates || permissions.canManageStudents || permissions.canManagePatients, false);
});

check('13 workspace salvo invalido', () => {
  storage.clear();
  const role = snapshot();
  storage.set(WorkspaceService.getStorageKey('user-invalid'), 'admin');
  const resolved = WorkspaceService.resolve({ userId: 'user-invalid', roleSnapshot: role });
  assert.equal(resolved.active, 'individual');
  assert.equal(resolved.source, 'safe-fallback');
  assert.equal(resolved.available.includes('admin'), false);
});

check('14 sessao expirada', () => {
  const role = snapshot({ primary: 'trainer', modes: ['trainer'] });
  const permissions = caps(role, 'trainer', unlocked, false);
  assert.equal(Object.values(permissions).every(value => value === false), true);
});

check('15 login resolve contexto antes da tela', () => {
  storage.clear();
  const role = snapshot({ primary: 'trainer', modes: ['trainer'] });
  assert.equal(WorkspaceService.resolve({ userId: 'login-user', roleSnapshot: role }).active, 'trainer');
  const authFlow = extract(index, 'async function showAuthenticatedApp', 'function getCurrentAuthUser');
  assert.match(authFlow, /setWorkspaceResolutionLoadingV42A\(true\)[\s\S]*await resolveAuthenticatedWorkspaceV42A\(\)[\s\S]*await showApp\(\)/);
});

check('16 logout limpa estado do workspace', () => {
  serviceContext.state.workspace = { loaded: true, active: 'trainer', available: ['trainer'] };
  WorkspaceService.resetSession();
  assert.equal(serviceContext.state.workspace.loaded, false);
  assert.equal(serviceContext.state.workspace.active, 'individual');
  assert.match(index, /function resetAuthenticatedUserState\(\)[\s\S]*WorkspaceService\.resetSession\(\)/);
});

check('17 refresh revalida workspace persistido', () => {
  storage.clear();
  const role = snapshot({ primary: 'trainer', modes: ['individual', 'student', 'trainer'] });
  WorkspaceService.resolve({ userId: 'refresh-user', roleSnapshot: role });
  assert.equal(WorkspaceService.select('student', { userId: 'refresh-user', roleSnapshot: role }).active, 'student');
  const refreshed = WorkspaceService.resolve({ userId: 'refresh-user', roleSnapshot: role });
  assert.equal(refreshed.active, 'student');
  assert.equal(refreshed.source, 'stored');
});

check('18 mobile mantem exatamente cinco destinos', () => {
  assert.equal(Object.values(WORKSPACE_NAVIGATION_V42A).every(items => items.length === 5), true);
  assert.match(index, /id="workspace-nav-items"[^>]*grid-cols-5/);
  assert.match(index, /@media\(max-width:767px\)/);
});

check('19 offline caches e fila sao isolados por usuario', () => {
  assert.match(index, /USER_SCOPED_STORAGE_BASE_KEYS_V42A=new Set\(\[[^\]]*SYNC_QUEUE_KEY[^\]]*forja_active_workout_session/s);
  assert.match(index, /return `\$\{normalized\}:\$\{getLocalStorageOwnerV42A\(userId\)\}`/);
  assert.match(index, /localStorage\.setItem\(resolveUserScopedStorageKeyV42A\(SYNC_QUEUE_KEY\)/);
  assert.match(index, /const queueOwnerId=String\(currentSession\?\.user\?\.id\|\|''\)/);
});

check('20 acesso manual e validado pelo roteador', () => {
  assert.equal(resolveWorkspaceRouteV42A('consultations', 'trainer').route, 'students');
  assert.equal(resolveWorkspaceRouteV42A('workouts', 'student').route, 'my-workout');
  assert.match(index, /function navigateToWorkspaceRouteV42A\(route[\s\S]*resolveWorkspaceRouteV42A\(route\)/);
});

check('21 edicao indevida da prescricao de treino', () => {
  const role = snapshot({ modes: ['student'] });
  const permissions = caps(role, 'student', lockedWorkout);
  assert.equal(permissions.canEditWorkoutPrescription, false);
  assert.equal(getPrescriptionProtectionV42A({ authenticated: true, assignedWorkoutState: { loaded: true, items: [], error: 'assigned_workouts_unavailable' }, assignedNutritionState: { loaded: true, items: [], error: null } }).workout.uncertain, true);
  assert.match(index, /PermissionService\.canEditPersonalPrescription\('workout'\)/);
});

check('22 edicao indevida da prescricao alimentar', () => {
  const role = snapshot({ modes: ['student'] });
  const permissions = caps(role, 'student', lockedNutrition);
  assert.equal(permissions.canEditNutritionPrescription, false);
  assert.equal(getPrescriptionProtectionV42A({ authenticated: true, assignedWorkoutState: { loaded: true, items: [], error: null }, assignedNutritionState: { loaded: true, items: [], error: 'assigned_nutrition_unavailable' } }).nutrition.uncertain, true);
  assert.match(index, /PermissionService\.canEditPersonalPrescription\('nutrition'\)/);
});

check('23 registros de execucao e adesao permanecem permitidos', () => {
  const role = snapshot({ modes: ['student'] });
  const permissions = caps(role, 'student', lockedBoth);
  assert.equal(permissions.canLogWorkoutExecution, true);
  assert.equal(permissions.canLogNutritionAdherence, true);
});

check('24 isolamento organizacional e RLS', () => {
  assert.match(migration, /create policy student_workout_assignments_select_participant_v41b[\s\S]*relationship\.status = 'active'[\s\S]*professional_type = 'trainer'[\s\S]*manage_workout_plan[\s\S]*organization\.status = 'active'[\s\S]*membership\.status = 'active'/);
  assert.match(migration, /workout_organization_membership_required/);
  assert.match(migration, /nutrition_organization_membership_required/);
  assert.match(migration, /professional_monitoring_organization_membership_required/);
  assert.match(migration, /membership\.organization_id = relationship_record\.organization_id/);
  assert.match(migration, /organization\.status = 'active'/);
  assert.doesNotMatch(migration, /raw_user_meta_data|user_metadata/i);
});

check('25 organizacao inativa nao concede workspace gestor', () => {
  const active = snapshot({ access: { ...emptyAccess(), memberships: [{ organization_id: 'org', role: 'owner', status: 'active', organizationStatus: 'active' }] } });
  const suspended = snapshot({ access: { ...emptyAccess(), memberships: [{ organization_id: 'org', role: 'owner', status: 'active', organizationStatus: 'suspended' }] } });
  assert.equal(active.hasManagerWorkspace, true);
  assert.equal(suspended.hasManagerWorkspace, false);
  assert.match(migration, /'organizationStatus', organization\.status/);
});

check('26 atribuicao futura fica protegida na virada offline', () => {
  const future = { assignmentId: 'a1', relationshipId: 'r1', status: 'active', relationshipStatus: 'active', professionalType: 'trainer', canManageWorkoutPlan: true, effectiveFrom: '2026-07-16' };
  assert.equal(isCurrentAssignedWorkoutPrescriptionV42A(future, '2026-07-15'), false);
  assert.equal(isCurrentAssignedWorkoutPrescriptionV42A(future, '2026-07-16'), true);
  assert.match(index, /hasScope\?\(item\.canManageWorkoutPlan===true\|\|item\.can_manage_workout_plan===true\):false/);
  assert.match(migration, /'canManageWorkoutPlan'[\s\S]*'canStart'[\s\S]*assignment\.effective_from <= current_date/);
});

check('27 migracao local e reset respeitam o dono', () => {
  assert.match(index, /LEGACY_STORAGE_CLAIM_MARKER_V42A='forja_legacy_storage_claim_v42a'/);
  assert.match(index, /if\(previousRaw\)[\s\S]*previous\?\.owner===owner/);
  assert.match(index, /legacyValue!==null&&localStorage\.getItem\(scopedKey\)===null/);
  assert.match(index, /USER_SCOPED_STORAGE_BASE_KEYS_V42A\.forEach\(key => localStorage\.removeItem\(resolveUserScopedStorageKeyV42A\(key\)\)\)/);
  assert.match(index, /previousStorageKey=lastAuthenticatedUserId\?resolveUserScopedStorageKeyV42A\(ACTIVE_WORKOUT_SESSION_KEY,lastAuthenticatedUserId\):`\$\{ACTIVE_WORKOUT_SESSION_KEY\}:offline`/);
  assert.match(index, /localStorage\.setItem\(resolveUserScopedStorageKeyV42A\(LS\.execucoes\), JSON\.stringify\(previousExecutions\)\)/);
});

check('scripts JavaScript inline possuem sintaxe valida', () => {
  const scriptPattern = /<script\b([^>]*)>([\s\S]*?)<\/script>/gi;
  let match;
  let parsed = 0;
  while ((match = scriptPattern.exec(index))) {
    const attributes = match[1];
    if (/\bsrc\s*=/.test(attributes) || /type\s*=\s*["'](?:application\/json|importmap)["']/i.test(attributes)) continue;
    new vm.Script(match[2], { filename: `index.html#inline-${parsed + 1}` });
    parsed += 1;
  }
  assert.ok(parsed > 0);
});

check('IDs unicos e handlers literais sem referencias orfas', () => {
  const markup = index.replace(/<script\b[^>]*>[\s\S]*?<\/script>/gi, '');
  const ids = [...markup.matchAll(/\bid\s*=\s*["']([^"']+)["']/gi)].map(match => match[1]);
  assert.equal(new Set(ids).size, ids.length);
  const idSet = new Set(ids);
  const handlerPattern = /(?:document\.getElementById|authEl)\(\s*["']([^"']+)["']\s*\)\s*\??\.\s*addEventListener/g;
  const missing = [...index.matchAll(handlerPattern)].map(match => match[1]).filter(id => !idSet.has(id));
  assert.deepEqual(missing, []);
});

check('scanner de segredos e conflitos', () => {
  assert.doesNotMatch(index, /service_role|SUPABASE_SERVICE_ROLE_KEY|sk_live_[A-Za-z0-9]+|github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]+|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i);
  assert.doesNotMatch(`${index}\n${migration}`, /^(?:<{7}|={7}|>{7})/m);
});

check('baseline e tipos permanecem intactos', () => {
  execFileSync('git', ['diff', '--quiet', 'origin/main', '--', 'supabase/migrations/20260715144255_forja_remote_baseline.sql', 'supabase/database.types.ts'], { cwd: root, stdio: 'pipe' });
});

check('migration possui nome, transacao e guards esperados', () => {
  assert.equal(basename(migrationPath), '20260715200320_harden_role_based_workspace_access.sql');
  assert.match(migration, /^begin;[\s\S]*commit;\s*$/i);
  assert.match(migration, /revoke all privileges on table[\s\S]*from public, anon, authenticated/);
  assert.match(migration, /alter default privileges for role postgres[\s\S]*revoke all privileges on routines from public, anon, authenticated/);
  assert.match(migration, /security definer[\s\S]*set search_path = ''/i);
  assert.doesNotMatch(migration, /\bservice_role\b/i);
});

const failures = results.filter(result => !result.passed);
for (const result of results) {
  console.log(`${result.passed ? 'PASS' : 'FAIL'} ${result.name}${result.error ? ` — ${result.error}` : ''}`);
}
console.log(`\n${results.length - failures.length}/${results.length} verificacoes aprovadas.`);
if (failures.length) process.exitCode = 1;

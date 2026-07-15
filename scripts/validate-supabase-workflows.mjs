import { readFileSync } from "node:fs";
import { join } from "node:path";

const workflowPath =
  process.env.SUPABASE_BASELINE_WORKFLOW_PATH ??
  join(process.cwd(), ".github", "workflows", "supabase-baseline.yml");
const workflow = readFileSync(workflowPath, "utf8");

const requireMatch = (pattern, message) => {
  if (!pattern.test(workflow)) throw new Error(message);
};

const getStep = (name) => {
  const escapedName = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(
    `^ {6}- name: ${escapedName}\\r?\\n(.*?)(?=^ {6}- name:|(?![\\s\\S]))`,
    "ms",
  ).exec(workflow);
  if (!match) throw new Error(`Missing workflow step: ${name}`);
  return match[1];
};

const globalEnv =
  /^ {4}env:\r?\n(.*?)(?=^ {4}steps:)/ms.exec(workflow)?.[1] ?? "";
for (const credential of [
  "SUPABASE_ACCESS_TOKEN",
  "SUPABASE_DB_PASSWORD",
  "SUPABASE_PROJECT_REF",
  "GH_TOKEN",
]) {
  if (new RegExp(`^ {6}${credential}:`, "m").test(globalEnv)) {
    throw new Error(`${credential} must not be declared in jobs.capture.env.`);
  }
}

for (const stepName of [
  "Validate target and required configuration",
  "Link the confirmed production project",
  "Confirm the registered remote baseline",
  "Recover the registered baseline migration",
  "Confirm local and remote migration histories align",
  "Require an empty production dry-run",
]) {
  const step = getStep(stepName);
  for (const credential of [
    "SUPABASE_ACCESS_TOKEN",
    "SUPABASE_DB_PASSWORD",
    "SUPABASE_PROJECT_REF",
  ]) {
    if (!new RegExp(`^ {10}${credential}:`, "m").test(step)) {
      throw new Error(
        `${stepName} must receive ${credential} only at step scope.`,
      );
    }
  }
}

const localCredentialCheck = getStep(
  "Verify remote credentials are absent from local validation",
);
requireMatch(
  /test -z "\$\{SUPABASE_ACCESS_TOKEN:-\}"/,
  "Local validation must reject a defined SUPABASE_ACCESS_TOKEN.",
);
requireMatch(
  /test -z "\$\{SUPABASE_DB_PASSWORD:-\}"/,
  "Local validation must reject a defined SUPABASE_DB_PASSWORD.",
);
if (/^ {10}SUPABASE_(ACCESS_TOKEN|DB_PASSWORD):/m.test(localCredentialCheck)) {
  throw new Error(
    "The local credential check must not receive remote credentials.",
  );
}

const localTypes = getStep(
  "Generate public database types from the validated local database",
);
for (const requirement of [
  /env -u SUPABASE_ACCESS_TOKEN -u SUPABASE_DB_PASSWORD/,
  /supabase gen types --local --lang typescript --schema public/,
  /test -s supabase\/database\.types\.ts/,
  /export type Database/,
]) {
  if (!requirement.test(localTypes))
    throw new Error(
      "Local type generation is missing a required credential-isolation check.",
    );
}

for (const localStepName of [
  "Start the minimal local Supabase stack",
  "Inspect local migration history",
  "Lint the reconstructed local database",
  "Run local security advisors",
  "Run local performance advisors",
  "Generate public database types from the validated local database",
  "Stop and remove local Supabase containers",
]) {
  if (
    /SUPABASE_(ACCESS_TOKEN|DB_PASSWORD|PROJECT_REF):|GH_TOKEN:/m.test(
      getStep(localStepName),
    )
  ) {
    throw new Error(`${localStepName} must not receive remote credentials.`);
  }
}

const prStep = getStep("Open the baseline pull request as draft");
if (!/^ {10}GH_TOKEN: \$\{\{ github\.token \}\}$/m.test(prStep)) {
  throw new Error("Only the draft PR step may receive GH_TOKEN.");
}
if (!/--draft/.test(prStep))
  throw new Error("The baseline PR must remain a draft.");
if (/\b(?:gh pr|git) merge\b/.test(workflow))
  throw new Error(
    "The temporary baseline workflow must not merge a pull request.",
  );

requireMatch(
  /^permissions:\r?\n  contents: write\r?\n  pull-requests: write/m,
  "The baseline workflow must retain its required GitHub permissions.",
);
const changeSetStep = getStep("Prepare the baseline-only change set");
if (!/rm \.github\/workflows\/supabase-baseline\.yml/.test(changeSetStep)) {
  throw new Error(
    "The temporary baseline workflow must remove itself from the generated change set.",
  );
}
const commitStep = getStep("Commit and push the baseline branch");
for (const requirement of [
  /git add --/,
  /git rm -- \.github\/workflows\/supabase-baseline\.yml/,
  /git push --set-upstream origin/,
]) {
  if (!requirement.test(commitStep))
    throw new Error("The baseline-only commit flow is incomplete.");
}

for (const scannerPattern of [
  "reject_sensitive_content 'sb_secret_[A-Za-z0-9_-]+'",
  "reject_sensitive_content 'sbp_[A-Za-z0-9_-]+'",
  "reject_sensitive_content 'gh[pousr]_[A-Za-z0-9_]+'",
  "reject_sensitive_content 'SUPABASE_(ACCESS_TOKEN|DB_PASSWORD)'",
]) {
  if (!workflow.includes(scannerPattern))
    throw new Error("The baseline secret scanner was weakened.");
}

const pushCommands = workflow.match(/^.*supabase db push.*$/gm) ?? [];
if (pushCommands.some((command) => !/--dry-run|--help/.test(command))) {
  throw new Error(
    "The temporary baseline workflow must not run a real db push.",
  );
}
if (/supabase db pull/.test(workflow))
  throw new Error("The temporary baseline workflow must not run db pull.");
if (/supabase migration repair/.test(workflow))
  throw new Error(
    "The temporary baseline workflow must not run migration repair.",
  );
if (
  !/^on:\r?\n  workflow_dispatch:/m.test(workflow) ||
  /^  (pull_request|push|schedule):/m.test(workflow)
) {
  throw new Error(
    "The temporary baseline workflow must only use workflow_dispatch.",
  );
}
if (!workflow.includes("yncintjylzmvzcadjfqa"))
  throw new Error("The expected FORJA project ref is missing.");
if (
  !/expected_version="20260715144255"/.test(workflow) ||
  !/expected_name="\$\{expected_version\}_forja_remote_baseline\.sql"/.test(
    workflow,
  )
) {
  throw new Error("The expected remote baseline identifier is missing.");
}

console.log(
  "Validated Supabase workflow credential isolation and baseline safeguards.",
);

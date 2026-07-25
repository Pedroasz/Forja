# ADR 0003: Professional consultation records

- Status: Accepted V4.3 v1 guardrails; implementation pending
- Date: 2026-07-25
- Decision owners: Pedro / FORJA
- Related specification: [V4.3A.1 consultation module design](../superpowers/specs/2026-07-25-v4.3a1-consultation-module-design.md)

## Context

FORJA needs professional consultations for trainers and nutritionists. A consultation combines:

- mutable autosaved drafts;
- exclusive author editing across devices;
- shared common history;
- profession-private content;
- field-level sharing;
- repeated measurements and calculation provenance;
- explicit client publication;
- immutable finalization and addenda;
- private attachments and generated reports;
- future subjects without FORJA accounts.

The current application has authoritative professional relationships, role-based workspaces, RPC-controlled writes and immutable plan-assignment snapshots. It has no consultation schema, editing lease or Storage policy. The “Consultas” screen is a no-data placeholder.

Consultation content is more sensitive than a generic plan or dashboard summary. Organization membership, visible navigation and browser state cannot be authorization sources.

## Decision

Adopt a **relational consultation core with canonical immutable versioned snapshots**.

### Security domain

The security domain is the consultation author plus stable subject:

- the active professional-client relationship authorizes creation and ongoing draft work;
- `manage_consultations` and `view_shared_consultation_history` default to false;
- consultation authorization requires an explicit audited action;
- only the client may grant or revoke shared-history access for one exact professional relationship and accepted privacy-text version;
- the author owns and exclusively edits the record;
- organization is context/provenance only;
- organization owner/admin status does not grant consultation content;
- organization owner/admin metadata is limited to schedule, status, attendance and responsible professional;
- other professionals read only finalized common projections or exact item shares;
- the client reads only immutable publication manifests explicitly created for that client.

### Record model

Use relational entities for:

- stable subject identity;
- consultation ownership, relationship, state and revision;
- field envelopes and definitions;
- measurement sessions, raw readings and aggregate results;
- formula/protocol identities and calculation provenance;
- editing lease;
- shares, publications, responses, attachments and audit events.

On finalization, produce canonical JSON with schema version and SHA-256. Freeze the relational content and preserve the snapshot. Corrections append an immutable addendum; new observations use a reassessment.

Canonicalization uses the versioned `forja.canonical-json.v1` byte contract defined by the specification and fixed expected-byte/hash fixtures; it does not hash PostgreSQL `jsonb::text`.

On publication, produce a separate immutable allowlisted client manifest. Never expose the live author record as the client view.

### Write model

Sensitive mutations use narrowly scoped authenticated RPCs:

- derive author from `auth.uid()`;
- derive subject from `relationship_id`;
- validate professional identity, account mode, plan entitlement, active relationship, organization context and consultation scope;
- enforce state, lease version and optimistic draft revision;
- keep transactions short;
- record content-free audit events.

Browser roles receive no direct insert/update/delete grant on consultation content.

Relationship revocation invalidates the lease and technically cancels every `scheduled`, `in_progress` or `paused` draft. Reactivation never reopens it. The only post-revocation mutation exception is the approved ownership-only cleanup for a system-cancelled, never-finalized/unpublished draft. It uses a one-purpose cleanup lease and may only hard-discard content into the independent minimal tombstone; it cannot edit, restart, finalize, add an addendum, publish or attach. V1 has no automatic time-based retention.

### Draft concurrency

Use a database-backed expiring editing lease plus optimistic `draft_revision`, not PostgreSQL advisory locks and not browser last-write-wins.

The lease supports explicit audited takeover and invalidates the prior session. Autosave debounce is 1.2 seconds, heartbeat is every 20 seconds and lease expiry is 60 seconds without an accepted heartbeat. Conflicts never silently overwrite data. Sensitive drafts remain online-first and are not added to `localStorage`, IndexedDB or the current offline queue.

### Calculation model

Use a curated immutable formula/protocol registry. Every result stores method ID/version, sources, raw inputs/units, physiological reference branch, eligibility, output, limitations and override reason.

Gender identity is separate from any source-required physiological parameter. The UI label is **“Referência fisiológica exigida pelo método”** with `referência masculina`, `referência feminina` and `não informar`. It appears only for a method that requires it, remains private and calculation-scoped, is never inferred from name, appearance or gender identity, and declining it makes only that formula ineligible. Historical results are never silently recalculated.

The approved initial categories are BMI, waist-to-hip ratio, waist-to-height ratio, resting metabolism estimate, total energy expenditure estimate, population hydration reference, skinfold/body-density protocols, estimated body-fat percentage, fat mass, fat-free mass, manual bioimpedance observations and reassessment comparison. Exact coefficients and algorithm versions remain subject to primary-source formula review and synthetic tests; no result is a diagnosis.

Raw calculation and device-observation evidence is never a client or cross-professional DTO. Immutable safe projections apply an unconditional denylist for physiological/device branch and selection provenance, private raw inputs/conditions, internal eligibility/exclusions, override reason and internal IDs/hashes. No publish/share flag may bypass it. Manual BIA uses a separate selected-metric safe projection.

### Attachment model

Use a private Storage bucket with relational authorization metadata and exact per-attachment publication/share records. Allow JPEG, PNG and WebP up to 10 MB each and PDF up to 15 MB, with at most 20 attachments per consultation. Validate size, extension, detected MIME, file signature and checksum; quarantine files until validation. Generate signed access for no more than five minutes only after database authorization. Never use public URLs or object overwrite for finalized evidence; replacement creates a new version. Production attachment publication remains blocked until an approved malware-scanning strategy exists.

Professional attachment sharing uses a dedicated exact-recipient attachment-share relation. It is never inferred from organization role, a whole consultation or client publication.

### Reminders and attendance

Support internal FORJA reminders 24 hours and 1 hour before the appointment and linked-client attendance confirm/decline as schedule metadata separate from consultation lifecycle and publication acknowledgement. Store schedule revision + instant + IANA zone + original offset. A response must target the current revision; rescheduling retires the old current response, rebuilds undelivered reminders atomically and preserves history. Cancellation, consultation start or no-show cancels pending reminders. Client refusal does not automatically cancel the consultation. Production scheduler activation remains a separate checkpoint and deployment approval.

### Sharing and client publication

The approved common projection is limited to authorized goals, routine, activity, sleep, hydration, basic weight history, measurements, evolution and general declared physical limitations. Medications, clinical conditions, detailed allergies, detailed food history, formula physiology parameters, internal notes, attachments, photos, raw bioimpedance data and profession-specific sections remain private unless explicitly shared.

Each consultation belongs to its author. Only the author may edit, finalize, publish, cancel or add an addendum. Other professionals receive authorized immutable projections only.

Finalization does not publish automatically. Publication is an explicit field/attachment-selective operation with a confirmation screen. Every version is immutable; replaced versions remain in client history. Withdrawal hides a version from the client but preserves internal audit, acknowledgement and comments.

Client acknowledgement uses **“Confirmar recebimento”** and means receipt only, not approval, agreement or signature. A publication accepts at most five permanent, non-editable comments of at most 1,000 characters each. Corrections require a new comment; v1 has no threaded chat.

## Why this decision

The model balances queryability and historical integrity:

- relational columns make ownership, lifecycle, RLS and comparisons enforceable;
- raw readings remain addressable and testable;
- snapshots preserve exactly what was finalized or published;
- explicit projections prevent field/JSON leakage;
- stable subject IDs permit future account linking;
- the design reuses current FORJA relationship and snapshot patterns without forcing consultation data into plan assignments.

## Alternatives considered

### One JSON consultation row

Rejected.

It would simplify draft writes, but field-level sharing, RLS projections, raw-reading constraints, attachment authorization and targeted comparisons would become fragile. Row-level RLS cannot safely hide arbitrary fields inside a payload from different actors.

### Fully normalized records without snapshots

Rejected.

It would make current-state queries straightforward but would not reliably preserve the exact interpretation, field-definition version, formula limitations or publication content at finalization time.

### Event sourcing as the source of truth

Rejected for v1.

Event sourcing could model every change, but it adds replay, migration, projection and privacy-erasure complexity disproportionate to the module. FORJA needs an audit trail, not a generalized event-sourced clinical platform.

### Reuse workout/nutrition assignment tables

Rejected.

Assignments model professional publication of a plan. They do not model consultation drafts, multiple professions, common/private fields, measurements, acknowledgements or editing leases. Reuse their immutable snapshot techniques, not their entities or participant-wide read policy.

### Collaborative live document

Rejected.

The approved product model has one author and one active editor. Real-time multi-user editing would weaken ownership semantics and add conflict complexity without a v1 need.

### Browser-first/offline draft

Rejected for v1.

The current browser queue stores module snapshots and lacks lease, revision, publication and sensitive-data controls. Durable offline consultation records need a separate encrypted cache and erasure design.

### Organization as the tenant owner

Rejected.

The current relationship metadata may be visible to organization admins, but consultation content belongs to its author/subject security domain. Automatic organization access would violate private-by-default professional sections.

## Consequences

### Positive

- immutable, explainable professional history;
- precise actor and field visibility;
- deterministic concurrency behavior;
- safe future subject/account linking;
- clear formula provenance and non-diagnostic boundaries;
- per-attachment privacy and publication;
- compatibility with existing FORJA RPC/RLS patterns.

### Costs

- more entities and migrations than a JSON-only draft;
- projection RPCs are required for common, shared and client views;
- finalization needs canonical serialization and hash tests;
- field definitions, measurement protocols and formulas require disciplined versioning;
- private Storage requires a new policy and validation contract;
- offline draft support remains deferred.
- internal reminder delivery requires a reviewed scheduler and time-zone test matrix.

### Risks to manage

- relationship-scope migration must not let the existing default-scope trigger erase new scopes;
- cross-professional history requires a precise allowlist and privacy disclosure;
- lease token replay and stale takeovers require adversarial tests;
- a mutable publication pointer must not mutate historical client content;
- signed URLs cannot retract an already downloaded file;
- formula population limits, especially Brazilian applicability, must be visible;
- client acknowledgement must never be represented as legal consent/signature.

## Implementation constraints

1. Implement in checkpoints A.2A through A.2I from the [V4.3A.2 plan](../superpowers/plans/2026-07-25-v4.3a2-consultation-foundation.md).
2. Use local migration tests and synthetic calculation fixtures before implementation code.
3. No remote migration or production action without separate explicit approval.
4. No client publication or cross-professional content read until actor-matrix tests pass.
5. No attachment upload until private Storage policies and validation tests pass.
6. Do not change the current Diet module as a side effect.
7. Before remote migration or real-data use, require privacy/LGPD review, complete RLS and multi-actor authorization tests, formula review, retention policy, attachment-security approval, explicit migration approval and explicit deployment approval.

## Remaining gates

The product and security guardrails recorded above are approved. The remaining gates are narrower:

- Before A.2B: identify who may activate `manage_consultations` and define the exact audited activation workflow.
- Before A.2E: approve exact algorithms, primary-source versions, coefficients, populations, exclusions and recommendation order. The calculation families and physiological-reference UI contract are already approved.
- Before A.2G: define the exact attendance-response cutoff. Production scheduling jobs remain a separate checkpoint.
- Before production/real data: complete privacy/LGPD and retention/export/deletion review; v1 has no automatic time-based retention.
- Before production attachment publication: approve malware scanning, retention and final report/PDF composition, watermark/footer and renderer evidence.
- Before any remote migration or deployment: obtain separate explicit approvals after all required local matrices and reviews pass.

A.2A is product-guardrail ready for local TDD after this design is reviewed and merged. It is not authorization to implement, migrate remotely, use real data or deploy.

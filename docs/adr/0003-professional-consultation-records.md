# ADR 0003: Professional consultation records

- Status: Proposed for V4.3A.2
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
- the author owns and exclusively edits the record;
- organization is context/provenance only;
- organization owner/admin status does not grant consultation content;
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

The only post-revocation mutation exception is the approved ownership-only retention cleanup for a system-cancelled, never-finalized/unpublished draft. It uses a one-purpose cleanup lease and may only hard-discard content into the independent tombstone; it cannot edit, restart, finalize, add an addendum, publish or attach.

### Draft concurrency

Use a database-backed expiring editing lease plus optimistic `draft_revision`, not PostgreSQL advisory locks and not browser last-write-wins.

The lease supports explicit takeover and invalidates the prior session. Sensitive drafts remain online-first and are not added to the current `localStorage`/`SyncQueue`.

### Calculation model

Use a curated immutable formula/protocol registry. Every result stores method ID/version, sources, raw inputs/units, physiological reference branch, eligibility, output, limitations and override reason.

Gender identity is separate from any source-required physiological parameter. Historical results are never silently recalculated.

Raw calculation and device-observation evidence is never a client or cross-professional DTO. Immutable safe projections apply an unconditional denylist for physiological/device branch and selection provenance, private raw inputs/conditions, internal eligibility/exclusions, override reason and internal IDs/hashes. No publish/share flag may bypass it. Manual BIA uses a separate selected-metric safe projection.

### Attachment model

Use a private Storage bucket with relational authorization metadata and exact per-attachment publication/share records. Generate short-lived access only after database authorization. Never use public URLs or object overwrite for finalized evidence.

Professional attachment sharing uses a dedicated exact-recipient attachment-share relation. It is never inferred from organization role, a whole consultation or client publication.

### Reminders and attendance

Support internal FORJA reminders and linked-client attendance confirm/decline as schedule metadata separate from consultation lifecycle and publication acknowledgement. Store schedule revision + instant + IANA zone + original offset. A response must target the current revision; rescheduling retires the old current response, rebuilds undelivered reminders atomically and preserves history. Production scheduler activation remains a separate deployment approval.

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

## Approval gates

Before A.2A/A.2B:

- common-field allowlist and consent/disclosure;
- client-owned grant/revoke path for common-history consent and disclosure version;
- `manage_consultations` default/activation for existing and new relationships;
- relationship scope defaults and revocation behavior;
- draft discard/retention;
- organization-admin no-content rule.

Before A.2E:

- initial formula allowlist, priority and physiological parameter wording;
- Brazilian applicability of energy and body-composition methods.

Before A.2G/A.2H:

- publication withdrawal, comments and acknowledgement semantics;
- internal reminder lead times, attendance wording and production scheduler;
- attachment types, limits, scanning, signed-URL lifetime and retention.

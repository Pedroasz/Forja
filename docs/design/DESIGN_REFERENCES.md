# FORJA — Design Reference Library

## Goal

Use open-source product repositories as reference to remove the generic "AI-generated SaaS dashboard" appearance from FORJA.

The objective is **not** to clone another product. Study interaction, hierarchy, density, navigation, data presentation and state design, then translate the principles into a FORJA-specific visual language.

## Anti-AI design rules

Avoid:
- default shadcn-looking dashboard composition;
- card-inside-card-inside-card layouts;
- excessive 16–24px rounded rectangles;
- glassmorphism;
- glowing gradients;
- random purple/blue accent gradients;
- oversized hero text inside product screens;
- generic sparkle/robot icons;
- every metric inside an isolated card;
- excessive whitespace that reduces information density;
- generic "AI copy" in empty states;
- animations with no functional meaning.

Prefer:
- strong alignment and consistent grid;
- clear Page → Section → Group → Field hierarchy;
- contextual separators before containers;
- flat information surfaces where possible;
- restrained radius (FORJA target: 6–10px);
- high-density professional layouts on desktop;
- deliberate mobile reflow;
- numbers and performance data with strong typographic hierarchy;
- color used semantically, not decoratively;
- domain-specific training, calendar, challenge and performance patterns;
- visible state and provenance rather than decorative UI.

## Reference repositories

### Tier A — preferred implementation/design references

#### 1. Cal.com / cal.diy
Repository: https://github.com/calcom/cal.diy
License checked: MIT.

Use for:
- calendar/scheduling information architecture;
- compact filters and date navigation;
- event creation flows;
- side navigation;
- modal/drawer composition;
- dense workspace patterns.

FORJA application:
- unified calendar;
- consultation scheduling;
- training event views;
- challenge/event date navigation.

Do not copy branding. Adapt interaction logic and density.

#### 2. Umami
Repository: https://github.com/umami-software/umami
License checked: MIT.

Use for:
- analytics hierarchy;
- restrained dashboards;
- charts without decorative clutter;
- metric grouping;
- filters/date ranges.

FORJA application:
- training performance;
- evolution;
- challenge analytics;
- professional summaries.

#### 3. Radix Themes
Repository: https://github.com/radix-ui/themes
License checked: MIT.

Use for:
- accessibility/state conventions;
- spacing/radius discipline;
- focus/hover/disabled treatment;
- foundational component behavior.

FORJA rule:
Do not inherit the default visual theme wholesale. Use primitives/conventions while keeping FORJA tokens.

#### 4. Mantine
Repository: https://github.com/mantinedev/mantine
License checked: MIT.

Use for:
- form ergonomics;
- complex input states;
- overlays;
- menus/selects;
- responsive composition.

FORJA application:
- professional consultation editor;
- measurements;
- filters;
- settings.

#### 5. Tremor
Repository: https://github.com/tremorlabs/tremor
License checked: Apache-2.0.

Use for:
- data visualization patterns;
- compact KPI composition;
- table/chart relationships;
- dashboard information density.

FORJA application:
- performance and challenge dashboards.

### Tier B — visual/product references only unless license/scope is rechecked before code reuse

#### Dub
Repository: https://github.com/dubinc/dub
License checked: mostly AGPLv3 with enterprise exceptions.

Study:
- polished SaaS navigation;
- dense dashboard;
- command/menu patterns;
- metric presentation.

Do not copy AGPL/enterprise code into FORJA without a deliberate license decision.

#### Twenty
Repository: https://github.com/twentyhq/twenty
License checked: mostly AGPLv3; selected SDK/UI packages are MIT.

Study:
- CRM-like information density;
- records/details split;
- keyboard-oriented interactions;
- list/detail navigation.

Before code reuse, verify that the exact source package/file is MIT.

#### Plane
Repository: https://github.com/makeplane/plane
License checked: AGPLv3.

Study:
- complex workspace navigation;
- filters;
- command surfaces;
- multi-state work items.

Reference-only by default.

#### OpenStatus
Repository: https://github.com/openstatusHQ/openstatus
License checked: AGPLv3.

Study:
- modern dark data UI;
- status/metric hierarchy;
- compact operational screens.

Reference-only by default.

#### Midday
Repository: https://github.com/midday-ai/midday
License checked: AGPLv3.

Study:
- premium dark/light product polish;
- spacing;
- navigation;
- restrained visual density.

Reference-only by default.

#### Formbricks
Repository: https://github.com/formbricks/formbricks
License checked: mixed; main app largely AGPLv3 with some MIT packages.

Study:
- form builder/workflow UX;
- surveys/structured inputs;
- settings architecture.

Reference-only unless the exact package license is verified.

## Component libraries: warning

### shadcn/ui
Repository: https://github.com/shadcn-ui/ui
License checked: MIT.

It is useful for implementation primitives and accessibility patterns, but **must not define the FORJA visual identity**.

A default shadcn dashboard is one of the visual patterns commonly associated with AI-generated prototypes.

Rule:
- use primitives selectively;
- replace default colors, spacing, radius, typography and composition;
- never paste a generated block unchanged into FORJA.

## FORJA design synthesis

Target feeling:

**Performance software + professional assessment + sports community.**

Not:
- generic SaaS admin;
- crypto dashboard;
- AI chatbot;
- gaming HUD;
- social-media clone.

### Visual DNA

- dark neutral technical foundation;
- orange = primary action/brand;
- green = completed/saved/success;
- blue = information;
- yellow = warning/pending;
- red = destructive/error;
- off-white primary text;
- restrained surfaces;
- numerical metrics may use mono typography;
- 6–10px radii;
- visible borders/separators;
- semantic iconography;
- minimal decorative gradients.

### Product-specific signatures

The following should make the interface recognizably FORJA:

1. Performance strip
   - current week;
   - adherence;
   - training volume;
   - next event;
   - challenge position.

2. Unified performance calendar
   - training;
   - consultations;
   - events;
   - challenges;
   - milestones.

3. Activity timeline
   - domain-specific workout/performance events;
   - not generic social post cards.

4. Challenge board
   - current challenge;
   - progress;
   - ranking;
   - transparent scoring rule;
   - event ledger.

5. Professional assessment workspace
   - client list;
   - central editor;
   - sticky status/summary;
   - dense measurement rows;
   - provenance/validation states.

6. Achievement language
   - understated, performance-oriented;
   - avoid casino/gamified neon.

## Design review workflow

For any major visual checkpoint:

1. Read this document and FORJA design tokens.
2. Select no more than 2–3 reference repositories relevant to the screen.
3. Identify patterns, not screenshots to clone.
4. Produce FORJA-specific wireframe/concept.
5. Check against anti-AI rules.
6. Validate desktop and mobile.
7. Verify keyboard/focus/contrast.
8. Only then implement.

## Licensing rule

Reference/inspiration is allowed.

Before copying actual source code:
- identify exact file/package;
- verify its current license;
- preserve required notices/attribution;
- avoid AGPL/enterprise code unless the project deliberately accepts those obligations.

When uncertain, reimplement the interaction/pattern from first principles instead of copying code.

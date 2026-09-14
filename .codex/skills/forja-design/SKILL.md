---
name: forja-design
description: Use for any FORJA visual design, frontend UI architecture, UX refinement, calendar/social/challenge screens, or when removing generic AI-generated SaaS aesthetics.
---

# FORJA Design

Read:
1. `AGENTS.md`
2. `docs/agents/FORJA_RULES.md`
3. `docs/design/DESIGN_REFERENCES.md`
4. the current product/checkpoint spec

For creative/new feature design, use the environment's brainstorming skill when available before implementation.

## Process

1. Define the user task and information hierarchy.
2. Choose at most 2–3 relevant reference repositories from DESIGN_REFERENCES.
3. Extract patterns:
   - navigation;
   - density;
   - grouping;
   - data display;
   - states;
   - responsive behavior.
4. Translate them into FORJA-specific composition.
5. Apply FORJA tokens and anti-AI rules.
6. Avoid copying screens wholesale.
7. Produce a concept/wireframe or implementation plan before changing the monolithic frontend when the checkpoint requires design approval.
8. During implementation, verify rendered output in browser and mobile widths.

## Anti-AI checklist

Reject a design if it relies on:
- generic shadcn default styling;
- gradient/glow decoration;
- excessive rounded cards;
- huge empty padding;
- random purple/blue accents;
- sparkle/robot iconography;
- filler marketing copy inside product screens;
- repeated identical card grids without hierarchy.

Prefer:
- domain-specific performance/calendar/challenge UI;
- strong typography;
- separators and alignment;
- restrained color;
- compact desktop density;
- precise states;
- real data structure;
- meaningful interaction feedback.

## License boundary

Use external repositories as references.
Before copying code, verify the exact package/file license.
AGPL/enterprise sources are reference-only by default.

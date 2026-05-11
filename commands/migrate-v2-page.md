---
description: Orchestrate migration of a legacy admin page to V2 (shadcn/Tailwind/TanStack). Master coordinator pattern — delegates plan + execution to isolated worktree workers.
---

# /migrate-v2-page

You are a master coordinator migrating a legacy page to V2. Always delegate to workers, except for first-step discovery.

**Usage:** `/migrate-v2-page <legacy-page-route-or-path>`

Example: `/migrate-v2-page /admin/ai_agent/training`

---

## Core rules

- New work always lands in `app/frontend/v2/` (NOT `client/`).
- Worktrees created from main via `claude-coord <slug>`. Rebase worktrees if main moved.
- `claude-coord` slug constraints: alphanumerics + `_.-` only. **No `/`** (claude-msg target regex rejects it). Use prefix-with-dash like `manoel-<slug>`.
- Each new claude-coord session needs `/caveman:caveman full` activated BEFORE the first task brief.
- Each worker brief MUST include the compaction-survival block + reporting block (see tmux-supervisor skill).

---

## Phase 0 — Identify tasks

Read the page from `client/pages/.../*.tsx` directly. Determine entities:
- 1 task per management page.
- If page has multiple managed entities (e.g. tabs), 1 task per entity + 1 task for the root shell.
- Root depends on children (or vice-versa — decide based on architecture; for tab shells, root owns routes/layout and children plug in).

Seed minimal `thoughts/plans/<slug>/plan.md` per task:
```md
# <Page> Migration
**Page:** <route>
**Legacy location:** <path>
**V2 target:** app/frontend/v2/pages/...
Brief: <1-2 sentences>
```

Use TaskCreate to track each plan. Add `addBlockedBy` for dependent plans.

---

## Phase 1 — Plan-investigation coordinators (parallel, but root first if root is the shell)

**Goal:** capture functionality, not pixels. Hidden state (selects, modals, heterogeneous row rendering, conditional branches) is the #1 failure mode. Use **three evidence channels** below — each catches what the others miss.

For each page, spawn a `plan-investigation-coordinator` session:

```bash
claude-coord manoel-<slug>
```

Then `/caveman:caveman full` + dispatch brief:

```
[plan-investigation-coordinator | <slug>]

Isolated worktree: manoel-<slug>. Report to <supervisor-target>. Use claude-msg via Bash ONLY.

Reporting:
  cat > /tmp/<slug>-msg.txt <<'EOF_MSG'
  [<slug>] <message>
  EOF_MSG
  claude-msg "<supervisor-target>" --read-file /tmp/<slug>-msg.txt

Compaction survival: write this brief to /tmp/<slug>-brief.md. Reread before each sub-task.

Rebase: git fetch origin && git rebase origin/main

Dev server: <URL>. If not running, ping coord — DO NOT start it.

## Three-channel evidence model

You MUST gather all three channels before declaring plan done. Channel gaps = plan rejected.

### Channel 1: Source-dig (code truth)

Trace EVERY component rendered on legacy page recursively. For each component, plan must include block:

```
### <ComponentName> (<file>:<line-range>)
Props: { ... }
Renders:
  - <child or element>   ← inline conditions, ternaries, maps
Conditionals: every {x && ...} / ternary / switch — enumerate each branch + what shows
Helpers/maps referenced: iconForType, typeLabel, formatX — INLINE the map contents, no "see source"
i18n keys: full list
Event handlers: onClick/onChange → what they call + what state changes
Heterogeneous data: if any prop has discriminator (type, kind, role, ...), enumerate ALL observed values + per-value rendering
```

Rule: every `&&` / ternary / `switch` in source = 1 line in plan. Every map/dict helper = inlined contents. No hand-waves.

### Channel 2: Interaction tree (UX truth)

Use agent-browser (session <slug>) to CLICK EVERYTHING. Document reveal-on-trigger states. Closed dropdowns are NOT documented — open them.

Format (nested):
```
- "<Trigger label>" <button|link|row> → <opens sheet|dialog|dropdown|navigates>
  - <revealed surface> contains:
    - <field|input|list> → <what typing/clicking does>
      - result rows: [<anatomy: icon? title? meta? type-suffix?>]
      - row types observed: <type1> (icon: <X>, label: <Y>), <type2> ...
  - submit/cancel/delete → <effect, toast, navigation>
- "Edit" row action → ...
- Empty state when no items → shows: ...
- Loading state → ...
- Error state → ...
```

Trigger-every-dropdown rule: every <Select>, combobox, autocomplete, search-result list MUST be opened + its option/row anatomy documented.

### Channel 3: SoM screenshots (visual truth)

For each interactive surface (page, sheet, dialog, dropdown-open, empty state, error state):
1. Take baseline screenshot → thoughts/plans/<slug>/legacy-<state>.png
2. Inject numbered red boxes on every clickable/visible element using agent-browser evaluate:
   ```js
   document.querySelectorAll('button, a, input, [role="button"], [role="option"], li, .clickable').forEach((el, i) => {
     const r = el.getBoundingClientRect()
     const box = document.createElement('div')
     box.style.cssText = `position:fixed;left:${r.left}px;top:${r.top}px;width:${r.width}px;height:${r.height}px;border:2px solid red;z-index:99999;pointer-events:none`
     box.innerHTML = `<span style="background:red;color:white;padding:2px 4px;font:12px monospace">${i}</span>`
     document.body.appendChild(box)
   })
   ```
3. Second screenshot → thoughts/plans/<slug>/legacy-<state>-som.png
4. Reference elements by SoM number throughout plan. No "the search thing on left."

### Coverage check (forcing function)

Plan MUST end with reconciliation table:

```
## Coverage check
| SoM # | Element              | Source ref            | Interaction              | Preserve in V2 (Phase 2) |
|-------|----------------------|-----------------------|--------------------------|--------------------------|
| 1     | New Exclusion btn    | ExclusionsPage.tsx:34 | opens AddExclusionSheet  | pending                  |
| 2     | Search input         | AddSheet.tsx:21       | filter results live      | pending                  |
| 3     | Result row (Wiki)    | ResultRow.tsx:42      | click → add to selection | pending                  |
| ...   |                      |                       |                          |                          |
```

Any SoM number lacking source ref OR interaction entry → plan incomplete. Self-block.

## Tasks

1. Read legacy <path>. Run Channel 1 source-dig recursively. Inline all maps/helpers/i18n keys.
2. Run Channel 2 interaction tree via agent-browser. Click every trigger. Open every dropdown.
3. Run Channel 3 SoM screenshots for every interactive surface. Save baseline + SoM pair.
4. Build Coverage check table. Verify no gaps.
5. Do NOT yet specify the new V2 pattern.

Gated: push, branch rename, deletions outside thoughts/plans/<slug>/.

DONE with: source-dig block count, interaction-tree depth, SoM screenshot paths, coverage table row count, any gaps flagged.
```

Start dev server in your supervisor worktree via `bin/start-dev-server.sh` if not already running, then pass the URL to workers.

Wait for all DONEs.

---

## Phase 2 — V2 pattern investigation (parallel)

Send each existing worker a follow-up brief:

```
Required reading:
- ai_plans/frontend_v2/shadcn_migration.md  ← canonical V2 stack doc
- app/frontend/AGENTS.md
- app/frontend/v2/App.tsx + app/frontend/v2/routes/ + closest precedent page (BannersPage, GoLinksPage, PersonasPage, etc.)
- app/frontend/v2/components/

Extend plan.md with:
1. V2 file layout (exact paths). Pages PascalCase + Page suffix; components/hooks/resources kebab-case. Feature code in features/<area>/, NOT components/.
2. **Source-to-V2 mapping table.** For each Channel 1 source-dig block from Phase 1, add a row:
   ```
   | Legacy component | V2 component (path)   | Branches preserved | Helpers/maps ported | Heterogeneous types covered |
   ```
   Every conditional branch / helper map / type discriminator from Channel 1 MUST appear here. If V2 collapses to fewer branches, EXPLICIT justification line required.
3. **Fill Coverage check table.** Update the Phase 1 Coverage table — set "Preserve in V2" column for every SoM #. Any row still "pending" = plan incomplete.
4. Reuse vs create. For each preserved functionality, mark [reuse: X] / [new: X] / [Phase X placeholder].
5. E2E test plan: Vitest + renderAppRoute + MSW. Detailed scenarios. Payload-shape assertions on mutations (snake_case keys). MUST include assertions for heterogeneous row rendering (per-type icon + type label suffix etc.) if Channel 1 documented any.
6. Screenshot proof plan: agent-browser per page state, output tmp/e2e/<slug>/, attached via /attach-pr-screenshots.
7. CI monitor: final impl step invokes /spawn-commit-review-monitor.
8. Migration sequencing + dependencies on other plans.

Constraints:
- ALL new code in app/frontend/v2/ — never client/.
- snake_case throughout V2 — NO axios case conversion in V2 (differs from legacy CLAUDE.md rule).
- route()/routes() from @/lib/access-control for routes + permission gating (NOT raw <Route>).
- Resource modules export xxxApi/xxxKeys/xxxQueries(/prefetchXxxDetail).
- useConfirm (not inline AlertDialog) for confirm dialogs.
- useUnsavedChanges for dirty-form guards.
- sonner toasts.
- shadcn semantic tokens (text-foreground/bg-accent/etc.) — no raw CSS vars.
```

Wait for all DONEs.

---

## Phase 2.1 — Final cross-plan review

You (the supervisor) review all enhanced plans for:
- Duplicate components proposed across plans → extract into a 5th shared plan OR fold into the root-shell plan.
- Architectural conflicts (e.g. different routing patterns) → pick one + dispatch adjustment briefs.
- Case-convention divergences → confirm snake_case wins.

If shared components belong in V2 styleguide, document under `app/frontend/v2/pages/styleguide/` (or follow current styleguide convention).

Dispatch adjustment briefs to affected workers. Wait for revised plans.

---

## Phase 2.5 — Critique each plan

Dispatch to each worker:

```
Run /tmux-critique-plan against your thoughts/plans/<slug>/plan.md. Apply genuinely useful critiques. Skip those that conflict with canonical V2 doc or coord decisions.

Add at bottom of plan.md:
## Critiques Applied
## Critiques Rejected (with 1-line reason each)

DONE with: applied count, rejected count, top 2 improvements.
```

Worker may fall back to streamlined self-critique if `/tmux-critique-plan` infra (devpipe personas) isn't available.

---

## Phase 3 — Execution (fresh coord sessions)

Sequencing rule for tab-shell migrations: **root MUST land first**. Children rebase onto root branch, not main.

Spawn root executor:
```bash
claude-coord exec-<slug>-root
```

Brief: implement plan, replace placeholder pages with `<ComingSoon />` so shell is testable standalone. typecheck + vitest + biome locally. Manual browser verify. Capture screenshots. Branch `manoel/<slug>-shell`. Push + PR + `/spawn-commit-review-monitor`.

**Pre-PR self-walkthrough (mandatory).** Before opening PR, executor MUST:
1. Reread Phase 1 Coverage check table from plan.
2. Open V2 in browser. Walk every SoM # row end-to-end. Click every trigger documented in interaction tree.
3. For every heterogeneous row rendering documented in Channel 1 (per-type icon, type label, etc.) — verify present in V2.
4. Take v2-<state>.png paired with each legacy-<state>.png from Phase 1.
5. DONE message MUST include: coverage table with all rows checked, paired screenshot list, one-line "intentional diffs vs legacy: ..." (empty list OK only if truly identical).

Supervisor blocks PR if walkthrough output missing or any Coverage row unchecked.

Once root PR open:
```bash
claude-coord exec-<slug>-<child>   # per child
```

Each child brief MUST rebase onto root branch:
```bash
git fetch origin && git rebase origin/manoel/<slug>-shell
```

Child branch: `manoel/<slug>-<child>-page`. PR base=main, body notes "Depends on #<root-PR>".

Each PR MUST include a screencast per PULL_REQUEST_TEMPLATE.md. Dispatch `/record-browser-screencast` to each executor after PR open (or include in the same brief). Attach mp4 URL to PR body under "Screencasts" section.

---

## Gotchas learned

- `thoughts/` is gitignored (humanlayer pattern). Screenshots + plan files live outside git on this branch — no commit needed.
- Worktree dev servers auto-select slot (3001+). Each executor can run its own without conflict.
- `route()` / `routes()` from `@/lib/access-control` do NOT support nested children with Outlet. Use hand-rolled `RouteObject[]` (mirror `ticketing.tsx`) for parent-with-children layouts.
- `paginationFromHeaders` is page-based; if backend emits cursor headers (Next-Cursor/Prev-Cursor), write a custom extractor mirroring `versions.ts`.
- Legacy axios bridges camelCase↔snake_case. V2 does NOT. Plans must explicitly call out snake_case in types + payloads + test assertions.
- `i18n` in V2: inline English in new components is acceptable; don't port legacy `views.admin.ai.training.*` keys unless the canonical V2 doc says so.
- Optimistic updates for inline toggles (active/enabled) — without them V2 feels slower than legacy.

---

## Final wrap-up

When all PRs up + screencasts attached + CI green: post final table to user with PR numbers, branches, merge order, follow-ups (Phase X placeholders, cleanup tickets like `CA-TODO-<slug>-cleanup` to flip legacy → V2 redirect).

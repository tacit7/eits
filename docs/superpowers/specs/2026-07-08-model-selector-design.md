# Unified Model Selector — Design Spec

**Date:** 2026-07-08 (revised twice same day after two design review rounds)
**Status:** Approved for implementation
**Scope:** Replace all three EITS model-picking surfaces with one shared component; refresh the Claude/Codex model catalog (display + validation) to the current lineup.

## 1. Goal

EITS has three separately-built model pickers today:

1. **Composer mid-chat switcher** (`message_composer.ex:216-279`) — plain DaisyUI dropdown, Claude/Codex only (no Pi branch), no search, no grouping, no active-checkmark, no cost indicator.
2. **New Agent drawer** (`new_agent_drawer.ex`) — flat triple-optgroup `<select>`, all providers rendered at once, no provider→model reactivity.
3. **New Session modal** (`new_session_modal.ex`) — has `phx-change` provider→model cascading, but still a bare native `<select>`.

All three get replaced by one shared `ModelSelector` component modeled on claudette's searchable, grouped, badge-annotated popover (reference screenshots: claudette's `ModelSelector` popover; two terminal screenshots of the actual current Claude/Codex model lineups available to this account).

Separately, the screenshots reveal `model_helpers.ex` and `scripts/eits`'s Claude catalogs are stale (missing the current Claude 5 family — Opus 4.8, Fable 5, Sonnet 5, Haiku 4.5 — and still validating against `claude-opus-4-7`-era slugs). This refresh ships as part of the same work, since a new picker showing unusable models would be worse than the one it replaces.

## 2. Reference Material

- Claudette's `ComposerToolbar.tsx`/`ModelSelector.tsx` (design description supplied by user; screenshot `~/screen/1783513358.jpg` — live popover: search box, grouped sections with "via Pi" badges, active-row checkmark, `$` icon on a billed 1M variant, "More" disclosure, per-Pi-sub-provider "Show all N").
- `~/screen/1783517089.jpg` — current Codex model list for this account: `gpt-5.5 (current)`, `gpt-5.4`, `gpt-5.4-mini` (display names only — full valid slug set per `scripts/eits agents spawn --help` also includes `gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.3-codex, gpt-5.2`, which become the "legacy" tier).
- `~/screen/1783517112.jpg` — current Claude model list: `Default (Recommended)`, `Opus` (Opus 4.8, 1M context), `Fable` (Fable 5 — most capable), `Sonnet` (Sonnet 5), `Haiku` (Haiku 4.5), plus a `sonnet-4-6 ✓ Custom model` row showing the currently-active session's model, which isn't in the curated list at all.

## 3. Explicitly Out of Scope

- **Free-text custom model entry.** The Claude screenshot's `sonnet-4-6 Custom model` row proves the underlying CLI allows arbitrary slugs, but this selector does not add a text-entry affordance. If a session's current model isn't in any known list (curated or Pi-discovered), the selector still shows and checks it as the active row (existing "always show current selection" rule) — it just can't be typed in fresh.
- Pi OAuth, editing model metadata from the UI.
- Changes to server-side spawn validation *behavior* — `ModelConfig`/`SpawnValidator` keep the same validation logic, only their static slug lists are refreshed (§6).

## 4. Data Layer

### 4.1 New struct (additive — no existing function signatures change)

```elixir
defmodule EyeInTheSky.ModelEntry do
  @moduledoc "Unified model metadata for the shared model selector."
  defstruct [:provider, :slug, :label, :group, :sub_provider,
             premium?: false, legacy?: false, default?: false]

  @type t :: %__MODULE__{
          provider: String.t(),
          slug: String.t(),
          label: String.t(),
          group: String.t(),
          sub_provider: String.t() | nil,
          premium?: boolean(),
          legacy?: boolean(),
          default?: boolean()
        }
end
```

`provider` is carried explicitly on every entry rather than inferred from section context — the row-badge rule (§5.1) and the emitted selection payload (§5.2) both read it directly, so nothing downstream has to guess a row's actual provider from which section it's rendered under.

### 4.2 `ModelHelpers.entries_for_provider/1` (new function, additive)

**`premium?` naming note:** renamed from an earlier `billed?` — the field means *"shown with a `$` marker as an incremental-cost/premium variant,"* not *"this is the only model here that costs money."* Nearly every non-local model call costs something; `premium?` flags the specific rows worth calling out (1M-context Claude variants, non-local Pi routes), it is not a claim that everything else is free.

- `"claude"` → static list built from the refreshed catalog (§6.1). `provider: "claude"`, `group: "Claude Code"`, `sub_provider: nil`. `premium?` true for an **explicitly enumerated alias set** (`opus[1m]`, `sonnet[1m]`, and their full-slug equivalents) — not fragile substring matching on `"1m"`, which risks false positives against unrelated slugs that happen to contain that text. `legacy?` true for anything not in the current-generation set (Opus 4.7-and-older, Sonnet 4.6-and-older, etc.). `default?` true for the `default` alias row — see the important nuance below.
- `"codex"` → static list, same shape. `provider: "codex"`, `group: "Codex"`. `premium?: false` always. `legacy?` true for `gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.3-codex, gpt-5.2`; primary/non-legacy = `gpt-5.5, gpt-5.4, gpt-5.4-mini`. `default?` on `gpt-5.5`.
- `"pi"` → reads `Pi.ModelDiscoveryCache.get_cached/0` **directly** (not the lossy `pi_models/0`, which discards the `"provider"` sub-provider key). Each discovered model's `"provider"` field becomes `sub_provider` (e.g. `"ollama-lan"`), and the entry's own `provider` field is `"pi"`; `group` is a display-cased version of `sub_provider` (e.g. could special-case `"ollama"`/`"ollama-lan"` to a friendlier "Ollama (LAN)" label, exact mapping left to the implementation plan). **`premium?` heuristic, stated as a heuristic, not a guarantee**: default to `sub_provider` not starting with `"ollama"` *only* if the discovery payload carries no better cost signal; if `Pi.ModelDiscoveryCache`'s discovered model map ever exposes real cost/billing metadata (check at implementation time — the harness may add this later), prefer that over the sub-provider-name heuristic. Wrong `$` badges erode trust fast; the implementation plan should re-verify this against whatever `Pi.Control.discover_models/0` actually returns before shipping. `legacy?: false` (no legacy concept for discovered models — they're either present or not). `default?: false`.

**`default?`/"Default" nuance:** `default` is a *selectable alias*, not a stable concrete model. Anthropic's own Claude Code `default` value can resolve to different underlying models depending on account, organization policy, and provider — it is not guaranteed to always mean "Opus 4.8" or any other fixed slug. The picker must not imply otherwise: the `default?: true` row is labeled "Default" with a small "Recommended" badge and a short description ("uses account/org default"), never a specific model name baked into the label. Do not resolve `default` to a concrete slug at catalog-build time and call that the default entry — keep `default` as its own literal alias value in the entry list.
- Existing `claude_models_with_meta/0`, `codex_models_with_meta/0`, `pi_models/0`, `models_for_provider/1`, `valid_model_slugs/1` are **untouched** — every existing caller keeps working exactly as today.

### 4.3 Always-show-current-selection rule

If a host component's current model slug isn't found in `entries_for_provider/1`'s output (the `sonnet-4-6`-style stale/custom case), the component synthesizes a one-off entry **including `provider`**, since the emitted selection payload (§5.2) always needs one — for a Pi session this uses `group: "Current"` rather than trying to reverse-engineer a stale sub-provider bucket:

```elixir
%ModelEntry{
  provider: selected_provider,
  slug: current,
  label: current,
  group: "Current",
  sub_provider: nil,
  premium?: false,
  legacy?: false,
  default?: false
}
```

This is always rendered, checked, outside any disclosure — mirroring claudette's "selected model never vanishes" rule, extended to models absent from every list.

## 5. Component Design

### 5.1 Shape

- **Trigger**: a pill (provider icon via `DmHelpers.provider_icon/1` + current model label via `ModelHelpers.model_display_name/1`). Composer variant is `disabled` while a turn is running (existing `@active_overlay`/turn-state assign gates this — reuse, don't reinvent). Drawer/modal variants are never turn-disabled.
- **Popover**: opens near the trigger (composer: upward, matching `slash_command_popup.js`'s `absolute bottom-full` placement since the composer sits at the bottom of the page; drawer/modal: downward, standard dropdown placement since they're full-page forms, not bottom-anchored).
- **Search box**: auto-focused on open. Client-side substring filter over `slug`/`label`/`group`/`sub_provider` (case-insensitive), reusing `agent_combobox.js`'s filter+highlight approach. While searching, all disclosures are bypassed — every match (primary + legacy + Pi overflow) renders inline, exactly like claudette.
- **Grouping**: sections by `group`, in a fixed order (Claude Code, Codex, then one section per Pi `sub_provider` group, alphabetical). Section header shows a "via Pi" badge only for Pi-provider sections (Claude Code/Codex sections never show it — they *are* the direct provider).
- **Disclosure**: 
  - Claude Code and Codex each get **one shared "More" toggle** at the bottom of their section for `legacy?: true` entries.
  - Each Pi sub-provider section gets its **own** "Show all N" toggle when it has more than a fixed primary-count (e.g. show first 3, collapse the rest) — matches claudette's per-bucket Pi disclosure.
  - If the active selection lives behind a disclosure, that disclosure auto-expands on open (claudette behavior, carried over).
- **Row**: bullet + label. Checkmark on the right for the active row. `$` icon (in place of the checkmark) for `premium?: true` rows that are *not* the active row — an active row that's also `premium?: true` shows both (checkmark takes visual priority, `$` moves to a smaller adjacent badge) to avoid ambiguity about what's currently selected. Small "Recommended" tag next to `default?: true` rows. Provider badge (icon) on a row only when that row's actual provider differs from its section's implied provider (this basically never fires for Claude Code/Codex sections and never fires within a Pi section, since Pi sections are already sub-provider-scoped — kept for structural parity with claudette, expected to be a no-op in practice today).
- **Keyboard/mouse**: ArrowUp/Down/Enter/Escape, click-outside-to-close, mouseover-highlight — lifted from `agent_combobox.js`.

### 5.2 Component API and event contract (boundary — must be exact)

**Assigns:**

| Assign | Required | Type | Meaning |
|---|---|---|---|
| `id` | yes | string | DOM id, passed through to the hook root |
| `entries` | yes | `[ModelEntry.t()]` | pre-computed by the host via `entries_for_provider/1` (§4.2), possibly concatenated across providers — see `allow_provider_switch?` below |
| `selected_provider` | yes | string | the currently active provider |
| `selected_model` | yes | string | the currently active slug |
| `allow_provider_switch?` | yes | boolean | see below |
| `event` | yes | string | the `phx-click`/hook-pushed event name the host's `handle_event/3` listens for |
| `disabled?` | no, default `false` | boolean | composer passes `true` while a turn is running; drawer/modal never disable |
| `placement` | no, default `:down` | `:up \| :down` | composer uses `:up` (bottom-anchored, matches `slash_command_popup.js`); drawer/modal use `:down` |

**`allow_provider_switch?` resolves the provider-switching ambiguity directly against current server behavior** (verified: `DmModelHelpers.handle_select_model/2` today only ever receives `%{"model", "effort"}` and calls `Sessions.update_session(session, %{model: model})` — it never touches `session.provider`, because **mid-conversation provider switching is not implemented anywhere in the app today** and is explicitly out of scope for this spec, per §3):

- **Composer**: `allow_provider_switch?: false`. The host pre-filters `entries` to the session's own `provider` before passing them in — the popover shows only that one provider's groups (e.g. a Pi session sees only its Pi sub-provider sections). This matches today's behavior exactly (the existing `cond` already picks one provider's list) while adding search/grouping/badges on top of it. Switching providers mid-chat would require also reassigning `provider_conversation_id`/session directory — a materially larger feature, not this one.
- **Drawer / New Session modal**: `allow_provider_switch?: true`. `entries` is the **full cross-provider list** (Claude Code + Codex + Pi sections together, exactly like claudette's real popover). This is a deliberate simplification of the current UI: it **replaces the separate provider `<select>`/agent-type field entirely** — one popover now does what two controls (provider select + model select) did before. Flagging this explicitly since it changes the drawer/modal's control layout, not just its model list.

**Emitted event payload (canonical, identical across all three hosts):**

```elixir
%{
  "provider" => entry.provider,
  "model" => entry.slug
}
```

No host invents its own shape. Each host's `handle_event(event, %{"provider" => provider, "model" => model}, socket)` still owns its own persistence/downstream behavior (composer persists via `Sessions.update_session/2`; drawer/modal just update component assigns for the pending spawn form) — the component only guarantees the two keys above arrive consistently.

**State authority:** the hook keeps *all* derived UI state (search text, open/closed, disclosure expansion, keyboard-highlighted row) client-side, but the actual selected provider/model is **server-authoritative** after the round trip. The hook does not optimistically "lock in" a visual selection independent of the server's response — if a selection is ever rejected (§7 validation-failure case), the LiveView re-renders with the previous `selected_provider`/`selected_model` assigns and the hook's `updated()` lifecycle re-syncs its `data-selected-model`/`data-selected-provider` attributes from that re-render, snapping the visible checkmark back.

### 5.3 JS Hook (`assets/js/hooks/model_selector_popup.js`, new)

- Sibling to `agent_combobox.js`, following its exact architecture: model list arrives via a `data-models` JSON attribute (array of `%ModelEntry{}`-shaped maps, serialized server-side), hook does all filtering/keyboard-nav/disclosure state client-side, writes the chosen `{slug, provider}` into a hidden input and/or directly dispatches one `phx-click`-equivalent (`this.pushEvent(...)` — the hook's own `pushEvent`, not a form submit) to the LiveView.
- `updated()` lifecycle re-syncs `data-models` when the server pushes a refreshed Pi list (subscribing to `Events.pi_models_refreshed` server-side and re-rendering the assign — the hook doesn't subscribe to PubSub itself, the LiveView does and re-renders).

### 5.4 Server wiring (per host — each keeps its own event name/persistence, the component only standardizes the picking UI)

All three hosts must treat the emitted `%{"provider" => ..., "model" => ...}` payload (§5.2) as **untrusted client input** and revalidate it server-side (against `ModelConfig.valid_model_slugs(provider)` and, for the composer, against `allow_provider_switch?: false` meaning the incoming `provider` must equal the session's own) before updating any assign, session record, or spawn param. Nothing in the JS hook is a trust boundary — it only shapes what gets sent.

- **Composer** (`message_composer.ex` + `dm_model_helpers.ex`):

  ```heex
  <.model_selector
    id="composer-model-selector"
    entries={@model_entries}
    selected_provider={@session.provider}
    selected_model={@selected_model}
    allow_provider_switch?={false}
    event="select_model"
    disabled?={@active_overlay == :turn_running}
    placement={:up}
  />
  ```

  `@model_entries` is pre-filtered to `@session.provider` by the host (per §5.2's `allow_provider_switch?: false` rule) — the popover only ever shows that one provider's groups. The emitted event still lands on the existing `"select_model"` handler (`dm_model_helpers.ex:36-59`), which already persists via `Sessions.update_session/2` — **add a Pi branch** there since today Pi sessions fall through to the Claude list, and add the server-side revalidation described above.

- **New Agent drawer**: replace the static triple-optgroup `<select>` and the (currently nonexistent) provider→model cascading with:

  ```heex
  <.model_selector
    id="new-agent-model-selector"
    entries={all_model_entries()}
    selected_provider={@pending_provider}
    selected_model={@pending_model}
    allow_provider_switch?={true}
    event="model_and_provider_selected"
  />
  ```

  `all_model_entries()` is the full cross-provider list (Claude Code + Codex + Pi sections together). The selector **replaces the separate provider/agent-type field entirely** — there is no independent provider `<select>` left to wire up; the drawer's `handle_event("model_and_provider_selected", %{"provider" => p, "model" => m}, socket)` revalidates and sets both `pending_provider` and `pending_model` from the one canonical payload.

- **New Session modal**: same pattern as the drawer — replace both the `provider_field/1` (`phx-change="provider_changed"`) and `model_selector/1` native `<select>` (lines 435-459) with one `<.model_selector allow_provider_switch?={true} entries={all_model_entries()} .../>`. The existing `"provider_changed"` (lines 63-83) and `"model_changed"` (lines 86-88) handlers are **collapsed into one handler** for the new component's single event, which revalidates and sets `selected_provider`/`selected_model` together — no more two-step cascade where changing provider triggers a separate default-model computation; the popover already only offers valid provider+model pairs.

## 6. Catalog Refresh (Claude + Codex)

**Both layers must move together** — display metadata (§4.2) and the validated slug lists, or the picker could offer models that fail spawn/switch validation.

### 6.1 Sources of truth to update

- `lib/eye_in_the_sky_web/helpers/model_helpers.ex` — `claude_models/0`, `claude_models_with_meta/0`, `codex_models/0`, `codex_models_with_meta/0`.
- `lib/eye_in_the_sky/agents/model_config.ex` — `claude_models/0`, `codex_models/0` (the actually-validated lists spawn/switch check against).
- `scripts/eits` — the bash-side `--provider claude`/`--provider codex` valid-model lists and help text (confirmed stale: still shows `claude-opus-4-7` as newest, no Fable 5 at all).

### 6.2 Exact slugs — verify before writing, do not hardcode from marketing names alone

The screenshots show **display names** ("Opus", "Fable", "Sonnet", "Haiku", "Default"), not API slugs. Known real slugs (from this session's own model reference): `claude-fable-5`, `claude-opus-4-8`, `claude-sonnet-5`, `claude-haiku-4-5-20251001`. The implementation plan must confirm these (and any `-1m` billed variants) against the authoritative current source before hardcoding — do not ship guessed slugs.

Codex: `scripts/eits`'s existing list (`gpt-5.5, gpt-5.4, gpt-5.2-codex, gpt-5.1-codex-max, gpt-5.4-mini, gpt-5.3-codex, gpt-5.2`) already matches the full valid set — no new slugs needed here, only the primary/legacy split (§4.2) and confirming `gpt-5.5` is still `default?: true`.

**Source-of-truth rule:** the Codex (and Claude) catalog's source of truth is **this account's own** `scripts/eits agents spawn --help` output and/or in-app CLI-visible model listings — never public provider marketing docs. Model availability is account/subscription-specific; a future implementer "correcting" this catalog against a public docs page could silently break or mismatch what's actually spawnable here. If `scripts/eits`'s list and a public reference ever disagree, `scripts/eits` wins.

### 6.3 Migration note

Existing sessions with an old-but-still-valid slug (e.g. `sonnet-4-6`) must keep working — §4.3's "always show current selection" rule covers display; `ModelConfig`'s validated list should **keep old-generation slugs valid for existing sessions** (don't remove them from the accepted set, only stop offering them as non-legacy/primary in the picker). This mirrors what the screenshot itself shows: `sonnet-4-6` still works and is still selectable, just outside the curated recommended list.

## 7. Testing

- **Data layer**: unit tests for `ModelEntry`/`entries_for_provider/1` per provider — correct `group`/`sub_provider`/`premium?`/`legacy?`/`default?` assignment; Pi entries preserve `sub_provider` from discovery; empty/stale Pi cache handled (existing `:empty`/`:stale` cases from `ModelDiscoveryCache`).
- **Component**: LiveView tests per host (composer, drawer, modal) — popover opens, search filters, disclosure expands/collapses, selecting an entry fires the right event and updates the right assign/DB field, always-show-current-selection for an out-of-catalog slug.
- **Validation-failure path** (previously untested): selecting a model absent from `ModelConfig.valid_model_slugs(provider)` — or, in the composer, submitting a payload with a `provider` different from the session's own when `allow_provider_switch?: false` — must not update persisted session state; the LiveView re-renders with the previous `selected_model`/`selected_provider` assigns intact, and (composer only, matching the existing `handle_select_model/2` error path) a flash error is shown.
- **JS hook**: manual/browser verification (this codebase has no existing JS unit-test harness for hooks per the Phase-1 exploration — follow that precedent, don't introduce one here) — keyboard nav, click-outside, search, disclosure toggling, mid-turn disabled state in the composer.
- **Catalog refresh**: a test asserting `ModelConfig.valid_model_combos()` still accepts every pre-refresh slug (no regressions for existing sessions) in addition to the new ones.

## 8. Self-Review

- **Placeholder scan**: none found — every field/behavior above has a concrete rule.
- **Consistency**: `%ModelEntry{}` field names used identically in §4.2/§5.1/§7. Existing function names/behavior explicitly preserved in §4.2's closing paragraph.
- **Scope check**: single component + one data struct + one catalog refresh — appropriately sized for one implementation plan; the three host-wiring changes (§5.4) are naturally sequential sub-tasks of the same plan, not separate specs.
- **Ambiguity flagged, not hidden**: §6.2 explicitly says the exact new Claude slugs need verification rather than presenting screenshot-derived guesses as fact.
- **Review round 1 corrections**: verified against the actual codebase (`DmModelHelpers.handle_select_model/2`) that mid-conversation provider switching has no server-side support today, which resolved the `allow_provider_switch?` boundary decisively rather than leaving it as a UI nuance; added the explicit component API/event contract (§5.2); added `provider` to `ModelEntry`; tightened `premium?` (then named `billed?`) detection to an enumerated alias set instead of substring matching; added the `default`-is-an-alias-not-a-model nuance; added the Codex/Claude source-of-truth rule; added the validation-failure test case.
- **Review round 2 corrections**: fixed a real contradiction between §5.2 (drawer/modal get `allow_provider_switch?: true` with the full cross-provider list) and the old §5.3, which had still described the drawer with a single-provider list and a "provider pill re-fetches entries" mechanism left over from before that decision was finalized — §5.4 (renumbered from §5.3) now gives concrete component-usage code for all three hosts matching §5.2 exactly, including the drawer/modal losing their separate provider-select field entirely. Renumbered §5 (Shape → API/event contract → JS Hook → Server wiring) so cross-references read in document order. Fixed the composer code example's assign name (`selected={@selected_model}` → the real `selected_provider`/`selected_model` pair). Added `provider` to the always-show-current-selection synthetic entry in §4.3. Added the "hosts must revalidate the emitted payload server-side, it's untrusted client input" rule to §5.4. Renamed `billed?` → `premium?` with an explicit definition note (marks incremental-cost rows, not a claim everything else is free). Softened the Pi premium-flag rule from a flat assumption to a stated heuristic, with a note to re-check `Pi.Control.discover_models/0`'s actual payload for real cost metadata before shipping.

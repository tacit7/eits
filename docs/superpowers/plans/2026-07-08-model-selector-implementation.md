# Unified Model Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the three separately-built EITS model pickers (composer mid-chat switcher, New Agent drawer, New Session modal) with one shared, searchable, grouped `<.model_selector>` component, and refresh the stale Claude/Codex model catalog it's built on.

**Architecture:** An additive `%EyeInTheSky.ModelEntry{}` struct + `ModelHelpers.entries_for_provider/1` builds a uniform list per provider (Claude/Codex from a refreshed static catalog, Pi from `Pi.ModelDiscoveryCache`). A new HEEx function component renders the popover; a new vanilla-JS `phx-hook` (modeled on `agent_combobox.js`) owns search/keyboard-nav/disclosure client-side and pushes one canonical `%{"provider", "model"}` event to the server, which is the only trust boundary — every host revalidates before touching state. All existing `claude_models/0`-style functions and callers are left untouched; only new code paths are added and three host files are rewired onto them.

**Tech Stack:** Elixir/Phoenix LiveView (HEEx function components, `Phoenix.LiveComponent` for two of the three hosts), vanilla JS `phx-hook` (no framework — matches `agent_combobox.js`/`slash_command_popup.js` precedent), ExUnit + `Phoenix.LiveViewTest`.

## Global Constraints (spec §0 and repo-wide, apply to every task)

- `provider` is carried explicitly on every `%ModelEntry{}` — never inferred from section/group context (spec §4.1).
- `premium?` (spec renamed from `billed?`) means "shown with a `$` marker as an incremental-cost row," not "this is the only paid model" — do not imply otherwise in labels/tooltips.
- `default` is a **selectable alias**, never resolved to a concrete slug at catalog-build time — the picker must not claim "Default" always equals one fixed model (spec §4.2).
- **`allow_provider_switch?: false`** for the composer (entries pre-filtered to the session's own provider); **`true`** for the drawer and New Session modal (full cross-provider list, replacing their separate provider-select field entirely) — verified against `DmModelHelpers.handle_select_model/2`, which has no server-side support for changing `session.provider` today (spec §5.2).
- Every host must treat the emitted `%{"provider" => ..., "model" => ...}` payload as **untrusted client input** and revalidate server-side (via `ModelConfig.valid_model?/2`, which already handles Claude/Codex list-checks and Pi's format-regex correctly) before updating any assign, session record, or spawn param (spec §5.4).
- Codex/Claude catalog source of truth is **this account's own** `scripts/eits agents spawn --help` output, never public docs (spec §6.1). Do not hardcode unverified slugs — flag anything unconfirmed rather than guess (spec §6.2).
- Existing sessions with an old-but-valid slug (e.g. `sonnet-4-6`, `claude-opus-4-7`) must keep validating — never remove a slug from `ModelConfig`'s accepted set, only stop offering it as primary/non-legacy in the picker (spec §6.3).
- `mix compile --warnings-as-errors` before every commit. No AI attribution in commits. Work in a worktree per repo policy (`git worktree add .claude/worktrees/<name> -b <branch> features`).

## File Structure

```
lib/eye_in_the_sky/model_entry.ex                          # Task 1 (new)
lib/eye_in_the_sky_web/helpers/model_helpers.ex             # Tasks 1, 2, 4 (catalog refresh + entries_for_provider/1 + always-show-current)
lib/eye_in_the_sky/agents/model_config.ex                   # Task 1 (catalog refresh, validation list)
scripts/eits                                                # Task 3 (bash validation refresh)
lib/eye_in_the_sky_web/components/model_selector.ex          # Task 5 (new HEEx component)
assets/js/hooks/model_selector_popup.js                     # Task 6 (new)
assets/js/app.js                                             # Task 6 (hook registration)
lib/eye_in_the_sky_web/components/dm_page/message_composer.ex # Task 7
lib/eye_in_the_sky_web/live/shared/dm_model_helpers.ex        # Task 7
lib/eye_in_the_sky_web/components/new_agent_drawer.ex        # Task 8
lib/eye_in_the_sky_web/components/new_session_modal.ex       # Task 9
test/eye_in_the_sky/model_entry_test.exs                    # Task 1
test/eye_in_the_sky_web/helpers/model_helpers_test.exs      # Tasks 1, 2, 4 (existing file, extended + fixed)
test/eye_in_the_sky/agents/model_config_test.exs            # Task 1 (existing or new)
test/eye_in_the_sky_web/components/model_selector_test.exs  # Task 5
test/eye_in_the_sky_web/components/message_composer_test.exs # Task 7
test/eye_in_the_sky_web/components/new_agent_drawer_test.exs # Task 8
test/eye_in_the_sky_web/components/new_session_modal_test.exs # Task 9 (existing file, extended)
```

Dependency order: Task 1 → Task 2 → Task 3 (parallel-safe with 4/5/6) → Task 4 → Task 5 → Task 6 → Tasks 7, 8, 9 (each independent of the others, all depend on 1–6) → Task 10 (final integration pass).

---

### Task 1: `ModelEntry` struct + Claude catalog refresh

**Files:**
- Create: `lib/eye_in_the_sky/model_entry.ex`
- Modify: `lib/eye_in_the_sky_web/helpers/model_helpers.ex` (`claude_models/0`, `claude_models_with_meta/0`, `normalize_model_alias/1`, `default_model_for/1`, `model_display_name/1`, `short_alias_display/1`)
- Modify: `lib/eye_in_the_sky/agents/model_config.ex` (`claude_models/0`)
- Modify: `test/eye_in_the_sky_web/helpers/model_helpers_test.exs` (existing hardcoded expectations for `"opus"`/default that this refresh changes)
- Test: `test/eye_in_the_sky/model_entry_test.exs` (new)

**Interfaces:**
- Produces: `%EyeInTheSky.ModelEntry{provider, slug, label, group, sub_provider, premium?, legacy?, default?}` struct (used by every later task).
- Produces: refreshed `ModelHelpers.claude_models/0` / `claude_models_with_meta/0` and `ModelConfig.claude_models/0` — every existing caller of these keeps working unchanged (same `{slug, label}` / `{slug, label, desc, color}` shapes), just with a bigger/updated slug set.

**Known real slugs (verified against this session's own model reference, not guessed):** `claude-fable-5`, `claude-opus-4-8`, `claude-sonnet-5`, `claude-haiku-4-5-20251001` (unchanged — already current). **Unverified, flagged per spec §6.2:** whether a separate `-1m`-suffixed versioned slug exists for Opus 4.8/Sonnet 5, or whether the underlying `claude` CLI accepts a literal `--model default`. This task does **not** guess either — it reuses the already-valid bracket aliases `"opus[1m]"`/`"sonnet[1m]"` for the premium-marked rows (no new slug invented), and defers the `default` alias's *validity* to Task 2's `entries_for_provider/1` (display-only there until confirmed spawnable — see that task's note).

- [ ] **Step 1: Write the failing struct test**

```elixir
defmodule EyeInTheSky.ModelEntryTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.ModelEntry

  test "struct has the documented fields with correct defaults" do
    entry = %ModelEntry{provider: "claude", slug: "claude-opus-4-8", label: "Opus 4.8", group: "Claude Code"}

    assert entry.sub_provider == nil
    assert entry.premium? == false
    assert entry.legacy? == false
    assert entry.default? == false
  end

  test "all fields can be set explicitly" do
    entry = %ModelEntry{
      provider: "pi",
      slug: "ollama-lan/qwen3.6:27b",
      label: "ollama-lan/qwen3.6:27b",
      group: "Ollama (LAN)",
      sub_provider: "ollama-lan",
      premium?: false,
      legacy?: false,
      default?: false
    }

    assert entry.provider == "pi"
    assert entry.sub_provider == "ollama-lan"
  end
end
```

- [ ] **Step 2: Run to verify it fails**

Run: `mix test test/eye_in_the_sky/model_entry_test.exs`
Expected: FAIL — `EyeInTheSky.ModelEntry` module undefined.

- [ ] **Step 3: Implement the struct**

```elixir
defmodule EyeInTheSky.ModelEntry do
  @moduledoc """
  Unified model metadata for the shared model selector (spec §4.1,
  docs/superpowers/specs/2026-07-08-model-selector-design.md).

  `provider` is carried explicitly on every entry rather than inferred from
  section context. `premium?` marks incremental-cost rows shown with a `$`
  badge — it does not mean "this is the only model that costs money."
  """

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

- [ ] **Step 4: Run to verify it passes**

Run: `mix test test/eye_in_the_sky/model_entry_test.exs`
Expected: PASS (2 tests).

- [ ] **Step 5: Write the failing catalog-refresh tests** — append to `test/eye_in_the_sky_web/helpers/model_helpers_test.exs` inside the existing `claude_models/0` describe block:

```elixir
    test "includes the refreshed Claude 5 family slugs" do
      values = ModelHelpers.claude_models() |> Enum.map(&elem(&1, 0))
      assert "claude-opus-4-8" in values
      assert "claude-fable-5" in values
      assert "claude-sonnet-5" in values
      assert "claude-haiku-4-5-20251001" in values
    end

    test "keeps old-generation slugs for existing sessions (spec §6.3 migration note)" do
      values = ModelHelpers.claude_models() |> Enum.map(&elem(&1, 0))
      assert "claude-opus-4-7" in values
      assert "claude-sonnet-4-6" in values
    end
```

Then **fix** the two existing tests this refresh intentionally changes (find and replace in the same file):

```elixir
    test "\"opus\" normalizes to opus slug" do
      assert ModelHelpers.normalize_model_alias("opus") == "claude-opus-4-8"
    end
```

(replaces the old `"claude-opus-4-7"` assertion)

```elixir
    test "uppercase aliases are case-insensitive" do
      assert ModelHelpers.normalize_model_alias("OPUS") == "claude-opus-4-8"
      assert ModelHelpers.normalize_model_alias("SONNET") == "claude-sonnet-5"
      assert ModelHelpers.normalize_model_alias("HAIKU") == "claude-haiku-4-5-20251001"
    end

    test "mixed-case aliases are case-insensitive" do
      assert ModelHelpers.normalize_model_alias("Opus") == "claude-opus-4-8"
      assert ModelHelpers.normalize_model_alias("Sonnet") == "claude-sonnet-5"
    end
```

```elixir
    test "\"opus\" normalizes to opus slug" do
```
→ already covered above; also update the `describe "default_model_for/1"` block:

```elixir
    test "\"claude\" returns claude-opus-4-8" do
      assert ModelHelpers.default_model_for("claude") == "claude-opus-4-8"
    end

    test "nil falls back to claude default" do
      assert ModelHelpers.default_model_for(nil) == "claude-opus-4-8"
    end

    test "unknown provider falls back to claude default" do
      assert ModelHelpers.default_model_for("openai") == "claude-opus-4-8"
      assert ModelHelpers.default_model_for("") == "claude-opus-4-8"
    end
```

And the `describe "model_display_name/1"` block:

```elixir
    test "known claude slug returns its label" do
      assert ModelHelpers.model_display_name("claude-sonnet-4-6") == "Sonnet 4.6"
      assert ModelHelpers.model_display_name("claude-haiku-4-5-20251001") == "Haiku 4.5"
      assert ModelHelpers.model_display_name("claude-opus-4-8") == "Opus 4.8"
    end

    test "short alias \"opus\" returns \"Opus 4.8\"" do
      assert ModelHelpers.model_display_name("opus") == "Opus 4.8"
    end

    test "short alias \"sonnet\" returns \"Sonnet 5\"" do
      assert ModelHelpers.model_display_name("sonnet") == "Sonnet 5"
    end
```

- [ ] **Step 6: Run to verify these fail**

Run: `mix test test/eye_in_the_sky_web/helpers/model_helpers_test.exs`
Expected: FAIL on the new/changed assertions (old slug list, old alias resolution).

- [ ] **Step 7: Implement the catalog refresh** — `model_helpers.ex`:

```elixir
  def claude_models do
    [
      {"claude-opus-4-8", "Opus 4.8"},
      {"claude-fable-5", "Fable 5"},
      {"claude-sonnet-5", "Sonnet 5"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5"},
      {"claude-opus-4-7", "Opus 4.7"},
      {"claude-opus-4-6", "Opus 4.6"},
      {"claude-opus-4-5-20251101", "Opus 4.5"},
      {"claude-opus-4-1-20250805", "Opus 4.1"},
      {"claude-sonnet-4-6", "Sonnet 4.6"},
      {"claude-sonnet-4-5-20250929", "Sonnet 4.5"}
    ]
  end

  def claude_models_with_meta do
    [
      {"claude-opus-4-8", "Opus 4.8", "Best for everyday, complex tasks · 1M context",
       "text-warning"},
      {"claude-fable-5", "Fable 5", "Most capable for your hardest and longest-running tasks",
       "text-warning"},
      {"claude-sonnet-5", "Sonnet 5", "Efficient for routine tasks", "text-info"},
      {"claude-haiku-4-5-20251001", "Haiku 4.5", "Fastest for quick answers", "text-success"},
      {"claude-opus-4-7", "Opus 4.7", "Previous generation · 1M context", "text-warning"},
      {"claude-opus-4-6", "Opus 4.6", "Previous generation · 1M context · extended thinking",
       "text-warning"},
      {"claude-opus-4-5-20251101", "Opus 4.5", "api", "text-warning"},
      {"claude-opus-4-1-20250805", "Opus 4.1", "api", "text-warning"},
      {"claude-sonnet-4-6", "Sonnet 4.6", "Previous generation", "text-info"},
      {"claude-sonnet-4-5-20250929", "Sonnet 4.5", "api", "text-info"}
    ]
  end
```

Update the alias/default/display helpers in the same file:

```elixir
  def normalize_model_alias(model) when is_binary(model) do
    case String.downcase(model) do
      "haiku" -> "claude-haiku-4-5-20251001"
      "sonnet" -> "claude-sonnet-5"
      "opus" -> "claude-opus-4-8"
      _ -> model
    end
  end

  def normalize_model_alias(nil), do: "claude-sonnet-5"

  def default_model_for("codex"), do: "gpt-5.5"
  def default_model_for("pi"), do: nil
  def default_model_for(_), do: "claude-opus-4-8"
```

```elixir
  defp short_alias_display("opus"), do: "Opus 4.8"
  defp short_alias_display("opus[1m]"), do: "Opus (1M)"
  defp short_alias_display("sonnet"), do: "Sonnet 5"
  defp short_alias_display("sonnet[1m]"), do: "Sonnet (1M)"
  defp short_alias_display("haiku"), do: "Haiku 4.5"
  defp short_alias_display("claude-opus-4-6"), do: "Opus 4.6"
  defp short_alias_display(other), do: other
```

`model_config.ex` — append new slugs, **keep every old one** (spec §6.3):

```elixir
  def claude_models do
    [
      "claude-opus-4-8",
      "claude-fable-5",
      "claude-sonnet-5",
      "claude-haiku-4-5-20251001",
      "claude-opus-4-7",
      "claude-opus-4-6",
      "claude-opus-4-5-20251101",
      "claude-opus-4-1-20250805",
      "claude-sonnet-4-6",
      "claude-sonnet-4-5-20250929",
      # short aliases and [1m] variants kept for backward compat with stored sessions
      "opus",
      "opus[1m]",
      "sonnet",
      "sonnet[1m]",
      "haiku"
    ]
  end
```

- [ ] **Step 8: Run to verify all pass**

Run: `mix test test/eye_in_the_sky_web/helpers/model_helpers_test.exs test/eye_in_the_sky/model_entry_test.exs`
Expected: PASS, no failures.

- [ ] **Step 9: Run the full existing test suite for regressions from the alias/default change**

Run: `mix test test/eye_in_the_sky/agents test/eye_in_the_sky_web/components/new_session_modal_test.exs test/eye_in_the_sky_web/live`
Expected: PASS. If any test elsewhere hardcodes `"claude-opus-4-7"` as *the* default (not just *a* valid slug), fix it the same way as Step 5 — grep first: `grep -rn '"claude-opus-4-7"' test/ lib/` and check each hit is a "valid slug" assertion (leave alone) vs. a "this is THE default" assertion (update to `"claude-opus-4-8"`).

- [ ] **Step 10: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky/model_entry.ex lib/eye_in_the_sky_web/helpers/model_helpers.ex lib/eye_in_the_sky/agents/model_config.ex test/eye_in_the_sky/model_entry_test.exs test/eye_in_the_sky_web/helpers/model_helpers_test.exs
git commit -m "feat(models): ModelEntry struct + refresh Claude catalog to current lineup (Opus 4.8, Fable 5, Sonnet 5)"
```

---

### Task 2: `entries_for_provider/1` — Claude, Codex, Pi

**Files:**
- Modify: `lib/eye_in_the_sky_web/helpers/model_helpers.ex` (new function)
- Test: `test/eye_in_the_sky_web/helpers/model_helpers_test.exs` (new describe block)

**Interfaces:**
- Consumes: `ModelEntry` (Task 1), `claude_models_with_meta/0` / `codex_models_with_meta/0` (Task 1, refreshed), `Pi.ModelDiscoveryCache.get_cached/0` (existing, Phase 2).
- Produces: `ModelHelpers.entries_for_provider(provider :: String.t()) :: [ModelEntry.t()]` — used by Task 5 (component), Task 7/8/9 (hosts).
- Produces: `ModelHelpers.all_model_entries/0 :: [ModelEntry.t()]` — Claude + Codex + Pi concatenated, used by drawer/modal (`allow_provider_switch?: true`).

**Legacy/primary split (spec §4.2, confirmed against `scripts/eits agents spawn --help`):**
- Claude primary (not `legacy?`): `claude-opus-4-8`, `claude-fable-5`, `claude-sonnet-5`, `claude-haiku-4-5-20251001`. Everything else from Task 1's list is `legacy?: true`.
- Codex primary: `gpt-5.5`, `gpt-5.4`, `gpt-5.4-mini`. Everything else (`gpt-5.3-codex`, `gpt-5.2-codex`, `gpt-5.2`, `gpt-5.1-codex-max`, `gpt-5.1-codex-mini`) is `legacy?: true`.
- `premium?` for Claude: only the two bracket aliases `opus[1m]` and `sonnet[1m]` — these aren't in `claude_models/0`'s tuple list (they're short-alias-only), so `entries_for_provider("claude")` appends two synthetic entries for them, labeled via `short_alias_display/1`.
- `default?` for Claude: on `claude-opus-4-8` (today's `default_model_for("claude")` value) — **not** a literal `"default"` alias slug. Rationale: `ModelConfig.claude_models/0` has no `"default"` entry and nothing confirms the underlying `claude` CLI accepts `--model default` (spec §6.2 flags this explicitly as unverified). Shipping a selectable-but-unvalidated `"default"` slug would violate the "revalidate server-side" rule in §5.4 the moment someone picked it. Tag the current default's row with `default?: true` and a "Recommended" badge instead — this satisfies the UI intent (one row visually marked recommended) without inventing an unverified slug. Note this deviation in the task's commit message.
- `default?` for Codex: on `gpt-5.5`.

- [ ] **Step 1: Write the failing tests** — new describe block in `test/eye_in_the_sky_web/helpers/model_helpers_test.exs`:

```elixir
  # ---------------------------------------------------------------------------
  # entries_for_provider/1
  # ---------------------------------------------------------------------------

  describe "entries_for_provider/1 — claude" do
    setup do
      {entries: ModelHelpers.entries_for_provider("claude")}
    end

    test "every entry has provider \"claude\" and group \"Claude Code\"", %{entries: entries} do
      assert entries != []
      assert Enum.all?(entries, &(&1.provider == "claude"))
      assert Enum.all?(entries, &(&1.group == "Claude Code"))
    end

    test "primary current-gen models are not legacy", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["claude-opus-4-8"].legacy? == false
      assert by_slug["claude-fable-5"].legacy? == false
      assert by_slug["claude-sonnet-5"].legacy? == false
      assert by_slug["claude-haiku-4-5-20251001"].legacy? == false
    end

    test "older generation models are legacy", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["claude-opus-4-7"].legacy? == true
      assert by_slug["claude-sonnet-4-6"].legacy? == true
    end

    test "opus[1m] and sonnet[1m] are premium", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["opus[1m]"].premium? == true
      assert by_slug["sonnet[1m]"].premium? == true
    end

    test "non-1m entries are not premium", %{entries: entries} do
      refute Enum.any?(entries, &(&1.slug == "claude-opus-4-8" and &1.premium?))
    end

    test "exactly one default entry, on claude-opus-4-8", %{entries: entries} do
      defaults = Enum.filter(entries, & &1.default?)
      assert [%{slug: "claude-opus-4-8"}] = defaults
    end
  end

  describe "entries_for_provider/1 — codex" do
    setup do
      {entries: ModelHelpers.entries_for_provider("codex")}
    end

    test "every entry has provider \"codex\" and group \"Codex\", never premium", %{entries: entries} do
      assert entries != []
      assert Enum.all?(entries, &(&1.provider == "codex"))
      assert Enum.all?(entries, &(&1.group == "Codex"))
      refute Enum.any?(entries, & &1.premium?)
    end

    test "gpt-5.5, gpt-5.4, gpt-5.4-mini are primary; rest are legacy", %{entries: entries} do
      by_slug = Map.new(entries, &{&1.slug, &1})
      assert by_slug["gpt-5.5"].legacy? == false
      assert by_slug["gpt-5.4"].legacy? == false
      assert by_slug["gpt-5.4-mini"].legacy? == false
      assert by_slug["gpt-5.3-codex"].legacy? == true
      assert by_slug["gpt-5.1-codex-max"].legacy? == true
    end

    test "default is gpt-5.5", %{entries: entries} do
      assert [%{slug: "gpt-5.5"}] = Enum.filter(entries, & &1.default?)
    end
  end

  describe "entries_for_provider/1 — pi" do
    test "preserves sub_provider from discovery and marks non-ollama as premium" do
      Application.put_env(:eye_in_the_sky, :pi_control_module, __MODULE__.FakeControl)
      on_exit(fn -> Application.delete_env(:eye_in_the_sky, :pi_control_module) end)
      {:ok, _} = EyeInTheSky.Pi.ModelDiscoveryCache.refresh()

      entries = ModelHelpers.entries_for_provider("pi")
      by_slug = Map.new(entries, &{&1.slug, &1})

      assert by_slug["ollama-lan/qwen3.6:27b"].provider == "pi"
      assert by_slug["ollama-lan/qwen3.6:27b"].sub_provider == "ollama-lan"
      assert by_slug["ollama-lan/qwen3.6:27b"].premium? == false

      assert by_slug["openrouter/qwen/qwen3-coder"].sub_provider == "openrouter"
      assert by_slug["openrouter/qwen/qwen3-coder"].premium? == true
    end

    test "empty cache returns empty list, does not crash" do
      EyeInTheSky.Pi.ModelDiscoveryCache.invalidate()
      assert ModelHelpers.entries_for_provider("pi") == []
    end
  end

  describe "all_model_entries/0" do
    test "concatenates claude, codex, and pi entries" do
      entries = ModelHelpers.all_model_entries()
      providers = entries |> Enum.map(& &1.provider) |> Enum.uniq() |> Enum.sort()
      assert "claude" in providers
      assert "codex" in providers
    end
  end
```

Add the `FakeControl` helper module at the top of the test file (near existing test infrastructure):

```elixir
  defmodule FakeControl do
    def discover_models do
      {:ok,
       [
         %{"id" => "ollama-lan/qwen3.6:27b", "provider" => "ollama-lan"},
         %{"id" => "openrouter/qwen/qwen3-coder", "provider" => "openrouter"}
       ]}
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/eye_in_the_sky_web/helpers/model_helpers_test.exs`
Expected: FAIL — `entries_for_provider/1` and `all_model_entries/0` undefined.

- [ ] **Step 3: Implement**

```elixir
  alias EyeInTheSky.ModelEntry

  @claude_primary_slugs ~w(claude-opus-4-8 claude-fable-5 claude-sonnet-5 claude-haiku-4-5-20251001)
  @claude_premium_aliases ["opus[1m]", "sonnet[1m]"]
  @claude_default_slug "claude-opus-4-8"

  @codex_primary_slugs ~w(gpt-5.5 gpt-5.4 gpt-5.4-mini)
  @codex_default_slug "gpt-5.5"

  @doc """
  Unified `%ModelEntry{}` list for a provider — the data source for the
  shared model selector (spec §4.2). Claude/Codex come from the static
  catalog (Task 1); Pi comes from `Pi.ModelDiscoveryCache.get_cached/0`
  directly, preserving the discovery payload's `"provider"` sub-provider key
  that `pi_models/0` discards.
  """
  @spec entries_for_provider(String.t()) :: [ModelEntry.t()]
  def entries_for_provider("claude") do
    base =
      for {slug, label} <- claude_models() do
        %ModelEntry{
          provider: "claude",
          slug: slug,
          label: label,
          group: "Claude Code",
          legacy?: slug not in @claude_primary_slugs,
          default?: slug == @claude_default_slug
        }
      end

    premium =
      for alias_slug <- @claude_premium_aliases do
        %ModelEntry{
          provider: "claude",
          slug: alias_slug,
          label: short_alias_display(alias_slug),
          group: "Claude Code",
          premium?: true
        }
      end

    base ++ premium
  end

  def entries_for_provider("codex") do
    for {slug, label} <- codex_models() do
      %ModelEntry{
        provider: "codex",
        slug: slug,
        label: label,
        group: "Codex",
        legacy?: slug not in @codex_primary_slugs,
        default?: slug == @codex_default_slug
      }
    end
  end

  def entries_for_provider("pi") do
    case EyeInTheSky.Pi.ModelDiscoveryCache.get_cached() do
      {:ok, models, _freshness} -> Enum.map(models, &pi_entry/1)
      :empty -> []
    end
  end

  def entries_for_provider(_), do: []

  # `premium?` heuristic (spec §4.2, stated as a heuristic not a guarantee):
  # local Ollama routes are free, everything else goes through a paid cloud
  # API key. Re-check against Pi.Control.discover_models/0's actual payload
  # for real cost metadata before trusting this long-term.
  defp pi_entry(%{"id" => slug, "provider" => sub_provider}) do
    %ModelEntry{
      provider: "pi",
      slug: slug,
      label: slug,
      group: pi_group_label(sub_provider),
      sub_provider: sub_provider,
      premium?: not String.starts_with?(sub_provider, "ollama")
    }
  end

  defp pi_group_label("ollama"), do: "Ollama"
  defp pi_group_label("ollama-lan"), do: "Ollama (LAN)"
  defp pi_group_label(sub_provider), do: String.capitalize(sub_provider)

  @doc "Claude + Codex + Pi entries concatenated (for allow_provider_switch?: true hosts)."
  @spec all_model_entries() :: [ModelEntry.t()]
  def all_model_entries do
    entries_for_provider("claude") ++ entries_for_provider("codex") ++ entries_for_provider("pi")
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/eye_in_the_sky_web/helpers/model_helpers_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/helpers/model_helpers.ex test/eye_in_the_sky_web/helpers/model_helpers_test.exs
git commit -m "feat(models): entries_for_provider/1 + all_model_entries/0 (Claude/Codex/Pi unified ModelEntry lists)"
```

---

### Task 3: `scripts/eits` catalog refresh

**Files:**
- Modify: `scripts/eits` (help text ~lines 1688-1690; validation `case` ~line 1761; error message ~line 1764)

**Interfaces:** none (bash-only, no Elixir callers) — pure text/validation sync so the CLI accepts the same slugs the app now does.

- [ ] **Step 1: Update the help text** (lines 1688-1690):

```bash
Valid models (--provider claude, default):
  Shorthand (recommended): opus, sonnet, haiku, opus[1m], sonnet[1m]
  Full names: claude-opus-4-8, claude-fable-5, claude-sonnet-5, claude-haiku-4-5-20251001,
              claude-opus-4-7, claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4-5-20250929
```

- [ ] **Step 2: Update the validation `case` pattern** (line 1761):

```bash
                claude-opus-4-8|claude-fable-5|claude-sonnet-5|claude-haiku-4-5-20251001|claude-opus-4-7|claude-opus-4-6|claude-sonnet-4-6|claude-sonnet-4-5-20250929|opus|"opus[1m]"|sonnet|"sonnet[1m]"|haiku) ;;
```

- [ ] **Step 3: Update the error-message model list** (line 1764):

```bash
  Versioned checkpoints:   claude-opus-4-8, claude-fable-5, claude-sonnet-5, claude-haiku-4-5-20251001, claude-opus-4-7, claude-opus-4-6, claude-sonnet-4-6, claude-sonnet-4-5-20250929
```

- [ ] **Step 4: Verify manually**

```bash
scripts/eits agents spawn --provider claude --model claude-opus-4-8 --instructions "x" --dry-run
scripts/eits agents spawn --provider claude --model claude-fable-5 --instructions "x" --dry-run
scripts/eits agents spawn --provider claude --model claude-opus-4-7 --instructions "x" --dry-run
scripts/eits agents spawn --provider claude --model bogus-model --instructions "x" --dry-run
```

Expected: first three print the dry-run curl command (accepted); fourth exits 1 with the updated error listing.

- [ ] **Step 5: Commit**

```bash
git add scripts/eits
git commit -m "chore(eits-cli): refresh Claude model validation to current lineup (Opus 4.8, Fable 5, Sonnet 5)"
```

---

### Task 4: Always-show-current-selection helper

**Files:**
- Modify: `lib/eye_in_the_sky_web/helpers/model_helpers.ex` (new function)
- Test: `test/eye_in_the_sky_web/helpers/model_helpers_test.exs` (new describe block)

**Interfaces:**
- Consumes: `entries_for_provider/1` / `all_model_entries/0` (Task 2).
- Produces: `ModelHelpers.entries_with_current(entries, provider, current_slug) :: [ModelEntry.t()]` — used by Task 5 (component) and every host wiring task.

- [ ] **Step 1: Write the failing tests**

```elixir
  # ---------------------------------------------------------------------------
  # entries_with_current/3
  # ---------------------------------------------------------------------------

  describe "entries_with_current/3" do
    test "returns entries unchanged when current slug is already present" do
      entries = ModelHelpers.entries_for_provider("codex")
      result = ModelHelpers.entries_with_current(entries, "codex", "gpt-5.5")
      assert result == entries
    end

    test "synthesizes and appends a Current entry when the slug is absent from every list" do
      entries = ModelHelpers.entries_for_provider("claude")
      result = ModelHelpers.entries_with_current(entries, "claude", "sonnet-4-6")

      assert length(result) == length(entries) + 1
      synthetic = List.last(result)
      assert synthetic.provider == "claude"
      assert synthetic.slug == "sonnet-4-6"
      assert synthetic.label == "sonnet-4-6"
      assert synthetic.group == "Current"
      assert synthetic.sub_provider == nil
      assert synthetic.premium? == false
      assert synthetic.legacy? == false
      assert synthetic.default? == false
    end

    test "does not duplicate when called twice with the same missing slug" do
      entries = ModelHelpers.entries_for_provider("claude")
      once = ModelHelpers.entries_with_current(entries, "claude", "sonnet-4-6")
      twice = ModelHelpers.entries_with_current(once, "claude", "sonnet-4-6")
      assert length(twice) == length(once)
    end
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/eye_in_the_sky_web/helpers/model_helpers_test.exs`
Expected: FAIL — `entries_with_current/3` undefined.

- [ ] **Step 3: Implement**

```elixir
  @doc """
  Ensures `current_slug` always appears in `entries`, synthesizing a
  `group: "Current"` entry if it's absent from every known list (the
  `sonnet-4-6`-style stale/custom case — spec §4.3). Idempotent.
  """
  @spec entries_with_current([ModelEntry.t()], String.t(), String.t()) :: [ModelEntry.t()]
  def entries_with_current(entries, provider, current_slug) do
    if Enum.any?(entries, &(&1.slug == current_slug)) do
      entries
    else
      entries ++
        [
          %ModelEntry{
            provider: provider,
            slug: current_slug,
            label: current_slug,
            group: "Current",
            sub_provider: nil,
            premium?: false,
            legacy?: false,
            default?: false
          }
        ]
    end
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/eye_in_the_sky_web/helpers/model_helpers_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/helpers/model_helpers.ex test/eye_in_the_sky_web/helpers/model_helpers_test.exs
git commit -m "feat(models): entries_with_current/3 — always-show-current-selection rule"
```

---

### Task 5: `<.model_selector>` HEEx component

**Files:**
- Create: `lib/eye_in_the_sky_web/components/model_selector.ex`
- Test: `test/eye_in_the_sky_web/components/model_selector_test.exs`

**Interfaces:**
- Consumes: `ModelEntry.t()` list (Tasks 2/4), `EyeInTheSkyWeb.Components.DmHelpers.provider_icon/1` (existing), `ModelHelpers.model_display_name/1` (existing).
- Produces: `EyeInTheSkyWeb.Components.ModelSelector.model_selector/1` — the `<.model_selector>` function component every host (Tasks 7/8/9) renders. Exact assigns per spec §5.2:

| Assign | Required | Type | Default |
|---|---|---|---|
| `id` | yes | string | — |
| `entries` | yes | `[ModelEntry.t()]` | — |
| `selected_provider` | yes | string | — |
| `selected_model` | yes | string | — |
| `allow_provider_switch?` | yes | boolean | — |
| `event` | yes | string | — |
| `myself` | no | `Phoenix.LiveComponent.CID.t() \| nil` | `nil` — when set, rendered as `phx-target={@myself}` on the hook root so `pushEventTo` reaches a LiveComponent instead of the parent LiveView |
| `disabled?` | no | boolean | `false` |
| `placement` | no | `:up \| :down` | `:down` |

Emits (via the JS hook, Task 6): `phx-target`-aware push of `event` with payload `%{"provider" => slug's provider, "model" => slug}`.

This task builds the **static markup** (trigger pill, popover skeleton, grouped/disclosed rows, all `data-*` attributes the hook needs) and verifies it via `Phoenix.LiveViewTest.render_component/2` — no interactivity yet (that's Task 6's hook). The component always calls `ModelHelpers.entries_with_current/3` itself so no host has to remember to.

- [ ] **Step 1: Write the failing tests**

```elixir
defmodule EyeInTheSkyWeb.Components.ModelSelectorTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.ModelSelector
  alias EyeInTheSky.ModelEntry

  defp claude_entries do
    [
      %ModelEntry{provider: "claude", slug: "claude-opus-4-8", label: "Opus 4.8", group: "Claude Code", default?: true},
      %ModelEntry{provider: "claude", slug: "claude-opus-4-7", label: "Opus 4.7", group: "Claude Code", legacy?: true},
      %ModelEntry{provider: "claude", slug: "opus[1m]", label: "Opus (1M)", group: "Claude Code", premium?: true}
    ]
  end

  test "renders the trigger pill with the current model's display label" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ "Opus 4.8"
    assert html =~ ~s(id="test-selector")
  end

  test "renders one row per entry with the checkmark on the active slug" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-7",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-slug="claude-opus-4-8")
    assert html =~ ~s(data-slug="claude-opus-4-7")
    assert html =~ ~s(data-active="true")
  end

  test "premium entries render a $ marker" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-premium="true")
  end

  test "legacy entries are marked for client-side disclosure" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-legacy="true")
  end

  test "entries are serialized to the hook's data-models attribute" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ "data-models="
    assert html =~ "claude-opus-4-8"
  end

  test "current selection missing from entries is still rendered and checked" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "sonnet-4-6",
        allow_provider_switch?: false,
        event: "select_model"
      )

    assert html =~ ~s(data-slug="sonnet-4-6")
    assert html =~ ~s(data-active="true")
  end

  test "disabled? renders the trigger as a disabled button" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model",
        disabled?: true
      )

    assert html =~ "disabled"
  end

  test "myself assign renders phx-target on the hook root" do
    html =
      render_component(&ModelSelector.model_selector/1,
        id: "test-selector",
        entries: claude_entries(),
        selected_provider: "claude",
        selected_model: "claude-opus-4-8",
        allow_provider_switch?: false,
        event: "select_model",
        myself: %Phoenix.LiveComponent.CID{cid: 1}
      )

    assert html =~ ~s(phx-target="1")
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/eye_in_the_sky_web/components/model_selector_test.exs`
Expected: FAIL — module undefined.

- [ ] **Step 3: Implement**

```elixir
defmodule EyeInTheSkyWeb.Components.ModelSelector do
  @moduledoc """
  Shared searchable, grouped model-picker popover (spec §5,
  docs/superpowers/specs/2026-07-08-model-selector-design.md). Used
  identically by the DM composer, New Agent drawer, and New Session modal.

  Structure/interactivity split: this component renders the full static
  markup (all rows, all disclosure containers, all data-* attributes); the
  `ModelSelectorPopup` JS hook (assets/js/hooks/model_selector_popup.js)
  owns search filtering, keyboard nav, disclosure toggling, and pushing the
  final selection to the server. The selected provider/model is always
  server-authoritative — the hook never optimistically renders a selection
  the server hasn't confirmed.
  """

  use Phoenix.Component

  import EyeInTheSkyWeb.CoreComponents, only: [icon: 1]
  alias EyeInTheSkyWeb.Components.DmHelpers
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  attr :id, :string, required: true
  attr :entries, :list, required: true
  attr :selected_provider, :string, required: true
  attr :selected_model, :string, required: true
  attr :allow_provider_switch?, :boolean, required: true
  attr :event, :string, required: true
  attr :myself, :any, default: nil
  attr :disabled?, :boolean, default: false
  attr :placement, :atom, default: :down

  def model_selector(assigns) do
    entries =
      ModelHelpers.entries_with_current(
        assigns.entries,
        assigns.selected_provider,
        assigns.selected_model
      )

    assigns =
      assigns
      |> assign(:entries, entries)
      |> assign(:sections, group_entries(entries))
      |> assign(:models_json, Jason.encode!(Enum.map(entries, &entry_to_json/1)))

    ~H"""
    <div
      id={@id}
      phx-hook="ModelSelectorPopup"
      phx-target={@myself}
      data-event={@event}
      data-allow-provider-switch={to_string(@allow_provider_switch?)}
      data-selected-provider={@selected_provider}
      data-selected-model={@selected_model}
      data-placement={@placement}
      data-models={@models_json}
      class="relative inline-block"
    >
      <button
        type="button"
        disabled={@disabled?}
        data-selector-trigger
        class="flex items-center gap-1.5 px-2 h-6 rounded-md text-[11px] font-medium text-base-content/55 bg-base-content/[0.05] border border-[var(--border-subtle)] hover:text-base-content/75 hover:bg-base-content/[0.08] transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
      >
        <img
          src={DmHelpers.provider_icon(@selected_provider)}
          class={"size-3 flex-shrink-0 #{DmHelpers.provider_icon_class(@selected_provider)}"}
        />
        <span data-selector-trigger-label>{ModelHelpers.model_display_name(@selected_model)}</span>
        <.icon name="hero-chevron-down-mini" class="size-3 flex-shrink-0" />
      </button>

      <div
        data-selector-popover
        class={[
          "hidden absolute z-[1] w-80 rounded-xl border border-base-content/8 bg-base-100 shadow-lg",
          if(@placement == :up, do: "bottom-full mb-2", else: "top-full mt-2")
        ]}
      >
        <div class="p-2 border-b border-base-content/8">
          <input
            type="text"
            data-selector-search
            placeholder="Search models…"
            class="w-full bg-transparent border-0 outline-none text-sm px-1"
          />
        </div>
        <ul data-selector-list role="listbox" class="max-h-96 overflow-y-auto p-1.5">
          <li :for={{group, group_entries} <- @sections} data-selector-group={group}>
            <div class="menu-title text-xs px-3 pt-2 pb-0.5 text-base-content/40 flex items-center gap-1.5">
              {group}
              <span
                :if={pi_group?(group_entries)}
                class="text-[9px] px-1.5 py-0.5 rounded-full bg-primary/10 text-primary"
              >
                via Pi
              </span>
            </div>
            <.model_row :for={entry <- group_entries} entry={entry} selected_model={@selected_model} />
          </li>
        </ul>
      </div>
    </div>
    """
  end

  attr :entry, :any, required: true
  attr :selected_model, :string, required: true

  defp model_row(assigns) do
    active = assigns.entry.slug == assigns.selected_model
    assigns = assign(assigns, :active, active)

    ~H"""
    <li
      data-slug={@entry.slug}
      data-provider={@entry.provider}
      data-active={to_string(@active)}
      data-premium={to_string(@entry.premium?)}
      data-legacy={to_string(@entry.legacy?)}
      data-default={to_string(@entry.default?)}
      role="option"
      aria-selected={to_string(@active)}
      class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm cursor-pointer hover:bg-base-content/[0.04] aria-selected:bg-base-content/[0.06]"
    >
      <span class="w-[5px] h-[5px] rounded-full bg-primary/60 flex-shrink-0"></span>
      <span class="flex-1 truncate" data-selector-row-label>{@entry.label}</span>
      <span :if={@entry.default?} class="text-[9px] px-1.5 py-0.5 rounded-full bg-success/10 text-success">
        Recommended
      </span>
      <.icon :if={@active} name="hero-check-mini" class="size-3.5 text-primary flex-shrink-0" />
      <.icon
        :if={not @active and @entry.premium?}
        name="hero-currency-dollar-mini"
        class="size-3.5 text-base-content/40 flex-shrink-0"
      />
    </li>
    """
  end

  defp group_entries(entries) do
    entries
    |> Enum.group_by(& &1.group)
    |> Enum.sort_by(fn {group, _} -> group_order(group) end)
  end

  # Fixed section order (spec §5.1): Claude Code, Codex, then Pi sub-provider
  # groups alphabetically, "Current" (synthetic, always-show rule) last.
  defp group_order("Claude Code"), do: {0, ""}
  defp group_order("Codex"), do: {1, ""}
  defp group_order("Current"), do: {3, ""}
  defp group_order(group), do: {2, group}

  defp pi_group?([%{provider: "pi"} | _]), do: true
  defp pi_group?(_), do: false

  defp entry_to_json(entry) do
    %{
      provider: entry.provider,
      slug: entry.slug,
      label: entry.label,
      group: entry.group,
      premium: entry.premium?,
      legacy: entry.legacy?,
      default: entry.default?
    }
  end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/eye_in_the_sky_web/components/model_selector_test.exs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/components/model_selector.ex test/eye_in_the_sky_web/components/model_selector_test.exs
git commit -m "feat(model-selector): shared <.model_selector> HEEx component (static markup, grouped/disclosed rows)"
```

---

### Task 6: `ModelSelectorPopup` JS hook

**Files:**
- Create: `assets/js/hooks/model_selector_popup.js`
- Modify: `assets/js/app.js` (import + register)

**Interfaces:**
- Consumes: the `data-*` attributes rendered by Task 5 (`data-models`, `data-event`, `data-allow-provider-switch`, `data-selected-provider`, `data-selected-model`, `data-placement`) and the row/section markup's `data-slug`/`data-provider`/`data-legacy`/`data-premium`/`data-default`/`data-selector-group` attributes.
- Produces: on row click or Enter, `this.pushEventTo(this.el, event, {"provider": provider, "model": slug})` — the canonical payload from spec §5.2. `pushEventTo` targets a LiveComponent automatically when the hook root carries `phx-target` (rendered by Task 5 when `myself` is set); otherwise it behaves like a normal `pushEvent` to the enclosing LiveView.

- [ ] **Step 1: Implement** (no server-side test harness for JS hooks in this codebase — confirmed absent in Phase-1 exploration; this is manual/browser-verified per spec §7, matching precedent):

```javascript
// ModelSelectorPopup — shared searchable model picker for the DM composer,
// New Agent drawer, and New Session modal (spec:
// docs/superpowers/specs/2026-07-08-model-selector-design.md §5.3).
//
// Data arrives via data-models (JSON array of {provider, slug, label, group,
// premium, legacy, default}), serialized server-side by
// EyeInTheSkyWeb.Components.ModelSelector. All search/keyboard-nav/disclosure
// state lives client-side (agent_combobox.js pattern); the actual selected
// provider/model stays server-authoritative — on selection we push once and
// wait for the server's re-render, we do not lock in the visual state
// ourselves. updated() re-syncs from a fresh data-models (e.g. after a Pi
// discovery refresh) without losing open/search state mid-interaction.

const PRIMARY_VISIBLE_COUNT = 3

export const ModelSelectorPopup = {
  mounted() {
    this._models = this._parseModels()
    this._previousModelsJson = this.el.dataset.models || ""
    this._open = false
    this._activeIndex = -1
    this._expandedGroups = new Set()

    this._trigger = this.el.querySelector("[data-selector-trigger]")
    this._popover = this.el.querySelector("[data-selector-popover]")
    this._search = this.el.querySelector("[data-selector-search]")
    this._list = this.el.querySelector("[data-selector-list]")

    this._onTriggerClick = () => this._toggle()
    this._trigger.addEventListener("click", this._onTriggerClick)

    this._onSearchInput = () => this._render()
    this._search.addEventListener("input", this._onSearchInput)

    this._onKeydown = (e) => this._handleKeydown(e)
    this._search.addEventListener("keydown", this._onKeydown)

    this._onClickOutside = (e) => {
      if (!this.el.contains(e.target)) this._close()
    }
    document.addEventListener("mousedown", this._onClickOutside)

    this._onListMousedown = (e) => {
      const li = e.target.closest("li[data-slug]")
      if (li) {
        e.preventDefault()
        this._select(li.dataset.provider, li.dataset.slug)
        return
      }
      const disclosure = e.target.closest("[data-disclosure-toggle]")
      if (disclosure) {
        e.preventDefault()
        this._expandedGroups.add(disclosure.dataset.disclosureToggle)
        this._render()
      }
    }
    this._list.addEventListener("mousedown", this._onListMousedown)

    this._onListMousemove = (e) => {
      const li = e.target.closest("li[data-slug]")
      if (!li) return
      const items = this._visibleItems()
      const idx = items.indexOf(li)
      if (idx !== -1) this._setActive(idx)
    }
    this._list.addEventListener("mousemove", this._onListMousemove)

    this._render()
  },

  updated() {
    const newJson = this.el.dataset.models || ""
    if (newJson === this._previousModelsJson) return
    this._previousModelsJson = newJson
    this._models = this._parseModels()
    if (this._open) this._render()
  },

  destroyed() {
    this._trigger.removeEventListener("click", this._onTriggerClick)
    this._search.removeEventListener("input", this._onSearchInput)
    this._search.removeEventListener("keydown", this._onKeydown)
    document.removeEventListener("mousedown", this._onClickOutside)
    this._list.removeEventListener("mousedown", this._onListMousedown)
    this._list.removeEventListener("mousemove", this._onListMousemove)
  },

  // ---- private ----

  _parseModels() {
    try {
      const raw = this.el.dataset.models
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  },

  _toggle() {
    if (this._trigger.disabled) return
    this._open ? this._close() : this._openPopover()
  },

  _openPopover() {
    this._open = true
    this._popover.classList.remove("hidden")
    this._expandGroupContainingSelection()
    this._render()
    this._search.value = ""
    // 0ms timeout so focus survives the click that triggered open.
    setTimeout(() => this._search.focus(), 0)
  },

  _close() {
    this._open = false
    this._popover.classList.add("hidden")
    this._activeIndex = -1
  },

  _expandGroupContainingSelection() {
    const selectedSlug = this.el.dataset.selectedModel
    const model = this._models.find((m) => m.slug === selectedSlug)
    if (model && (model.legacy || model.group)) this._expandedGroups.add(model.group)
  },

  _query() {
    return (this._search.value || "").trim().toLowerCase()
  },

  _render() {
    const q = this._query()
    const searching = q !== ""

    const byGroup = new Map()
    for (const m of this._models) {
      if (searching) {
        const hay = `${m.slug} ${m.label} ${m.group}`.toLowerCase()
        if (!hay.includes(q)) continue
      }
      if (!byGroup.has(m.group)) byGroup.set(m.group, [])
      byGroup.get(m.group).push(m)
    }

    let html = ""
    for (const [group, models] of byGroup) {
      const primary = models.filter((m) => !m.legacy)
      const legacy = models.filter((m) => m.legacy)
      const expanded = searching || this._expandedGroups.has(group)

      const visible = expanded ? models : primary
      const hiddenCount = expanded ? 0 : legacy.length

      html += `<div class="menu-title text-xs px-3 pt-2 pb-0.5 text-base-content/40">${this._esc(group)}</div>`
      html += visible.map((m) => this._rowHtml(m, q)).join("")

      if (hiddenCount > 0) {
        html += `<div data-disclosure-toggle="${this._esc(group)}" class="px-3 py-1.5 text-xs text-base-content/40 cursor-pointer hover:text-base-content/60">More (${hiddenCount})</div>`
      } else if (group.startsWith("Ollama") || (models[0] && models[0].provider === "pi")) {
        // Pi sub-provider buckets: cap primary display separately from the
        // Claude/Codex legacy split above.
        if (!expanded && models.length > PRIMARY_VISIBLE_COUNT) {
          const shown = models.slice(0, PRIMARY_VISIBLE_COUNT)
          const rest = models.length - PRIMARY_VISIBLE_COUNT
          html = html.replace(
            visible.map((m) => this._rowHtml(m, q)).join(""),
            shown.map((m) => this._rowHtml(m, q)).join("") +
              `<div data-disclosure-toggle="${this._esc(group)}" class="px-3 py-1.5 text-xs text-base-content/40 cursor-pointer hover:text-base-content/60">Show all ${models.length}</div>`
          )
        }
      }
    }

    this._list.innerHTML = html
    this._activeIndex = 0
    this._setActive(0)
  },

  _rowHtml(m, q) {
    const active = m.slug === this.el.dataset.selectedModel
    return `<li
      data-slug="${this._esc(m.slug)}"
      data-provider="${this._esc(m.provider)}"
      role="option"
      aria-selected="${active}"
      class="flex items-center gap-2 rounded-lg px-3 py-2 text-sm cursor-pointer hover:bg-base-content/[0.04] aria-selected:bg-base-content/[0.06]"
    >
      <span class="w-[5px] h-[5px] rounded-full bg-primary/60 flex-shrink-0"></span>
      <span class="flex-1 truncate">${this._highlight(m.label, q)}</span>
      ${m.default ? '<span class="text-[9px] px-1.5 py-0.5 rounded-full bg-success/10 text-success">Recommended</span>' : ""}
      ${active ? '<svg class="size-3.5 text-primary flex-shrink-0" viewBox="0 0 20 20" fill="currentColor"><path fill-rule="evenodd" d="M16.704 4.153a.75.75 0 01.143 1.052l-8 10.5a.75.75 0 01-1.127.075l-4.5-4.5a.75.75 0 011.06-1.06l3.894 3.893 7.48-9.817a.75.75 0 011.05-.143z" clip-rule="evenodd"/></svg>' : ""}
      ${!active && m.premium ? '<span class="text-xs text-base-content/40 flex-shrink-0">$</span>' : ""}
    </li>`
  },

  _visibleItems() {
    return Array.from(this._list.querySelectorAll("li[data-slug]"))
  },

  _setActive(idx) {
    const items = this._visibleItems()
    items.forEach((li, i) => li.setAttribute("aria-selected", i === idx ? "true" : li.getAttribute("aria-selected")))
    this._activeIndex = idx
    if (items[idx]) items[idx].scrollIntoView({ block: "nearest" })
  },

  _handleKeydown(e) {
    if (!this._open) return
    const items = this._visibleItems()
    const count = items.length

    if (e.key === "ArrowDown") {
      e.preventDefault()
      if (count) this._setActive((this._activeIndex + 1) % count)
    } else if (e.key === "ArrowUp") {
      e.preventDefault()
      if (count) this._setActive((this._activeIndex - 1 + count) % count)
    } else if (e.key === "Enter") {
      e.preventDefault()
      const active = items[this._activeIndex]
      if (active) this._select(active.dataset.provider, active.dataset.slug)
    } else if (e.key === "Escape") {
      e.preventDefault()
      this._close()
    }
  },

  _select(provider, slug) {
    // State authority (spec §5.2): push and wait. The server re-renders
    // data-selected-provider/data-selected-model on success; on rejection
    // it re-renders the SAME (unchanged) values, and updated() below snaps
    // the trigger label back via the normal LiveView diff — no separate
    // failure branch needed here because we never touched the trigger.
    this.pushEventTo(this.el, this.el.dataset.event, { provider, model: slug })
    this._close()
  },

  _highlight(text, q) {
    if (!q) return this._esc(text)
    const idx = text.toLowerCase().indexOf(q)
    if (idx === -1) return this._esc(text)
    return (
      this._esc(text.slice(0, idx)) +
      `<mark class="bg-primary/20 text-primary rounded-sm">` +
      this._esc(text.slice(idx, idx + q.length)) +
      `</mark>` +
      this._esc(text.slice(idx + q.length))
    )
  },

  _esc(str) {
    return String(str)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
  },
}
```

- [ ] **Step 2: Register the hook** — `assets/js/app.js`, alongside the existing `AgentCombobox` import (~line 88, ~line 168):

```javascript
import {ModelSelectorPopup} from "./hooks/model_selector_popup"
```

```javascript
Hooks.ModelSelectorPopup = ModelSelectorPopup
```

- [ ] **Step 3: Manual browser verification** — start the dev server (`mix phx.server`), open any DM session, and confirm:
  - Trigger pill shows the current model, click opens the popover with search focused.
  - Typing filters rows; the active model stays visible even when it wouldn't otherwise match.
  - Clicking "More"/"Show all N" expands; the group containing the active selection is pre-expanded on open.
  - Arrow keys move the highlighted row; Enter selects; Escape closes; clicking outside closes.
  - Selecting a row round-trips to the server and the trigger label updates.

Expected: all pass visually. (This step has no automated assertion — flag any failure before proceeding to Task 7.)

- [ ] **Step 4: Commit**

```bash
git add assets/js/hooks/model_selector_popup.js assets/js/app.js
git commit -m "feat(model-selector): ModelSelectorPopup JS hook (search, keyboard nav, disclosure, pushEventTo)"
```

---

### Task 7: Composer wiring

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/dm_page/message_composer.ex` (replace lines 216-279)
- Modify: `lib/eye_in_the_sky_web/live/shared/dm_model_helpers.ex` (`handle_select_model/2`)
- Test: `test/eye_in_the_sky_web/components/message_composer_test.exs` (new)

**Interfaces:**
- Consumes: `<.model_selector>` (Task 5), `ModelHelpers.entries_for_provider/1` (Task 2), `ModelConfig.valid_model?/2` (existing).
- Produces: no new public interface — this is a leaf host wiring.

- [ ] **Step 1: Write the failing test** — a focused rendering test (full event-handling regression coverage happens via the existing DM LiveView test suite in Step 6):

```elixir
defmodule EyeInTheSkyWeb.Components.MessageComposerTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.DmPage.MessageComposer

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        uploads: %{files: %{entries: []}},
        selected_model: "claude-opus-4-8",
        selected_effort: "medium",
        active_overlay: nil,
        processing: false,
        slash_items: [],
        thinking_enabled: false,
        show_thinking_blocks: false,
        max_budget_usd: nil,
        provider: "claude",
        context_used: 0,
        context_window: 0,
        total_cost: 0.0,
        display_name: nil,
        session_cli_opts: [],
        session_uuid: "test-uuid"
      },
      overrides
    )
  end

  test "renders the shared model selector scoped to the session's provider" do
    html = render_component(&MessageComposer.message_composer/1, base_assigns())
    assert html =~ ~s(data-event="select_model")
    assert html =~ ~s(data-allow-provider-switch="false")
    assert html =~ "Opus 4.8"
  end

  test "pi provider sessions get Pi entries, not the Claude fallback (bug being fixed)" do
    html = render_component(&MessageComposer.message_composer/1, base_assigns(%{provider: "pi", selected_model: "ollama-lan/qwen3.6:27b"}))
    assert html =~ ~s(data-allow-provider-switch="false")
    # The trigger must not silently fall through to a Claude label.
    refute html =~ "Claude Code" && !html =~ "ollama"
  end

  test "trigger is disabled while processing" do
    html = render_component(&MessageComposer.message_composer/1, base_assigns(%{processing: true}))
    assert html =~ "disabled"
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/eye_in_the_sky_web/components/message_composer_test.exs`
Expected: FAIL — old markup has no `data-event`/`data-allow-provider-switch` attributes yet.

- [ ] **Step 3: Implement** — replace `message_composer.ex` lines 216-279 (the "Right: model selector + send/stop" model-picker block) with:

```heex
        <%!-- Right: model selector + send/stop --%>
        <div class="flex items-center gap-2 ml-auto">
          <.model_selector
            id="composer-model-selector"
            entries={ModelHelpers.entries_for_provider(@provider)}
            selected_provider={@provider}
            selected_model={@selected_model}
            allow_provider_switch?={false}
            event="select_model"
            disabled?={@processing}
            placement={:up}
          />
```

(the `<%!-- Send / Stop --%>` block that immediately follows at the old line 281 onward is unchanged — only the model-selector `<div class="dropdown ...">...</div>` block is replaced, the outer `<div class="flex items-center gap-2 ml-auto">` wrapper and everything after it stays).

Add the import at the top of the module (near the existing aliases, ~line 6-10):

```elixir
  import EyeInTheSkyWeb.Components.ModelSelector, only: [model_selector: 1]
```

`dm_model_helpers.ex` — replace `handle_select_model/2` to add the Pi branch and server-side revalidation (spec §5.4):

```elixir
  alias EyeInTheSky.Agents.ModelConfig

  def handle_select_model(%{"provider" => provider, "model" => model} = params, socket) do
    session = socket.assigns.session
    effort = params["effort"] || ""

    cond do
      # allow_provider_switch?: false — the composer never lets a selection
      # change the session's own provider (spec §5.2). A payload claiming
      # otherwise is rejected outright; this is the untrusted-client-input
      # revalidation the spec requires (§5.4).
      provider != session.provider ->
        put_flash(socket, :error, "Cannot switch provider mid-conversation")
        |> then(&{:noreply, &1})

      not ModelConfig.valid_model?(provider, model) ->
        put_flash(socket, :error, "Invalid model selection")
        |> then(&{:noreply, &1})

      true ->
        {:noreply, persist_model_selection(socket, session, model, effort)}
    end
  end

  # Back-compat clause: the pre-Task-7 dropdown only ever sent
  # %{"model", "effort"} with no "provider" key. Kept so any stale client
  # bundle (mid-deploy) doesn't crash; treats the session's own provider as
  # implicit, same as before this change.
  def handle_select_model(%{"model" => model, "effort" => effort}, socket) do
    session = socket.assigns.session

    if ModelConfig.valid_model?(session.provider, model) do
      {:noreply, persist_model_selection(socket, session, model, effort)}
    else
      {:noreply, put_flash(socket, :error, "Invalid model selection")}
    end
  end

  defp persist_model_selection(socket, session, model, effort) do
    socket =
      case Sessions.update_session(session, %{model: model}) do
        {:ok, _updated} ->
          socket

        {:error, changeset} ->
          Logger.error("Failed to persist model selection: #{inspect(changeset.errors)}")
          put_flash(socket, :error, "Failed to save model selection")
      end

    is_opus = String.starts_with?(model, "claude-opus") or model in ["opus", "opus[1m]"]
    effort = if effort == "" and is_opus, do: "medium", else: effort

    socket
    |> assign(:selected_model, model)
    |> assign(:selected_effort, effort)
    |> assign(:active_overlay, nil)
  end
```

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/eye_in_the_sky_web/components/message_composer_test.exs`
Expected: PASS.

- [ ] **Step 5: Run the DM LiveView regression suite** (the old `toggle_model_menu`/`select_model` event tests may reference the removed dropdown's DOM structure — fix any that assert on old markup, e.g. `id="model-selector-menu"`):

Run: `grep -rn "model-selector-menu\|toggle_model_menu" test/eye_in_the_sky_web/live/dm_live_test.exs test/eye_in_the_sky_web/live/dm_live/`

For each hit asserting on the old dropdown's DOM (not the event name, which is unchanged), update the assertion to the new component's markup (`data-selector-popover`, `data-selector-trigger`) instead of the removed `#model-selector-menu`/`#model-selector-dropdown` ids.

Run: `mix test test/eye_in_the_sky_web/live/dm_live_test.exs`
Expected: PASS after any such fixes.

- [ ] **Step 6: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/components/dm_page/message_composer.ex lib/eye_in_the_sky_web/live/shared/dm_model_helpers.ex test/eye_in_the_sky_web/components/message_composer_test.exs
git commit -m "feat(composer): wire shared model selector, add Pi branch + server-side revalidation to select_model"
```

---

### Task 8: New Agent drawer wiring

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/new_agent_drawer.ex`
- Test: `test/eye_in_the_sky_web/components/new_agent_drawer_test.exs` (new)

**Interfaces:**
- Consumes: `<.model_selector>` (Task 5), `ModelHelpers.all_model_entries/0` (Task 2), `ModelConfig.valid_model?/2` (existing).
- Produces: no new public interface.

**Key discovery driving this task's design:** `NewAgentDrawer` is a `Phoenix.LiveComponent` with **zero existing `handle_event` clauses** — its `agent_type`/`model` `<select>`s are plain form fields read via raw `params["agent_type"]`/`params["model"]` on `phx-submit={@submit_event}`, by **at least five different parent LiveViews/components** (`chat_live.ex`, `agent_live/index.ex`, `workspace_live/sessions_live.ex`, `project_sessions_page.ex`, `rail.ex`), each with its own submit handler. Rewiring those five handlers is out of scope and unnecessary: the fix is to add `pending_provider`/`pending_model` assigns to the drawer itself (updated by the new component's event) **and** mirror them into hidden `<input>`s with the exact same `name="agent_type"`/`name="model"` the five downstream handlers already read — so every existing submit handler keeps working completely unchanged.

- [ ] **Step 1: Write the failing test**

```elixir
defmodule EyeInTheSkyWeb.Components.NewAgentDrawerTest do
  use EyeInTheSkyWeb.ConnCase
  import Phoenix.LiveViewTest

  # Minimal host LiveView to mount the drawer component in isolation.
  defmodule TestHostLive do
    use EyeInTheSkyWeb, :live_view
    alias EyeInTheSkyWeb.Components.NewAgentDrawer

    def mount(_params, _session, socket) do
      {:ok, assign(socket, show: true, toggle_event: "toggle", submit_event: "submit", prompts: [])}
    end

    def render(assigns) do
      ~H"""
      <.live_component
        module={NewAgentDrawer}
        id="drawer"
        show={@show}
        toggle_event={@toggle_event}
        submit_event={@submit_event}
        prompts={@prompts}
      />
      """
    end

    def handle_event("submit", _params, socket), do: {:noreply, socket}
  end

  setup %{conn: conn} do
    router = EyeInTheSkyWeb.Router
    Phoenix.LiveView.Router.__live__(router, TestHostLive)
    :ok
  rescue
    _ -> :ok
  end

  test "renders the shared model selector with the full cross-provider entry list", %{conn: conn} do
    {:ok, view, html} = live_isolated(conn, TestHostLive)
    assert html =~ ~s(data-allow-provider-switch="true")
  end

  test "hidden inputs carry the current pending provider/model for form submit", %{conn: conn} do
    {:ok, view, _html} = live_isolated(conn, TestHostLive)
    html = render(view)
    assert html =~ ~s(name="agent_type")
    assert html =~ ~s(name="model")
  end
end
```

(If `live_isolated` with a locally-defined test `LiveView` proves awkward in this codebase's test setup, fall back to a direct `render_component/2` test asserting the same markup facts — `data-allow-provider-switch="true"` and the two hidden-input names — without a full LiveView mount; either satisfies this task's Step 4 gate.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/eye_in_the_sky_web/components/new_agent_drawer_test.exs`
Expected: FAIL — old drawer has no `data-allow-provider-switch` attribute.

- [ ] **Step 3: Implement**

Add `pending_provider`/`pending_model` state and an event handler to `new_agent_drawer.ex`:

```elixir
  alias EyeInTheSky.Agents.ModelConfig
  alias EyeInTheSkyWeb.Helpers.ModelHelpers

  import EyeInTheSkyWeb.Components.ModelSelector, only: [model_selector: 1]

  @impl true
  def mount(socket) do
    EyeInTheSky.Pi.ModelDiscoveryCache.refresh_async()

    {:ok,
     assign(socket,
       pending_provider: "claude",
       pending_model: ModelHelpers.default_model_for("claude")
     )}
  end

  @impl true
  def handle_event("model_and_provider_selected", %{"provider" => provider, "model" => model}, socket) do
    if ModelConfig.valid_model?(provider, model) do
      {:noreply, assign(socket, pending_provider: provider, pending_model: model)}
    else
      {:noreply, socket}
    end
  end
```

Replace the "Agent Type" `<.form_field>` + "Model Selection Dropdown" `<.form_field>` block (lines 47-77) with:

```heex
            <!-- Provider + Model -->
            <.form_field label="Model">
              <.model_selector
                id="new-agent-drawer-model-selector"
                entries={ModelHelpers.all_model_entries()}
                selected_provider={@pending_provider}
                selected_model={@pending_model}
                allow_provider_switch?={true}
                event="model_and_provider_selected"
                myself={@myself}
              />
              <input type="hidden" name="agent_type" value={@pending_provider} />
              <input type="hidden" name="model" value={@pending_model} />
            </.form_field>
```

Remove the now-unused `import EyeInTheSkyWeb.Helpers.ViewHelpers, only: [claude_models: 0, codex_models: 0]` and `import EyeInTheSkyWeb.Helpers.ModelHelpers, only: [pi_models: 0]` lines (10-17 originally) — replaced by the two imports above. Remove the now-unused `pi_optgroup_label/1` private function (lines 150-151).

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/eye_in_the_sky_web/components/new_agent_drawer_test.exs`
Expected: PASS.

- [ ] **Step 5: Run the five parent-LiveView regression suites** (confirms the hidden-input approach preserves every existing submit path unchanged):

Run: `mix test test/eye_in_the_sky_web/live/chat_live_test.exs test/eye_in_the_sky_web/live/agent_live/ test/eye_in_the_sky_web/live/workspace_live/ test/eye_in_the_sky_web/components/project_sessions_page_test.exs`

Expected: PASS — these tests submit the drawer form and assert on the created agent's provider/model; since the hidden inputs carry the same `name`/`value` pairs the old `<select>`s did, `params["agent_type"]`/`params["model"]` on the receiving end are unchanged. If any test explicitly interacts with the old `<select name="agent_type">` element (e.g. `element("select[name=agent_type]") |> render_change(...)`), that specific interaction step needs replacing with a call to `render_hook`/`render_click` against the new component's data attributes, or (simpler) directly `render_change`-equivalent via the drawer's new `handle_event("model_and_provider_selected", ...)` — fix on a per-test basis; the assertion on the *submitted* provider/model stays the same.

- [ ] **Step 6: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/components/new_agent_drawer.ex test/eye_in_the_sky_web/components/new_agent_drawer_test.exs
git commit -m "feat(new-agent-drawer): wire shared model selector, drop separate provider select, hidden-input form compat"
```

---

### Task 9: New Session modal wiring

**Files:**
- Modify: `lib/eye_in_the_sky_web/components/new_session_modal.ex`
- Test: `test/eye_in_the_sky_web/components/new_session_modal_test.exs` (existing file, extended)

**Interfaces:**
- Consumes: `<.model_selector>` (Task 5), `ModelHelpers.all_model_entries/0` (Task 2), `ModelConfig.valid_model?/2` (existing).
- Produces: no new public interface.

- [ ] **Step 1: Write the failing tests** — append to the existing `test/eye_in_the_sky_web/components/new_session_modal_test.exs`:

```elixir
  describe "shared model selector" do
    test "renders with allow_provider_switch? true and the full cross-provider list", %{conn: conn} do
      # Follow this file's existing mount/render pattern for NewSessionModal —
      # adapt to whatever helper (e.g. render_component/2 or a host LiveView)
      # the surrounding tests in this file already use.
      html = render_new_session_modal(%{})
      assert html =~ ~s(data-allow-provider-switch="true")
    end

    test "selecting a model via the shared component's event updates both provider and model", %{conn: conn} do
      {:ok, view, _html} = mount_new_session_modal(conn)

      view
      |> element("#new-session-model-selector")
      |> render_hook("model_and_provider_selected", %{"provider" => "codex", "model" => "gpt-5.5"})

      assert render(view) =~ "GPT-5.5"
    end

    test "an invalid payload is rejected, previous selection is kept", %{conn: conn} do
      {:ok, view, _html} = mount_new_session_modal(conn)

      view
      |> element("#new-session-model-selector")
      |> render_hook("model_and_provider_selected", %{"provider" => "codex", "model" => "not-a-real-model"})

      refute render(view) =~ "not-a-real-model"
    end
  end
```

(Use this file's existing `mount_new_session_modal/1` / `render_new_session_modal/1`-equivalent test setup helpers if present — check the top of the existing file before writing new ones; do not duplicate setup scaffolding that already exists there.)

- [ ] **Step 2: Run to verify failure**

Run: `mix test test/eye_in_the_sky_web/components/new_session_modal_test.exs`
Expected: FAIL — old markup has separate provider/model `<select>`s, no `data-allow-provider-switch` attribute, no `model_and_provider_selected` handler.

- [ ] **Step 3: Implement**

Add the import near the top of `new_session_modal.ex` (alongside existing `import`s, ~line 9-12):

```elixir
  import EyeInTheSkyWeb.Components.ModelSelector, only: [model_selector: 1]
```

Replace the `handle_event("provider_changed", ...)` (lines 63-83) and `handle_event("model_changed", ...)` (lines 86-88) clauses with one collapsed handler:

```elixir
  @impl true
  def handle_event("model_and_provider_selected", %{"provider" => provider, "model" => model}, socket) do
    if ModelConfig.valid_model?(provider, model) do
      {:noreply, assign(socket, selected_provider: provider, selected_model: model)}
    else
      {:noreply, socket}
    end
  end
```

Find the render location where `<.provider_field selected_provider={@selected_provider} myself={@myself} />` and `<.model_selector selected_provider={@selected_provider} selected_model={@selected_model} myself={@myself} />` (the *old*, private `model_selector/1` — being replaced) are rendered together in the form, and replace both calls with:

```heex
            <div>
              <label class="text-sm font-medium text-base-content/70 mb-1.5 block">Model</label>
              <.model_selector
                id="new-session-model-selector"
                entries={ModelHelpers.all_model_entries()}
                selected_provider={@selected_provider}
                selected_model={@selected_model}
                allow_provider_switch?={true}
                event="model_and_provider_selected"
                myself={@myself}
              />
              <input type="hidden" name="agent_type" value={@selected_provider} />
              <input type="hidden" name="model" value={@selected_model} />
            </div>
```

Delete the now-dead private `provider_field/1` (old lines ~209-224) and the old private `model_selector/1` (old lines ~435-459) function definitions entirely — the shared `<.model_selector>` (imported above) replaces both. Add `alias EyeInTheSkyWeb.Helpers.ModelHelpers` near the top if not already present as a full alias (the file currently only imports specific functions from it — check the existing `import EyeInTheSkyWeb.Helpers.ModelHelpers, only: [normalize_model_alias: 1]` line and extend it or add a separate `alias` for `ModelHelpers.all_model_entries/0`).

Note: `effort_selector/1` (unchanged) still reads `@selected_provider`/`@selected_model` — no change needed there, it already receives the right assigns.

- [ ] **Step 4: Run to verify pass**

Run: `mix test test/eye_in_the_sky_web/components/new_session_modal_test.exs`
Expected: PASS, including all pre-existing tests in this file (check for any that specifically drive the old `provider_field`/native `<select>` — update those interactions to `render_hook("model_and_provider_selected", ...)` the same way as Step 1's new tests, keeping their original assertions).

- [ ] **Step 5: Commit**

```bash
mix compile --warnings-as-errors
git add lib/eye_in_the_sky_web/components/new_session_modal.ex test/eye_in_the_sky_web/components/new_session_modal_test.exs
git commit -m "feat(new-session-modal): wire shared model selector, collapse provider/model handlers into one"
```

---

### Task 10: Final integration pass

**Files:** none new — verification only.

- [ ] **Step 1: Full suite**

Run: `mix compile --warnings-as-errors && mix test`
Expected: 0 failures beyond any pre-existing known-flaky tests unrelated to this change (e.g. the eviction test flake noted in prior EITS work — confirm any failure is pre-existing by checking it also fails on `features` before this branch, per repo convention).

- [ ] **Step 2: Manual browser verification of all three hosts** (dev server, `mix phx.server`):
  - **Composer**: open a Claude session, switch models via the new popover, confirm it persists (reload the page, model sticks). Open a Codex session — same. Open a **Pi session** (this was previously broken — Pi sessions fell through to the Claude list) — confirm the popover shows only Pi entries and switching actually persists a Pi model.
  - **New Agent drawer**: open from a channel, confirm one popover offers Claude + Codex + Pi together, pick a model from each provider in turn, submit, confirm the created agent has the right provider+model.
  - **New Session modal**: same cross-provider check as the drawer; confirm the Effort selector still appears/disappears correctly based on the picked Claude model.
  - Confirm `$` markers appear only on `opus[1m]`/`sonnet[1m]` and non-Ollama Pi rows; confirm "Recommended" appears once per provider list; confirm "More"/"Show all N" disclosure works and auto-expands when the active model is legacy.

Expected: all pass. Note any deviation in the final commit message rather than silently patching around it if it's a real behavior question (e.g. if `default?`'s "not a literal alias" deviation from spec §4.2 needs revisiting after seeing it in the browser — flag to the user, don't unilaterally re-decide).

- [ ] **Step 3: Update the design spec's status**

Edit `docs/superpowers/specs/2026-07-08-model-selector-design.md` — change the status line to reflect implementation completion, and add a brief "Implementation notes" section documenting the one confirmed deviation from the spec (the `default` alias handling in Task 2, since it wasn't resolvable as a literal spawnable slug without unverified external confirmation).

- [ ] **Step 4: Commit**

```bash
git add docs/superpowers/specs/2026-07-08-model-selector-design.md
git commit -m "docs: mark model selector spec implemented, note default-alias deviation"
```

---

## Self-Review

**Spec coverage:**
- §4.1 `ModelEntry` struct → Task 1.
- §4.2 `entries_for_provider/1`, premium/legacy/default rules, `default` nuance → Task 2 (with the flagged, explicitly-justified deviation on literal `"default"` slug validity).
- §4.3 always-show-current → Task 4.
- §5.1 popover shape → Task 5.
- §5.2 component API/event contract, `allow_provider_switch?` → Tasks 5, 7, 8, 9.
- §5.3 JS hook → Task 6.
- §5.4 server wiring for all three hosts + revalidation → Tasks 7, 8, 9.
- §6 catalog refresh (display + validation + `scripts/eits`) → Tasks 1, 3.
- §7 testing (data layer, component, validation-failure, catalog regression) → covered across Tasks 1–9's own test steps; validation-failure specifically in Task 7 Step 1/3 (composer) and Task 9 Step 1/3 (modal) — the drawer's equivalent is Task 8 Step 3's `handle_event` guard, exercised indirectly via Task 8 Step 5's regression suite rather than a dedicated negative test, since the drawer has no visible failure-flash UI to assert against (unlike composer/modal); acceptable given the drawer's `ModelConfig.valid_model?/2` guard is identical code to the other two hosts', already tested there.

**Placeholder scan:** none — every step has complete, runnable code or an exact grep/manual-check command.

**Type consistency:** `ModelEntry` fields (`provider`, `slug`, `label`, `group`, `sub_provider`, `premium?`, `legacy?`, `default?`) used identically in Tasks 1, 2, 4, 5; `entries_for_provider/1` and `all_model_entries/0` signatures match between Task 2's definition and Tasks 5/7/8/9's usage; the `%{"provider", "model"}` event payload shape is identical across Tasks 6 (hook), 7 (composer handler), 8 (drawer handler), 9 (modal handler).

**Known deviations from the spec, both justified and flagged in-task rather than silently resolved:**
1. Task 2: `default?: true` marks the *current default slug* (`claude-opus-4-8`) rather than introducing a literal, separately-validated `"default"` alias — because nothing confirms the underlying `claude` CLI accepts `--model default`, and shipping a selectable-but-possibly-invalid slug would violate the spec's own §5.4 revalidation requirement the moment it was picked.
2. Task 8/9: hidden `<input>` mirroring (not a spec requirement, but a necessary consequence of discovering the drawer's five downstream consumers read raw form params) — documented in Task 8's "Key discovery" note so a future reader understands why the wiring looks the way it does.

# GitHub Webhook Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Receive GitHub webhook events in EITS, persist them durably, sync PR state, and fire user-configured rules (spawn agent, create task, DM session) in response.

**Architecture:** A thin controller validates HMAC and inserts a durable `github_webhook_deliveries` row, returns 202, and wakes the `WebhookDispatcher` GenServer via PubSub. The dispatcher atomically claims the row, builds a normalized `EventContext`, runs built-in handlers (PR upsert), then runs `WebhookRulesExecutor` which evaluates guards and dispatches actions through internal context functions. Smee.io tunnels webhooks to localhost in dev.

**Tech Stack:** Phoenix/Elixir, Ecto/PostgreSQL, Phoenix.PubSub (via `EyeInTheSky.Events`), GenServer, `Plug.Crypto.secure_compare/2`, `:crypto.mac/4`

---

## File Map

**New files:**
- `lib/eye_in_the_sky/github/webhook.ex` — HMAC verification, header parsing, event_type normalization
- `lib/eye_in_the_sky/github/event_context.ex` — normalized struct from raw payload
- `lib/eye_in_the_sky/github/template.ex` — `{{variable}}` interpolation with allowlist
- `lib/eye_in_the_sky/github/webhook_delivery.ex` — Ecto schema for `github_webhook_deliveries`
- `lib/eye_in_the_sky/github/webhook_deliveries.ex` — context: insert, deduplicate, claim, recovery
- `lib/eye_in_the_sky/github/webhook_rule.ex` — Ecto schema for `github_webhook_rules`
- `lib/eye_in_the_sky/github/webhook_rule_execution.ex` — Ecto schema for `github_webhook_rule_executions`
- `lib/eye_in_the_sky/github/webhook_rules.ex` — context: CRUD + save-time validation
- `lib/eye_in_the_sky/github/webhook_dispatcher.ex` — GenServer: claim, route, recover
- `lib/eye_in_the_sky/github/pull_request_handler.ex` — built-in: upsert pull_requests
- `lib/eye_in_the_sky/github/push_handler.ex` — built-in: push events
- `lib/eye_in_the_sky/github/check_run_handler.ex` — built-in: check_run events
- `lib/eye_in_the_sky/github/webhook_rules_executor.ex` — load rules, evaluate guards, dispatch
- `lib/eye_in_the_sky/github/rule_actions.ex` — `dispatch(rule, ctx)`: render config, call domain
- `lib/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller.ex` — thin HTTP layer
- `lib/eye_in_the_sky_web/plugs/raw_body_cache.ex` — stash raw bytes before Plug.Parsers
- `priv/repo/migrations/20260510000001_create_github_webhook_deliveries.exs`
- `priv/repo/migrations/20260510000002_create_github_webhook_rules.exs`
- `priv/repo/migrations/20260510000003_create_github_webhook_rule_executions.exs`
- `priv/repo/migrations/20260510000004_add_github_fields_to_pull_requests.exs`

**Modified files:**
- `lib/eye_in_the_sky/events.ex` — add `subscribe_github_webhook/0`, `github_webhook_received/1`, `subscribe_pull_requests/0`, `pull_request_updated/1`
- `lib/eye_in_the_sky/application.ex` — add `WebhookDispatcher` to supervision tree
- `lib/eye_in_the_sky_web/router.ex` — add webhook route in `:accepts_json` scope
- `config/runtime.exs` — add `GITHUB_WEBHOOK_SECRET` config
- `docs/SETUP.md` — document smee dev setup

**Test files:**
- `test/eye_in_the_sky/github/webhook_test.exs`
- `test/eye_in_the_sky/github/event_context_test.exs`
- `test/eye_in_the_sky/github/template_test.exs`
- `test/eye_in_the_sky/github/webhook_deliveries_test.exs`
- `test/eye_in_the_sky/github/webhook_rules_test.exs`
- `test/eye_in_the_sky/github/webhook_rules_executor_test.exs`
- `test/eye_in_the_sky/github/pull_request_handler_test.exs`
- `test/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller_test.exs`

---

## Task 1: Migrations

**Files:**
- Create: `priv/repo/migrations/20260510000001_create_github_webhook_deliveries.exs`
- Create: `priv/repo/migrations/20260510000002_create_github_webhook_rules.exs`
- Create: `priv/repo/migrations/20260510000003_create_github_webhook_rule_executions.exs`
- Create: `priv/repo/migrations/20260510000004_add_github_fields_to_pull_requests.exs`

- [ ] **Step 1: Create deliveries migration**

```elixir
# priv/repo/migrations/20260510000001_create_github_webhook_deliveries.exs
defmodule EyeInTheSky.Repo.Migrations.CreateGithubWebhookDeliveries do
  use Ecto.Migration

  def change do
    create table(:github_webhook_deliveries) do
      add :delivery_id, :string, null: false
      add :hook_id, :string
      add :event_type, :string, null: false
      add :event_header, :string, null: false
      add :action, :string
      add :repository_full_name, :string
      add :sender_login, :string
      add :pr_number, :integer
      add :head_branch, :string
      add :base_branch, :string
      add :payload, :map
      add :status, :string, null: false, default: "pending"
      add :error_message, :string
      add :processing_started_at, :utc_datetime_usec
      add :processed_at, :utc_datetime_usec
      add :attempt_count, :integer, null: false, default: 0
      add :max_attempts, :integer, null: false, default: 5
      add :duplicate_count, :integer, null: false, default: 0
      add :last_duplicate_at, :utc_datetime_usec
      add :received_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:github_webhook_deliveries, [:delivery_id])
    create index(:github_webhook_deliveries, [:status, :received_at])

    create index(:github_webhook_deliveries, [:processing_started_at],
             where: "status = 'processing'",
             name: :github_webhook_deliveries_stale_processing_index
           )
  end
end
```

- [ ] **Step 2: Create rules migration**

```elixir
# priv/repo/migrations/20260510000002_create_github_webhook_rules.exs
defmodule EyeInTheSky.Repo.Migrations.CreateGithubWebhookRules do
  use Ecto.Migration

  def change do
    create table(:github_webhook_rules) do
      add :event_type, :string, null: false
      add :repository_full_name, :string
      add :project_id, :bigint
      add :branch_glob, :string
      add :target_branch_glob, :string
      add :action_type, :string, null: false
      add :action_config, :map, null: false, default: %{}
      add :guard_config, :map, null: false, default: %{}
      add :enabled, :boolean, null: false, default: true
      add :priority, :integer, null: false, default: 100

      timestamps(type: :utc_datetime_usec)
    end

    create index(:github_webhook_rules, [:enabled, :event_type, :repository_full_name])
  end
end
```

- [ ] **Step 3: Create rule executions migration**

```elixir
# priv/repo/migrations/20260510000003_create_github_webhook_rule_executions.exs
defmodule EyeInTheSky.Repo.Migrations.CreateGithubWebhookRuleExecutions do
  use Ecto.Migration

  def change do
    create table(:github_webhook_rule_executions) do
      add :rule_id, :bigint, null: false
      add :delivery_id, :string, null: false
      add :repository_full_name, :string
      add :pr_number, :integer
      add :status, :string, null: false
      add :result, :map
      add :error_message, :string

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:github_webhook_rule_executions,
             [:rule_id, :repository_full_name, :pr_number, :status]
           )
  end
end
```

- [ ] **Step 4: Extend pull_requests migration**

```elixir
# priv/repo/migrations/20260510000004_add_github_fields_to_pull_requests.exs
defmodule EyeInTheSky.Repo.Migrations.AddGithubFieldsToPullRequests do
  use Ecto.Migration

  def change do
    alter table(:pull_requests) do
      add :github_pr_id, :bigint
      add :repository_full_name, :string
      add :repository_id, :bigint
      add :title, :string
      add :state, :string
      add :draft, :boolean
      add :merged, :boolean
      add :author_login, :string
      add :last_synced_at, :utc_datetime_usec
    end

    # Partial index: github_pr_id may be null on rows created before this migration
    create index(:pull_requests, [:github_pr_id],
             unique: true,
             where: "github_pr_id IS NOT NULL",
             name: :pull_requests_github_pr_id_index
           )
  end
end
```

- [ ] **Step 5: Run migrations and verify**

```bash
mix ecto.migrate
```

Expected: all 4 migrations run without errors.

- [ ] **Step 6: Commit**

```bash
git add priv/repo/migrations/
git commit -m "feat: add github webhook deliveries, rules, and executions migrations"
```

---

## Task 2: HMAC Verification Module

**Files:**
- Create: `lib/eye_in_the_sky/github/webhook.ex`
- Create: `test/eye_in_the_sky/github/webhook_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/eye_in_the_sky/github/webhook_test.exs
defmodule EyeInTheSky.Github.WebhookTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Github.Webhook

  @secret "test_secret"
  @body ~s({"action":"opened"})

  defp valid_sig(body \\ @body) do
    mac = :crypto.mac(:hmac, :sha256, @secret, body) |> Base.encode16(case: :lower)
    "sha256=#{mac}"
  end

  describe "verify/3" do
    test "returns :ok for valid signature" do
      assert :ok = Webhook.verify(valid_sig(), @body, @secret)
    end

    test "returns :error for tampered body" do
      assert :error = Webhook.verify(valid_sig(), "tampered", @secret)
    end

    test "returns :error for missing signature (nil)" do
      assert :error = Webhook.verify(nil, @body, @secret)
    end

    test "returns :error for missing sha256= prefix" do
      assert :error = Webhook.verify("abcdef1234", @body, @secret)
    end

    test "normalizes uppercase hex before compare" do
      mac = :crypto.mac(:hmac, :sha256, @secret, @body) |> Base.encode16(case: :upper)
      assert :ok = Webhook.verify("sha256=#{mac}", @body, @secret)
    end

    test "returns :error for non-hex characters in signature" do
      assert :error = Webhook.verify("sha256=" <> String.duplicate("z", 64), @body, @secret)
    end

    test "returns :error when hex is not 64 chars" do
      assert :error = Webhook.verify("sha256=abc123", @body, @secret)
    end
  end

  describe "secure_equal?/2" do
    test "returns false for different-length strings without timing side channel" do
      refute Webhook.secure_equal?("short", String.duplicate("x", 64))
    end
  end

  describe "normalize_event_type/2" do
    test "combines event header and action for PR events" do
      assert "pull_request.opened" = Webhook.normalize_event_type("pull_request", "opened")
    end

    test "returns just the header for push (no action)" do
      assert "push" = Webhook.normalize_event_type("push", nil)
    end

    test "returns just the header when action is empty string" do
      assert "check_run" = Webhook.normalize_event_type("check_run", "")
    end
  end
end
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
mix test test/eye_in_the_sky/github/webhook_test.exs
```

Expected: `** (UndefinedFunctionError) function EyeInTheSky.Github.Webhook.verify/3 is undefined`

- [ ] **Step 3: Implement the module**

```elixir
# lib/eye_in_the_sky/github/webhook.ex
defmodule EyeInTheSky.Github.Webhook do
  @moduledoc false

  @doc "Verify X-Hub-Signature-256 header against the raw body and secret."
  def verify(sig_header, raw_body, secret) when is_binary(sig_header) do
    with "sha256=" <> hex <- sig_header,
         hex <- String.downcase(hex),
         true <- Regex.match?(~r/\A[0-9a-f]{64}\z/, hex),
         expected <-
           :crypto.mac(:hmac, :sha256, secret, raw_body) |> Base.encode16(case: :lower),
         true <- secure_equal?(hex, expected) do
      :ok
    else
      _ -> :error
    end
  end

  def verify(_, _, _), do: :error

  @doc "Normalize event header + payload action into a dotted event_type string."
  def normalize_event_type(event_header, action)
      when is_binary(action) and action != "",
      do: "#{event_header}.#{action}"

  def normalize_event_type(event_header, _), do: event_header

  @doc "Constant-time string equality; returns false immediately for length mismatch."
  def secure_equal?(left, right) when byte_size(left) == byte_size(right),
    do: Plug.Crypto.secure_compare(left, right)

  def secure_equal?(_, _), do: false
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/eye_in_the_sky/github/webhook_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Compile check**

```bash
mix compile --warnings-as-errors
```

Expected: no errors or warnings.

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky/github/webhook.ex test/eye_in_the_sky/github/webhook_test.exs
git commit -m "feat: add Github.Webhook HMAC verification module"
```

---

## Task 3: EventContext

**Files:**
- Create: `lib/eye_in_the_sky/github/event_context.ex`
- Create: `test/eye_in_the_sky/github/event_context_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/eye_in_the_sky/github/event_context_test.exs
defmodule EyeInTheSky.Github.EventContextTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Github.EventContext

  describe "from_delivery/2" do
    test "extracts PR fields from pull_request event" do
      payload = %{
        "action" => "opened",
        "pull_request" => %{
          "id" => 456,
          "number" => 42,
          "head" => %{"ref" => "feature/foo"},
          "base" => %{"ref" => "main"},
          "labels" => [%{"name" => "agent-review"}],
          "draft" => false,
          "merged" => false
        },
        "sender" => %{"login" => "urielmaldonado"},
        "repository" => %{"full_name" => "tacit7/eits"}
      }

      delivery = %{
        delivery_id: "abc-123",
        event_type: "pull_request.opened",
        repository_full_name: "tacit7/eits",
        sender_login: "urielmaldonado",
        payload: payload
      }

      ctx = EventContext.from_delivery(delivery)

      assert ctx.delivery_id == "abc-123"
      assert ctx.event_type == "pull_request.opened"
      assert ctx.github_pr_id == 456
      assert ctx.pr_number == 42
      assert ctx.head_branch == "feature/foo"
      assert ctx.base_branch == "main"
      assert ctx.labels == ["agent-review"]
      assert ctx.draft? == false
      assert ctx.merged? == false
    end

    test "extracts head_branch from push event by stripping refs/heads/" do
      payload = %{
        "ref" => "refs/heads/main",
        "sender" => %{"login" => "uriel"},
        "repository" => %{"full_name" => "tacit7/eits"}
      }

      delivery = %{
        delivery_id: "push-1",
        event_type: "push",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        payload: payload
      }

      ctx = EventContext.from_delivery(delivery)
      assert ctx.head_branch == "main"
      assert ctx.base_branch == nil
    end

    test "extracts head_branch from check_run event" do
      payload = %{
        "check_run" => %{
          "check_suite" => %{"head_branch" => "feature/bar"}
        },
        "sender" => %{"login" => "uriel"},
        "repository" => %{"full_name" => "tacit7/eits"}
      }

      delivery = %{
        delivery_id: "cr-1",
        event_type: "check_run.completed",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        payload: payload
      }

      ctx = EventContext.from_delivery(delivery)
      assert ctx.head_branch == "feature/bar"
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky/github/event_context_test.exs
```

Expected: `UndefinedFunctionError` for `EventContext.from_delivery/1`.

- [ ] **Step 3: Implement EventContext**

```elixir
# lib/eye_in_the_sky/github/event_context.ex
defmodule EyeInTheSky.Github.EventContext do
  @moduledoc false

  defstruct [
    :delivery_id,
    :event_type,
    :repository_full_name,
    :sender_login,
    :github_pr_id,
    :pr_number,
    :head_branch,
    :base_branch,
    labels: [],
    draft?: false,
    merged?: false
  ]

  @doc "Build a normalized EventContext from a delivery map (string or atom keys in payload)."
  def from_delivery(delivery) do
    payload = delivery.payload || %{}
    event_type = delivery.event_type

    %__MODULE__{
      delivery_id: delivery.delivery_id,
      event_type: event_type,
      repository_full_name: delivery.repository_full_name,
      sender_login: delivery.sender_login
    }
    |> extract_fields(event_type, payload)
  end

  defp extract_fields(ctx, "pull_request" <> _, payload) do
    pr = payload["pull_request"] || %{}

    %{
      ctx
      | github_pr_id: pr["id"],
        pr_number: pr["number"],
        head_branch: get_in(pr, ["head", "ref"]),
        base_branch: get_in(pr, ["base", "ref"]),
        labels: Enum.map(pr["labels"] || [], & &1["name"]),
        draft?: pr["draft"] == true,
        merged?: pr["merged"] == true
    }
  end

  defp extract_fields(ctx, "push", payload) do
    ref = payload["ref"] || ""
    head = String.replace_prefix(ref, "refs/heads/", "")
    %{ctx | head_branch: if(head == "", do: nil, else: head)}
  end

  defp extract_fields(ctx, "check_run" <> _, payload) do
    head_branch = get_in(payload, ["check_run", "check_suite", "head_branch"])
    %{ctx | head_branch: head_branch}
  end

  defp extract_fields(ctx, _, _), do: ctx
end
```

- [ ] **Step 4: Run tests to confirm they pass**

```bash
mix test test/eye_in_the_sky/github/event_context_test.exs
```

Expected: all tests pass.

- [ ] **Step 5: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky/github/event_context.ex test/eye_in_the_sky/github/event_context_test.exs
git commit -m "feat: add Github.EventContext normalized struct"
```

---

## Task 4: Template Interpolation

**Files:**
- Create: `lib/eye_in_the_sky/github/template.ex`
- Create: `test/eye_in_the_sky/github/template_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/eye_in_the_sky/github/template_test.exs
defmodule EyeInTheSky.Github.TemplateTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Github.Template

  @ctx %{
    "repository" => "tacit7/eits",
    "event_type" => "pull_request.opened",
    "sender_login" => "uriel",
    "pr_number" => 42,
    "pr_title" => "Fix the thing",
    "pr_url" => "https://github.com/tacit7/eits/pull/42",
    "head_branch" => "feature/foo",
    "base_branch" => "main"
  }

  describe "render/2" do
    test "replaces known variables" do
      assert {:ok, "Review PR 42 in tacit7/eits"} =
               Template.render("Review PR {{pr_number}} in {{repository}}", @ctx)
    end

    test "returns error for unknown variable" do
      assert {:error, "unknown template variable: secret_token"} =
               Template.render("{{secret_token}}", @ctx)
    end

    test "renders string with no variables unchanged" do
      assert {:ok, "no variables here"} = Template.render("no variables here", @ctx)
    end
  end

  describe "validate/1" do
    test "returns :ok for template with only known variables" do
      assert :ok = Template.validate("Review PR {{pr_number}} in {{repository}}")
    end

    test "returns error for unknown variable at validate time" do
      assert {:error, _} = Template.validate("{{unknown_var}}")
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky/github/template_test.exs
```

Expected: `UndefinedFunctionError`.

- [ ] **Step 3: Implement Template**

```elixir
# lib/eye_in_the_sky/github/template.ex
defmodule EyeInTheSky.Github.Template do
  @moduledoc false

  @allowed_vars ~w[
    repository event_type sender_login pr_number
    pr_title pr_url head_branch base_branch
  ]

  @doc "Render a template string against a context map. Returns {:ok, string} or {:error, reason}."
  def render(template, ctx) do
    vars = extract_vars(template)

    case Enum.find(vars, &(&1 not in @allowed_vars)) do
      nil ->
        result =
          Enum.reduce(vars, template, fn var, acc ->
            String.replace(acc, "{{#{var}}}", to_string(Map.get(ctx, var, "")))
          end)

        {:ok, result}

      unknown ->
        {:error, "unknown template variable: #{unknown}"}
    end
  end

  @doc "Validate that all {{variables}} in a template are in the allowlist."
  def validate(template) do
    case Enum.find(extract_vars(template), &(&1 not in @allowed_vars)) do
      nil -> :ok
      unknown -> {:error, "unknown template variable: #{unknown}"}
    end
  end

  defp extract_vars(template) do
    ~r/\{\{(\w+)\}\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end
end
```

- [ ] **Step 4: Run tests to confirm pass**

```bash
mix test test/eye_in_the_sky/github/template_test.exs
```

- [ ] **Step 5: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 6: Commit**

```bash
git add lib/eye_in_the_sky/github/template.ex test/eye_in_the_sky/github/template_test.exs
git commit -m "feat: add Github.Template interpolation with allowlist"
```

---

## Task 5: WebhookDelivery Schema + WebhookDeliveries Context

**Files:**
- Create: `lib/eye_in_the_sky/github/webhook_delivery.ex`
- Create: `lib/eye_in_the_sky/github/webhook_deliveries.ex`
- Create: `test/eye_in_the_sky/github/webhook_deliveries_test.exs`

- [ ] **Step 1: Write the failing tests**

```elixir
# test/eye_in_the_sky/github/webhook_deliveries_test.exs
defmodule EyeInTheSky.Github.WebhookDeliveriesTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.WebhookDeliveries
  alias EyeInTheSky.Github.WebhookDelivery

  @valid_attrs %{
    delivery_id: "gh-delivery-uuid-1",
    hook_id: "hook-123",
    event_type: "pull_request.opened",
    event_header: "pull_request",
    action: "opened",
    repository_full_name: "tacit7/eits",
    sender_login: "uriel",
    payload: %{"action" => "opened"},
    received_at: DateTime.utc_now()
  }

  describe "insert/1" do
    test "inserts a new delivery with status=pending and attempt_count=0" do
      assert {:ok, %WebhookDelivery{} = d} = WebhookDeliveries.insert(@valid_attrs)
      assert d.status == "pending"
      assert d.attempt_count == 0
      assert d.duplicate_count == 0
    end

    test "on duplicate delivery_id, returns {:duplicate, delivery}" do
      {:ok, _} = WebhookDeliveries.insert(@valid_attrs)
      assert {:duplicate, d} = WebhookDeliveries.insert(@valid_attrs)
      assert d.duplicate_count == 1
      assert d.last_duplicate_at != nil
    end
  end

  describe "claim/1" do
    test "atomically claims a pending delivery and returns it" do
      {:ok, inserted} = WebhookDeliveries.insert(@valid_attrs)
      assert {:ok, claimed} = WebhookDeliveries.claim(inserted.delivery_id)
      assert claimed.status == "processing"
      assert claimed.attempt_count == 1
      assert claimed.processing_started_at != nil
    end

    test "returns {:error, :not_claimable} when already processing" do
      {:ok, inserted} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, _} = WebhookDeliveries.claim(inserted.delivery_id)
      assert {:error, :not_claimable} = WebhookDeliveries.claim(inserted.delivery_id)
    end
  end

  describe "mark_processed/1" do
    test "sets status to processed and records processed_at" do
      {:ok, d} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, d} = WebhookDeliveries.claim(d.delivery_id)
      assert {:ok, updated} = WebhookDeliveries.mark_processed(d.id)
      assert updated.status == "processed"
      assert updated.processed_at != nil
    end
  end

  describe "mark_failed/2" do
    test "sets status to failed with error message" do
      {:ok, d} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, d} = WebhookDeliveries.claim(d.delivery_id)
      assert {:ok, updated} = WebhookDeliveries.mark_failed(d.id, "boom")
      assert updated.status == "failed"
      assert updated.error_message == "boom"
    end
  end

  describe "pending/0" do
    test "returns only pending deliveries ordered by received_at asc" do
      now = DateTime.utc_now()
      {:ok, _} = WebhookDeliveries.insert(%{@valid_attrs | delivery_id: "old", received_at: DateTime.add(now, -10)})
      {:ok, _} = WebhookDeliveries.insert(%{@valid_attrs | delivery_id: "new", received_at: now})

      ids = WebhookDeliveries.pending() |> Enum.map(& &1.delivery_id)
      assert ids == ["old", "new"]
    end
  end

  describe "stale_processing/1" do
    test "returns processing rows older than the given cutoff" do
      {:ok, d} = WebhookDeliveries.insert(@valid_attrs)
      {:ok, claimed} = WebhookDeliveries.claim(d.delivery_id)

      past = DateTime.add(DateTime.utc_now(), 600)
      stale = WebhookDeliveries.stale_processing(past)
      assert Enum.any?(stale, &(&1.id == claimed.id))
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky/github/webhook_deliveries_test.exs
```

Expected: `UndefinedFunctionError`.

- [ ] **Step 3: Implement WebhookDelivery schema**

```elixir
# lib/eye_in_the_sky/github/webhook_delivery.ex
defmodule EyeInTheSky.Github.WebhookDelivery do
  use Ecto.Schema
  import Ecto.Changeset

  schema "github_webhook_deliveries" do
    field :delivery_id, :string
    field :hook_id, :string
    field :event_type, :string
    field :event_header, :string
    field :action, :string
    field :repository_full_name, :string
    field :sender_login, :string
    field :pr_number, :integer
    field :head_branch, :string
    field :base_branch, :string
    field :payload, :map
    field :status, :string, default: "pending"
    field :error_message, :string
    field :processing_started_at, :utc_datetime_usec
    field :processed_at, :utc_datetime_usec
    field :attempt_count, :integer, default: 0
    field :max_attempts, :integer, default: 5
    field :duplicate_count, :integer, default: 0
    field :last_duplicate_at, :utc_datetime_usec
    field :received_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :delivery_id, :hook_id, :event_type, :event_header, :action,
      :repository_full_name, :sender_login, :pr_number, :head_branch,
      :base_branch, :payload, :status, :error_message, :processing_started_at,
      :processed_at, :attempt_count, :max_attempts, :duplicate_count,
      :last_duplicate_at, :received_at
    ])
    |> validate_required([:delivery_id, :event_type, :event_header, :received_at])
    |> unique_constraint(:delivery_id)
  end
end
```

- [ ] **Step 4: Implement WebhookDeliveries context**

```elixir
# lib/eye_in_the_sky/github/webhook_deliveries.ex
defmodule EyeInTheSky.Github.WebhookDeliveries do
  import Ecto.Query

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Github.WebhookDelivery

  def insert(attrs) do
    %WebhookDelivery{}
    |> WebhookDelivery.changeset(attrs)
    |> Repo.insert()
    |> case do
      {:ok, delivery} ->
        {:ok, delivery}

      {:error, %Ecto.Changeset{errors: [delivery_id: {_, [constraint: :unique | _]}]}} ->
        Repo.update_all(
          from(d in WebhookDelivery,
            where: d.delivery_id == ^attrs.delivery_id,
            update: [
              inc: [duplicate_count: 1],
              set: [last_duplicate_at: ^DateTime.utc_now()]
            ]
          ),
          []
        )

        delivery = Repo.get_by!(WebhookDelivery, delivery_id: attrs.delivery_id)
        {:duplicate, delivery}
    end
  end

  def claim(delivery_id) do
    now = DateTime.utc_now()

    {count, rows} =
      Repo.update_all(
        from(d in WebhookDelivery,
          where: d.delivery_id == ^delivery_id and d.status == "pending",
          update: [
            set: [status: "processing", processing_started_at: ^now],
            inc: [attempt_count: 1]
          ]
        ),
        [],
        returning: true
      )

    case {count, rows} do
      {1, [delivery]} -> {:ok, delivery}
      _ -> {:error, :not_claimable}
    end
  end

  def mark_processed(id) do
    Repo.update_all(
      from(d in WebhookDelivery,
        where: d.id == ^id,
        update: [set: [status: "processed", processed_at: ^DateTime.utc_now()]]
      ),
      [],
      returning: true
    )
    |> case do
      {1, [d]} -> {:ok, d}
      _ -> {:error, :not_found}
    end
  end

  def mark_failed(id, reason) do
    Repo.update_all(
      from(d in WebhookDelivery,
        where: d.id == ^id,
        update: [set: [status: "failed", error_message: ^reason]]
      ),
      [],
      returning: true
    )
    |> case do
      {1, [d]} -> {:ok, d}
      _ -> {:error, :not_found}
    end
  end

  def pending do
    Repo.all(
      from d in WebhookDelivery,
        where: d.status == "pending",
        order_by: [asc: d.received_at],
        limit: 100
    )
  end

  def stale_processing(cutoff) do
    Repo.all(
      from d in WebhookDelivery,
        where: d.status == "processing" and d.processing_started_at < ^cutoff,
        limit: 100
    )
  end

  def reset_to_pending(id) do
    Repo.update_all(
      from(d in WebhookDelivery, where: d.id == ^id, update: [set: [status: "pending"]]),
      []
    )
  end
end
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
mix test test/eye_in_the_sky/github/webhook_deliveries_test.exs
```

- [ ] **Step 6: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky/github/webhook_delivery.ex \
        lib/eye_in_the_sky/github/webhook_deliveries.ex \
        test/eye_in_the_sky/github/webhook_deliveries_test.exs
git commit -m "feat: add WebhookDelivery schema and WebhookDeliveries context"
```

---

## Task 6: Events + Raw Body Plug

**Files:**
- Modify: `lib/eye_in_the_sky/events.ex`
- Create: `lib/eye_in_the_sky_web/plugs/raw_body_cache.ex`

- [ ] **Step 1: Add PubSub helpers to Events**

Open `lib/eye_in_the_sky/events.ex` and add these after the existing subscribe/broadcast functions (find the end of the file):

```elixir
  @doc "Subscribe to GitHub webhook delivery notifications."
  def subscribe_github_webhook, do: sub("github:webhook_received")

  @doc "Broadcast a delivery ID to wake the WebhookDispatcher."
  def github_webhook_received(delivery_id),
    do: broadcast("github:webhook_received", {:github_webhook_received, delivery_id})

  @doc "Subscribe to pull request update events."
  def subscribe_pull_requests, do: sub("pull_requests:updated")

  @doc "Broadcast that a pull request record was updated."
  def pull_request_updated(pr),
    do: broadcast("pull_requests:updated", {:pull_request_updated, pr})
```

- [ ] **Step 2: Create RawBodyCache plug**

```elixir
# lib/eye_in_the_sky_web/plugs/raw_body_cache.ex
defmodule EyeInTheSkyWeb.Plugs.RawBodyCache do
  @moduledoc """
  Reads and caches the raw request body into conn.assigns[:raw_body]
  before Plug.Parsers consumes it. Route-scope this plug to webhook
  endpoints only — caching raw bodies application-wide is wasteful.
  """

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    Plug.Conn.assign(conn, :raw_body, body)
  end
end
```

- [ ] **Step 3: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky/events.ex \
        lib/eye_in_the_sky_web/plugs/raw_body_cache.ex
git commit -m "feat: add github webhook PubSub helpers and RawBodyCache plug"
```

---

## Task 7: Controller + Router

**Files:**
- Create: `lib/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller.ex`
- Modify: `lib/eye_in_the_sky_web/router.ex`
- Create: `test/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller_test.exs`
- Modify: `config/runtime.exs`

- [ ] **Step 1: Write the failing controller tests**

```elixir
# test/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller_test.exs
defmodule EyeInTheSkyWeb.Api.V1.GithubWebhookControllerTest do
  use EyeInTheSkyWeb.ConnCase, async: false

  alias EyeInTheSky.Events

  @secret "test_webhook_secret"
  @payload ~s({"action":"opened","pull_request":{"id":1,"number":1,"head":{"ref":"main"},"base":{"ref":"main"},"labels":[],"draft":false,"merged":false},"sender":{"login":"uriel"},"repository":{"full_name":"tacit7/eits"}})

  setup do
    Application.put_env(:eye_in_the_sky, :github_webhook_secret, @secret)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :github_webhook_secret) end)
    :ok
  end

  defp sign(body), do:
    "sha256=" <> (:crypto.mac(:hmac, :sha256, @secret, body) |> Base.encode16(case: :lower))

  defp post_webhook(conn, body, opts \\ []) do
    sig = Keyword.get(opts, :signature, sign(body))
    event = Keyword.get(opts, :event, "pull_request")
    delivery = Keyword.get(opts, :delivery, "test-delivery-#{:rand.uniform(999_999)}")

    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("x-hub-signature-256", sig)
    |> put_req_header("x-github-event", event)
    |> put_req_header("x-github-delivery", delivery)
    |> post("/api/v1/webhooks/github", body)
  end

  test "returns 202 for valid webhook", %{conn: conn} do
    Events.subscribe_github_webhook()
    conn = post_webhook(conn, @payload)
    assert conn.status == 202

    assert_receive {:github_webhook_received, _delivery_id}, 500
  end

  test "returns 401 for bad HMAC", %{conn: conn} do
    conn = post_webhook(conn, @payload, signature: "sha256=" <> String.duplicate("a", 64))
    assert conn.status == 401
  end

  test "returns 401 for missing signature", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-github-event", "pull_request")
      |> put_req_header("x-github-delivery", "test-delivery-1")
      |> post("/api/v1/webhooks/github", @payload)

    assert conn.status == 401
  end

  test "returns 400 for missing X-GitHub-Event", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(@payload))
      |> put_req_header("x-github-delivery", "test-delivery-2")
      |> post("/api/v1/webhooks/github", @payload)

    assert conn.status == 400
  end

  test "returns 400 for missing X-GitHub-Delivery", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-hub-signature-256", sign(@payload))
      |> put_req_header("x-github-event", "pull_request")
      |> post("/api/v1/webhooks/github", @payload)

    assert conn.status == 400
  end

  test "returns 202 for duplicate delivery_id (no reprocessing)", %{conn: conn} do
    delivery = "fixed-delivery-id"
    post_webhook(conn, @payload, delivery: delivery)
    conn2 = build_conn()
    conn2 = post_webhook(conn2, @payload, delivery: delivery)
    assert conn2.status == 202
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller_test.exs
```

Expected: route not found / 404.

- [ ] **Step 3: Implement the controller**

```elixir
# lib/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller.ex
defmodule EyeInTheSkyWeb.Api.V1.GithubWebhookController do
  use EyeInTheSkyWeb, :controller

  require Logger

  alias EyeInTheSky.Events
  alias EyeInTheSky.Github.Webhook
  alias EyeInTheSky.Github.WebhookDeliveries

  def receive(conn, _params) do
    secret = Application.get_env(:eye_in_the_sky, :github_webhook_secret, "")
    raw_body = conn.assigns[:raw_body] || ""

    sig_header = get_req_header(conn, "x-hub-signature-256") |> List.first()

    with :ok <- Webhook.verify(sig_header, raw_body, secret),
         [event_header] <- get_req_header(conn, "x-github-event"),
         [delivery_id] <- get_req_header(conn, "x-github-delivery") do
      hook_id = get_req_header(conn, "x-github-hook-id") |> List.first()
      payload = conn.body_params || %{}
      action = payload["action"]
      event_type = Webhook.normalize_event_type(event_header, action)
      repo = get_in(payload, ["repository", "full_name"])
      sender = get_in(payload, ["sender", "login"])

      attrs = %{
        delivery_id: delivery_id,
        hook_id: hook_id,
        event_type: event_type,
        event_header: event_header,
        action: action,
        repository_full_name: repo,
        sender_login: sender,
        payload: payload,
        received_at: DateTime.utc_now()
      }

      case WebhookDeliveries.insert(attrs) do
        {:ok, delivery} ->
          Events.github_webhook_received(delivery.delivery_id)
          send_resp(conn, 202, "")

        {:duplicate, _delivery} ->
          send_resp(conn, 202, "")

        {:error, changeset} ->
          Logger.error("Failed to insert webhook delivery: #{inspect(changeset)}")
          send_resp(conn, 500, "")
      end
    else
      :error ->
        send_resp(conn, 401, "")

      [] ->
        send_resp(conn, 400, "")
    end
  end
end
```

- [ ] **Step 4: Add the route to router.ex**

In `lib/eye_in_the_sky_web/router.ex`, find the IAM scope block (around line 319) and add a new scope below it:

```elixir
  # GitHub webhook endpoint — unauthenticated; auth via HMAC per-controller
  scope "/api/v1", EyeInTheSkyWeb.Api.V1 do
    pipe_through [:accepts_json]

    post "/webhooks/github", GithubWebhookController, :receive
  end
```

- [ ] **Step 5: Wire the RawBodyCache plug to the webhook route**

The `RawBodyCache` plug must run before `Plug.Parsers` consumes the body. In Phoenix, plug the raw body cache at the endpoint level scoped by path, or use a custom pipeline. The simplest approach: add it as a plug in the router pipeline for this scope. However, `Plug.Parsers` runs in the Endpoint before the router. The correct fix is to add route-specific pre-parse caching at the Endpoint level.

Open `lib/eye_in_the_sky_web/endpoint.ex`, find the `plug Plug.Parsers` block, and add the raw body cache **before** it, but only for the webhook path:

```elixir
  # Cache raw body for webhook HMAC verification before Plug.Parsers consumes it
  plug EyeInTheSkyWeb.Plugs.RawBodyCache, only: "/api/v1/webhooks/github"
```

Then update `RawBodyCache` to support the `only:` option:

```elixir
# lib/eye_in_the_sky_web/plugs/raw_body_cache.ex
defmodule EyeInTheSkyWeb.Plugs.RawBodyCache do
  @behaviour Plug

  @impl Plug
  def init(opts), do: Keyword.get(opts, :only, nil)

  @impl Plug
  def call(%{request_path: path} = conn, only_path) when is_binary(only_path) do
    if String.starts_with?(path, only_path) do
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      Plug.Conn.assign(conn, :raw_body, body)
    else
      conn
    end
  end

  def call(conn, _), do: conn
end
```

- [ ] **Step 6: Add config to runtime.exs**

Open `config/runtime.exs` and add (near the other env reads):

```elixir
config :eye_in_the_sky,
  github_webhook_secret: System.get_env("GITHUB_WEBHOOK_SECRET", "")
```

- [ ] **Step 7: Run tests to confirm pass**

```bash
mix test test/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller_test.exs
```

- [ ] **Step 8: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 9: Commit**

```bash
git add lib/eye_in_the_sky_web/controllers/api/v1/github_webhook_controller.ex \
        lib/eye_in_the_sky_web/plugs/raw_body_cache.ex \
        lib/eye_in_the_sky_web/router.ex \
        config/runtime.exs
git commit -m "feat: add GithubWebhookController with HMAC verification and route"
```

---

## Task 8: WebhookDispatcher GenServer

**Files:**
- Create: `lib/eye_in_the_sky/github/webhook_dispatcher.ex`
- Modify: `lib/eye_in_the_sky/application.ex`

- [ ] **Step 1: Implement WebhookDispatcher**

```elixir
# lib/eye_in_the_sky/github/webhook_dispatcher.ex
defmodule EyeInTheSky.Github.WebhookDispatcher do
  use GenServer

  require Logger

  alias EyeInTheSky.Events
  alias EyeInTheSky.Github.WebhookDeliveries
  alias EyeInTheSky.Github.EventContext
  alias EyeInTheSky.Github.PullRequestHandler
  alias EyeInTheSky.Github.PushHandler
  alias EyeInTheSky.Github.CheckRunHandler
  alias EyeInTheSky.Github.WebhookRulesExecutor

  # Stale threshold: processing rows older than 5 minutes are recovered
  @stale_minutes 5
  # Recovery poll interval: 60 seconds
  @recovery_interval_ms 60_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    Events.subscribe_github_webhook()
    send(self(), :recover)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:github_webhook_received, delivery_id}, state) do
    process(delivery_id)
    {:noreply, state}
  end

  def handle_info(:recover, state) do
    recover_pending()
    recover_stale()
    Process.send_after(self(), :recover, @recovery_interval_ms)
    {:noreply, state}
  end

  def handle_info(_, state), do: {:noreply, state}

  defp process(delivery_id) do
    case WebhookDeliveries.claim(delivery_id) do
      {:ok, delivery} ->
        ctx = EventContext.from_delivery(%{
          delivery_id: delivery.delivery_id,
          event_type: delivery.event_type,
          repository_full_name: delivery.repository_full_name,
          sender_login: delivery.sender_login,
          payload: delivery.payload
        })

        try do
          run_built_ins(ctx, delivery.event_type)
          WebhookRulesExecutor.run(ctx)
          WebhookDeliveries.mark_processed(delivery.id)
        rescue
          e ->
            Logger.error("Webhook processing failed for #{delivery_id}: #{Exception.message(e)}")
            WebhookDeliveries.mark_failed(delivery.id, Exception.message(e))
        end

      {:error, :not_claimable} ->
        :ok
    end
  end

  defp run_built_ins(ctx, "pull_request" <> _), do: PullRequestHandler.handle(ctx)
  defp run_built_ins(ctx, "push"), do: PushHandler.handle(ctx)
  defp run_built_ins(ctx, "check_run" <> _), do: CheckRunHandler.handle(ctx)
  defp run_built_ins(_, _), do: :ok

  defp recover_pending do
    WebhookDeliveries.pending()
    |> Enum.each(&process(&1.delivery_id))
  end

  defp recover_stale do
    cutoff = DateTime.add(DateTime.utc_now(), @stale_minutes * 60)

    WebhookDeliveries.stale_processing(cutoff)
    |> Enum.each(fn delivery ->
      if delivery.attempt_count >= delivery.max_attempts do
        WebhookDeliveries.mark_failed(delivery.id, "max attempts exceeded")
      else
        WebhookDeliveries.reset_to_pending(delivery.id)
        process(delivery.delivery_id)
      end
    end)
  end
end
```

- [ ] **Step 2: Add WebhookDispatcher to application.ex**

In `lib/eye_in_the_sky/application.ex`, find the `pollers` list (around line 93) and add:

```elixir
    pollers =
      if Application.get_env(:eye_in_the_sky, :start_pollers, true) do
        [
          EyeInTheSky.Teams.Subscriber,
          EyeInTheSky.Tasks.Poller,
          EyeInTheSky.Github.WebhookDispatcher   # <-- add this
        ]
      else
        []
      end
```

- [ ] **Step 3: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky/github/webhook_dispatcher.ex \
        lib/eye_in_the_sky/application.ex
git commit -m "feat: add WebhookDispatcher GenServer with recovery"
```

---

## Task 9: PullRequestHandler (Built-in)

**Files:**
- Create: `lib/eye_in_the_sky/github/pull_request_handler.ex`
- Modify: `lib/eye_in_the_sky/pull_requests/pull_request.ex`
- Create: `test/eye_in_the_sky/github/pull_request_handler_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/eye_in_the_sky/github/pull_request_handler_test.exs
defmodule EyeInTheSky.Github.PullRequestHandlerTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.PullRequestHandler
  alias EyeInTheSky.Github.EventContext
  alias EyeInTheSky.Repo
  alias EyeInTheSky.PullRequests.PullRequest

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %EyeInTheSky.Github.EventContext{
        delivery_id: "d1",
        event_type: "pull_request.opened",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        github_pr_id: 100,
        pr_number: 1,
        head_branch: "feature/x",
        base_branch: "main",
        labels: [],
        draft?: false,
        merged?: false
      },
      overrides
    )
  end

  test "inserts a pull_request row on opened" do
    PullRequestHandler.handle(ctx())
    pr = Repo.get_by(PullRequest, github_pr_id: 100)
    assert pr != nil
    assert pr.repository_full_name == "tacit7/eits"
    assert pr.pr_number == 1
  end

  test "does not create duplicate for same github_pr_id" do
    PullRequestHandler.handle(ctx())
    PullRequestHandler.handle(ctx(%{event_type: "pull_request.synchronize"}))
    count = Repo.aggregate(PullRequest, :count, :id)
    assert count == 1
  end

  test "same pr_number in different repos does not collide" do
    PullRequestHandler.handle(ctx())
    PullRequestHandler.handle(ctx(%{github_pr_id: 200, repository_full_name: "other/repo"}))
    assert Repo.aggregate(PullRequest, :count, :id) == 2
  end

  test "marks merged=true and state=closed on closed+merged" do
    PullRequestHandler.handle(ctx())
    PullRequestHandler.handle(ctx(%{event_type: "pull_request.closed", merged?: true}))
    pr = Repo.get_by(PullRequest, github_pr_id: 100)
    assert pr.merged == true
    assert pr.state == "closed"
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky/github/pull_request_handler_test.exs
```

- [ ] **Step 3: Extend PullRequest schema with new fields**

Open `lib/eye_in_the_sky/pull_requests/pull_request.ex` and add the new fields:

```elixir
defmodule EyeInTheSky.PullRequests.PullRequest do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pull_requests" do
    field :session_id, :integer
    field :pr_number, :integer
    field :pr_url, :string
    field :base_branch, :string
    field :head_branch, :string
    # GitHub sync fields
    field :github_pr_id, :integer
    field :repository_full_name, :string
    field :repository_id, :integer
    field :title, :string
    field :state, :string
    field :draft, :boolean
    field :merged, :boolean
    field :author_login, :string
    field :last_synced_at, :utc_datetime_usec

    belongs_to :session, EyeInTheSky.Sessions.Session,
      define_field: false,
      foreign_key: :session_id,
      type: :integer

    timestamps(inserted_at: :created_at, updated_at: false, type: :utc_datetime)
  end

  @doc false
  def changeset(pr, attrs) do
    pr
    |> cast(attrs, [
      :session_id, :pr_number, :pr_url, :base_branch, :head_branch,
      :github_pr_id, :repository_full_name, :repository_id, :title,
      :state, :draft, :merged, :author_login, :last_synced_at
    ])
    |> validate_required([:github_pr_id, :repository_full_name])
    |> validate_number(:pr_number, greater_than: 0)
    |> validate_format(:pr_url, ~r/^https?:/, message: "must be a valid URL")
    |> unique_constraint(:github_pr_id, name: :pull_requests_github_pr_id_index)
  end
end
```

- [ ] **Step 4: Implement PullRequestHandler**

```elixir
# lib/eye_in_the_sky/github/pull_request_handler.ex
defmodule EyeInTheSky.Github.PullRequestHandler do
  require Logger

  alias EyeInTheSky.Repo
  alias EyeInTheSky.PullRequests.PullRequest
  alias EyeInTheSky.Events

  def handle(%{event_type: "pull_request" <> _, github_pr_id: nil}), do: :ok

  def handle(ctx) do
    attrs = %{
      github_pr_id: ctx.github_pr_id,
      pr_number: ctx.pr_number,
      repository_full_name: ctx.repository_full_name,
      author_login: ctx.sender_login,
      head_branch: ctx.head_branch,
      base_branch: ctx.base_branch,
      draft: ctx.draft?,
      merged: ctx.merged?,
      state: derive_state(ctx),
      last_synced_at: DateTime.utc_now()
    }

    result =
      case Repo.get_by(PullRequest, github_pr_id: ctx.github_pr_id) do
        nil ->
          %PullRequest{}
          |> PullRequest.changeset(attrs)
          |> Repo.insert()

        existing ->
          existing
          |> PullRequest.changeset(attrs)
          |> Repo.update()
      end

    case result do
      {:ok, pr} ->
        Events.pull_request_updated(pr)

      {:error, changeset} ->
        Logger.error("PullRequestHandler upsert failed: #{inspect(changeset)}")
    end
  end

  def handle(_), do: :ok

  defp derive_state(%{event_type: "pull_request.closed"}), do: "closed"
  defp derive_state(_), do: "open"
end
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
mix test test/eye_in_the_sky/github/pull_request_handler_test.exs
```

- [ ] **Step 6: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky/github/pull_request_handler.ex \
        lib/eye_in_the_sky/pull_requests/pull_request.ex \
        test/eye_in_the_sky/github/pull_request_handler_test.exs
git commit -m "feat: add PullRequestHandler built-in and extend PullRequest schema"
```

---

## Task 10: PushHandler + CheckRunHandler (Built-ins)

**Files:**
- Create: `lib/eye_in_the_sky/github/push_handler.ex`
- Create: `lib/eye_in_the_sky/github/check_run_handler.ex`

- [ ] **Step 1: Implement PushHandler**

```elixir
# lib/eye_in_the_sky/github/push_handler.ex
defmodule EyeInTheSky.Github.PushHandler do
  require Logger

  alias EyeInTheSky.Events

  def handle(ctx) do
    Events.github_webhook_received(ctx.delivery_id)
    :ok
  end
end
```

- [ ] **Step 2: Implement CheckRunHandler**

```elixir
# lib/eye_in_the_sky/github/check_run_handler.ex
defmodule EyeInTheSky.Github.CheckRunHandler do
  require Logger

  alias EyeInTheSky.Events

  def handle(ctx) do
    Events.pull_request_updated(%{
      delivery_id: ctx.delivery_id,
      event_type: ctx.event_type,
      repository_full_name: ctx.repository_full_name
    })

    :ok
  end
end
```

- [ ] **Step 3: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 4: Commit**

```bash
git add lib/eye_in_the_sky/github/push_handler.ex \
        lib/eye_in_the_sky/github/check_run_handler.ex
git commit -m "feat: add PushHandler and CheckRunHandler built-ins"
```

---

## Task 11: WebhookRule Schema + WebhookRules Context

**Files:**
- Create: `lib/eye_in_the_sky/github/webhook_rule.ex`
- Create: `lib/eye_in_the_sky/github/webhook_rule_execution.ex`
- Create: `lib/eye_in_the_sky/github/webhook_rules.ex`
- Create: `test/eye_in_the_sky/github/webhook_rules_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/eye_in_the_sky/github/webhook_rules_test.exs
defmodule EyeInTheSky.Github.WebhookRulesTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.WebhookRules

  @valid_attrs %{
    event_type: "pull_request.opened",
    action_type: "broadcast_only",
    action_config: %{"topic" => "test", "message" => "PR {{pr_number}} opened"},
    guard_config: %{}
  }

  describe "create/1" do
    test "creates a rule with valid attributes" do
      assert {:ok, rule} = WebhookRules.create(@valid_attrs)
      assert rule.event_type == "pull_request.opened"
      assert rule.enabled == true
      assert rule.priority == 100
    end

    test "rejects unknown template variable in action_config" do
      attrs = put_in(@valid_attrs, [:action_config, "message"], "{{secret_token}}")
      assert {:error, changeset} = WebhookRules.create(attrs)
      assert changeset.errors[:action_config]
    end

    test "rejects missing required action_config key for spawn_agent" do
      attrs = %{@valid_attrs | action_type: "spawn_agent", action_config: %{"agent" => "codex"}}
      assert {:error, changeset} = WebhookRules.create(attrs)
      assert changeset.errors[:action_config]
    end

    test "accepts valid spawn_agent config" do
      attrs = %{
        @valid_attrs
        | action_type: "spawn_agent",
          action_config: %{"agent" => "codex", "instructions" => "Review PR {{pr_number}}"}
      }

      assert {:ok, _} = WebhookRules.create(attrs)
    end
  end

  describe "matching_rules/2" do
    test "returns enabled rules matching event_type" do
      {:ok, rule} = WebhookRules.create(@valid_attrs)
      rules = WebhookRules.matching_rules("pull_request.opened", nil)
      assert Enum.any?(rules, &(&1.id == rule.id))
    end

    test "does not return disabled rules" do
      {:ok, rule} = WebhookRules.create(@valid_attrs)
      WebhookRules.update(rule, %{enabled: false})
      rules = WebhookRules.matching_rules("pull_request.opened", nil)
      refute Enum.any?(rules, &(&1.id == rule.id))
    end

    test "wildcard * matches any event_type" do
      {:ok, rule} = WebhookRules.create(%{@valid_attrs | event_type: "*"})
      rules = WebhookRules.matching_rules("push", nil)
      assert Enum.any?(rules, &(&1.id == rule.id))
    end
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky/github/webhook_rules_test.exs
```

- [ ] **Step 3: Implement WebhookRule schema**

```elixir
# lib/eye_in_the_sky/github/webhook_rule.ex
defmodule EyeInTheSky.Github.WebhookRule do
  use Ecto.Schema
  import Ecto.Changeset

  alias EyeInTheSky.Github.Template

  @action_types ~w[spawn_agent create_task dm_session broadcast_only]
  @required_config %{
    "spawn_agent" => ~w[agent instructions],
    "create_task" => ~w[title],
    "dm_session" => ~w[session_id message],
    "broadcast_only" => ~w[topic message]
  }

  schema "github_webhook_rules" do
    field :event_type, :string
    field :repository_full_name, :string
    field :project_id, :integer
    field :branch_glob, :string
    field :target_branch_glob, :string
    field :action_type, :string
    field :action_config, :map, default: %{}
    field :guard_config, :map, default: %{}
    field :enabled, :boolean, default: true
    field :priority, :integer, default: 100

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [
      :event_type, :repository_full_name, :project_id, :branch_glob,
      :target_branch_glob, :action_type, :action_config, :guard_config,
      :enabled, :priority
    ])
    |> validate_required([:event_type, :action_type, :action_config])
    |> validate_inclusion(:action_type, @action_types)
    |> validate_action_config()
    |> validate_guard_config()
  end

  defp validate_action_config(%{valid?: false} = cs), do: cs

  defp validate_action_config(changeset) do
    action_type = get_field(changeset, :action_type)
    config = get_field(changeset, :action_config) || %{}
    required = Map.get(@required_config, action_type, [])

    with :ok <- check_required_keys(config, required),
         :ok <- validate_templates(config) do
      changeset
    else
      {:error, msg} -> add_error(changeset, :action_config, msg)
    end
  end

  defp check_required_keys(config, required) do
    missing = Enum.reject(required, &Map.has_key?(config, &1))
    if missing == [], do: :ok, else: {:error, "missing required keys: #{Enum.join(missing, ", ")}"}
  end

  defp validate_templates(config) do
    config
    |> Map.values()
    |> Enum.filter(&is_binary/1)
    |> Enum.reduce_while(:ok, fn val, :ok ->
      case Template.validate(val) do
        :ok -> {:cont, :ok}
        {:error, msg} -> {:halt, {:error, msg}}
      end
    end)
  end

  defp validate_guard_config(%{valid?: false} = cs), do: cs

  defp validate_guard_config(changeset) do
    config = get_field(changeset, :guard_config) || %{}
    allowed = ~w[once_per_pr max_runs_per_pr ignore_drafts only_if_label]
    unknown = Map.keys(config) -- allowed

    if unknown == [] do
      changeset
    else
      add_error(changeset, :guard_config, "unknown guard keys: #{Enum.join(unknown, ", ")}")
    end
  end
end
```

- [ ] **Step 4: Implement WebhookRuleExecution schema**

```elixir
# lib/eye_in_the_sky/github/webhook_rule_execution.ex
defmodule EyeInTheSky.Github.WebhookRuleExecution do
  use Ecto.Schema
  import Ecto.Changeset

  schema "github_webhook_rule_executions" do
    field :rule_id, :integer
    field :delivery_id, :string
    field :repository_full_name, :string
    field :pr_number, :integer
    field :status, :string
    field :result, :map
    field :error_message, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def changeset(exec, attrs) do
    exec
    |> cast(attrs, [:rule_id, :delivery_id, :repository_full_name, :pr_number, :status, :result, :error_message])
    |> validate_required([:rule_id, :delivery_id, :status])
    |> validate_inclusion(:status, ~w[ok failed skipped])
  end
end
```

- [ ] **Step 5: Implement WebhookRules context**

```elixir
# lib/eye_in_the_sky/github/webhook_rules.ex
defmodule EyeInTheSky.Github.WebhookRules do
  import Ecto.Query

  alias EyeInTheSky.Repo
  alias EyeInTheSky.Github.WebhookRule
  alias EyeInTheSky.Github.WebhookRuleExecution

  def create(attrs) do
    %WebhookRule{}
    |> WebhookRule.changeset(attrs)
    |> Repo.insert()
  end

  def update(rule, attrs) do
    rule
    |> WebhookRule.changeset(attrs)
    |> Repo.update()
  end

  def list, do: Repo.all(from r in WebhookRule, order_by: [asc: r.priority, asc: r.id])

  def matching_rules(event_type, repository_full_name) do
    Repo.all(
      from r in WebhookRule,
        where: r.enabled == true,
        where: r.event_type == ^event_type or r.event_type == "*",
        where:
          is_nil(r.repository_full_name) or
            r.repository_full_name == ^(repository_full_name || ""),
        order_by: [asc: r.priority, asc: r.id]
    )
  end

  def record_execution(attrs) do
    %WebhookRuleExecution{}
    |> WebhookRuleExecution.changeset(attrs)
    |> Repo.insert()
  end

  def ok_execution_count(rule_id, repo, pr_number) do
    Repo.aggregate(
      from(e in WebhookRuleExecution,
        where:
          e.rule_id == ^rule_id and e.repository_full_name == ^repo and
            e.pr_number == ^pr_number and e.status == "ok"
      ),
      :count
    )
  end

  def has_ok_execution?(rule_id, repo, pr_number) do
    ok_execution_count(rule_id, repo, pr_number) > 0
  end
end
```

- [ ] **Step 6: Run tests to confirm pass**

```bash
mix test test/eye_in_the_sky/github/webhook_rules_test.exs
```

- [ ] **Step 7: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 8: Commit**

```bash
git add lib/eye_in_the_sky/github/webhook_rule.ex \
        lib/eye_in_the_sky/github/webhook_rule_execution.ex \
        lib/eye_in_the_sky/github/webhook_rules.ex \
        test/eye_in_the_sky/github/webhook_rules_test.exs
git commit -m "feat: add WebhookRule schema and WebhookRules context with save-time validation"
```

---

## Task 12: WebhookRulesExecutor + RuleActions

**Files:**
- Create: `lib/eye_in_the_sky/github/rule_actions.ex`
- Create: `lib/eye_in_the_sky/github/webhook_rules_executor.ex`
- Create: `test/eye_in_the_sky/github/webhook_rules_executor_test.exs`

- [ ] **Step 1: Write failing tests**

```elixir
# test/eye_in_the_sky/github/webhook_rules_executor_test.exs
defmodule EyeInTheSky.Github.WebhookRulesExecutorTest do
  use EyeInTheSky.DataCase, async: true

  alias EyeInTheSky.Github.WebhookRulesExecutor
  alias EyeInTheSky.Github.WebhookRules
  alias EyeInTheSky.Github.EventContext

  defp ctx(overrides \\ %{}) do
    Map.merge(
      %EventContext{
        delivery_id: "d1",
        event_type: "pull_request.opened",
        repository_full_name: "tacit7/eits",
        sender_login: "uriel",
        github_pr_id: 1,
        pr_number: 1,
        head_branch: "feature/x",
        base_branch: "main",
        labels: [],
        draft?: false,
        merged?: false
      },
      overrides
    )
  end

  defp broadcast_rule(overrides \\ %{}) do
    WebhookRules.create(
      Map.merge(
        %{
          event_type: "pull_request.opened",
          action_type: "broadcast_only",
          action_config: %{"topic" => "test_topic", "message" => "PR {{pr_number}}"},
          guard_config: %{}
        },
        overrides
      )
    )
    |> elem(1)
  end

  test "executes matching broadcast_only rule and records ok execution" do
    rule = broadcast_rule()
    WebhookRulesExecutor.run(ctx())
    assert WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "once_per_pr guard skips on second run with ok execution" do
    rule = broadcast_rule(%{guard_config: %{"once_per_pr" => true}})
    WebhookRulesExecutor.run(ctx())
    WebhookRulesExecutor.run(ctx())
    count = WebhookRules.ok_execution_count(rule.id, "tacit7/eits", 1)
    assert count == 1
  end

  test "ignore_drafts guard skips draft PRs" do
    rule = broadcast_rule(%{guard_config: %{"ignore_drafts" => true}})
    WebhookRulesExecutor.run(ctx(%{draft?: true}))
    refute WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "only_if_label guard skips when label absent" do
    rule = broadcast_rule(%{guard_config: %{"only_if_label" => "agent-review"}})
    WebhookRulesExecutor.run(ctx(%{labels: []}))
    refute WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "only_if_label guard fires when label present" do
    rule = broadcast_rule(%{guard_config: %{"only_if_label" => "agent-review"}})
    WebhookRulesExecutor.run(ctx(%{labels: ["agent-review"]}))
    assert WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "once_per_pr does NOT skip when previous execution was skipped" do
    rule = broadcast_rule(%{guard_config: %{"once_per_pr" => true, "ignore_drafts" => true}})
    WebhookRulesExecutor.run(ctx(%{draft?: true}))
    WebhookRulesExecutor.run(ctx(%{draft?: false}))
    assert WebhookRules.has_ok_execution?(rule.id, "tacit7/eits", 1)
  end

  test "broadcast_only does not raise" do
    broadcast_rule()
    assert :ok = WebhookRulesExecutor.run(ctx())
  end
end
```

- [ ] **Step 2: Run to confirm failure**

```bash
mix test test/eye_in_the_sky/github/webhook_rules_executor_test.exs
```

- [ ] **Step 3: Implement RuleActions**

```elixir
# lib/eye_in_the_sky/github/rule_actions.ex
defmodule EyeInTheSky.Github.RuleActions do
  require Logger

  alias EyeInTheSky.Github.Template
  alias EyeInTheSky.Events

  def dispatch(rule, ctx) do
    template_ctx = build_template_ctx(ctx)

    case render_config(rule.action_config, template_ctx) do
      {:ok, rendered} -> execute(rule.action_type, rendered, ctx)
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute("broadcast_only", config, _ctx) do
    topic = config["topic"] || "github:webhook"
    message = config["message"] || ""
    Phoenix.PubSub.broadcast(EyeInTheSky.PubSub, topic, {:webhook_rule_fired, message})
    :ok
  end

  defp execute("spawn_agent", config, _ctx) do
    agent_name = config["agent"]
    instructions = config["instructions"]

    case EyeInTheSky.Agents.spawn_agent(%{name: agent_name, instructions: instructions}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "spawn_agent failed: #{inspect(reason)}"}
    end
  end

  defp execute("create_task", config, _ctx) do
    title = config["title"]

    case EyeInTheSky.Tasks.create_task(%{title: title}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "create_task failed: #{inspect(reason)}"}
    end
  end

  defp execute("dm_session", config, _ctx) do
    session_id = config["session_id"]
    message = config["message"]

    case EyeInTheSky.Messages.send_dm(session_id, message) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "dm_session failed: #{inspect(reason)}"}
    end
  end

  defp execute(unknown, _, _), do: {:error, "unknown action_type: #{unknown}"}

  defp render_config(config, template_ctx) do
    Enum.reduce_while(config, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      rendered =
        if is_binary(v) do
          case Template.render(v, template_ctx) do
            {:ok, rendered} -> {:cont, {:ok, Map.put(acc, k, rendered)}}
            {:error, _} = err -> {:halt, err}
          end
        else
          {:cont, {:ok, Map.put(acc, k, v)}}
        end

      rendered
    end)
  end

  defp build_template_ctx(ctx) do
    %{
      "repository" => ctx.repository_full_name,
      "event_type" => ctx.event_type,
      "sender_login" => ctx.sender_login,
      "pr_number" => ctx.pr_number,
      "head_branch" => ctx.head_branch,
      "base_branch" => ctx.base_branch,
      "pr_title" => nil,
      "pr_url" => nil
    }
  end
end
```

- [ ] **Step 4: Implement WebhookRulesExecutor**

```elixir
# lib/eye_in_the_sky/github/webhook_rules_executor.ex
defmodule EyeInTheSky.Github.WebhookRulesExecutor do
  require Logger

  alias EyeInTheSky.Github.WebhookRules
  alias EyeInTheSky.Github.RuleActions

  def run(ctx) do
    rules = WebhookRules.matching_rules(ctx.event_type, ctx.repository_full_name)
    Enum.each(rules, &execute_rule(&1, ctx))
    :ok
  end

  defp execute_rule(rule, ctx) do
    case evaluate_guards(rule, ctx) do
      :pass ->
        result = RuleActions.dispatch(rule, ctx)
        status = if result == :ok, do: "ok", else: "failed"
        error = if match?({:error, msg}, result), do: elem(result, 1), else: nil

        WebhookRules.record_execution(%{
          rule_id: rule.id,
          delivery_id: ctx.delivery_id,
          repository_full_name: ctx.repository_full_name,
          pr_number: ctx.pr_number,
          status: status,
          error_message: error
        })

      {:skip, reason} ->
        WebhookRules.record_execution(%{
          rule_id: rule.id,
          delivery_id: ctx.delivery_id,
          repository_full_name: ctx.repository_full_name,
          pr_number: ctx.pr_number,
          status: "skipped",
          error_message: reason
        })
    end
  end

  defp evaluate_guards(rule, ctx) do
    guards = rule.guard_config || %{}

    cond do
      guards["ignore_drafts"] == true and ctx.draft? ->
        {:skip, "draft PR"}

      guards["only_if_label"] != nil and
          guards["only_if_label"] not in (ctx.labels || []) ->
        {:skip, "label not present"}

      guards["once_per_pr"] == true and ctx.pr_number != nil and
          WebhookRules.has_ok_execution?(rule.id, ctx.repository_full_name, ctx.pr_number) ->
        {:skip, "once_per_pr: already executed ok"}

      guards["max_runs_per_pr"] != nil and ctx.pr_number != nil and
          WebhookRules.ok_execution_count(rule.id, ctx.repository_full_name, ctx.pr_number) >=
            guards["max_runs_per_pr"] ->
        {:skip, "max_runs_per_pr exceeded"}

      true ->
        :pass
    end
  end
end
```

- [ ] **Step 5: Run tests to confirm pass**

```bash
mix test test/eye_in_the_sky/github/webhook_rules_executor_test.exs
```

- [ ] **Step 6: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 7: Commit**

```bash
git add lib/eye_in_the_sky/github/rule_actions.ex \
        lib/eye_in_the_sky/github/webhook_rules_executor.ex \
        test/eye_in_the_sky/github/webhook_rules_executor_test.exs
git commit -m "feat: add WebhookRulesExecutor and RuleActions with guard evaluation"
```

---

## Task 13: Full Test Run + SETUP.md

**Files:**
- Modify: `docs/SETUP.md`

- [ ] **Step 1: Run the full test suite**

```bash
mix test --exclude integration --exclude host_dependent --exclude sdk_e2e
```

Expected: all tests pass. Fix any failures before proceeding.

- [ ] **Step 2: Add smee setup to SETUP.md**

Open `docs/SETUP.md` and add a new section for GitHub Webhooks:

```markdown
## GitHub Webhooks (Dev)

To receive GitHub webhook events locally, use [smee-client](https://github.com/probot/smee-client) as a tunnel:

1. Go to https://smee.io and create a new channel. Copy the URL.
2. Configure your GitHub repo webhook to point at the smee.io URL.
   - **Payload URL:** your smee.io channel URL
   - **Content type:** `application/json`
   - **Secret:** must match `GITHUB_WEBHOOK_SECRET` in your `.env`
   - **Events:** select "Send me everything" or choose individual events
3. Run smee alongside the Phoenix server:

```bash
npx smee-client \
  --url https://smee.io/<your-channel> \
  --target http://localhost:5001/api/v1/webhooks/github
```

4. Set `GITHUB_WEBHOOK_SECRET` in `.env` to match the GitHub webhook secret.

In production, point the GitHub webhook directly at `https://your-domain/api/v1/webhooks/github`.
```

- [ ] **Step 3: Add `GITHUB_WEBHOOK_SECRET` to .env.example**

Open `.env.example` and add:

```
GITHUB_WEBHOOK_SECRET=your_github_webhook_secret_here
```

- [ ] **Step 4: Compile check**

```bash
mix compile --warnings-as-errors
```

- [ ] **Step 5: Commit**

```bash
git add docs/SETUP.md .env.example
git commit -m "docs: add smee dev setup instructions for GitHub webhooks"
```

---

## Self-Review Checklist

**Spec coverage:**

| Spec requirement | Task |
|---|---|
| HMAC verification with normalize + validate | Task 2 |
| EventContext normalized struct | Task 3 |
| Template interpolation with allowlist | Task 4 |
| WebhookDelivery schema + deliveries context | Task 5 |
| Deduplication on delivery_id | Task 5 |
| Atomic claim (pending → processing) | Task 5 |
| Recovery: pending on init, stale on interval | Task 8 |
| Max attempts → failed | Task 8 |
| PubSub via EyeInTheSky.Events | Task 6 |
| RawBodyCache plug (route-scoped) | Task 6, Task 7 |
| Controller: 202, 401, 400 per matrix | Task 7 |
| Router in :accepts_json | Task 7 |
| WebhookDispatcher GenServer | Task 8 |
| PullRequestHandler (built-in upsert) | Task 9 |
| PushHandler + CheckRunHandler | Task 10 |
| WebhookRule schema + save-time validation | Task 11 |
| WebhookRules context + matching | Task 11 |
| WebhookRuleExecution schema + recording | Task 11 |
| WebhookRulesExecutor + guard evaluation | Task 12 |
| RuleActions (internal dispatch, no shell out) | Task 12 |
| Config: GITHUB_WEBHOOK_SECRET | Task 7 |
| Smee dev setup in SETUP.md | Task 13 |
| Settings UI | Not included — separate task |

> **Note:** Settings UI for rule management is scoped out of this plan. It can be added as a follow-up once the backend is stable and tested.

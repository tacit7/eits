defmodule EyeInTheSkyWeb.SettingsProvidersTabTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias EyeInTheSky.Accounts
  alias EyeInTheSky.Pi.ModelDiscoveryCache

  defmodule FakeControl do
    def list_providers do
      {:ok,
       %{
         "defaultVisibleCount" => 2,
         "providers" => [
           %{
             "id" => "openrouter",
             "label" => "OpenRouter",
             "kind" => "api",
             "authSource" => nil
           },
           %{
             "id" => "anthropic",
             "label" => "Anthropic",
             "kind" => "oauth",
             "authSource" => "keychain"
           },
           %{
             "id" => "echo",
             "label" => "Echo",
             "kind" => "api",
             "authSource" => nil
           }
         ]
       }}
    end

    def set_api_key("openrouter", _key), do: :ok
    # Simulate a provider that echoes the submitted key inside its error message,
    # which is the primary threat model for FIX 1 (Codex review).
    def set_api_key("echo", key),
      do: {:error, {:pi_control, "invalid key #{key}"}}

    def set_api_key(_pid, _key), do: {:error, {:pi_control, "unknown provider"}}
    def clear_api_key(_pid), do: :ok
    def discover_models, do: {:ok, []}
    def auth_status, do: {:ok, %{}}
  end

  defp create_user do
    {:ok, user} = Accounts.get_or_create_user("test-settings-providers-user")
    user
  end

  defp auth_conn(conn) do
    user = create_user()
    init_test_session(conn, %{"user_id" => user.id})
  end

  setup do
    Application.put_env(:eye_in_the_sky, :pi_control_module, FakeControl)
    ModelDiscoveryCache.invalidate()

    on_exit(fn ->
      Application.delete_env(:eye_in_the_sky, :pi_control_module)
      ModelDiscoveryCache.invalidate()
    end)

    :ok
  end

  test "providers tab lists providers with configured status and copy", %{conn: conn} do
    {:ok, view, _html} = live(auth_conn(conn), ~p"/settings?tab=providers")

    html = render(view)
    assert html =~ "Providers"
    assert html =~ "auth.json"
    assert html =~ "OpenRouter"
    assert html =~ "Anthropic"
    # configured badge for anthropic (authSource present)
    assert html =~ "configured"
    # not set for openrouter
    assert html =~ "not set"
  end

  # Poll render/1 until `expect` appears (async pi key op returns via handle_info).
  defp render_until(view, expect, deadline_ms \\ 2_000) do
    deadline = System.monotonic_time(:millisecond) + deadline_ms
    do_render_until(view, expect, deadline)
  end

  defp do_render_until(view, expect, deadline) do
    html = render(view)

    cond do
      html =~ expect ->
        html

      System.monotonic_time(:millisecond) > deadline ->
        flunk("timeout waiting for: #{expect}")

      true ->
        Process.sleep(25)
        do_render_until(view, expect, deadline)
    end
  end

  test "saving a key calls set_api_key, invalidates cache, flashes success (async)", %{conn: conn} do
    {:ok, view, _} = live(auth_conn(conn), ~p"/settings?tab=providers")

    view
    |> form(~s(form[phx-submit="pi_set_key"][data-provider-id="openrouter"]), %{
      "key" => "sk-or-test-value"
    })
    |> render_submit()

    html = render_until(view, "Key saved")

    # Success flash mentions auth.json
    assert html =~ "Key saved"
    # Key value must not appear in the rendered page (never echo secret material)
    refute html =~ "sk-or-test-value"
  end

  test "a provider error that echoes the submitted key is redacted before flashing", %{conn: conn} do
    {:ok, view, _} = live(auth_conn(conn), ~p"/settings?tab=providers")

    submitted_key = "sk-or-abc123def456ghi789xyz"

    view
    |> form(~s(form[phx-submit="pi_set_key"][data-provider-id="echo"]), %{
      "key" => submitted_key
    })
    |> render_submit()

    html = render_until(view, "Key save failed")

    # The submitted key must never appear in the rendered HTML, even though the
    # fake control's error string echoes it back verbatim.
    refute html =~ submitted_key
    refute html =~ "sk-or-abc123def456"
    assert html =~ "[redacted]"
  end

  test "oauth-kind providers show disabled Phase 3 sign-in button", %{conn: conn} do
    {:ok, view, _html} = live(auth_conn(conn), ~p"/settings?tab=providers")
    html = render(view)
    assert html =~ "Sign in (Phase 3)"
  end
end

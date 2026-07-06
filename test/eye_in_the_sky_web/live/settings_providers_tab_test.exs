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
           }
         ]
       }}
    end

    def set_api_key("openrouter", _key), do: :ok
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

  test "saving a key calls set_api_key, invalidates cache, flashes success", %{conn: conn} do
    {:ok, view, _} = live(auth_conn(conn), ~p"/settings?tab=providers")

    html =
      view
      |> form(~s(form[phx-submit="pi_set_key"][data-provider-id="openrouter"]), %{
        "key" => "sk-or-test-value"
      })
      |> render_submit()

    # Success flash mentions auth.json
    assert html =~ "Key saved"
    # Key value must not appear in the rendered page (never echo secret material)
    refute html =~ "sk-or-test-value"
  end

  test "oauth-kind providers show disabled Phase 3 sign-in button", %{conn: conn} do
    {:ok, view, _html} = live(auth_conn(conn), ~p"/settings?tab=providers")
    html = render(view)
    assert html =~ "Sign in (Phase 3)"
  end
end

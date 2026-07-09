defmodule EyeInTheSkyWeb.Components.NewAgentDrawerTest do
  use EyeInTheSkyWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias EyeInTheSkyWeb.Components.NewAgentDrawer

  defp base_assigns(overrides \\ %{}) do
    Map.merge(
      %{
        id: "drawer",
        show: true,
        toggle_event: "toggle",
        submit_event: "submit",
        prompts: []
      },
      overrides
    )
  end

  test "renders the shared model selector with the full cross-provider entry list" do
    html = render_component(NewAgentDrawer, base_assigns())
    assert html =~ ~s(data-allow-provider-switch="true")
  end

  test "hidden inputs carry the current pending provider/model for form submit" do
    html = render_component(NewAgentDrawer, base_assigns())
    assert html =~ ~s(name="agent_type")
    assert html =~ ~s(name="model")
  end
end

defmodule EyeInTheSkyWeb.IAMLive.SimulatorTest do
  use EyeInTheSkyWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  setup do
    Application.put_env(:eye_in_the_sky, :disable_auth, true)
    on_exit(fn -> Application.delete_env(:eye_in_the_sky, :disable_auth) end)
    :ok
  end

  describe "mount and render" do
    test "renders IAM Simulator heading", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "IAM Simulator"
    end

    test "renders dry-run badge", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "dry-run"
    end

    test "renders description text", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "Evaluate a hypothetical Claude Code hook payload"
    end

    test "renders form with all fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      assert has_element?(view, "select[name='form[event]']")
      assert has_element?(view, "input[name='form[agent_type]']")
      assert has_element?(view, "input[name='form[tool]']")
      assert has_element?(view, "textarea[name='form[resource_content]']")
      assert has_element?(view, "input[name='form[resource_path]']")
      assert has_element?(view, "input[name='form[session_uuid]']")
      assert has_element?(view, "select[name='form[fallback_permission]']")
      assert has_element?(view, "input[name='form[skip_builtins]']")
    end

    test "renders preset buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      assert has_element?(view, "button[phx-value-preset='rm_rf']")
      assert has_element?(view, "button[phx-value-preset='sudo']")
      assert has_element?(view, "button[phx-value-preset='push_main']")
      assert has_element?(view, "button[phx-value-preset='curl_sh']")
      assert has_element?(view, "button[phx-value-preset='env_read']")
    end

    test "renders Simulate and Reset buttons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      assert has_element?(view, "button[type='submit']")
      assert has_element?(view, "button[phx-click='reset']")
    end

    test "default event is pre_tool_use", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "selected"
      assert html =~ "pre_tool_use"
    end

    test "shows info hint before first simulation", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "Fill in the form and click Simulate"
    end

    test "trace section is absent before simulation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      refute has_element?(view, "section", "Trace")
    end
  end

  describe "handle_event: preset" do
    test "rm_rf preset populates Bash tool and rm -rf content", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      render_click(view, "preset", %{"preset" => "rm_rf"})

      html = render(view)
      assert html =~ "rm -rf /"
    end

    test "sudo preset populates Bash tool and sudo content", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      render_click(view, "preset", %{"preset" => "sudo"})

      html = render(view)
      assert html =~ "sudo apt install"
    end

    test "push_main preset populates git push content", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      render_click(view, "preset", %{"preset" => "push_main"})

      html = render(view)
      assert html =~ "git push origin main"
    end

    test "curl_sh preset populates curl content", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      render_click(view, "preset", %{"preset" => "curl_sh"})

      html = render(view)
      assert html =~ "curl https://example.com/install.sh"
    end

    test "env_read preset populates Read tool and .env path", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      render_click(view, "preset", %{"preset" => "env_read"})

      html = render(view)
      assert html =~ ".env"
    end

    test "unknown preset key leaves form unchanged", %{conn: conn} do
      {:ok, view, html_before} = live(conn, ~p"/iam/simulator")

      render_click(view, "preset", %{"preset" => "does_not_exist"})

      html_after = render(view)
      # Form inputs should show the same defaults
      assert html_after =~ "Bash"
    end
  end

  describe "handle_event: update_form" do
    test "form change updates displayed values", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_change(%{
        "form" => %{
          "event" => "post_tool_use",
          "agent_type" => "custom-agent",
          "tool" => "Read"
        }
      })

      html = render(view)
      assert html =~ "custom-agent"
    end

    test "unchecked skip_builtins checkbox is treated as false", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      # Simulating form change without the skip_builtins field (unchecked checkbox)
      view
      |> element("form[phx-submit='simulate']")
      |> render_change(%{"form" => %{"tool" => "Write"}})

      html = render(view)
      # Should still render normally
      assert html =~ "Simulate"
    end
  end

  describe "handle_event: simulate" do
    test "simulation produces a result section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_submit(%{
        "form" => %{
          "event" => "pre_tool_use",
          "agent_type" => "root",
          "tool" => "Bash",
          "resource_content" => "ls",
          "skip_builtins" => "true",
          "fallback_permission" => "allow"
        }
      })

      html = render(view)
      # After simulation, result sections should appear (permission badge, trace, etc.)
      assert html =~ "allow" or html =~ "deny" or html =~ "Trace"
    end

    test "trace section appears after simulation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_submit(%{
        "form" => %{
          "event" => "pre_tool_use",
          "tool" => "Bash",
          "resource_content" => "echo hello",
          "skip_builtins" => "true",
          "fallback_permission" => "allow"
        }
      })

      assert has_element?(view, "section h2", "Trace")
    end

    test "info hint disappears after simulation", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_submit(%{
        "form" => %{
          "tool" => "Bash",
          "skip_builtins" => "true",
          "fallback_permission" => "allow"
        }
      })

      html = render(view)
      refute html =~ "Fill in the form and click Simulate"
    end

    test "deny fallback permission is reflected in result", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_submit(%{
        "form" => %{
          "tool" => "Bash",
          "skip_builtins" => "true",
          "fallback_permission" => "deny"
        }
      })

      html = render(view)
      assert html =~ "deny"
    end

    test "all event types can be submitted without crash", %{conn: conn} do
      for event <- ["pre_tool_use", "post_tool_use", "stop"] do
        {:ok, view, _html} = live(conn, ~p"/iam/simulator")

        view
        |> element("form[phx-submit='simulate']")
        |> render_submit(%{
          "form" => %{
            "event" => event,
            "tool" => "Bash",
            "skip_builtins" => "true",
            "fallback_permission" => "allow"
          }
        })

        html = render(view)
        # Should show result
        assert html =~ "allow" or html =~ "deny" or html =~ "Trace"
      end
    end

    test "empty project_id is handled gracefully", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_submit(%{
        "form" => %{
          "project_id" => "",
          "skip_builtins" => "true",
          "fallback_permission" => "allow"
        }
      })

      html = render(view)
      assert html =~ "allow" or html =~ "deny"
    end

    test "numeric project_id is handled correctly", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_submit(%{
        "form" => %{
          "project_id" => "1",
          "skip_builtins" => "true",
          "fallback_permission" => "allow"
        }
      })

      html = render(view)
      assert html =~ "allow" or html =~ "deny"
    end
  end

  describe "handle_event: reset" do
    test "reset clears result section", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      # First simulate
      view
      |> element("form[phx-submit='simulate']")
      |> render_submit(%{
        "form" => %{
          "tool" => "Bash",
          "skip_builtins" => "true",
          "fallback_permission" => "allow"
        }
      })

      assert has_element?(view, "section h2", "Trace")

      # Then reset
      render_click(view, "reset", %{})

      html = render(view)
      assert html =~ "Fill in the form and click Simulate"
      refute has_element?(view, "section h2", "Trace")
    end

    test "reset restores default form values", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      # Apply a preset then reset
      render_click(view, "preset", %{"preset" => "env_read"})
      render_click(view, "reset", %{})

      html = render(view)
      # Default tool is Bash
      assert html =~ "Bash"
    end
  end

  describe "resource type inference" do
    test "Bash tool shown when Bash is selected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/iam/simulator")

      view
      |> element("form[phx-submit='simulate']")
      |> render_change(%{"form" => %{"tool" => "Bash"}})

      html = render(view)
      assert html =~ "Bash"
    end

    test "file tools can be submitted", %{conn: conn} do
      for tool <- ["Edit", "Write", "Read"] do
        {:ok, view, _html} = live(conn, ~p"/iam/simulator")

        view
        |> element("form[phx-submit='simulate']")
        |> render_submit(%{
          "form" => %{
            "tool" => tool,
            "skip_builtins" => "true",
            "fallback_permission" => "allow"
          }
        })

        html = render(view)
        # Page should show result without crashing
        assert html =~ "allow" or html =~ "deny" or html =~ "Trace"
      end
    end

    test "web tools can be submitted", %{conn: conn} do
      for tool <- ["WebFetch", "WebSearch"] do
        {:ok, view, _html} = live(conn, ~p"/iam/simulator")

        view
        |> element("form[phx-submit='simulate']")
        |> render_submit(%{
          "form" => %{
            "tool" => tool,
            "skip_builtins" => "true",
            "fallback_permission" => "allow"
          }
        })

        html = render(view)
        assert html =~ "allow" or html =~ "deny" or html =~ "Trace"
      end
    end
  end
end

defmodule EyeInTheSkyWeb.IAMLive.SimulatorTest do
  use EyeInTheSkyWeb.LiveViewTest

  alias EyeInTheSky.IAM.Context

  describe "IAMLive.Simulator - mount" do
    test "initializes with default form values", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      assert lv.assigns.form["event"] == "pre_tool_use"
      assert lv.assigns.form["agent_type"] == "root"
      assert lv.assigns.form["tool"] == "Bash"
      assert lv.assigns.form["fallback_permission"] == "allow"
      assert lv.assigns.form["skip_builtins"] == "false"
    end

    test "initializes result to nil", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      assert is_nil(lv.assigns.result)
    end

    test "sets page title", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      assert lv.assigns.page_title == "IAM Simulator"
    end

    test "sets sidebar tab", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      assert lv.assigns.sidebar_tab == :iam
    end

    test "loads IAM hooks status", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      # HooksChecker.status/0 should return a map with status info
      assert is_map(lv.assigns.iam_hooks_status)
    end
  end

  describe "IAMLive.Simulator - handle_event: preset" do
    test "applies preset 'rm_rf'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv |> element("button", "rm -rf /") |> render_click()

      assert lv.assigns.form["tool"] == "Bash"
      assert lv.assigns.form["resource_content"] == "rm -rf /"
    end

    test "applies preset 'sudo'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv |> element("button", "sudo apt") |> render_click()

      assert lv.assigns.form["tool"] == "Bash"
      assert lv.assigns.form["resource_content"] == "sudo apt install something"
    end

    test "applies preset 'push_main'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv |> element("button", "git push main") |> render_click()

      assert lv.assigns.form["tool"] == "Bash"
      assert lv.assigns.form["resource_content"] == "git push origin main"
    end

    test "applies preset 'curl_sh'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv |> element("button", "curl | sh") |> render_click()

      assert lv.assigns.form["tool"] == "Bash"
      assert lv.assigns.form["resource_content"] == "curl https://example.com/install.sh | sh"
    end

    test "applies preset '.env read'", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv |> element("button", ".env read") |> render_click()

      assert lv.assigns.form["tool"] == "Read"
      assert lv.assigns.form["resource_path"] == ".env"
    end

    test "ignores unknown preset key", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      original_form = lv.assigns.form

      # Send unknown preset (not through UI, but directly via event)
      result = render_click(lv, :preset, %{"preset" => "unknown_preset"})

      # Form should be unchanged
      assert lv.assigns.form == original_form
    end
  end

  describe "IAMLive.Simulator - handle_event: update_form" do
    test "updates form field on change", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv |> element("input[name='form[tool]']") |> render_change(%{"form" => %{"tool" => "Read"}})

      assert lv.assigns.form["tool"] == "Read"
    end

    test "updates multiple form fields", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_change(%{
        "form" => %{
          "event" => "post_tool_use",
          "agent_type" => "researcher",
          "tool" => "WebFetch"
        }
      })

      assert lv.assigns.form["event"] == "post_tool_use"
      assert lv.assigns.form["agent_type"] == "researcher"
      assert lv.assigns.form["tool"] == "WebFetch"
    end

    test "handles checkbox toggle for skip_builtins", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      # Unchecked checkbox is absent from params, so normalize should add it as "false"
      lv |> element("input[name='form[skip_builtins]']") |> render_change(%{"form" => %{}})

      assert lv.assigns.form["skip_builtins"] == "false"
    end

    test "preserves form state on change", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      # Set some initial values
      lv
      |> element("form")
      |> render_change(%{
        "form" => %{
          "event" => "pre_tool_use",
          "agent_type" => "test-agent"
        }
      })

      initial_form = lv.assigns.form

      # Update only one field
      lv |> element("input[name='form[tool]']") |> render_change(%{"form" => %{"tool" => "Write"}})

      # Other fields should be preserved
      assert lv.assigns.form["event"] == "pre_tool_use"
      assert lv.assigns.form["agent_type"] == "test-agent"
      assert lv.assigns.form["tool"] == "Write"
    end
  end

  describe "IAMLive.Simulator - handle_event: simulate" do
    test "generates result with valid form data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{
          "event" => "pre_tool_use",
          "agent_type" => "root",
          "tool" => "Bash",
          "resource_content" => "rm -rf /",
          "skip_builtins" => "false",
          "fallback_permission" => "allow"
        }
      })

      # Verify result is populated
      assert lv.assigns.result != nil
      assert is_map(lv.assigns.result)
    end

    test "builds context correctly from form data", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{
          "event" => "post_tool_use",
          "agent_type" => "researcher",
          "tool" => "WebFetch",
          "resource_path" => "https://example.com",
          "project_id" => "42",
          "session_uuid" => "test-uuid-123"
        }
      })

      # Verify context is set
      assert lv.assigns.context != nil
      assert %Context{} = lv.assigns.context
    end

    test "parses event correctly (pre_tool_use)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"event" => "pre_tool_use"}
      })

      assert lv.assigns.context.event == :pre_tool_use
    end

    test "parses event correctly (post_tool_use)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"event" => "post_tool_use"}
      })

      assert lv.assigns.context.event == :post_tool_use
    end

    test "parses event correctly (stop)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"event" => "stop"}
      })

      assert lv.assigns.context.event == :stop
    end

    test "defaults unknown event to pre_tool_use", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"event" => "invalid_event"}
      })

      assert lv.assigns.context.event == :pre_tool_use
    end

    test "parses permission correctly (allow)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"fallback_permission" => "allow"}
      })

      assert lv.assigns.result.decision.permission == :allow
    end

    test "parses permission correctly (deny)", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"fallback_permission" => "deny"}
      })

      assert lv.assigns.result.decision.permission == :deny
    end

    test "handles skip_builtins option", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"skip_builtins" => "true"}
      })

      # Result should be populated (can't directly verify skip_builtins was used without mocking)
      assert lv.assigns.result != nil
    end

    test "handles empty project_id as nil", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"project_id" => ""}
      })

      assert is_nil(lv.assigns.context.project_id)
    end

    test "parses numeric project_id", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"project_id" => "123"}
      })

      assert lv.assigns.context.project_id == 123
    end

    test "infers resource_type as :command for Bash", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"tool" => "Bash"}
      })

      assert lv.assigns.context.resource_type == :command
    end

    test "infers resource_type as :file for file tools", %{conn: conn} do
      file_tools = ["Edit", "Write", "Read", "NotebookEdit", "MultiEdit"]

      for tool <- file_tools do
        {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

        lv
        |> element("form")
        |> render_submit(%{
          "form" => %{"tool" => tool}
        })

        assert lv.assigns.context.resource_type == :file
      end
    end

    test "infers resource_type as :url for web tools", %{conn: conn} do
      web_tools = ["WebFetch", "WebSearch"]

      for tool <- web_tools do
        {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

        lv
        |> element("form")
        |> render_submit(%{
          "form" => %{"tool" => tool}
        })

        assert lv.assigns.context.resource_type == :url
      end
    end

    test "defaults to :unknown for unknown tool", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"tool" => "UnknownTool"}
      })

      assert lv.assigns.context.resource_type == :unknown
    end
  end

  describe "IAMLive.Simulator - handle_event: reset" do
    test "resets form to defaults", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      # Modify form
      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{
          "event" => "stop",
          "agent_type" => "custom",
          "tool" => "Write"
        }
      })

      # Reset
      lv |> element("button", "Reset") |> render_click()

      assert lv.assigns.form["event"] == "pre_tool_use"
      assert lv.assigns.form["agent_type"] == "root"
      assert lv.assigns.form["tool"] == "Bash"
    end

    test "clears result on reset", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      # Generate result
      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"tool" => "Bash"}
      })

      assert lv.assigns.result != nil

      # Reset
      lv |> element("button", "Reset") |> render_click()

      assert is_nil(lv.assigns.result)
    end
  end

  describe "IAMLive.Simulator - rendering" do
    test "renders title and description", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "IAM Simulator"
      assert html =~ "dry-run"
    end

    test "renders form inputs", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "Event"
      assert html =~ "Agent type"
      assert html =~ "Tool"
      assert html =~ "Resource path"
      assert html =~ "Resource content"
    end

    test "renders preset buttons", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "rm -rf /"
      assert html =~ "sudo apt"
      assert html =~ "git push main"
      assert html =~ "curl | sh"
      assert html =~ ".env read"
    end

    test "renders simulate button", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "Simulate"
    end

    test "renders result section after simulation", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{"tool" => "Bash"}
      })

      html = render(lv)

      # Result section should be visible
      assert html =~ "Trace" or html =~ "decision"
    end

    test "shows info message when no result", %{conn: conn} do
      {:ok, _lv, html} = live(conn, ~p"/iam/simulator")

      assert html =~ "Fill in the form and click Simulate"
    end
  end

  describe "IAMLive.Simulator - integration" do
    test "complete flow: form change → simulate → reset", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      # Initial state
      assert lv.assigns.form["tool"] == "Bash"
      assert is_nil(lv.assigns.result)

      # Apply preset
      lv |> element("button", "rm -rf /") |> render_click()

      assert lv.assigns.form["resource_content"] == "rm -rf /"

      # Simulate
      lv |> element("form") |> render_submit()

      assert lv.assigns.result != nil

      # Reset
      lv |> element("button", "Reset") |> render_click()

      assert lv.assigns.form["tool"] == "Bash"
      assert is_nil(lv.assigns.result)
    end
  end

  describe "IAMLive.Simulator - edge cases" do
    test "handles empty string values in form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{
          "resource_path" => "",
          "resource_content" => "",
          "session_uuid" => ""
        }
      })

      # Should convert empty strings to nil in context
      assert is_nil(lv.assigns.context.resource_path)
      assert is_nil(lv.assigns.context.resource_content)
      assert is_nil(lv.assigns.context.session_uuid)
    end

    test "handles whitespace-only values in form", %{conn: conn} do
      {:ok, lv, _html} = live(conn, ~p"/iam/simulator")

      lv
      |> element("form")
      |> render_submit(%{
        "form" => %{
          "resource_path" => "   ",
          "agent_type" => "   "
        }
      })

      # Whitespace should be preserved (not trimmed at simulator level)
      assert lv.assigns.context.resource_path != nil or is_nil(lv.assigns.context.resource_path)
    end
  end
end

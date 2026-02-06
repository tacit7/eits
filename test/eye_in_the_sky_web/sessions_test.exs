defmodule EyeInTheSkyWeb.SessionsTest do
  use EyeInTheSkyWeb.DataCase

  alias EyeInTheSkyWeb.Sessions
  alias EyeInTheSkyWeb.Sessions.Session

  describe "model tracking" do
    setup do
      agent =
        Repo.insert!(%EyeInTheSkyWeb.Agents.Agent{
          id: "test-agent-#{System.unique_integer()}",
          source: "worktree",
          bookmarked: false
        })

      {:ok, agent: agent}
    end

    test "create_session_with_model requires model_provider and model_name", %{agent: agent} do
      # Missing model_provider
      {:error, changeset} =
        Sessions.create_session_with_model(%{
          id: "test-session",
          agent_id: agent.id,
          started_at: DateTime.utc_now(),
          model_name: "claude-3-5-sonnet"
        })

      assert "model_provider" in (changeset.errors
                                  |> Enum.map(&elem(&1, 0))
                                  |> Enum.map(&to_string/1))

      # Missing model_name
      {:error, changeset} =
        Sessions.create_session_with_model(%{
          id: "test-session-2",
          agent_id: agent.id,
          started_at: DateTime.utc_now(),
          model_provider: "anthropic"
        })

      assert "model_name" in (changeset.errors
                              |> Enum.map(&elem(&1, 0))
                              |> Enum.map(&to_string/1))

      # Both present - should succeed
      {:ok, session} =
        Sessions.create_session_with_model(%{
          id: "test-session-3",
          agent_id: agent.id,
          started_at: DateTime.utc_now(),
          model_provider: "anthropic",
          model_name: "claude-3-5-sonnet"
        })

      assert session.model_provider == "anthropic"
      assert session.model_name == "claude-3-5-sonnet"
    end

    test "model_version is optional in creation", %{agent: agent} do
      {:ok, session} =
        Sessions.create_session_with_model(%{
          id: "test-session-version",
          agent_id: agent.id,
          started_at: DateTime.utc_now(),
          model_provider: "anthropic",
          model_name: "claude-3-5-sonnet"
          # Note: no model_version
        })

      assert session.model_provider == "anthropic"
      assert session.model_name == "claude-3-5-sonnet"
      assert is_nil(session.model_version) or session.model_version == ""
    end

    test "extract_model_info parses nested model objects" do
      # Valid model object with all fields
      {:ok, model_info} =
        Sessions.extract_model_info(%{
          "provider" => "anthropic",
          "name" => "claude-3-5-sonnet",
          "version" => "20241022"
        })

      assert model_info == %{
               model_provider: "anthropic",
               model_name: "claude-3-5-sonnet",
               model_version: "20241022"
             }

      # Valid model object without version
      {:ok, model_info} =
        Sessions.extract_model_info(%{
          "provider" => "anthropic",
          "name" => "claude-3-5-sonnet"
        })

      assert model_info == %{
               model_provider: "anthropic",
               model_name: "claude-3-5-sonnet",
               model_version: nil
             }

      # Atom keys should also work
      {:ok, model_info} =
        Sessions.extract_model_info(%{
          provider: "anthropic",
          name: "claude-opus"
        })

      assert model_info.model_provider == "anthropic"
      assert model_info.model_name == "claude-opus"

      # Missing required fields
      {:error, msg} = Sessions.extract_model_info(%{"provider" => "anthropic"})
      assert String.contains?(msg, ["provider", "name"])

      # Invalid input
      {:error, _msg} = Sessions.extract_model_info(nil)
      {:error, _msg} = Sessions.extract_model_info("not a map")
    end

    test "format_model_info displays model information correctly", %{agent: agent} do
      # Session with all model fields
      {:ok, session} =
        Sessions.create_session_with_model(%{
          id: "test-format-1",
          agent_id: agent.id,
          started_at: DateTime.utc_now(),
          model_provider: "anthropic",
          model_name: "claude-3-5-sonnet",
          model_version: "20241022"
        })

      formatted = Sessions.format_model_info(session)
      assert formatted == "anthropic/claude-3-5-sonnet (20241022)"

      # Session without version
      {:ok, session_no_version} =
        Sessions.create_session_with_model(%{
          id: "test-format-2",
          agent_id: agent.id,
          started_at: DateTime.utc_now(),
          model_provider: "anthropic",
          model_name: "claude-opus"
        })

      formatted = Sessions.format_model_info(session_no_version)
      assert formatted == "anthropic/claude-opus"

      # Session without model info (should fallback)
      formatted = %Session{model_provider: nil, model_name: nil} |> Sessions.format_model_info()
      assert formatted == "unknown"
    end

    test "model fields are immutable after creation", %{agent: agent} do
      {:ok, session} =
        Sessions.create_session_with_model(%{
          id: "test-immutable",
          agent_id: agent.id,
          started_at: DateTime.utc_now(),
          model_provider: "anthropic",
          model_name: "claude-3-5-sonnet",
          model_version: "20241022"
        })

      # Try to update model fields
      {:ok, updated} =
        Sessions.update_session(session, %{
          model_provider: "openai",
          model_name: "gpt-4",
          model_version: "1.0",
          # This should update
          status: "idle"
        })

      # Model fields should NOT change
      assert updated.model_provider == "anthropic"
      assert updated.model_name == "claude-3-5-sonnet"
      assert updated.model_version == "20241022"

      # But status should change
      assert updated.status == "idle"
    end

    test "create_session_with_model handles extraction from nested model param" do
      agent =
        Repo.insert!(%EyeInTheSkyWeb.Agents.Agent{
          id: "test-extract-#{System.unique_integer()}",
          source: "worktree",
          bookmarked: false
        })

      # If we can extract model info from a nested structure
      model_data = %{
        "provider" => "anthropic",
        "name" => "claude-3-5-sonnet",
        "version" => "20241022"
      }

      {:ok, extracted} = Sessions.extract_model_info(model_data)

      # Use extracted info to create session
      session_attrs =
        Map.merge(extracted, %{
          id: "test-extracted-session",
          agent_id: agent.id,
          started_at: DateTime.utc_now()
        })

      {:ok, session} = Sessions.create_session_with_model(session_attrs)

      assert Sessions.format_model_info(session) == "anthropic/claude-3-5-sonnet (20241022)"
    end
  end
end

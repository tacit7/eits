defmodule EyeInTheSkyWeb.MCP.Tools.DataToolsTest do
  use EyeInTheSkyWeb.DataCase, async: false

  alias EyeInTheSkyWeb.MCP.Tools.{
    ProjectAdd,
    Commits,
    PromptGet,
    SaveSessionContext,
    LoadSessionContext
  }

  alias EyeInTheSkyWeb.{Agents, Sessions, Prompts}

  @frame :test_frame

  import EyeInTheSkyWeb.Factory

  defp new_prompt do
    {:ok, p} =
      Prompts.create_prompt(%{
        uuid: Ecto.UUID.generate(),
        name: "prompt #{uniq()}",
        slug: "slug#{uniq()}",
        prompt_text: "do the thing",
        active: true
      })

    p
  end

  # ---- ProjectAdd ----

  test "ProjectAdd: creates project" do
    r = ProjectAdd.execute(%{name: "Proj #{uniq()}"}, @frame) |> json_result()
    assert r.success == true
    assert r.message == "Project created"
    assert is_integer(r.project_id)
  end

  test "ProjectAdd: fails without a name" do
    r = ProjectAdd.execute(%{name: nil}, @frame) |> json_result()
    assert r.success == false
  end

  # ---- Commits ----

  test "Commits: logs commits for a known session" do
    s = new_session()

    r =
      Commits.execute(
        %{
          agent_id: s.uuid,
          commit_hashes: ["abc123", "def456"],
          commit_messages: ["msg1", "msg2"]
        },
        @frame
      )
      |> json_result()

    assert r.success == true
    assert r.message == "Logged 2/2 commits"
  end

  test "Commits: returns error when session cannot be resolved" do
    r =
      Commits.execute(
        %{
          agent_id: "unknown-uuid",
          commit_hashes: ["aaa111"],
          commit_messages: ["orphan"]
        },
        @frame
      )
      |> json_result()

    # nil guard: unknown UUID returns error instead of silently inserting with nil session_id
    assert r.success == false
    assert String.contains?(r.message, "Could not resolve session")
  end

  test "Commits: handles empty list" do
    s = new_session()
    r = Commits.execute(%{agent_id: s.uuid, commit_hashes: []}, @frame) |> json_result()
    assert r.success == true
    assert r.message == "Logged 0/0 commits"
  end

  # ---- PromptGet ----

  test "PromptGet: returns prompt by integer ID" do
    p = new_prompt()
    r = PromptGet.execute(%{id: to_string(p.id)}, @frame) |> json_result()
    assert r.success == true
    assert r.prompt.id == p.id
  end

  test "PromptGet: returns prompt by slug" do
    p = new_prompt()
    r = PromptGet.execute(%{slug: p.slug}, @frame) |> json_result()
    assert r.success == true
    assert r.prompt.slug == p.slug
  end

  test "PromptGet: includes prompt_text by default" do
    p = new_prompt()
    r = PromptGet.execute(%{id: to_string(p.id)}, @frame) |> json_result()
    assert r.prompt.prompt_text == "do the thing"
  end

  test "PromptGet: excludes prompt_text when include_text false" do
    p = new_prompt()
    r = PromptGet.execute(%{id: to_string(p.id), include_text: false}, @frame) |> json_result()
    assert r.success == true
    refute Map.has_key?(r.prompt, :prompt_text)
  end

  test "PromptGet: error for nonexistent ID" do
    r = PromptGet.execute(%{id: "999999"}, @frame) |> json_result()
    assert r.success == false
  end

  test "PromptGet: error when neither id nor slug given" do
    r = PromptGet.execute(%{}, @frame) |> json_result()
    assert r.success == false
    assert r.message == "Either id or slug is required"
  end

  # ---- SaveSessionContext / LoadSessionContext ----

  test "SaveSessionContext: saves context for a known session" do
    s = new_session()

    r =
      SaveSessionContext.execute(%{agent_id: s.uuid, context: "# Context\nsome work"}, @frame)
      |> json_result()

    assert r.success == true
    assert r.message == "Session context saved"
  end

  test "SaveSessionContext: error for unknown session UUID" do
    r =
      SaveSessionContext.execute(%{agent_id: "ghost-uuid", context: "data"}, @frame)
      |> json_result()

    assert r.success == false
  end

  test "LoadSessionContext: error when no context saved" do
    s = new_session()
    r = LoadSessionContext.execute(%{agent_id: s.uuid}, @frame) |> json_result()
    assert r.success == false
    assert String.contains?(r.message, "No context found")
  end

  test "LoadSessionContext: returns saved context" do
    s = new_session()
    SaveSessionContext.execute(%{agent_id: s.uuid, context: "# My context"}, @frame)
    r = LoadSessionContext.execute(%{agent_id: s.uuid}, @frame) |> json_result()
    assert r.success == true
    assert r.context == "# My context"
  end

  test "LoadSessionContext: session_id takes priority over agent_id" do
    s = new_session()
    SaveSessionContext.execute(%{agent_id: s.uuid, context: "right context"}, @frame)

    r =
      LoadSessionContext.execute(%{session_id: s.uuid, agent_id: "other"}, @frame)
      |> json_result()

    assert r.success == true
    assert r.context == "right context"
  end
end

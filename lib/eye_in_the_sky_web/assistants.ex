defmodule EyeInTheSkyWeb.Assistants do
  @moduledoc """
  Context for managing reusable assistant definitions.
  An assistant wraps a prompt with executable configuration (model, effort, tool policy, scope).
  """

  import Ecto.Query, warn: false
  alias EyeInTheSkyWeb.Repo
  alias EyeInTheSkyWeb.Assistants.{Assistant, Tool}

  @doc """
  Returns all assistants, optionally filtered by project.
  """
  def list_assistants(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    include_inactive = Keyword.get(opts, :include_inactive, false)

    query = from(a in Assistant)

    query =
      unless include_inactive do
        where(query, [a], a.active == true)
      else
        query
      end

    query =
      case project_id do
        nil -> query
        id -> where(query, [a], a.project_id == ^id or is_nil(a.project_id))
      end

    query
    |> order_by([a], desc: a.updated_at)
    |> preload([:prompt, :project])
    |> Repo.all()
  end

  @doc """
  Gets a single assistant by ID. Raises if not found.
  """
  def get_assistant!(id) do
    Assistant
    |> Repo.get!(id)
    |> Repo.preload([:prompt, :project])
  end

  @doc """
  Gets a single assistant by ID. Returns nil if not found.
  """
  def get_assistant(id) do
    Assistant
    |> Repo.get(id)
    |> case do
      nil -> nil
      a -> Repo.preload(a, [:prompt, :project])
    end
  end

  @doc """
  Creates an assistant.
  """
  def create_assistant(attrs \\ %{}) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %Assistant{}
    |> Assistant.changeset(attrs)
    |> Ecto.Changeset.put_change(:inserted_at, now)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.insert()
  end

  @doc """
  Updates an assistant.
  """
  def update_assistant(%Assistant{} = assistant, attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    assistant
    |> Assistant.changeset(attrs)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.update()
  end

  @doc """
  Deactivates an assistant (soft delete).
  """
  def deactivate_assistant(%Assistant{} = assistant) do
    update_assistant(assistant, %{active: false})
  end

  @doc """
  Hard deletes an assistant.
  """
  def delete_assistant(%Assistant{} = assistant) do
    Repo.delete(assistant)
  end

  @doc """
  Returns a changeset for tracking assistant changes.
  """
  def change_assistant(%Assistant{} = assistant, attrs \\ %{}) do
    Assistant.changeset(assistant, attrs)
  end

  @doc """
  Lists project-scoped assistants.
  """
  def list_project_assistants(project_id) do
    Assistant
    |> where([a], a.project_id == ^project_id and a.active == true)
    |> order_by([a], desc: a.updated_at)
    |> preload([:prompt])
    |> Repo.all()
  end

  @doc """
  Lists global assistants (no project scope).
  """
  def list_global_assistants do
    Assistant
    |> where([a], is_nil(a.project_id) and a.active == true)
    |> order_by([a], desc: a.updated_at)
    |> preload([:prompt])
    |> Repo.all()
  end

  # ── Tool Registry ─────────────────────────────────────────────────────────────

  @doc """
  Lists all active tools in the catalog.
  """
  def list_tools(opts \\ []) do
    include_inactive = Keyword.get(opts, :include_inactive, false)

    Tool
    |> then(fn q -> if include_inactive, do: q, else: where(q, [t], t.active == true) end)
    |> order_by([t], asc: t.name)
    |> Repo.all()
  end

  @doc """
  Gets a tool by name. Returns nil if not found.
  """
  def get_tool_by_name(name), do: Repo.get_by(Tool, name: name, active: true)

  @doc """
  Gets a tool by ID.
  """
  def get_tool!(id), do: Repo.get!(Tool, id)

  @doc """
  Checks if a tool is allowed for a given assistant.
  Returns {:ok, :allowed}, {:ok, :requires_approval}, or {:error, :denied}.

  Policy precedence:
    1. If tool is in assistant's denied list — denied
    2. If tool is in assistant's requires_approval list — requires_approval
    3. If tool is in assistant's allowed list — allowed
    4. Falls back to tool's requires_approval_default
    5. If no tool_policy set on assistant — allowed (open policy)
  """
  def check_tool_policy(%Assistant{tool_policy: nil}, _tool_name), do: {:ok, :allowed}
  def check_tool_policy(%Assistant{tool_policy: policy}, tool_name) when is_map(policy) do
    denied   = Map.get(policy, "denied", [])
    approval = Map.get(policy, "requires_approval", [])
    allowed  = Map.get(policy, "allowed", [])

    cond do
      tool_name in denied   -> {:error, :denied}
      tool_name in approval -> {:ok, :requires_approval}
      tool_name in allowed  -> {:ok, :allowed}
      allowed == []         -> {:ok, :allowed}
      true                  -> {:error, :denied}
    end
  end

  @doc """
  Returns the list of tool names allowed for an assistant (no approval check).
  Used for prompt construction — tells the assistant which tools it can use.
  """
  def allowed_tool_names(%Assistant{tool_policy: nil}) do
    list_tools() |> Enum.map(& &1.name)
  end

  def allowed_tool_names(%Assistant{tool_policy: policy}) when is_map(policy) do
    denied  = Map.get(policy, "denied", [])
    allowed = Map.get(policy, "allowed", [])

    if allowed == [] do
      list_tools()
      |> Enum.map(& &1.name)
      |> Enum.reject(& &1 in denied)
    else
      allowed -- denied
    end
  end
end

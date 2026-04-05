defmodule EyeInTheSky.Prompts do
  @moduledoc """
  The Prompts context for managing subagent prompt templates.
  """

  import Ecto.Query, warn: false
  alias EyeInTheSky.Prompts.Prompt
  alias EyeInTheSky.Repo
  alias EyeInTheSky.Search.PgSearch
  alias EyeInTheSky.Utils.ToolHelpers

  @doc """
  Returns the list of prompts with optional project filter.
  """
  def list_prompts(opts \\ []) do
    project_id = Keyword.get(opts, :project_id)
    include_inactive = Keyword.get(opts, :include_inactive, false)

    query = from(p in Prompt)

    query =
      if include_inactive do
        query
      else
        where(query, [p], p.active == true)
      end

    query =
      case project_id do
        nil -> query
        id -> where(query, [p], p.project_id == ^id or is_nil(p.project_id))
      end

    query
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Gets a single prompt by ID.

  Raises `Ecto.NoResultsError` if the Prompt does not exist.
  """
  def get_prompt!(id), do: Repo.get!(Prompt, id)

  @doc "Gets a single prompt by ID. Returns nil if not found."
  def get_prompt(id), do: Repo.get(Prompt, id)

  @doc """
  Gets a single prompt by UUID.

  Raises `Ecto.NoResultsError` if the Prompt does not exist.
  """
  def get_prompt_by_uuid!(uuid), do: Repo.get_by!(Prompt, uuid: uuid)

  @doc """
  Gets a single prompt by slug.
  Returns nil if not found.
  """
  def get_prompt_by_slug(slug, project_id \\ nil) do
    query =
      from p in Prompt,
        where: p.slug == ^slug and p.active == true

    query =
      case project_id do
        nil ->
          where(query, [p], is_nil(p.project_id))

        id ->
          from p in query,
            where: p.project_id == ^id or is_nil(p.project_id),
            order_by: [desc: fragment("CASE WHEN ? IS NULL THEN 0 ELSE 1 END", p.project_id)]
      end

    Repo.one(query)
  end

  @doc """
  Resolves a prompt by integer ID, UUID, or slug (in that order).
  Returns `{:ok, prompt}` or `{:error, :not_found}`.
  The `project_id` param narrows slug lookups to a specific project.
  """
  def get_prompt_by_ref(ref, project_id \\ nil) do
    cond do
      id = ToolHelpers.parse_int(ref) ->
        case get_prompt(id) do
          nil -> {:error, :not_found}
          prompt -> {:ok, prompt}
        end

      Regex.match?(~r/^[0-9a-f-]{36}$/, ref) ->
        case get_prompt(ref) do
          nil -> {:error, :not_found}
          prompt -> {:ok, prompt}
        end

      true ->
        prompt =
          if project_id do
            get_prompt_by_slug(ref, project_id) || get_prompt_by_slug(ref, nil)
          else
            get_prompt_by_slug(ref, nil)
          end

        if prompt, do: {:ok, prompt}, else: {:error, :not_found}
    end
  end

  @doc """
  Creates a prompt. Auto-generates UUID and timestamps if not provided.
  """
  def create_prompt(attrs \\ %{}) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    %Prompt{}
    |> Prompt.changeset(attrs)
    |> Ecto.Changeset.put_change(:uuid, Ecto.UUID.generate())
    |> Ecto.Changeset.put_change(:created_at, now)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.insert()
  end

  @doc """
  Updates a prompt.
  """
  def update_prompt(%Prompt{} = prompt, attrs) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    prompt
    |> Prompt.changeset(attrs)
    |> Ecto.Changeset.put_change(:updated_at, now)
    |> Repo.update()
  end

  @doc """
  Soft deletes a prompt by setting active to false.
  """
  def deactivate_prompt(%Prompt{} = prompt) do
    update_prompt(prompt, %{active: false})
  end

  @doc """
  Hard deletes a prompt.
  Returns `{:error, :has_active_schedule}` if a scheduled job references this prompt.
  """
  def delete_prompt(%Prompt{} = prompt) do
    case Repo.delete(prompt) do
      {:ok, p} -> {:ok, p}
      {:error, %Ecto.Changeset{} = cs} -> {:error, cs}
    end
  rescue
    Ecto.ConstraintError -> {:error, :has_active_schedule}
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking prompt changes.
  """
  def change_prompt(%Prompt{} = prompt, attrs \\ %{}) do
    Prompt.changeset(prompt, attrs)
  end

  @doc """
  Lists global prompts (no project_id).
  """
  def list_global_prompts do
    Prompt
    |> where([p], is_nil(p.project_id) and p.active == true)
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Lists project-specific prompts.
  """
  def list_project_prompts(project_id) do
    Prompt
    |> where([p], p.project_id == ^project_id and p.active == true)
    |> order_by([p], desc: p.updated_at)
    |> Repo.all()
  end

  @doc """
  Search prompts using PostgreSQL full-text search.
  """
  def search_prompts(query, project_id \\ nil) when is_binary(query) do
    extra_where =
      if project_id do
        dynamic([p], (p.project_id == ^project_id or is_nil(p.project_id)) and p.active == true)
      else
        dynamic([p], p.active == true)
      end

    PgSearch.search_for(query,
      table: "subagent_prompts",
      schema: Prompt,
      search_columns: ["name", "description", "prompt_text"],
      sql_filter: """
      #{if project_id, do: "AND (s.project_id = $2 OR s.project_id IS NULL)", else: ""}
      AND s.active = true
      """,
      sql_params: if(project_id, do: [project_id], else: []),
      extra_where: extra_where,
      order_by: [desc: :updated_at]
    )
  end
end

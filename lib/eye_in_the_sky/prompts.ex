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
    limit_val = Keyword.get(opts, :limit, 500)

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
    |> limit(^limit_val)
    |> Repo.all()
  end

  @doc """
  Gets a single prompt by ID.

  Raises `Ecto.NoResultsError` if the Prompt does not exist.
  """
  def get_prompt!(id), do: Repo.get!(Prompt, id)

  @doc "Gets a single prompt by ID. Returns `{:ok, prompt}` or `{:error, :not_found}`."
  def get_prompt(id) do
    case Repo.get(Prompt, id) do
      nil -> {:error, :not_found}
      prompt -> {:ok, prompt}
    end
  end

  @doc """
  Gets a single prompt by UUID.

  Raises `Ecto.NoResultsError` if the Prompt does not exist.
  """
  def get_prompt_by_uuid!(uuid), do: Repo.get_by!(Prompt, uuid: uuid)

  @doc "Gets a single prompt by UUID. Returns `{:ok, prompt}` or `{:error, :not_found}`."
  def get_prompt_by_uuid(uuid) do
    case Repo.get_by(Prompt, uuid: uuid) do
      nil -> {:error, :not_found}
      prompt -> {:ok, prompt}
    end
  end

  @doc """
  Gets a single prompt by slug.
  Returns `{:ok, prompt}` or `{:error, :not_found}`.
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

    case Repo.one(query) do
      nil -> {:error, :not_found}
      prompt -> {:ok, prompt}
    end
  end

  @doc """
  Resolves a prompt by integer ID, UUID, or slug (in that order).
  Returns `{:ok, prompt}` or `{:error, :not_found}`.
  The `project_id` param narrows slug lookups to a specific project.
  """
  def get_prompt_by_ref(ref, project_id \\ nil) do
    cond do
      id = ToolHelpers.parse_int(ref) ->
        get_prompt(id)

      Regex.match?(~r/^[0-9a-f-]{36}$/, ref) ->
        get_prompt_by_uuid(ref)

      true ->
        if project_id do
          case get_prompt_by_slug(ref, project_id) do
            {:ok, prompt} -> {:ok, prompt}
            {:error, :not_found} -> get_prompt_by_slug(ref, nil)
          end
        else
          get_prompt_by_slug(ref, nil)
        end
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
  Returns `{:error, changeset}` if a scheduled job references this prompt.
  """
  def delete_prompt(%Prompt{} = prompt) do
    prompt
    |> Prompt.delete_changeset()
    |> Repo.delete()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking prompt changes.
  """
  def change_prompt(%Prompt{} = prompt, attrs \\ %{}) do
    Prompt.changeset(prompt, attrs)
  end

  @doc """
  Lists global prompts (no project_id). Default limit: 500.
  """
  def list_global_prompts(opts \\ []) do
    limit_val = Keyword.get(opts, :limit, 500)

    Prompt
    |> where([p], is_nil(p.project_id) and p.active == true)
    |> order_by([p], desc: p.updated_at)
    |> limit(^limit_val)
    |> Repo.all()
  end

  @doc """
  Lists project-specific prompts. Default limit: 500.
  """
  def list_project_prompts(project_id, opts \\ []) do
    limit_val = Keyword.get(opts, :limit, 500)

    Prompt
    |> where([p], p.project_id == ^project_id and p.active == true)
    |> order_by([p], desc: p.updated_at)
    |> limit(^limit_val)
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
      extra_where: extra_where,
      order_by: [desc: :updated_at]
    )
  end
end

defmodule EyeInTheSkyWebWeb.Api.V1.PromptController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Prompts

  @doc """
  GET /api/v1/prompts - List prompts. Supports ?query= for search, ?project_id= for scoping.
  """
  def index(conn, params) do
    prompts =
      cond do
        params["query"] && params["query"] != "" ->
          Prompts.search_prompts(params["query"], params["project_id"])

        params["project_id"] ->
          Prompts.list_project_prompts(params["project_id"])

        true ->
          Prompts.list_global_prompts()
      end

    json(conn, %{
      success: true,
      prompts:
        Enum.map(prompts, fn p ->
          %{id: p.id, uuid: p.uuid, name: p.name, slug: p.slug, description: p.description, project_id: p.project_id, active: p.active}
        end)
    })
  end

  @doc """
  GET /api/v1/prompts/:id - Get a prompt by ID or slug.
  Query params: project_id (for slug scope), include_text (default true)
  """
  def show(conn, %{"id" => id} = params) do
    include_text = params["include_text"] != "false"

    result =
      cond do
        # If it looks like a UUID or integer, try by ID first
        Regex.match?(~r/^\d+$/, id) ->
          try do
            {:ok, Prompts.get_prompt!(id)}
          rescue
            Ecto.NoResultsError -> {:error, :not_found}
          end

        Regex.match?(~r/^[0-9a-f-]{36}$/, id) ->
          try do
            {:ok, Prompts.get_prompt!(id)}
          rescue
            Ecto.NoResultsError -> {:error, :not_found}
          end

        # Otherwise treat as slug
        true ->
          prompt =
            if params["project_id"] do
              Prompts.get_prompt_by_slug(id, params["project_id"]) ||
                Prompts.get_prompt_by_slug(id, nil)
            else
              Prompts.get_prompt_by_slug(id, nil)
            end

          if prompt, do: {:ok, prompt}, else: {:error, :not_found}
      end

    case result do
      {:ok, prompt} ->
        base = %{
          success: true,
          prompt: %{
            id: prompt.id,
            uuid: prompt.uuid,
            name: prompt.name,
            slug: prompt.slug,
            description: prompt.description,
            project_id: prompt.project_id,
            active: prompt.active
          }
        }

        response =
          if include_text do
            put_in(base, [:prompt, :prompt_text], prompt.prompt_text)
          else
            base
          end

        json(conn, response)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{error: "Prompt not found"})
    end
  end

  @doc """
  POST /api/v1/prompts - Create a new prompt.

  Required: name, slug, prompt_text
  Optional: description, project_id, tags, created_by
  """
  def create(conn, params) do
    attrs = %{
      name: params["name"],
      slug: params["slug"],
      description: params["description"],
      prompt_text: params["prompt_text"],
      project_id: params["project_id"],
      tags: params["tags"],
      created_by: params["created_by"]
    }

    case Prompts.create_prompt(attrs) do
      {:ok, prompt} ->
        conn
        |> put_status(:created)
        |> json(%{
          id: prompt.id,
          uuid: prompt.uuid,
          name: prompt.name,
          slug: prompt.slug,
          description: prompt.description,
          version: prompt.version
        })

      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "Failed to create prompt", details: translate_errors(changeset)})
    end
  end

  defp translate_errors(%Ecto.Changeset{} = changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Enum.reduce(opts, msg, fn {key, value}, acc ->
        String.replace(acc, "%{#{key}}", to_string(value))
      end)
    end)
  end
end

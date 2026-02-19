defmodule EyeInTheSkyWebWeb.Api.V1.PromptController do
  use EyeInTheSkyWebWeb, :controller

  alias EyeInTheSkyWeb.Prompts

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

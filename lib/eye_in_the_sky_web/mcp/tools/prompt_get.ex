defmodule EyeInTheSkyWeb.MCP.Tools.PromptGet do
  @moduledoc "Retrieve a subagent prompt by slug or ID (project-aware fallback)"

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field :id, :string, description: "Prompt ID"
    field :slug, :string, description: "Prompt slug"
    field :project_id, :string, description: "Project context for slug lookup (checks project-scoped first, falls back to global)"
    field :include_text, :boolean, description: "Include prompt_text in response (default: true)"
  end

  @impl true
  def execute(params, frame) do
    alias EyeInTheSkyWeb.Prompts

    include_text = params["include_text"] != false

    result =
      cond do
        params["id"] ->
          try do
            prompt = Prompts.get_prompt!(params["id"])
            format_prompt(prompt, include_text)
          rescue
            Ecto.NoResultsError -> %{success: false, message: "Prompt not found"}
          end

        params["slug"] ->
          # Project-aware: check project scope first, fall back to global
          prompt =
            if params["project_id"] do
              Prompts.get_prompt_by_slug(params["slug"], params["project_id"]) ||
                Prompts.get_prompt_by_slug(params["slug"], nil)
            else
              Prompts.get_prompt_by_slug(params["slug"], nil)
            end

          if prompt do
            format_prompt(prompt, include_text)
          else
            %{success: false, message: "Prompt not found for slug: #{params["slug"]}"}
          end

        true ->
          %{success: false, message: "Either id or slug is required"}
      end

    response = Response.tool() |> Response.json(result)
    {:reply, response, frame}
  end

  defp format_prompt(prompt, include_text) do
    base = %{
      success: true,
      message: "Prompt found",
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

    if include_text do
      put_in(base, [:prompt, :prompt_text], prompt.prompt_text)
    else
      base
    end
  end
end

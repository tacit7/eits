defmodule EyeInTheSkyWeb.Live.Shared.PromptsHelpers do
  @moduledoc false
  import Phoenix.Component, only: [assign: 3]

  alias EyeInTheSky.Prompts

  def load_prompts(socket) do
    prompts = list_prompts_for_scope(socket.assigns)
    filtered = apply_filters_and_sort(prompts, socket.assigns)

    socket
    |> assign(:prompts, prompts)
    |> assign(:filtered_prompts, filtered)
  end

  defp list_prompts_for_scope(%{project_id: project_id}) when is_integer(project_id) do
    Prompts.list_prompts(project_id: project_id)
  end

  defp list_prompts_for_scope(_) do
    Prompts.list_prompts()
  end

  def handle_search(%{"query" => query}, socket, reload_fn) do
    {:noreply, socket |> assign(:search_query, query) |> reload_fn.()}
  end

  def handle_sort_prompts(%{"by" => by}, socket, reload_fn) do
    {:noreply, socket |> assign(:sort_by, by) |> reload_fn.()}
  end

  def handle_filter_scope(%{"scope" => scope}, socket, reload_fn) do
    {:noreply, socket |> assign(:scope_filter, scope) |> reload_fn.()}
  end

  def handle_duplicate_prompt(uuid, socket, reload_fn) do
    case Prompts.get_prompt_by_uuid(uuid) do
      {:ok, prompt} ->
        case Prompts.duplicate_prompt(prompt) do
          {:ok, _copy} ->
            {:noreply, socket |> reload_fn.() |> Phoenix.LiveView.put_flash(:info, "Duplicated")}

          {:error, _} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Duplicate failed")}
        end

      {:error, :not_found} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Prompt not found")}
    end
  end

  def handle_deactivate_prompt(uuid, socket, reload_fn, clear_fn) do
    case Prompts.get_prompt_by_uuid(uuid) do
      {:ok, prompt} ->
        case Prompts.deactivate_prompt(prompt) do
          {:ok, _} ->
            socket =
              socket
              |> reload_fn.()
              |> clear_fn.(uuid)
              |> Phoenix.LiveView.put_flash(:info, "Deactivated")

            {:noreply, socket}

          {:error, _} ->
            {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Deactivate failed")}
        end

      {:error, :not_found} ->
        {:noreply, Phoenix.LiveView.put_flash(socket, :error, "Prompt not found")}
    end
  end

  def apply_filters_and_sort(prompts, assigns) do
    prompts
    |> filter_by_scope(assigns[:scope_filter] || "all")
    |> filter_by_search(assigns[:search_query] || "")
    |> sort_prompts(assigns[:sort_by] || "recent")
  end

  defp filter_by_scope(prompts, "all"), do: prompts

  defp filter_by_scope(prompts, "global") do
    Enum.filter(prompts, &is_nil(&1.project_id))
  end

  defp filter_by_scope(prompts, "project") do
    Enum.filter(prompts, &(!is_nil(&1.project_id)))
  end

  defp filter_by_scope(prompts, _), do: prompts

  defp filter_by_search(prompts, ""), do: prompts

  defp filter_by_search(prompts, query) do
    q = String.downcase(query)

    Enum.filter(prompts, fn prompt ->
      String.contains?(String.downcase(prompt.slug), q) ||
        String.contains?(String.downcase(prompt.name || ""), q) ||
        String.contains?(String.downcase(prompt.description || ""), q)
    end)
  end

  defp sort_prompts(prompts, "name_asc"), do: Enum.sort_by(prompts, & &1.name)
  defp sort_prompts(prompts, "name_desc"), do: Enum.sort_by(prompts, & &1.name, :desc)
  defp sort_prompts(prompts, "recent"), do: Enum.sort_by(prompts, & &1.updated_at, :desc)
  defp sort_prompts(prompts, _), do: Enum.sort_by(prompts, & &1.updated_at, :desc)
end

defmodule EyeInTheSkyWeb.Components.DmPage.CodexRequestPanel do
  use EyeInTheSkyWeb, :html

  attr :requests, :list, default: []

  def panel(assigns) do
    ~H"""
    <div
      :if={@requests != []}
      id="codex-requests"
      class="w-full max-w-6xl mx-auto mb-3 space-y-2 overflow-y-auto max-h-[45vh] shrink-0"
    >
      <section
        :for={request <- @requests}
        id={"codex-request-#{encoded_id(request["id"])}"}
        class="border border-warning/35 bg-base-200 px-4 py-3 text-message"
        aria-label="Codex request"
      >
        <div class="flex items-center gap-2 font-semibold">
          <.icon name="hero-exclamation-triangle" class="size-4 text-warning" />
          {title(request["method"])}
        </div>
        <div :if={request["params"]["reason"]} class="mt-1 text-base-content/70">
          {request["params"]["reason"]}
        </div>

        <div :if={network_context(request)} class="mt-2 font-mono text-mini break-all">
          {network_context(request)}
        </div>
        <div
          :if={command(request) && !network_context(request)}
          class="mt-2 font-mono text-mini break-all"
        >
          {command(request)}
        </div>
        <div :if={request["params"]["cwd"]} class="mt-1 text-mini text-base-content/50 break-all">
          {request["params"]["cwd"]}
        </div>
        <div
          :if={request["params"]["grantRoot"]}
          class="mt-1 text-mini text-base-content/50 break-all"
        >
          {request["params"]["grantRoot"]}
        </div>
        <pre
          :if={request["params"]["additionalPermissions"]}
          class="mt-2 max-h-24 overflow-auto text-mini whitespace-pre-wrap break-all"
        >{Jason.encode!(request["params"]["additionalPermissions"], pretty: true)}</pre>

        <div :if={request["method"] == "item/fileChange/requestApproval"} class="mt-2 space-y-2">
          <details :for={change <- get_in(request, ["params", "preview", "changes"]) || []}>
            <summary class="cursor-pointer font-mono text-mini break-all">
              {change["kind"]} {change["path"]}
            </summary>
            <pre
              :if={change["diff"]}
              class="mt-1 max-h-40 overflow-auto text-mini whitespace-pre-wrap break-all"
            >{String.slice(change["diff"], 0, 10_000)}</pre>
          </details>
        </div>

        <div :if={request["method"] == "item/permissions/requestApproval"} class="mt-2">
          <pre class="max-h-32 overflow-auto text-mini whitespace-pre-wrap break-all">{Jason.encode!(request["params"]["permissions"] || request["params"]["requestedPermissions"] || %{}, pretty: true)}</pre>
        </div>
        <div
          :if={approval_request?(request) && !approval_details?(request)}
          class="mt-2 text-mini text-warning/80"
        >
          Request details are unavailable. Decline this request.
        </div>

        <.form
          for={to_form(%{}, as: :approval)}
          id={"codex-request-form-#{encoded_id(request["id"])}"}
          phx-submit="codex_request_answer"
          class="mt-3 space-y-2"
        >
          <input type="hidden" name="approval[request_id]" value={request["id"]} />

          <%= if question_request?(request) do %>
            <div :for={question <- request["params"]["questions"] || []}>
              <%= if is_list(question["options"]) and question["options"] != [] and !Enum.any?(question["options"], &(&1["isOther"] == true)) do %>
                <.input
                  type="select"
                  name={"approval[answers][#{question["id"]}]"}
                  label={question["question"] || question["id"]}
                  prompt="Select an answer"
                  value=""
                  options={
                    Enum.map(question["options"], fn option -> {option["label"], option["label"]} end)
                  }
                />
              <% else %>
                <.input
                  type="text"
                  name={"approval[answers][#{question["id"]}]"}
                  label={question["question"] || question["id"]}
                  value=""
                  required
                />
              <% end %>
            </div>
          <% end %>

          <%= if request["method"] == "mcpServer/elicitation/request" do %>
            <div :if={request["params"]["message"]} class="text-mini text-base-content/70">
              {request["params"]["message"]}
            </div>
            <a
              :if={safe_url(request["params"]["url"])}
              href={request["params"]["url"]}
              target="_blank"
              rel="noopener noreferrer"
              class="text-info underline break-all"
            >
              {request["params"]["url"]}
            </a>
            <.input
              :if={request["params"]["requestedSchema"]}
              type="textarea"
              name="approval[content_json]"
              label="Response data (JSON)"
              value="{}"
              rows="3"
            />
          <% end %>

          <div class="flex flex-wrap gap-2">
            <%= if approval_request?(request) do %>
              <button
                :if={approval_details?(request) && decision_available?(request, "accept")}
                type="submit"
                name="approval[action]"
                value="accept"
                class="eits-action eits-action--primary"
              >
                <.icon name="hero-check" class="size-4" /> Allow once
              </button>
              <button
                :if={
                  request["method"] != "item/permissions/requestApproval" &&
                    approval_details?(request) && decision_available?(request, "acceptForSession")
                }
                type="submit"
                name="approval[action]"
                value="acceptForSession"
                class="eits-action eits-action--ghost"
              >
                Allow for session
              </button>
            <% else %>
              <button
                type="submit"
                name="approval[action]"
                value={if(question_request?(request), do: "answer", else: "accept")}
                class="eits-action eits-action--primary"
              >
                <.icon name="hero-check" class="size-4" /> Submit
              </button>
            <% end %>
            <button
              type="submit"
              name="approval[action]"
              value="decline"
              class="eits-action eits-action--ghost"
            >
              Decline
            </button>
          </div>
        </.form>
      </section>
    </div>
    """
  end

  defp encoded_id(id), do: id |> to_string() |> Base.url_encode64(padding: false)

  defp question_request?(%{"method" => method}),
    do: method in ["tool/requestUserInput", "item/tool/requestUserInput"]

  defp approval_request?(%{"method" => method}),
    do:
      method in [
        "item/commandExecution/requestApproval",
        "item/fileChange/requestApproval",
        "item/permissions/requestApproval"
      ]

  defp title("item/commandExecution/requestApproval"), do: "Approve command"
  defp title("item/fileChange/requestApproval"), do: "Approve file changes"
  defp title("item/permissions/requestApproval"), do: "Grant permissions"
  defp title("tool/requestUserInput"), do: "Codex question"
  defp title("item/tool/requestUserInput"), do: "Codex question"
  defp title("mcpServer/elicitation/request"), do: "MCP request"
  defp title(_), do: "Codex request"

  defp approval_details?(%{"method" => "item/commandExecution/requestApproval"} = request) do
    is_binary(command(request)) or not is_nil(network_context(request))
  end

  defp approval_details?(%{"method" => "item/fileChange/requestApproval"} = request) do
    changes = get_in(request, ["params", "preview", "changes"])
    is_list(changes) and changes != []
  end

  defp approval_details?(%{"method" => "item/permissions/requestApproval"} = request) do
    is_map(request["params"]["permissions"] || request["params"]["requestedPermissions"])
  end

  defp approval_details?(_), do: true

  defp decision_available?(request, action) do
    case request["params"]["availableDecisions"] do
      available when is_list(available) ->
        Enum.any?(available, fn
          ^action -> true
          %{"decision" => ^action} -> true
          _ -> false
        end)

      _ ->
        true
    end
  end

  defp safe_url(url) when is_binary(url), do: String.starts_with?(url, ["https://", "http://"])
  defp safe_url(_), do: false

  defp command(request),
    do: request["params"]["command"] || get_in(request, ["params", "preview", "command"])

  defp network_context(request) do
    case get_in(request, ["params", "networkApprovalContext"]) do
      %{"host" => host} = context ->
        "#{context["protocol"] || "network"}://#{host}#{if context["port"], do: ":#{context["port"]}", else: ""}"

      _ ->
        nil
    end
  end
end

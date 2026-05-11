defmodule EyeInTheSky.Github.RuleActions do
  require Logger

  alias EyeInTheSky.Github.Template

  def dispatch(rule, ctx) do
    template_ctx = build_template_ctx(ctx)

    case render_config(rule.action_config, template_ctx) do
      {:ok, rendered} -> execute(rule.action_type, rendered, ctx)
      {:error, reason} -> {:error, reason}
    end
  end

  defp execute("broadcast_only", config, _ctx) do
    topic = config["topic"] || "github:webhook"
    message = config["message"] || ""
    Phoenix.PubSub.broadcast(EyeInTheSky.PubSub, topic, {:webhook_rule_fired, message})
    :ok
  end

  defp execute("spawn_agent", config, _ctx) do
    agent_name = config["agent"]
    instructions = config["instructions"]

    case EyeInTheSky.Agents.AgentManager.spawn_agent(%{
           "agent" => agent_name,
           "instructions" => instructions
         }) do
      {:ok, _} -> :ok
      {:error, _code, reason} -> {:error, "spawn_agent failed: #{reason}"}
      {:error, reason} -> {:error, "spawn_agent failed: #{inspect(reason)}"}
    end
  end

  defp execute("create_task", config, _ctx) do
    title = config["title"]

    case EyeInTheSky.Tasks.create_task(%{title: title}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "create_task failed: #{inspect(reason)}"}
    end
  end

  defp execute("dm_session", config, _ctx) do
    session_id = config["session_id"]
    body = config["message"]

    attrs = %{
      session_id: session_id,
      body: body,
      sender_role: "system",
      recipient_role: "user",
      direction: "outbound",
      status: "pending"
    }

    case EyeInTheSky.Messages.create_message(attrs) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, "dm_session failed: #{inspect(reason)}"}
    end
  end

  defp execute(unknown, _, _), do: {:error, "unknown action_type: #{unknown}"}

  defp render_config(config, template_ctx) do
    Enum.reduce_while(config, {:ok, %{}}, fn {k, v}, {:ok, acc} ->
      if is_binary(v) do
        case Template.render(v, template_ctx) do
          {:ok, rendered} -> {:cont, {:ok, Map.put(acc, k, rendered)}}
          {:error, _} = err -> {:halt, err}
        end
      else
        {:cont, {:ok, Map.put(acc, k, v)}}
      end
    end)
  end

  defp build_template_ctx(ctx) do
    %{
      "repository" => ctx.repository_full_name,
      "event_type" => ctx.event_type,
      "sender_login" => ctx.sender_login,
      "pr_number" => ctx.pr_number,
      "head_branch" => ctx.head_branch,
      "base_branch" => ctx.base_branch,
      "pr_title" => nil,
      "pr_url" => nil
    }
  end
end

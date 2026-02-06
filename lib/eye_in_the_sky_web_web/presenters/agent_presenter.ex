defmodule EyeInTheSkyWebWeb.Presenters.AgentPresenter do
  @moduledoc """
  Presenter utilities for Agent views: serialization and formatting helpers
  used by AgentLive.Show and related views.
  """

  @type id_str :: String.t() | nil
  @type task_map :: %{
          id: id_str,
          title: any,
          description: any,
          priority: any,
          state: any,
          tags: any,
          created_at: any
        }
  @type commit_map :: %{id: any, commit_hash: any, commit_message: any, created_at: any}
  @type log_map :: %{id: any, type: any, message: any, timestamp: any}

  # Header builders
  @spec build_header(map(), nil | map()) :: map()
  def build_header(agent, nil) do
    %{
      agent_id: agent.id,
      agent_type: "Claude Code",
      status: nil,
      session_id: nil,
      session_name: nil,
      project: agent.project_name,
      duration: nil,
      started: nil
    }
  end

  @spec build_header(map(), map()) :: map()
  def build_header(agent, session) do
    %{
      agent_id: agent.id,
      agent_type: "Claude Code",
      status: session_status(session),
      session_id: session.id,
      session_name: session.name,
      project: agent.project_name,
      duration: format_duration(session.started_at, session.ended_at),
      started: format_timestamp(session.started_at)
    }
  end

  defp session_status(session) do
    if session.ended_at && session.ended_at != "", do: "completed", else: "active"
  end

  # Serialization helpers
  @spec serialize_tasks(list(map()) | any) :: list(map())
  def serialize_tasks(tasks) when is_list(tasks) do
    Enum.map(tasks, fn task ->
      %{
        id: format_uuid(task.id),
        title: task.title,
        description: task.description,
        priority: task.priority,
        state_name: task.state && task.state.name,
        tags: task.tags && Enum.map(task.tags, &%{id: format_uuid(&1.id), name: &1.name}),
        created_at: task.created_at
      }
    end)
  end

  def serialize_tasks(_), do: []

  @spec serialize_commits(list(map()) | any) :: list(map())
  def serialize_commits(commits) when is_list(commits) do
    Enum.map(commits, fn commit ->
      %{
        id: to_string(commit.id),
        commit_hash: commit.commit_hash,
        commit_message: commit.commit_message,
        created_at: commit.created_at
      }
    end)
  end

  def serialize_commits(_), do: []

  @spec serialize_logs(list(map()) | any) :: list(map())
  def serialize_logs(logs) when is_list(logs) do
    Enum.map(logs, fn log ->
      %{
        id: to_string(log.id),
        type: log.type,
        message: log.message,
        timestamp: log.timestamp
      }
    end)
  end

  def serialize_logs(_), do: []

  @spec serialize_context(nil | map()) :: nil | map()
  def serialize_context(nil), do: nil

  def serialize_context(context) do
    %{
      context: context.context
    }
  end

  @spec serialize_notes(list(map()) | any) :: list(map())
  def serialize_notes(notes) when is_list(notes) do
    Enum.map(notes, fn note ->
      %{
        id: format_uuid(note.id),
        body: note.body,
        created_at: note.created_at
      }
    end)
  end

  def serialize_notes(_), do: []

  @spec serialize_claude_messages(list(map()) | any) :: list(map())
  def serialize_claude_messages(messages) when is_list(messages) do
    messages
    |> Enum.map(fn msg ->
      {sender_role, body, inserted_at, provider} =
        case msg do
          %{__struct__: EyeInTheSkyWeb.Messages.Message} = message ->
            {message.sender_role, message.body, message.inserted_at, message.provider}

          map when is_map(map) ->
            role = map[:role] || map["role"]
            content = map[:content] || map["content"]
            timestamp = map[:timestamp] || map["timestamp"]
            provider = map[:provider] || map["provider"] || "claude"

            ui_role =
              case role do
                "assistant" -> "agent"
                "user" -> "user"
                other -> other
              end

            {ui_role, content, timestamp, provider}
        end

      %{
        sender_role: sender_role,
        body: body,
        inserted_at: format_timestamp(inserted_at),
        provider: provider || "claude"
      }
    end)
  end

  def serialize_claude_messages(_), do: []

  @spec group_and_serialize_messages(list(map()) | any) :: list(map())
  def group_and_serialize_messages(messages) when is_list(messages) do
    messages
    |> Enum.chunk_by(&{&1.sender_role, &1.direction})
    |> Enum.map(fn group ->
      first_message = List.first(group)
      last_message = List.last(group)

      %{
        sender_role: first_message.sender_role,
        direction: first_message.direction,
        provider: first_message.provider,
        timestamp: first_message.inserted_at,
        date: NaiveDateTime.to_date(first_message.inserted_at),
        status: last_message.status,
        messages:
          Enum.map(group, fn msg ->
            %{
              id: to_string(msg.id),
              body: msg.body,
              inserted_at: msg.inserted_at
            }
          end)
      }
    end)
    |> add_date_separators()
  end

  def group_and_serialize_messages(_), do: []

  defp add_date_separators(groups) do
    groups
    |> Enum.with_index()
    |> Enum.map(fn {group, idx} ->
      prev_date = if idx > 0, do: Enum.at(groups, idx - 1).date, else: nil
      show_date = prev_date && group.date != prev_date
      Map.put(group, :show_date_separator, show_date)
    end)
  end

  # Formatting helpers
  @spec format_uuid(nil | integer | String.t()) :: String.t() | nil
  def format_uuid(nil), do: nil
  def format_uuid(id) when is_integer(id), do: to_string(id)

  def format_uuid(id) when is_binary(id) do
    if String.contains?(id, "-") do
      id
    else
      case byte_size(id) do
        32 -> format_uuid_string(id)
        36 -> id
        _ -> id
      end
    end
  end

  defp format_uuid_string(<<
         a1::binary-size(8),
         a2::binary-size(4),
         a3::binary-size(4),
         a4::binary-size(4),
         a5::binary-size(12)
       >>) do
    "#{a1}-#{a2}-#{a3}-#{a4}-#{a5}"
  end

  @spec format_timestamp(nil | String.t() | DateTime.t() | NaiveDateTime.t()) :: String.t() | nil
  def format_timestamp(nil), do: nil
  def format_timestamp(""), do: nil
  def format_timestamp(%DateTime{} = datetime), do: DateTime.to_iso8601(datetime)
  def format_timestamp(%NaiveDateTime{} = ndt), do: NaiveDateTime.to_iso8601(ndt)
  def format_timestamp(timestamp) when is_binary(timestamp), do: timestamp

  @spec format_duration(any, any) :: String.t()
  def format_duration(_started, nil), do: "Active"
  def format_duration(_started, ""), do: "Active"
  def format_duration(_started, _ended), do: "Ended"
end

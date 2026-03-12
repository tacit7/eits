defmodule EyeInTheSkyWebWeb.Api.V1.GiteaWebhookController do
  @moduledoc """
  Handles Gitea webhook events for PR automation.

  Registered at POST /api/v1/webhooks/gitea.

  Events handled:
  - pull_request (action: opened) -> spawn codex agent to review the PR
  - issue_comment (commenter: codex) -> DM the claude session that owns the PR
  - pull_request_comment (commenter: codex) -> same as above
  """

  use EyeInTheSkyWebWeb, :controller

  require Logger

  alias EyeInTheSkyWeb.Claude.AgentManager
  alias EyeInTheSkyWeb.{Messages, Sessions}

  # PR opened -> spawn codex reviewer
  def handle(conn, %{"action" => "opened", "pull_request" => pr} = params) do
    event = get_req_header(conn, "x-gitea-event") |> List.first()

    if event in ["pull_request", "pull_request_sync"] do
      pr_number = pr["number"]
      pr_title = pr["title"]
      pr_body = pr["body"] || ""
      pr_url = pr["html_url"] || ""
      head_branch = get_in(pr, ["head", "label"]) || get_in(pr, ["head", "ref"]) || "unknown"
      repo = get_in(params, ["repository", "full_name"]) || "claude/eits-web"

      Logger.info("Gitea webhook: PR ##{pr_number} opened - spawning codex reviewer")

      instructions = build_review_instructions(pr_number, pr_title, pr_body, pr_url, head_branch, repo)

      case AgentManager.create_agent(
             agent_type: "codex",
             description: "PR Review: #{pr_title} (##{pr_number})",
             instructions: instructions,
             project_path: "/Users/urielmaldonado/projects/eits/web"
           ) do
        {:ok, %{session: session}} ->
          Logger.info("Codex reviewer spawned for PR ##{pr_number}, session=#{session.uuid}")
          json(conn, %{success: true, message: "Codex reviewer spawned", session_id: session.uuid})

        {:error, reason} ->
          Logger.error("Failed to spawn codex for PR ##{pr_number}: #{inspect(reason)}")

          conn
          |> put_status(:internal_server_error)
          |> json(%{error: "Failed to spawn reviewer: #{inspect(reason)}"})
      end
    else
      json(conn, %{success: true, message: "Ignored: #{event} #{params["action"]}"})
    end
  end

  # PR comment by codex -> DM the claude session
  def handle(conn, %{"action" => "created", "comment" => comment, "issue" => issue}) do
    event = get_req_header(conn, "x-gitea-event") |> List.first()
    commenter = get_in(comment, ["user", "login"]) || ""
    pr_number = issue["number"]
    pr_body = get_in(issue, ["body"]) || ""
    comment_body = comment["body"] || ""

    is_pr = not is_nil(issue["pull_request"])
    is_codex = commenter == "codex"

    if event in ["issue_comment", "pull_request_comment"] and is_pr and is_codex do
      Logger.info("Gitea webhook: codex commented on PR ##{pr_number}")

      case extract_session_uuid(pr_body) do
        {:ok, session_uuid} ->
          dm_session(conn, session_uuid, pr_number, comment_body)

        :not_found ->
          Logger.warning("No Session-ID found in PR ##{pr_number} body; cannot notify session")
          json(conn, %{success: true, message: "No session to notify"})
      end
    else
      json(conn, %{success: true, message: "Ignored: #{event} by #{commenter}"})
    end
  end

  def handle(conn, params) do
    event = get_req_header(conn, "x-gitea-event") |> List.first()
    action = params["action"]
    Logger.debug("Gitea webhook ignored: event=#{event} action=#{action}")
    json(conn, %{success: true, message: "Ignored"})
  end

  defp build_review_instructions(pr_number, pr_title, pr_body, pr_url, head_branch, repo) do
    """
    You are a code reviewer. Review PR ##{pr_number} in the #{repo} repo.

    PR Title: #{pr_title}
    PR URL: #{pr_url}
    Branch: #{head_branch}

    PR Description:
    #{pr_body}

    Steps:
    1. Run: tea pr view #{pr_number} --login codex --repo claude/eits-web
    2. Check the diff: git fetch gitea && git diff gitea/main...gitea/#{head_branch}
    3. Review the changes for: correctness, security, code quality, missing tests, breaking changes.
    4. Post a concise review comment:
       tea comment #{pr_number} --login codex --repo claude/eits-web "your review here"
       - Start with: LGTM / NEEDS CHANGES / BLOCKED
       - List specific issues with file:line references if applicable
       - Keep it actionable and direct

    Focus on real issues. Skip praise.
    """
  end

  defp extract_session_uuid(pr_body) do
    case Regex.run(~r/Session-ID:\s*([0-9a-f-]{36})/i, pr_body, capture: :all_but_first) do
      [uuid] -> {:ok, String.trim(uuid)}
      _ -> :not_found
    end
  end

  defp dm_session(conn, session_uuid, pr_number, comment_body) do
    case Sessions.get_session_by_uuid(session_uuid) do
      {:ok, session} ->
        notification = """
        Codex posted a review comment on PR ##{pr_number}:

        #{comment_body}

        Check the PR: tea pr view #{pr_number} --login claude --repo eits-web
        """

        attrs = %{
          uuid: Ecto.UUID.generate(),
          session_id: session.id,
          body: notification,
          sender_role: "agent",
          recipient_role: "agent",
          direction: "inbound",
          status: "delivered",
          provider: "claude",
          metadata: %{
            sender_id: "gitea-webhook",
            source: "pr_review",
            pr_number: pr_number
          }
        }

        case Messages.create_message(attrs) do
          {:ok, msg} ->
            Phoenix.PubSub.broadcast(
              EyeInTheSkyWeb.PubSub,
              "session:#{session.id}",
              {:new_dm, msg}
            )

            Logger.info("DM sent to session #{session_uuid} for PR ##{pr_number} comment")
            json(conn, %{success: true, message: "Session notified"})

          {:error, cs} ->
            Logger.error("Failed to DM session #{session_uuid}: #{inspect(cs)}")

            conn
            |> put_status(:internal_server_error)
            |> json(%{error: "Failed to deliver notification"})
        end

      {:error, :not_found} ->
        Logger.warning("Session #{session_uuid} from PR ##{pr_number} not found")
        json(conn, %{success: true, message: "Session not found; notification skipped"})
    end
  end
end

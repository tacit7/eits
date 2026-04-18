defmodule EyeInTheSkyWeb.Api.V1.GiteaWebhookController do
  @moduledoc """
  Handles Gitea webhook events for PR automation.

  Registered at POST /api/v1/webhooks/gitea.

  Events handled:
  - pull_request (action: opened | synchronize) -> spawn codex agent to review the PR
  - issue_comment (commenter: codex) -> DM the claude session that owns the PR
  - pull_request_comment (commenter: codex) -> same as above
  """

  use EyeInTheSkyWeb, :controller

  action_fallback EyeInTheSkyWeb.Api.V1.FallbackController

  require Logger

  alias EyeInTheSky.Agents.AgentManager
  alias EyeInTheSky.Agents.WebhookSanitizer
  alias EyeInTheSky.Codex.ReviewInstructions
  alias EyeInTheSky.{Messages, Sessions}

  defp agent_manager,
    do: Application.get_env(:eye_in_the_sky, :agent_manager_module, AgentManager)

  defp with_verified_webhook(conn, params, fun) do
    with :ok <- verify_signature(conn),
         {:ok, repo} <- require_repo(params),
         {:ok, project_path} <- require_project_path() do
      fun.(repo, project_path)
    else
      {:error, :unauthorized} ->
        {:error, :unauthorized}

      {:error, :missing_repo} ->
        {:error, :bad_request, "Missing repository.full_name in payload"}

      {:error, :project_path_not_configured} ->
        {:error, :internal_server_error, "Server misconfigured: project_path not set"}
    end
  end

  defp with_verified_repo(conn, params, fun) do
    with :ok <- verify_signature(conn),
         {:ok, repo} <- require_repo(params) do
      fun.(repo)
    else
      {:error, :unauthorized} ->
        {:error, :unauthorized}

      {:error, :missing_repo} ->
        {:error, :bad_request, "Missing repository.full_name in payload"}
    end
  end

  # PR opened -> spawn codex reviewer
  def handle(conn, %{"action" => "opened", "pull_request" => pr} = params) do
    with_verified_webhook(conn, params, fn repo, project_path ->
      handle_pr_opened_event(conn, pr, repo, project_path)
    end)
  end

  # PR synchronized (push to open PR branch) -> spawn codex reviewer
  def handle(conn, %{"action" => "synchronize", "pull_request" => pr} = params) do
    with_verified_webhook(conn, params, fn repo, project_path ->
      handle_pr_opened_event(conn, pr, repo, project_path)
    end)
  end

  # PR comment by codex -> DM the claude session
  def handle(conn, %{"action" => "created", "comment" => comment, "issue" => issue} = params) do
    with_verified_repo(conn, params, fn repo ->
      event = get_req_header(conn, "x-gitea-event") |> List.first()
      commenter = get_in(comment, ["user", "login"]) || ""
      pr_number = issue["number"]
      pr_body = get_in(issue, ["body"]) || ""
      comment_body = comment["body"] || ""

      is_pr = not is_nil(issue["pull_request"])
      is_codex = commenter == "codex"

      if event in ["issue_comment", "pull_request_comment"] and is_pr and is_codex do
        handle_codex_comment(conn, %{
          pr_body: pr_body,
          pr_number: pr_number,
          comment_body: comment_body,
          repo: repo
        })
      else
        json(conn, %{success: true, message: "Ignored: #{event} by #{commenter}"})
      end
    end)
  end

  def handle(conn, params) do
    case verify_signature(conn) do
      :ok ->
        event = get_req_header(conn, "x-gitea-event") |> List.first()
        action = params["action"]
        Logger.debug("Gitea webhook ignored: event=#{event} action=#{action}")
        json(conn, %{success: true, message: "Ignored"})

      {:error, :unauthorized} ->
        {:error, :unauthorized}
    end
  end

  defp handle_pr_opened_event(conn, pr, repo, project_path) do
    pr_number = pr["number"]
    pr_title = WebhookSanitizer.sanitize_text(pr["title"])
    pr_body = WebhookSanitizer.sanitize_text(pr["body"])
    pr_url = pr["html_url"] || ""
    # head.ref is the plain branch name; head.label is "owner:branch"
    head_branch = WebhookSanitizer.sanitize_branch(get_in(pr, ["head", "ref"]) || "unknown")

    Logger.info("Gitea webhook: PR ##{pr_number} - spawning codex reviewer")

    pr_context = %{
      number: pr_number,
      title: pr_title,
      body: pr_body,
      url: pr_url,
      head_branch: head_branch,
      repo: repo
    }

    instructions = ReviewInstructions.build(pr_context)

    case agent_manager().create_agent(
           agent_type: "codex",
           description: "PR Review: #{pr_title} (##{pr_number})",
           instructions: instructions,
           project_path: project_path
         ) do
      {:ok, %{session: session}} ->
        Logger.info("Codex reviewer spawned for PR ##{pr_number}, session=#{session.uuid}")

        json(conn, %{
          success: true,
          message: "Codex reviewer spawned",
          session_id: session.uuid
        })

      {:error, reason} ->
        Logger.error("Failed to spawn codex for PR ##{pr_number}: #{inspect(reason)}")
        {:error, :internal_server_error, "Failed to spawn reviewer"}
    end
  end

  defp handle_codex_comment(conn, event) do
    %{pr_body: pr_body, pr_number: pr_number, comment_body: comment_body, repo: repo} = event
    Logger.info("Gitea webhook: codex commented on PR ##{pr_number}")

    case extract_session_uuid(pr_body) do
      {:ok, session_uuid} ->
        dm_session(conn, %{
          session_uuid: session_uuid,
          pr_number: pr_number,
          comment_body: comment_body,
          repo: repo
        })

      :not_found ->
        Logger.warning("No Session-ID found in PR ##{pr_number} body; cannot notify session")
        json(conn, %{success: true, message: "No session to notify"})
    end
  end

  defp verify_signature(conn) do
    secret = Application.get_env(:eye_in_the_sky, :gitea_webhook_secret, "")

    if secret == "" do
      if Application.get_env(:eye_in_the_sky, :allow_unsigned_webhooks, false) do
        Logger.warning("Gitea webhook: no secret configured, allowing unsigned (dev opt-in)")
        :ok
      else
        Logger.error("Gitea webhook: GITEA_WEBHOOK_SECRET not set — rejecting unsigned request")

        {:error, :unauthorized}
      end
    else
      sig_header = get_req_header(conn, "x-gitea-signature") |> List.first()
      body = conn.assigns[:raw_body] || ""
      expected = :crypto.mac(:hmac, :sha256, secret, body) |> Base.encode16(case: :lower)
      # Normalize: strip "sha256=" prefix if present so we compare raw hex to raw hex
      normalized_sig = (sig_header || "") |> String.replace_prefix("sha256=", "")

      if Plug.Crypto.secure_compare(expected, normalized_sig) do
        :ok
      else
        Logger.warning("Gitea webhook: invalid signature")
        {:error, :unauthorized}
      end
    end
  end

  defp require_repo(params) do
    case get_in(params, ["repository", "full_name"]) do
      nil -> {:error, :missing_repo}
      repo -> {:ok, repo}
    end
  end

  defp require_project_path do
    case Application.get_env(:eye_in_the_sky, :project_path) do
      nil ->
        Logger.error("Gitea webhook: :project_path not configured in application env")
        {:error, :project_path_not_configured}

      path ->
        {:ok, path}
    end
  end

  defp split_repo(repo) do
    case String.split(repo, "/", parts: 2) do
      [owner, name] -> {owner, name}
      _ -> {"claude", repo}
    end
  end

  defp extract_session_uuid(pr_body) do
    case Regex.run(~r/Session-ID:\s*([0-9a-f-]{36})/i, pr_body, capture: :all_but_first) do
      [uuid] -> {:ok, String.trim(uuid)}
      _ -> :not_found
    end
  end

  defp dm_session(conn, event) do
    %{session_uuid: session_uuid, pr_number: pr_number, comment_body: comment_body, repo: repo} =
      event

    {owner, repo_name} = split_repo(repo)

    case Sessions.get_session_by_uuid(session_uuid) do
      {:ok, session} ->
        notification = """
        Codex posted a review comment on PR ##{pr_number}:

        #{comment_body}

        Check the PR: tea pr view #{pr_number} --login #{owner} --repo #{owner}/#{repo_name}
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
            EyeInTheSky.Events.session_new_dm(session.id, msg)

            Logger.info("DM sent to session #{session_uuid} for PR ##{pr_number} comment")
            json(conn, %{success: true, message: "Session notified"})

          {:error, cs} ->
            Logger.error("Failed to DM session #{session_uuid}: #{inspect(cs)}")
            {:error, :internal_server_error, "Failed to deliver notification"}
        end

      {:error, :not_found} ->
        Logger.warning("Session #{session_uuid} from PR ##{pr_number} not found")
        json(conn, %{success: true, message: "Session not found; notification skipped"})
    end
  end
end

defmodule EyeInTheSkyWeb.Repo.Migrations.CreateApplicationTables do
  use Ecto.Migration

  def change do
    # ── Projects ──────────────────────────────────────────────
    create table(:projects) do
      add :name, :string
      add :slug, :string
      add :path, :string
      add :remote_url, :string
      add :git_remote, :string
      add :repo_url, :string
      add :branch, :string
      add :active, :boolean, default: true
    end

    create unique_index(:projects, [:slug])

    # ── Workflow States ───────────────────────────────────────
    create table(:workflow_states) do
      add :name, :string, null: false
      add :position, :integer
      add :color, :string
      add :updated_at, :utc_datetime
    end

    # Seed default workflow states
    execute(
      """
      INSERT INTO workflow_states (id, name, position, color) VALUES
        (1, 'To Do', 1, '#6B7280'),
        (2, 'In Progress', 2, '#3B82F6'),
        (4, 'In Review', 3, '#F59E0B'),
        (3, 'Done', 4, '#10B981')
      """,
      "DELETE FROM workflow_states WHERE id IN (1, 2, 3, 4)"
    )

    # ── Tags ──────────────────────────────────────────────────
    create table(:tags) do
      add :name, :string, null: false
      add :color, :string
    end

    create unique_index(:tags, [:name])

    # ── Agents ────────────────────────────────────────────────
    create table(:agents) do
      add :uuid, :string
      add :persona_id, :string
      add :source, :string
      add :description, :text
      add :feature_description, :text
      add :status, :string
      add :bookmarked, :boolean, default: false
      add :git_worktree_path, :string
      add :session_id, :integer
      add :project_name, :string
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :last_activity_at, :naive_datetime
      add :created_at, :text
      add :archived_at, :text
    end

    create unique_index(:agents, [:uuid])
    create index(:agents, [:project_id])
    create index(:agents, [:status])

    # ── Sessions ──────────────────────────────────────────────
    create table(:sessions) do
      add :uuid, :string
      add :agent_id, references(:agents, on_delete: :nilify_all)
      add :name, :string
      add :description, :text
      add :status, :string, default: "idle"
      add :intent, :string
      add :started_at, :text
      add :last_activity_at, :text
      add :ended_at, :text
      add :provider, :string, default: "claude"
      add :model, :string
      add :model_provider, :string
      add :model_name, :string
      add :model_version, :string
      add :archived_at, :text
      add :project_id, :integer
      add :git_worktree_path, :string
    end

    create unique_index(:sessions, [:uuid])
    create index(:sessions, [:agent_id])
    create index(:sessions, [:status])

    # ── Tasks ─────────────────────────────────────────────────
    create table(:tasks) do
      add :uuid, :string
      add :title, :string
      add :description, :text
      add :priority, :integer, default: 0
      add :due_at, :text
      add :completed_at, :text
      add :archived, :boolean, default: false
      add :agent_id, :integer
      add :state_id, references(:workflow_states, on_delete: :nilify_all)
      add :project_id, :integer
      add :created_at, :text
      add :updated_at, :text
    end

    create unique_index(:tasks, [:uuid])
    create index(:tasks, [:state_id])
    create index(:tasks, [:project_id])

    # ── Join: task_sessions ───────────────────────────────────
    create table(:task_sessions, primary_key: false) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :session_id, references(:sessions, on_delete: :delete_all), null: false
    end

    create unique_index(:task_sessions, [:task_id, :session_id])
    create index(:task_sessions, [:session_id])

    # ── Join: task_tags ───────────────────────────────────────
    create table(:task_tags, primary_key: false) do
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:task_tags, [:task_id, :tag_id])

    # ── Commits ───────────────────────────────────────────────
    create table(:commits) do
      add :session_id, references(:sessions, on_delete: :nilify_all)
      add :commit_hash, :string
      add :commit_message, :text
      add :created_at, :utc_datetime
    end

    create index(:commits, [:session_id])
    create unique_index(:commits, [:commit_hash])

    # ── Join: commit_tasks ────────────────────────────────────
    create table(:commit_tasks, primary_key: false) do
      add :commit_id, references(:commits, on_delete: :delete_all), null: false
      add :task_id, references(:tasks, on_delete: :delete_all), null: false
    end

    create unique_index(:commit_tasks, [:commit_id, :task_id])

    # ── Pull Requests ─────────────────────────────────────────
    create table(:pull_requests) do
      add :session_id, references(:sessions, on_delete: :nilify_all)
      add :pr_number, :integer
      add :pr_url, :string
      add :base_branch, :string
      add :head_branch, :string
      add :created_at, :utc_datetime
    end

    create index(:pull_requests, [:session_id])

    # ── Notes ─────────────────────────────────────────────────
    create table(:notes) do
      add :uuid, :string
      add :parent_type, :string
      add :parent_id, :string
      add :title, :string
      add :body, :text
      add :starred, :integer, default: 0
      add :created_at, :text
    end

    create index(:notes, [:parent_type, :parent_id])

    # ── Channels ──────────────────────────────────────────────
    create table(:channels) do
      add :uuid, :string
      add :name, :string
      add :description, :text
      add :channel_type, :string, default: "public"
      add :created_by_session_id, :string
      add :project_id, references(:projects, on_delete: :nilify_all)
      add :archived_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:channels, [:uuid])

    # ── Channel Members ───────────────────────────────────────
    create table(:channel_members) do
      add :uuid, :string
      add :channel_id, references(:channels, on_delete: :delete_all)
      add :agent_id, :integer
      add :session_id, :integer
      add :role, :string, default: "member"
      add :joined_at, :utc_datetime
      add :last_read_at, :utc_datetime
      add :notifications, :string, default: "all"

      timestamps(type: :utc_datetime)
    end

    create index(:channel_members, [:channel_id])
    create unique_index(:channel_members, [:channel_id, :session_id])

    # ── Messages ──────────────────────────────────────────────
    create table(:messages) do
      add :uuid, :string
      add :sender_role, :string
      add :recipient_role, :string
      add :provider, :string
      add :provider_session_id, :string
      add :direction, :string
      add :body, :text
      add :status, :string, default: "sent"
      add :metadata, :map, default: %{}
      add :thread_reply_count, :integer, default: 0
      add :last_thread_reply_at, :utc_datetime
      add :source_uuid, :string
      add :session_id, references(:sessions, on_delete: :nilify_all)
      add :channel_id, references(:channels, on_delete: :nilify_all)
      add :parent_message_id, references(:messages, on_delete: :nilify_all)
      add :project_id, references(:projects, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:messages, [:session_id])
    create index(:messages, [:channel_id])
    create unique_index(:messages, [:source_uuid])

    # ── Message Reactions ─────────────────────────────────────
    create table(:message_reactions) do
      add :uuid, :string
      add :message_id, references(:messages, on_delete: :delete_all)
      add :session_id, :integer
      add :emoji, :string

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:message_reactions, [:message_id])

    # ── File Attachments ──────────────────────────────────────
    create table(:file_attachments) do
      add :uuid, :string
      add :message_id, references(:messages, on_delete: :delete_all)
      add :filename, :string
      add :original_filename, :string
      add :content_type, :string
      add :size_bytes, :integer
      add :storage_path, :string
      add :upload_session_id, :string

      timestamps(type: :utc_datetime)
    end

    create index(:file_attachments, [:message_id])

    # ── Logs ──────────────────────────────────────────────────
    create table(:logs) do
      add :session_id, references(:sessions, on_delete: :delete_all)
      add :type, :string
      add :message, :text
      add :timestamp, :text
    end

    create index(:logs, [:session_id])

    # ── Session Logs ──────────────────────────────────────────
    create table(:session_logs) do
      add :session_id, references(:sessions, on_delete: :delete_all)
      add :level, :string
      add :category, :string
      add :message, :text
      add :details, :text
      add :created_at, :text
    end

    create index(:session_logs, [:session_id])

    # ── Prompts (subagent_prompts) ────────────────────────────
    create table(:subagent_prompts) do
      add :uuid, :string
      add :name, :string
      add :slug, :string
      add :description, :text
      add :prompt_text, :text
      add :project_id, :integer
      add :active, :boolean, default: true
      add :version, :integer, default: 1
      add :tags, :string
      add :created_by, :string
      add :created_at, :naive_datetime
      add :updated_at, :naive_datetime
    end

    create unique_index(:subagent_prompts, [:slug])
    create index(:subagent_prompts, [:project_id])

    # ── Bookmarks ─────────────────────────────────────────────
    create table(:bookmarks) do
      add :uuid, :string
      add :bookmark_type, :string
      add :bookmark_id, :string
      add :file_path, :string
      add :line_number, :integer
      add :url, :string
      add :title, :string
      add :description, :text
      add :category, :string
      add :priority, :integer, default: 0
      add :position, :integer
      add :project_id, :integer
      add :agent_id, :integer
      add :accessed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:bookmarks, [:bookmark_type])

    # ── Scheduled Jobs ────────────────────────────────────────
    create table(:scheduled_jobs) do
      add :name, :string
      add :description, :text
      add :job_type, :string
      add :origin, :string, default: "user"
      add :schedule_type, :string
      add :schedule_value, :string
      add :config, :text, default: "{}"
      add :enabled, :integer, default: 1
      add :last_run_at, :text
      add :next_run_at, :text
      add :run_count, :integer, default: 0
      add :created_at, :text
      add :updated_at, :text
    end

    # ── Job Runs ──────────────────────────────────────────────
    create table(:job_runs) do
      add :job_id, references(:scheduled_jobs, on_delete: :delete_all)
      add :status, :string
      add :started_at, :text
      add :completed_at, :text
      add :result, :text
      add :session_id, :integer
      add :created_at, :text
    end

    create index(:job_runs, [:job_id])

    # ── Session Context ───────────────────────────────────────
    create table(:session_context) do
      add :context, :text
      add :session_id, :integer
      add :agent_id, references(:agents, on_delete: :nilify_all)
      add :created_at, :text
      add :updated_at, :text
    end

    create index(:session_context, [:session_id])

    # ── Agent Context ─────────────────────────────────────────
    create table(:agent_context, primary_key: false) do
      add :agent_id, references(:agents, on_delete: :delete_all), primary_key: true
      add :session_id, references(:sessions, on_delete: :delete_all), primary_key: true
      add :project_id, references(:projects, on_delete: :delete_all), primary_key: true
      add :context, :text
      add :updated_at, :utc_datetime
    end

    # ── Meta (key-value settings) ─────────────────────────────
    create table(:meta, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text
      add :updated_at, :utc_datetime
    end

    # ── Session Metrics ───────────────────────────────────────
    create table(:session_metrics) do
      add :session_id, references(:sessions, on_delete: :delete_all)
      add :agent_id, :integer
      add :tokens_used, :integer, default: 0
      add :tokens_budget, :integer, default: 0
      add :tokens_remaining, :integer, default: 0
      add :input_tokens, :integer, default: 0
      add :output_tokens, :integer, default: 0
      add :cache_creation_input_tokens, :integer, default: 0
      add :cache_read_input_tokens, :integer, default: 0
      add :estimated_cost_usd, :float, default: 0.0
      add :model_name, :string
      add :request_count, :integer, default: 0
      add :subagent_count, :integer, default: 0
      add :notes, :text
      add :timestamp, :utc_datetime
    end

    create unique_index(:session_metrics, [:session_id])
  end
end

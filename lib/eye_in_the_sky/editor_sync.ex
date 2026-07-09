defmodule EyeInTheSky.EditorSync do
  @moduledoc """
  Opens DB-backed content (notes, tasks, prompts) in an external editor and
  syncs changes back automatically.

  Workflow:
  1. Load the current record from the DB.
  2. Write its content to a stable temp file under `{System.tmp_dir!()}/eits/{namespace}/`.
  3. Start a watcher GenServer that polls the file and syncs saves back to the DB.
  4. Launch the editor via `EyeInTheSky.Editors`.
  5. If the editor launch fails, stop the watcher and return an error.

  Only one watcher runs per record. Calling `open/3` again for the same record
  reopens the file in the editor without overwriting in-progress edits.

  Authorization is the caller's responsibility. LiveViews should only pass IDs
  for records that the user has already loaded through their normal project-scoped
  queries.
  """

  require Logger

  alias EyeInTheSky.Editors
  alias EyeInTheSky.Instance
  alias EyeInTheSky.Notes
  alias EyeInTheSky.Prompts
  alias EyeInTheSky.Tasks

  @registry EyeInTheSky.EditorSync.Registry
  @supervisor EyeInTheSky.EditorSync.Supervisor

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Open `record_id` of `type` in the editor identified by `editor_id`.

  Returns `{:ok, label}` on success where `label` is the editor's display name.
  Returns `{:error, reason}` on failure — use `format_error/1` for user-facing text.
  """
  @spec open(:note | :task | :prompt, term(), String.t()) ::
          {:ok, String.t()} | {:error, atom() | term()}
  def open(type, record_id, editor_id) do
    with {:ok, record} <- load_record(type, record_id),
         {:ok, tmp_path} <- ensure_tmp_path(type, record_id),
         {:ok, editor} <- resolve_editor(editor_id) do
      case registry_lookup(type, record_id) do
        {:ok, _pid} ->
          # Watcher already running — just reopen the existing file.
          launch_editor(editor, tmp_path)
          {:ok, editor.label}

        :not_found ->
          open_fresh(type, record_id, record, tmp_path, editor)
      end
    end
  end

  @doc "Format an error atom as a user-facing string."
  @spec format_error(atom() | term()) :: String.t()
  def format_error(:not_found), do: "Record not found"
  def format_error(:not_installed), do: "Editor not installed"
  def format_error(:unknown_editor), do: "Unknown editor"
  def format_error(:write_failed), do: "Could not write temp file"
  def format_error(_), do: "Could not open editor"

  # ---------------------------------------------------------------------------
  # Private — open fresh (no existing watcher)
  # ---------------------------------------------------------------------------

  defp open_fresh(type, record_id, record, tmp_path, editor) do
    content = content_for(type, record)

    with :ok <- write_content(tmp_path, content) do
      initial_hash = :crypto.hash(:sha256, content)

      watcher_opts = [
        type: type,
        record_id: record_id,
        tmp_path: tmp_path,
        initial_hash: initial_hash
      ]

      case DynamicSupervisor.start_child(
             @supervisor,
             {EyeInTheSky.EditorSync.Watcher, watcher_opts}
           ) do
        {:ok, pid} ->
          # Register so future opens find this watcher.
          Registry.register(@registry, {type, record_id}, pid)
          # Fire-and-forget: editor launch errors surface as OS notifications,
          # not return values, because the editor process outlives this call.
          launch_editor(editor, tmp_path)
          {:ok, editor.label}

        {:error, reason} ->
          Logger.error("[EditorSync] failed to start watcher: #{inspect(reason)}")
          {:error, :watcher_start_failed}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private — helpers
  # ---------------------------------------------------------------------------

  defp load_record(:note, id) do
    case Notes.get_note(id) do
      {:ok, r} -> {:ok, r}
      _ -> {:error, :not_found}
    end
  end

  defp load_record(:prompt, id) do
    case Prompts.get_prompt(id) do
      {:ok, r} -> {:ok, r}
      _ -> {:error, :not_found}
    end
  end

  defp load_record(:task, id) do
    case Tasks.get_task(id) do
      {:ok, r} -> {:ok, r}
      _ -> {:error, :not_found}
    end
  end

  defp ensure_tmp_path(type, id) do
    namespace = Instance.namespace()
    dir = Path.join([System.tmp_dir!(), "eits", namespace])

    with :ok <- File.mkdir_p(dir) do
      {:ok, path_for(type, id, dir)}
    else
      {:error, reason} ->
        Logger.error("[EditorSync] mkdir failed: #{inspect(reason)}")
        {:error, :write_failed}
    end
  end

  defp path_for(:note, id, dir), do: Path.join(dir, "note-#{id}.md")
  defp path_for(:task, id, dir), do: Path.join(dir, "task-#{id}.md")
  defp path_for(:prompt, id, dir), do: Path.join(dir, "prompt-#{id}.md")

  defp content_for(:note, record), do: record.body || ""
  defp content_for(:prompt, record), do: record.prompt_text || ""
  defp content_for(:task, record), do: record.description || ""

  defp write_content(path, content) do
    case File.write(path, content) do
      :ok -> :ok
      {:error, _} -> {:error, :write_failed}
    end
  end

  defp resolve_editor(editor_id) do
    dirs = build_search_dirs()

    case Editors.find(editor_id) do
      nil ->
        {:error, :unknown_editor}

      ed ->
        case resolve_binary(ed, dirs) do
          nil -> {:error, :not_installed}
          cmd -> {:ok, Map.put(ed, :cmd, cmd)}
        end
    end
  end

  # Use the same detection logic as Editors — probe extra PATH dirs first.
  defp build_search_dirs do
    home = System.get_env("HOME", "")

    extra = [
      "/opt/homebrew/bin",
      "/usr/local/bin",
      "/usr/local/sbin",
      Path.join(home, ".local/bin")
    ]

    from_path =
      case System.get_env("PATH") do
        nil -> []
        s -> String.split(s, ":")
      end

    (extra ++ from_path)
    |> Enum.uniq()
    |> Enum.filter(&File.dir?/1)
  end

  defp resolve_binary(%{bin: bin} = ed, dirs) do
    find_bin(bin, dirs) || mac_app_cmd(ed)
  end

  defp find_bin(bin, dirs) do
    Enum.find_value(dirs, fn dir ->
      p = Path.join(dir, bin)
      if File.regular?(p) && executable?(p), do: p
    end)
  end

  defp executable?(path) do
    case File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: m}} -> Bitwise.band(m, 0o111) != 0
      _ -> false
    end
  end

  defp mac_app_cmd(%{bin: bin}) do
    case :os.type() do
      {:unix, :darwin} ->
        home = System.get_env("HOME", "")
        roots = ["/Applications", Path.join(home, "Applications")]
        names = mac_app_names(bin)

        Enum.find_value(roots, fn root ->
          Enum.find_value(names, fn name ->
            bundle = Path.join(root, "#{name}.app")
            if File.exists?(bundle), do: "__open_a__:#{name}", else: nil
          end)
        end)

      _ ->
        nil
    end
  end

  defp mac_app_names("code"), do: ["Visual Studio Code"]
  defp mac_app_names("cursor"), do: ["Cursor"]
  defp mac_app_names("zed"), do: ["Zed"]
  defp mac_app_names("subl"), do: ["Sublime Text"]
  defp mac_app_names("emacs"), do: ["Emacs"]
  defp mac_app_names(_), do: []

  defp launch_editor(%{terminal: true, cmd: cmd}, path) do
    # Use .command file trick — same as Editors.launch_in_terminal/2
    quoted_cmd = shell_quote(cmd)
    quoted_path = shell_quote(path)
    script = "#!/bin/sh\n#{quoted_cmd} #{quoted_path}\n"
    tmp = Path.join(System.tmp_dir!(), "eits_sync_#{:erlang.unique_integer([:positive])}.command")

    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      File.write!(tmp, script)
      File.chmod!(tmp, 0o755)
      System.cmd("open", [tmp], stderr_to_stdout: true)
    end)

    :ok
  end

  defp launch_editor(%{cmd: "__open_a__:" <> app_name}, path) do
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd("open", ["-a", app_name, path], stderr_to_stdout: true)
    end)

    :ok
  end

  defp launch_editor(%{cmd: cmd}, path) do
    Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
      System.cmd(cmd, [path], stderr_to_stdout: true, cd: "/")
    end)

    :ok
  end

  defp shell_quote(str) do
    "'#{String.replace(str, "'", "'\\''")}'"
  end

  defp registry_lookup(type, record_id) do
    case Registry.lookup(@registry, {type, record_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> :not_found
    end
  end
end

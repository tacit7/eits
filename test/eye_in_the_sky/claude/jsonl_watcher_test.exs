defmodule EyeInTheSky.Claude.JsonlWatcherTest do
  use ExUnit.Case, async: false

  alias EyeInTheSky.Claude.{JsonlWatcher, SessionFileLocator}

  @moduletag :tmp_dir

  setup %{tmp_dir: tmp_dir} do
    # Stub HOME so SessionFileLocator builds paths under our tmp dir.
    original_home = System.get_env("HOME")
    System.put_env("HOME", tmp_dir)

    on_exit(fn ->
      if original_home, do: System.put_env("HOME", original_home), else: System.delete_env("HOME")
    end)

    project_path = Path.join(tmp_dir, "fake-project")
    File.mkdir_p!(project_path)

    # Pre-create the .claude/projects/<escaped>/ dir so the watcher can attach.
    escaped = SessionFileLocator.escape_project_path(project_path)
    watch_dir = Path.join([tmp_dir, ".claude", "projects", escaped])
    File.mkdir_p!(watch_dir)

    {:ok, project_path: project_path, watch_dir: watch_dir}
  end

  test "starts even when the JSONL file does not exist yet", %{
    project_path: project_path,
    watch_dir: watch_dir
  } do
    {:ok, pid} =
      JsonlWatcher.start_link(
        session_id: 9_999_999,
        session_uuid: "11111111-1111-1111-1111-111111111111",
        project_path: project_path
      )

    assert Process.alive?(pid)
    state = :sys.get_state(pid)
    assert state.session_id == 9_999_999
    # file_path is nil because the file didn't exist at init.
    assert state.file_path == nil
    assert state.watcher_pid != nil
    # We're watching the parent directory.
    assert is_pid(state.watcher_pid)
    assert File.dir?(watch_dir)

    JsonlWatcher.stop(pid)
  end

  test "stop/1 is idempotent on dead pids" do
    refute Process.alive?(:c.pid(0, 99_999, 0))
    assert :ok == JsonlWatcher.stop(:c.pid(0, 99_999, 0))
    assert :ok == JsonlWatcher.stop(nil)
  end
end

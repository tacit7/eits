defmodule EyeInTheSky.Editors do
  @moduledoc """
  Registry of known external editors with detection and async launch.

  `detect_installed/0` scans PATH (and macOS /Applications) to find which
  editors are actually available on this machine. The result is used to
  populate the split-button dropdown on agents, skills, and files pages.
  """

  @editors [
    %{id: "code", label: "VS Code", bin: "code"},
    %{id: "cursor", label: "Cursor", bin: "cursor"},
    %{id: "zed", label: "Zed", bin: "zed"},
    %{id: "nvim", label: "Neovim", bin: "nvim"},
    %{id: "vim", label: "Vim", bin: "vim"},
    %{id: "hx", label: "Helix", bin: "hx"},
    %{id: "subl", label: "Sublime Text", bin: "subl"},
    %{id: "emacs", label: "Emacs", bin: "emacs"},
    %{id: "nano", label: "nano", bin: "nano"}
  ]

  # Paths allowed to be opened in an external editor.
  @allowed_roots [
    Path.expand("~/.claude"),
    Path.expand("~/projects")
  ]

  @doc "All editor IDs in registry order."
  def all_ids, do: Enum.map(@editors, & &1.id)

  @doc "All editor entries (id, label, bin)."
  def all, do: @editors

  @doc """
  Returns the subset of editors whose binary is found in PATH or (macOS)
  in /Applications. List is in registry order.
  """
  def detect_installed do
    Enum.filter(@editors, &installed?/1)
  end

  @doc """
  Find an editor struct by id. Returns `nil` if unknown.
  """
  def find(id), do: Enum.find(@editors, &(&1.id == id))

  @doc """
  Open `path` in the editor identified by `editor_id`.

  Returns `{:ok, label}` and starts the launch in a supervised task so the
  LiveView is not blocked. Returns `{:error, reason}` on validation failure
  (unknown editor, editor not installed, path not allowed, path not found).
  """
  def open(editor_id, path) when is_binary(editor_id) and is_binary(path) do
    with {:editor, %{bin: bin, label: label} = _ed} <- {:editor, find(editor_id)},
         {:installed, true} <- {:installed, !!System.find_executable(bin)},
         {:allowed, true} <- {:allowed, path_allowed?(path)},
         {:exists, true} <- {:exists, File.exists?(path)} do
      Task.Supervisor.start_child(EyeInTheSky.TaskSupervisor, fn ->
        System.cmd(bin, [path], stderr_to_stdout: true, cd: "/")
      end)

      {:ok, label}
    else
      {:editor, nil} -> {:error, :unknown_editor}
      {:installed, false} -> {:error, :not_installed}
      {:allowed, false} -> {:error, :not_allowed}
      {:exists, false} -> {:error, :not_found}
    end
  end

  # --- Private ---

  defp installed?(%{bin: bin}) do
    !!System.find_executable(bin) || mac_app_exists?(bin)
  end

  # macOS: check /Applications and ~/Applications by matching the bin name
  # against known app bundle patterns. Only runs on darwin.
  defp mac_app_exists?(bin) do
    case :os.type() do
      {:unix, :darwin} ->
        home = System.get_env("HOME", "")

        roots = [
          "/Applications",
          Path.join(home, "Applications")
        ]

        app_names = mac_app_names(bin)

        Enum.any?(roots, fn root ->
          Enum.any?(app_names, fn name ->
            File.exists?(Path.join(root, "#{name}.app"))
          end)
        end)

      _ ->
        false
    end
  end

  defp mac_app_names("code"), do: ["Visual Studio Code"]
  defp mac_app_names("cursor"), do: ["Cursor"]
  defp mac_app_names("zed"), do: ["Zed"]
  defp mac_app_names("subl"), do: ["Sublime Text"]
  defp mac_app_names("emacs"), do: ["Emacs"]
  defp mac_app_names(_), do: []

  defp path_allowed?(path) do
    expanded = Path.expand(path)
    Enum.any?(@allowed_roots, &String.starts_with?(expanded, &1 <> "/"))
  end
end

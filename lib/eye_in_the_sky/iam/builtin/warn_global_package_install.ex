defmodule EyeInTheSky.IAM.Builtin.WarnGlobalPackageInstall do
  @moduledoc """
  Match (intended for `instruct` effect) Bash invocations that install
  packages globally, polluting the system environment:
    * `npm install -g` / `npm i -g`
    * `yarn global add`
    * `pnpm add -g` / `pnpm add --global`
    * `pip install` without a virtualenv indicator (no `venv/`, `.venv/`, or
      `--user` flag — heuristic only)
    * `pip3 install` (same heuristic)
    * `brew install` (modifies system Homebrew)

  Global installs can break other projects' environments and produce
  non-reproducible builds. Prefer project-local installs or lockfile-driven
  approaches.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @global_re ~r/\b(?:
    npm\s+(?:install|i)\s+(?:[^\n]*\s)?-g\b|
    yarn\s+global\s+add|
    pnpm\s+add\s+(?:[^\n]*\s)?(?:-g|--global)\b|
    pip3?\s+install\b(?!.*(?:--user|venv|\.venv))|
    brew\s+install\b
  )/xi

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@global_re, cmd)
  end

  def matches?(_, _), do: false
end

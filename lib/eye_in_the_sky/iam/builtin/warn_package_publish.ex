defmodule EyeInTheSky.IAM.Builtin.WarnPackagePublish do
  @moduledoc """
  Match (intended for `instruct` effect) Bash invocations that publish
  packages to public registries:
    * `npm publish`
    * `yarn publish`
    * `pnpm publish`
    * `mix hex.publish`
    * `cargo publish`
    * `gem push` / `gem build` + publish pattern
    * `twine upload` (Python PyPI)

  Publishing is irreversible on most registries. The agent should confirm
  the version, changelog, and auth context before proceeding.
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  @publish_re ~r/\b(?:
    npm\s+publish|
    yarn\s+publish|
    pnpm\s+publish|
    mix\s+hex\.publish|
    cargo\s+publish|
    gem\s+push|
    twine\s+upload
  )\b/xi

  @impl true
  def matches?(%Policy{} = _p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    Regex.match?(@publish_re, cmd)
  end

  def matches?(_, _), do: false
end

defmodule EyeInTheSky.IAM.Builtin.BlockRmRf do
  @moduledoc """
  Deny dangerous `rm` invocations: recursive+force targeting `/`, `$HOME`,
  `~`, or a top-level directory like `/etc`, `/var`, `/usr`.

  Supports `"allowPaths"` — a list of absolute path prefixes that escape
  this policy (e.g. scratch dirs).
  """

  @behaviour EyeInTheSky.IAM.BuiltinMatcher

  alias EyeInTheSky.IAM.Context
  alias EyeInTheSky.IAM.Policy

  # rm with at least -r and -f (any order, combined or split).
  @rm_rf_re ~r/\brm\s+(?:-[a-zA-Z]*r[a-zA-Z]*f|-[a-zA-Z]*f[a-zA-Z]*r|(?:-r\s+-f|-f\s+-r))\b/

  @dangerous_targets ~w(/ /* /etc /usr /var /bin /sbin /lib /opt /root /home /boot /System /Library ~ $HOME)

  @impl true
  def matches?(%Policy{} = p, %Context{tool: "Bash", resource_content: cmd})
      when is_binary(cmd) do
    if Regex.match?(@rm_rf_re, cmd) and targets_dangerous_path?(cmd) do
      not in_allow_paths?(cmd, p)
    else
      false
    end
  end

  def matches?(_, _), do: false

  defp targets_dangerous_path?(cmd) do
    Enum.any?(@dangerous_targets, fn t ->
      Regex.match?(~r/(?:^|\s)#{Regex.escape(t)}(?:\s|\/|$)/, cmd)
    end)
  end

  defp in_allow_paths?(cmd, %Policy{condition: %{} = cond}) do
    paths = Map.get(cond, "allowPaths") || Map.get(cond, :allowPaths) || []

    Enum.any?(paths, fn p when is_binary(p) ->
      String.contains?(cmd, p)
    end)
  end

  defp in_allow_paths?(_, _), do: false
end

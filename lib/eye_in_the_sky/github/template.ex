defmodule EyeInTheSky.Github.Template do
  @moduledoc false

  @allowed_vars ~w[
    repository event_type sender_login pr_number
    pr_title pr_url head_branch base_branch
  ]

  @doc "Render a template string against a context map. Returns {:ok, string} or {:error, reason}."
  def render(template, ctx) do
    vars = extract_vars(template)

    case Enum.find(vars, &(&1 not in @allowed_vars)) do
      nil ->
        result =
          Enum.reduce(vars, template, fn var, acc ->
            String.replace(acc, "{{#{var}}}", to_string(Map.get(ctx, var, "")))
          end)

        {:ok, result}

      unknown ->
        {:error, "unknown template variable: #{unknown}"}
    end
  end

  @doc "Validate that all {{variables}} in a template are in the allowlist."
  def validate(template) do
    case Enum.find(extract_vars(template), &(&1 not in @allowed_vars)) do
      nil -> :ok
      unknown -> {:error, "unknown template variable: #{unknown}"}
    end
  end

  defp extract_vars(template) do
    ~r/\{\{(\w+)\}\}/
    |> Regex.scan(template, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
  end
end

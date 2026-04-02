defmodule EyeInTheSkyWeb.OverviewLive.Settings.TabHelpers do
  @moduledoc false

  alias EyeInTheSky.Settings

  def is_default?(settings, key) do
    defaults = Settings.defaults()
    settings[key] == defaults[key]
  end

  def format_db_size(bytes) when bytes >= 1_048_576 do
    "#{Float.round(bytes / 1_048_576, 1)} MB"
  end

  def format_db_size(bytes) when bytes >= 1024 do
    "#{Float.round(bytes / 1024, 1)} KB"
  end

  def format_db_size(bytes), do: "#{bytes} B"

  def mask_env_var(var_name) do
    case System.get_env(var_name) do
      nil ->
        {:not_set, nil}

      val when byte_size(val) >= 4 ->
        {:set, "****" <> String.slice(val, -4, 4)}

      val ->
        {:set, String.duplicate("*", byte_size(val))}
    end
  end
end

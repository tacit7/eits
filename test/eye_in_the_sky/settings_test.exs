defmodule EyeInTheSky.SettingsTest do
  use EyeInTheSky.DataCase, async: false

  alias EyeInTheSky.Settings

  # ---- get/1 ----

  test "get returns default when key has no stored value" do
    assert Settings.get("default_model") == "sonnet"
  end

  test "get returns stored value when set" do
    Settings.put("default_model", "opus")
    assert Settings.get("default_model") == "opus"
  end

  test "get returns nil for unknown key with no default" do
    assert Settings.get("nonexistent_key_xyz") == nil
  end

  # ---- put/2 ----

  test "put stores a new value" do
    Settings.put("test_key_abc", "hello")
    assert Settings.get("test_key_abc") == "hello"
  end

  test "put overwrites an existing value" do
    Settings.put("test_overwrite", "first")
    Settings.put("test_overwrite", "second")
    assert Settings.get("test_overwrite") == "second"
  end

  test "put converts non-string values to string" do
    Settings.put("test_int", 42)
    assert Settings.get("test_int") == "42"
  end

  test "put broadcasts settings_changed on PubSub" do
    Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "settings")
    Settings.put("test_pubsub", "val")
    assert_receive {:settings_changed, "test_pubsub", "val"}
  end

  # ---- get_float/1 ----

  test "get_float returns float for valid numeric string default" do
    assert Settings.get_float("pricing_opus_input") == 15.0
  end

  test "get_float returns float for stored value" do
    Settings.put("pricing_opus_input", "20.5")
    assert Settings.get_float("pricing_opus_input") == 20.5
  end

  test "get_float returns nil for unknown key" do
    assert Settings.get_float("nonexistent_float_key") == nil
  end

  # ---- get_integer/1 ----

  test "get_integer returns integer for valid numeric string default" do
    # Default is "0" as configured in Settings.@defaults
    assert Settings.get_integer("cli_idle_timeout_ms") == 0
  end

  test "get_integer returns integer for stored value" do
    Settings.put("cli_idle_timeout_ms", "600000")
    assert Settings.get_integer("cli_idle_timeout_ms") == 600_000
  end

  test "get_integer returns nil for unknown key" do
    assert Settings.get_integer("nonexistent_int_key") == nil
  end

  # ---- get_boolean/1 ----

  test "get_boolean returns false for default false value" do
    assert Settings.get_boolean("log_claude_raw") == false
  end

  test "get_boolean returns true when stored as true" do
    Settings.put("log_claude_raw", "true")
    assert Settings.get_boolean("log_claude_raw") == true
  end

  test "get_boolean returns false for non-true strings" do
    Settings.put("log_claude_raw", "yes")
    assert Settings.get_boolean("log_claude_raw") == false
  end

  # ---- all/0 ----

  test "all returns defaults merged with stored values" do
    Settings.put("default_model", "haiku")
    result = Settings.all()
    assert result["default_model"] == "haiku"
    # Other defaults still present
    assert result["tts_voice"] == "Ava"
  end

  test "all includes custom keys not in defaults" do
    Settings.put("custom_key_all", "custom_val")
    result = Settings.all()
    assert result["custom_key_all"] == "custom_val"
  end

  # ---- put_many/1 ----

  test "put_many sets multiple keys at once" do
    Settings.put_many(%{"multi_a" => "1", "multi_b" => "2"})
    assert Settings.get("multi_a") == "1"
    assert Settings.get("multi_b") == "2"
  end

  # ---- reset/1 ----

  test "reset removes stored value and reverts to default" do
    Settings.put("default_model", "haiku")
    assert Settings.get("default_model") == "haiku"

    Settings.reset("default_model")
    assert Settings.get("default_model") == "sonnet"
  end

  test "reset broadcasts settings_changed with default value" do
    Settings.put("tts_voice", "Serena")
    Phoenix.PubSub.subscribe(EyeInTheSky.PubSub, "settings")
    Settings.reset("tts_voice")
    assert_receive {:settings_changed, "tts_voice", "Ava"}
  end

  # ---- pricing/0 ----

  test "pricing returns map with opus, sonnet, haiku keys" do
    pricing = Settings.pricing()
    assert Map.has_key?(pricing, "opus")
    assert Map.has_key?(pricing, "sonnet")
    assert Map.has_key?(pricing, "haiku")
  end

  test "pricing values are floats" do
    pricing = Settings.pricing()
    assert is_float(pricing["opus"].input) or is_number(pricing["opus"].input)
    assert pricing["opus"].input == 15.0
    assert pricing["sonnet"].output == 15.0
    assert pricing["haiku"].input == 0.8
  end

  test "pricing reflects updated settings" do
    Settings.put("pricing_opus_input", "25.0")
    pricing = Settings.pricing()
    assert pricing["opus"].input == 25.0
  end

  # ---- defaults/0 ----

  test "defaults returns the default map" do
    defaults = Settings.defaults()
    assert is_map(defaults)
    assert defaults["default_model"] == "sonnet"
    assert defaults["tts_voice"] == "Ava"
  end

  # ---- new defaults ----

  describe "defaults" do
    test "preferred_editor defaults to code" do
      Settings.reset("preferred_editor")
      assert Settings.get("preferred_editor") == "code"
    end

    test "eits_workflow_enabled defaults to true" do
      Settings.reset("eits_workflow_enabled")
      assert Settings.get_boolean("eits_workflow_enabled") == true
    end
  end
end

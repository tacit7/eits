defmodule EyeInTheSky.Settings.JsonSettingsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSky.Settings.JsonSettings

  describe "deep_merge/2" do
    test "merges leaf-level keys, right wins" do
      assert JsonSettings.deep_merge(%{"a" => 1}, %{"a" => 2}) == %{"a" => 2}
    end

    test "merges nested maps recursively (does not clobber sibling keys)" do
      left = %{"anthropic" => %{"permission_mode" => "acceptEdits", "fallback_model" => "sonnet"}}
      right = %{"anthropic" => %{"permission_mode" => "plan"}}

      assert JsonSettings.deep_merge(left, right) == %{
               "anthropic" => %{"permission_mode" => "plan", "fallback_model" => "sonnet"}
             }
    end

    test "right scalar replaces left map" do
      assert JsonSettings.deep_merge(%{"a" => %{"b" => 1}}, %{"a" => 2}) == %{"a" => 2}
    end
  end

  describe "put_setting/3" do
    test "auto-creates intermediate maps" do
      assert JsonSettings.put_setting(%{}, "anthropic.permission_mode", "plan") == %{
               "anthropic" => %{"permission_mode" => "plan"}
             }
    end

    test "preserves siblings in the same namespace" do
      start = %{"anthropic" => %{"fallback_model" => "sonnet"}}

      assert JsonSettings.put_setting(start, "anthropic.permission_mode", "plan") == %{
               "anthropic" => %{"permission_mode" => "plan", "fallback_model" => "sonnet"}
             }
    end

    test "treats nil settings as empty map" do
      assert JsonSettings.put_setting(nil, "general.thinking_enabled", true) == %{
               "general" => %{"thinking_enabled" => true}
             }
    end
  end

  describe "get_setting/2" do
    test "reads nested via dotted key" do
      m = %{"anthropic" => %{"permission_mode" => "plan"}}
      assert JsonSettings.get_setting(m, "anthropic.permission_mode") == "plan"
    end

    test "returns nil for missing path" do
      assert JsonSettings.get_setting(%{}, "anthropic.permission_mode") == nil
      assert JsonSettings.get_setting(nil, "anthropic.permission_mode") == nil
    end
  end

  describe "delete_setting/2" do
    test "removes key and prunes empty parent map" do
      m = %{"anthropic" => %{"permission_mode" => "plan"}}
      assert JsonSettings.delete_setting(m, "anthropic.permission_mode") == %{}
    end

    test "does not prune parents that still have siblings" do
      m = %{"anthropic" => %{"permission_mode" => "plan", "fallback_model" => "sonnet"}}

      assert JsonSettings.delete_setting(m, "anthropic.permission_mode") == %{
               "anthropic" => %{"fallback_model" => "sonnet"}
             }
    end

    test "deleting an absent key is a no-op (and still prunes)" do
      m = %{"anthropic" => %{"fallback_model" => "sonnet"}}
      assert JsonSettings.delete_setting(m, "general.thinking_enabled") == m
    end
  end

  describe "reset_namespace/2" do
    test "drops the whole namespace" do
      m = %{"anthropic" => %{"permission_mode" => "plan"}, "general" => %{"thinking_enabled" => true}}

      assert JsonSettings.reset_namespace(m, "anthropic") == %{
               "general" => %{"thinking_enabled" => true}
             }
    end
  end

  describe "effective_settings/2" do
    test "layers app defaults < agent < session" do
      agent = %{"anthropic" => %{"fallback_model" => "haiku"}}
      session = %{"anthropic" => %{"permission_mode" => "plan"}}

      effective = JsonSettings.effective_settings(agent, session)

      # session overrides default
      assert effective["anthropic"]["permission_mode"] == "plan"
      # agent override is preserved
      assert effective["anthropic"]["fallback_model"] == "haiku"
      # untouched default still present
      assert effective["general"]["show_live_stream"] == true
    end

    test "deleting a session override falls back to agent value" do
      agent = %{"anthropic" => %{"permission_mode" => "plan"}}
      session_after_delete = JsonSettings.delete_setting(%{"anthropic" => %{"permission_mode" => "default"}}, "anthropic.permission_mode")

      effective = JsonSettings.effective_settings(agent, session_after_delete)
      assert effective["anthropic"]["permission_mode"] == "plan"
    end

    test "tolerates nil inputs" do
      effective = JsonSettings.effective_settings(nil, nil)
      assert is_map(effective)
      assert effective["general"]["thinking_enabled"] == false
    end
  end

  describe "coerce_value/3" do
    test "rejects unknown key" do
      assert {:error, :unknown_setting_key} = JsonSettings.coerce_value("x", "totally.fake", :session)
    end

    test "rejects key in disallowed scope" do
      # from_pr is only declared for :session
      assert {:error, :scope_not_allowed} =
               JsonSettings.coerce_value("owner/repo#1", "anthropic.from_pr", :agent)
    end

    test "boolean coercion" do
      assert {:ok, true} = JsonSettings.coerce_value(true, "general.thinking_enabled", :session)
      assert {:ok, false} = JsonSettings.coerce_value("false", "general.thinking_enabled", :session)
      assert {:error, :type_mismatch} = JsonSettings.coerce_value("yep", "general.thinking_enabled", :session)
    end

    test "float strict parsing rejects partial parses" do
      assert {:ok, 50.0} = JsonSettings.coerce_value("50", "general.max_budget_usd", :session)
      assert {:ok, 12.5} = JsonSettings.coerce_value("12.5", "general.max_budget_usd", :session)
      assert {:error, :invalid_float} = JsonSettings.coerce_value("50abc", "general.max_budget_usd", :session)
    end

    test "empty string coerces to nil for *_or_nil types" do
      assert {:ok, nil} = JsonSettings.coerce_value("", "general.max_budget_usd", :session)
      assert {:ok, nil} = JsonSettings.coerce_value("", "anthropic.from_pr", :session)
    end

    test "enum validates membership" do
      assert {:ok, "plan"} = JsonSettings.coerce_value("plan", "anthropic.permission_mode", :session)
      assert {:error, :invalid_enum_value} = JsonSettings.coerce_value("yolo", "anthropic.permission_mode", :session)
    end

    test "enum_or_nil collapses empty string to nil" do
      assert {:ok, nil} = JsonSettings.coerce_value("", "anthropic.fallback_model", :session)
      assert {:ok, "haiku"} = JsonSettings.coerce_value("haiku", "anthropic.fallback_model", :session)
      assert {:error, :invalid_enum_value} = JsonSettings.coerce_value("gpt-4", "anthropic.fallback_model", :session)
    end

    test "integer strict parsing" do
      assert {:ok, 5} = JsonSettings.coerce_value("5", "anthropic.max_turns", :session)
      assert {:error, :invalid_integer} = JsonSettings.coerce_value("5abc", "anthropic.max_turns", :session)
    end
  end
end

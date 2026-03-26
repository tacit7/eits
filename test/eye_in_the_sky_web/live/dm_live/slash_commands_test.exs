defmodule EyeInTheSkyWeb.DmLive.SlashCommandsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.DmLive.SlashCommands

  describe "parse/1" do
    test "plain text passes through unchanged" do
      {server, cli, body} = SlashCommands.parse("hello world")
      assert server == []
      assert cli == []
      assert body == "hello world"
    end

    test "server command /rename extracts name" do
      {server, cli, body} = SlashCommands.parse("/rename My Session")
      assert server == [{:rename, "My Session"}]
      assert cli == []
      assert body == ""
    end

    test "server command /model extracts model name" do
      {server, _cli, body} = SlashCommands.parse("/model sonnet")
      assert server == [{:model, "sonnet"}]
      assert body == ""
    end

    test "server command /effort extracts level" do
      {server, _cli, body} = SlashCommands.parse("/effort high")
      assert server == [{:effort, "high"}]
      assert body == ""
    end

    test "cli flag /plan produces permission_mode" do
      {_server, cli, body} = SlashCommands.parse("/plan")
      assert cli == [{:permission_mode, "plan"}]
      assert body == ""
    end

    test "cli flag /sandbox produces sandbox: true" do
      {_server, cli, _body} = SlashCommands.parse("/sandbox")
      assert cli == [{:sandbox, true}]
    end

    test "/no-sandbox is consumed (does not leak into body)" do
      {_server, cli, body} = SlashCommands.parse("/no-sandbox")
      assert body == ""
      # consumed as a no-op cli flag
      assert cli == [{:_noop, true}]
    end

    test "cli flag /chrome and /no-chrome" do
      {_, cli, _} = SlashCommands.parse("/chrome")
      assert cli == [{:chrome, true}]

      {_, cli, _} = SlashCommands.parse("/no-chrome")
      assert cli == [{:chrome, false}]
    end

    test "cli flag /mcp with file path" do
      {_, cli, _} = SlashCommands.parse("/mcp ./my-mcp.json")
      assert cli == [{:mcp_config, "./my-mcp.json"}]
    end

    test "cli flag /add-dir with path" do
      {_, cli, _} = SlashCommands.parse("/add-dir ../lib")
      assert cli == [{:add_dir, "../lib"}]
    end

    test "cli flag /plugin with path" do
      {_, cli, _} = SlashCommands.parse("/plugin ./my-plugins")
      assert cli == [{:plugin_dir, "./my-plugins"}]
    end

    test "cli flag /config with file" do
      {_, cli, _} = SlashCommands.parse("/config ./settings.json")
      assert cli == [{:settings_file, "./settings.json"}]
    end

    test "cli flag /agents with name" do
      {_, cli, _} = SlashCommands.parse("/agents reviewer")
      assert cli == [{:agent, "reviewer"}]
    end

    test "cli flag /permissions with mode" do
      {_, cli, _} = SlashCommands.parse("/permissions acceptEdits")
      assert cli == [{:permission_mode, "acceptEdits"}]
    end

    test "cli flag /max-turns with valid integer" do
      {_, cli, _} = SlashCommands.parse("/max-turns 10")
      assert cli == [{:max_turns, 10}]
    end

    test "cli flag /max-turns with invalid value is unknown" do
      {_, cli, body} = SlashCommands.parse("/max-turns abc")
      assert cli == []
      assert body == "/max-turns abc"
    end

    test "mixed: slash command + regular text" do
      input = "/model opus\nTell me about Elixir"
      {server, cli, body} = SlashCommands.parse(input)
      assert server == [{:model, "opus"}]
      assert cli == []
      assert body == "Tell me about Elixir"
    end

    test "multiple slash commands in one message" do
      input = "/model sonnet\n/effort high\n/plan\nDo the thing"
      {server, cli, body} = SlashCommands.parse(input)
      assert server == [{:model, "sonnet"}, {:effort, "high"}]
      assert cli == [{:permission_mode, "plan"}]
      assert body == "Do the thing"
    end

    test "unknown commands stay in body" do
      {_, _, body} = SlashCommands.parse("/foobar something")
      assert body == "/foobar something"
    end

    test "slash-like text mid-line is not a command" do
      {_, _, body} = SlashCommands.parse("use /model sonnet for this")
      assert body == "use /model sonnet for this"
    end
  end

  describe "route/2" do
    test "rename returns server tuple" do
      assert SlashCommands.route("rename", "My Name") == {:server, {:rename, "My Name"}}
    end

    test "plan returns cli tuple" do
      assert SlashCommands.route("plan", nil) == {:cli, {:permission_mode, "plan"}}
    end

    test "unknown command returns :unknown" do
      assert SlashCommands.route("bogus", nil) == :unknown
    end

    test "rename without arg returns :unknown" do
      assert SlashCommands.route("rename", nil) == :unknown
    end
  end
end

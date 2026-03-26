defmodule EyeInTheSkyWeb.DmLive.SlashCommandsTest do
  use ExUnit.Case, async: true

  alias EyeInTheSkyWeb.DmLive.SlashCommands

  describe "parse/1" do
    test "plain text passes through unchanged" do
      {server, session, body} = SlashCommands.parse("hello world")
      assert server == []
      assert session == []
      assert body == "hello world"
    end

    test "server command /rename extracts name" do
      {server, session, body} = SlashCommands.parse("/rename My Session")
      assert server == [{:rename, "My Session"}]
      assert session == []
      assert body == ""
    end

    test "server command /model extracts model name" do
      {server, _session, body} = SlashCommands.parse("/model sonnet")
      assert server == [{:model, "sonnet"}]
      assert body == ""
    end

    test "server command /effort extracts level" do
      {server, _session, body} = SlashCommands.parse("/effort high")
      assert server == [{:effort, "high"}]
      assert body == ""
    end

    test "session flag /plan produces permission_mode" do
      {_server, session, body} = SlashCommands.parse("/plan")
      assert session == [{:permission_mode, "plan"}]
      assert body == ""
    end

    test "session flag /sandbox produces sandbox: true" do
      {_server, session, _body} = SlashCommands.parse("/sandbox")
      assert session == [{:sandbox, true}]
    end

    test "/no-sandbox clears sandbox toggle" do
      {_server, session, body} = SlashCommands.parse("/no-sandbox")
      assert body == ""
      assert session == [{:_clear, :sandbox}]
    end

    test "session flag /chrome and /no-chrome" do
      {_, session, _} = SlashCommands.parse("/chrome")
      assert session == [{:chrome, true}]

      {_, session, _} = SlashCommands.parse("/no-chrome")
      assert session == [{:chrome, false}]
    end

    test "session flag /mcp with file path" do
      {_, session, _} = SlashCommands.parse("/mcp ./my-mcp.json")
      assert session == [{:mcp_config, "./my-mcp.json"}]
    end

    test "session flag /add-dir with path" do
      {_, session, _} = SlashCommands.parse("/add-dir ../lib")
      assert session == [{:add_dir, "../lib"}]
    end

    test "session flag /plugin with path" do
      {_, session, _} = SlashCommands.parse("/plugin ./my-plugins")
      assert session == [{:plugin_dir, "./my-plugins"}]
    end

    test "session flag /config with file" do
      {_, session, _} = SlashCommands.parse("/config ./settings.json")
      assert session == [{:settings_file, "./settings.json"}]
    end

    test "session flag /agents with name" do
      {_, session, _} = SlashCommands.parse("/agents reviewer")
      assert session == [{:agent, "reviewer"}]
    end

    test "session flag /permissions with mode" do
      {_, session, _} = SlashCommands.parse("/permissions acceptEdits")
      assert session == [{:permission_mode, "acceptEdits"}]
    end

    test "session flag /max-turns with valid integer" do
      {_, session, _} = SlashCommands.parse("/max-turns 10")
      assert session == [{:max_turns, 10}]
    end

    test "session flag /max-turns with invalid value is unknown" do
      {_, session, body} = SlashCommands.parse("/max-turns abc")
      assert session == []
      assert body == "/max-turns abc"
    end

    test "mixed: slash command + regular text" do
      input = "/model opus\nTell me about Elixir"
      {server, session, body} = SlashCommands.parse(input)
      assert server == [{:model, "opus"}]
      assert session == []
      assert body == "Tell me about Elixir"
    end

    test "multiple slash commands in one message" do
      input = "/model sonnet\n/effort high\n/plan\nDo the thing"
      {server, session, body} = SlashCommands.parse(input)
      assert server == [{:model, "sonnet"}, {:effort, "high"}]
      assert session == [{:permission_mode, "plan"}]
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

    test "/chrome alone: session flag set, body empty" do
      {_server, session, body} = SlashCommands.parse("/chrome")
      assert session == [{:chrome, true}]
      assert body == ""
    end

    test "/no-sandbox is consumed, not leaked" do
      {_server, session, body} = SlashCommands.parse("/no-sandbox\nhello")
      assert body == "hello"
      assert session == [{:_clear, :sandbox}]
    end
  end

  describe "route/2" do
    test "rename returns server tuple" do
      assert SlashCommands.route("rename", "My Name") == {:server, {:rename, "My Name"}}
    end

    test "plan returns session tuple" do
      assert SlashCommands.route("plan", nil) == {:session, {:permission_mode, "plan"}}
    end

    test "chrome returns session tuple" do
      assert SlashCommands.route("chrome", nil) == {:session, {:chrome, true}}
    end

    test "unknown command returns :unknown" do
      assert SlashCommands.route("bogus", nil) == :unknown
    end

    test "rename without arg returns :unknown" do
      assert SlashCommands.route("rename", nil) == :unknown
    end
  end
end

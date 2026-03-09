defmodule EyeInTheSkyWeb.MCP.Server do
  @moduledoc """
  MCP Server for Eye in the Sky.

  Exposes the same tool surface as the Go core MCP server,
  backed by existing Phoenix contexts. Served over Streamable HTTP
  at POST /mcp.
  """

  use Anubis.Server,
    name: "eits",
    version: "1.0.0",
    capabilities: [:tools],
    protocol_versions: ["2024-11-05", "2025-03-26", "2025-06-18"]

  # Phase 1 — Core DB tools
  component(EyeInTheSkyWeb.MCP.Tools.Session, name: "i-session")
  component(EyeInTheSkyWeb.MCP.Tools.SessionInfo, name: "i-session-info")
  component(EyeInTheSkyWeb.MCP.Tools.EndSession, name: "i-end-session")
  component(EyeInTheSkyWeb.MCP.Tools.Commits, name: "i-commits")
  component(EyeInTheSkyWeb.MCP.Tools.NoteAdd, name: "i-note-add")
  component(EyeInTheSkyWeb.MCP.Tools.NoteGet, name: "i-note-get")
  component(EyeInTheSkyWeb.MCP.Tools.NoteSearch, name: "i-note-search")
  component(EyeInTheSkyWeb.MCP.Tools.SessionSearch, name: "i-session-search")
  component(EyeInTheSkyWeb.MCP.Tools.SaveSessionContext, name: "i-save-session-context")
  component(EyeInTheSkyWeb.MCP.Tools.LoadSessionContext, name: "i-load-session-context")
  component(EyeInTheSkyWeb.MCP.Tools.Todo, name: "i-todo")
  component(EyeInTheSkyWeb.MCP.Tools.PromptGet, name: "i-prompt-get")
  component(EyeInTheSkyWeb.MCP.Tools.ProjectAdd, name: "i-project-add")

  # Phase 2 — System tools
  component(EyeInTheSkyWeb.MCP.Tools.Speak, name: "i-speak")
  component(EyeInTheSkyWeb.MCP.Tools.Window, name: "i-window")

  # Phase 3 — Messaging tools
  component(EyeInTheSkyWeb.MCP.Tools.ChatSend, name: "i-chat-send")
  component(EyeInTheSkyWeb.MCP.Tools.Dm, name: "i-dm")
  component(EyeInTheSkyWeb.MCP.Tools.ChatChannelList, name: "i-chat-channel-list")

  # Phase 4 — Agent spawning
  component(EyeInTheSkyWeb.MCP.Tools.SpawnAgent, name: "i-spawn-agent")
end

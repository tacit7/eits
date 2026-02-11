# Load schema from Go core into test database
# Since the Go MCP server owns the schema, we need to initialize it for tests
unless EyeInTheSkyWeb.SchemaLoader.schema_loaded?() do
  IO.puts("\n=== Loading schema into test database ===\n")
  EyeInTheSkyWeb.SchemaLoader.load_schema!()
  IO.puts("✓ Schema loaded successfully\n")
end

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(EyeInTheSkyWeb.Repo, :manual)

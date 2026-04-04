# Load schema from Go core into test database
# Since the Go MCP server owns the schema, we need to initialize it for tests
unless EyeInTheSky.SchemaLoader.schema_loaded?() do
  IO.puts("\n=== Loading schema into test database ===\n")
  EyeInTheSky.SchemaLoader.load_schema!()
  IO.puts("✓ Schema loaded successfully\n")
end

ExUnit.start(exclude: [:sdk_e2e, :host_dependent])
Ecto.Adapters.SQL.Sandbox.mode(EyeInTheSky.Repo, :manual)

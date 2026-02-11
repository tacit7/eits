# Integration Tests

Real end-to-end tests with actual Claude CLI processes (NO MOCKS).

## Test Database

Configured in `config/test.exs`:
```elixir
config :eye_in_the_sky_web, EyeInTheSkyWeb.Repo,
  database: Path.expand("../eye_in_the_sky_web_test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox
```

- **Location**: `config/eye_in_the_sky_web_test.db`
- **Isolation**: Ecto.Adapters.SQL.Sandbox for transaction rollback between tests
- **Schema**: Created automatically by the test application startup

## Real E2E Test Flow

### Setup Phase
1. Override `cli_module` config to use real `EyeInTheSkyWeb.Claude.CLI`
2. Create test project in DB with real filesystem path
3. Create agent and session records
4. Create channel for communication

### Test Execution
1. **Spawn real Claude CLI**:
   ```elixir
   SessionManager.resume_session(
     session.uuid,
     "prompt here",
     model: "haiku",
     project_path: "/tmp/test-project"
   )
   ```
   This spawns: `claude --session test-session-uuid -p /tmp/test-project`

2. **Simulate @mention in web UI**:
   ```elixir
   view |> form("#dm-form", %{
     "target_id" => session.id,
     "body" => "@agent message here"
   })
   |> render_submit()
   ```

3. **Wait for real Claude response** via PubSub

4. **Verify message in database**

### Cleanup
- Cancel session (kills real Claude process)
- Sandbox rolls back all DB changes

## Running Integration Tests

### All unit tests (with mocks - fast):
```bash
mix test
```

### Real E2E tests (spawns actual Claude - slow):
```bash
# Run all integration tests
mix test --only integration

# Run specific test
mix test test/integration/real_e2e_test.exs:26

# Run with logs
mix test --only integration --trace
```

### Skip integration tests:
Integration tests are tagged with `@tag :skip` by default.

To enable them, remove the skip tag or run:
```bash
mix test --include skip --only integration
```

## Requirements for Integration Tests

1. **Claude CLI in PATH**:
   ```bash
   which claude
   # Should return: /usr/local/bin/claude or similar
   ```

2. **EITS MCP server running** (for i-start-session, etc.):
   ```bash
   # Check if NATS is running
   ps aux | grep nats-server

   # Check if MCP server is configured in ~/.claude/claude_desktop_config.json
   ```

3. **Test project directory writable**:
   ```bash
   ls -la /tmp/eits-e2e-test-project
   ```

## Why Integration Tests Are Skipped by Default

- **Slow**: Real Claude CLI takes 5-10 seconds per request
- **External dependency**: Requires claude binary and API access
- **Cost**: Makes real API calls to Anthropic
- **Environment**: Needs MCP server configuration

Use these for:
- Pre-release validation
- Critical bug investigation
- Verifying real Claude integration after major changes

## Test Database vs Production Database

| | Test | Production |
|---|---|---|
| **Path** | `config/eye_in_the_sky_web_test.db` | `~/.config/eye-in-the-sky/eits.db` |
| **Isolation** | SQL Sandbox (rollback) | Persistent |
| **CLI Module** | MockCLI (default) or real CLI (integration) | Real CLI always |
| **Migrations** | Auto-applied on start | Go MCP server owns schema |

## Debugging Failed Integration Tests

### Check if Claude CLI works:
```bash
echo "test" | claude --session test-123 -p /tmp
```

### Check SessionManager state:
```elixir
# In test
registry = EyeInTheSkyWeb.Claude.Registry
workers = Registry.lookup(registry, {:session, session.uuid})
IO.inspect(workers, label: "Active workers")
```

### Check database state:
```bash
sqlite3 config/eye_in_the_sky_web_test.db "SELECT * FROM sessions ORDER BY id DESC LIMIT 5;"
```

### Enable verbose logging:
```elixir
# In config/test.exs
config :logger, level: :debug
```

## Future Improvements

1. **Docker environment** for reproducible integration tests
2. **Record/replay** mode to cache Claude responses
3. **Parallel execution** with unique project directories
4. **CI/CD integration** with API key management
5. **Performance benchmarks** for SessionManager under load

# SessionManager Test Suite Summary

## Overview

Comprehensive test suite for SessionManager and SessionWorker coordination logic, covering deduplication, message queueing, status broadcasting, and error handling.

## Test Coverage

### 1. Basic Worker Spawning (3 tests)
- ✅ Spawns new SessionWorker under DynamicSupervisor
- ✅ Returns session_ref for tracking
- ✅ Broadcasts :working status on start

### 2. Deduplication Logic (3 tests)
- ✅ Queues message when worker already exists
- ✅ Spawns new worker when existing worker is dead
- ✅ Returns error when spawning worker fails

### 3. Message Queue Processing (4 tests)
- ✅ Processes queued messages after CLI exit
- ✅ Worker goes idle after processing empty queue
- ✅ Rejects messages when queue is full (max 5)
- ✅ Processes message immediately when worker is idle

### 4. Status Broadcasting (3 tests)
- ✅ Broadcasts :working when processing starts
- ✅ Broadcasts :idle after CLI exits with empty queue
- ✅ Broadcasts :queue_full when queue limit reached

### 5. Session Cancellation (3 tests)
- ✅ Stops worker and broadcasts idle
- ✅ Returns error when session not found
- ✅ Handles already-dead worker gracefully

### 6. List Sessions (4 tests)
- ✅ Returns info for all active workers
- ✅ Includes queue_depth and processing status
- ✅ Returns empty list when no sessions active
- ✅ Excludes dead workers from list

### 7. Continue Session (2 tests)
- ✅ Spawns new worker for continue operation
- ✅ Does not deduplicate continue requests

### 8. Multiple Sessions Isolation (2 tests)
- ✅ Sessions operate independently
- ✅ Queues are independent between sessions

### 9. Worker Restart Behavior (2 tests)
- ✅ Worker does not restart after normal exit (temporary restart)
- ✅ Worker goes idle after normal exit

### 10. Edge Cases (2 tests)
- ✅ Handles concurrent resume attempts
- ✅ Handles worker crash gracefully

## Test Infrastructure

### MockCLI (`test/support/mock_cli.ex`)
Test double for CLI module that:
- Spawns mock "port" processes (PIDs) instead of real ports
- Supports controllable output injection via `{:send_output, line}`
- Supports controlled exit via `{:exit, code}`
- Can simulate hanging processes via `:hang` message
- Implements all CLI interface methods (spawn_new_session, continue_session, resume_session, cancel)

### SessionManagerCase (`test/support/session_manager_case.ex`)
Test case template providing:
- **Helpers:**
  - `await_worker/2` - Wait for worker registration
  - `get_mock_port/1` - Extract mock port PID from worker state
  - `send_mock_output/2` - Send output to mock port
  - `send_mock_exit/2` - Trigger mock port exit
  - `make_port_hang/1` - Make mock port hang forever
  - `subscribe_session_status/1` - Subscribe to PubSub status broadcasts
  - `assert_status_broadcast/3` - Assert status broadcast received
- **Setup:**
  - Injects MockCLI module via application config
  - Cleans up after tests

### Test Setup
Each test gets isolated:
- Phoenix.PubSub instance
- Registry for worker lookups
- DynamicSupervisor for worker processes
- SessionManager coordinator

All processes are killed and restarted between tests to ensure isolation.

## Configuration Changes

### `lib/eye_in_the_sky_web/claude/session_worker.ex`
- Added `@cli_module` compile-time injection point
- Replaced hardcoded `CLI` calls with `@cli_module` calls
- Fixed `terminate/2` to handle mock ports (PIDs) vs real ports

### `config/test.exs`
- Added `cli_module: EyeInTheSkyWeb.Claude.MockCLI`

## Test Results

```
28 tests, 0 failures
```

Tests are stable across multiple random seeds (verified with seeds: 0, 1, 42, 100, 999).

## Key Behaviors Verified

1. **Deduplication works** - Concurrent resume attempts to same session queue messages instead of spawning duplicate workers
2. **Queue processing is reliable** - Queued messages are processed after CLI exits
3. **Queue overflow handling** - Drops messages and broadcasts :queue_full when queue reaches max (5)
4. **Status visibility** - PubSub broadcasts keep UI in sync with worker state
5. **Cancellation is safe** - Can cancel sessions and resources are cleaned up properly
6. **Crash recovery** - System can spawn new workers after crashes
7. **Session isolation** - Multiple sessions don't interfere with each other

## Production Issues Addressed

This test suite specifically catches the issues seen in production:

1. ✅ **Duplicate workers** - Tests verify deduplication logic prevents multiple workers for same session
2. ✅ **Stuck queues** - Tests verify queue_full broadcast when messages pile up
3. ✅ **Lost messages** - Tests verify queued messages are processed after CLI exits
4. ✅ **No visibility** - Tests verify all status broadcasts (:working, :idle, :queue_full)

## Running Tests

```bash
# Run full suite
mix test test/eye_in_the_sky_web/claude/session_manager_test.exs

# Run with specific seed for reproducibility
mix test test/eye_in_the_sky_web/claude/session_manager_test.exs --seed 0

# Run specific test
mix test test/eye_in_the_sky_web/claude/session_manager_test.exs:110
```

## Future Improvements

1. Add test for idle timeout (currently set to 60 seconds, not tested)
2. Add test for output parsing and message recording
3. Add test for NATS publishing integration
4. Consider testing with real port timeouts (would be slow)
5. Add property-based tests for concurrent operations

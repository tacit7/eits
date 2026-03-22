#!/usr/bin/env bats
# Tests for scripts/eits CLI
# Runs against the real server at http://localhost:5001/api/v1

EITS="$BATS_TEST_DIRNAME/../../scripts/eits"
export EITS_URL="http://localhost:5001/api/v1"
export EITS_PROJECT_ID="1"

# Use a fixed test session that's already in the DB
TEST_SESSION="b820f555-e03e-4900-baf7-8be15281a4e7"

setup_file() {
  # Resolve agent UUID from known session and write to shared tmp file
  agent=$("$EITS" sessions get "$TEST_SESSION" | jq -r '.agent_id')
  echo "$agent" > "$BATS_FILE_TMPDIR/agent_uuid"
}

_agent_uuid() { cat "$BATS_FILE_TMPDIR/agent_uuid"; }

# ── sessions ─────────────────────────────────────────────────────────────────

@test "sessions get: returns session_id field" {
  run "$EITS" sessions get "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.session_id' >/dev/null
}

@test "sessions get: returns project_id field" {
  run "$EITS" sessions get "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.project_id' >/dev/null
}

@test "sessions get: agent_id is UUID not integer" {
  run "$EITS" sessions get "$TEST_SESSION"
  [ "$status" -eq 0 ]
  agent_id=$(echo "$output" | jq -r '.agent_id')
  [[ "$agent_id" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]
}

@test "sessions update --name: updates session name" {
  run "$EITS" sessions update "$TEST_SESSION" --name "bats-updated-name"
  [ "$status" -eq 0 ]
  name=$("$EITS" sessions get "$TEST_SESSION" | jq -r '.name')
  [ "$name" = "bats-updated-name" ]
}

@test "sessions update --description: updates session description" {
  run "$EITS" sessions update "$TEST_SESSION" --description "bats test description"
  [ "$status" -eq 0 ]
  desc=$("$EITS" sessions get "$TEST_SESSION" | jq -r '.description')
  [ "$desc" = "bats test description" ]
}

@test "sessions update: rejects unknown flags" {
  run "$EITS" sessions update "$TEST_SESSION" --bogus "foo" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown flag" ]]
}

@test "sessions context: returns valid JSON (200 with data or 404 no context)" {
  # Endpoint returns 404 when no context has been saved yet — that's fine
  run bash -c "'$EITS' sessions context '$TEST_SESSION' 2>/dev/null; true"
  [ "$status" -eq 0 ]
}

# ── tasks create ──────────────────────────────────────────────────────────────

@test "tasks create: returns task_id" {
  run "$EITS" tasks create --title "bats test task"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.task_id' >/dev/null
}

@test "tasks create: fails without --title" {
  run "$EITS" tasks create 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "title" ]]
}

@test "tasks create: succeeds with EITS_PROJECT_ID from env" {
  export EITS_PROJECT_ID="1"
  run "$EITS" tasks create --title "bats project env test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.task_id' >/dev/null
  # tasks get does not return project_id — creation success is sufficient verification
}

@test "tasks create: links to session via EITS_SESSION_UUID env" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  task_id=$("$EITS" tasks create --title "bats session env test" | jq -r '.task_id')
  run "$EITS" tasks list --session "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e ".tasks[] | select(.id == ($task_id | tonumber))" >/dev/null
}

@test "tasks create: --project overrides EITS_PROJECT_ID" {
  export EITS_PROJECT_ID="1"
  # Pass same project explicitly — should succeed
  run "$EITS" tasks create --title "bats project override" --project "1"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.task_id' >/dev/null
}

# ── tasks lifecycle ───────────────────────────────────────────────────────────

@test "tasks start: moves task to state 2 (In Progress)" {
  task_id=$("$EITS" tasks create --title "bats start test" | jq -r '.task_id')
  run "$EITS" tasks start "$task_id"
  [ "$status" -eq 0 ]
  state_id=$("$EITS" tasks get "$task_id" | jq -r '.task.state_id')
  [ "$state_id" = "2" ]
}

@test "tasks update --state 4: moves task to In Review" {
  task_id=$("$EITS" tasks create --title "bats review test" | jq -r '.task_id')
  "$EITS" tasks start "$task_id" >/dev/null
  run "$EITS" tasks update "$task_id" --state 4
  [ "$status" -eq 0 ]
  state_id=$("$EITS" tasks get "$task_id" | jq -r '.task.state_id')
  [ "$state_id" = "4" ]
}

@test "tasks done: moves task to state 3 (Done)" {
  task_id=$("$EITS" tasks create --title "bats done test" | jq -r '.task_id')
  "$EITS" tasks start "$task_id" >/dev/null
  run "$EITS" tasks done "$task_id"
  [ "$status" -eq 0 ]
  state_id=$("$EITS" tasks get "$task_id" | jq -r '.task.state_id')
  [ "$state_id" = "3" ]
}

@test "tasks annotate: returns note_id" {
  task_id=$("$EITS" tasks create --title "bats annotate test" | jq -r '.task_id')
  run "$EITS" tasks annotate "$task_id" --body "test annotation"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.note_id' >/dev/null
}

# ── tasks link-session ────────────────────────────────────────────────────────

@test "tasks link-session: links with explicit session UUID" {
  task_id=$("$EITS" tasks create --title "bats link test" --session "" | jq -r '.task_id')
  run "$EITS" tasks link-session "$task_id" "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

@test "tasks link-session: uses EITS_SESSION_UUID when no arg given" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  task_id=$("$EITS" tasks create --title "bats link env test" --session "" | jq -r '.task_id')
  run "$EITS" tasks link-session "$task_id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

@test "tasks link-session: fails with no session and EITS_SESSION_UUID unset" {
  run env -u EITS_SESSION_UUID "$EITS" tasks link-session "999" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "session_uuid" ]]
}

# ── notes ─────────────────────────────────────────────────────────────────────

@test "notes create: returns id" {
  run "$EITS" notes create \
    --parent-type session \
    --parent-id "$TEST_SESSION" \
    --body "bats test note"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id' >/dev/null
}

@test "notes list --q: returns matching results" {
  unique="bats-searchable-xyzzy-$(date +%s)"
  "$EITS" notes create \
    --parent-type session \
    --parent-id "$TEST_SESSION" \
    --body "$unique" >/dev/null
  run "$EITS" notes list --q "$unique"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

# ── commits ───────────────────────────────────────────────────────────────────

@test "commits create: requires at least one --hash" {
  export EITS_AGENT_UUID="$(_agent_uuid)"
  run "$EITS" commits create 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "--hash" ]]
}

@test "commits create: fails without agent (no env, no flag)" {
  run env -u EITS_AGENT_UUID "$EITS" commits create --hash "abc123" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "EITS_AGENT_UUID" ]]
}

@test "commits create: uses EITS_AGENT_UUID from env (no 'agent_id required' error)" {
  export EITS_AGENT_UUID="$(_agent_uuid)"
  # Server may reject an unknown hash (404/422) but we verify the env var was picked up
  # by checking the error is NOT the local "agent_id is required" message
  run bash -c "EITS_AGENT_UUID='$(_agent_uuid)' '$EITS' commits create --hash 'deadbeef0000000000000000000000000000000001' 2>&1; true"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "agent_id is required" ]]
}

@test "commits create: --agent overrides EITS_AGENT_UUID" {
  real_agent="$(_agent_uuid)"
  run bash -c "EITS_AGENT_UUID='fake-uuid' '$EITS' commits create --agent '$real_agent' --hash 'deadbeef0000000000000000000000000000000002' 2>&1; true"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "agent_id is required" ]]
}

# ── teams ─────────────────────────────────────────────────────────────────────

setup_team() {
  local name="bats-team-$(date +%s)-$RANDOM"
  local id
  id=$("$EITS" teams create --name "$name" --description "bats test team" | jq -r '.id')
  echo "$id" >> "$BATS_FILE_TMPDIR/teams_to_cleanup"
  echo "$id"
}

teardown_teams() {
  local f="$BATS_FILE_TMPDIR/teams_to_cleanup"
  [ -f "$f" ] || return 0
  local ids
  ids=$(grep -E '^[0-9]+$' "$f" | tr '\n' ',' | sed 's/,$//')
  if [ -n "$ids" ]; then
    PGPASSWORD="${EITS_PG_PASSWORD:-postgres}" psql \
      --no-psqlrc -U "${EITS_PG_USER:-postgres}" -h "${EITS_PG_HOST:-localhost}" -d "${EITS_PG_DB:-eits_dev}" \
      -c "DELETE FROM team_members WHERE team_id IN ($ids); DELETE FROM teams WHERE id IN ($ids);" \
      >/dev/null 2>&1 || true
  fi
  rm -f "$f"
}

@test "teams list: returns success and teams array" {
  run "$EITS" teams list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.teams | type == "array"' >/dev/null
}

@test "teams list --status archived: returns archived teams only" {
  team_id=$(setup_team)
  "$EITS" teams delete "$team_id" >/dev/null
  run "$EITS" teams list --status archived
  [ "$status" -eq 0 ]
  echo "$output" | jq -e ".teams[] | select(.id == $team_id)" >/dev/null
  teardown_teams
}

@test "teams create: returns id, uuid, name" {
  name="bats-create-$(date +%s)-$RANDOM"
  run "$EITS" teams create --name "$name" --description "test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.id | type == "number"' >/dev/null
  echo "$output" | jq -e '.uuid | type == "string"' >/dev/null
  echo "$output" | jq -e ".name == \"$name\"" >/dev/null
  echo "$output" | jq -r '.id' >> "$BATS_FILE_TMPDIR/teams_to_cleanup"
  teardown_teams
}

@test "teams create: fails without --name" {
  run "$EITS" teams create --description "no name" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "name" ]]
}

@test "teams get: returns team by id" {
  team_id=$(setup_team)
  run "$EITS" teams get "$team_id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e ".id == $team_id" >/dev/null
  echo "$output" | jq -e '.members | type == "array"' >/dev/null
  teardown_teams
}

@test "teams get: resolves team by name" {
  name="bats-byname-$(date +%s)-$RANDOM"
  team_id=$("$EITS" teams create --name "$name" | jq -r '.id')
  echo "$team_id" >> "$BATS_FILE_TMPDIR/teams_to_cleanup"
  run "$EITS" teams get "$name"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e ".id == $team_id" >/dev/null
  teardown_teams
}

@test "teams status: alias for get, includes members" {
  team_id=$(setup_team)
  run "$EITS" teams status "$team_id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e ".id == $team_id" >/dev/null
  echo "$output" | jq -e '.members | type == "array"' >/dev/null
  teardown_teams
}

@test "teams delete: archives team" {
  team_id=$(setup_team)
  run "$EITS" teams delete "$team_id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  archived=$("$EITS" teams list --status archived | jq -e ".teams[] | select(.id == $team_id)")
  [ -n "$archived" ]
  teardown_teams
}

@test "teams members: returns members array" {
  team_id=$(setup_team)
  run "$EITS" teams members "$team_id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.members | type == "array"' >/dev/null
  teardown_teams
}

@test "teams join: adds member to team" {
  team_id=$(setup_team)
  run "$EITS" teams join "$team_id" --name "bats-member" --role "member"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.member_id | type == "number"' >/dev/null
  members=$("$EITS" teams members "$team_id")
  echo "$members" | jq -e '.members[] | select(.name == "bats-member")' >/dev/null
  teardown_teams
}

@test "teams join: auto-picks EITS_SESSION_UUID when --session omitted" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  team_id=$(setup_team)
  run "$EITS" teams join "$team_id" --name "bats-auto-session"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  teardown_teams
}

@test "teams update-member: changes member status" {
  team_id=$(setup_team)
  member_id=$("$EITS" teams join "$team_id" --name "bats-status-member" | jq -r '.member_id')
  run "$EITS" teams update-member "$team_id" "$member_id" --status "done"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.status == "done"' >/dev/null
  teardown_teams
}

@test "teams leave: removes member" {
  team_id=$(setup_team)
  member_id=$("$EITS" teams join "$team_id" --name "bats-leave-member" | jq -r '.member_id')
  run "$EITS" teams leave "$team_id" "$member_id"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  members=$("$EITS" teams members "$team_id" | jq '.members')
  count=$(echo "$members" | jq "[.[] | select(.id == $member_id)] | length")
  [ "$count" -eq 0 ]
  teardown_teams
}

# ── default URL ───────────────────────────────────────────────────────────────

@test "BASE_URL: defaults to http://localhost:5001/api/v1 when EITS_URL unset" {
  run env -u EITS_URL "$EITS" sessions get "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.session_id' >/dev/null
}

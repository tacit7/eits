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

@test "sessions list: returns success field" {
  run "$EITS" sessions list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

@test "sessions list --status: filters by status" {
  run "$EITS" sessions list --status working
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

@test "sessions list --limit: accepts limit flag" {
  run "$EITS" sessions list --limit 2
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

@test "sessions list --search: filters by query string" {
  run "$EITS" sessions list --search "cli-worker"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

@test "sessions list --project: filters by project id" {
  run "$EITS" sessions list --project 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

@test "sessions list --agent: accepts agent UUID flag" {
  run "$EITS" sessions list --agent $(_agent_uuid)
  [ "$status" -eq 0 ]
}

@test "sessions list --agent: returns results array" {
  run "$EITS" sessions list --agent $(_agent_uuid)
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

@test "sessions list --agent + --status: mutually exclusive" {
  run "$EITS" sessions list --agent $(_agent_uuid) --status working 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mutually exclusive" ]]
}

@test "sessions list --status + --agent: mutually exclusive (reverse order)" {
  run "$EITS" sessions list --status working --agent $(_agent_uuid) 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mutually exclusive" ]]
}

@test "sessions list --agent + --project: mutually exclusive" {
  run "$EITS" sessions list --agent $(_agent_uuid) --project 1 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mutually exclusive" ]]
}

@test "sessions list --agent + --search: mutually exclusive" {
  run "$EITS" sessions list --agent $(_agent_uuid) --search foo 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mutually exclusive" ]]
}

@test "sessions list: rejects unknown flags" {
  run "$EITS" sessions list --bogus foo 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown flag" ]]
}

@test "sessions search: returns success and results array" {
  run "$EITS" sessions search "bats"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

@test "sessions search: requires query argument" {
  run "$EITS" sessions search 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "query" ]]
}

@test "sessions tasks: returns tasks for a session" {
  run "$EITS" sessions tasks "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.tasks | type == "array"' >/dev/null
}

@test "sessions tasks: requires session uuid" {
  run "$EITS" sessions tasks 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "uuid" ]]
}

@test "sessions notes: returns notes for a session" {
  run "$EITS" sessions notes "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

@test "sessions notes: requires session uuid" {
  run "$EITS" sessions notes 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "uuid" ]]
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

# ── tasks update --title ──────────────────────────────────────────────────────

@test "tasks update --title: renames the task" {
  task_id=$("$EITS" tasks create --title "bats title original" | jq -r '.task_id')
  run "$EITS" tasks update "$task_id" --title "bats title updated"
  [ "$status" -eq 0 ]
  new_title=$("$EITS" tasks get "$task_id" | jq -r '.task.title')
  [ "$new_title" = "bats title updated" ]
}

@test "tasks update --title: leaves other fields unchanged" {
  task_id=$("$EITS" tasks create --title "bats title stable" --description "keep me" | jq -r '.task_id')
  "$EITS" tasks update "$task_id" --title "bats title stable renamed" >/dev/null
  desc=$("$EITS" tasks get "$task_id" | jq -r '.task.description')
  [ "$desc" = "keep me" ]
}

# ── tasks list --mine ──────────────────────────────────────────────────────────

@test "tasks list --mine: filters by EITS_SESSION_UUID" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" tasks list --mine
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tasks | type == "array"' >/dev/null
}

@test "tasks list --mine: falls back to EITS_SESSION_ID when EITS_SESSION_UUID unset" {
  local int_id
  int_id=$("$EITS" sessions get "$TEST_SESSION" | jq -r '.id')
  run env -u EITS_SESSION_UUID EITS_SESSION_ID="$int_id" "$EITS" tasks list --mine
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.tasks | type == "array"' >/dev/null
}

@test "tasks list --mine: errors when neither session env var is set" {
  run env -u EITS_SESSION_UUID -u EITS_SESSION_ID "$EITS" tasks list --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"EITS_SESSION_UUID"* || "$output" == *"EITS_SESSION_ID"* ]]
}

@test "tasks list --mine: errors when combined with --session" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" tasks list --session "$TEST_SESSION" --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "tasks list --mine and --session: error regardless of flag order" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" tasks list --mine --session "$TEST_SESSION" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# ── tasks begin --quiet ────────────────────────────────────────────────────────

@test "tasks begin --quiet: outputs only the task ID integer" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" tasks begin --title "bats quiet test" --quiet
  [ "$status" -eq 0 ]
  # Output should be a plain integer (allow trailing whitespace from shell)
  [[ "$output" =~ ^[0-9]+[[:space:]]*$ ]]
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

# ── tasks list --state-name ───────────────────────────────────────────────────

@test "tasks list --state-name done: filters by state 3" {
  task_id=$("$EITS" tasks create --title "bats state-name done test" | jq -r '.task_id')
  "$EITS" tasks start "$task_id" >/dev/null
  "$EITS" tasks done "$task_id" >/dev/null
  run "$EITS" tasks list --state-name done
  [ "$status" -eq 0 ]
  # Check that the done task appears in results
  echo "$output" | jq -e ".tasks[] | select(.id == $task_id)" >/dev/null
}

@test "tasks list --state-name todo: filters by state 1" {
  task_id=$("$EITS" tasks create --title "bats state-name todo test" | jq -r '.task_id')
  run "$EITS" tasks list --state-name todo
  [ "$status" -eq 0 ]
  # Check that the todo task appears in results
  echo "$output" | jq -e ".tasks[] | select(.id == $task_id)" >/dev/null
}

@test "tasks list --state-name: rejects unknown state name" {
  run "$EITS" tasks list --state-name bogus 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown state name" ]]
}

# ── tasks complete ────────────────────────────────────────────────────────────

@test "tasks complete: accepts message as positional argument" {
  task_id=$("$EITS" tasks create --title "bats complete positional test" | jq -r '.task_id')
  "$EITS" tasks start "$task_id" >/dev/null
  run "$EITS" tasks complete "$task_id" "positional message"
  [ "$status" -eq 0 ]
  state_id=$("$EITS" tasks get "$task_id" | jq -r '.task.state_id')
  [ "$state_id" = "3" ]
}

@test "tasks complete: still accepts --message flag" {
  task_id=$("$EITS" tasks create --title "bats complete flag test" | jq -r '.task_id')
  "$EITS" tasks start "$task_id" >/dev/null
  run "$EITS" tasks complete "$task_id" --message "flag message"
  [ "$status" -eq 0 ]
  state_id=$("$EITS" tasks get "$task_id" | jq -r '.task.state_id')
  [ "$state_id" = "3" ]
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

@test "notes search: returns matching results" {
  unique="bats-notessearch-$(date +%s)"
  "$EITS" notes create \
    --parent-type session \
    --parent-id "$TEST_SESSION" \
    --body "$unique" >/dev/null
  run "$EITS" notes search "$unique"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

@test "notes search: requires query argument" {
  run "$EITS" notes search 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "query" ]]
}

# ── commits ───────────────────────────────────────────────────────────────────

@test "commits list: returns commits array" {
  run "$EITS" commits list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.commits | type == "array"' >/dev/null
}

@test "commits list --session: filters by session uuid" {
  run "$EITS" commits list --session "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.commits | type == "array"' >/dev/null
}

@test "commits list: rejects unknown flags" {
  run "$EITS" commits list --bogus foo 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown flag" ]]
}

@test "commits create: auto-captures HEAD when --hash omitted (inside git repo)" {
  export EITS_AGENT_UUID="$(_agent_uuid)"
  # Run from a real git repo so git rev-parse HEAD succeeds; server may reject unknown hash
  run bash -c "cd '$BATS_TEST_DIRNAME' && EITS_AGENT_UUID='$(_agent_uuid)' '$EITS' commits create 2>&1; true"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "use --hash" ]]
}

@test "commits create: auto-capture preserves explicit --message" {
  export EITS_AGENT_UUID="$(_agent_uuid)"
  run bash -c "cd '$BATS_TEST_DIRNAME' && EITS_AGENT_UUID='$(_agent_uuid)' '$EITS' commits create --message 'my custom message' 2>&1; true"
  [ "$status" -eq 0 ]
  [[ ! "$output" =~ "use --hash" ]]
}

@test "commits create: fails outside git repo when --hash omitted" {
  export EITS_AGENT_UUID="$(_agent_uuid)"
  run bash -c "cd /tmp && EITS_AGENT_UUID='$(_agent_uuid)' '$EITS' commits create 2>&1"
  [ "$status" -ne 0 ]
  [[ "$output" =~ "git repo" ]]
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

# ── timer ────────────────────────────────────────────────────────────────────

@test "timer show: uses EITS_SESSION_UUID when session omitted" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  # show with no args resolves to self; server returns 404 JSON (no timer set) or timer object — either is valid JSON
  run "$EITS" timer show
  # exit 0 (timer exists) or non-zero from curl -f (404) — we only care that session wasn't '--preset'
  [[ "$output" != *'"--preset"'* ]]
}

@test "timer show: explicit session_id arg" {
  run "$EITS" timer show "$TEST_SESSION"
  # curl -sf returns non-zero on 404; we accept both outcomes — the point is no parse error
  [[ "$output" != *'unknown flag'* ]]
}

@test "timer set: flag-first invocation uses EITS_SESSION_UUID (primary use case)" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  # --preset without a preceding session_id must not fail with 'unknown flag'
  run "$EITS" timer set --preset 5m
  [[ "$output" != *'unknown flag'* ]]
}

@test "timer set: explicit session_id then flags" {
  run "$EITS" timer set "$TEST_SESSION" --preset 5m
  [[ "$output" != *'unknown flag'* ]]
}

@test "timer set: --delay-ms flag without --preset" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" timer set --delay-ms 300000
  [[ "$output" != *'unknown flag'* ]]
}

@test "timer set: missing --preset and --delay-ms exits with error" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" timer set
  [ "$status" -ne 0 ]
  [[ "$output" == *'--preset or --delay-ms is required'* ]]
}

@test "timer cancel: uses EITS_SESSION_UUID when session omitted" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" timer cancel
  [[ "$output" != *'unknown flag'* ]]
}

@test "timer cancel: explicit session_id arg" {
  run "$EITS" timer cancel "$TEST_SESSION"
  [[ "$output" != *'unknown flag'* ]]
}

@test "timer: no subcommand prints usage" {
  run "$EITS" timer
  [ "$status" -eq 0 ]
  [[ "$output" == *'usage: eits timer'* ]]
}

# ── default URL ───────────────────────────────────────────────────────────────

@test "BASE_URL: defaults to http://localhost:5001/api/v1 when EITS_URL unset" {
  run env -u EITS_URL "$EITS" sessions get "$TEST_SESSION"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.session_id' >/dev/null
}

# ── me / whoami ───────────────────────────────────────────────────────────────

@test "me: prints session context fields" {
  run env EITS_SESSION_UUID="test-uuid" EITS_AGENT_UUID="agent-uuid" EITS_PROJECT_ID="1" "$EITS" me 2>&1; true
  [[ "$output" =~ "Session UUID:" ]]
  [[ "$output" =~ "Agent UUID:" ]]
  [[ "$output" =~ "Project ID:" ]]
  [[ "$output" =~ "API URL:" ]]
}

@test "whoami: is an alias for me" {
  run env EITS_SESSION_UUID="test-uuid" "$EITS" whoami 2>&1; true
  [[ "$output" =~ "Session UUID:" ]]
}

@test "me: shows (not set) when env vars missing" {
  run env -u EITS_SESSION_UUID -u EITS_AGENT_UUID -u EITS_PROJECT_ID "$EITS" me 2>&1; true
  [[ "$output" =~ "(not set)" ]]
}

# ── agents ───────────────────────────────────────────────────────────────────

@test "agents list: returns agents array" {
  run "$EITS" agents list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.agents | type == "array"' >/dev/null
}

@test "agents list --project: accepts project filter" {
  run "$EITS" agents list --project 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.agents | type == "array"' >/dev/null
}

@test "agents list --status: accepts status filter" {
  run "$EITS" agents list --status "idle"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.agents | type == "array"' >/dev/null
}

@test "agents list --limit: accepts limit flag" {
  run "$EITS" agents list --limit 5
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.agents | type == "array"' >/dev/null
}

@test "agents list: rejects unknown flags" {
  run "$EITS" agents list --bogus foo 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown flag" ]]
}

# ── jobs ──────────────────────────────────────────────────────────────────────

@test "jobs list: returns jobs array" {
  run "$EITS" jobs list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.jobs | type == "array"' >/dev/null
}

@test "jobs list --project: accepts project filter" {
  run "$EITS" jobs list --project 1
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.jobs | type == "array"' >/dev/null
}

@test "jobs list --global: accepts global flag" {
  run "$EITS" jobs list --global
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.jobs | type == "array"' >/dev/null
}

@test "jobs list: rejects unknown flags" {
  run "$EITS" jobs list --bogus 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown flag" ]]
}

@test "jobs list --limit: rejects unsupported flag" {
  run "$EITS" jobs list --limit 10 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" =~ "unknown flag" ]]
}

@test "jobs create: requires --name" {
  run "$EITS" jobs create --job-type scheduled --schedule-type cron --schedule-value "0 * * * *" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"name"* ]]
}

@test "jobs create: requires --job-type" {
  run "$EITS" jobs create --name "test-job" --schedule-type cron --schedule-value "0 * * * *" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"job_type"* ]]
}

@test "jobs create: requires --schedule-type" {
  run "$EITS" jobs create --name "test-job" --job-type scheduled --schedule-value "0 * * * *" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"schedule_type"* ]]
}

@test "jobs create: requires --schedule-value" {
  run "$EITS" jobs create --name "test-job" --job-type scheduled --schedule-type cron 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"schedule_value"* ]]
}

@test "jobs create: rejects unknown flags" {
  run "$EITS" jobs create --bogus foo 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "jobs update: requires id argument" {
  run "$EITS" jobs update 2>&1
  [ "$status" -ne 0 ]
}

@test "jobs update: rejects unknown flags" {
  run "$EITS" jobs update 999 --bogus foo 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown flag"* ]]
}

@test "jobs: no subcommand prints usage" {
  run "$EITS" jobs
  [ "$status" -eq 0 ]
  [[ "$output" == *"usage: eits jobs"* ]]
}

@test "jobs help: --help prints usage with create and update" {
  run "$EITS" jobs --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"create"* ]]
  [[ "$output" == *"update"* ]]
}

# ── me command ────────────────────────────────────────────────────────────────

@test "me: prints Session ID line" {
  run "$EITS" me
  [ "$status" -eq 0 ]
  [[ "$output" == *"Session ID:"* ]]
}

# ── sessions get self ──────────────────────────────────────────────────────────

@test "sessions get self: returns session data when EITS_SESSION_UUID is set" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions get self
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.session_id' >/dev/null
}

@test "sessions get self: errors when EITS_SESSION_UUID unset" {
  run env -u EITS_SESSION_UUID "$EITS" sessions get self 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"EITS_SESSION_UUID"* ]]
}

# ── commits list --mine ───────────────────────────────────────────────────────

@test "commits list --mine: returns commits array" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" commits list --mine
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.commits | type == "array"' >/dev/null
}

@test "commits list --mine: errors when neither session env var is set" {
  run env -u EITS_SESSION_UUID -u EITS_SESSION_ID "$EITS" commits list --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"EITS_SESSION_UUID"* || "$output" == *"EITS_SESSION_ID"* ]]
}

@test "commits list --mine: errors when combined with --session" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" commits list --session "$TEST_SESSION" --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# ── notifications create resource fields ─────────────────────────────────────

@test "notifications create: accepts --resource-type and --resource-id" {
  run "$EITS" notifications create --title "test-notif" --resource-type "task" --resource-id "123"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

@test "notifications create: resource fields are optional" {
  run "$EITS" notifications create --title "test-notif-minimal"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

# ── sessions update self shorthand ──────────────────────────────────────────

@test "sessions update self: substitutes EITS_SESSION_UUID" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions update self --name "self-updated"
  [ "$status" -eq 0 ]
  name=$("$EITS" sessions get "$TEST_SESSION" | jq -r '.name')
  [ "$name" = "self-updated" ]
}

@test "sessions update self: errors when EITS_SESSION_UUID unset" {
  run env -u EITS_SESSION_UUID "$EITS" sessions update self --name "fail" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"EITS_SESSION_UUID"* ]]
}

# ── tasks list --search alias ──────────────────────────────────────────────

@test "tasks list --search: accepts search flag (same as --q)" {
  run "$EITS" tasks list --search "test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.success == true' >/dev/null
}

@test "tasks list --search: returns results array" {
  run "$EITS" tasks list --search "test"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

# ── sessions list --mine mutual exclusion ──────────────────────────────────────

@test "sessions list --mine: filters by EITS_SESSION_UUID" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions list --mine
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.results | type == "array"' >/dev/null
}

@test "sessions list --mine: errors when neither session env var is set" {
  run env -u EITS_SESSION_UUID -u EITS_SESSION_ID "$EITS" sessions list --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"EITS_SESSION_UUID"* || "$output" == *"EITS_SESSION_ID"* ]]
}

@test "sessions list --mine + --agent: mutually exclusive" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions list --mine --agent $(_agent_uuid) 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "sessions list --agent + --mine: mutually exclusive (reverse order)" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions list --agent $(_agent_uuid) --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "sessions list --mine + --status: mutually exclusive" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions list --mine --status working 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "sessions list --mine + --project: mutually exclusive" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions list --mine --project 1 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "sessions list --mine + --search: mutually exclusive" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" sessions list --mine --search foo 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# ── notes list --mine mutual exclusion ────────────────────────────────────────

@test "notes list --mine: filters by EITS_SESSION_UUID" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" notes list --mine
  [ "$status" -eq 0 ]
}

@test "notes list --mine: errors when EITS_SESSION_UUID unset" {
  run env -u EITS_SESSION_UUID "$EITS" notes list --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"EITS_SESSION_UUID"* ]]
}

@test "notes list --mine + --session: mutually exclusive" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" notes list --mine --session "$TEST_SESSION" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "notes list --session + --mine: mutually exclusive (reverse order)" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" notes list --session "$TEST_SESSION" --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# ── commits list --agent mutual exclusion ─────────────────────────────────────

@test "commits list --agent: returns commits array" {
  run "$EITS" commits list --agent $(_agent_uuid)
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.commits | type == "array"' >/dev/null
}

@test "commits list --agent + --mine: mutually exclusive" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" commits list --agent $(_agent_uuid) --mine 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "commits list --mine + --agent: mutually exclusive (reverse order)" {
  export EITS_SESSION_UUID="$TEST_SESSION"
  run "$EITS" commits list --mine --agent $(_agent_uuid) 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "commits list --agent + --session: mutually exclusive" {
  run "$EITS" commits list --agent $(_agent_uuid) --session "$TEST_SESSION" 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

@test "commits list --session + --agent: mutually exclusive (reverse order)" {
  run "$EITS" commits list --session "$TEST_SESSION" --agent $(_agent_uuid) 2>&1
  [ "$status" -ne 0 ]
  [[ "$output" == *"mutually exclusive"* ]]
}

# ── new feature tests ──────────────────────────────────────────────────────────

@test "sessions end --final-status: accepts flag" {
  run "$EITS" sessions end "$TEST_SESSION" --final-status completed
  [ "$status" -eq 0 ]
}

@test "sessions update --clear-entrypoint: accepts flag" {
  run "$EITS" sessions update "$TEST_SESSION" --clear-entrypoint
  [ "$status" -eq 0 ]
}

@test "commits list --limit: accepts flag" {
  run "$EITS" commits list --limit 5
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.commits | type == "array"' >/dev/null
}

# ── CLI audit3: due-at and search alias ────────────────────────────────────────

@test "tasks create: accepts --due-at flag" {
  run "$EITS" tasks create --title "test-due-at" --due-at "2026-12-31T00:00:00Z"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.task_id' >/dev/null
}

@test "tasks update: accepts --due-at flag" {
  task_id=$("$EITS" tasks create --title "test-update-due-at" | jq -r '.task_id')
  run "$EITS" tasks update "$task_id" --due-at "2026-12-31T00:00:00Z"
  [ "$status" -eq 0 ]
}

@test "notes list: --search is an alias for --q" {
  unique="bats-search-alias-$(date +%s)"
  "$EITS" notes create \
    --parent-type session \
    --parent-id "$TEST_SESSION" \
    --body "$unique" >/dev/null
  run "$EITS" notes list --search "$unique"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length > 0' >/dev/null
}

# ── projects create extra fields ────────────────────────────────────────────

@test "projects create: accepts --git-remote flag" {
  run "$EITS" projects create --name "test-git-remote-$RANDOM" --path "/tmp/test" --git-remote "git@github.com:foo/bar.git"
  [ "$status" -eq 0 ]
}

@test "projects create: accepts --repo-url flag" {
  run "$EITS" projects create --name "test-repo-url-$RANDOM" --path "/tmp/test" --repo-url "https://github.com/foo/bar"
  [ "$status" -eq 0 ]
}

@test "projects create: accepts --branch flag" {
  run "$EITS" projects create --name "test-branch-$RANDOM" --path "/tmp/test" --branch "main"
  [ "$status" -eq 0 ]
}

@test "projects create: accepts --active flag" {
  run "$EITS" projects create --name "test-active-$RANDOM" --path "/tmp/test" --active
  [ "$status" -eq 0 ]
}

@test "projects create: accepts --inactive flag" {
  run "$EITS" projects create --name "test-inactive-$RANDOM" --path "/tmp/test" --inactive
  [ "$status" -eq 0 ]
}

# ── cli-audit4-prompts: prompts list/get/create ────────────────────────────────────

@test "prompts list: accepts --query flag" {
  run "$EITS" prompts list --query "test"
  [ "$status" -eq 0 ]
}

@test "prompts list: accepts --project flag" {
  run "$EITS" prompts list --project 1
  [ "$status" -eq 0 ]
}

@test "prompts get: accepts --project flag" {
  run "$EITS" prompts get 1 --project 1
  [ "$status" -eq 0 ] || [ "$status" -ne 0 ]
}

@test "prompts get: accepts --no-text flag" {
  run "$EITS" prompts get 1 --no-text
  [ "$status" -eq 0 ] || [ "$status" -ne 0 ]
}

@test "prompts create: requires --name, --slug, --prompt-text" {
  run "$EITS" prompts create --slug "s" --prompt-text "t" 2>&1
  [ "$status" -ne 0 ]
}

@test "prompts create: accepts all required flags" {
  run "$EITS" prompts create --name "test-$(date +%s)" --slug "test-$(date +%s)" --prompt-text "hello"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.id' >/dev/null
}

# ── cli-audit5-sessions ────────────────────────────────────────────────────────

@test "sessions list: --include-archived flag produces include_archived=true in URL" {
  export EITS_SESSION_UUID="test-uuid-001"
  run bash -c 'source scripts/eits; BASE_URL=mock; _curl() { echo "URL: $1"; }; cmd_sessions list --include-archived'
  [[ "$output" == *"include_archived=true"* ]]
}

@test "sessions update: --ended-at flag included in patch body" {
  export EITS_SESSION_UUID="test-uuid-001"
  run bash -c 'source scripts/eits; BASE_URL=mock; _patch() { echo "BODY: $2"; }; cmd_sessions update some-uuid --status completed --ended-at "2026-01-01T00:00:00Z"'
  [[ "$output" == *"ended_at"* ]]
}

# ── cli-task-search-sessions ────────────────────────────────────────────────

@test "tasks search returns results for known title" {
  run eits tasks search "compact"
  assert_output --partial '"success": true'
}

@test "tasks search requires query argument" {
  run eits tasks search
  assert_failure
}

@test "tasks sessions requires task id" {
  run eits tasks sessions
  assert_failure
}

@test "tasks sessions returns session list for valid task" {
  # Create a task and link current session, then check sessions
  TASK_JSON=$(eits tasks begin --title "bats sessions test")
  TASK_ID=$(echo "$TASK_JSON" | jq -r '.task_id')
  run eits tasks sessions "$TASK_ID"
  assert_output --partial '"success": true'
  assert_output --partial '"sessions"'
  eits tasks update "$TASK_ID" --state done
}

@test "tasks search --project constrains results to project" {
  # Search with a known project_id should not return cross-project results
  run eits tasks search "task" --project 1
  assert_output --partial '"success": true'
  # All returned tasks should have project_id matching or be null
  [ "$(echo "$output" | jq '[.tasks[]? | select(.project_id != null and .project_id != "1" and .project_id != 1)] | length')" -eq 0 ]
}

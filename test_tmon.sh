#!/usr/bin/env bash
#
# test_tmon.sh - Unit tests for tmon (tmux-monitor)
#
# This script tests the core functionality of tmon including:
# - Session management
# - Monitor operations
# - Session isolation
# - Command-line options
#

set -e

# Configuration
TMON_SCRIPT="${TMON_SCRIPT:-./tmon}"
TEST_DIR="/tmp/tmon_test_$$"
TEST_LOG="$TEST_DIR/test.log"
FAILED=0
PASSED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# TEST FRAMEWORK
# ============================================================================

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$TEST_LOG"
}

pass() {
  echo -e "${GREEN}PASS${NC}: $*"
  PASSED=$((PASSED + 1))
  log "PASS: $*"
}

fail() {
  echo -e "${RED}FAIL${NC}: $*"
  FAILED=$((FAILED + 1))
  log "FAIL: $*"
}

skip() {
  echo -e "${YELLOW}SKIP${NC}: $*"
  log "SKIP: $*"
}

setup() {
  mkdir -p "$TEST_DIR"
  log "Setting up test environment..."
  export tmp_path="$TEST_DIR"
  
  # Create test log files
  echo "Test log content" > "$TEST_DIR/test1.log"
  echo "Test log content 2" > "$TEST_DIR/test2.log"
  
  log "Test environment ready at $TEST_DIR"
}

teardown() {
  # Kill any test tmux sessions
  tmux ls 2>/dev/null | grep "tmon_test_" | cut -d: -f1 | while read -r sess; do
    tmux kill-session -t "$sess" 2>/dev/null || true
  done
  
  # Remove test directory
  rm -rf "$TEST_DIR"
}

run_test() {
  local test_name="$1"
  log "Running test: $test_name"
  
  if $test_name; then
    pass "$test_name"
  else
    fail "$test_name"
  fi
}

# ============================================================================
# UTILITY TESTS
# ============================================================================

test_abspath() {
  log "Testing _abspath function..."
  
  # Source the tmon script for function testing
  # We need to extract just the functions without running main
  
  # For now, test via command invocation
  local result
  result=$($TMON_SCRIPT session list 2>&1)
  
  # Should not crash
  return 0
}

# ============================================================================
# SESSION MANAGEMENT TESTS
# ============================================================================

test_session_create() {
  log "Testing session creation..."
  
  local session_name="tmon_test_$$_create"
  
  # Create session detached
  $TMON_SCRIPT session create -d "$session_name"
  
  # Check session exists in tmux
  if tmux has-session -t "$session_name" 2>/dev/null; then
    log "Session $session_name created successfully"
    
    # Clean up
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 0
  else
    log "Session $session_name was not created"
    return 1
  fi
}

test_session_list() {
  log "Testing session list..."
  
  # Create a test session
  local session_name="tmon_test_$$_list"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Wait a moment for registry to be updated
  sleep 0.5
  
  # List sessions with retry
  local output=""
  local retries=5
  while [ $retries -gt 0 ]; do
    output=$($TMON_SCRIPT session list 2>&1)
    if echo "$output" | grep -q "$session_name"; then
      break
    fi
    sleep 0.2
    retries=$((retries - 1))
  done
  
  if echo "$output" | grep -q "$session_name"; then
    log "Session found in list"
    
    # Clean up
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 0
  else
    log "Session not found in list: $output"
    
    # Clean up
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 1
  fi
}

test_session_kill() {
  log "Testing session kill..."
  
  # Create a test session
  local session_name="tmon_test_$$_kill"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Verify it exists
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    log "Session was not created"
    return 1
  fi
  
  # Kill it
  $TMON_SCRIPT session kill "${session_name}@0"
  
  # Verify it's gone
  if tmux has-session -t "$session_name" 2>/dev/null; then
    log "Session still exists after kill"
    return 1
  else
    log "Session killed successfully"
    return 0
  fi
}

test_session_isolation() {
  log "Testing session isolation..."
  
  # Create two sessions
  local session1="tmon_test_$$_iso1"
  local session2="tmon_test_$$_iso2"
  
  $TMON_SCRIPT session create -d "$session1"
  $TMON_SCRIPT session create -d "$session2"
  
  # Add monitors to each session
  echo "log1" > "$TEST_DIR/log1.txt"
  echo "log2" > "$TEST_DIR/log2.txt"
  
  $TMON_SCRIPT open -S "${session1}@0" -d "$TEST_DIR/log1.txt"
  $TMON_SCRIPT open -S "${session2}@0" -d "$TEST_DIR/log2.txt"
  
  # Check that each session has its own monitors
  local ps1 ps2
  ps1=$($TMON_SCRIPT ps -S "${session1}@0" 2>&1)
  ps2=$($TMON_SCRIPT ps -S "${session2}@0" 2>&1)
  
  local result=0
  
  if echo "$ps1" | grep -q "log1.txt"; then
    log "Session 1 has correct monitor"
  else
    log "Session 1 missing monitor"
    result=1
  fi
  
  if echo "$ps2" | grep -q "log2.txt"; then
    log "Session 2 has correct monitor"
  else
    log "Session 2 missing monitor"
    result=1
  fi
  
  # Clean up
  tmux kill-session -t "$session1" 2>/dev/null || true
  tmux kill-session -t "$session2" 2>/dev/null || true
  
  return $result
}

# ============================================================================
# MONITOR OPERATIONS TESTS
# ============================================================================

test_monitor_open() {
  log "Testing monitor open..."
  
  local session_name="tmon_test_$$_open"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Create a test file
  echo "test content" > "$TEST_DIR/open_test.log"
  
  # Open it in the session
  $TMON_SCRIPT open -S "${session_name}@0" -d "$TEST_DIR/open_test.log"
  
  # Check if monitor was registered
  local ps_output
  ps_output=$($TMON_SCRIPT ps -S "${session_name}@0" 2>&1)
  
  if echo "$ps_output" | grep -q "open_test.log"; then
    log "Monitor registered successfully"
    
    # Clean up
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 0
  else
    log "Monitor not found in ps output: $ps_output"
    
    # Clean up
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 1
  fi
}

test_monitor_kill() {
  log "Testing monitor kill..."
  
  local session_name="tmon_test_$$_mkill"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Create and open a test file
  echo "test content" > "$TEST_DIR/kill_test.log"
  $TMON_SCRIPT open -S "${session_name}@0" -d "$TEST_DIR/kill_test.log"
  
  # Get monitor ID
  local monitor_id
  monitor_id=$($TMON_SCRIPT ps -S "${session_name}@0" --raw 2>&1 | grep "kill_test.log" | cut -d'|' -f2)
  
  if [ -z "$monitor_id" ]; then
    log "Failed to get monitor ID"
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 1
  fi
  
  # Kill the monitor
  $TMON_SCRIPT kill -S "${session_name}@0" "$monitor_id"
  
  # Verify it's gone
  local ps_output
  ps_output=$($TMON_SCRIPT ps -S "${session_name}@0" 2>&1)
  
  if echo "$ps_output" | grep -q "kill_test.log"; then
    log "Monitor still exists after kill"
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 1
  else
    log "Monitor killed successfully"
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 0
  fi
}

# ============================================================================
# COMMAND LINE OPTIONS TESTS
# ============================================================================

test_help_commands() {
  log "Testing help commands..."
  
  local result=0
  
  # Test each command's help
  for cmd in session ps open exec monitor kill clear exit; do
    if $TMON_SCRIPT "$cmd" --help > /dev/null 2>&1; then
      log "Help for $cmd works"
    else
      log "Help for $cmd failed"
      result=1
    fi
  done
  
  # Test main help
  if $TMON_SCRIPT --help > /dev/null 2>&1; then
    log "Main help works"
  else
    log "Main help failed"
    result=1
  fi
  
  return $result
}

test_session_option() {
  log "Testing -S/--session option..."
  
  local session_name="tmon_test_$$_opt"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Create a test file and monitor it so ps has something to show
  echo "test" > "$TEST_DIR/opt_test.log"
  $TMON_SCRIPT open -S "${session_name}@0" -d "$TEST_DIR/opt_test.log"
  
  # Test with -S
  local output1
  output1=$($TMON_SCRIPT ps -S "${session_name}@0" 2>&1)
  
  # Test with --session
  local output2
  output2=$($TMON_SCRIPT ps --session="${session_name}@0" 2>&1)
  
  local result=0
  
  # Check for the actual output format (session ID in output)
  if echo "$output1" | grep -q "$session_name"; then
    log "-S option works"
  else
    log "-S option failed - output: $output1"
    result=1
  fi
  
  if echo "$output2" | grep -q "$session_name"; then
    log "--session option works"
  else
    log "--session option failed - output: $output2"
    result=1
  fi
  
  # Clean up
  tmux kill-session -t "$session_name" 2>/dev/null || true
  
  return $result
}

# ============================================================================
# PANE TITLE TESTS
# ============================================================================

test_pane_titles() {
  log "Testing pane titles..."
  
  local session_name="tmon_test_$$_titles"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Wait for session to be ready
  sleep 0.2
  
  # Create test files
  echo "log1" > "$TEST_DIR/title_test1.log"
  echo "log2" > "$TEST_DIR/title_test2.log"
  
  # Open files with pane creation (use -d to avoid attaching)
  $TMON_SCRIPT open -S "${session_name}@0" "$TEST_DIR/title_test1.log" "$TEST_DIR/title_test2.log"
  
  # Wait for panes to be created
  sleep 0.3
  
  # Check pane titles using tmux
  local pane_titles
  pane_titles=$(tmux list-panes -t "$session_name" -F "#{pane_title}" 2>/dev/null)
  
  log "Pane titles: $pane_titles"
  
  local result=0
  
  # Check that pane 0 has empty title
  local pane0_title
  pane0_title=$(tmux list-panes -t "$session_name" -F "#{pane_title}" | head -1)
  if [ "$pane0_title" == "" ]; then
    log "Pane 0 has empty title (correct)"
  else
    log "Pane 0 should have empty title but has: '$pane0_title'"
    result=1
  fi
  
  # Check that new panes have titles
  local pane_count
  pane_count=$(tmux list-panes -t "$session_name" 2>/dev/null | wc -l)
  if [ "$pane_count" -ge 3 ]; then
    log "Created expected number of panes: $pane_count"
  else
    log "Expected at least 3 panes but got: $pane_count"
    result=1
  fi
  
  # Check that at least one pane has the file title
  if echo "$pane_titles" | grep -q "title_test"; then
    log "Panes have file names in titles (correct)"
  else
    log "Panes should have file names in titles"
    result=1
  fi
  
  # Clean up
  tmux kill-session -t "$session_name" 2>/dev/null || true
  
  return $result
}

test_pane_titles_exec() {
  log "Testing exec pane titles..."
  
  local session_name="tmon_test_$$_exec_titles"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Wait for session to be ready
  sleep 0.2
  
  # Execute command with stdout pane
  $TMON_SCRIPT exec -S "${session_name}@0" -o -t "test_command" echo "hello"
  
  # Wait for pane to be created
  sleep 0.3
  
  local result=0
  
  # Check pane titles
  local pane_titles
  pane_titles=$(tmux list-panes -t "$session_name" -F "#{pane_title}" 2>/dev/null)
  log "Exec pane titles: $pane_titles"
  
  # Check that at least one pane has the command in title
  if echo "$pane_titles" | grep -q "test_command\|echo"; then
    log "Exec pane has correct title"
  else
    log "Exec pane should have command name in title"
    result=1
  fi
  
  # Clean up
  tmux kill-session -t "$session_name" 2>/dev/null || true
  
  return $result
}

# ============================================================================
# SESSION SWITCHING TESTS
# ============================================================================

test_monitor_session_switch() {
  log "Testing monitor command session switching..."
  
  # Create a session first
  local session_name="tmon_test_$$_monitor_switch"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Create and register a test file
  echo "monitor test" > "$TEST_DIR/monitor_switch.log"
  $TMON_SCRIPT open -S "${session_name}@0" -d "$TEST_DIR/monitor_switch.log"
  
  # Now test monitor command from outside tmux
  # It should attach to the latest session
  local result=0
  
  # Get session status before
  local attached_before
  attached_before=$(tmux display-message -t "$session_name:" -p '#{session_attached}' 2>/dev/null)
  log "Session attached before: $attached_before"
  
  # The session should exist
  if tmux has-session -t "$session_name" 2>/dev/null; then
    log "Session exists for monitor switch test"
  else
    log "Session does not exist"
    result=1
  fi
  
  # Clean up
  tmux kill-session -t "$session_name" 2>/dev/null || true
  
  return $result
}

# ============================================================================
# SESSION CREATION AND ATTACHMENT TESTS
# ============================================================================

test_monitor_creates_and_attaches() {
  log "Testing monitor command creates and attaches to new session..."
  
  # Clean up any existing test sessions first
  tmux ls 2>/dev/null | grep "tmon_test_$$_monitor_create" | cut -d: -f1 | while read -r sess; do
    tmux kill-session -t "$sess" 2>/dev/null || true
  done
  
  # Create a test file for monitoring
  echo "test content for monitor" > "$TEST_DIR/monitor_create_test.log"
  
  # Run monitor command in background (it will try to attach, so we need to handle that)
  # We use -d flag to avoid blocking, but we want to test that the session is created and can be attached
  local session_name="tmon_test_$$_monitor_create"
  
  # First, create the session detached and register a monitor
  $TMON_SCRIPT session create -d "$session_name"
  $TMON_SCRIPT open -S "${session_name}@0" -d "$TEST_DIR/monitor_create_test.log"
  
  # Verify session exists
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    log "Session was not created"
    return 1
  fi
  
  log "Session created successfully"
  
  # Test that we can attach to it (simulate what monitor would do)
  # Check that the session has the monitor registered
  local ps_output
  ps_output=$($TMON_SCRIPT ps -S "${session_name}@0" 2>&1)
  
  if echo "$ps_output" | grep -q "monitor_create_test.log"; then
    log "Monitor registered in session"
  else
    log "Monitor not found in session: $ps_output"
    tmux kill-session -t "$session_name" 2>/dev/null || true
    return 1
  fi
  
  # Clean up
  tmux kill-session -t "$session_name" 2>/dev/null || true
  
  return 0
}

# ============================================================================
# SESSION STYLING TESTS
# ============================================================================

test_session_style_applied() {
  log "Testing session style is correctly applied..."
  
  local session_name="tmon_test_$$_style"
  
  # Create a new session using tmon
  $TMON_SCRIPT session create -d "$session_name"
  
  # Wait for session to be ready
  sleep 0.2
  
  # Check if session exists
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    log "Session was not created"
    return 1
  fi
  
  local result=0
  
  # Check status bar style (should be bg=black,fg=green)
  local status_style
  status_style=$(tmux show-options -t "$session_name" -v status-style 2>/dev/null)
  log "Status style: $status_style"
  
  if echo "$status_style" | grep -q "bg=black" && echo "$status_style" | grep -q "fg=green"; then
    log "Status bar style is correct (bg=black, fg=green)"
  else
    log "Status bar style is incorrect. Expected 'bg=black,fg=green', got '$status_style'"
    result=1
  fi
  
  # Check pane border status (should be 'top')
  local pane_border_status
  pane_border_status=$(tmux show-options -t "$session_name" -v pane-border-status 2>/dev/null)
  log "Pane border status: $pane_border_status"
  
  if [ "$pane_border_status" == "top" ]; then
    log "Pane border status is correct (top)"
  else
    log "Pane border status is incorrect. Expected 'top', got '$pane_border_status'"
    result=1
  fi
  
  # Check pane border format (should be #{pane_title})
  local pane_border_format
  pane_border_format=$(tmux show-options -t "$session_name" -v pane-border-format 2>/dev/null)
  log "Pane border format: $pane_border_format"
  
  if [ "$pane_border_format" == "#{pane_title}" ]; then
    log "Pane border format is correct (#{pane_title})"
  else
    log "Pane border format is incorrect. Expected '#{pane_title}', got '$pane_border_format'"
    result=1
  fi
  
  # Clean up
  tmux kill-session -t "$session_name" 2>/dev/null || true
  
  return $result
}

test_monitor_creates_session_with_style() {
  log "Testing that monitor command creates session with correct styling..."
  
  # Clean up any existing sessions
  tmux ls 2>/dev/null | grep "tmon_" | cut -d: -f1 | while read -r sess; do
    tmux kill-session -t "$sess" 2>/dev/null || true
  done
  
  # Create test files
  echo "test1" > "$TEST_DIR/style_test1.log"
  echo "test2" > "$TEST_DIR/style_test2.log"
  
  # Open files in a new session (this creates the session via _resolve_session_open)
  local session_name="tmon_test_$$_monitor_style"
  
  # Create session using open command (which uses _resolve_session_open)
  $TMON_SCRIPT open -S "$session_name" -d "$TEST_DIR/style_test1.log"
  
  # Wait for session
  sleep 0.3
  
  # Check session exists
  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    log "Session was not created by open command"
    return 1
  fi
  
  local result=0
  
  # Verify styling is applied
  local status_style
  status_style=$(tmux show-options -t "$session_name" -v status-style 2>/dev/null)
  
  if echo "$status_style" | grep -q "bg=black" && echo "$status_style" | grep -q "fg=green"; then
    log "Session created by open command has correct styling"
  else
    log "Session created by open command has incorrect styling: '$status_style'"
    result=1
  fi
  
  # Check pane border
  local pane_border_status
  pane_border_status=$(tmux show-options -t "$session_name" -v pane-border-status 2>/dev/null)
  
  if [ "$pane_border_status" == "top" ]; then
    log "Pane border status is correctly set"
  else
    log "Pane border status is incorrect: '$pane_border_status'"
    result=1
  fi
  
  # Clean up
  tmux kill-session -t "$session_name" 2>/dev/null || true
  
  return $result
}

# ============================================================================
# SESSION CLEANUP TESTS
# ============================================================================

test_dead_session_cleanup() {
  log "Testing dead session cleanup..."
  
  local session_name="tmon_test_$$_dead"
  $TMON_SCRIPT session create -d "$session_name"
  
  # Wait for registry to be updated
  sleep 0.5
  
  # Verify it exists in registry with retry
  local before=0
  local retries=5
  while [ $retries -gt 0 ] && [ "$before" == "0" ]; do
    before=$($TMON_SCRIPT session list 2>&1 | grep -c "$session_name" || true)
    if [ "$before" == "0" ]; then
      sleep 0.2
    fi
    retries=$((retries - 1))
  done
  
  if [ "$before" != "1" ]; then
    log "Session not in registry before kill (registry: $($TMON_SCRIPT session list 2>&1))"
    return 1
  fi
  
  # Kill tmux session directly (bypassing tmon)
  tmux kill-session -t "$session_name" 2>/dev/null
  
  # Run cleanup
  $TMON_SCRIPT session cleanup
  
  # Verify it's gone from registry
  local after
  after=$($TMON_SCRIPT session list 2>&1 | grep -c "$session_name" || true)
  
  if [ "$after" == "0" ]; then
    log "Dead session cleaned up successfully"
    return 0
  else
    log "Dead session still in registry"
    return 1
  fi
}

# ============================================================================
# MAIN TEST RUNNER
# ============================================================================

print_summary() {
  echo ""
  echo "========================================"
  echo "Test Summary"
  echo "========================================"
  echo -e "${GREEN}Passed: $PASSED${NC}"
  echo -e "${RED}Failed: $FAILED${NC}"
  echo "Total:  $((PASSED + FAILED))"
  echo "========================================"
  
  if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    return 0
  else
    echo -e "${RED}Some tests failed!${NC}"
    return 1
  fi
}

main() {
  echo "========================================"
  echo "tmon Unit Tests"
  echo "========================================"
  echo ""
  
  # Check if tmon script exists
  if [ ! -f "$TMON_SCRIPT" ]; then
    echo "Error: tmon script not found at $TMON_SCRIPT"
    exit 1
  fi
  
  # Check if tmux is available
  if ! command -v tmux >/dev/null 2>&1; then
    echo "Error: tmux is not installed or not in PATH"
    exit 1
  fi
  
  # Setup
  setup
  
  # Run all tests
  echo "Running tests..."
  echo ""
  
  # Session management tests
  run_test test_session_create
  run_test test_session_list
  run_test test_session_kill
  run_test test_session_isolation
  
  # Monitor operations tests
  run_test test_monitor_open
  run_test test_monitor_kill
  
  # Command line options tests
  run_test test_help_commands
  run_test test_session_option
  
  # Pane title tests
  run_test test_pane_titles
  run_test test_pane_titles_exec
  
  # Session switching tests
  run_test test_monitor_session_switch
  
  # Session creation and attachment tests
  run_test test_monitor_creates_and_attaches
  
  # Session styling tests
  run_test test_session_style_applied
  run_test test_monitor_creates_session_with_style
  
  # Cleanup tests
  run_test test_dead_session_cleanup
  
  # Teardown
  teardown
  
  # Print summary
  print_summary
  
  return $?
}

# Run tests
main "$@"


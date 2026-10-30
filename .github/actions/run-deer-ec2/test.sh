#!/usr/bin/env bash
set -euo pipefail

# Requires Bash, jq, and mikefarah/yq v4. The AWS CLI is mocked; no credentials or network access are used.
# Testing locally on Windows, use WSL or Docker for Bash.
# Keep this file LF-terminated; Windows core.autocrlf=true can make Bash reject it in WSL or Docker.

action_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
test_dir="$(mktemp -d)"
trap 'rm -rf "$test_dir"' EXIT
# Extract each action's inline script so the harness tests the real step bodies.
# Assumption to verify if action.yml changes: the four run blocks remain steps 0-3.
for index in 0 1 2 3; do
  yq -r ".runs.steps[$index].run" "$action_dir/action.yml" > "$test_dir/step-$index.sh"
  bash -n "$test_dir/step-$index.sh"
done

# These are fake action inputs. The measure path deliberately contains a quote
# and command-substitution syntax to verify they are passed literally to PowerShell.
export GITHUB_RUN_ID=123
export GITHUB_RUN_ATTEMPT=2
export MODEL_REPO="solaristechnical/DEER-Prototypes-EnergyPlus"
export COMMIT_SHA=64daae4514c08c7d93da60561c0f6384a464c300
export MEASURE_PATH="commercial measures/Bob's \$(printf unsafe)"
export S3_BUCKET=test-bucket
export WORKFLOW_PACKAGE_S3_KEY=githubactions/123/workflow.zip
export SCENARIO_ID="SWHC030-03 Whole House Fan_SFm_1975"
export INSTANCE_ID=i-test

# Replace real delays and AWS calls in child Bash processes with test doubles.
sleep() { :; }
aws() {
  case "$1 $2" in
    "ssm send-command")
      if [[ "$MODE" == send-error ]]; then
        echo "Mock SSM submission error" >&2
        return 1
      fi
      if [[ "$MODE" == no-command ]]; then echo None; return; fi
      while [[ $# -gt 0 ]]; do
        if [[ "$1" == --parameters ]]; then printf '%s' "$2" > parameters.json; break; fi
        shift
      done
      echo command-test
      ;;
    "ssm get-command-invocation")
      local count=0 status=Success
      [[ ! -f poll-count ]] || count="$(cat poll-count)"
      count=$((count + 1))
      echo "$count" > poll-count
      case "$MODE" in
        unavailable) echo "Mock SSM invocation error" >&2; return 1 ;;
        delayed)
          if [[ "$count" -eq 1 ]]; then
            echo "Mock InvocationDoesNotExist" >&2
            return 1
          fi
          if [[ "$count" -eq 2 ]]; then status=InProgress; fi
          ;;
        Failed|Cancelled|TimedOut|Pending) status="$MODE" ;;
      esac
      jq -nc --arg status "$status" '{Status:$status,StatusDetails:$status,ResponseCode:0}'
      ;;
    "s3 cp")
      [[ "$3" == "s3://$S3_BUCKET/githubactions/$GITHUB_RUN_ID/steps/$DEER_STEP/step-status.json" ]] || return 1
      local count=0
      [[ ! -f download-count ]] || count="$(cat download-count)"
      count=$((count + 1))
      echo "$count" > download-count
      case "$MODE" in
        missing) return 1 ;;
        malformed) echo 'not json' > "$4" ;;
        invalid-status) echo '{"Status":5}' > "$4" ;;
        retry-status)
          if [[ "$count" -lt 3 ]]; then
            echo 'not json' > "$4"
          else
            echo '{"Status":"Success"}' > "$4"
          fi
          ;;
        deer-failure) echo '{"Status":"Failed"}' > "$4" ;;
        *) echo '{"Status":"Success"}' > "$4" ;;
      esac
      ;;
    *) echo "Unexpected AWS call: $*" >&2; return 1 ;;
  esac
}
export -f aws sleep

# Read a named output from the current case's GitHub Actions output file.
output() { sed -n "s/^$1=//p" "$GITHUB_OUTPUT"; }
run_case() (
  local name="$1" expected="$2" result=success
  export MODE="$3" DEER_STEP="${4:-package-qc}"
  mkdir "$test_dir/$name"
  cd "$test_dir/$name"
  export GITHUB_OUTPUT="$PWD/outputs" GITHUB_STEP_SUMMARY="$PWD/summary"
  export POLL_ATTEMPTS=3 POLL_INTERVAL_SECONDS=1
  [[ "$MODE" != invalid-poll ]] || POLL_ATTEMPTS=0
  : > "$GITHUB_OUTPUT"

  # Run each extracted step in order, preserving Actions outcomes and outputs.
  export SEND_COMMAND_OUTCOME=success
  bash -e -o pipefail "$test_dir/step-0.sh" > log 2>&1 || SEND_COMMAND_OUTCOME=failure
  export COMMAND_ID="$(output command_id)"
  export WAIT_OUTCOME=success
  bash -e -o pipefail "$test_dir/step-1.sh" >> log 2>&1 || WAIT_OUTCOME=failure
  if [[ -n "$COMMAND_ID" ]]; then
    bash -e -o pipefail "$test_dir/step-2.sh" >> log 2>&1 || result=failure
  fi
  export SSM_STATUS="$(output ssm_status)"
  export STATUS_FILE_AVAILABLE="$(output step_status_available)"
  export STEP_STATUS="$(output step_status)"
  bash -e -o pipefail "$test_dir/step-3.sh" >> log 2>&1 || result=failure

  # Check the overall result and the specific contract exercised by this mode.
  if [[ "$result" != "$expected" ]]; then
    cat log
    echo "FAIL: $name (expected $expected, got $result)" >&2
    exit 1
  fi
  if [[ "$expected" == failure ]]; then grep -q '::error::' log; fi
  case "$MODE" in
    success|delayed|retry-status)
      [[ "$COMMAND_ID" == command-test && "$SSM_STATUS" == Success ]]
      [[ "$STATUS_FILE_AVAILABLE" == true && "$STEP_STATUS" == Success ]]
      grep -q "transcript_$DEER_STEP.log" summary
      jq -e --arg fragment "-MeasurePath 'commercial measures/Bob''s \$(printf unsafe)'" \
        '.commands[0] | contains($fragment)' parameters.json > /dev/null
      jq -e --arg step "-RequestedSteps '$DEER_STEP'" \
        '.commands[0] | contains($step)' parameters.json > /dev/null
      jq -e '.executionTimeout == ["14400"]' parameters.json > /dev/null
      jq -e --arg scenario "-ScenarioId '$SCENARIO_ID'" \
        '.commands[0] | contains($scenario)' parameters.json > /dev/null
      ;;
    Failed|Cancelled|TimedOut)
      [[ "$SSM_STATUS" == "$MODE" && "$(cat poll-count)" == 1 ]]
      [[ "$STATUS_FILE_AVAILABLE" == true ]]
      ;;
    Pending|unavailable)
      [[ "$(cat poll-count)" == 3 ]]
      [[ "$(output ssm_status_details)" == "Polling deadline reached;"* ]]
      [[ "$MODE" != unavailable ]] || [[ "$SSM_STATUS" == Unknown ]]
      ;;
    send-error|no-command)
      [[ -z "$COMMAND_ID" && "$SSM_STATUS" == NotSubmitted ]]
      [[ ! -f poll-count && ! -f download-count ]]
      ;;
    missing|malformed|invalid-status)
      [[ "$(cat download-count)" == 10 && "$STATUS_FILE_AVAILABLE" == false ]]
      [[ ! -f step-status.json ]]
      ;;
    deer-failure) [[ "$SSM_STATUS" == Success && "$STEP_STATUS" == Failed ]] ;;
    invalid-poll) [[ "$WAIT_OUTCOME" == failure && ! -f poll-count ]] ;;
  esac
  [[ "$MODE" != delayed ]] || [[ "$(cat poll-count)" == 3 ]]
  [[ "$MODE" != retry-status ]] || [[ "$(cat download-count)" == 3 ]]
  echo "PASS: $name"
)

for step in package-qc compose compose-qc simulate-1 simulate-2; do
  run_case "$step-success" success success "$step"
done
run_case invocation-eventual-consistency success delayed
run_case invalid-status-retry success retry-status
for mode in Failed Cancelled TimedOut Pending unavailable send-error no-command missing malformed invalid-status deer-failure invalid-poll; do
  run_case "$mode" failure "$mode"
done

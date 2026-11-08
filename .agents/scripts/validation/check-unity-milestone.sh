#!/bin/bash

# ==============================================================================
# [기능]: Unity 마일스톤 증거가 사전 빌드 또는 빌드 완료 게이트를 충족하는지 확인합니다.
# [작성자]: 윤승종
# ===============================================================================

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
AGENTS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
PROFILE_SCRIPT="$AGENTS_ROOT/scripts/shared/profile.sh"
SCHEMA_PATH="$AGENTS_ROOT/config/unity-milestone-validation-schema.conf"
EVIDENCE_PATH=""
PHASE=""
EXPECTED_CHANGE_ID=""
EXPECTED_AUTHORITY=""
VALIDATED_SCOPE_LIST=""
PROFILE_MULTIPLE_VALUES=""

fail_gate()
{
    printf '%s\n' "[마일스톤 검증] 게이트 실패: $1" >&2
    exit 1
}

fail_argument()
{
    printf '%s\n' "[마일스톤 검증] 잘못된 인자: $1" >&2
    exit 3
}

fail_input()
{
    printf '%s\n' "[마일스톤 검증] 입력 오류: $1" >&2
    exit 4
}

require_readable_regular_file()
{
    local label=$1
    local path=$2

    if [ -z "$path" ] || [ -L "$path" ] || [ ! -f "$path" ] || [ ! -r "$path" ]; then
        fail_input "$label 파일을 읽을 수 없습니다: $path"
    fi
}

validate_identifier()
{
    local label=$1
    local value

    value=$2
    case "$value" in
        ""|none|[[:space:]]*|*[[:space:]])
            fail_gate "$label는 비어 있거나 none이거나 공백으로 시작 또는 끝날 수 없습니다."
            ;;
    esac
}

newline_list_contains()
{
    local list=$1
    local expected=$2
    local item

    while IFS= read -r item || [ -n "$item" ]; do
        if [ "$item" = "$expected" ]; then
            return 0
        fi
    done <<NEWLINE_LIST_EOF
$list
NEWLINE_LIST_EOF

    return 1
}

load_multiple_profile_values()
{
    local key=$1
    local values
    local profile_status

    values=$(
        profile_get_all "$key"
        profile_status=$?
        printf '%s' x
        exit "$profile_status"
    )
    profile_status=$?
    if [ "$profile_status" -ne 0 ]; then
        return "$profile_status"
    fi

    values=${values%?}
    case "$values" in
        *$'\n')
            values=${values%?}
            ;;
    esac
    PROFILE_MULTIPLE_VALUES=$values
    return 0
}

validate_scope_records()
{
    local key=$1
    local scopes
    local scope
    local scope_list=""
    local scope_count=0

    load_multiple_profile_values "$key" || fail_input "증거에서 $key 기록을 읽을 수 없습니다."
    scopes=$PROFILE_MULTIPLE_VALUES
    if [ -z "$scopes" ]; then
        fail_gate "$key 기록이 하나 이상 필요합니다."
    fi

    while IFS= read -r scope || [ -n "$scope" ]; do
        validate_identifier "$key" "$scope"
        case "$scope" in
            *'|'*)
                fail_gate "$key 항목에는 구분자 |를 사용할 수 없습니다: $scope"
                ;;
        esac

        if newline_list_contains "$scope_list" "$scope"; then
            fail_gate "$key 항목이 중복되었습니다: $scope"
        fi

        if [ -z "$scope_list" ]; then
            scope_list=$scope
        else
            scope_list="${scope_list}
$scope"
        fi
        scope_count=$((scope_count + 1))
    done <<SCOPE_RECORDS_EOF
$scopes
SCOPE_RECORDS_EOF

    if [ "$scope_count" -eq 0 ]; then
        fail_gate "$key 기록이 하나 이상 필요합니다."
    fi

    VALIDATED_SCOPE_LIST=$scope_list
}

validate_result_records()
{
    local key=$1
    local expected_subjects=$2
    local records
    local record
    local subject
    local remainder
    local automated_test_id
    local result
    local result_subjects=""
    local expected_subject
    local record_count=0

    load_multiple_profile_values "$key" || fail_input "증거에서 $key 기록을 읽을 수 없습니다."
    records=$PROFILE_MULTIPLE_VALUES
    if [ -z "$records" ]; then
        fail_gate "$key 기록이 하나 이상 필요합니다."
    fi

    while IFS= read -r record || [ -n "$record" ]; do
        record_count=$((record_count + 1))

        case "$record" in
            *'|'*)
                subject=${record%%|*}
                remainder=${record#*|}
                ;;
            *)
                fail_gate "$key 기록 형식이 올바르지 않습니다: $record"
                ;;
        esac

        case "$remainder" in
            *'|'*)
                automated_test_id=${remainder%%|*}
                result=${remainder#*|}
                ;;
            *)
                fail_gate "$key 기록 형식이 올바르지 않습니다: $record"
                ;;
        esac

        case "$result" in
            *'|'*)
                fail_gate "$key 기록 구분자가 너무 많습니다: $record"
                ;;
        esac

        validate_identifier "$key subject" "$subject"
        validate_identifier "$key automated-test-id" "$automated_test_id"
        if [ "$result" != "passed" ]; then
            fail_gate "$key 기록이 통과 증거가 아닙니다: $record"
        fi

        if newline_list_contains "$result_subjects" "$subject"; then
            fail_gate "$key subject가 중복되었습니다: $subject"
        fi
        if ! newline_list_contains "$expected_subjects" "$subject"; then
            fail_gate "$key subject가 확정 scope에 없습니다: $subject"
        fi

        if [ -z "$result_subjects" ]; then
            result_subjects=$subject
        else
            result_subjects="${result_subjects}
$subject"
        fi
    done <<RESULT_RECORDS_EOF
$records
RESULT_RECORDS_EOF

    if [ "$record_count" -eq 0 ]; then
        fail_gate "$key 기록이 하나 이상 필요합니다."
    fi

    while IFS= read -r expected_subject || [ -n "$expected_subject" ]; do
        if [ -n "$expected_subject" ] && ! newline_list_contains "$result_subjects" "$expected_subject"; then
            fail_gate "$key에 확정 scope 결과가 누락되었습니다: $expected_subject"
        fi
    done <<EXPECTED_SUBJECTS_EOF
$expected_subjects
EXPECTED_SUBJECTS_EOF
}

EVIDENCE_SPECIFIED=0
PHASE_SPECIFIED=0
CHANGE_ID_SPECIFIED=0
AUTHORITY_SPECIFIED=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --evidence)
            if [ "$#" -lt 2 ] || [ "${2#--}" != "$2" ]; then
                fail_argument "--evidence 뒤에 증거 파일 경로가 필요합니다."
            fi
            if [ "$EVIDENCE_SPECIFIED" -eq 1 ]; then
                fail_argument "--evidence는 한 번만 지정할 수 있습니다."
            fi
            EVIDENCE_PATH=$2
            EVIDENCE_SPECIFIED=1
            shift 2
            ;;
        --phase)
            if [ "$#" -lt 2 ] || [ "${2#--}" != "$2" ]; then
                fail_argument "--phase 뒤에 prebuild 또는 built가 필요합니다."
            fi
            if [ "$PHASE_SPECIFIED" -eq 1 ]; then
                fail_argument "--phase는 한 번만 지정할 수 있습니다."
            fi
            case "$2" in
                prebuild|built)
                    PHASE=$2
                    ;;
                *)
                    fail_argument "지원하지 않는 phase입니다: $2"
                    ;;
            esac
            PHASE_SPECIFIED=1
            shift 2
            ;;
        --change-id)
            if [ "$#" -lt 2 ] || [ "${2#--}" != "$2" ]; then
                fail_argument "--change-id 뒤에 변경 식별자가 필요합니다."
            fi
            if [ "$CHANGE_ID_SPECIFIED" -eq 1 ]; then
                fail_argument "--change-id는 한 번만 지정할 수 있습니다."
            fi
            EXPECTED_CHANGE_ID=$2
            CHANGE_ID_SPECIFIED=1
            shift 2
            ;;
        --expected-authority)
            if [ "$#" -lt 2 ] || [ "${2#--}" != "$2" ] || [ "$AUTHORITY_SPECIFIED" -eq 1 ]; then
                fail_argument "--expected-authority 뒤에 local 또는 unity_ci가 한 번 필요합니다."
            fi
            case "$2" in local|unity_ci) EXPECTED_AUTHORITY=$2 ;; *) fail_argument "지원하지 않는 authority입니다: $2" ;; esac
            AUTHORITY_SPECIFIED=1
            shift 2
            ;;
        *)
            fail_argument "알 수 없는 인자입니다: $1"
            ;;
    esac
done

if [ "$EVIDENCE_SPECIFIED" -ne 1 ] || [ "$PHASE_SPECIFIED" -ne 1 ] || [ "$CHANGE_ID_SPECIFIED" -ne 1 ]; then
    fail_argument "--evidence, --phase, --change-id를 모두 지정해야 합니다."
fi
if [ "$PHASE" = built ] && [ "$AUTHORITY_SPECIFIED" -ne 1 ]; then
    fail_argument "built에는 --expected-authority가 필요합니다."
fi

if [ -z "$EXPECTED_CHANGE_ID" ] || [ "$EXPECTED_CHANGE_ID" = "none" ]; then
    fail_argument "--change-id에는 비어 있지 않은 변경 식별자가 필요합니다."
fi

if [ -L "$EVIDENCE_PATH" ]; then
    fail_input "증거 파일은 심볼릭 링크일 수 없습니다: $EVIDENCE_PATH"
fi

require_readable_regular_file "profile.sh" "$PROFILE_SCRIPT"
require_readable_regular_file "스키마" "$SCHEMA_PATH"
require_readable_regular_file "증거" "$EVIDENCE_PATH"

. "$PROFILE_SCRIPT" || fail_input "profile.sh를 불러올 수 없습니다."

if ! declare -F profile_load >/dev/null 2>&1 || ! declare -F profile_get >/dev/null 2>&1 || ! declare -F profile_get_all >/dev/null 2>&1; then
    fail_input "profile.sh에 필요한 프로필 API가 없습니다."
fi

profile_load "$EVIDENCE_PATH" "$SCHEMA_PATH" || fail_input "증거 파일 형식이 올바르지 않습니다."

load_multiple_profile_values "coverage_status" || fail_input "coverage_status 기록을 읽을 수 없습니다."
if [ "$PROFILE_MULTIPLE_VALUES" != "confirmed" ]; then
    fail_gate "coverage_status는 정확히 한 번 confirmed여야 합니다."
fi

MILESTONE_ID=$(profile_get "milestone_id") || fail_input "증거에서 milestone_id 값을 읽을 수 없습니다."
CHANGE_ID=$(profile_get "change_id") || fail_input "증거에서 change_id 값을 읽을 수 없습니다."
BUILD_AUTHORITY=$(profile_get "build_authority") || fail_input "증거에서 build_authority 값을 읽을 수 없습니다."
COMPILE_RESULT=$(profile_get "compile") || fail_input "증거에서 compile 값을 읽을 수 없습니다."
UNIT_TEST_RESULT=$(profile_get "unit_test") || fail_input "증거에서 unit_test 값을 읽을 수 없습니다."
INTEGRATION_TEST_RESULT=$(profile_get "integration_test") || fail_input "증거에서 integration_test 값을 읽을 수 없습니다."
BUILD_VALIDATION_RESULT=$(profile_get "build_validation") || fail_input "증거에서 build_validation 값을 읽을 수 없습니다."
BUILD_RUN_ID=$(profile_get "build_run_id") || fail_input "증거에서 build_run_id 값을 읽을 수 없습니다."
BUILD_ARTIFACT_HASH=$(profile_get "build_artifact_hash") || fail_input "증거에서 build_artifact_hash 값을 읽을 수 없습니다."

validate_identifier "milestone_id" "$MILESTONE_ID"
validate_identifier "change_id" "$CHANGE_ID"

if [ "$CHANGE_ID" != "$EXPECTED_CHANGE_ID" ]; then
    fail_gate "change_id가 예상값과 다릅니다."
fi
if [ -n "$EXPECTED_AUTHORITY" ] && [ "$BUILD_AUTHORITY" != "$EXPECTED_AUTHORITY" ]; then
    fail_gate "build_authority가 선택한 권위와 다릅니다."
fi

if [ "$COMPILE_RESULT" != "passed" ]; then
    fail_gate "compile이 passed여야 합니다."
fi

if [ "$UNIT_TEST_RESULT" != "passed" ]; then
    fail_gate "unit_test가 passed여야 합니다."
fi

if [ "$INTEGRATION_TEST_RESULT" != "passed" ]; then
    fail_gate "integration_test가 passed여야 합니다."
fi

validate_scope_records "module_scope"
MODULE_SCOPE_LIST=$VALIDATED_SCOPE_LIST
validate_scope_records "interaction_scope"
INTERACTION_SCOPE_LIST=$VALIDATED_SCOPE_LIST
validate_result_records "module_result" "$MODULE_SCOPE_LIST"
validate_result_records "interaction_result" "$INTERACTION_SCOPE_LIST"

case "$PHASE" in
    prebuild)
        if [ "$BUILD_VALIDATION_RESULT" != "pending" ]; then
            fail_gate "prebuild에서는 build_validation이 pending이어야 합니다."
        fi
        if [ "$BUILD_RUN_ID" != "pending" ]; then
            fail_gate "prebuild에서는 build_run_id가 pending이어야 합니다."
        fi
        if [ "$BUILD_ARTIFACT_HASH" != "pending" ]; then
            fail_gate "prebuild에서는 build_artifact_hash가 pending이어야 합니다."
        fi
        ;;
    built)
        if [ "$BUILD_VALIDATION_RESULT" != "passed" ]; then
            fail_gate "built에서는 build_validation이 passed여야 합니다."
        fi
        validate_identifier "build_run_id" "$BUILD_RUN_ID"
        RUN_ID_CANONICAL=$(printf '%s' "$BUILD_RUN_ID" | LC_ALL=C tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$RUN_ID_CANONICAL" in
            pending|none|n/a|not_run|unknown|tbd|-)
                fail_gate "built에서는 build_run_id에 실제 실행 ID가 필요합니다."
                ;;
        esac

        validate_identifier "build_artifact_hash" "$BUILD_ARTIFACT_HASH"
        if [ "$BUILD_ARTIFACT_HASH" = "pending" ] || [ "${#BUILD_ARTIFACT_HASH}" -ne 64 ]; then
            fail_gate "built에서는 build_artifact_hash가 lowercase SHA-256이어야 합니다."
        fi
        case "$BUILD_ARTIFACT_HASH" in
            *[!0123456789abcdef]*)
                fail_gate "built에서는 build_artifact_hash가 lowercase SHA-256이어야 합니다."
                ;;
        esac
        ;;
esac

printf '%s\n' "[마일스톤 검증] phase=$PHASE milestone=$MILESTONE_ID change=$CHANGE_ID authority=$BUILD_AUTHORITY"
exit 0

#!/bin/bash

# ==============================================================================
# [기능]: 프로필 기반 Unity 하네스 린터의 Bash 진입점을 제공합니다.
# [작성자]: 윤승종
# ==============================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
AGENTS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
PROFILE_SCRIPT="$AGENTS_ROOT/scripts/shared/profile.sh"
LINT_SCRIPT="$AGENTS_ROOT/scripts/shared/lint.sh"
SCHEMA_PATH="$AGENTS_ROOT/config/profile-schema.conf"

PROJECT_ROOT=$(cd "$AGENTS_ROOT/.." && pwd)
PROFILE_PATH=""
OUTPUT_FORMAT="human"

print_usage()
{
    printf '%s\n' "사용법: bash .agents/scripts/lint/check-harness.sh [--project-root 경로] [--profile 경로] [--format human|machine]"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --project-root)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' "--project-root 뒤에 값을 지정해야 합니다." >&2
                exit 3
            fi
            PROJECT_ROOT=$2
            shift 2
            ;;
        --profile)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' "--profile 뒤에 값을 지정해야 합니다." >&2
                exit 3
            fi
            PROFILE_PATH=$2
            shift 2
            ;;
        --format)
            if [ "$#" -lt 2 ]; then
                printf '%s\n' "--format 뒤에 값을 지정해야 합니다." >&2
                exit 3
            fi
            OUTPUT_FORMAT=$2
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            printf '%s\n' "알 수 없는 인자입니다: $1" >&2
            print_usage >&2
            exit 3
            ;;
    esac
done

case "$OUTPUT_FORMAT" in
    human|machine)
        ;;
    *)
        printf '%s\n' "지원하지 않는 출력 형식입니다: $OUTPUT_FORMAT" >&2
        exit 3
        ;;
esac

if [ -z "$PROFILE_PATH" ]; then
    PROFILE_PATH="$PROJECT_ROOT/.agents/config/project-profile.conf"
fi

if [ ! -f "$PROFILE_SCRIPT" ] || [ ! -r "$PROFILE_SCRIPT" ] || [ ! -f "$LINT_SCRIPT" ] || [ ! -r "$LINT_SCRIPT" ] || [ ! -f "$SCHEMA_PATH" ] || [ ! -r "$SCHEMA_PATH" ]; then
    printf '%s\n' "[하네스 린트] 필수 스크립트 또는 스키마를 읽을 수 없습니다." >&2
    exit 4
fi

. "$PROFILE_SCRIPT"
. "$LINT_SCRIPT"

human_unescape()
{
    local value=$1

    value=${value//%0A/\\n}
    value=${value//%0D/\\r}
    value=${value//%7C/|}
    value=${value//%25/%}
    HUMAN_UNESCAPED_VALUE=$value
}

LINT_OUTPUT=$(lint_project "$PROJECT_ROOT" "$PROFILE_PATH" "$SCHEMA_PATH" 2>&1)
LINT_STATUS=$?

if [ "$OUTPUT_FORMAT" = "machine" ]; then
    if [ -n "$LINT_OUTPUT" ]; then
        printf '%s\n' "$LINT_OUTPUT"
    fi
    exit "$LINT_STATUS"
fi

ERROR_COUNT=0
WARNING_COUNT=0
while IFS='|' read -r rule_id severity relative_path line_number message || [ -n "$rule_id$severity$relative_path$line_number$message" ]; do
    if [ -z "$rule_id" ]; then
        continue
    fi
    case "$severity" in
        error)
            ERROR_COUNT=$((ERROR_COUNT + 1))
            severity_label="오류"
            ;;
        *)
            WARNING_COUNT=$((WARNING_COUNT + 1))
            severity_label="경고"
            ;;
    esac
    human_unescape "$relative_path"
    display_path=$HUMAN_UNESCAPED_VALUE
    human_unescape "$message"
    display_message=$HUMAN_UNESCAPED_VALUE
    printf '[%s] %s %s:%s - %s\n' "$severity_label" "$rule_id" "$display_path" "$line_number" "$display_message"
done <<LINT_OUTPUT_EOF
$LINT_OUTPUT
LINT_OUTPUT_EOF

printf '[요약] 오류 %s건, 경고 %s건\n' "$ERROR_COUNT" "$WARNING_COUNT"
exit "$LINT_STATUS"

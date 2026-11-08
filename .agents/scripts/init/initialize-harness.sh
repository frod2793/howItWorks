#!/bin/bash

# ==============================================================================
# [기능]: Unity 하네스 감지, 재감지, 프로필 확정 진입점을 제공합니다.
# [작성자]: 윤승종
# ==============================================================================

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
AGENTS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
PROFILE_SCRIPT="$AGENTS_ROOT/scripts/shared/profile.sh"
DETECT_SCRIPT="$AGENTS_ROOT/scripts/shared/detect.sh"
SCHEMA_PATH="$AGENTS_ROOT/config/profile-schema.conf"
SIGNATURES_PATH="$AGENTS_ROOT/config/detection-signatures.conf"

print_usage()
{
    printf '%s\n' '사용법: bash .agents/scripts/init/initialize-harness.sh [--project-root <path>] [--confirm|--redetect]'
}

print_error()
{
    printf '%s\n' "[초기화] $1" >&2
}

prepare_output_directory()
{
    local directory_path=$1

    if [ -L "$directory_path" ]; then
        print_error "출력 디렉터리로 심볼릭 링크를 사용할 수 없습니다: $directory_path"
        return 2
    fi
    if [ -e "$directory_path" ] && [ ! -d "$directory_path" ]; then
        print_error "출력 경로가 디렉터리가 아닙니다: $directory_path"
        return 2
    fi
    if [ ! -d "$directory_path" ] && ! mkdir "$directory_path" 2>/dev/null; then
        print_error "출력 디렉터리를 만들 수 없습니다: $directory_path"
        return 2
    fi

    return 0
}

if [ ! -f "$PROFILE_SCRIPT" ] || [ ! -r "$PROFILE_SCRIPT" ]; then
    print_error "profile.sh를 읽을 수 없습니다: $PROFILE_SCRIPT"
    exit 4
fi
if [ ! -f "$DETECT_SCRIPT" ] || [ ! -r "$DETECT_SCRIPT" ]; then
    print_error "detect.sh를 읽을 수 없습니다: $DETECT_SCRIPT"
    exit 4
fi

. "$PROFILE_SCRIPT"
. "$DETECT_SCRIPT"
detect_install_signal_handlers

PROJECT_START=$(pwd)
ACTION=detect
HAS_PROJECT_ROOT=0

while [ "$#" -gt 0 ]; do
    case "$1" in
        --project-root)
            if [ "$#" -lt 2 ]; then
                print_error "--project-root 뒤에 경로를 지정해야 합니다."
                print_usage >&2
                exit 3
            fi
            case "$2" in
                --*)
                    print_error "--project-root 뒤에 경로를 지정해야 합니다."
                    print_usage >&2
                    exit 3
                    ;;
            esac
            if [ "$HAS_PROJECT_ROOT" -eq 1 ]; then
                print_error "--project-root는 한 번만 사용할 수 있습니다."
                exit 3
            fi
            PROJECT_START=$2
            HAS_PROJECT_ROOT=1
            shift 2
            ;;
        --confirm)
            if [ "$ACTION" != "detect" ]; then
                print_error "--confirm과 --redetect는 함께 사용할 수 없습니다."
                exit 3
            fi
            ACTION=confirm
            shift
            ;;
        --redetect)
            if [ "$ACTION" != "detect" ]; then
                print_error "--confirm과 --redetect는 함께 사용할 수 없습니다."
                exit 3
            fi
            ACTION=redetect
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            print_error "알 수 없는 인자입니다: $1"
            print_usage >&2
            exit 3
            ;;
    esac
done

PROJECT_ROOT=$(find_unity_project_root "$PROJECT_START")
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    exit "$STATUS"
fi

PROJECT_AGENTS_ROOT="$PROJECT_ROOT/.agents"
CONFIG_DIRECTORY="$PROJECT_AGENTS_ROOT/config"
REPORT_DIRECTORY="$PROJECT_AGENTS_ROOT/reports"
PROFILE_PATH="$CONFIG_DIRECTORY/project-profile.conf"
CANDIDATE_PATH="$CONFIG_DIRECTORY/project-profile.candidate.conf"
REPORT_PATH="$REPORT_DIRECTORY/detection-report.md"

prepare_output_directory "$PROJECT_AGENTS_ROOT" || exit $?
prepare_output_directory "$CONFIG_DIRECTORY" || exit $?

if [ "$ACTION" = "confirm" ]; then
    if [ ! -f "$PROFILE_PATH" ] || [ ! -r "$PROFILE_PATH" ]; then
        print_error "확정할 project-profile.conf를 읽을 수 없습니다: $PROFILE_PATH"
        exit 3
    fi

    profile_load "$PROFILE_PATH" "$SCHEMA_PATH" >/dev/null 2>&1
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        print_error "프로필 스키마 검증에 실패하여 확정할 수 없습니다: $PROFILE_PATH"
        exit 3
    fi

    profile_confirm "$PROFILE_PATH" "$SCHEMA_PATH" >/dev/null 2>&1
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        print_error "프로필 상태를 원자적으로 확정할 수 없습니다: $PROFILE_PATH"
        exit "$STATUS"
    fi

    printf '%s\n' "[초기화] 프로필 상태를 confirmed로 확정했습니다: $PROFILE_PATH"
    exit 0
fi

prepare_output_directory "$REPORT_DIRECTORY" || exit $?

if [ -e "$PROFILE_PATH" ]; then
    if [ ! -f "$PROFILE_PATH" ] || [ ! -r "$PROFILE_PATH" ]; then
        print_error "기존 프로필을 읽을 수 없습니다: $PROFILE_PATH"
        exit 3
    fi

    profile_load "$PROFILE_PATH" "$SCHEMA_PATH" >/dev/null 2>&1
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        print_error "기존 프로필 스키마 검증에 실패했습니다: $PROFILE_PATH"
        exit 3
    fi

    CONFIRMATION_STATUS=$(profile_get "confirmation_status")
    if [ "$CONFIRMATION_STATUS" = "confirmed" ] && [ "$ACTION" = "detect" ]; then
        printf '%s\n' "[초기화] 기존 확정 프로필을 보존했습니다: $PROFILE_PATH"
        printf '%s\n' '[초기화] 비교 후보가 필요하면 --redetect를 사용하십시오.'
        exit 0
    fi
fi

if [ "$ACTION" = "redetect" ]; then
    if [ -f "$PROFILE_PATH" ] && [ -r "$PROFILE_PATH" ]; then
        detect_project "$PROJECT_ROOT" "$CANDIDATE_PATH" "$REPORT_PATH" "$SCHEMA_PATH" "$SIGNATURES_PATH" "$PROFILE_PATH"
    else
        detect_project "$PROJECT_ROOT" "$CANDIDATE_PATH" "$REPORT_PATH" "$SCHEMA_PATH" "$SIGNATURES_PATH"
    fi
    STATUS=$?
    if [ "$STATUS" -ne 0 ]; then
        exit "$STATUS"
    fi

    printf '%s\n' "[초기화] 재감지 후보 프로필을 생성했습니다: $CANDIDATE_PATH"
    exit 0
fi

detect_project "$PROJECT_ROOT" "$PROFILE_PATH" "$REPORT_PATH" "$SCHEMA_PATH" "$SIGNATURES_PATH"
STATUS=$?
if [ "$STATUS" -ne 0 ]; then
    exit "$STATUS"
fi

printf '%s\n' '[초기화] 감지 결과는 pending입니다. 보고서를 검토한 뒤 --confirm을 실행하십시오.'
exit 0

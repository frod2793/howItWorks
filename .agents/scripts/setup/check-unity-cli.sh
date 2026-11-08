#!/bin/bash

# ==============================================================================
# [기능]: Unity CLI 설치 상태를 읽기 전용으로 확인합니다. 설치·갱신·네트워크 접근은 수행하지 않습니다.
# [작성자]: 윤승종
# ==============================================================================

set -u

MODE="check"
DEFAULT_INSTALL_PATH="$HOME/.unity/bin/unity"

print_usage()
{
    printf '%s\n' "사용법: bash .agents/scripts/setup/check-unity-cli.sh [--check|--preflight] [--project-root <경로>]"
    printf '%s\n' "--project-root는 다른 검사 스크립트와의 호출 규약 통일용이며 검사 자체는 머신 전역입니다."
}

print_status()
{
    printf '%s\n' "[Unity CLI] $1"
}

print_error()
{
    printf '%s\n' "[Unity CLI] $1" >&2
}

while [ $# -gt 0 ]; do
    case "$1" in
        --check)
            MODE="check"
            ;;
        --preflight)
            MODE="preflight"
            ;;
        --project-root)
            shift
            if [ $# -eq 0 ]; then
                print_error "--project-root 값이 없습니다."
                exit 2
            fi
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            print_error "알 수 없는 인자입니다: $1"
            print_usage
            exit 2
            ;;
    esac
    shift
done

UNITY_CLI_PATH=""
if command -v unity >/dev/null 2>&1; then
    UNITY_CLI_PATH=$(command -v unity)
elif [ -x "$DEFAULT_INSTALL_PATH" ]; then
    UNITY_CLI_PATH="$DEFAULT_INSTALL_PATH"
fi

if [ -z "$UNITY_CLI_PATH" ]; then
    print_status "상태: missing"
    print_status "Unity CLI가 설치되어 있지 않습니다. 설치는 사용자가 현재 요청한 경우에만 수행합니다."
    exit 1
fi

UNITY_CLI_VERSION=$("$UNITY_CLI_PATH" --version 2>/dev/null)
UNITY_CLI_VERSION_STATUS=$?
if [ "$UNITY_CLI_VERSION_STATUS" -ne 0 ] || [ -z "$UNITY_CLI_VERSION" ]; then
    print_status "상태: broken"
    print_status "경로: $UNITY_CLI_PATH"
    print_error "unity --version 실행에 실패했습니다. 복구는 사용자가 현재 요청한 경우에만 수행합니다."
    exit 1
fi

print_status "상태: installed"
print_status "경로: $UNITY_CLI_PATH"
print_status "버전: $UNITY_CLI_VERSION"

if [ "$MODE" = "preflight" ]; then
    if "$UNITY_CLI_PATH" doctor --ci --no-banner --non-interactive; then
        print_status "preflight: passed"
    else
        print_status "preflight: failed"
        print_error "unity doctor --ci 진단이 실패했습니다. 빌드·테스트 실행 전에 환경을 복구해야 합니다."
        exit 1
    fi
fi

exit 0

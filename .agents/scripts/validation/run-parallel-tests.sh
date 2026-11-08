#!/bin/bash

# ==============================================================================
# [기능]: 여러 Unity 실행 루트(worktree)의 테스트를 프로세스 예산 안에서 병렬 실행하고 NUnit 증거를 수집합니다.
# [작성자]: 윤승종
# 사용자가 해당 테스트 실행을 현재 요청한 경우에만 사용합니다. 결과는 증거 입력이며 권위는 기존 검증 정책을 따릅니다.
# ==============================================================================

set -u

MODE=""
MAX_PROCS=2
HARD_CAP=4
SKIP_PREFLIGHT=0
DEFAULT_INSTALL_PATH="$HOME/.unity/bin/unity"

print_usage()
{
    printf '%s\n' "사용법: bash .agents/scripts/validation/run-parallel-tests.sh --mode EditMode|PlayMode [--max-procs N] [--skip-preflight] <프로젝트루트> [<프로젝트루트> ...]"
    printf '%s\n' "각 프로젝트루트는 ProjectSettings/ProjectVersion.txt를 포함한 Unity 실행 루트의 물리 경로여야 합니다."
}

print_error()
{
    printf '%s\n' "[병렬 테스트] $1" >&2
}

print_status()
{
    printf '%s\n' "[병렬 테스트] $1"
}

ROOTS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --mode)
            shift
            [ $# -gt 0 ] || { print_error "--mode 값이 없습니다."; exit 3; }
            MODE="$1"
            ;;
        --max-procs)
            shift
            [ $# -gt 0 ] || { print_error "--max-procs 값이 없습니다."; exit 3; }
            MAX_PROCS="$1"
            ;;
        --skip-preflight)
            SKIP_PREFLIGHT=1
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        -*)
            print_error "알 수 없는 인자입니다: $1"
            print_usage
            exit 3
            ;;
        *)
            ROOTS[${#ROOTS[@]}]="$1"
            ;;
    esac
    shift
done

case "$MODE" in
    EditMode|PlayMode) ;;
    *)
        print_error "--mode는 EditMode 또는 PlayMode여야 합니다."
        exit 3
        ;;
esac

case "$MAX_PROCS" in
    ''|*[!0-9]*)
        print_error "--max-procs는 양의 정수여야 합니다."
        exit 3
        ;;
esac
if [ "$MAX_PROCS" -lt 1 ]; then
    MAX_PROCS=1
fi
if [ "$MAX_PROCS" -gt "$HARD_CAP" ]; then
    print_error "동시 Unity 프로세스 예산은 최대 ${HARD_CAP}개입니다. --max-procs를 ${HARD_CAP}로 낮춥니다."
    MAX_PROCS=$HARD_CAP
fi

if [ ${#ROOTS[@]} -eq 0 ]; then
    print_error "실행할 프로젝트루트가 없습니다."
    print_usage
    exit 3
fi

UNITY_CLI_PATH=""
if command -v unity >/dev/null 2>&1; then
    UNITY_CLI_PATH=$(command -v unity)
elif [ -x "$DEFAULT_INSTALL_PATH" ]; then
    UNITY_CLI_PATH="$DEFAULT_INSTALL_PATH"
fi
if [ -z "$UNITY_CLI_PATH" ]; then
    print_error "Unity CLI가 설치되어 있지 않습니다. 설치는 사용자가 현재 요청한 경우에만 수행합니다."
    exit 1
fi

PHYSICAL_ROOTS=()
for root in "${ROOTS[@]}"; do
    if [ ! -d "$root" ] || [ ! -f "$root/ProjectSettings/ProjectVersion.txt" ]; then
        print_error "Unity 실행 루트가 아닙니다: $root"
        exit 4
    fi
    physical=$(cd "$root" && pwd -P) || { print_error "물리 경로를 확정할 수 없습니다: $root"; exit 4; }
    for seen in ${PHYSICAL_ROOTS[@]+"${PHYSICAL_ROOTS[@]}"}; do
        # -ef also catches case-only and symlink aliases of the same directory.
        if [ "$seen" -ef "$physical" ]; then
            print_error "같은 물리 실행 루트가 중복되었습니다(증거·로그 경로 충돌): $root -> $seen"
            exit 4
        fi
    done
    PHYSICAL_ROOTS[${#PHYSICAL_ROOTS[@]}]="$physical"
done
ROOTS=("${PHYSICAL_ROOTS[@]}")

if [ "$SKIP_PREFLIGHT" -eq 0 ]; then
    if ! "$UNITY_CLI_PATH" doctor --ci --no-banner --non-interactive; then
        print_error "unity doctor --ci preflight가 실패했습니다. 환경 복구 후 다시 실행합니다."
        exit 1
    fi
fi

# ponytail: 같은 프로젝트 내 shard 분할(unity test --shard)은 미지원. worktree 단위 병렬만 제공하며 shard 자동화가 필요하면 확장.
PIDS=()
JOB_ROOTS=()
JOB_EVIDENCE=()
FAIL_COUNT=0
NEXT_WAIT=0

wait_one()
{
    local pid=${PIDS[$NEXT_WAIT]}
    local job_root=${JOB_ROOTS[$NEXT_WAIT]}
    local evidence=${JOB_EVIDENCE[$NEXT_WAIT]}
    local code=0

    wait "$pid" || code=$?
    if [ "$code" -eq 0 ] && [ -s "$evidence" ]; then
        print_status "passed: $job_root evidence=$evidence"
    elif [ "$code" -eq 0 ]; then
        print_status "not_verified(NUnit XML 없음): $job_root evidence=$evidence"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    else
        print_status "failed(exit=$code): $job_root evidence=$evidence"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
    NEXT_WAIT=$((NEXT_WAIT + 1))
}

for root in "${ROOTS[@]}"; do
    while [ $(( ${#PIDS[@]} - NEXT_WAIT )) -ge "$MAX_PROCS" ]; do
        wait_one
    done

    report_dir="$root/.agents/reports"
    if [ ! -d "$root/.agents" ]; then
        report_dir="$root"
    fi
    mkdir -p "$report_dir" || { print_error "리포트 디렉터리를 만들 수 없습니다: $report_dir"; exit 4; }
    evidence_path="$report_dir/parallel-test-$MODE.xml"
    log_path="$report_dir/parallel-test-$MODE.log"

    rm -f "$evidence_path" || { print_error "이전 NUnit XML을 지울 수 없습니다: $evidence_path"; exit 4; }
    print_status "start: $root mode=$MODE"
    "$UNITY_CLI_PATH" test "$root" --mode "$MODE" --output "$evidence_path" \
        --no-banner --non-interactive --quiet > "$log_path" 2>&1 &
    PIDS[${#PIDS[@]}]=$!
    JOB_ROOTS[${#JOB_ROOTS[@]}]="$root"
    JOB_EVIDENCE[${#JOB_EVIDENCE[@]}]="$evidence_path"
done

while [ "$NEXT_WAIT" -lt ${#PIDS[@]} ]; do
    wait_one
done

if [ "$FAIL_COUNT" -gt 0 ]; then
    print_error "실패했거나 NUnit XML이 없는 실행 루트가 ${FAIL_COUNT}개 있습니다. 각 로그와 NUnit XML을 확인해 기록합니다."
    exit 1
fi

print_status "모든 실행 루트 통과. NUnit XML을 검증 기록의 입력으로 사용합니다."
exit 0

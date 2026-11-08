#!/bin/bash

# ==============================================================================
# [기능]: PreToolUse hook — .agents 삭제와 관리 파일의 직접 변조를 차단합니다.
# [작성자]: 윤승종
# ==============================================================================
# 근거 사례: docs/troubleshooting/2026-08-27-harness-recopy-local-state-loss.md
# 하네스 갱신은 보호 필터 동기화(rsync -a --delete + 로컬 상태 exclude 또는 H+P 필터)만 허용합니다.

if ! command -v python3 >/dev/null 2>&1; then
    echo "하네스 보호: Python 3가 없어 명령을 검사할 수 없습니다. Python 3 설치 후 재시도하십시오." >&2
    exit 2
fi

python3 "$(dirname "$0")/protect-agents-dir.py"
[ "$?" -eq 0 ] && exit 0
exit 2

#!/bin/bash

# ==============================================================================
# [기능]: 커밋 전 자동 실행되어 코딩 규칙 및 아키텍처 위반 사항을 종합 검증하는 Git pre-commit 스크립트
# [작성자]: 윤승종
# ==============================================================================

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

echo "======================================================================"
echo "🛡️  Git 커밋 전 자동 검증 (Pre-commit Checks) 실행 시작"
echo "======================================================================"

# 1. 아키텍처 및 제약 린터 실행
bash .agents/scripts/lint/check-architecture.sh
LINT_EXIT=$?

if [ $LINT_EXIT -ne 0 ]; then
    echo -e "${RED}🚨 아키텍처 검증에 실패했습니다. 커밋을 차단합니다.${NC}"
    exit 1
fi

# 2. 추가 검사: 스테이징된 C# 파일 추출
STAGED_CS_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep "\.cs$")

if [ -z "$STAGED_CS_FILES" ]; then
    echo -e "${GREEN}✅ 변경되거나 추가된 C# 소스 코드가 없습니다. 검증 통과.${NC}"
    exit 0
fi

VIOLATION_FOUND=0

echo -e "\n🔍 스테이징된 파일 대상 추가 규칙 검증 시작..."

for FILE in $STAGED_CS_FILES; do
    if [ ! -f "$FILE" ]; then
        continue
    fi
    
    # 2.1. private/protected 필드 m_ 네이밍 룰 체크
    # [SerializeField] 또는 private/protected 선언 중 m_ 접두사가 없는 카멜케이스 형태의 변수 선언 탐색
    BAD_FIELDS=$(grep -nE "^\s*(private|protected|\[SerializeField\])\s+[a-zA-Z0-9_<>]+\s+[a-z][a-zA-Z0-9_]*\s*;" "$FILE" 2>/dev/null)
    if [ ! -z "$BAD_FIELDS" ]; then
        echo -e "${RED}❌ [위반] $FILE - private/protected/SerializeField 필드는 m_ 접두사를 사용해야 합니다:${NC}"
        echo "$BAD_FIELDS"
        VIOLATION_FOUND=1
    fi

    # 2.2. 로그 메시지 한글 규칙 체크
    # Debug.Log 등으로 영어 문자만 출력하는 형태 탐색 (단순 예시 검출)
    ENG_LOGS=$(grep -nE "Debug\.Log(Warning|Error)?\(\s*\"[a-zA-Z0-9\s\!]*\"\s*\)" "$FILE" 2>/dev/null)
    if [ ! -z "$ENG_LOGS" ]; then
        echo -e "${YELLOW}⚠️  [경고] $FILE - 로그 메시지는 한글 작성이 원칙입니다 (클래스명 접두사 포함):${NC}"
        echo "$ENG_LOGS"
    fi

    # 2.3. 클래스 헤더 XML 주석 존재 여부 검사
    # 윤승종 작성자 표기가 주석에 있는지 확인
    HAS_AUTHOR=$(grep -i "작성자.*윤승종" "$FILE" 2>/dev/null)
    if [ -z "$HAS_AUTHOR" ]; then
        echo -e "${YELLOW}⚠️  [경고] $FILE - 파일 헤더나 클래스 XML 주석에 '작성자: 윤승종' 표기가 누락되었을 수 있습니다.${NC}"
    fi
done

echo -e "\n======================================================================"
if [ $VIOLATION_FOUND -eq 0 ]; then
    echo -e "${GREEN}🎉 모든 커밋 규칙 검증 성공! 커밋을 진행합니다.${NC}"
    exit 0
else
    echo -e "${RED}🚨 일부 코딩 표준 위반 사항이 존재합니다. 커밋을 취소합니다.${NC}"
    exit 1
fi
echo "======================================================================"

#!/bin/bash

# ==============================================================================
# [기능]: Unity 프로젝트 내 아키텍처 규칙 및 성능, 안전성 제약 위반을 자동 검출하는 스크립트
# [작성자]: 윤승종
# ==============================================================================

# 실행 위치에 따라 Assets/Scripts 경로 자동 탐색
if [ -d "Assets/Scripts" ]; then
    TARGET_DIR="Assets/Scripts"
elif [ -d "../../Assets/Scripts" ]; then
    TARGET_DIR="../../Assets/Scripts"
else
    TARGET_DIR="Assets/Scripts"
fi

EXIT_CODE=0

echo "======================================================================"
echo "[Linter] Unity 아키텍처 및 안전성 제약 사항 검증 시작"
echo "대상 디렉토리: $TARGET_DIR"
echo "======================================================================"

if [ ! -d "$TARGET_DIR" ]; then
    echo "⚠️  [경고] $TARGET_DIR 디렉토리가 존재하지 않습니다. 스캔을 건너뜁니다."
    exit 0
fi

# 색상 정의
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# ------------------------------------------------------------------------------
# 1. View -> Model 직접 참조 검출
# ------------------------------------------------------------------------------
echo -e "\n🔍 1. View -> Model 직접 참조 검출 중..."
VIOLATIONS=$(grep -rn "using.*\.Models;" "$TARGET_DIR/Views" 2>/dev/null)
if [ ! -z "$VIOLATIONS" ]; then
    echo -e "${RED}❌ [위반] View에서 Models 네임스페이스를 직접 reference하고 있습니다!${NC}"
    echo "$VIOLATIONS"
    EXIT_CODE=1
else
    echo -e "${GREEN}✅ View -> Model 직접 참조 없음 (단방향 MVVM 준수)${NC}"
fi

# ------------------------------------------------------------------------------
# 2. 싱글톤(Singleton) 패턴 사용 검출
# ------------------------------------------------------------------------------
echo -e "\n🔍 2. 싱글톤 패턴(static Instance) 검출 중..."
# 코어/플러그인/서드파티가 아닌 일반 도메인 스크립트에서 static Instance 패턴 검사
VIOLATIONS=$(grep -rn "public static.*Instance" "$TARGET_DIR" --exclude-dir="Core" --exclude-dir="Plugins" 2>/dev/null)
if [ ! -z "$VIOLATIONS" ]; then
    echo -e "${RED}❌ [위반] 싱글톤 패턴이 검출되었습니다. VContainer DI를 적용하십시오!${NC}"
    echo "$VIOLATIONS"
    EXIT_CODE=1
else
    echo -e "${GREEN}✅ 싱글톤 패턴 검출 안 됨 (No Singleton 준수)${NC}"
fi

# ------------------------------------------------------------------------------
# 3. Fake Null 연산자 사용 검출
# ------------------------------------------------------------------------------
echo -e "\n🔍 3. UnityEngine.Object 상속 타입에 대한 Fake Null(?. 또는 ??) 사용 검출 중..."
# UnityEngine.Object 파생 클래스를 직접 구분하긴 어려우므로 .cs 파일 내의 ?. 와 ?? 사용 양태를 경고 수준으로 수집
VIOLATIONS=$(grep -rnE "\b(m_[a-zA-Z0-9_]*|button|text|image|slider)\s*\?\?\s*" "$TARGET_DIR" 2>/dev/null)
VIOLATIONS_COND=$(grep -rnE "\b(m_[a-zA-Z0-9_]*|button|text|image|slider)\?\." "$TARGET_DIR" 2>/dev/null)

if [ ! -z "$VIOLATIONS" ] || [ ! -z "$VIOLATIONS_COND" ]; then
    echo -e "${YELLOW}⚠️  [경고] UnityEngine.Object 파생 필드로 추정되는 변수에 ?. 또는 ?? 연산자가 사용되었습니다.${NC}"
    echo -e "${YELLOW}   (Unity Fake Null 안정성 이슈 방지를 위해 명시적 null 체크 '!= null'를 권장합니다.)${NC}"
    [ ! -z "$VIOLATIONS" ] && echo "$VIOLATIONS"
    [ ! -z "$VIOLATIONS_COND" ] && echo "$VIOLATIONS_COND"
else
    echo -e "${GREEN}✅ 특수 Null 연산자 오용 의심 사례 없음${NC}"
fi

# ------------------------------------------------------------------------------
# 4. Update 루프 내 new 할당 검출
# ------------------------------------------------------------------------------
echo -e "\n🔍 4. Update 루프 내 new 키워드 할당 검출 중..."
# Update() 계열 함수 블록 내부에 new가 쓰였는지 간단한 패턴 분석
VIOLATIONS=$(awk '
/void (Update|FixedUpdate|LateUpdate)\(\)/ {
    in_update = 1;
    file_info = FILENAME ":" FNR " " $0;
    brace_depth = 0;
}
in_update {
    if ($0 ~ /{/) brace_depth++;
    if ($0 ~ /}/) brace_depth--;
    if ($0 ~ /\bnew\b/ && !($0 ~ /new\s+(Vector3|Vector2|Vector4|Quaternion|Color)/)) {
        print FILENAME ":" FNR ": [할당 의심] " $0;
    }
    if (brace_depth == 0 && $0 ~ /}/) {
        in_update = 0;
    }
}
' $(find "$TARGET_DIR" -name "*.cs" 2>/dev/null) 2>/dev/null)

if [ ! -z "$VIOLATIONS" ]; then
    echo -e "${RED}❌ [위반] Update 루프 내에서 가비지 컬렉터(GC) 할당을 유발하는 new 연산이 감지되었습니다!${NC}"
    echo "$VIOLATIONS"
    EXIT_CODE=1
else
    echo -e "${GREEN}✅ Update 루프 내 new 할당 없음 (Zero Allocation 준수)${NC}"
fi

# ------------------------------------------------------------------------------
# 5. 코루틴 사용 검출
# ------------------------------------------------------------------------------
echo -e "\n🔍 5. 코루틴(StartCoroutine, IEnumerator) 사용 검출 중..."
VIOLATIONS_START=$(grep -rn "StartCoroutine" "$TARGET_DIR" 2>/dev/null)
VIOLATIONS_ENUM=$(grep -rn "IEnumerator" "$TARGET_DIR" --exclude-dir="Tests" 2>/dev/null)

if [ ! -z "$VIOLATIONS_START" ] || [ ! -z "$VIOLATIONS_ENUM" ]; then
    echo -e "${RED}❌ [위반] 코루틴 관련 키워드가 감지되었습니다. UniTask를 도입하십시오!${NC}"
    [ ! -z "$VIOLATIONS_START" ] && echo "$VIOLATIONS_START"
    [ ! -z "$VIOLATIONS_ENUM" ] && echo "$VIOLATIONS_ENUM"
    EXIT_CODE=1
else
    echo -e "${GREEN}✅ 코루틴 사용 안 함 (UniTask 표준화 준수)${NC}"
fi

echo -e "\n======================================================================"
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}🎉 모든 아키텍처 규칙 검증 완료! (패스)${NC}"
else
    echo -e "${RED}🚨 아키텍처 규칙 위반이 존재합니다. 코드를 수정한 뒤 다시 시도해 주십시오.${NC}"
fi
echo "======================================================================"

exit $EXIT_CODE

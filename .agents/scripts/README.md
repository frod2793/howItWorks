# 자동 검증 스크립트 가이드 (Scripts Guide)

이 디렉토리는 AI 에이전트와 인간 개발자가 코드를 커밋하기 전, 프로젝트 아키텍처 규칙과 안전 규칙을 자동으로 검증할 수 있도록 돕는 쉘 스크립트들을 보관합니다.

---

## 1. 스크립트 상세 설명

### check-architecture.sh
- **위치**: `.agents/scripts/lint/check-architecture.sh`
- **역할**: 정적 분석을 통해 프로젝트의 5대 금지 규칙을 모니터링합니다.
  1. View가 Model 영역의 네임스페이스를 직접 reference하는지 여부 (단방향 MVVM 위반)
  2. 싱글톤 패턴(`Instance`) 선언 탐색
  3. UnityEngine.Object에 특수 null 연산자(`?.`, `??`)를 적용한 오용 의심 탐색
  4. Update 루프 내에서 가비지 컬렉터(GC) 할당을 유발하는 무거운 객체 `new` 생성 검사
  5. 코루틴 지양 및 UniTask 표준화 규칙에 의거, 코루틴 관련 키워드 탐색

### pre-commit-checks.sh
- **위치**: `.agents/scripts/ci/pre-commit-checks.sh`
- **역할**: Git 커밋이 발생하기 직전 변경 사항을 자동 스캔하여 다음 요소를 추가 확인합니다.
  - private / protected 필드의 `m_` 접두사 네이밍 규칙 검사
  - 로그 메시지의 영문 노출 및 클래스명 접두사 누락 경고
  - 신규 파일에 대한 작성자 명시(작성자: 윤승종) 누락 경고

---

## 2. 사용 방법

### 수동 실행
원하는 검사 스크립트를 로컬 터미널에서 직접 실행할 수 있습니다.
```bash
# 아키텍처 및 MVVM 규칙 단독 검증
bash .agents/scripts/lint/check-architecture.sh

# 커밋 전 전체 규칙 검증
bash .agents/scripts/ci/pre-commit-checks.sh
```

### Git Hook 연동 (커밋 전 자동 실행)
커밋이 수행될 때 자동으로 검사하고 규칙 위반 시 커밋을 반려하려면, 레포지토리 로드 후 로컬 터미널에서 다음 명령을 실행하여 Git Hook으로 등록하십시오.

```bash
# Git Hooks 디렉토리로 스크립트 링크 또는 복사
cp .agents/scripts/ci/pre-commit-checks.sh .git/hooks/pre-commit

# 실행 권한 부여
chmod +x .git/hooks/pre-commit
```
이 설정을 마치면 `git commit` 명령 시 자동으로 검증이 구동됩니다.

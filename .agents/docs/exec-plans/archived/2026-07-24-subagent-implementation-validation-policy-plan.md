# 서브 에이전트 구현·검증 실행 정책 실행 계획

**상태**: 아카이브 — 범용 하네스 반영 완료, 업무용 오버레이는 별도 하네스에서 관리
**생성일**: 2026-07-24
**담당자**: 메인 에이전트, 구현 서브 에이전트
**관련 설계**: [서브 에이전트 구현·검증 실행 정책 설계](../../design-docs/2026-07-24-subagent-implementation-validation-policy-design.md)

> 이 문서는 당시 두 하네스를 동시에 수정하던 실행 기록입니다. 현재 범용 하네스에서는 공통 정책 반영이 끝났고, 업무용 전용 파일은 이 패키지에 존재하지 않으므로 실행 가능한 `active` 계획으로 사용하지 않습니다. 아카이브 이동은 미실행 검증을 통과로 바꾸지 않습니다.

## 목표와 완료 기준

- **목표**: 범용·업무용 Unity 하네스의 모든 현재 정책 표면에 “사용자 요청 시에만 검증·테스트”, “모든 구현은 규칙을 전달받은 서브 에이전트가 수행”, “구현 후 메인 에이전트 정적 코드 리뷰”를 일관되게 반영한다.
- **완료 기준**: 두 하네스의 최상위 규칙, 온보딩, 검증 정책, 실행계획 템플릿, 업무 SOP·추적성 문서와 문서 계약 기대값이 승인된 설계와 일치하고, 수정한 실행 스크립트의 구문 오류 확인과 메인 에이전트 정적 리뷰가 완료된다.
- **범위 밖**: 기존 Unity 프로젝트 적용, 과거 완료 계획·과거 설계 소급 수정, 하네스 린트·계약 테스트·Unity 테스트·런타임 검증·Player Build·외부 CI 실행, 외부 서비스 작업.

## 현재 실행 권한

| 항목 | 권한 | 이번 작업 처리 |
|------|------|----------------|
| 문서·계약 기대값 구현 | 승인됨 | 반드시 서브 에이전트가 수정 |
| 코드·스크립트 컴파일 또는 구문 오류 확인 | 필수 예외 | 수정된 Bash 스크립트에 `bash -n` 적용 |
| 정적 코드 리뷰 | 필수 | 메인 에이전트가 구현 diff를 독립 검토 |
| 하네스 린트·정적 정책 검사 | 없음 | `not_run` |
| Unit·Integration·계약 테스트 | 없음 | `not_run` |
| Unity EditMode·PlayMode·런타임·시각 검증 | 없음 | `not_run` |
| Player Build·Unity CI | 없음 | `not_run` |
| Jira·Slack·GitHub·이메일·Connector 작업 | 없음 | 수행 금지 |

두 하네스는 Git 저장소가 아닌 공유 템플릿 폴더다. 커밋·워크트리를 만들지 않고, 구현 전 `/tmp` 기준 스냅샷과 구현 후 디렉터리 diff로 변경 범위를 검토한다.

## 공통 구현 전달 계약

각 구현 서브 에이전트에게 다음 항목을 누락 없이 전달한다.

1. 사용자의 세 가지 변경 요구와 승인된 설계
2. 대상 하네스의 `.agents/AGENTS.md`와 연결된 필수 문서
3. Karpathy Guidelines와 최소 변경 원칙
4. 생성·수정 가능한 정확한 파일 목록
5. 관련 없는 파일, 과거 기록, 외부 서비스와 기존 프로젝트 적용 금지
6. 테스트 권한 `none`과 실행 금지 목록
7. 수정 스크립트에 대한 컴파일·구문 오류 확인 방법
8. 변경 파일, 구현 요약, 구문 확인 결과, `not_run`, 남은 위험을 포함한 완료 보고 형식

## 작업 단위

### Task 1: 범용 하네스 정책 동기화

**구현 주체**: 범용 하네스 구현 서브 에이전트

**수정 허용 파일:**

- `.agents/AGENTS.md`
- `.agents/docs/onboarding/agent-quickstart.md`
- `.agents/docs/onboarding/developer-quickstart.md`
- `.agents/docs/onboarding/tech-stack-overview.md`
- `.agents/docs/onboarding/agent-tooling.md`
- `.agents/docs/coding-standards/core/unity-validation.md`
- `.agents/docs/exec-plans/README.md`
- `.agents/docs/exec-plans/_TEMPLATE.md`
- `.agents/scripts/README.md`
- `.agents/tests/README.md`
- `.agents/tests/run-tests.sh`

**구현 내용:**

- 메인·구현 서브 에이전트의 책임과 필수 전달 계약을 최상위 규칙에 명시한다.
- 컴파일·구문 오류 확인을 제외한 모든 검증·테스트는 사용자의 현재 명시적 요청이 있을 때만 실행하도록 통일한다.
- 기존 마일스톤·CI 검증 규격은 삭제하지 않고, 미요청 시 `not_run`이며 통과 상태로 전환할 수 없음을 명시한다.
- 구현 후 메인 에이전트 정적 코드 리뷰와 중요 지적 재작업 절차를 명시한다.
- 온보딩, 도구 사용 시점, 실행계획 템플릿에서 테스트 우선·자동 검증을 무조건 수행하도록 읽히는 문구를 권한 기반 절차로 바꾼다.
- Bash 문서 계약 테스트에 새 정책의 필수 문구 기대값을 추가하되 테스트는 실행하지 않는다.
- `bash -n .agents/tests/run-tests.sh`로 구문 오류만 확인한다.

### Task 2: 업무용 하네스 오버레이 동기화

**선행 조건**: Task 1 구현과 메인 에이전트 리뷰 완료
**구현 주체**: 별도의 업무용 하네스 구현 서브 에이전트

**당시 업무용 하네스 수정 범위:**

- `<업무용-하네스>/AGENTS.md`
- `<업무용-하네스>/docs/onboarding/agent-quickstart.md`
- `<업무용-하네스>/docs/onboarding/developer-quickstart.md`
- `<업무용-하네스>/docs/onboarding/tech-stack-overview.md`
- `<업무용-하네스>/docs/onboarding/agent-tooling.md`
- `<업무용-하네스>/docs/coding-standards/core/unity-validation.md`
- `<업무용-하네스>/docs/exec-plans/README.md`
- `<업무용-하네스>/docs/exec-plans/_TEMPLATE.md`
- `<업무용-하네스>/docs/business-standards/client-code-architecture.md`
- `<업무용-하네스>/docs/business-standards/client-workflow-sop.md`
- `<업무용-하네스>/docs/business-standards/traceability.md`
- `<업무용-하네스>/scripts/README.md`
- `<업무용-하네스>/tests/README.md`
- `<업무용-하네스>/tests/run-tests.sh`
- `<업무용-하네스>/tests/run-workflow-tests.ps1`
- `<업무용-하네스>/tests/run-workflow-tests.sh`

**구현 내용:**

- 범용 하네스의 공유 정책 문서를 업무용 복사본에 동일하게 반영한다.
- 업무 고정 아키텍처·AI 리뷰 70점·CI·QA 품질 게이트를 유지하면서, 사용자가 실행을 요청하지 않은 게이트는 `not_run`이고 상태를 진전시키지 않음을 명시한다.
- 업무 SOP와 추적성 문서에 서브 에이전트 구현, 규칙 전달, 컴파일 오류 확인, 메인 에이전트 리뷰 절차를 연결한다.
- 업무 문서 계약 기대값을 새 정책에 맞춰 갱신하되 테스트는 실행하지 않는다.
- 범용 `.agents` 최종 내용 체크섬을 계산해 업무용 무변경 계약의 기대 해시를 갱신한다.
- 수정된 Bash 스크립트에 `bash -n`을 실행해 구문 오류만 확인한다.

### Task 3: 메인 에이전트 정적 코드 리뷰와 재작업

**검토 항목:**

- 사용자의 세 요구가 두 하네스에 모두 명시됐는가
- 최우선 규칙과 하위 문서 사이에 무조건 테스트·검증 지시가 남아 있지 않은가
- 컴파일 확인과 사용자 요청형 테스트의 경계가 모호하지 않은가
- 기존 CI·QA 품질 기준이 삭제되거나 자동 통과로 바뀌지 않았는가
- 문서 계약 기대값이 구현 문구를 실제로 고정하는가
- 범용과 업무용 공유 정책 문서가 동기화됐는가
- 변경이 허용 파일에 한정되고 과거 기록과 관련 없는 파일을 보존했는가

중요 지적이 있으면 해당 구현을 수행한 같은 서브 에이전트에게 정확한 수정 범위를 전달하고, 수정 후 메인 에이전트가 재리뷰한다.

### Task 4: 완료 보고

- 변경 파일과 핵심 정책을 요약한다.
- Bash 구문 오류 확인 결과를 별도로 보고한다.
- 하네스 린트, 계약 테스트, Unity 테스트, 런타임 검증과 빌드는 `not_run`으로 명시한다.
- 범용 하네스 반영 여부와 현재 요청으로 실행한 계약 테스트 결과를 별도로 기록한다. 업무용 오버레이는 현재 패키지 밖의 별도 범위이므로 `archived/`에 보존하며, 아카이브 상태를 검증 완료나 CI 통과로 해석하지 않는다.

## 변경 이력

| 날짜 | 작성자 | 변경 내용 |
|------|--------|-----------|
| 2026-07-24 | 메인 에이전트 | 사용자 승인 설계를 실행 가능한 서브 에이전트 작업 단위로 구체화 |

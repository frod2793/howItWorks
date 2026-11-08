# Unity 워크트리 전용 Editor·MCP 라우팅 정책 설계

> 2026-09-08 갱신: 이 문서가 다루는 Unity MCP 절차는 Unity CLI·Pipeline으로 전면 대체되었다. 현행 기준은 [Unity linked worktree Editor·CLI 격리](../onboarding/unity-worktree-cli.md)이며, 아래 내용은 설계 이력으로만 보존한다.

**상태**: 사용자 방향 승인, 문서 검토 대기  
**작성일**: 2026-07-26  
**적용 대상**: 범용 Unity 하네스와 Unity 클라이언트 업무용 하네스

## 1. 배경과 목표

Git linked worktree로 Unity 작업을 병렬 수행할 때 셸의 현재 경로와 Unity Editor가 연 프로젝트가 다를 수 있다. 이 상태에서 메인 체크아웃에 연결된 MCP 인스턴스를 사용하면 워크트리 변경이 아닌 다른 프로젝트 상태를 읽거나 수정하고, 잘못된 컴파일·씬·런타임 결과를 증거로 사용할 위험이 있다.

두 하네스는 다음 원칙을 최우선 운영 규칙으로 고정한다.

1. Unity 작업 전에 현재 물리 프로젝트 루트와 linked worktree 여부를 확인한다.
2. linked worktree마다 별도의 Unity Editor와 정확히 하나의 MCP 인스턴스를 사용한다.
3. Editor와 MCP의 `projectRoot`가 현재 워크트리의 물리 루트와 일치하기 전에는 Unity 구현을 시작하지 않는다.
4. 전용 Editor 실행 또는 MCP 바인딩에 실패하면 다른 Editor나 실행 방식으로 우회하지 않고 Unity 구현 전체를 중단해 차단 원인을 보고한다.

## 2. 적용 범위와 범위 밖

### 적용 범위

- Git 일반 체크아웃과 linked worktree 판별
- 워크트리 전용 Unity Editor 선택 또는 신규 실행
- Unity MCP custom tools와 인스턴스 발견
- 병렬 Editor의 MCP 서버 포트 충돌 탐지와 필요 시 포트 재할당
- 물리 `projectRoot` 일치 확인과 인스턴스 고정
- 병렬 작업 중 워크트리·Editor·MCP 격리
- 컴파일 확인과 Unity 직렬화 작업의 실행 권위
- 실패·재연결·도메인 리로드 시 차단 및 복구 절차
- 일반용·업무용 하네스의 정책 문서와 계약 동기화

### 범위 밖

- Unity Editor 설치 또는 버전 자동 다운로드
- Unity Hub, 라이선스와 MCP 패키지의 설치·복구
- 워크트리 생성·삭제·병합 자동화
- 운영체제별 Unity 실행기를 새 Bash·PowerShell 도구로 구현
- 테스트, EditMode·PlayMode, 런타임·시각 검증 또는 Player Build 실행
- 기존 Unity 프로젝트에 현재 템플릿을 소급 적용

## 3. 용어와 불변 조건

| 용어 | 정의 |
|---|---|
| 실행 루트 | 에이전트가 현재 작업하는 Unity 프로젝트의 심볼릭 링크 해소 후 물리 절대 경로 |
| 일반 체크아웃 | Git dir와 common dir가 같고 서브모듈이 아닌 프로젝트 |
| linked worktree | Git dir와 common dir가 다르며 서브모듈이 아닌 프로젝트 |
| 전용 Editor | 실행 루트를 `projectPath`로 열고 다른 체크아웃과 공유하지 않는 Unity Editor 프로세스 |
| 대상 MCP 인스턴스 | MCP가 보고한 `projectRoot`가 실행 루트와 물리적으로 일치하는 정확한 `Name@hash` 인스턴스 |
| MCP endpoint | 전용 Editor의 MCP 서버가 현재 세션에서 사용하는 loopback host와 port |

다음 불변 조건을 유지한다.

- 병렬 Unity 작업은 `워크트리 1개 : Unity Editor 1개 : MCP 인스턴스 1개`다.
- 프로젝트명, 활성 씬, Editor 창 제목 또는 인스턴스 표시 이름만으로 대상을 선택하지 않는다.
- 심볼릭 링크가 포함된 문자열 비교가 아니라 양쪽을 물리 절대 경로로 정규화한 뒤 동일 루트인지 확인한다.
- 다른 체크아웃의 Editor, 첫 번째로 발견된 인스턴스 또는 이전 작업에서 활성화한 인스턴스로 폴백하지 않는다.
- 일반 체크아웃도 MCP `projectRoot`가 실행 루트와 일치하지 않으면 사용할 수 없다.
- MCP port는 충돌 회피와 접속을 위한 endpoint일 뿐 프로젝트 identity가 아니다. port가 달라도 `projectRoot`와 `Name@hash` 확인을 생략하지 않는다.
- 동시에 실행하는 각 전용 Editor는 서로 충돌하지 않는 MCP endpoint를 사용한다.

## 4. 실행 전 판별과 Editor 준비

### 4.1 프로젝트와 worktree 판별

Unity 구현 서브 에이전트를 파견하기 전에 메인 에이전트가 다음 정보를 확정한다.

1. `git rev-parse --show-toplevel`로 Git 프로젝트 루트를 확인한다.
2. 실행 루트를 물리 절대 경로로 정규화한다.
3. `git rev-parse --git-dir`와 `git rev-parse --git-common-dir`을 물리 경로로 비교한다.
4. `git rev-parse --show-superproject-working-tree` 결과가 있으면 linked worktree가 아니라 서브모듈로 처리한다.
5. Git 프로젝트가 아니면 linked worktree 규칙은 적용하지 않되 MCP `projectRoot` 일치 확인은 유지한다.

### 4.2 전용 Editor 선택 또는 실행

- linked worktree에 이미 실행 루트와 일치하는 전용 Editor가 하나만 존재하면 그 Editor를 재사용한다.
- 일치하는 Editor가 없으면 워크트리의 `ProjectSettings/ProjectVersion.txt`를 읽고 해당 버전의 Unity Editor를 새로 연다.
- Editor 실행 시 `projectPath`는 워크트리 실행 루트의 물리 절대 경로여야 한다.
- 메인 체크아웃이나 다른 워크트리의 Editor는 종료하거나 재사용하지 않는다.
- `ProjectVersion.txt` 부재, 해당 Editor 버전 부재, 라이선스·프로세스 실행 실패는 차단 사유다. 임의의 다른 Unity 버전을 사용하지 않는다.

## 5. MCP endpoint 준비와 대상 고정

### 5.1 포트 충돌 처리

기존 endpoint로 각 전용 Editor가 정상 등록되면 port를 변경하지 않는다. 다음 상황에서만 대상 워크트리의 MCP 서버 port 변경을 허용한다.

- 다른 Editor·프로세스가 port를 이미 점유해 bind가 실패함
- 병렬 Editor가 같은 endpoint를 사용해 한 인스턴스만 노출되거나 연결이 반복적으로 끊김
- MCP 서버 또는 인스턴스 정보가 명시적으로 port 충돌을 보고함

port 변경은 다음 경계를 지킨다.

1. 현재 활성 listener와 이미 할당한 워크트리 endpoint를 확인한 뒤 사용 중이 아닌 loopback port를 선택한다. 특정 port를 모든 프로젝트에 하드코딩하지 않는다.
2. 대상 워크트리의 전용 Editor·MCP 서버만 변경하고 메인 체크아웃이나 다른 워크트리의 endpoint를 수정하지 않는다.
3. 공개 네트워크 interface로 listen하지 않는다. 외부 접속은 별도 사용자 승인 없이는 범위 밖이다.
4. 가능한 경우 Editor 세션 또는 프로세스 단위 override를 우선한다.
5. port 설정이 프로젝트 파일에 저장되면 로컬 실행 설정으로 취급해 제품 변경·커밋·병합 범위에서 제외하고 handoff 전에 원복한다. 안전하게 분리하거나 원복할 수 없으면 port를 변경하지 않고 구현을 차단한다.
6. 변경에 재시작이 필요하면 대상 전용 Editor 또는 그 MCP 서버만 재시작한다.
7. 변경 뒤에는 endpoint 접속만으로 성공 처리하지 않고 아래 전체 MCP 발견 절차를 처음부터 다시 수행한다.

사용 가능한 port를 확보하지 못하거나 지원되는 설정 방법을 확인할 수 없으면 임의 설정 파일이나 패키지 원본을 수정하지 않고 차단 사유를 보고한다.

### 5.2 MCP 발견과 인스턴스 선택

Editor 준비 후 다음 순서로 MCP 컨텍스트를 확정한다.

1. `mcpforunity://custom-tools`를 먼저 확인해 현재 프로젝트의 추가 도구를 파악한다.
2. `mcpforunity://instances`에서 현재 등록된 Unity 인스턴스를 조회한다.
3. 각 후보의 `projectRoot`를 실행 루트와 같은 방식으로 물리 경로 정규화한다.
4. 실행 루트와 정확히 일치하는 인스턴스가 하나일 때만 대상 MCP 인스턴스로 채택한다.
5. 정확한 `Name@hash`로 `set_active_instance`를 호출한다.
6. `mcpforunity://project/info`와 `mcpforunity://editor/state`를 다시 읽어 `projectRoot`, `ready_for_tools`, 컴파일과 도메인 리로드 상태를 확인한다.
7. 병렬 에이전트는 도구가 지원할 때 모든 Unity MCP 호출에 대상 `unity_instance`를 명시하고, 리소스 조회 전에도 자신의 대상 인스턴스를 다시 고정한다. 변경 가능한 전역 활성 인스턴스에만 의존하지 않는다.

일치 인스턴스가 없거나 둘 이상이면 자동 선택하지 않는다. Editor 시작과 MCP 등록에는 제한된 범위로 재조회할 수 있지만 무기한 대기하지 않으며, 준비되지 않으면 차단 상태로 전환한다.

## 6. 구현 차단과 복구

다음 중 하나라도 해당하면 해당 실행 루트의 Unity 구현 전체를 시작하거나 계속하지 않는다.

- linked worktree 판별 또는 실행 루트 확정 실패
- `ProjectVersion.txt` 또는 일치 Unity Editor 부재
- 전용 Editor 실행 실패 또는 비정상 종료
- MCP port 충돌을 해소하지 못했거나 port 설정을 안전하게 분리·원복할 수 없음
- 일치하는 MCP 인스턴스가 없거나 둘 이상임
- MCP `projectRoot` 불일치
- `ready_for_tools=false`가 일시적 컴파일·도메인 리로드 대기 후에도 해소되지 않음
- MCP 재연결 후 대상 인스턴스의 동일성을 다시 확인할 수 없음

차단 시 허용되는 작업은 로컬 파일과 규칙의 읽기, 분석, 계획 갱신, 인스턴스 재조회와 정확한 차단 보고뿐이다. C#·에셋·씬·프리팹·ProjectSettings·Packages를 포함한 Unity 프로젝트 구현 파일 수정, Unity MCP 변경 명령, 컴파일 확인과 다른 Editor·배치모드 우회는 금지한다.

차단 보고에는 다음을 포함한다.

- 실행 루트와 linked worktree 판별 결과
- 기대 Unity 버전과 Editor 실행 결과
- 원래 endpoint, port 변경 사유와 최종 할당 endpoint
- 발견한 MCP 인스턴스의 `Name@hash`와 각 `projectRoot`
- 마지막 `editor/state`와 차단 이유
- 구현 파일이 아직 변경되지 않았다는 사실 또는 차단 전에 변경이 있었다면 정확한 변경 범위
- 복구에 필요한 사용자 조치

복구 후에는 Editor·MCP 발견 절차를 처음부터 다시 수행하고 대상 인스턴스를 재고정한다.

## 7. 구현 서브 에이전트 전달 계약

기존 9개 필수 전달 패킷 중 Unity Editor·MCP 항목은 다음 정보를 포함하도록 강화한다.

| 전달 항목 | 필수 내용 |
|---|---|
| 실행 컨텍스트 | 실행 루트, 일반 체크아웃·linked worktree·비Git 판별 결과 |
| Editor 컨텍스트 | `ProjectVersion.txt` 버전, 전용 Editor 실행 여부 |
| MCP 컨텍스트 | 대상 endpoint, port 변경 사유 또는 `not_changed`, `Name@hash`, 확인된 물리 `projectRoot`, `ready_for_tools` 상태 |
| 라우팅 규칙 | 지원되는 호출의 `unity_instance` 명시와 리소스 조회 전 인스턴스 재고정 |
| 컴파일 확인 | 대상 Editor에서 컴파일 완료를 기다린 뒤 같은 인스턴스의 Console 오류 확인 |
| 차단 조건 | 불일치·미등록·다중 일치·준비 실패 시 구현 전체 중단과 보고 형식 |

메인 에이전트가 위 실행 컨텍스트를 확정하지 못하면 구현 서브 에이전트를 파견하지 않는다. 구현 중 도메인 리로드, Editor 재시작 또는 MCP 재연결이 발생하면 서브 에이전트는 변경을 멈추고 대상 동일성을 다시 확인한다.

## 8. 검증 및 증거 경계

- Unity 컴파일 확인은 반드시 구현 파일이 위치한 실행 루트의 전용 Editor와 대상 MCP 인스턴스에서 수행한다.
- 다른 체크아웃 Editor의 clean Console, 컴파일, 테스트, 실행 화면은 현재 워크트리의 증거가 아니다.
- 올바른 Editor·MCP 바인딩은 테스트 실행이 아니라 구현 전 안전 게이트다.
- 하네스 린트, 계약 테스트, Unit·Integration·EditMode·PlayMode, 런타임·씬·Inspector·시각 검증과 Player Build는 사용자가 현재 요청한 경우에만 실행한다.
- 요청하지 않은 검증은 기존 정책대로 `not_run`으로 기록한다.

이번 하네스 정책 변경에서는 문서 변경의 컴파일 확인은 `N/A`다. 계약 Bash·PowerShell 파일을 수정할 경우 각 언어의 구문 확인까지만 필수로 수행한다. 구문 확인 진입점이 없으면 정확한 차단 원인을 보고하고 성공으로 주장하지 않는다. 계약 테스트 자체는 사용자 요청이 없으므로 실행하지 않는다.

## 9. 정책 동기화 범위

### 공통 기준

- 두 하네스에 같은 내용의 `.agents/docs/onboarding/unity-worktree-cli.md(구 `unity-worktree-mcp.md`)` 생성
- `.agents/AGENTS.md`에서 실행 전 필수 규칙으로 연결
- `.agents/docs/onboarding/agent-tooling.md`에 worktree·Editor·MCP 준비 순서 추가
- `.agents/docs/onboarding/agent-quickstart.md`와 `developer-quickstart.md`에 실행 게이트 추가
- `.agents/docs/coding-standards/core/unity-validation.md`에 증거 권위 경계 추가
- `.agents/docs/exec-plans/README.md`와 `_TEMPLATE.md`에 실행 루트·Editor·MCP 바인딩 기록 추가
- `.agents/tests/run-tests.sh`의 문서 계약에 공통 규칙 추가

### 업무용 추가 기준

- `<업무용-하네스>/docs/business-standards/client-workflow-sop.md`에 구현 파견 전 worktree 격리 게이트 추가
- `<업무용-하네스>/docs/business-standards/traceability.md`에 정책 ID와 문서·계약 매핑 추가
- `<업무용-하네스>/tests/run-workflow-tests.sh`와 `<업무용-하네스>/tests/run-workflow-tests.ps1`의 정책 계약에 같은 차단 조건 추가

기존 완료 계획과 과거 설계·증거 문서는 당시 기록이므로 소급 수정하지 않는다. 새 규칙은 앞으로 생성하는 작업과 실행 계획부터 적용한다.

## 10. 수용 기준

- 두 하네스가 같은 worktree 판별, 전용 Editor, MCP 경로 일치와 차단 규칙을 갖는다.
- 일반 체크아웃과 linked worktree 모두 실행 루트와 다른 MCP 인스턴스를 사용할 수 없다.
- linked worktree에 일치하는 전용 Editor·MCP가 없으면 Unity 구현 파일을 변경하기 전에 중단한다.
- 병렬 Unity 작업이 서로 다른 `Name@hash` 대상으로 명시적으로 라우팅된다.
- port 충돌 시 대상 전용 Editor에만 사용 가능한 loopback port를 할당하고, port만으로 인스턴스를 식별하지 않는다.
- port 변경이 프로젝트 파일에 남으면 제품 변경에서 제외하고 handoff 전에 원복한다.
- 도메인 리로드·재연결 뒤 대상 동일성을 재확인한다.
- 컴파일 확인이 현재 워크트리의 Editor·Console에서만 이루어진다.
- 업무용 기존 아키텍처, AI 리뷰, CI, QA와 상태 전이 품질 기준은 삭제되거나 완화되지 않는다.
- 사용자가 요청하지 않은 테스트·검증은 실행하지 않고 `not_run`으로 남긴다.

## 11. 변경 이력

| 날짜 | 작성자 | 변경 내용 |
|---|---|---|
| 2026-07-26 | Codex | 사용자 승인 방향과 전용 Editor·MCP 차단 조건을 반영한 초안 |
| 2026-07-26 | Codex | 필요 시 워크트리별 MCP 서버 port 충돌 회피·재할당·원복 정책 추가 |

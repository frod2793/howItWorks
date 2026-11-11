# 범용 Unity 하네스 — AI 에이전트 가이드

> 이 파일은 에이전트가 가장 먼저 읽는 진입점입니다. 실제 프로젝트 규칙은 감지 결과가 아니라 사용자가 확정한 `.agents/config/project-profile.conf`가 결정합니다.

- 모든 진행 보고에 `진행도 N%`를 반드시 포함한다.

## 최우선 규칙: 차단 금지와 차단 해결

이 절은 이 문서·하위 문서·스킬의 다른 모든 규칙보다 먼저 적용합니다.

- 기본 진행 규칙: 같은 제한이 3턴 이상 반복되고 가능한 진전이 없으면 목표를 `blocked`로 기록하고, 재개 방법(재개 조건, 다음 단계, 재개 명령이나 위치)을 함께 남깁니다.
- 사용자가 "차단 금지"를 지시하면 그 지시가 적용되는 작업에서는 차단 금지가 위 기본 진행 규칙과 하네스의 다른 모든 규칙보다 우선합니다. 목표를 `blocked`·일시 중지로 바꾸지 않고, 승인 대기·확인 질문으로 멈추지 않으며, 권장안이나 가장 최근의 확정 지시로 계속 진행합니다. 정한 선택과 근거는 기록해 완료 보고에 포함합니다.
- 파견 전 모델 질문을 요구한 사용자의 최신 명시적 지시는 일반 차단 금지보다 우선합니다. 해당 역할의 사용자 배정이 확정되기 전에는 답변 없이 임의 선택·대체 파견하지 않습니다. 이전 파견의 배정을 자동 재사용해 새 파견의 질문을 생략하지 않습니다.
- 차단 금지는 진행을 막는 대기만 없애며 보호 hook·보안 경계·검증 증거 기준을 우회하거나 완화하지 않습니다. 실행하지 않은 검증을 완료로 보고하지 않습니다.
- 차단 금지 중에도 같은 출력을 반복하지 않습니다. 직전과 같은 상태 보고·조회 결과·질문·명령을 새 근거(바뀐 입력·원인·방법·결과) 없이 다시 내보내는 것은 진행이 아니며 금지합니다. 다른 허용 경로가 남아 있으면 그 경로로 진행하고, 남은 경로가 없으면 시도한 방법·원인·남은 차단 요소·재개 조건을 한 번만 보고한 뒤 새 입력이 올 때까지 같은 출력을 내지 않습니다. 이 1회 보고는 `blocked` 전환이나 승인 대기가 아니므로 차단 금지 위반이 아닙니다.
- 차단 금지 중에는 무의미한 대기도 허용하지 않습니다. 상태를 바꿀 조건·종료 시점·확인 대상이 없는 대기·sleep·주기적 재확인·빈 턴 반복은 진행이 아니며 금지합니다. 대기 대신 방안을 모색합니다: 원인을 진단하고 다른 도구·채널·실행 방식이나 독립적인 다른 작업으로 진행하며, 꼭 기다려야 하면 완료 알림 등 상태 변화 신호와 제한 시간을 정합니다.
- 차단 금지 지시 여부와 관계없이, 작업이 차단 상태(권한·샌드박스 거부, 도구·연결 실패, 테스트 실패, 누락된 입력 등)가 되면 세션을 닫거나 작업을 중단하지 않고 해결을 시도합니다. 원인을 진단하고, 고칠 수 있으면 고친 뒤 다시 실행하며, 고칠 수 없으면 우회 경로(다른 도구·채널·실행 방식)를 찾아 계속합니다. 같은 조회와 상태 보고를 반복하는 것은 해결 시도가 아닙니다.
- 목표를 일시 중지·대기·차단 상태로 둘 때는 재개 방법을 기록하고, 차단 요인이 해소되면 스스로 목표를 재개합니다. 재개 방법을 확보할 수 없으면 목표를 차단하지 않고 계속 진행합니다.
- 모든 시도가 실패해도 작업 상태와 산출물을 보존한 채 시도한 방법·원인·남은 차단 요소를 보고하며, 작업을 임의로 종료하거나 폐기하지 않습니다.
- 서브 에이전트를 파견할 때 차단 금지 지시가 있으면 전달 패킷에 그 지시를 포함합니다.
- 사용자가 해제하거나 새 지시를 내리면 그 지시를 따릅니다.

## 작업 종료와 반복 방지

- 승인 시 원문 목표·수용 조건·허용 파일·현재 검증 권한을 고정합니다. 필수 조건을 충족하면 현재 작업을 종료하며, 추가 개선을 완료 조건에 붙이지 않습니다.
- 재시도는 입력·실패 원인·실행 방법 중 실제로 바뀐 근거와 예상 시간을 기록한 경우에만 합니다. 동일 입력·동일 실패·동일 방법의 재실행은 금지합니다. 차단 금지는 다른 허용 경로로 진전하라는 뜻이며 보호 경계를 우회하거나 무한 반복하라는 뜻이 아닙니다.
- 중요한 검수 지적은 같은 구현자가 수정하고, 재검수는 수정한 지적과 실제 영향 범위만 확인합니다. 새 중대 문제가 있으면 증거와 새 범위를 분리해 보고하며, 현재 수용 조건을 임의 확대하거나 미충족 조건을 완료·PASS로 바꾸지 않습니다.

## 필수 읽기 순서

1. 자기 실행 루트의 `AGENTS.md`와 존재하는 `.agents/AGENTS.md`를 직접 읽습니다. 전달 패킷은 직접 재독을 대체하지 않습니다.
2. 최신 사용자 요구·승인 범위·역할·보호 경로·검증 실행 권한을 확인합니다.
3. `.agents/config/project-profile.conf`의 상태와 확정 프로필을 확인합니다.
4. Core·Optimization Base와 확정 Profiles의 적용 의무를 확인합니다. 상세 문서의 읽기 시점은 아래 작업 분류와 실제 영향으로 정합니다.
5. 모호한 작업은 관련 경계를 먼저 확인한 뒤 분류합니다. 관련 상세 문서는 해당 분석·설계·수정 전에 읽으며, 미로딩은 정책 면제가 아닙니다.
6. 구현 전 전체 계획 승인과 [에이전트 도구 준비](docs/onboarding/agent-tooling.md)의 해당 백엔드 적용 규칙을 확인합니다.

| 작업 분류·실제 영향 | 상세 문서 읽기 시점 |
|---|---|
| 코드·아키텍처·수명·성능 | 관련 [Core](docs/coding-standards/core/architecture-principles.md)·확정 [Profiles](docs/profiles/architecture/)를 분석·설계 전에 읽음 |
| 렌더링·최적화 | 관련 [Optimization Base](docs/coding-standards/optimization/rendering-techniques.md)와 [일반 최적화](docs/coding-standards/optimization/general-techniques.md)를 판정·설정 변경 전에 읽음 |
| Unity·UI·직렬화·Editor | [Unity 안전성](docs/coding-standards/core/unity-safety.md)·[Editor 격리](docs/onboarding/unity-worktree-cli.md)를 관련 작업 전에, 요청된 Unity 검증·빌드는 [CLI 가이드](docs/onboarding/unity-cli.md)·[검증 정책](docs/coding-standards/core/unity-validation.md)를 실행 계획 전에 읽음 |
| Git·업무 상태 | 현재 요청된 Git·상태 동작의 프로젝트 규칙을 실행 전에 읽음 |
| 병렬·파견 | [병렬 작업 규칙](docs/onboarding/parallel-work.md)을 역할·소유 경계 계획 전에 읽음 |

`pending`이면 선택 Profiles는 참고이며, `confirmed`일 때 확정된 기술 Profiles만 강제합니다. `architecture=custom`이면 일반 아키텍처 전용 강제만 사용자 경계로 축소합니다.

프로필이 없으면 먼저 초기화하고 `.agents/reports/detection-report.md`를 검토합니다. 감지값은 후보일 뿐이며 사용자 확인 없이 프로젝트 사실로 단정하지 않습니다.

## 규칙 우선순위

현재 사용자의 명시적 지시가 우선합니다. 루트·상위 `CLAUDE.md` 등에 사용자가 확정한 프로젝트별 예외는 해당 작업 범위의 하네스 기본값보다 우선하며, 무관한 품질 게이트나 실행 권한의 포괄 예외로 확대하지 않습니다. 그다음 확정 프로필과 Core·Optimization Base를 적용합니다.

## 최우선 구현·검증 권한 정책

이 섹션은 구현 주체와 검증 실행 권한에 관해 하위 문서와 스킬의 기본 지시보다 우선합니다. 기존 테스트·CI·마일스톤 품질 기준은 삭제하지 않고, 사용자가 요청했을 때 실행할 검증 명세로 유지합니다.

### 역할 분리

- 메인 에이전트는 실제 파일과 규칙을 분석하고 계획·승인 범위를 확정한 뒤 구현 규칙 묶음을 서브 에이전트에게 전달합니다. 구현 파일을 직접 생성하거나 수정하지 않습니다.
- 모든 구현 파일 생성·수정은 구현 서브 에이전트가 수행합니다. 전달받은 범위 안에서 최소 변경하고 관련 없는 사용자 변경을 보존합니다.
- 구현 서브 에이전트가 완료를 보고하면 메인 에이전트가 요구사항 일치와 코드 품질을 독립적으로 정적 리뷰합니다.
- 중요한 리뷰 지적은 같은 구현 서브 에이전트가 수정하고 메인 에이전트가 재리뷰합니다. 정적 리뷰는 테스트나 런타임 검증을 대체하지 않습니다.

### 필수 전달 패킷

메인 에이전트는 구현 전에 다음 항목을 빠짐없이 전달합니다.

1. 사용자 요구와 목표
2. 승인된 계획과 변경 범위
3. 프로젝트 `.agents/AGENTS.md` 및 연결된 최우선 규칙
4. 적용할 아키텍처·코딩·명명 규칙과 Karpathy Guidelines
5. 생성·수정 가능한 정확한 대상 파일
6. 관련 없는 변경, 서드파티, 외부 서비스 등 금지 범위
7. 현재 요청에서 허용된 검증·테스트 목록 또는 `none`
8. `unity command recompile`·배치 컴파일·프로젝트 명령 등 컴파일·구문 오류 확인 방법. Unity 작업이면 실행 루트 유형과 물리 절대 경로, `ProjectSettings/ProjectVersion.txt`의 Editor 버전과 대상 Editor 상태, `linked_worktree`의 전용 상태, Pipeline 인스턴스 `pid`·`port`·`version`, exact match인 물리 `projectPath`, `editor_status` 결과를 함께 포함 Editor 의존 여부(`의존` 또는 `비의존: 근거`)를 먼저 명시하고, `비의존`이면 identity 항목은 `N/A`로 둡니다.
9. 변경 파일, 구현 요약, 컴파일 결과, `not_run`, 남은 위험을 포함한 완료 보고 형식

전달 패킷이 누락되거나 충돌하면 구현 서브 에이전트는 추측해 구현하지 않고 메인 에이전트에 필요한 정보를 요청합니다.

패킷과 별개로, 구현·검수 서브 에이전트는 백엔드와 무관하게(Codex·Claude·Antigravity 등) 작업 시작 전 자기 실행 루트의 `.agents/AGENTS.md`를 직접 다시 읽고 적용하며, 완료 보고에 하네스 핵심 규칙 준수 여부를 명시합니다. 전달 패킷 수신은 하네스 직접 재독을 대체하지 않습니다.

완료 보고에는 원문 목표·수용 조건별로 실제 변경 파일과 동작이 어떻게 충족하는지, 목표·대상·사용자 지정 구조와 패턴·실행 환경을 바꾸지 않았는지의 요구사항 일치 결과를 적습니다. 필요해 보이는 다른 작업을 스스로 시작하거나 요청된 결과를 더 쉬운 결과로 대체하지 않으며, 새 범위가 필요하면 근거를 분리해 사용자 지시를 받습니다. 플러그인·스킬(Ponytail 등)의 간소화 권고는 목표·대상·패턴을 바꾸는 권한이 아니고, 차단 금지도 기존 승인 범위 안에서만 우회합니다. 원문 요구 → 허용 파일 → 실제 diff → 지정 플랫폼·패턴 → 명령 로그 증거를 완료 보고에서 대조합니다. 정책 변경의 대표 3사례는 저장 로그 또는 scratch fixture로 분류하고, 명령·기기 기록이 없으면 `unknown` 또는 `not_run`으로 남깁니다.

### 검증 실행과 상태 전환

- 적용 가능한 코드·스크립트 변경은 실제 진입점으로 컴파일·구문 오류를 확인하는 것까지 필수입니다. 문서만 변경하면 `N/A`로 기록하고, 진입점이 없거나 실행이 막히면 원인을 보고하며 성공으로 주장하지 않습니다.
- 하네스 린트, 정적 정책 검사, 계약·Unit·Integration 테스트, Unity EditMode·PlayMode 테스트, 런타임·씬·Inspector·시각 검증, Player Build와 외부 CI는 사용자가 현재 명시한 범위에서만 실행합니다.
- 허용된 검증 안에서도 변경과 관련된 기존 테스트 그룹(`--group`·`--runtime`)만 선정 이유와 함께 실행합니다. 같은 revision·입력·환경에서 이미 통과한 검증은 새 변경·실패·미해결 우려가 없으면 반복하지 않으며, 제품 `.cs` 국소 변경에 하네스 자체 suite를 자동 실행하지 않습니다. hook·parser 변경의 보호 회귀는 줄이지 않고, 시간 제한 때문에 미완료 검증을 통과로 처리하지 않습니다.
- 사용자가 요청하지 않은 검증은 `not_run`으로 기록합니다. 이를 검증 완료나 CI 통과로 해석하지 않고 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done 상태로 전환하지 않습니다.

## Worktree별 Unity Editor·CLI 격리

모든 Unity 실행 루트는 실행 중 Editor를 사용할 때 `unity status --format json`의 인스턴스 `project`와 대상 물리 프로젝트 루트의 exact match, `unity command editor_status --project-path <물리 경로>`의 `projectPath` exact match·`status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용)·`compiling=false`를 확인합니다. Git linked worktree에서 Unity 작업을 병렬 수행할 때는 추가로 `워크트리 1개 : Unity Editor 1개 : Pipeline 인스턴스 1개`를 적용하고 `ProjectVersion.txt` 버전의 전용 Editor를 해당 물리 `projectPath`로 실행합니다.

- 같은 물리 경로의 인스턴스가 없거나 둘 이상이면 상주 Editor 경로를 포기하고 백그라운드 경로로 진행합니다.
- `blocked`(실행 루트 미확정)에서만 구현 파일 수정을 금지합니다. `ready` 또는 `background: editor_unavailable`이면 승인된 범위로 진행하며, 프로젝트 파일에 port·endpoint 설정을 쓰지 않습니다.
- Unity 검증·빌드·실행 중 Editor 상호작용은 Unity CLI·Pipeline으로 수행합니다. Pipeline 패키지 명령은 `unity command`로 호출합니다. Unity MCP는 사용하지 않습니다. 기준은 [Unity CLI 실행 가이드](docs/onboarding/unity-cli.md)의 CLI 단일 원칙과 [도구 준비 문서](docs/onboarding/agent-tooling.md)를 따릅니다. Editor 프로세스 기동은 `bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`를 최초 진입점으로 사용합니다. helper가 CLI를 한 번 시도하고 실패 시 동일 버전 Unity 앱을 한 번 직접 실행합니다. 이미 `unity open` 실패를 확인했다면 `--skip-cli`로 CLI 재시도를 생략합니다. 실행 중 Editor와의 상호작용은 계속 CLI·Pipeline만 사용하며, 앱 실행 성공만으로 `ready`를 인정하지 않습니다.
- Unity Pipeline 패키지(`com.unity.pipeline`)는 항상 최신 버전으로 유지합니다. Unity 작업을 시작할 때 `unity pipeline list`에서 대상 프로젝트가 `updateAvailable`이거나 Pipeline 서버에 접속되지 않으면 `unity pipeline upgrade --project-path <물리 절대 경로>`로 올리고, 실행 중인 Editor에는 창 포커스 없이 `unity command package resolve --project-path <물리 절대 경로>`로 반영한 뒤 `recompile_status`로 완료를 확인하고 진행합니다. 반영되지 않으면 Editor를 재시작하며, 어떤 경우에도 Editor 창을 앞으로 가져오거나 포커스를 옮기지 않습니다.
- 플레이 기반 테스트의 UI 관측·조작은 사용자 포커스를 가져가지 않도록 `agent-desktop` 기본 headless 모드로 수행합니다. `--app`·`--window-id`로 대상을 정하고 최신 `snapshot`의 ref로만 동작한 뒤 결과를 다시 읽어 확인합니다. `--headed`, `focus`·`focus-window`·`launch --activate` 등 앱·창 활성화, 전역 물리 키보드·마우스 입력은 금지합니다. Unity Game 캔버스에 접근성 노드가 없으면 승인된 Unity CLI·Pipeline 자동화를 쓰고, 그것도 없으면 `not_run`으로 기록하며 물리 입력으로 전환하지 않습니다. 컴파일·Play 상태·테스트 명령은 위 CLI·Pipeline과 물리 프로젝트 identity 규칙을 그대로 따릅니다. 세부는 [도구 준비 문서](docs/onboarding/agent-tooling.md)의 무포커스 UI 검증 절을 따릅니다.
- 이 게이트는 실행 중 Editor를 실제로 사용하는 Editor 의존 작업에 적용합니다. **Editor 비의존 변경**(기존 `.cs` 로직 수정만·직렬화 표면 불변·scene/prefab/asset/UI 배치/Inspector 값 무변경)은 실행 루트·물리 경로 판별만 하고 게이트 없이 구현을 파견하며, 컴파일 확인은 [Unity CLI 실행 가이드](docs/onboarding/unity-cli.md)를 따릅니다. 정의·절차는 [Unity linked worktree Editor·CLI 격리](docs/onboarding/unity-worktree-cli.md)의 적용 범위를 따릅니다.
- port를 identity로 사용하지 않습니다. `unity status --format json` 조회, 물리 `project` exact match 선별, `unity command editor_status --project-path <물리 경로>`, `unity list --project-path <물리 경로>` 순서로 대상 인스턴스를 확정합니다. `unity command`·`unity list`에는 `--project-path <물리 절대 경로>`, `unity run`에는 위치 인자 `<물리 절대 경로>`를 필수로 지정합니다.
- 바인딩이 `ready`가 아니면 [백그라운드 경로](docs/onboarding/unity-worktree-cli.md)(`background: editor_unavailable`)로 파견합니다 — 구현은 파일 수준, 검증은 물리 경로를 명시한 Unity CLI·batchmode, Editor 상호작용 항목은 `unity run --command`로 headless 수행하고 그것도 불가하면 `not_run`. 실행 루트·물리 경로를 확정할 수 없을 때만 구현 서브 에이전트를 파견하지 않고 Unity 구현 전체를 중단합니다. 다른 Editor, 메인 checkout 또는 목록의 첫 인스턴스로 대상을 바꾸지 않습니다.
- 상주 Editor 경로의 컴파일·Console은 동일 identity의 `unity command` 결과로, 백그라운드 경로의 컴파일·테스트·빌드는 동일 물리 경로·버전의 CLI 결과로 인정하며 명령·로그·종료코드를 기록합니다. 다른 checkout의 로컬 결과는 대상 변경의 증거가 아니며, 승인된 `unity_ci` 증거의 별도 권위는 기존 검증 정책을 따릅니다.
- Editor 비의존 변경의 컴파일 증거는 동일 실행 루트에서 Unity CLI로 얻은 결과 또는 상주 전용 Editor의 결과를 인정하며, 없으면 `not_run`으로 기록합니다.

상세 판별, 인스턴스 고정, 복구와 증거 기준은 [Unity linked worktree Editor·CLI 격리](docs/onboarding/unity-worktree-cli.md)를 따릅니다. 이 게이트는 기존 구현 역할과 검증 실행 권한을 변경하지 않습니다.

## 상태별 규칙 활성화

| 조건 | 강제 범위 | 처리 원칙 |
|------|-----------|-----------|
| 프로필 없음 | 구현 중지 | 초기화 후 감지 보고서를 검토 |
| `confirmation_status=pending` | Core + Optimization Base | 모든 기술 Profiles는 참고만 하고 강제하지 않음 |
| `confirmation_status=confirmed` | Core + Optimization Base + 확정된 기술 Profiles | 프로필별 검사를 활성화 |
| `confirmed` + `architecture=custom` | Core + Optimization Base + 사용자 아키텍처 경계 + 확정된 DI·비동기·트윈·렌더링 Profiles | 일반 아키텍처 전용 검사만 축소 |

`confirmation_status`는 규칙 확정 여부이고 `architecture`는 아키텍처 선택입니다. `architecture=custom`은 상태가 아니며, 확정된 프로젝트에서는 일반 아키텍처 검사만 사용자 경계로 대체합니다. 확정된 DI·비동기·트윈·렌더링 Profiles는 계속 활성화합니다.

## 규칙 문서 맵

### Core — 항상 적용

- [아키텍처 원칙](docs/coding-standards/core/architecture-principles.md)
- [네이밍과 문서화](docs/coding-standards/core/naming-and-documentation.md)
- [런타임 성능](docs/coding-standards/core/runtime-performance.md)
- [Unity 안전성](docs/coding-standards/core/unity-safety.md)
- [Unity 기능·마일스톤 검증](docs/coding-standards/core/unity-validation.md)

### Optimization Base — 항상 적용 의무 확인, 관련 작업 전에 상세 읽기

- [렌더링 최적화 기법](docs/coding-standards/optimization/rendering-techniques.md)
- [일반 최적화 기법](docs/coding-standards/optimization/general-techniques.md)

각 기법은 `applicable`, `not_applicable`, `unknown` 상태와 측정 결과를 확인한 뒤 적용합니다. 적용 전후 수치와 롤백 조건 없이 설정을 변경하지 않습니다.

### Profiles — 확정된 선택만 적용

- 아키텍처: [MVVM](docs/profiles/architecture/mvvm.md), [MVP](docs/profiles/architecture/mvp.md), [MVC](docs/profiles/architecture/mvc.md), [Layered/Clean](docs/profiles/architecture/layered-clean.md), [Custom](docs/profiles/architecture/custom.md)
- [의존성 주입](docs/profiles/dependency-injection.md)
- [비동기 백엔드](docs/profiles/async.md)
- [트윈 백엔드](docs/profiles/tween.md)
- [렌더 파이프라인](docs/profiles/rendering.md)

특정 기술 이름은 해당 프로필이 `confirmed`일 때의 조건부 규칙입니다. Core의 기본 선택으로 해석하지 않습니다.

## 프로젝트 경로

- 생성·수정 대상은 프로필의 모든 `${source_root}`에서 찾습니다.
- 테스트 대상은 프로필의 모든 `${test_root}`에서 찾습니다.
- `test_root`가 없으면 임의 경로를 만들지 말고 프로젝트가 제공하는 대체 검증 방법을 계획에 기록합니다.
- `exclude_root`와 서드파티 원본은 변경 범위에서 제외합니다.

## 기준 플랫폼

- 이 하네스의 기준 플랫폼은 macOS이며 스크립트의 canonical 런타임은 Bash입니다.
- PowerShell 스크립트는 Windows 참고용으로 유지하며 PowerShell 실행 검증 미실시 상태입니다. 결과가 다르면 bash 결과를 기준으로 합니다.
- Unity Editor 설치 확인, 테스트·빌드 실행에는 [Unity CLI 실행 가이드](docs/onboarding/unity-cli.md)를 사용하며, 상태 확인은 다음 명령을 사용합니다.

```bash
bash .agents/scripts/setup/check-unity-cli.sh --check
```


## 작업 승인과 검증

1. 현재 프로필과 관련 Core·Optimization Base·Profiles 문서를 읽습니다.
2. 실제 파일과 직렬화 상태를 근거로 분석합니다.
3. 구현 계획을 작성하고 사용자의 명시적인 전체 승인을 기다립니다.
4. 승인 후 메인 에이전트가 필수 전달 패킷을 구현 서브 에이전트에게 전달합니다.
5. 구현 서브 에이전트가 최소 범위로 구현하고 적용 가능한 코드·스크립트의 컴파일·구문 오류를 확인합니다.
6. 메인 에이전트가 독립 정적 리뷰하고, 사용자가 현재 요청한 검증만 실행합니다.

사용자가 하네스 정적 검사를 현재 요청한 경우 다음 진입점을 사용할 수 있습니다.

```bash
bash .agents/scripts/lint/check-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/lint/check-harness.ps1 -ProjectRoot .
```

처음 참여한 에이전트는 [에이전트 온보딩](docs/onboarding/agent-quickstart.md)을 함께 읽습니다.

## Unity 기능·마일스톤 검증

다음은 사용자가 해당 검증을 현재 요청했을 때 적용하는 품질 명세입니다. 요청하지 않은 항목은 `not_run`이며 통과로 간주하지 않습니다.

- 개별 Task 검증 범위는 정적 검사, 대상 테스트, 논리적 변경 묶음 단위 Unity 컴파일이며 Player Build를 포함하지 않습니다. 범위 선택은 실행 권한을 넓히지 않습니다.
- 기능·마일스톤 검증은 `Assets/_Game` 프로젝트 소유 모듈과 상호작용의 전체 자동화 통합 테스트를 완료해야 합니다.
- Player Build가 현재 명시적으로 요청된 경우 사전 게이트를 통과한 동일 변경분에만 1회 수행하며, Unity CI Build Validation이 있으면 로컬 중복 빌드를 수행하지 않습니다.
- 세부 증거 형식과 무효화 기준은 [Unity 기능·마일스톤 검증 정책](docs/coding-standards/core/unity-validation.md)을 따릅니다.

## 에이전트 도구 워크플로

모든 코드 작성, 기능 구현, 리팩토링, 테스트 및 Bash·PowerShell 스크립트 작성·수정에는 karpathy-guidelines를 적용합니다.

- 작업 전 가정, 사용자 승인 범위와 검증 기준을 고정하고 최소 변경으로 구현합니다.
- 작업 계획은 [병렬 작업 규칙](docs/onboarding/parallel-work.md)의 계획 단계 병렬화 원칙에 따라 병렬 처리 우선으로 수립해 시간 단축을 고려합니다.
- 실패 처리·사례 수집·해결안 검증·승격은 [트러블슈팅 사례 관리](docs/troubleshooting/README.md)의 수집 정책과 검색·사용 규칙을 따릅니다.
- `karpathy-guidelines`가 미설치이면 작업 전에 보고하고 사용자 지시를 기다립니다. 자동 네트워크 설치하지 않습니다.
- 설치·복구는 사용자 현재 요청 범위에서 명시적으로 요청된 경우에만 수행합니다.
- 창의적 변경·버그 수정·완료 전에는 현재 승인 범위 안에서 작업에 맞는 `superpowers` 스킬을 적용합니다. `test-driven-development`와 `verification-before-completion`의 실행 시점은 [도구 준비 문서](docs/onboarding/agent-tooling.md)를 따르며, 스킬이 현재 사용자 검증 권한을 넓히지는 않습니다.
- 프로젝트 파악과 아키텍처 질문은 graphify를 우선하고, graphify 미설치 환경에서만 `understand`, `understand-chat`, `understand-explain`을 사용합니다.
- 변경 영향과 온보딩은 graphify 그래프가 있으면 graphify 쿼리로 수행하고, graphify가 없고 Understand 그래프가 이미 있을 때만 `understand-diff`, `understand-onboard`를 사용합니다.
- 스타일 플러그인 적용과 외부 서비스 MCP 경계는 [도구 준비 문서](docs/onboarding/agent-tooling.md)의 스타일 플러그인 규칙을 따릅니다.
- 역할별 모델 분담은 [도구 준비 문서](docs/onboarding/agent-tooling.md)의 사용자 배정 절차를 따릅니다. 모든 역할은 매 파견 사용자 질문·답변 확인을 기본으로 하며, 현재 명시 승인된 자동 선택 예외만 해당 범위에 적용합니다. 역할 경계와 증거 기준을 변경하지 않습니다.
- 토큰 절약은 [도구 준비 문서](docs/onboarding/agent-tooling.md)의 토큰 절약 절을 따릅니다. 필요한 부분만 읽고 원문 대신 경로로 가리키되, 증거 기준과 `.agents/AGENTS.md` 직접 재독 의무는 줄이지 않습니다.
- 에이전트 간 통신은 Orca 오케스트레이션을 우선 사용합니다. 구현 파견과 완료 보고, 검수 요청과 결과 수신, 질문과 답변은 오케스트레이션으로 주고받고, 오케스트레이션을 사용할 수 없을 때만 orca terminal 명령으로 주고받으며 사유를 기록합니다. 오케스트레이션을 사용하기 전에 `orca skills get orchestration`으로 현재 orca 버전의 가이드를 읽고 역할 분류·파견·완료 절차를 확인합니다. 세부 기준은 [도구 준비 문서](docs/onboarding/agent-tooling.md)를 따릅니다.
- 도구 누락은 Unity 코드 린트 실패가 아닙니다. [도구 준비 문서](docs/onboarding/agent-tooling.md)의 복구 절차를 따릅니다.
- Superpowers 설치 상태는 활성화된 `plugin@marketplace`와 같은 marketplace의 캐시 조합 또는 공식 저장소와 사용자 홈의 전역 `superpowers` 스킬 링크 조합을 확인합니다.

## 구현 완료 후 안내

- Inspector에서 연결해야 하는 `func_` 버튼 메서드
- 새로 할당해야 하는 직렬화 필드
- 이벤트 구독·해제 위치
- 컴파일·구문 확인 결과 또는 문서 변경의 `N/A`
- 하네스 핵심 규칙 준수 여부(CLI 우선 실행, 서브 에이전트 호출 채널, 병렬 우선 계획, 트러블슈팅 기록) 한 줄 명시
- 사용자 요청으로 실행한 검증, `not_run` 항목과 남은 위험

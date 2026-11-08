# Unity linked worktree Editor·CLI 격리

## 목적과 최우선 경계

이 문서는 모든 Unity 실행 루트의 Editor identity 안전 게이트와 Git linked worktree에서 병렬 작업할 때 실행 루트, Unity Editor와 Pipeline 인스턴스를 격리하는 상세 기준입니다. Unity와의 모든 상호작용은 Unity CLI(`unity`)와 Pipeline 패키지(`com.unity.pipeline`)로만 수행하며 Unity MCP는 사용하지 않습니다. 다른 온보딩·실행 계획 문서는 이 문서를 요약하고 연결하며, 절차가 충돌하면 이 문서를 따릅니다.

- `normal_checkout`, `linked_worktree`, `submodule`, `non_git` 모두 실행 중 Editor를 사용할 때 `unity status --format json`의 인스턴스 `project`가 물리 프로젝트 루트와 exact match인 후보 하나인지 확인합니다. 준비 상태는 아래 명시적 판정대로 동일 대상의 `editor_status` `projectPath` exact match·`unityVersion` 일치·`status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용)·`compiling=false`와 명령 목록 확인으로 확정합니다. `unity status`의 `state`만으로 준비 여부를 결정하지 않습니다.
- linked worktree의 기본 단위는 `워크트리 1개 : Unity Editor 1개 : Pipeline 인스턴스 1개`입니다.
- 구현 서브 에이전트를 파견하기 전에 대상 worktree의 Editor 바인딩이 `ready` 또는 `background: editor_unavailable`로 확정되어야 합니다.
- CLI의 Editor 실행이 실패하면 아래 앱 직접 실행 경로를 1회 시도합니다. 앱 실행도 실패하거나 이후 Pipeline 인스턴스 식별·`editor_status` 확인이 실패하면 아래 "Editor 불가 시 백그라운드 경로"로 진행합니다. 실행 루트·물리 경로 자체를 확정할 수 없을 때만 Unity 구현 전체를 중단합니다.
- 다른 Editor, 메인 checkout 또는 목록의 첫 인스턴스로 대상을 바꾸지 않습니다. 같은 물리 경로에 대한 Unity CLI·batchmode는 우회가 아니라 백그라운드 경로입니다.
- 이 안전 게이트는 테스트가 아니며 기존 구현 역할, 검증 실행 권한과 품질 기준을 변경하거나 확대하지 않습니다.

### 적용 범위 — Editor 의존 작업에만

이 게이트는 실행 중 Editor를 실제로 사용하는 **Editor 의존 작업**에 적용합니다. 다음을 모두 만족하는 **Editor 비의존 변경**은 게이트 없이 구현 서브 에이전트를 파견할 수 있으며, 실행 루트 유형·물리 경로 판별만 유지합니다.

- 변경이 기존 `.cs` 파일의 내용 수정뿐이다 — 파일 생성·삭제·이동·이름 변경 없음(`.meta` 불변)
- 직렬화 표면이 그대로다 — `[SerializeField]`·public 필드/프로퍼티의 추가·삭제·이름·타입 변경, 클래스·네임스페이스·asmdef 변경 없음
- scene·prefab·asset·ScriptableObject·UI 배치·Inspector 값·`ProjectSettings`·`Packages`를 건드리지 않는다
- 씬·GameObject·에셋 조작, 프로젝트 등록 명령 실행 등 실행 중 Editor와의 상호작용이 필요 없다

구현 도중 위 조건을 벗어나게 되면 그 시점부터 게이트를 적용합니다(Editor 의존 파일을 수정하기 전에 `ready` 확보 또는 백그라운드 경로 기록). Editor 비의존 변경의 컴파일 확인은 [Unity CLI 실행 가이드](unity-cli.md)의 "Editor 비의존 변경의 컴파일 확인"을 따르며, 실행 중 Editor에 `unity command`를 보내는 순간에는 이 게이트를 그대로 적용합니다.

### Editor 불가 시 백그라운드 경로

Editor 바인딩을 확정할 수 없어도(인스턴스 없음, exact match 실패, `editor_status`가 `ready`도 아니고 현재 승인된 PlayMode 관측·정지·캡처 작업의 `playing`도 아님, 작업 도중 연결 상실, 같은 경로의 인스턴스가 둘 이상) 실행 루트와 물리 프로젝트 경로가 확정돼 있으면 Unity 작업을 중단하지 않고 **백그라운드 경로**로 진행합니다. 계획·전달 패킷·증거의 Editor 상태는 `background: editor_unavailable <사유>`로 기록합니다.

- 구현: 구현 서브 에이전트는 파일 수준으로 진행합니다 — 승인된 `.cs`·scene·prefab·asset·`.meta` 등 텍스트 직렬화 파일이 대상입니다. 일반 기능 worktree에서 `ProjectSettings/**`·`Packages/**`를 수정하지 않습니다. Integration Owner만 자기 통합 worktree의 명시적으로 승인된 설정 범위를 수정할 수 있으며, 백그라운드 실행은 이 권한 경계를 바꾸지 않습니다. 신규 에셋·스크립트의 `.meta`는 배치 임포트(아래 CLI)로 생성해 함께 커밋합니다.
- 검증: 컴파일·EditMode·PlayMode 테스트·Build Validation은 대상 물리 절대 경로를 명시한 Unity CLI(`unity test`, `unity build`, Editor 실행파일 `-batchmode -nographics -quit`)로 수행합니다. 사용자가 현재 요청한 범위만 실행하는 원칙은 그대로입니다.
- Editor 상호작용 항목: 씬·GameObject·프리팹 조작, 스크린샷, 프로젝트 등록 명령 등 실행 중 Editor가 필요한 명령은 `unity run <물리 경로> --command <명령> -- <인자>`로 headless 배치 Editor에서 수행합니다(`unity run`은 `--project-path` 옵션이 없고 위치 인자로 경로를 받습니다). Library 잠금 등으로 headless 실행도 불가하면 그 항목만 `not_run: editor_unavailable`로 보고하고 나머지 작업은 끝까지 진행합니다. Editor가 복구되면 그 항목을 수행합니다.
- identity: 백그라운드 경로의 identity는 CLI 명령에 명시한 물리 절대 경로와 `ProjectVersion.txt` 버전입니다. 증거에는 명령 전문, 물리 경로, 버전, 로그·결과 파일 경로, 종료코드를 기록합니다. 다른 checkout·worktree 경로로 실행한 결과는 여전히 증거가 아닙니다.
- Library 잠금: 같은 물리 프로젝트를 연 대화형 Editor가 있으면 배치 실행이 실패합니다. 그 Editor가 `editor_status`에도 응답하지 않으면 `unity status --format json`으로 물리 `project`가 exact match인 프로세스만 골라 **해당 워크트리의 Editor만** 종료한 뒤 배치 실행합니다(다른 워크트리 Editor는 건드리지 않음). 확인 없는 종료는 프로젝트 지침(CLAUDE.md 등)이 사전 승인한 경우에만 하고, 승인 문구가 없으면 종료 전 사용자에게 확인합니다. 종료할 수 없으면 `not_run`으로 기록하고 성공으로 주장하지 않습니다.
- 복구: Editor가 다시 `ready`가 되면 이후 작업은 기존 게이트를 그대로 적용하며, 백그라운드 경로에서 수집한 증거는 유효합니다.

## 실행 루트와 linked worktree 판별

먼저 현재 실행 루트와 Unity 프로젝트 루트를 심볼릭 링크가 제거된 물리 절대 경로로 기록합니다. Git 저장소라면 다음 네 결과를 모두 수집하고, 상대 경로로 반환된 Git 경로도 물리 절대 경로로 정규화합니다.

```bash
git rev-parse --show-toplevel
git rev-parse --git-dir
git rev-parse --git-common-dir
git rev-parse --show-superproject-working-tree
```

판별 결과는 다음 네 값 중 하나로 고정합니다.

| 실행 루트 유형 | 판별 기준 |
|----------------|-----------|
| `non_git` | 현재 실행 루트에서 필수 `git rev-parse` 조회가 Git 저장소가 아니어서 실패함 |
| `submodule` | `--show-superproject-working-tree`의 물리 절대 경로가 비어 있지 않음 |
| `linked_worktree` | superproject 경로가 비어 있고 물리 `--git-dir`와 `--git-common-dir`가 다름 |
| `normal_checkout` | superproject 경로가 비어 있고 물리 `--git-dir`와 `--git-common-dir`가 같음 |

`.git`이 파일인지 디렉터리인지만 보고 유형을 추정하지 않습니다. 결과가 서로 모순되거나 물리 경로를 확정할 수 없으면 Unity 구현을 차단하고 정확한 실행 루트를 다시 확인합니다. Unity 프로젝트 루트가 Git top-level과 다르면 두 경로를 각각 기록하며, 이후 Editor 비교에는 `ProjectSettings/ProjectVersion.txt`를 포함하는 물리 Unity 프로젝트 루트를 사용합니다.

## 전용 Unity Editor 준비

실행 루트가 `linked_worktree`이면 `ProjectSettings/ProjectVersion.txt`에서 요구 Unity 버전을 읽고, 그 버전의 Unity Editor를 물리 `projectPath`로 실행합니다. 기동 helper 내부의 첫 실행은 `unity open <물리 절대 경로>`이며, Editor가 Pipeline 인스턴스를 열려면 프로젝트에 `com.unity.pipeline` 패키지가 있어야 합니다(`unity pipeline list`의 `Pipeline` 열이 `true`).

- 같은 물리 프로젝트 경로와 Unity 버전에 정확히 대응하는 전용 Editor가 하나 이미 실행 중이면 재사용할 수 있습니다.
- 해당 경로의 Editor가 없으면 별도 Editor를 실행하고, 다른 checkout이나 다른 worktree를 연 Editor는 재사용하지 않습니다.
- 같은 물리 경로를 가리키는 Editor가 여러 개이거나 Editor의 경로·버전을 확정할 수 없으면 모호성을 해소할 때까지 상주 Editor 경로를 쓰지 않고 백그라운드 경로로 진행합니다.
- 병렬 Unity 작업 동안 각 linked worktree는 자신의 전용 Editor 하나만 사용합니다.
- CLI와 Pipeline 패키지의 호환 버전을 사전 확인합니다. `unity pipeline list`의 `업데이트 가능` 열이 `true`이거나 `editor_status`가 Pipeline 버전 오류(예: `0.6.0-exp.1 이상 필요`)로 실패하면 `background: editor_unavailable: pipeline_outdated`로 기록하고, `.agents/AGENTS.md`의 Pipeline 최신 유지 규칙에 따라 `unity pipeline upgrade --project-path <물리 절대 경로>`로 갱신하고 실행 중인 Editor에 반영한 다음 `editor_status`를 재검증합니다. Pipeline 패키지가 없는 프로젝트에 새로 추가하는 것은 사용자 승인 뒤 수행합니다.

### CLI 실행 실패 시 Unity 앱 직접 실행

Editor 프로세스 기동은 `bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`를 최초 진입점으로 사용합니다. helper가 CLI를 한 번 시도하고 실패 시 동일 버전 Unity 앱을 한 번 직접 실행합니다. 이미 `unity open` 실패를 확인했다면 `--skip-cli`로 CLI 재시도를 생략합니다. 실행 중 Editor와의 상호작용은 계속 CLI·Pipeline만 사용하며, 앱 실행 성공만으로 `ready`를 인정하지 않습니다. `--unity-app <물리 Unity.app 경로>`로 기본 Hub 위치 밖의 앱을 지정할 수 있습니다. 앱의 버전과 실행 파일을 검증하며, 잠금이나 같은 프로젝트의 기존 Editor가 있으면 중복 실행하지 않습니다. 자동 설치·강제 종료·잠금 삭제는 하지 않습니다. 직접 실행 후에도 아래 Pipeline identity 확인을 모두 통과해야 하며 실패하면 백그라운드 경로로 전환합니다. 명령·CLI 실패 원인·앱 경로·버전·`launched_via`와 후속 identity 판정을 기록합니다.

## Pipeline 인스턴스 발견과 고정

대상 Editor에 명령을 보내기 전에 다음 순서로 identity와 준비 상태를 확인합니다. 이 절차는 네 실행 루트 유형 모두에 적용합니다.

1. `unity status --format json`으로 실행 중인 Pipeline 인스턴스 목록(`port`, `project`, `version`, `pid`, `state`)을 읽습니다.
2. 각 후보의 `project`를 물리 절대 경로로 비교하여 대상 Unity 프로젝트 루트와 exact match인 후보만 남깁니다.
3. 후보가 정확히 하나일 때 그 `pid`·`port`·`version`을 기록합니다. 후보가 없거나 둘 이상이면 백그라운드 경로로 진행합니다.
4. `unity command editor_status --project-path <물리 절대 경로> --format json`으로 `projectPath` exact match, `status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용), `compiling=false`, `unityVersion`이 `ProjectVersion.txt`와 같은지 다시 확인합니다.
5. `unity list --project-path <물리 절대 경로>`로 프로젝트가 등록한 명령과 추가 규칙을 확인합니다.
6. 물리 `projectPath`가 exact match이고 `editor_status`가 `ready`(승인된 PlayMode 관측·정지·캡처 작업은 `playing`)일 때만 바인딩을 `ready`로 기록합니다.

`unity command`·`unity list`에는 `--project-path <물리 절대 경로>`, `unity run`에는 위치 인자 `<물리 절대 경로>`를 필수로 지정합니다. 자동 감지, 현재 디렉터리 기본값, 이름·glob 해석에 의존하지 않습니다. 초기 편집·컴파일 준비는 `status=ready`를 요구합니다. 사용자가 현재 승인한 PlayMode 관측·정지·캡처 작업은 `projectPath`·`unityVersion` 일치와 `compiling=false`를 유지하면 `status=playing`도 허용하며, `playing` 자체를 `editor_unavailable`로 판정하지 않습니다. port는 인스턴스 identity가 아니며 CLI와 Pipeline 서버가 관리합니다. 프로젝트 파일에 port나 endpoint 설정을 쓰지 않으므로 `ready` 전 쓰기 예외는 없습니다.

### `unity status`와 `editor_status`가 다를 때의 명시적 판정

위 발견 순서의 후보 수·물리 경로·버전·명령 목록 조건을 모두 유지합니다. `unity status`의 `state`는 진단 입력이며 최종 준비 응답은 동일 대상의 최신 `editor_status`입니다.

| 관측 | 판정 |
|---|---|
| 후보 하나·exact match, `editor_status` 경로·버전 일치·`ready`·`compiling=false`, `unity list` 성공 | 바인딩 `ready`; 승인된 작업만 수행 |
| 위 조건은 충족하지만 `unity status state=unreachable` | 같은 물리 대상의 `unity pipeline list`에서 서버 reachable까지 확인하고 불일치 원문·조회 시각을 보관한 경우 `ready`; 확인 실패는 `background: editor_unavailable` |
| 후보 없음/복수, 경로·버전 불일치, Pipeline 연결 또는 `editor_status`·명령 목록 확인 실패 | `background: editor_unavailable`; 다른 Editor로 대체 금지 |

`unity status state=ready`만 있고 최종 응답이 없으면 `ready`가 아닙니다. 승인된 PlayMode 관측·정지·캡처에 한한 `playing` 허용은 위 표에서도 동일하게 적용합니다. 이후 연결이 끊기면 다시 identity를 고정하기 전의 새 결과를 인정하지 않습니다.

## 구현 차단과 복구

실행 루트·물리 경로를 확정할 수 없으면 Unity 구현 서브 에이전트를 파견하거나 Unity 구현 파일을 수정하지 않습니다. 바인딩만 `ready`가 아니면 백그라운드 경로로 진행합니다. 작업 도중 Editor 연결이 끊기거나 `editor_status`의 `projectPath`·`unityVersion`이 달라지면 즉시 상주 Editor 경로를 중단하고 그 이후의 Editor 컴파일·Console 결과를 증거로 사용하지 않으며, 구현·검증은 백그라운드 경로로 이어갑니다.

이 차단은 Editor 의존 작업에 적용합니다. Editor 비의존 변경은 위 "적용 범위"에 따라 게이트 없이 진행하고, Editor 의존 파일을 수정해야 하는 시점부터 이 절을 적용합니다.

복구할 때는 대상 물리 프로젝트 경로와 `ProjectVersion.txt` 버전, 전용 Editor 상태를 차례로 다시 확인하고 `unity status` 조회부터 `editor_status`·`unity list` 확인까지 전체 순서를 다시 수행합니다. 같은 안전 경계를 복구할 수 없으면 사유를 정확히 기록하고 백그라운드 경로로 진행합니다. 다른 Editor, 메인 checkout 또는 첫 인스턴스로 대상을 바꾸지 않습니다.

## 서브 에이전트 전달 정보

Unity 구현 전달 패킷에는 기존 요구사항과 함께 다음 정보를 포함합니다.

- 실행 루트 유형과 물리 절대 경로
- `ProjectSettings/ProjectVersion.txt`의 Unity 버전과 대상 Editor 상태, `linked_worktree`이면 전용 상태
- Pipeline 인스턴스 `pid`·`port`·`version`
- exact match로 확인한 물리 `projectPath`
- `editor_status` 결과(`status`, `compiling`, `unityVersion`)
- 동일 실행 루트의 대상 Editor에서 수행할 컴파일·구문 오류 확인 방법(`unity command recompile` 후 `recompile_status`, 또는 배치 컴파일)
- Editor 상태: `ready` 또는 `background: editor_unavailable <사유>`(백그라운드 경로면 CLI 명령·물리 경로·버전이 identity)
- Editor 의존 여부(`의존` 또는 `비의존: 근거`). `비의존`이면 인스턴스·`projectPath`·`editor_status` 항목은 `N/A`로 두고 컴파일 확인 방법은 배치 CLI 기준으로 적습니다

메인 에이전트는 위 값이 모두 확정되고 Unity 작업 차단 상태가 `ready` 또는 `background: editor_unavailable`인 경우에 구현 서브 에이전트를 파견합니다(`blocked`는 실행 루트 미확정일 때만). 구현 서브 에이전트는 전달받은 identity를 확인하며, 값이 누락되거나 현재 상태와 다르면 추측해 진행하지 않고 메인 에이전트에 보고합니다. Editor 비의존 변경이면 실행 루트·물리 경로, Editor 의존 여부와 근거, CLI 컴파일 확인 방법이 확정되면 파견합니다.

## 컴파일·증거 경계

로컬 Unity Editor 컴파일과 Console 증거는 전달 패킷에 기록된 동일 실행 루트의 물리 프로젝트 루트와 대상 Editor의 Pipeline 인스턴스에서 `unity command`로 얻은 결과만 인정합니다. linked worktree라면 해당 worktree의 전용 Editor여야 합니다.

- 다른 checkout, 다른 worktree, 메인 checkout 또는 다른 Editor의 성공 결과는 대상 변경의 로컬 Unity Editor 증거가 아닙니다.
- 증거에는 실행 루트 유형과 물리 경로, Unity 버전, Pipeline 인스턴스 `pid`·`port`, 물리 `projectPath`, `editor_status` 결과를 함께 기록합니다.
- 바인딩 변경이나 연결 상실 뒤에는 identity와 준비 상태를 다시 확정하고 새 증거를 수집합니다.
- 사용자가 현재 승인한 `unity_ci` 증거는 동일 `change_id`, 선택된 `build_authority`와 [Unity 기능·마일스톤 검증 정책](../coding-standards/core/unity-validation.md)의 evidence 계약을 충족할 때 별도 권위로 인정합니다. 이는 다른 checkout의 로컬 Editor 결과를 인정하는 예외가 아닙니다.
- 올바른 Editor 바인딩은 구현 전 안전 게이트일 뿐 컴파일, 테스트, 런타임, 씬·Inspector·시각 검증 또는 Player Build의 통과를 뜻하지 않습니다.
- Editor 비의존 변경의 컴파일 증거는 동일 실행 루트에서 [Unity CLI](unity-cli.md)로 얻은 결과 또는 이미 상주하는 전용 Editor의 결과를 인정합니다. 둘 다 없으면 `not_run`으로 기록하고 성공으로 주장하지 않습니다.
- 백그라운드 경로의 컴파일·테스트·빌드 증거는 동일 물리 경로를 명시한 Unity CLI 결과(명령·경로·버전·로그·종료코드 기록)를 상주 Editor 결과와 동등하게 인정합니다.
- 사용자에게 현재 허용되지 않은 검증은 계속 `not_run`으로 기록합니다.

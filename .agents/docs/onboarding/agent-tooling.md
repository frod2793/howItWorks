# 에이전트 도구 준비

이 하네스는 구현 품질과 코드베이스 이해를 위해 Karpathy Guidelines, Superpowers, Understand-Anything을 사용합니다. 도구 준비 상태는 Unity 게임 코드의 품질과 별도 경계이며, 도구 누락을 Unity 코드 린트 실패로 간주하지 않습니다.

## Unity worktree·Editor 준비

이 준비 절차는 실행 중 Editor가 필요한 작업에만 적용합니다. 배치로 완결되는 테스트·빌드·진단은 [Unity CLI 실행 가이드](unity-cli.md)의 CLI 단일 원칙에 따라 Editor 실행과 바인딩 없이 수행합니다.

Unity와의 모든 상호작용은 Unity CLI와 Pipeline 패키지(`com.unity.pipeline`)로만 수행하며 Unity MCP 서버·클라이언트는 설치하거나 연결하지 않습니다. 프로젝트에 Pipeline 패키지가 없으면 `unity pipeline list`의 `Pipeline` 열이 `false`이며, 패키지 추가는 제품 변경이므로 사용자가 현재 요청한 경우에만 수행합니다. Unity 공식 `unity-cli` 에이전트 스킬은 `unity skill install claude-code`로 사용자 전역 스킬 디렉터리에 설치할 수 있으며, 하네스 규칙과 충돌하면 하네스가 우선합니다.

Unity 작업에서는 구현 서브 에이전트를 파견하기 전에 다음 순서로 대상 실행 루트와 Editor 바인딩을 확정합니다.

1. `git rev-parse --show-toplevel`, `--git-dir`, `--git-common-dir`, `--show-superproject-working-tree`와 물리 절대 경로로 실행 루트를 감지합니다.
2. `linked_worktree`이면 `ProjectSettings/ProjectVersion.txt` 버전과 물리 `projectPath`로 전용 Unity Editor를 준비합니다(`bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`; 이미 CLI 실패를 확인했으면 `--skip-cli`).
3. `unity status --format json`에서 `project`가 대상 물리 프로젝트 루트와 exact match인 인스턴스 하나를 찾아 `pid`·`port`·`version`을 기록합니다.
4. `unity command editor_status --project-path <물리 경로> --format json`으로 `projectPath` exact match, `status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용), `compiling=false`, `unityVersion` 일치를 확인합니다.
5. `unity list --project-path <물리 경로>`로 프로젝트가 등록한 명령과 추가 규칙을 먼저 확인합니다.
6. 바인딩이 `ready`이면 상주 Editor 경로로, 아니면 `background: editor_unavailable`을 기록하고 백그라운드 경로로 Unity 구현 서브 에이전트를 파견합니다.

3~5단계의 identity 확인은 네 실행 루트 유형 모두에 적용하고, 2단계의 전용 Editor는 linked worktree에 추가로 적용합니다. port는 identity가 아닙니다. `unity command`·`unity list`에는 `--project-path <물리 절대 경로>`, `unity run`에는 위치 인자 `<물리 절대 경로>`를 필수로 지정합니다. CLI와 Pipeline 패키지의 호환 버전을 사전 확인합니다. `unity pipeline list`의 `업데이트 가능` 열이 `true`이거나 `editor_status`가 Pipeline 버전 오류(예: `0.6.0-exp.1 이상 필요`)로 실패하면 `background: editor_unavailable: pipeline_outdated`로 기록하고, `.agents/AGENTS.md`의 Pipeline 최신 유지 규칙에 따라 `unity pipeline upgrade --project-path <물리 절대 경로>`로 갱신하고 실행 중인 Editor에 반영한 다음 `editor_status`를 재검증합니다. Pipeline 패키지가 없는 프로젝트에 새로 추가하는 것은 사용자 승인 뒤 수행합니다. 1단계(실행 루트·물리 경로) 실패만 Unity 구현 전체를 중단하며, 그 밖의 단계 실패는 백그라운드 경로로 진행합니다. 다른 Editor, 메인 checkout 또는 첫 인스턴스로 대상을 바꾸지 않습니다. 상세 판별·복구·증거 기준은 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)를 따릅니다.

이 절차는 Editor 의존 작업에 적용합니다. Editor 비의존 변경(기존 `.cs` 로직 수정만·직렬화 표면 불변·scene/prefab/asset/UI 배치/Inspector 값 무변경)의 정의와 생략 조건은 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)의 적용 범위를 따릅니다.

Editor 프로세스 기동은 `bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`를 최초 진입점으로 사용합니다. helper가 CLI를 한 번 시도하고 실패 시 동일 버전 Unity 앱을 한 번 직접 실행합니다. 이미 `unity open` 실패를 확인했다면 `--skip-cli`로 CLI 재시도를 생략합니다. 실행 중 Editor와의 상호작용은 계속 CLI·Pipeline만 사용하며, 앱 실행 성공만으로 `ready`를 인정하지 않습니다.

## 상태 확인

상태 확인은 사용자 홈과 전역 설정을 변경하지 않습니다.

```bash
bash .agents/scripts/setup/check-agent-tooling.sh --check
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup/check-agent-tooling.ps1 -Check
```

출력 상태는 `installed`, `disabled`, `broken`, `missing`입니다. `disabled`와 `broken`은 기존 설치를 자동으로 덮어쓰지 않고 복구 안내만 제공합니다.

## Unity CLI 상태 확인

Unity 검증·빌드 실행이 요청된 작업에서는 Unity CLI 상태를 함께 확인합니다. 기준 플랫폼은 macOS이며 기본 설치 경로는 `~/.unity/bin/unity`입니다.

```bash
bash .agents/scripts/setup/check-unity-cli.sh --check
bash .agents/scripts/setup/check-unity-cli.sh --preflight
```

출력 상태는 `installed`, `broken`, `missing`입니다. CLI 누락은 Unity 코드 린트 실패가 아니며, 설치·업그레이드는 사용자가 현재 요청한 경우에만 수행합니다. 명령과 게이트 매핑, batchmode 경계와 증거 통합은 [Unity CLI 실행 가이드](unity-cli.md)를 따릅니다.

## 적용 시점

모든 코드 작성, 기능 구현, 리팩토링, 테스트 및 Bash·PowerShell 스크립트 작성·수정에는 karpathy-guidelines를 적용합니다.

- 작업 전 가정, 사용자 승인 범위와 검증 기준을 고정하고 최소 변경으로 구현합니다.
- 모든 구현 파일 생성·수정은 `superpowers:subagent-driven-development` 성격으로 구현 서브 에이전트가 수행합니다. 메인 에이전트는 계획·규칙 전달·리뷰를 담당하고 직접 구현하지 않습니다.
- `karpathy-guidelines`가 미설치이면 작업 전에 보고하고 사용자 지시를 기다립니다. 자동 네트워크 설치하지 않습니다.
- 설치·복구는 사용자 현재 요청 범위에서 명시적으로 요청된 경우에만 수행합니다.
- 창의적 변경: `superpowers:brainstorming`을 먼저 적용합니다.
- 기능·버그 수정: `superpowers:systematic-debugging`을 적용하되 진단·재현 실행은 현재 승인 범위에 한정합니다. `superpowers:test-driven-development`는 사용자가 RED·테스트 실행을 현재 요청한 범위에서만 실행합니다. 권한이 `none`이면 해당 단계는 `not_run`으로 남기고 향후 검증 명세만 유지합니다.
- 완료 전: `superpowers:verification-before-completion`은 사용자가 현재 요청한 검증 범위에서만 실행합니다. 적용 가능한 코드·스크립트의 컴파일·구문 오류 확인은 별도의 필수 단계이고, 그 밖의 검증은 사용자가 현재 요청한 경우에만 실행합니다.
- 메인 에이전트의 독립 정적 코드 리뷰에는 필요 시 `superpowers:requesting-code-review`를 사용할 수 있습니다. 중요한 지적은 같은 구현 서브 에이전트가 수정하고 메인 에이전트가 재리뷰합니다.
- 초기 프로젝트 파악과 아키텍처·파일 관계 질의: graphify가 설치되어 있으면 graphify(그래프 빌드 1회 후 쿼리)로 일원화하고, graphify 미설치 환경에서만 `understand`·`understand-chat`·`understand-explain`을 대체 경로로 사용합니다. 같은 프로젝트에 두 그래프를 이중 빌드하지 않습니다.
- 변경 영향 검수·신규 참여자 안내: graphify 그래프(`graphify-out/`)가 있으면 graphify 쿼리(`query`·`path`·`explain`)로 수행합니다. graphify가 없고 Understand 그래프(`.ua/knowledge-graph.json`)가 이미 있을 때만 `understand-diff`·`understand-onboard`를 사용합니다. 이를 위해 그래프를 새로 빌드하거나 변환하지 않습니다.

사용자의 현재 승인 범위와 검증 권한은 스킬의 기본 워크플로보다 우선합니다. 스킬 적용은 린트, 테스트, 런타임 검증, Player Build 또는 외부 CI 실행 권한을 추가하지 않습니다. 요청하지 않은 검증은 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done으로 주장하거나 전환하지 않습니다.

Understand-Anything의 기본 설치 소스는 `Egonex-AI/Understand-Anything`이며, `Lum1104/Understand-Anything`은 원작자 출처 별칭으로 기록합니다.

## 백엔드 중립 스타일 규칙과 Claude Code 스타일 플러그인

Ponytail·ADHD의 의미 규칙은 백엔드와 무관하게 적용합니다. 해당 백엔드에 실제 제공된 스킬·플러그인과 최신 사용자 직접 지시를 따르며, 아래 구현·보고 원칙을 지킵니다.

- `ponytail`: 최소 변경·최소 파일, 기존 코드와 표준 라이브러리 재사용 우선, 요청되지 않은 추상화 금지.
- `i-have-adhd`: 결론과 다음 행동 먼저, 다단계 작업은 번호 목록, 진행 상태와 구체적인 시간 표시, 불필요한 서두 제거.

Claude Code 환경에서만 사용자 홈의 `.claude/plugins/installed_plugins.json`으로 Claude 플러그인 설치 상태를 확인합니다. Codex 등 다른 백엔드에 Claude 설치 JSON을 요구하지 않습니다. 해당 백엔드의 제공 스킬·직접 지시를 적용하며, 미설치는 실패가 아니며 자동 설치하지 않습니다. 설치·복구는 사용자가 현재 요청한 경우에만 수행합니다.

설치 상태, 현재 세션 활성 상태, 실제 행동 준수 증거는 구분합니다. 설치만으로 활성·준수를 주장하지 않고, 명령·diff·보고 근거가 없으면 `unknown` 또는 `not_run`으로 기록합니다. 스타일은 사용자 목표·대상·플랫폼·지정 패턴·아키텍처·승인 범위·보호 경로·검증 증거 기준을 변경하지 않습니다. 충돌하면 하네스의 승인 범위와 증거·문서 의무가 우선합니다.

figma·Gamma·Atlassian 등 외부 서비스 MCP·플러그인은 하네스 표준 활용 대상이 아니며, 사용자의 현재 요청에 명시된 범위에서만 사용합니다.

## 보조 도구: graphify·headroom

다음 보조 도구가 설치되어 있으면 적극 활용합니다. 미설치는 실패가 아니며 설치는 사용자가 현재 요청한 경우에만 수행합니다.

- graphify(코드베이스 지식그래프): 실행 루트에 그래프 산출물(`graphify-out/`)이 있으면 프로젝트 파악·아키텍처·파일 관계 질의를 grep보다 graphify 쿼리로 먼저 시도합니다. 그래프 빌드는 초기 프로젝트 파악 단계 또는 사용자 요청 시 1회 수행합니다. 그래프 빌드·구조 질의는 graphify로 일원화하며, understand 계열 그래프(`.ua/`)와 이중 빌드하지 않습니다.
- headroom(컨텍스트 압축 프록시): Claude·Codex 세션 기동은 `headroom wrap claude` / `headroom wrap codex` 경유를 권장합니다(요청 토큰 압축, 로컬 프록시·복원 가능). 프록시 장애가 감지되면 일반 기동으로 폴백하고 트러블슈팅 사례로 기록합니다. 압축은 증거 기준과 검증 권한을 변경하지 않습니다.

## 무포커스 플레이·UI 검증: agent-desktop

플레이 기반 테스트의 UI 관측·조작은 사용자 포커스·마우스·키보드를 가져가지 않도록 [agent-desktop](https://github.com/vercel-labs/agent-desktop)을 기본 headless 모드로 사용합니다. 미설치는 실패가 아니며 설치는 사용자가 현재 요청한 경우에만 수행합니다.

- 사용 전 `agent-desktop status`로 접근성·화면 기록 권한을 확인하고, 설치된 버전과 일치하는 `agent-desktop skills get desktop`·`agent-desktop skills get platform`을 읽습니다.
- `agent-desktop list-windows --app <앱>`으로 창을 확인하고 `agent-desktop snapshot --app <앱> --window-id <id> -i --compact`로 관측합니다. 동작은 최신 snapshot의 qualified ref(`@<snapshot_id>:eN`)로만 수행하고, 동작 후 `snapshot`·`get`·`is`로 결과를 다시 읽어 확인합니다. 재시도는 `disposition.retry`가 `safe`일 때만 합니다.
- 금지: `--headed`, `focus`·`focus-window`, `launch --activate` 등 앱·창 활성화, `mouse-*`·`hover`·`drag`·`key-down`·`key-up` 등 전역 물리 키보드·마우스 입력. headless 실패를 headed 모드나 물리 입력으로 우회하지 않습니다.
- Unity Game 캔버스처럼 접근성 노드가 없는 UI는 승인된 Unity CLI·Pipeline 자동화로 수행하고, 그것도 없으면 `not_run`으로 기록합니다.
- Unity 컴파일·Play 상태·테스트 명령은 [Unity CLI 실행 가이드](unity-cli.md)와 물리 프로젝트 identity 게이트를 그대로 따르며 agent-desktop으로 대체하지 않습니다.
- Pipeline 패키지 갱신 반영은 Editor 창 포커스가 아니라 `unity command package resolve --project-path <물리 절대 경로>` 후 `recompile_status` 확인으로 수행하고, 반영되지 않으면 Editor를 재시작합니다.

## 외부 대기 타임아웃

Editor·Pipeline 명령·빌드 등 외부 응답 대기는 기본 3분을 상한으로 합니다. 상한을 초과하면 해당 대기를 중단하고, 상태를 트러블슈팅 사례로 기록한 뒤 복구 절차로 진입합니다. 복구 시 해당 실행 루트의 Editor 강제 종료는 허용되며 다른 실행 루트의 Editor는 건드리지 않습니다. stale 인스턴스·정지 모달·소실된 빌드 job을 정상 대기로 오인해 무한 대기하지 않습니다. 장시간 명령은 `unity command --detach`로 제출하고 `unity job`으로 완료를 확인합니다.

대기는 폴링이 아니라 백그라운드 실행과 완료 이벤트 수신을 우선합니다(예: Claude Code의 백그라운드 실행·Monitor 알림). 이벤트 수단이 없는 환경에서만 타임아웃 폴링을 사용합니다.

## Claude Code 적용 키트

Claude Code는 `.agents/AGENTS.md`를 자동 로드하지 않으므로, 하네스를 새 프로젝트에 적용할 때 다음 두 파일을 함께 설치해 Claude 네이티브 진입점을 만듭니다.

1. 루트 또는 상위 경로에 `CLAUDE.md`가 없을 때만 `.agents/templates/CLAUDE.md`를 프로젝트 루트에 복사합니다. 기존 파일이 있으면 그 파일의 사용자 지정 내용을 보존하고 "하네스 준수 (최우선 — 이탈 금지)" 섹션만 병합합니다. 전체 파일 덮어쓰기는 허용하지 않습니다.
2. `.agents/templates/claude-settings.json` → 프로젝트 루트 `.claude/settings.json`으로 복사해 결정론 보호 hook(.agents 삭제 차단)을 활성화합니다. 기존 settings.json이 있으면 hooks 항목만 병합합니다.

Codex는 전역 지침에 따라 `.agents/AGENTS.md`를 직접 읽습니다. 보호 hook은 구조화된 `tool_name`·`tool_input` JSON을 검사하며 Bash뿐 아니라 Write·Edit·MultiEdit·NotebookEdit·apply_patch의 관리 파일 수정을 차단합니다. 다른 백엔드에서 재사용하려면 실제 hook 등록 지원과 동일 JSON 입력 계약을 확인해야 하며, 설치되어 있다는 이유만으로 활성 보호를 주장하지 않습니다. Python3 부재 또는 잘못된 JSON은 차단합니다. 설치 시 hook 명령은 해당 프로젝트의 물리 절대경로로 고정하고, 실행 파일 부재·검사기 오류 등 모든 실패를 exit 2로 변환합니다. 새 키트 launcher는 Claude가 제공한 `CLAUDE_PROJECT_DIR`의 물리 경로에 고정합니다. 이 값이 없으면 exit 2로 중단하고, 현재 폴더에서 상위로 검색하여 중첩 패키지의 가짜 hook을 선택하지 않습니다. 프로젝트 밖 cwd에서도 고정된 hook을 호출하며 실제 수정 대상 경로를 검사합니다.

관리 대상인 `.agents/AGENTS.md`, scripts/config, work-items/active·completed 직접 수정은 차단하고, 정상 reports, work-items/evidence, artifacts, docs/exec-plans·product-specs·troubleshooting 기록과 workflow CLI 상태 저장은 허용합니다. 보호 동기화는 [병렬 작업 규칙](parallel-work.md)의 제외 계약을 따릅니다. 대소문자 별칭·보호 경로 glob·명령 감싸기·Git의 복구/초기화/보관 명령에도 같은 경계를 적용합니다. 보호 대상이 포함된 해석 불가능한 동적 명령은 안전한 것으로 추정하지 않습니다.

이 hook은 알려진 오작동을 차단하는 방어입니다. 같은 OS 사용자 권한으로 임의 셸·언어·eval을 실행하거나 스크립트와 증거를 함께 변조할 수 있으므로 완전한 샌드박스나 인증된 CI를 대체하지 않습니다. 증거의 형식·내용 검사와 실제 명령 실행 provenance는 구분하며, 키트 설치는 역할 경계·검증 권한을 변경하지 않습니다.

## 역할별 에이전트·모델 분담

역할 구분(메인 에이전트의 계획·규칙 전달·독립 리뷰, 구현 서브 에이전트, 검수 에이전트)은 기존 규칙을 따릅니다. 모든 역할의 백엔드·모델·추론 강도는 고정하지 않으며 난이도에 따라 자동 선택하지 않습니다.

- 설계·계획·설계 검수, 구현·구현 검수, 기계적 검수·검증 실행 등 각 역할의 매 파견 전 사용자에게 백엔드·모델·추론 강도를 질문하고 답변으로 배정을 확인합니다.
- 사용자가 현재 파견에 대해 이미 답변한 경우 그 동일 파견의 질문만 반복하지 않습니다. 이후 사용자가 변경하면 가장 최근의 명시적 지시를 따릅니다. 현재 작업의 배정을 하네스 기본값으로 저장하지 않습니다.
- 사용자 선택이 확정되기 전에는 파견하지 않으며, 답변 없이 임의 선택·대체 파견하지 않습니다. 파견 전 모델 질문을 요구한 사용자의 최신 명시적 지시는 일반 차단 금지보다 우선합니다.
- 사용량 한도·호출 실패 등으로 다른 백엔드·모델·추론 강도로 fallback하려면 대체 파견 전 사용자에게 다시 질문하고 답변으로 배정을 확인합니다.
- 사용자가 현재 작업의 Codex 내부 권장 자동 선택을 명시적으로 허용하면 그 승인 범위에서만 선택·근거를 기록합니다. 지정 검수 터미널·독립 컨텍스트는 유지하며, 이 예외를 다른 작업의 기본값으로 저장하지 않습니다.
- 모델 배정은 역할 경계, 검증 권한과 증거 기준을 변경하지 않습니다. 모든 검수는 동일한 증거 기준(`not_run` 명시, 실측 근거)을 따릅니다.
- 서브 에이전트 호출 채널은 실행 환경이 지원하면 orca CLI 단일 게이트웨이로 통일합니다. 백엔드(Codex·Claude·Antigravity 등)는 해당 역할에 대한 사용자 배정으로 결정하며 채널 통일이 백엔드 다양성을 제한하지 않습니다. orca를 사용할 수 없는 환경에서만 해당 백엔드 CLI 직접 실행을 예외 경로로 사용하고 사유를 기록합니다.
- Codex에서 orca CLI가 `runtime_access_denied`(EPERM)로 거부되면 같은 명령을 반복하지 않습니다. 원인은 Codex 샌드박스입니다. `~/.codex/config.toml` 최상위에 `sandbox_mode = "workspace-write"`와 `[sandbox_workspace_write]`의 `network_access = true`를 두고, `codex app-server daemon restart` 후 실행 중인 Codex 세션을 재시작합니다. 기존 세션은 시작할 때의 샌드박스를 유지합니다. `check-agent-tooling.sh --check`는 이 설정이 없으면 경고합니다. 사용자 전역 설정 변경은 사용자가 요청한 경우에만 수행합니다.
- 에이전트 간 통신은 Orca 오케스트레이션을 우선 사용합니다.
  - **Orca 오케스트레이션(`orca orchestration`, 우선)**: 구현 파견과 완료 보고, 검수 요청과 결과 수신, 질문과 답변(ask/reply), 병렬 작업 대기, 작업 의존 순서(DAG), 결정 게이트 등 에이전트끼리 주고받는 모든 통신에 사용합니다. `worker-start`로 파견하고 `worker_done`·escalation·question은 Orca가 깨워 전달하는 메시지로 받습니다. 명령·대기·정리 절차는 현재 설치된 orca 버전의 가이드·preamble이 우선합니다. 파일 폴링, 감시 스크립트, 반복 `check`나 `terminal read`로 완료를 추정하지 않습니다.
  - **orca CLI(terminal·worktree 명령)**: 워크트리 생성·관리, 터미널 상태 확인, 감독 없는 소유권 인계에 사용합니다. 오케스트레이션을 사용할 수 없을 때는 에이전트 간 통신도 `orca terminal send`·`read`·`wait`로 대신하고 완료 확인 방법과 사유를 기록합니다.
  - **오케스트레이션 구성 파악(필수)**: 사용 전에 `orca skills get orchestration`으로 현재 orca 버전과 일치하는 가이드를 읽습니다. 가이드의 역할 분류(감독자·파견 작업자·감독 없는 인계·일반 터미널 에이전트)로 자기 역할을 먼저 정하고, 다음 구성을 따릅니다.
    - 감독자: 독립 작업을 모두 `worker-start`로 띄운 뒤 턴을 종료하고, Orca가 깨우면 받은 메시지를 처리합니다(질문은 `reply`, `worker_done`은 기대한 Dispatch와 대조, 깨우기가 지정한 `check` 명령만 실행). receipt나 `worker-list`의 `next`가 있으면 따릅니다. 자동 깨우기가 없는 orca 버전에서만 그 버전 가이드가 정한 `check --wait`·ack·`worker-retain`·`worker-release` 절차를 fallback으로 사용합니다. 턴을 끝내면 즉시 자동 재개되는 goal 모드(Codex 등)가 활성이면 자동 깨우기가 있어도 턴을 종료하지 않고 제한 시간 블로킹 대기 1회(`orca orchestration check --wait --timeout-ms 600000` 등)로 받습니다. 실행 중 worker가 있거나 승인·답변 대기만 남은 상태는 goal을 `blocked`로 둘 사유가 아니며, `blocked` 전에는 무엇이 없어서 무엇을 못 하는지와 재개 조건을 보고합니다. `update_goal`에는 active 상태가 없으므로 재개는 `/goal resume`으로 하며 blocked 보고에 함께 적습니다. blocked 세션에 사용자 답변·승인이나 Orca 깨우기로 새 턴이 와 재개 조건이 충족되면 다시 묻지 않고 `orca terminal send --terminal "$ORCA_TERMINAL_HANDLE" --text "/goal resume" --enter`를 턴의 마지막 행동으로 지연 없이 동기 실행하고 바로 턴을 끝내 재개하며(입력은 대기열에 들어갔다가 턴 종료 직후 적용됨, nohup·sleep 지연 예약은 명령 종료 시 함께 종료되므로 쓰지 않음), 핸들이 없거나 전송이 실패하면 사용자에게 `/goal resume` 입력을 요청합니다. 침묵이나 timeout은 실패가 아니라 중간 상태이며, 종료가 확인되지 않으면 중지·재시도·release하지 않습니다.
    - 감독 알림 위치: 새 Run의 감독자·알림 수신 터미널은 사용자가 입력 중인 대화 PTY와 분리된 전용 터미널로 둡니다. Orca 1.4.253의 PTY 전달은 같은 입력 경로에 알림 문자열을 쓰고 약 500ms 뒤 Enter를 보내며 그 사이 사용자 초안·IME를 다시 확인하지 않으므로, 사용자 대화 PTY에서 받으면 입력 중인 내용이 함께 제출될 수 있습니다. 결과는 전용 터미널에서 처리한 뒤 사용자 대화에는 요약만 전달합니다.
    - 파견 작업자: 주입된 preamble의 명령과 ID만 사용하고, 막히면 `ask`로 묻고, 마지막에 `worker_done`을 `--outcome succeeded` 또는 `failed`로 정확히 한 번 보냅니다.
    - 작업 명세(spec)에는 대상·변경·제약·편집 범위·완료 증거를 모두 적습니다.
    - DAG·모델 지정·같은 터미널 재사용·검수 소유, 재시도·중지·release, 원격 배치, 메시지·결정 게이트는 해당 상황에서 `orca skills get orchestration --reference references/<파일>.md`로 그 참조 문서만 읽고 따릅니다(`--references`로 목록 확인).
  - 두 방식 모두 호출 채널의 사용 방식일 뿐 역할 분담·검증 권한·증거 기준을 바꾸지 않습니다.
- 호출 채널을 먼저 정한 뒤 모델과 컨텍스트를 선택합니다. orca를 사용할 수 있으면 orca로 호출하며, 사용할 수 없을 때만 사유를 기록하고 백엔드 CLI 예외를 사용합니다. 선택된 채널이 컨텍스트 fork를 지원하는 조사·검토에 한해 fork를 사용할 수 있습니다. fork 최적화를 이유로 호출 채널이나 확정된 구현 역할을 바꾸지 않습니다. 독립 컨텍스트가 필요한 구현·검수는 같은 채널에서 새 컨텍스트를 사용합니다.

이 절은 배포 가능한 역할별 모델 분담 계약의 정본입니다. 프로젝트별 사용자 예외는 해당 범위에만 적용하며, 어떤 배정도 역할 경계와 증거 기준을 변경하지 않습니다.

## 명시적 설치

누락된 도구의 설치가 사용자 현재 요청 범위에 명시된 경우에만 다음 명령을 실행합니다.

```bash
bash .agents/scripts/setup/check-agent-tooling.sh --install-missing
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup/check-agent-tooling.ps1 -InstallMissing
```

이 모드는 네트워크와 전역 설정을 변경할 수 있습니다. 초기화·린트·CI는 설치 모드를 자동 호출하지 않습니다. 원격 스크립트를 파이프로 즉시 실행하지 않고, 로컬로 받은 설치 진입점을 실행합니다.

설치 전에는 `CODEX_HOME/plugins/cache`, `CODEX_HOME/skills`, 사용자 홈의 전역 skills 디렉터리, `$HOME/.understand-anything`의 물리 경로가 각각의 허용 루트 안에 있는지 확인합니다. 중간 심볼릭 링크나 Junction이 사용자 홈 또는 `CODEX_HOME` 밖으로 빠져나가면 네트워크·설치 명령을 실행하기 전에 종료 코드 `3`으로 거부합니다.

Superpowers는 공식 Codex 설치 방식에 따라 `${CODEX_HOME:-$HOME/.codex}/superpowers`에 저장소를 받고 사용자 홈의 전역 `superpowers` 스킬 링크를 해당 저장소의 `skills`에 연결합니다. 자동 설치는 임시 경로에 clone한 뒤 `using-superpowers/SKILL.md`를 검증하고 원자적으로 이동합니다.

## `disabled`·`broken` 수동 복구

상태 검사가 `disabled` 또는 `broken`을 보고하면 자동으로 덮어쓰지 않습니다. 점검기는 `config.toml` 비파괴 백업, `disabled` 설정 활성화 또는 malformed 설정 교정, 충돌 경로 이동, 설치, `--check`/`-Check` 재검증 순서까지 먼저 출력합니다. 기존 경로의 충돌을 해소한 뒤에만 해당 도구의 설치 명령을 실행합니다.

Karpathy Guidelines:

```bash
python3 "${CODEX_HOME:-$HOME/.codex}/skills/.system/skill-installer/scripts/install-skill-from-github.py" --repo multica-ai/andrej-karpathy-skills --path skills/karpathy-guidelines
```

Superpowers:

```bash
CODEX_SUPERPOWERS="${CODEX_HOME:-$HOME/.codex}/superpowers"
AGENT_SKILLS_ROOT="$HOME/.agents"
AGENT_SKILLS="$AGENT_SKILLS_ROOT/skills"
git clone https://github.com/obra/superpowers.git "$CODEX_SUPERPOWERS"
mkdir -p "$AGENT_SKILLS"
ln -s "$CODEX_SUPERPOWERS/skills" "$AGENT_SKILLS/superpowers"
```

기존 저장소나 링크가 있다면 위 명령으로 덮어쓰지 말고, 별도 백업 경로로 이동한 뒤 실행합니다.

Understand-Anything:

```bash
git clone https://github.com/Egonex-AI/Understand-Anything.git "$HOME/.understand-anything/repo"
bash "$HOME/.understand-anything/repo/install.sh" codex
```

PowerShell에서는 다음 명령을 사용합니다.

```powershell
$CodexRoot = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $HOME ".codex" } else { $env:CODEX_HOME }
python3 (Join-Path $CodexRoot "skills/.system/skill-installer/scripts/install-skill-from-github.py") --repo multica-ai/andrej-karpathy-skills --path skills/karpathy-guidelines

$SuperpowersRoot = Join-Path $CodexRoot "superpowers"
$AgentRoot = Join-Path $HOME ".agents"
$SkillsRoot = Join-Path $AgentRoot "skills"
git clone https://github.com/obra/superpowers.git $SuperpowersRoot
New-Item -ItemType Directory -Path $SkillsRoot -Force
$LinkType = if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) { "Junction" } else { "SymbolicLink" }
New-Item -ItemType $LinkType -Path (Join-Path $SkillsRoot "superpowers") -Target (Join-Path $SuperpowersRoot "skills")

$UnderstandRoot = Join-Path $HOME ".understand-anything/repo"
git clone https://github.com/Egonex-AI/Understand-Anything.git $UnderstandRoot
& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File (Join-Path $UnderstandRoot "install.ps1") codex
```

`disabled` 상태는 먼저 `config.toml`의 해당 `plugin@marketplace` 항목을 활성화해야 합니다. malformed 설정, 저장소만 남은 상태, 링크만 남은 상태는 충돌 항목을 백업 경로로 이동하거나 잘못된 항목을 교정한 뒤 위 명령을 실행합니다. 자동 복구는 이 기존 상태를 삭제하거나 덮어쓰지 않습니다.

복구 후 `--check` 또는 `-Check`를 다시 실행합니다. 복구 명령은 Unity 소스를 검사하는 린트·CI와 연동되지 않으며, 도구 상태는 Unity 코드 린트 실패로 간주하지 않습니다.

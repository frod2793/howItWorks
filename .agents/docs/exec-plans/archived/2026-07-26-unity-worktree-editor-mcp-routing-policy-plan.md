# Unity Worktree Editor MCP Routing Policy Implementation Plan

> 2026-09-08 갱신: 이 문서가 다루는 Unity MCP 절차는 Unity CLI·Pipeline으로 전면 대체되었다. 현행 기준은 [Unity linked worktree Editor·CLI 격리](../../onboarding/unity-worktree-cli.md)이며, 아래 내용은 설계 이력으로만 보존한다.

**상태:** 아카이브 — 범용 하네스 정책 반영 완료, 업무용 오버레이는 별도 하네스로 분리

> **아카이브 안내:** 이 문서는 2026-07-26 당시의 두 하네스 동시 적용 계획입니다. 현재 범용 하네스의 실행 계획으로 재사용하지 않으며, 미실행 검증과 업무용 전용 작업은 완료로 간주하지 않습니다.

**Goal:** 일반용·업무용 Unity 하네스에 worktree별 전용 Unity Editor, 충돌 없는 MCP endpoint, 물리 `projectRoot`와 `Name@hash` 기반 라우팅 및 실패 시 구현 전체 차단 규칙을 추가한다.

**Architecture:** 두 하네스가 byte-identical하게 공유하는 단일 기준 문서 `docs/onboarding/unity-worktree-mcp.md`를 만들고, 최상위 규칙·온보딩·검증·실행계획 문서는 그 기준을 요약·연결한다. 일반용 문서 계약과 업무용 Bash·PowerShell 정책 계약이 필수 문구를 고정하며, 업무용 고유 SOP·추적성은 기존 품질 게이트를 보존한 채 구현 파견 전 격리 게이트만 추가한다.

**Tech Stack:** Markdown, Bash, PowerShell, Git worktree 판별 명령, Unity Editor `ProjectVersion.txt`/`projectPath`, MCP for Unity resources와 multi-instance routing

---

## 작업 경계

- 일반용 루트: `<범용-하네스-루트>`
- 업무용 루트: `<업무용-하네스-루트>`
- 승인 설계: 일반용 `.agents/docs/design-docs/2026-07-26-unity-worktree-editor-mcp-routing-design.md`
- 현재 테스트 권한: `none`
- 필수 오류 확인: Markdown 변경은 `N/A`; Bash 변경은 `bash -n`; PowerShell 변경은 설치된 `pwsh` 또는 `powershell` parser
- `not_run`: 하네스 린트, 문서·정책 계약 테스트, Unit·Integration·EditMode·PlayMode, 런타임·씬·Inspector·시각 검증, Player Build, 외부 CI
- 두 하네스는 Git 저장소가 아니므로 commit과 worktree 생성은 `N/A`다.
- 이번 변경은 미래 Unity 프로젝트용 템플릿 정책만 수정한다. 실제 Unity 프로젝트, Editor, MCP port 또는 외부 서비스는 조작하지 않는다.
- 모든 운영 규칙·계약 파일 생성과 수정은 구현 서브 에이전트가 수행한다. 메인 에이전트는 계획, 규칙 전달, 명세 리뷰와 코드 품질 리뷰만 수행한다.
- 구현 서브 에이전트는 관련 없는 파일, 기존 완료 계획, 과거 설계·증거, 서드파티와 사용자 변경을 수정하지 않는다.

## 고정 정책 문구

모든 문서와 계약은 표현 차이를 허용하되 다음 의미를 빠짐없이 보존한다.

1. `git rev-parse --show-toplevel`, `--git-dir`, `--git-common-dir`, `--show-superproject-working-tree`와 물리 절대 경로로 일반 체크아웃·linked worktree·서브모듈·비Git을 구분한다.
2. linked worktree는 `ProjectSettings/ProjectVersion.txt` 버전과 물리 `projectPath`로 전용 Unity Editor를 연다.
3. 병렬 작업은 `워크트리 1개 : Unity Editor 1개 : MCP 인스턴스 1개`다.
4. 정상 endpoint는 유지하고 bind 충돌이나 병렬 연결 충돌이 있을 때만 대상 전용 Editor의 사용 가능한 loopback port로 변경한다.
5. port는 identity가 아니며 `mcpforunity://custom-tools` 확인, `mcpforunity://instances` 검색, 물리 `projectRoot` exact match, 정확한 `Name@hash`, `set_active_instance`, `project/info`, `editor/state`, `ready_for_tools` 확인을 모두 수행한다.
6. 병렬 에이전트는 지원되는 Unity MCP 호출에 `unity_instance`를 명시하고 리소스 조회 전 자신의 인스턴스를 다시 고정한다.
7. port 설정이 프로젝트 파일에 남으면 제품 변경에서 제외하고 handoff 전에 원복한다.
8. 전용 Editor·port·MCP 바인딩·`projectRoot`·준비 상태를 확정하지 못하면 Unity 구현 서브 에이전트를 파견하지 않으며 Unity 구현 전체를 중단한다.
9. 다른 Editor, 메인 체크아웃, 첫 인스턴스, 배치모드로 우회하지 않는다.
10. 컴파일과 Console 오류 확인은 같은 worktree의 대상 Editor·MCP에서만 수행하며 다른 체크아웃의 결과는 증거가 아니다.
11. 테스트와 검증 실행 권한, 구현 서브 에이전트 수행, 구현 후 메인 정적 리뷰라는 기존 최우선 정책은 유지한다.

### Task 1: 일반용 기준 문서와 정책 표면

**Files:**

- Create: 일반용 `.agents/docs/onboarding/unity-worktree-cli.md(구 `unity-worktree-mcp.md`)`
- Modify: 일반용 `.agents/AGENTS.md`
- Modify: 일반용 `.agents/docs/onboarding/agent-tooling.md`
- Modify: 일반용 `.agents/docs/onboarding/agent-quickstart.md`
- Modify: 일반용 `.agents/docs/onboarding/developer-quickstart.md`
- Modify: 일반용 `.agents/docs/coding-standards/core/unity-validation.md`
- Modify: 일반용 `.agents/docs/exec-plans/README.md`
- Modify: 일반용 `.agents/docs/exec-plans/_TEMPLATE.md`

- [ ] **Step 1: 승인 설계와 기존 최우선 실행 권한 정책 읽기**

  승인 설계 전체, 일반용 `.agents/AGENTS.md`, `agent-tooling.md`, `agent-quickstart.md`, `developer-quickstart.md`, `unity-validation.md`, 실행 계획 README와 템플릿을 읽는다. 현재 검증 권한 `none`, 문서 컴파일 `N/A`, 구현 파일 직접 수정 금지와 관련 없는 변경 보존을 확인한다.

- [ ] **Step 2: 단일 기준 문서 생성**

  `unity-worktree-mcp.md`는 다음 순서의 독립 섹션을 갖는다.

  ```text
  # Unity worktree 전용 Editor·MCP 라우팅
  ## 목적과 최우선 경계
  ## 실행 루트와 linked worktree 판별
  ## 전용 Unity Editor 준비
  ## MCP endpoint와 port 충돌 처리
  ## MCP 인스턴스 발견과 고정
  ## 구현 차단과 복구
  ## 서브 에이전트 전달 정보
  ## 컴파일·증거 경계
  ```

  문서는 고정 정책 문구 1~11을 운영 절차로 풀어 쓰고, port 변경은 loopback·대상 Editor 한정·세션 override 우선·프로젝트 파일 원복·port 단독 식별 금지로 제한한다.

- [ ] **Step 3: 최상위 규칙 연결**

  일반용 `.agents/AGENTS.md`의 필수 읽기 순서에 Unity 또는 MCP 작업이면 `docs/onboarding/unity-worktree-mcp.md`를 읽도록 추가한다. `최우선 구현·검증 권한 정책` 뒤에 `워크트리별 Unity Editor·MCP 격리` 섹션을 추가하고 다음 문구를 포함한다.

  ```text
  Unity 구현 전에 실행 루트와 linked worktree 여부를 판별합니다.
  linked worktree는 해당 물리 루트를 연 전용 Unity Editor와 `projectRoot`가 일치하는 정확한 `Name@hash` MCP 인스턴스만 사용합니다.
  필요한 경우 대상 전용 Editor의 MCP 서버 port를 충돌하지 않는 loopback port로 변경할 수 있지만 port만으로 인스턴스를 식별하지 않습니다.
  전용 Editor·MCP 바인딩을 확정하지 못하면 구현 서브 에이전트를 파견하지 않고 Unity 구현 전체를 중단합니다.
  ```

  필수 전달 패킷 8번의 기존 컴파일 문구를 보존하면서 실행 루트 유형, Editor 버전, endpoint, port 변경 사유, `Name@hash`, 물리 `projectRoot`, `ready_for_tools`를 추가한다.

- [ ] **Step 4: 도구·온보딩 정책 연결**

  `agent-tooling.md`에 `Unity worktree·MCP 준비` 섹션을 추가해 감지 → 전용 Editor → endpoint 충돌 처리 → custom tools → instances → 경로 일치 → 인스턴스 고정 → ready 확인 → 구현 파견 순서를 기록한다.

  `agent-quickstart.md`의 구현 흐름에서 사용자 승인과 규칙 전달 사이에 `실행 루트·worktree 판별`, `전용 Editor·MCP 바인딩` 단계를 추가한다.

  `developer-quickstart.md`의 개발 환경 확인과 첫 기능 작업에 worktree별 전용 Editor, port 충돌 시 대상 endpoint만 변경, 바인딩 실패 시 구현 중단을 추가한다.

- [ ] **Step 5: 검증 증거 권위 추가**

  `unity-validation.md`에 `Worktree Editor·MCP 증거 권위` 섹션을 추가한다. 올바른 바인딩은 테스트가 아니라 구현 전 안전 게이트이며, 다른 checkout의 clean Console·컴파일·테스트·화면은 현재 worktree 증거가 아니라고 명시한다.

- [ ] **Step 6: 실행 계획 기록 필드 추가**

  실행 계획 README의 실행 원칙과 워크플로우에 구현 파견 전 worktree·Editor·MCP gate를 추가한다. `_TEMPLATE.md`의 `현재 실행 권한과 역할` 표에는 다음 행을 추가한다.

  ```markdown
  | 실행 루트 | 물리 절대 경로와 `normal_checkout|linked_worktree|submodule|non_git` |
  | Unity Editor | `ProjectVersion.txt` 버전, 전용 Editor 상태 또는 `N/A` |
  | MCP 바인딩 | endpoint, port 변경 사유 또는 `not_changed`, `Name@hash`, 물리 `projectRoot`, `ready_for_tools` |
  | Unity 작업 차단 | `ready` 또는 정확한 `blocked` 사유 |
  ```

  템플릿 본문에는 `blocked`이면 Unity 구현 파일을 수정하지 않고 다른 Editor·배치모드로 우회하지 않는다는 문장을 추가한다.

- [ ] **Step 7: 구현 서브 에이전트 자체 검토**

  변경 파일 목록, 고정 정책 문구 1~11의 매핑, 문서 컴파일 `N/A`, 모든 자동 검증 `not_run`, 관련 없는 변경이 없음을 보고한다.

### Task 2: 일반용 문서 계약

**Files:**

- Modify: 일반용 `.agents/tests/run-tests.sh`

- [ ] **Step 1: 기존 문서 계약 helper와 등록 방식을 확인**

  `assert_document_contains_all`, `run_registered_test`, 기존 `test_docs_define_subagent_implementation_and_validation_authority`를 읽고 같은 스타일을 사용한다.

- [ ] **Step 2: worktree·Editor·MCP 문서 계약 추가**

  새 함수 이름은 다음과 같이 고정한다.

  ```bash
  test_docs_define_unity_worktree_editor_mcp_routing()
  ```

  이 함수는 기준 문서 존재와 다음 핵심 문자열을 확인한다.

  ```text
  git rev-parse --git-dir
  git rev-parse --git-common-dir
  git rev-parse --show-superproject-working-tree
  ProjectSettings/ProjectVersion.txt
  워크트리 1개 : Unity Editor 1개 : MCP 인스턴스 1개
  mcpforunity://custom-tools
  mcpforunity://instances
  Name@hash
  projectRoot
  set_active_instance
  ready_for_tools
  unity_instance
  loopback
  port만으로 인스턴스를 식별하지 않습니다
  Unity 구현 전체를 중단
  다른 Editor
  배치모드
  ```

  같은 함수에서 AGENTS, agent-tooling, 두 quickstart, unity-validation, 실행 계획 README와 템플릿이 기준 문서 링크, 차단 문구와 네 개 실행 컨텍스트 행을 포함하는지 확인한다.

- [ ] **Step 3: docs 그룹에 계약 등록**

  기존 등록부에 다음 호출을 한 번만 추가한다.

  ```bash
  run_registered_test test_docs_define_unity_worktree_editor_mcp_routing docs bash
  ```

- [ ] **Step 4: Bash 구문 오류 확인**

  일반용 루트에서 실행한다.

  ```bash
  bash -n .agents/tests/run-tests.sh
  ```

  기대 결과는 종료 코드 `0`과 출력 없음이다. 계약 테스트는 실행하지 않고 `not_run`으로 보고한다.

- [ ] **Step 5: 구현 서브 에이전트 자체 검토**

  함수 중복, 잘못된 경로, 등록 누락, 기존 계약 삭제가 없는지 확인하고 변경 파일·구문 결과·`not_run`을 보고한다.

### Task 3: 업무용 정책 표면과 추적성

**Files:**

- Create: `<업무용-하네스>/docs/onboarding/unity-worktree-mcp.md`
- Modify: `<업무용-하네스>/AGENTS.md`
- Modify: `<업무용-하네스>/docs/onboarding/agent-tooling.md`
- Modify: `<업무용-하네스>/docs/onboarding/agent-quickstart.md`
- Modify: `<업무용-하네스>/docs/onboarding/developer-quickstart.md`
- Modify: `<업무용-하네스>/docs/coding-standards/core/unity-validation.md`
- Modify: `<업무용-하네스>/docs/exec-plans/README.md`
- Modify: `<업무용-하네스>/docs/exec-plans/_TEMPLATE.md`
- Modify: `<업무용-하네스>/docs/business-standards/client-workflow-sop.md`
- Modify: `<업무용-하네스>/docs/business-standards/traceability.md`

- [ ] **Step 1: 공통 문서 동기화**

  일반용 Task 1의 최종 결과를 기준으로 다음 네 파일을 업무용에 byte-identical하게 반영한다.

  ```text
  <업무용-하네스>/docs/onboarding/unity-worktree-mcp.md
  <업무용-하네스>/docs/onboarding/agent-tooling.md
  <업무용-하네스>/docs/coding-standards/core/unity-validation.md
  <업무용-하네스>/docs/exec-plans/_TEMPLATE.md
  ```

  두 하네스의 업무 고유 AGENTS, quickstart와 실행 계획 README는 복사하지 않고 기존 업무 문맥을 보존해 같은 정책만 추가한다.

- [ ] **Step 2: 업무용 최상위·온보딩·계획 문서 연결**

  업무용 AGENTS 필수 읽기 순서와 최우선 정책에 일반용과 같은 worktree gate를 추가한다. 기존 Layered·MVP·VContainer·UniTask·단일 Assembly, AI 리뷰 70점, Compile·Unit·Integration·Build Validation, QA와 상태 전이 문구는 삭제하거나 완화하지 않는다.

  업무용 두 quickstart와 실행 계획 README에 Task 1과 같은 실행 루트, 전용 Editor, endpoint, port, `Name@hash`, `projectRoot`, `ready_for_tools`, 차단 조건을 추가한다.

- [ ] **Step 3: 업무 SOP 추가**

  SOP 버전을 `v1.2`로 올리고 2026-07-26 개정 이력에 `worktree별 전용 Unity Editor·MCP 격리와 port 충돌 처리`를 기록한다.

  `역할과 책임`, `구현·검증 실행 권한`, `6.2 기능 개발 또는 버그 수정`에 다음 순서를 추가한다.

  ```text
  실행 루트·linked worktree 판별
  전용 Unity Editor 실행
  필요 시 대상 MCP 서버의 loopback port 변경
  projectRoot와 Name@hash 일치 확인
  ready_for_tools 확인
  구현 서브 에이전트 파견
  ```

  실패하면 Unity 구현 전체를 중단하고 다른 Editor·메인 checkout·배치모드로 우회하지 않는다고 명시한다.

- [ ] **Step 4: 업무 추적성 ID 추가**

  추적표에 다음 행을 추가한다.

  ```markdown
  | WORK-UNITY-001 | 최상위 worktree별 Unity Editor·MCP 격리, SOP 6.2 | linked worktree의 전용 Editor, 충돌 없는 loopback endpoint, 물리 projectRoot·Name@hash 일치, 실패 시 Unity 구현 전체 차단 | 오류 |
  ```

  자동·수동 경계에도 port는 identity가 아니며 다른 checkout 결과를 증거로 사용할 수 없다는 문장을 추가한다.

- [ ] **Step 5: 업무용 문서 자체 검토**

  공통 네 파일의 byte 동일성, 업무 품질 게이트 보존, 새 추적 ID 단일성, 문서 컴파일 `N/A`, 자동 검증 `not_run`을 보고한다.

### Task 4: 업무용 Bash·PowerShell 정책 계약과 공통 해시

**Files:**

- Modify: `<업무용-하네스>/tests/run-tests.sh`
- Modify: `<업무용-하네스>/tests/run-workflow-tests.sh`
- Modify: `<업무용-하네스>/tests/run-workflow-tests.ps1`

- [ ] **Step 1: 업무용 공통 문서 계약 추가**

  업무용 `run-tests.sh`에 Task 2와 같은 함수명과 핵심 문자열 계약을 추가하고 docs 그룹에 한 번 등록한다. 업무용 AGENTS의 기존 문구 차이는 유지하되 의미가 같은 worktree gate를 검사한다.

- [ ] **Step 2: Bash 업무 정책 계약 추가**

  `run-workflow-tests.sh`에 다음 함수를 추가하고 `policy` 그룹에 등록한다.

  ```bash
  test_unity_worktree_editor_mcp_routing_policy()
  ```

  함수는 AGENTS, 기준 문서, SOP, traceability에서 `WORK-UNITY-001`, 전용 Editor, loopback port, `projectRoot`, `Name@hash`, `ready_for_tools`, 구현 파견 전 gate, 구현 전체 중단과 우회 금지를 검사한다.

- [ ] **Step 3: PowerShell 업무 정책 계약 추가**

  UTF-8 BOM을 보존하고 `run-workflow-tests.ps1`에 다음 함수를 추가한다.

  ```powershell
  function Test-UnityWorktreeEditorMcpRoutingPolicy
  ```

  Bash 정책 계약과 같은 파일·문구를 `Assert-Contains`와 `Assert-FragmentsInOrder`로 검사하고 `policy` 그룹에 다음과 같이 등록한다.

  ```powershell
  Invoke-Test 'test_unity_worktree_editor_mcp_routing_policy' 'policy' { Test-UnityWorktreeEditorMcpRoutingPolicy }
  ```

  Bash의 `test_powershell_static_contract` 예상 함수 목록에도 `Test-UnityWorktreeEditorMcpRoutingPolicy`를 추가한다.

- [ ] **Step 4: 최종 일반용 하네스 해시 갱신**

  일반용 Task 1·2의 리뷰와 재작업이 끝난 뒤 일반용 루트가 더 변경되지 않는 시점에 기존 알고리즘으로 해시를 계산한다.

  ```bash
  cd "${COMMON_HARNESS_ROOT:?COMMON_HARNESS_ROOT를 지정해야 합니다}"
  find .agents -type f -print | LC_ALL=C sort | while IFS= read -r file; do shasum -a 256 "$file"; done | shasum -a 256
  ```

  출력의 첫 필드를 업무용 `run-workflow-tests.sh`의 `COMMON_EXPECTED_HASH`에 기록한다. 이후 일반용 `.agents`를 수정하면 해시를 반드시 다시 계산한다.

- [ ] **Step 5: Bash 구문 오류 확인**

  업무용 루트에서 실행한다.

  ```bash
  bash -n <업무용-하네스>/tests/run-tests.sh
  bash -n <업무용-하네스>/tests/run-workflow-tests.sh
  ```

  두 명령 모두 종료 코드 `0`과 출력 없음이 기대 결과다.

- [ ] **Step 6: PowerShell 구문 오류 확인**

  `pwsh`가 있으면 업무용 루트에서 parser를 실행한다.

  ```bash
  pwsh -NoProfile -NonInteractive -Command '$tokens = $null; $errors = $null; [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path "<업무용-하네스>/tests/run-workflow-tests.ps1"), [ref]$tokens, [ref]$errors) > $null; if ($errors.Count -gt 0) { $errors | ForEach-Object { $_.Message }; exit 1 }'
  ```

  `powershell`만 있으면 같은 parser 코드를 `powershell`로 실행한다. 둘 다 없으면 설치하지 않고 정확한 차단 사유와 PowerShell 구문 미확인을 보고한다.

- [ ] **Step 7: 자동 테스트 미실행 경계 기록**

  `run-tests.sh`, `run-workflow-tests.sh`, `run-workflow-tests.ps1` 자체는 실행하지 않는다. 하네스 린트와 모든 계약·Unity 테스트는 `not_run`이다.

- [ ] **Step 8: 구현 서브 에이전트 자체 검토**

  Bash·PowerShell 함수명과 그룹 등록의 일치, PowerShell BOM, 공통 해시, 기존 업무 품질 계약 보존, 변경 파일과 구문 결과를 보고한다.

## 리뷰와 재작업 순서

각 Task는 다음 순서를 모두 통과해야 다음 Task로 이동한다.

1. 구현 서브 에이전트 자체 검토
2. 별도 명세 리뷰어가 승인 설계와 이 계획에 대한 누락·과잉 구현 확인
3. 별도 코드 품질 리뷰어가 문서 일관성, 계약 취약성, Bash·PowerShell 안전성과 기존 정책 회귀 확인
4. Important 이상 지적은 같은 구현 서브 에이전트가 수정
5. 같은 리뷰어가 재검토
6. 모든 Task 완료 후 메인 에이전트가 전체 변경을 독립 정적 리뷰

메인 최종 리뷰는 다음을 확인한다.

- 두 하네스의 기준 문서와 공통 네 파일이 의도대로 일치하는가
- 일반·linked worktree·서브모듈·비Git 판별이 충돌 없이 설명되는가
- port 변경이 필요한 경우에만 대상 loopback endpoint로 제한되는가
- port가 identity로 오인되지 않고 `projectRoot`와 `Name@hash`가 권위인가
- MCP custom tools, instances, 인스턴스 고정, `ready_for_tools`, `unity_instance`가 빠짐없는가
- 바인딩 실패 시 구현 파견 전 전체 중단과 우회 금지가 명확한가
- 다른 checkout의 Console·테스트가 증거로 사용되지 않는가
- 기존 구현 권한·검증 권한·업무 품질 게이트가 보존됐는가
- 변경 범위가 계획 파일에 한정됐는가
- 실행한 Bash·PowerShell 구문 확인과 `not_run` 항목이 구분됐는가

## 완료 상태

정책 문서와 계약 수정, 필수 구문 확인 및 메인 정적 리뷰가 끝나면 구현 적용 상태를 보고한다. 사용자가 계약 테스트·하네스 린트·Unity 검증을 요청하지 않았으므로 자동 검증은 `not_run`이며, 이를 검증 완료나 CI 통과로 주장하지 않는다. 미실행 계약 검증이 남으므로 이 계획 파일은 `active/`에 유지한다.

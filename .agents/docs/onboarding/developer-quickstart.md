# 개발자 온보딩

이 하네스는 프로젝트의 Unity 버전, 패키지, 폴더, 아키텍처를 미리 고정하지 않습니다. 실제 설치 상태와 확정 프로필을 먼저 확인합니다.

## 프로필 준비 흐름

### 1. 초기화

macOS/Linux Bash:

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root .
```

Windows PowerShell:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot .
```

### 2. 감지 보고서 검토

`.agents/reports/detection-report.md`와 실제 `ProjectSettings/ProjectVersion.txt`, `Packages/manifest.json`, 코드 사용 근거를 대조합니다. `.agents/config/project-profile.conf`의 source, test, exclude 경로도 직접 확인합니다.

### 3. 프로필 확정

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root . --confirm
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot . -Confirm
```

### 4. 검사 명령 준비

다음 명령은 사용자가 현재 하네스 검사를 요청한 경우에만 실행하는 예시입니다. 요청하지 않았다면 `not_run`으로 기록합니다.

```bash
bash .agents/scripts/lint/check-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/lint/check-harness.ps1 -ProjectRoot .
```

## 개발 환경 확인

- Unity Editor 버전은 프로필과 `ProjectVersion.txt`가 일치하는지 확인합니다.
- 현재 실행 루트의 물리 절대 경로와 Git 유형을 `normal_checkout`, `linked_worktree`, `submodule`, `non_git` 중 하나로 판별합니다.
- 모든 Unity 실행 루트는 실행 중 Editor를 사용할 때 `unity status --format json`의 인스턴스 `project`와 대상 물리 프로젝트 루트의 exact match, `unity command editor_status --project-path <물리 경로>`의 `projectPath` exact match·`status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용)·`compiling=false`를 확인합니다.
- `linked_worktree`의 Unity 작업은 추가로 `ProjectVersion.txt` 버전과 물리 `projectPath`의 전용 Editor를 사용합니다(`bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`; 이미 CLI 실패를 확인했으면 `--skip-cli`). port는 identity가 아니며 CLI가 관리합니다.
- 바인딩이 `ready`가 아니면 `background: editor_unavailable`로 기록하고 CLI·batchmode 백그라운드 경로로 진행합니다. 실행 루트·물리 경로를 확정할 수 없을 때만 Unity 구현을 시작하지 않습니다. 인스턴스 고정 절차는 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)를 따릅니다.
- 설치해야 할 DI, async, tween, rendering 패키지는 확정된 값과 [기술 프로필 안내](tech-stack-overview.md)에서 확인합니다.
- 값이 `none` 또는 `unknown`이면 특정 패키지를 임의 설치하지 않습니다.
- 소스는 `${source_root}`, 테스트는 `${test_root}`, 제외 경로는 `exclude_root`를 따릅니다.

## 코드 검사 경계 확인

코드 검사는 `project-profile.conf`의 `source_root`를 사용하며 모든 `source_root`는 `Assets/_Game` 또는 그 하위 경로여야 합니다. `Assets/_Game` 밖의 Asset Store, UPM과 기타 외부 에셋 코드는 검사하지 않습니다. `_Game` 내부의 외부 원본만 `exclude_root`로 명시합니다.

## Unity 기능·마일스톤 검증

다음은 사용자가 해당 검증을 현재 요청한 경우에 실행하는 품질 명세입니다. 요청하지 않은 항목은 `not_run`이며 통과로 간주하지 않습니다.

- 개별 Task 검증 범위는 정적 검사, 대상 테스트, 논리적 변경 묶음 단위 Unity 컴파일이며 Player Build를 포함하지 않습니다.
- 기능·마일스톤 검증은 `Assets/_Game` 프로젝트 소유 모듈과 상호작용의 전체 자동화 통합 테스트를 수행합니다.
- Player Build가 현재 명시적으로 요청된 경우 사전 게이트를 통과한 동일 변경분에만 1회 수행하며, Unity CI Build Validation이 있으면 로컬 중복 빌드를 수행하지 않습니다.
- 증거 형식과 변경 후 무효화 기준은 [Unity 기능·마일스톤 검증 정책](../coding-standards/core/unity-validation.md)을 따릅니다.

## 첫 기능 작업

1. 현재 실행 루트의 물리 절대 경로와 Git 유형을 판별합니다.
2. [제품 스펙](../product-specs/)에서 사용자 요구와 수용 기준을 확인합니다.
3. [설계 템플릿](../design-docs/_TEMPLATE.md)에 선택 프로필 역할과 의존 방향을 기록합니다.
4. [실행 계획 템플릿](../exec-plans/_TEMPLATE.md)에 실행 루트, Unity Editor 바인딩, 현재 테스트 권한과 `not_run` 항목을 기록합니다. 실패 검증은 사용자가 요청한 경우에만 실행하도록 계획합니다.
5. 전체 승인 후 Unity 작업이면 모든 실행 루트의 Editor identity 바인딩을 `ready`로 확정하고, `linked_worktree`에는 전용 Editor를 추가로 확정합니다. 실행 루트를 확정할 수 없을 때만 구현 전체를 중단하며, 상주 Editor만 불가하면 `background: editor_unavailable`로 기록하고 CLI·batchmode 백그라운드 경로로 진행합니다. 다른 Editor로 대상을 바꾸지 않습니다. Editor 비의존 변경(기존 `.cs` 로직 수정만·직렬화 표면 불변·scene/prefab/asset/UI 배치/Inspector 값 무변경)은 이 게이트의 대상이 아니며 실행 루트 판별만 하고 파견합니다 — 정의는 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)의 적용 범위를 따릅니다.
6. 전체 승인 후 메인 에이전트가 필수 전달 패킷을 구현 서브 에이전트에게 전달합니다.
7. 구현 서브 에이전트가 최소 범위로 구현하고 적용 가능한 코드·스크립트의 컴파일·구문 오류를 확인합니다. 문서만 변경하면 `N/A`입니다.
8. 메인 에이전트가 독립 정적 리뷰하고, 중요한 지적은 같은 구현 서브 에이전트가 수정한 뒤 메인 에이전트가 재리뷰합니다.
9. 대상 테스트, 프로필 검사, 직렬화·런타임 검증은 사용자가 현재 요청한 항목만 실행하고 나머지는 `not_run`으로 기록합니다.

서드파티 원본은 수정하지 않고 프로젝트 소유 Adapter·Wrapper 경계에서 대응합니다. `not_run`은 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거가 아닙니다.

Editor 기동은 `bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`를 사용합니다. 이미 `unity open` 실패를 확인했다면 `--skip-cli`를 지정합니다. 동일 버전 앱을 직접 실행해도 [Unity CLI 실행 가이드](unity-cli.md)의 후속 identity·ready 확인을 통과해야 합니다.

작업 종료·반복 방지는 [AGENTS](../../AGENTS.md)의 작업 종료와 반복 방지 절을, 매 파견 모델 배정과 현재 승인 예외는 [도구 준비](agent-tooling.md)의 역할별 에이전트·모델 분담 절을 따릅니다.

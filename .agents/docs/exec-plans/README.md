# 실행 계획 관리 가이드

## 디렉터리와 상태

```text
docs/exec-plans/
├── active/       진행 중인 계획
├── completed/    사용자 승인 완료 기준과 허가된 검증을 충족한 계획
├── _TEMPLATE.md
└── README.md
```

파일명은 `YYYY-MM-DD-기능명-plan.md` 형식을 사용합니다. 완료 전에는 `active/`에 둡니다. `not_run`인 필수 검증을 통과로 간주하지 않으며, 사용자 승인 완료 기준과 현재 허가된 검증을 충족한 경우에만 `completed/`로 이동합니다.

## 프로필 기반 작성 계약

1. `.agents/config/project-profile.conf`의 상태와 선택값을 계획 첫 부분에 고정합니다.
2. 생성·수정 항목은 `${source_root}`, 테스트 항목은 `${test_root}`를 사용합니다.
3. 각 클래스에는 `선택 프로필의 역할`을 함께 적어 아키텍처 경계를 검증합니다.
4. `dependency_injection=none`이면 컨테이너 단계를 만들지 말고 Composition Root 변경을 계획합니다.
5. 최적화 Task는 `적용 상태`, 사전·사후 `측정 근거`, 실패 시 `롤백 조건`을 포함합니다.
6. Open Questions는 실제 미결정 사항이 있을 때만 남기며 구현 승인을 대신하지 않습니다.

`test_root`가 없으면 임의 경로를 만들지 않고 `${test_root}=N/A`와 수동·대체 자동 검증을 기록합니다.


계획은 개별 Task 검증인지 기능·마일스톤 전체 검증인지 명시합니다. 개별 Task에는 승인된 변경 범위·컴파일·대상 테스트를 계획하며 Player Build는 비대상입니다. 비대상은 빌드 성공이 아닙니다. 아래 전체 scope·prebuild·built 계약은 기능·마일스톤 전체 검증에 적용합니다.

## 기능·마일스톤 검증 계약

다음은 사용자가 해당 검증을 현재 요청했을 때 실행할 기술 명세입니다. 현재 테스트 권한이 `none`이면 명세를 계획에 보존하되 실행 결과는 `not_run`으로 기록합니다.

템플릿의 대괄호 표기는 실제 계획을 작성할 때 실제 값으로 교체합니다. `기능·마일스톤 선언`에는 `milestone_id`, 포함 Task, 수용 기준, `target_platform`, `local|unity_ci`, Git change set 또는 비Git checksum을 기록합니다.

- `module_scope`와 `interaction_scope` inventory는 imported package, Asset Store, UPM과 third-party originals를 제외하고 실제 식별자로 확정합니다. inventory가 확정된 경우에만 `coverage_status=confirmed`를 사용합니다.
- 통합 테스트 매트릭스에는 `Assets/_Game` 전체의 프로젝트 소유 모듈과 상호작용을 자동화 테스트로 매핑합니다. result 대상은 scope inventory와 exact match여야 하며 missing/unexpected/duplicate/invalid를 허용하지 않습니다.
- 개별 Task step에는 Player Build 명령 금지를 적용합니다. 정적 검사, 대상 테스트, 논리적 변경 묶음 단위 Unity 컴파일만 계획합니다.
- 계획에는 실제 evidence path, change-id 계산 절차·명령, prebuild·built의 Bash·PowerShell 명령, `build_authority`, `build_run_id`, `build_artifact_hash`를 필수로 기록합니다.
- 최종 Player Build는 Compile, 전체 Unit, 전체 Integration과 prebuild evidence가 같은 변경분임을 확인한 뒤 선택한 build authority의 Player Build 또는 Unity CI Build Validation을 1회만 기록합니다.
- prebuild는 run ID와 artifact hash를 `pending`으로, built는 nonpending run ID와 lowercase 64-hex artifact hash로 같은 evidence path에 기록합니다.

## 실행 원칙

- 실패하는 테스트 또는 재현 절차는 현재 테스트 권한에 포함된 경우에만 먼저 확인합니다. 권한이 `none`이면 RED·재현 단계는 `not_run`으로 남기고 향후 검증 명세만 보존합니다.
- Unity 작업은 실행 루트의 물리 경로와 `normal_checkout`, `linked_worktree`, `submodule`, `non_git` 유형을 먼저 기록합니다. 모든 실행 루트는 실행 중 Editor를 사용할 때 `unity status --format json`의 인스턴스 `project`와 대상 물리 프로젝트 루트의 exact match, `unity command editor_status --project-path <물리 경로>`의 `projectPath` exact match·`status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용)·`compiling=false`를 구현 전 안전 게이트로 확정합니다. `linked_worktree`이면 전용 Editor를 추가합니다.
- 실행 루트를 확정할 수 없으면 Unity 구현 서브 에이전트를 파견하거나 구현 파일을 수정하지 않습니다. Editor 바인딩만 `ready`가 아니면 `background: editor_unavailable`로 기록하고 CLI·batchmode 백그라운드 경로로 진행합니다. 다른 Editor 또는 메인 checkout으로 대상을 바꾸지 않습니다. 상세 기준은 [Unity linked worktree Editor·CLI 격리](../onboarding/unity-worktree-cli.md)를 따릅니다.
- 각 Step은 하나의 검증 가능한 결과를 만듭니다.
- 변경 파일은 승인된 `${source_root}`와 `${test_root}` 범위로 제한합니다.
- 선택되지 않은 기술이나 Profiles를 계획에 끼워 넣지 않습니다.
- 사용자 전체 승인 이후에만 구현을 시작합니다.
- 모든 구현 파일 생성·수정은 필수 전달 패킷을 받은 구현 서브 에이전트가 수행하며, 메인 에이전트는 계획·규칙 전달·리뷰를 담당합니다.
- 적용 가능한 코드·스크립트의 컴파일·구문 오류 확인은 필수입니다. 문서만 변경하면 `N/A`이고 확인 진입점이 없거나 막히면 성공으로 주장하지 않습니다.
- 구현 후 메인 에이전트가 독립 정적 리뷰하고, 중요한 지적은 같은 구현 서브 에이전트가 수정한 뒤 메인 에이전트가 재리뷰합니다.
- 완료 보고는 컴파일·구문 확인 결과와 사용자 요청으로 실행한 검증의 최신 출력을 구분합니다. 미요청 검증은 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done으로 전환하지 않습니다.

## 워크플로우

1. [_TEMPLATE.md](_TEMPLATE.md)를 복사해 `active/`에 생성
2. 프로필 스냅샷, 성공 기준, 파일 범위, 실행 루트 유형과 물리 경로, 현재 테스트 권한과 `not_run` 항목 작성
3. Unity 작업이면 모든 실행 루트의 Editor identity와 차단 조건을 기록하고, `linked_worktree`이면 전용 Editor 조건을 추가
4. 사용자에게 전체 계획 승인 요청
5. 승인 후 Unity 작업이면 모든 실행 루트의 Editor identity를 고정하고 `editor_status`의 `ready`를 확인. `linked_worktree`이면 전용 Editor도 확정합니다. 확정하지 못하면 `background: editor_unavailable`로 기록하고 CLI·batchmode 백그라운드 경로로 파견하며, 실행 루트를 확정할 수 없을 때만 Unity 구현 전체를 중단합니다. Editor 비의존 변경(기존 `.cs` 로직 수정만·직렬화 표면 불변·scene/prefab/asset/UI 배치/Inspector 값 무변경)은 이 게이트의 대상이 아니며 실행 루트 판별만 하고 파견합니다 — 정의는 [Unity linked worktree Editor·CLI 격리](../onboarding/unity-worktree-cli.md)의 적용 범위를 따릅니다.
6. 메인 에이전트가 요구·승인 범위·최우선 규칙·구현 규칙·대상 파일·금지 범위·테스트 권한·컴파일 방법·완료 보고 형식을 구현 서브 에이전트에게 전달
7. 구현 서브 에이전트가 Task를 구현하고 적용 가능한 코드·스크립트의 컴파일·구문 오류 확인
8. 서브 에이전트 완료 보고 후 메인 에이전트 독립 정적 리뷰와 필요한 재작업·재리뷰
9. 사용자가 현재 요청한 정적 검사·대상 테스트·런타임 검증만 실행하고 나머지는 `not_run`으로 기록
10. 사용자가 현재 명시적으로 요청한 경우에만 기능·마일스톤 사전 게이트와 최종 Player Build 또는 Unity CI Build Validation 1회 실행
11. 사용자 승인 완료 기준에 미실행 필수 검증이 남지 않은 경우에만 `completed/`로 이동

- built 검증 명령은 prebuild에서 보관한 선택 권위를 `--expected-authority`/`-ExpectedAuthority` 필수 인자로 전달합니다. 증거 파일 자체에서 기대 권위를 다시 읽어 전달하지 않습니다.

Editor 기동은 `bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`를 사용합니다. 이미 `unity open` 실패를 확인했다면 `--skip-cli`를 지정합니다. 동일 버전 앱을 직접 실행해도 [Unity CLI 실행 가이드](../onboarding/unity-cli.md)의 후속 identity·ready 확인을 통과해야 합니다.

## 종료·재검수 경계

승인된 목표·수용 조건·허용 파일을 고정하고 충족 시 종료합니다. 동일 입력·실패·방법 재시도 금지와 수정 지적·실제 영향만 재검수하는 계약은 [AGENTS](../../AGENTS.md)의 작업 종료와 반복 방지 절을 따릅니다. 새 중대 문제는 별도 증거·범위로 보고합니다.

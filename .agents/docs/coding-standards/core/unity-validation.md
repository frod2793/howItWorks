# Unity 기능·마일스톤 검증 정책

## 실행 권한과 상태 전환 경계

이 문서의 기술적 품질 게이트는 사용자가 해당 검증을 현재 요청했을 때 실행하는 명세입니다. 품질 기준 자체는 유지하되 이 문서는 검증 실행 권한을 부여하지 않습니다.

- 적용 가능한 코드·스크립트 변경의 컴파일·구문 오류 확인과 구현 후 메인 에이전트 정적 리뷰는 필수입니다. 문서만 변경하면 컴파일 확인은 `N/A`이고, 확인 진입점이 없거나 막히면 성공으로 처리하지 않습니다.
- 하네스 린트, 정적 정책 검사, 계약·Unit·Integration 테스트, Unity EditMode·PlayMode 테스트, 런타임·씬·Inspector·시각 검증은 사용자가 현재 명시한 범위에서만 실행합니다.
- Player Build와 외부 Unity CI는 사용자가 현재 명시적으로 요청한 경우에만 실행합니다.
- 요청하지 않은 필수 검증은 `not_run`으로 기록하며 `passed`나 검증 완료로 간주하지 않고 후속 상태를 차단합니다. 개별 Task에서 Player Build는 검증 비대상이며, 이를 빌드 성공으로 기록하지 않습니다.
- 메인 에이전트의 정적 리뷰는 테스트·런타임·빌드 검증을 대체하지 않습니다. 사용자가 이후 전체 기능·마일스톤 검증을 요청하면 `not_run` 항목은 아래 사전 빌드 게이트에 따라 Player Build를 차단합니다.

## Worktree Editor·CLI 증거 권위

모든 Unity 실행 루트는 실행 중 Editor를 사용할 때 `unity status`의 `project` exact match와 `editor_status`의 `projectPath` exact match·`status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용)를 확인합니다. linked worktree는 전용 Editor 격리를 추가로 적용합니다. 올바른 Editor 바인딩은 테스트 결과가 아니라 구현 전 안전 게이트이며, 이 게이트를 통과해도 컴파일, 테스트, 런타임, 씬·Inspector·시각 검증 또는 Player Build가 통과한 것으로 보지 않고 사용자의 현재 검증 권한을 확대하지 않습니다.

- 로컬 Unity Editor 컴파일과 Console 증거는 대상 실행 루트의 물리 `projectPath`와 그 Editor의 Pipeline 인스턴스에서 `unity command`로 수집한 결과만 인정합니다. linked worktree라면 `ProjectVersion.txt` 버전의 전용 Editor여야 합니다.
- 다른 checkout, 메인 checkout, 다른 worktree 또는 다른 Editor의 결과는 대상 변경의 로컬 Unity Editor 증거가 아닙니다.
- port는 identity가 아니며, `project`·`projectPath` exact match와 `editor_status`의 `ready`를 함께 확인합니다.
- 작업 중 바인딩이 끊기거나 identity가 달라지면 상주 Editor 경로를 중단하고 다시 고정하기 전의 Editor 결과를 증거로 사용하지 않으며, 구현·검증은 백그라운드 경로로 이어갑니다.
- 다른 Editor로 대상을 바꾸는 것은 연결 실패의 우회 수단이 아닙니다. 같은 물리 경로에 대한 Unity CLI·batchmode는 우회가 아니라 백그라운드 경로이며, 그 증거는 명령·물리 경로·버전·로그를 기록하면 상주 Editor 결과와 동등하게 인정합니다.
- Editor 비의존 변경(정의는 [Unity linked worktree Editor·CLI 격리](../../onboarding/unity-worktree-cli.md)의 적용 범위)은 이 게이트의 대상이 아니며, 그 컴파일 증거는 동일 실행 루트에서 Unity CLI로 얻은 결과 또는 상주 전용 Editor의 결과를 인정합니다.

사용자가 현재 승인한 `unity_ci` 증거는 동일 `change_id`, 선택된 `build_authority`와 이 문서의 evidence 계약을 충족할 때 별도 권위로 인정합니다. 이는 다른 checkout의 로컬 Editor 결과를 인정하거나 아래 사전 빌드·built 기준을 완화하는 예외가 아닙니다.

실행 루트 판별, 전용 Editor 준비, Pipeline 인스턴스 발견·고정과 복구 기준은 [Unity linked worktree Editor·CLI 격리](../../onboarding/unity-worktree-cli.md)를 따릅니다.

## 개별 Task

사용자가 개별 Task 검증을 현재 요청한 경우 다음 범위를 적용합니다.

- 개별 Task 검증에서는 Player Build를 수행하지 않습니다.
- 각 Task의 검증 범위는 정적 검사, 변경 대상 테스트, 논리적 변경 묶음 단위의 Unity 컴파일입니다.
- 대상 테스트와 컴파일은 해당 Task가 만든 변경을 확인하는 증거이며, 기능·마일스톤 전체 완료 증거를 대체하지 않습니다.

## 기능·마일스톤 사전 빌드 게이트

사용자가 기능·마일스톤 검증을 현재 요청한 경우 다음 게이트를 적용합니다. Player Build 실행은 별도의 현재 명시적 요청이 있어야 합니다.

기능·마일스톤 계획은 시작 전에 `milestone_id`, 포함 Task, 수용 기준, `target_platform`, 빌드 권위(`local` 또는 `unity_ci`)를 선언합니다. `Assets/_Game` 전체에서 프로젝트가 소유한 모듈과 상호작용을 전체 자동화 통합 테스트에 매핑합니다.

- `coverage_status=confirmed`는 실제 `Assets/_Game` project-owned module/interaction inventory가 계획에서 확정된 경우에만 기록합니다. 검증기는 증거에 이 값이 정확히 한 번 존재하는지 스키마와 독립적으로 검사합니다. 스키마의 허용값·필수 여부·중복 허용을 바꿔도 이 게이트를 완화할 수 없습니다.
- imported package, Asset Store, UPM과 third-party originals는 프로젝트 소유 inventory에서 제외합니다.
- `module_scope`와 `interaction_scope`에는 확정된 실제 식별자를 기록합니다. `module_result`와 `interaction_result`의 대상은 각 scope와 exact match여야 합니다.
- scope와 result 사이에 missing/unexpected/duplicate/invalid 항목이 하나라도 있으면 검증기는 Player Build를 차단합니다.
- Compile, 전체 Unit 테스트, 전체 Integration 테스트가 모두 `passed`여야 합니다.
- 자동화 대상, 모듈 결과 또는 상호작용 결과가 `failed`, `missing`, `not_run` 중 하나이면 Player Build를 차단합니다.
- prebuild 증거에는 동일 change_id, `build_validation=pending`, `build_run_id=pending`, `build_artifact_hash=pending`을 기록합니다.

## 최종 Player Build

사용자가 Player Build를 현재 명시적으로 요청한 경우에만 다음 기준으로 실행합니다.

- 사전 빌드 게이트를 통과한 동일 change_id에 대해서만 Player Build를 1회 수행합니다.
- 같은 변경분에 Unity CI Build Validation이 있으면 로컬 Player Build를 중복 수행하지 않습니다.
- built 증거는 prebuild에서 선택한 `build_authority`인 `local` 또는 `unity_ci` 중 1개의 실행만 기록합니다. 소비자는 선택 권위를 보관하고 `--expected-authority` 또는 `-ExpectedAuthority`로 반드시 전달해 built와 대조합니다. built에서 이 인자를 생략하면 인자 오류로 거부합니다. 파일 경로가 같아도 권위 변경은 허용하지 않습니다.
- 완료 증거는 동일 변경분의 Player Build 또는 Unity CI Build Validation 1회, `build_validation=passed`, 실제 실행을 식별하는 build_run_id (앞뒤 공백 및 대소문자를 정규화한 `pending`, `n/a`, `none`, `not_run`, `unknown`, `tbd`, `-` 등 대체 문자열 금지), lowercase 64-hex artifact hash입니다.
- 사용자가 요청한 진단 목적의 Player Build는 완료 증거가 아닙니다.

## 검증 전 입력 안정화

승인된 검증을 시작하기 전에 동일 Unity 버전의 import·package resolution을 마치고, 자동 변경된 `.meta`·`packages-lock.json`·`ProjectSettings`를 검토해 검증 대상에 포함합니다. 그다음 입력 ID를 계산하고 사전 검증을 수집합니다. 빌드가 실제 입력을 바꾸면 이전 증거를 통과시키지 않고 바뀐 입력을 안정화한 뒤 검증을 다시 수집합니다. 단순 줄바꿈·파일명 Unicode 표현 차이의 정규화는 의미 있는 설정 변경을 숨기는 허가가 아닙니다. 이 순서가 해당 프로젝트에서 안정적인지는 실제 Unity 실행으로 별도 확인합니다.

## 증거 무효화

입력 안정화는 다음 순서로 기록합니다. manifest는 소비자가 정한 실제 입력 범위의 경로·상태(추가/수정/삭제)·파일별 SHA-256을 담고, 삭제·부재는 hash 대신 명시적으로 기록합니다. Git HEAD는 별도 provenance이며 dirty/untracked 목록만으로 내용 동일성을 추정하지 않습니다.

1. 검증 전 기존 dirty/untracked manifest·SHA와 Git index 바이트 hash를 보관합니다. 비Git은 동일 입력 범위의 내용 manifest·SHA를 보관합니다.
2. 동일 버전의 import·package resolution 후 생성·삭제 파일을 기존 manifest와 대조합니다. 예를 들어 untracked Addressables `link.xml`·`.meta`의 부재나 복원이 있으면 원인을 추정하지 말고 실제 경로·바이트 변화와 검토 결정을 기록합니다. 기존 사용자 파일을 임의 삭제·복원하지 않습니다.
3. 검토한 최종 입력 manifest·SHA를 고정한 뒤 `change_id`를 계산해 검증 대상·명령·로그에 연결합니다. 다른 worktree의 파일이나 증거로 대체하지 않습니다.
4. 실행 후 같은 범위의 manifest·SHA·`change_id`를 다시 계산합니다. 최종 입력이 다르면 현재 증거를 보존하고 해당 단계의 증거를 무효화합니다. 바뀐 입력의 재검증은 새 검증 권한을 확인한 뒤 수행하며 이전 실행 권한을 자동 재사용하지 않습니다.

`not_verified`는 최종 입력에 유효한 증거가 없다는 설명 용어이며 새 workflow 상태값이 아닙니다. 입력 목록·hash 수집 예시는 [Unity CLI 가이드](../../onboarding/unity-cli.md)의 검증 전후 입력 기록을 따릅니다.

`Assets/_Game`, 관련 scene·prefab data, `ProjectSettings`, package, assembly, build pipeline을 변경하면 기존 사전 빌드와 빌드 완료 증거는 무효입니다.

- 소비자는 로컬과 CI가 같은 논리적 빌드 입력에 동일한 식별자를 계산하도록 경로·텍스트 정규화와 제외 범위를 명시합니다. 구체 구현과 입력 목록은 해당 소비자의 문서에서 관리합니다.
- 비Git 입력도 재현 가능한 내용 식별 절차와 신뢰 범위를 기록해야 합니다.
- 독립 증거 검증기는 `change_id`를 계산하지 않는 pure read-only gate입니다. 소비자는 빌드 입력에서 값을 직접 재계산하여 호출자가 넘긴 값과 증거를 대조해야 합니다.
- 호출 에이전트는 prebuild 직전과 built 직전에 실제 무효화 범위에서 `change_id`를 다시 계산하고 expected change-id argument인 `--change-id` 또는 `-ExpectedChangeId`로 전달합니다.
- 이전 실행에서 보관한 stale change-id 문자열을 재사용하지 않습니다.
- 검증기는 상태를 저장하지 않으므로 generic consumer가 같은 evidence path를 유지하고 prebuild 다음 built라는 phase sequence를 보장해야 합니다.


## 로컬 검증의 신뢰 한계

동일 OS 사용자 권한은 하네스 스크립트·설정·증거를 함께 변조할 수 있습니다. 로컬 검사와 hook은 우발적 우회·오작동을 줄이는 방어이며 샌드박스나 인증된 CI가 아닙니다. change_id와 검증 결과의 형식·내용 일치가 실제 명령 실행을 인증하지는 않습니다. 실제 실행 명령·로그·대상·산출물 provenance는 별도로 확인합니다.

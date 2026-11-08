# [기능명] 실행 계획

> 파일명: `YYYY-MM-DD-기능명-plan.md`

**상태**: 계획 중 / 승인 대기 / 진행 중 / 완료
**생성일**: YYYY-MM-DD
**담당자**: [이름]
**관련 설계**: [경로]

## 목표와 완료 기준

- **목표**: [측정 가능한 결과]
- **완료 기준**: [테스트·수치·사용자 결과]
- **범위 밖**: [다루지 않는 항목]
- **종료 경계**: [승인된 수용 조건 충족 시 종료; 재검수는 수정 지적·실제 영향만]
- **재시도 근거**: [변경된 입력·실패 원인·방법과 예상 시간; 동일 조합 재실행 금지]

## 현재 실행 권한과 역할

| 항목 | 계획 값 |
|------|---------|
| 실행 루트 | [물리 절대 경로와 `normal_checkout`, `linked_worktree`, `submodule`, `non_git` 중 하나 또는 비-Unity·문서 작업 `N/A`] |
| Unity Editor | [`ProjectSettings/ProjectVersion.txt` 버전과 대상 Editor 상태, `linked_worktree`의 전용 상태 또는 비-Unity·문서 작업 `N/A`] |
| Editor 의존 여부 | [`의존` 또는 `비의존: 근거`(기존 `.cs` 로직 수정만·직렬화 표면 불변·scene/prefab/asset/UI 배치/Inspector 값 무변경) 또는 비-Unity·문서 작업 `N/A`. `비의존`이면 아래 Editor 바인딩 항목은 `N/A`] |
| Editor 바인딩 | [Pipeline 인스턴스 `pid`·`port`·`version`, exact match 물리 `projectPath`, `editor_status` 결과(`status`·`compiling`·`unityVersion`) 또는 비-Unity·문서 작업 `N/A`] |
| Unity 작업 차단 | [`ready`, `background: editor_unavailable 사유`, `blocked: 실행 루트 미확정 사유` 또는 비-Unity·문서 작업 `N/A`. `blocked`이면 Unity 구현 파일 수정 금지, `background`면 CLI·batchmode 경로로 진행] |
| 현재 테스트 권한 | `none` 또는 [사용자가 현재 요청한 정확한 검증·테스트 목록] |
| 구현 서브 에이전트 | [모든 구현 파일 생성·수정 담당자] |
| 컴파일 확인 | [`unity command recompile`·배치 컴파일·언어별 구문 명령 또는 문서 변경 `N/A`] |
| 메인 리뷰 | [독립 정적 코드 리뷰 담당자와 중요 지적 재작업·재리뷰 절차] |
| `not_run` | [현재 요청하지 않아 실행하지 않을 린트·테스트·런타임·빌드·외부 CI] |

메인 에이전트는 사용자 요구, 승인 범위, 최우선 규칙, 아키텍처·코딩·명명·Karpathy 규칙, 정확한 대상 파일, 금지 범위, 테스트 권한, 컴파일 확인 방법과 완료 보고 형식을 구현 서브 에이전트에게 전달하고 직접 구현하지 않습니다. Unity 작업은 `.agents/docs/onboarding/unity-worktree-cli.md`에 따라 바인딩이 `ready` 또는 `background: editor_unavailable`인 경우에 전달합니다(`blocked`는 실행 루트 미확정일 때만). 적용 가능한 코드·스크립트의 컴파일·구문 오류 확인은 필수이며, 문서만 변경하면 `N/A`입니다. 확인 진입점이 없거나 막히면 성공으로 주장하지 않습니다.

`blocked`(실행 루트 미확정)에서만 Unity 구현 파일 수정을 금지합니다. `ready` 또는 `background: editor_unavailable`이면 승인된 범위로 진행하며, Pipeline 인스턴스의 port는 CLI가 관리하므로 프로젝트 파일에 port·endpoint 설정을 쓰지 않습니다.

현재 테스트 권한이 `none`이면 아래 RED, 테스트, 린트, 런타임, Player Build와 외부 CI 단계는 실행하지 않고 `not_run`으로 기록합니다. 아래 검증 항목과 명령은 사용자가 이후 요청할 때 실행할 품질 명세로 보존하며, 스킬의 기본 워크플로가 사용자 권한을 넓히지 않습니다.


## 실제 행동과 요구사항 대조

계획과 완료 보고에서 원문 요구 → 허용 파일 → 실제 diff → 지정 플랫폼·패턴 → 명령 로그 증거를 대조합니다. 선언이나 숫자 요약만으로 준수를 추정하지 않습니다.

| 원문 요구·수용 조건 | 허용 파일 | 실제 diff·파일 SHA | 지정 플랫폼·패턴 대조 | 명령·로그·기기 기록 | 판정·남은 경계 |
|---|---|---|---|---|---|
| [원문] | [승인된 경로] | [변경 근거] | [실제 실행 환경·구조] | [증거 경로 또는 unknown/not_run] | [충족/불일치/unknown/not_run] |

정책 변경은 대표 3사례(허용 범위 유지 / 타파일 이탈 / 플랫폼·패턴 대체)를 저장된 로그 또는 scratch fixture로 분류하고 근거를 남깁니다. 명령·기기 기록이 없으면 `unknown` 또는 `not_run`이며 실제 에이전트 준수·기기 동작으로 주장하지 않습니다. 새 자동 eval 프레임워크나 제품 Task마다 실제 에이전트 재실행을 요구하지 않습니다.

## 검증 선택과 시간 증거

허용된 기존 그룹만 관련성·선정 이유를 기록해 실행합니다. 그룹을 자동 추측해 실행하지 않으며, timeout·중단·미실행을 PASS로 처리하지 않습니다. 아래 표를 계획 시 채우고 완료 보고에서 실제 결과를 갱신합니다. 작업 전체 시간과 검증 실행 시간은 따로 기록합니다. 같은 입력·환경에서 통과한 검증은 새 변경·실패·미해결 우려가 있을 때만 재실행합니다.

| 선정 이유 | 명령·그룹 | 입력 revision/hash | 환경 | 예상 초 | 실제 초 | 결과·로그 | 재실행 이유 |
|---|---|---|---|---|---|---|---|
| [관련 변경] | [정확한 명령] | [실행 직전 입력] | [OS·런타임·물리 루트] | [초] | [초 또는 not_run] | [종료 코드·증거] | [최초/새 변경/실패/우려] |

작업 전체 시간: [초·시작/종료]. 검증 실행 시간: [각 명령 실제 초와 합계]. 이 표는 표준 본문 증거이며 workflow schema·상태·진입점이나 실행 권한을 변경하지 않습니다.

## 프로필 계약

`.agents/config/project-profile.conf`를 기준으로 작성합니다.

| 항목 | 계획 값 | 영향 |
|------|---------|------|
| `confirmation_status` | [pending/confirmed] | [강제 가능한 범위] |
| `architecture` | [값] | [선택 프로필의 역할과 의존 방향] |
| `dependency_injection` | [값 또는 `none`] | [컨테이너 또는 Composition Root] |
| `${source_root}` | [모든 값] | 생성·수정 범위 |
| `${test_root}` | [모든 값 또는 N/A] | 테스트 또는 대체 검증 범위 |

| 선택 프로필의 역할 | 클래스 | 책임 |
|---------------------|--------|------|
| [역할] | `[ClassName]` | [책임] |

`test_root`가 없으면 경로를 발명하지 않고 `N/A`로 기록한 뒤 대체 자동·수동 검증을 지정합니다.

## 기능·마일스톤 선언

| 항목 | 실제 값 |
|------|---------|
| 검증 범위 | 개별 Task 또는 기능·마일스톤 전체; 현재 승인 범위에 맞게 선택 |
| `milestone_id` | [기능·마일스톤 식별자] |
| 포함 Task | [Task 번호와 이름] |
| 수용 기준 | [검증 가능한 수용 기준] |
| `target_platform` | [대상 플랫폼] |
| 빌드 권위 | `local|unity_ci` |
| 변경 식별 근거 | Git change set 또는 비Git checksum |
| `coverage_status` | `confirmed` — 아래 실제 inventory 확정 후에만 사용 |
| evidence path | [동일 prebuild·built 증거 파일 경로] |
| change-id 계산 절차·명령 | [실제 무효화 범위와 재계산 명령] |
| `build_authority` | [실제 `local` 또는 `unity_ci` 한 값] |
| `build_run_id` | prebuild: `pending` / built: [실제 실행 ID] |
| `build_artifact_hash` | prebuild: `pending` / built: [lowercase 64-hex SHA-256] |

사용자가 개별 Task 검증을 요청한 경우 정적 검사, 대상 테스트, 논리적 변경 묶음 단위 Unity 컴파일을 계획합니다. Player Build는 사용자가 현재 명시적으로 요청한 경우에만 기능·마일스톤 사전 게이트 뒤의 최종 검증으로 계획합니다.

개별 Task 검증이면 아래 전체 모듈·상호작용 매트릭스와 prebuild/built·Player Build 계약은 `N/A`이며, 승인된 변경 범위와 컴파일·대상 테스트 증거를 계획합니다. 범위 선택은 검증 실행 권한을 추가하지 않습니다.

## 모듈 scope inventory

imported package, Asset Store, UPM과 third-party originals를 제외한 `Assets/_Game` project-owned module을 실제 식별자로 확정합니다.

| `module_scope` 실제 식별자 | 소유 경로·어셈블리 | 자동화 테스트 ID |
|----------------------------|--------------------|------------------|
| [실제 모듈 식별자] | [실제 경로·어셈블리] | [실제 테스트 ID] |

## 상호작용 scope inventory

프로젝트 소유 모듈 사이의 상호작용을 실제 식별자로 확정합니다.

| `interaction_scope` 실제 식별자 | 참여 모듈 | 자동화 Integration 테스트 ID |
|---------------------------------|-----------|--------------------------------|
| [실제 상호작용 식별자] | [실제 모듈 식별자 목록] | [실제 테스트 ID] |

## 작업 단위

### Task 1: [검증 가능한 컴포넌트]

**파일:**

- Create: `${source_root}/[경로]/[파일명].cs`
- Modify: `${source_root}/[경로]/[파일명].cs`
- Test: `${test_root}/[경로]/[테스트파일명].cs`

- [ ] **Step 1: 실패하는 테스트 또는 재현 절차 작성**
  - 실행 권한: `[현재 테스트 권한에 포함 / none이면 not_run]`
  - Run: `[명령 또는 Unity Test Runner 경로]`
  - Expected RED: `[기능 부재 때문에 발생하는 실패]`
- [ ] **Step 2: 실패 확인**
  - Evidence: `[종료 코드·실패 메시지 또는 not_run]`
- [ ] **Step 3: 최소 구현**
  - 선택 프로필 경계: `[역할과 허용 방향]`
  - `dependency_injection=none`이면 조립 위치: `[Composition Root]`
- [ ] **Step 4: 대상 테스트 통과 확인** — 권한이 없으면 `not_run`
- [ ] **Step 5: 관련 회귀 검사 실행** — 권한이 없으면 `not_run`
- [ ] **Step 6: 적용 가능한 코드·스크립트 컴파일·구문 오류 확인** — 문서만 변경하면 `N/A`
- [ ] **Step 7: 서브 에이전트 완료 보고 후 메인 에이전트 독립 정적 리뷰**

## 최적화 결정

| 기법 | 적용 상태 | 측정 근거 | 롤백 조건 | 담당 Task |
|------|-----------|-----------|-----------|-----------|
| [기법] | applicable / not_applicable / unknown | [전후 수치] | [회귀 기준] | [Task] |

적용할 최적화가 없더라도 `not_applicable` 근거를 남깁니다. 측정할 수 없으면 `unknown`으로 유지합니다.

## 아키텍처·SOLID 준수 선언

설계가 다음 항목을 어떻게 지키는지 선언합니다. 위반 소지가 있으면 사유와 대안 검토를 기록하고, 준수 선언 없이 구현 Task로 진행하지 않습니다. 문서만 변경하면 전체를 `N/A`로 기록합니다.

| 항목 | 선언 |
|------|------|
| 단일 책임·역할 경계 | [신규·수정 클래스별 책임 1줄과 선택 프로필 역할 매핑] |
| 의존 방향 | [허용 방향 준수 방식. 위반 소지가 있으면 사유] |
| 전역 상태 | [가변 public static 미사용 확인 또는 예외 사유] |

## 검증 계획

현재 테스트 권한에 포함된 항목만 실행합니다. 다음 명령과 체크리스트는 사용자가 요청한 경우의 실행 예시이며, 미요청 항목은 `not_run`입니다.

### 자동 검증

```bash
bash .agents/scripts/lint/check-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/lint/check-harness.ps1 -ProjectRoot .
```

### 프로젝트 검증

- [ ] `${test_root}` 테스트 또는 기록한 대체 검증 통과
- [ ] 컴파일·직렬화·씬 참조 영향 확인
- [ ] 최적화 전후 측정과 롤백 조건 확인

## 통합 테스트 매트릭스

`Assets/_Game` 전체의 프로젝트 소유 모듈과 상호작용을 자동화 테스트로 빠짐없이 매핑합니다. `module_result`·`interaction_result` 대상은 위 scope inventory와 exact match여야 하며 missing/unexpected/duplicate/invalid 또는 `failed/missing/not_run`이면 사전 빌드를 차단합니다.

| 자동화 대상 | 소유 모듈·상호작용 | 테스트 ID | 실행 권위 | 결과 |
|-------------|---------------------|-----------|-----------|------|
| Compile | [컴파일 대상] | [자동화 테스트 ID] | `local` 또는 `unity_ci` | passed / failed / missing / not_run |
| 전체 Unit | [소유 모듈] | [자동화 테스트 ID] | `local` 또는 `unity_ci` | passed / failed / missing / not_run |
| 전체 Integration | [모듈 간 상호작용] | [자동화 테스트 ID] | `local` 또는 `unity_ci` | passed / failed / missing / not_run |

## 증거 실행 계약

호출 직전에 위 change-id 계산 절차·명령을 실행하고, 결과를 동일 evidence path의 `change_id`와 expected 인자로 전달합니다.

### prebuild Bash

```bash
bash .agents/scripts/validation/check-unity-milestone.sh \
  --evidence [실제 evidence path] \
  --phase prebuild \
  --change-id [직전 재계산 change-id]
```

### prebuild PowerShell

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .agents/scripts/validation/check-unity-milestone.ps1 `
  -Evidence [실제 evidence path] `
  -Phase prebuild `
  -ExpectedChangeId [직전 재계산 change-id]
```

### built Bash

```bash
bash .agents/scripts/validation/check-unity-milestone.sh \
  --evidence [실제 evidence path] \
  --phase built \
  --change-id [직전 재계산 change-id] --expected-authority [prebuild에서-선택한-local-또는-unity_ci]
```

### built PowerShell

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .agents/scripts/validation/check-unity-milestone.ps1 `
  -Evidence [실제 evidence path] `
  -Phase built `
  -ExpectedChangeId [직전 재계산 change-id] -ExpectedAuthority [prebuild에서-선택한-local-또는-unity_ci]
```

## 최종 Player Build

사용자가 Player Build를 현재 명시적으로 요청한 경우에만 아래 체크리스트를 실행합니다. 요청하지 않았다면 전체 항목은 `not_run`이고 빌드 완료로 해석하지 않습니다.

- [ ] 전체 Task가 완료되었고 수용 기준을 충족함
- [ ] Compile+all Unit+all Integration이 모두 `passed`임
- [ ] scope inventory와 result matrix가 exact match이고 동일 `change_id`의 prebuild evidence가 검증됨
- [ ] same change의 Player Build 또는 Unity CI Build Validation once가 완료됨
- [ ] prebuild와 동일한 `build_authority` 1개의 실제 `build_run_id`와 lowercase 64-hex `build_artifact_hash`가 기록됨
- [ ] 같은 evidence path의 built 직전에 `change_id`를 재계산했고 `build_validation=passed` 증거와 일치함

## Open Questions

질문마다 결정권자와 구현 차단 여부를 기록합니다. **미결정 사항이 없으면 이 섹션을 삭제**합니다.

## 완료 기준

- [ ] 승인된 구현 Task가 완료됨
- [ ] 적용 가능한 코드·스크립트의 컴파일·구문 오류 확인 완료 또는 문서 변경 `N/A`
- [ ] 구현 후 메인 에이전트 독립 정적 리뷰 완료
- [ ] 중요한 리뷰 지적을 같은 구현 서브 에이전트가 수정했고 메인 에이전트가 재리뷰함
- [ ] 현재 테스트 권한에 포함된 검증만 완료됨
- [ ] 미요청 검증이 `not_run`으로 기록되었고 검증 완료·CI 통과·`ci_tests_passed`·`ci_passed`·Approve·Merge·Done으로 오인되지 않음
- [ ] 변경이 승인된 경로에 한정됨
- [ ] Inspector·직렬화·이벤트 후속 안내 완료
- [ ] 사용자 승인 완료 기준에 미실행 필수 검증이 남아 있지 않을 때만 이 계획을 `completed/`로 이동

## 변경 이력

| 날짜 | 작성자 | 변경 내용 |
|------|--------|-----------|
| YYYY-MM-DD | [작성자] | 초안 |

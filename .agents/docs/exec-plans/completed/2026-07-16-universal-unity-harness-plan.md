# 범용 Unity 하네스 구현 계획

> **에이전트 작업자 필수 하위 스킬:** 이 계획을 작업 단위별로 구현할 때 `superpowers:subagent-driven-development` 또는 `superpowers:executing-plans`를 사용한다. 모든 단계는 체크박스로 진행 상태를 추적한다.

**목표:** Unity 프로젝트를 읽기 전용으로 감지하여 안전한 프로젝트 프로필을 생성하고, 공통 규칙과 확정된 아키텍처·기술 프로필만 검사하는 크로스플랫폼 `.agents` 하네스를 구축한다.

**아키텍처:** 공통 규칙, 조건부 최적화 지식, 선택 프로필을 분리한다. Bash와 PowerShell 구현은 하나의 설정 스키마와 감지 시그니처를 공유하고 동일한 검사 ID·심각도·종료 코드를 출력한다. 자동화는 `.agents` 밖의 Unity 프로젝트 파일을 변경하지 않는다.

**기술 스택:** Bash 3.2 호환 셸, PowerShell 5.1+ 호환 스크립트, Unity YAML·JSON 텍스트 파일, `find`·`grep`·`sed`·`awk`, PowerShell 기본 cmdlet. 외부 Python, Node.js, `jq`, Pester 의존성은 추가하지 않는다.

**설계 문서:** `.agents/docs/design-docs/2026-07-16-universal-unity-harness-design.md`

**저장소 제약:** 대상 폴더는 Git 저장소가 아니다. 각 Task의 마지막은 커밋 대신 전체 변경 파일과 검증 결과를 확인하는 체크포인트로 사용한다. Git 저장소를 새로 만들거나 외부 저장소에 커밋하지 않는다.

**필수 에이전트 도구:** 구현과 검수에 `multica-ai/andrej-karpathy-skills`, `obra/superpowers`, `Understand-Anything`을 적극 사용한다. 설치 감지와 수동 부트스트랩 경로를 하네스에 포함하되, 일반 초기화·린트 실행은 사용자의 전역 Codex 설정을 자동 변경하지 않는다.

**현재 환경 확인 결과:** 세 도구는 모두 설치·활성화되어 있다. Understand-Anything은 사용자가 제시한 `Lum1104/Understand-Anything`의 현재 계승 저장소인 `Egonex-AI/Understand-Anything`에서 설치된 2.9.2 계열을 그대로 사용한다. 이미 작동하는 전역 설치본을 교체하지 않는다.

---

## 최종 파일 구조

### 신규 설정 파일

- `.agents/config/profile-schema.conf`: 허용 키, 필수 여부, 반복 가능 여부, 값 형식을 정의하는 단일 스키마
- `.agents/config/project-profile.example.conf`: 기존 베이스 규칙을 초기값으로 사용하는 프로필 예시
- `.agents/config/detection-signatures.conf`: 아키텍처 감지용 공통 시그니처와 가중치
- `.agents/config/agent-tooling.conf`: 필수 에이전트 도구 ID, 원격 소스, 설치 진입점, 사용 정책

### 신규 Bash 파일

- `.agents/scripts/shared/profile.sh`: 안전한 프로필 파싱·검증·쓰기
- `.agents/scripts/shared/detect.sh`: 프로젝트 루트, 패키지, 렌더링, 경로, 아키텍처 감지
- `.agents/scripts/shared/lint.sh`: 공통 검사와 선택 프로필 검사
- `.agents/scripts/init/initialize-harness.sh`: 감지·후보 생성·확정 진입점
- `.agents/scripts/lint/check-harness.sh`: 프로필 기반 검사 진입점
- `.agents/scripts/setup/check-agent-tooling.sh`: 전역 스킬·플러그인 상태 확인과 명시적 부트스트랩

### 신규 PowerShell 파일

- `.agents/scripts/shared/profile.ps1`
- `.agents/scripts/shared/detect.ps1`
- `.agents/scripts/shared/lint.ps1`
- `.agents/scripts/init/initialize-harness.ps1`
- `.agents/scripts/lint/check-harness.ps1`
- `.agents/scripts/ci/pre-commit-checks.ps1`
- `.agents/scripts/setup/check-agent-tooling.ps1`

### 신규 테스트 파일

- `.agents/tests/run-tests.sh`: 임시 Unity 픽스처 생성, Bash 기능 검사, PowerShell 호출 가능 시 교차 검증
- `.agents/tests/run-tests.ps1`: 같은 픽스처 계약을 PowerShell에서 검증
- `.agents/tests/README.md`: 실행 방법과 미검증 경계
- `.agents/reports/.gitkeep`: 생성 보고서 디렉터리 유지

### 신규 규칙 문서

- `.agents/docs/coding-standards/core/architecture-principles.md`
- `.agents/docs/coding-standards/core/naming-and-documentation.md`
- `.agents/docs/coding-standards/core/runtime-performance.md`
- `.agents/docs/coding-standards/core/unity-safety.md`
- `.agents/docs/coding-standards/optimization/rendering-techniques.md`
- `.agents/docs/profiles/architecture/mvvm.md`
- `.agents/docs/profiles/architecture/mvp.md`
- `.agents/docs/profiles/architecture/mvc.md`
- `.agents/docs/profiles/architecture/layered-clean.md`
- `.agents/docs/profiles/architecture/custom.md`
- `.agents/docs/profiles/dependency-injection.md`
- `.agents/docs/profiles/async.md`
- `.agents/docs/profiles/tween.md`
- `.agents/docs/profiles/rendering.md`
- `.agents/docs/onboarding/agent-tooling.md`

### 수정할 기존 파일

- `.agents/AGENTS.md`
- `.agents/ARCHITECTURE.md`
- `.agents/docs/coding-standards/architecture-rules.md`
- `.agents/docs/coding-standards/naming-conventions.md`
- `.agents/docs/coding-standards/performance-rules.md`
- `.agents/docs/coding-standards/safety-rules.md`
- `.agents/docs/coding-standards/unity-specific.md`
- `.agents/docs/design-docs/README.md`
- `.agents/docs/design-docs/_TEMPLATE.md`
- `.agents/docs/exec-plans/README.md`
- `.agents/docs/exec-plans/_TEMPLATE.md`
- `.agents/docs/product-specs/README.md`
- `.agents/docs/product-specs/_TEMPLATE.md`
- `.agents/docs/onboarding/agent-quickstart.md`
- `.agents/docs/onboarding/developer-quickstart.md`
- `.agents/docs/onboarding/tech-stack-overview.md`
- `.agents/scripts/README.md`
- `.agents/scripts/lint/check-architecture.sh`
- `.agents/scripts/ci/pre-commit-checks.sh`

---

### Task 1: 공통 프로필 계약과 테스트 러너 고정

**Files:**
- Create: `.agents/config/profile-schema.conf`
- Create: `.agents/config/project-profile.example.conf`
- Create: `.agents/config/detection-signatures.conf`
- Create: `.agents/tests/run-tests.sh`
- Create: `.agents/tests/run-tests.ps1`
- Create: `.agents/tests/README.md`
- Create: `.agents/reports/.gitkeep`

- [x] **Step 1: Bash 테스트 러너에 실패하는 계약 테스트 작성**

`run-tests.sh`는 `set -u`를 사용하되 개별 테스트의 실패를 수집하여 마지막에 `통과 N / 실패 M / 건너뜀 K`를 출력한다. 테스트 임시 루트는 `mktemp -d`로 만들고 `trap`에서 제거한다. 다음 테스트 이름을 고정한다.

```bash
test_profile_accepts_repeated_source_roots
test_profile_rejects_unknown_key
test_profile_rejects_invalid_enum
test_profile_does_not_execute_values
test_detect_rejects_non_unity_directory
test_detects_mvvm_vcontainer_unitask_urp
test_architecture_conflict_falls_back_to_custom
test_existing_confirmed_profile_is_not_overwritten
test_pending_profile_downgrades_profile_violation_to_warning
test_confirmed_profile_blocks_profile_violation
test_custom_profile_skips_architecture_specific_rules
test_korean_and_space_path_is_supported
test_detection_does_not_modify_project_files
```

프로필 값 실행 방지 테스트는 다음 입력을 파일에 기록하고, 파싱 후 표식 파일이 생기지 않았는지 검사한다.

```text
project_name=$(touch __profile_value_executed__)
```

- [x] **Step 2: 초기 테스트 실패 확인**

Run:

```bash
bash .agents/tests/run-tests.sh
```

Expected: `profile.sh 파일을 찾을 수 없습니다`를 포함하고 종료 코드 `1`.

- [x] **Step 3: 공통 스키마 작성**

`profile-schema.conf`는 `key|required|cardinality|type|allowed` 열을 사용한다. 전체 키를 다음과 같이 고정한다.

```text
profile_version|required|single|enum|1
confirmation_status|required|single|enum|pending,confirmed
project_name|required|single|text|
unity_version|required|single|text|
render_pipeline|required|single|enum|urp,hdrp,builtin,custom,unknown
architecture|required|single|enum|mvvm,mvp,mvc,layered_clean,custom
source_root|required|multiple|path|
test_root|optional|multiple|path|
dependency_injection|required|single|enum|vcontainer,zenject,custom,none,unknown
async_backend|required|single|enum|unitask,coroutine,task,mixed,unknown
tween_backend|required|single|enum|dotween,leantween,custom,none,unknown
target_platform|required|multiple|text|
response_language|required|single|enum|ko,en,project_default
log_language|required|single|enum|ko,en,project_default
author_name|required|single|text|
private_field_prefix|required|single|text|
ui_callback_prefix|required|single|text|
region_policy|required|single|enum|required,encouraged,disabled
xml_documentation_policy|required|single|enum|all_methods,public_api,disabled
gpu_resident_drawer|required|single|enum|applicable,not_applicable,unknown
gpu_occlusion_culling|required|single|enum|applicable,not_applicable,unknown
stp|required|single|enum|applicable,not_applicable,unknown
mesh_lod|required|single|enum|applicable,not_applicable,unknown
exclude_root|optional|multiple|path|
```

- [x] **Step 4: 베이스 프로필 예시 작성**

예시 파일은 `pending`, `custom`, `unknown`을 안전한 초기 상태로 사용하고 사용자 베이스 정책은 다음 값으로 제안한다.

```text
profile_version=1
confirmation_status=pending
project_name=SampleGame
unity_version=unknown
render_pipeline=unknown
architecture=custom
source_root=Assets
dependency_injection=unknown
async_backend=unknown
tween_backend=unknown
target_platform=unknown
response_language=ko
log_language=ko
author_name=윤승종
private_field_prefix=m_
ui_callback_prefix=func_
region_policy=encouraged
xml_documentation_policy=all_methods
gpu_resident_drawer=unknown
gpu_occlusion_culling=unknown
stp=unknown
mesh_lod=unknown
exclude_root=Assets/Plugins
exclude_root=Assets/ThirdParty
```

- [x] **Step 5: 아키텍처 감지 시그니처 작성**

시그니처 형식은 `profile|pattern|weight`로 고정한다. Bash `grep -E`와 .NET 정규식 양쪽에서 같은 의미인 표현만 사용한다.

```text
mvvm|ViewModel|4
mvvm|Views?/|1
mvvm|Models?/|1
mvp|Presenter|4
mvp|Views?/|1
mvp|Models?/|1
mvc|Controller|4
mvc|Views?/|1
mvc|Models?/|1
layered_clean|UseCase|4
layered_clean|Domain|2
layered_clean|Application|2
layered_clean|Infrastructure|2
```

- [x] **Step 6: 테스트 러너 자체 문법 확인**

Run:

```bash
bash -n .agents/tests/run-tests.sh
```

Expected: 출력 없음, 종료 코드 `0`.

- [x] **Step 7: Task 1 체크포인트**

Run:

```bash
find .agents/config .agents/tests .agents/reports -type f -print | sort
```

Expected: 설정 3개, 테스트 3개, 보고서 유지 파일 1개가 출력된다.

---

### Task 2: Bash 3.2 호환 안전 프로필 파서 구현

**Files:**
- Create: `.agents/scripts/shared/profile.sh`
- Modify: `.agents/tests/run-tests.sh`

- [x] **Step 1: 파서 실패 테스트 활성화**

테스트 러너에서 `profile.sh`를 로드하고 다음 API를 호출한다.

```bash
profile_reset
profile_load "$profile_path" "$schema_path"
profile_validate "$schema_path"
profile_get "architecture"
profile_get_all "source_root"
profile_write "$output_path"
```

Expected contracts:

- 알 수 없는 키: 반환 코드 `3`
- 잘못된 열거형: 반환 코드 `3`
- 반복 불가 키 중복: 반환 코드 `3`
- 필수 키 누락: 반환 코드 `3`
- 두 개의 `source_root`: 입력 순서를 유지하여 두 줄 반환
- `$()`, 백틱과 세미콜론이 포함된 값: 문자열로 보존하고 실행하지 않음

- [x] **Step 2: 실패 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group profile
```

Expected: `profile_reset: command not found` 또는 동일한 미구현 실패, 종료 코드 `1`.

- [x] **Step 3: 안전한 파서 구현**

`profile.sh`는 연관 배열, `eval`, `source`를 사용하지 않는다. Bash 3.2에서 동작하도록 개행 구분 문자열을 저장소로 사용한다.

필수 공개 함수:

```bash
profile_reset()
profile_load()
profile_validate()
profile_get()
profile_get_all()
profile_set_single()
profile_write()
profile_confirm()
```

구현 규칙:

1. 빈 줄과 첫 비공백 문자가 `#`인 줄만 건너뛴다.
2. 첫 `=` 이전을 키, 이후 전체를 값으로 보존한다.
3. 키는 스키마의 첫 열과 정확히 일치해야 한다.
4. 경로는 절대 경로, `..`, 역슬래시를 허용하되 프로젝트 루트와 결합한 뒤 검사 단계에서 정규화한다.
5. `profile_confirm`은 기존 파일을 임시 파일에 복제해 `confirmation_status`만 바꾼 뒤 원자적으로 교체한다.
6. 출력 키 순서는 스키마 순서와 같아야 한다.

- [x] **Step 4: 프로필 테스트 통과 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group profile
```

Expected: `프로필 테스트: 통과`, 종료 코드 `0`, `__profile_value_executed__` 파일 없음.

- [x] **Step 5: Bash 문법과 금지 API 검사**

Run:

```bash
bash -n .agents/scripts/shared/profile.sh
grep -En '\beval\b|^[[:space:]]*(source|\.)[[:space:]].*project-profile' .agents/scripts/shared/profile.sh
```

Expected: 문법 검사 `0`, 금지 API 검색 결과 없음.

- [x] **Step 6: Task 2 체크포인트**

Run:

```bash
bash .agents/tests/run-tests.sh --group profile
```

Expected: 프로필 그룹 전체 통과.

---

### Task 3: Bash 읽기 전용 감지기와 초기화 진입점 구현

**Files:**
- Create: `.agents/scripts/shared/detect.sh`
- Create: `.agents/scripts/init/initialize-harness.sh`
- Modify: `.agents/tests/run-tests.sh`

- [x] **Step 1: 감지 픽스처와 실패 테스트 작성**

테스트 러너가 임시 디렉터리에 다음 픽스처를 생성한다.

```text
mvvm-urp/
├── ProjectSettings/ProjectVersion.txt
├── ProjectSettings/GraphicsSettings.asset
├── Packages/manifest.json
└── Assets/_Game/Scripts/{Views,ViewModels,Models}/*.cs

conflict/
├── ProjectSettings/ProjectVersion.txt
├── Packages/manifest.json
└── Assets/Scripts/{ViewModels,Presenters}/*.cs

not-unity/
└── README.md
```

MVVM 픽스처의 `manifest.json`에는 `com.unity.render-pipelines.universal`, `jp.hadashikick.vcontainer`, `com.cysharp.unitask` 키를 넣는다. C# 파일에는 `ViewModel` 타입과 `VContainer`, `Cysharp.Threading.Tasks`, `DG.Tweening` 네임스페이스 증거를 넣는다.

- [x] **Step 2: 감지 테스트 실패 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group detection
```

Expected: `detect_project: command not found`, 종료 코드 `1`.

- [x] **Step 3: 프로젝트·패키지·경로 감지 구현**

`detect.sh` 공개 API:

```bash
find_unity_project_root()
detect_unity_version()
detect_source_roots()
detect_test_roots()
detect_render_pipeline()
detect_dependency_injection()
detect_async_backend()
detect_tween_backend()
detect_target_platforms()
detect_architecture()
detect_optimization_states()
write_detection_report()
detect_project()
```

판정 규칙:

- `ProjectVersion.txt`와 `manifest.json`이 모두 있어야 Unity 프로젝트다.
- 소스 루트 우선순위는 `.asmdef`가 있는 코드 루트, 이름이 `Scripts`인 코드 루트, 마지막으로 `Assets`다.
- 기본 제외 경로는 `Library`, `Temp`, `Logs`, `obj`, `UserSettings`, `Packages`, `.git`, `.agents`, `Assets/Plugins`, `Assets/ThirdParty`다.
- 아키텍처 점수가 하나만 최고이고 4 이상이면 해당 프로필을 사용한다.
- 최고 점수 동률, 최고 점수 4 미만 또는 증거 없음이면 `custom`을 사용한다.
- URP와 HDRP 패키지가 동시에 발견되면 `custom`; 하나만 발견되면 해당 값; 둘 다 없고 커스텀 파이프라인 참조가 비어 있으면 `builtin`; 나머지는 `unknown`이다.
- UniTask, Coroutine, Task 증거가 둘 이상이면 `mixed`다.
- 정적 프로젝트 파일에서 타겟 플랫폼을 확정할 근거가 없으면 `target_platform=unknown`으로 두고 보고서의 사용자 확인 항목에 기록한다.
- GPU 기법은 지원 증거가 충분할 때만 `applicable`, 명확히 지원하지 않을 때 `not_applicable`, 씬·플랫폼 판단이 필요하면 `unknown`이다.

- [x] **Step 4: 보고서 형식 구현**

`detection-report.md`는 다음 섹션을 항상 포함한다.

```markdown
# Unity 하네스 감지 보고서
## 요약
## 감지 근거와 신뢰도
## 소스 및 테스트 루트
## 조건부 최적화 적용 가능성
## 충돌 및 미확정 항목
## 사용자 확인 절차
```

각 요약 항목은 `값`, `신뢰도`, `근거 파일`을 기록한다. 정적 파일만으로 확인할 수 없는 씬 가림 구조와 GPU 병목은 `unknown`으로 기록한다.

- [x] **Step 5: 초기화 진입점 구현**

지원 명령:

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root .
bash .agents/scripts/init/initialize-harness.sh --project-root . --confirm
bash .agents/scripts/init/initialize-harness.sh --project-root . --redetect
```

동작:

- 첫 감지: `project-profile.conf`와 `detection-report.md` 생성
- 확정 파일 존재: 덮어쓰지 않고 종료 코드 `0`과 안내 출력
- `--redetect`: `project-profile.candidate.conf`와 비교 보고서 생성
- `--confirm`: 스키마 검증 후 상태만 `confirmed`로 변경
- Unity 프로젝트 아님: 아무 파일도 쓰지 않고 종료 코드 `2`
- 필수 파일 읽기 실패: 종료 코드 `4`

- [x] **Step 6: 감지 테스트 통과 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group detection
```

Expected: MVVM 픽스처는 `mvvm/vcontainer/unitask/urp`, 충돌 픽스처는 `custom`, 비Unity 픽스처는 종료 코드 `2`.

- [x] **Step 7: 변경 금지 검사 통과 확인**

테스트는 감지 전후 `.agents` 외부의 `find` 목록과 `cksum` 결과를 비교한다.

Run:

```bash
bash .agents/tests/run-tests.sh --group readonly
```

Expected: `프로젝트 파일 변경 없음`, 종료 코드 `0`.

- [x] **Step 8: Task 3 체크포인트**

Run:

```bash
bash -n .agents/scripts/shared/detect.sh
bash -n .agents/scripts/init/initialize-harness.sh
```

Expected: 모두 출력 없음, 종료 코드 `0`.

---

### Task 4: Bash 공통·프로필 린터와 CI 진입점 구현

**Files:**
- Create: `.agents/scripts/shared/lint.sh`
- Create: `.agents/scripts/lint/check-harness.sh`
- Modify: `.agents/scripts/lint/check-architecture.sh`
- Modify: `.agents/scripts/ci/pre-commit-checks.sh`
- Modify: `.agents/tests/run-tests.sh`

- [x] **Step 1: 린터 실패 테스트 작성**

정규화된 출력 계약은 다음과 같다.

```text
RULE_ID|severity|relative/path.cs|line|한글 메시지
```

검사 ID와 심각도:

```text
CONFIG001|error|프로필 오류
PATH001|error|소스 루트 없음
SOLID001|error|public static Instance 싱글톤 의심
PERF001|warning|매 프레임 LINQ 사용
PERF002|warning|매 프레임 참조 타입 new 할당
UNITYNULL001|warning|Unity Object Fake Null 오용 의심
MVVM001|error|View에서 Model 직접 참조
MVP001|error|View에서 Model 직접 참조
MVC001|warning|View에서 Model 상태 직접 변경 의심
LAYER001|error|Domain에서 바깥 계층 참조
VCONTAINER001|warning|직렬화 View RegisterInstance 사용 의심
UNITASK001|error|UniTask 확정 프로젝트의 Coroutine 사용
DOTWEEN001|warning|Update 계열에서 Tween 생성
STYLE001|warning|private 필드 접두사 위반
DOC001|warning|프로필 문서화 정책 위반
```

테스트는 `pending`일 때 `MVVM001`을 warning으로 낮추고 종료 코드 `0`, `confirmed`일 때 error와 종료 코드 `1`, `custom`일 때 `MVVM001` 미출력을 요구한다.

- [x] **Step 2: 린터 테스트 실패 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group lint
```

Expected: `lint_project: command not found`, 종료 코드 `1`.

- [x] **Step 3: 공통 검사 구현**

`lint.sh` 공개 API:

```bash
lint_reset()
lint_emit()
lint_core_rules()
lint_architecture_rules()
lint_technology_rules()
lint_project()
lint_exit_code()
```

구현 제약:

- `source_root` 목록만 검사한다.
- `exclude_root`와 기본 제외 경계를 먼저 적용한다.
- 정규식만으로 타입을 확정할 수 없는 Fake Null·할당 검사는 warning이다.
- `public static ... Instance`는 Core error로 유지한다.
- 프로필 상태가 `pending`이면 모든 프로필 error를 warning으로 낮춘다.
- `architecture=custom`이면 아키텍처 규칙을 실행하지 않는다.
- 기술 프로필 값이 `unknown`, `none`, `custom`이면 해당 기술 전용 검사를 실행하지 않는다.

- [x] **Step 4: 진입점과 호환 래퍼 구현**

`check-harness.sh`는 `--project-root`, `--profile`, `--format human|machine`을 지원한다. 기존 `check-architecture.sh`는 새 진입점을 호출하고 다음 폐기 예정 안내를 한 줄 출력한다.

```text
[check-architecture] 범용 검사기로 위임합니다: check-harness.sh
```

`pre-commit-checks.sh`는 Git 저장소 여부와 관계없이 전체 프로필 검사를 실행한다. Git 저장소이면 현재 브랜치나 스테이징 상태를 수정하지 않는다.

- [x] **Step 5: 린터 테스트 통과 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group lint
```

Expected: `pending`, `confirmed`, `custom` 시나리오 모두 통과.

- [x] **Step 6: Bash 전체 검사 통과 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --runtime bash
```

Expected: 실패 `0`.

- [x] **Step 7: Task 4 체크포인트**

Run:

```bash
bash -n .agents/scripts/shared/lint.sh
bash -n .agents/scripts/lint/check-harness.sh
bash -n .agents/scripts/lint/check-architecture.sh
bash -n .agents/scripts/ci/pre-commit-checks.sh
```

Expected: 모두 출력 없음, 종료 코드 `0`.

---

### Task 5: PowerShell 5.1+ 동등 구현

**Files:**
- Create: `.agents/scripts/shared/profile.ps1`
- Create: `.agents/scripts/shared/detect.ps1`
- Create: `.agents/scripts/shared/lint.ps1`
- Create: `.agents/scripts/init/initialize-harness.ps1`
- Create: `.agents/scripts/lint/check-harness.ps1`
- Create: `.agents/scripts/ci/pre-commit-checks.ps1`
- Modify: `.agents/tests/run-tests.ps1`
- Modify: `.agents/tests/run-tests.sh`

- [x] **Step 1: PowerShell 계약 테스트 활성화**

`run-tests.ps1`은 외부 Pester 없이 `Assert-Equal`, `Assert-True`, `Assert-ExitCode` 함수를 정의한다. Bash 테스트와 같은 픽스처 이름과 기대 프로필을 사용한다.

필수 공개 함수:

```powershell
Read-HarnessProfile
Test-HarnessProfile
Write-HarnessProfile
Confirm-HarnessProfile
Find-UnityProjectRoot
Invoke-ProjectDetection
Write-DetectionReport
Invoke-HarnessLint
```

- [x] **Step 2: PowerShell 테스트 실패 확인**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/tests/run-tests.ps1
```

Expected: `Read-HarnessProfile 명령을 찾을 수 없습니다`, 종료 코드 `1`.

- [x] **Step 3: 프로필 파서 구현**

구현 규칙:

- `Get-Content`로 줄 단위 파싱
- 스키마 키만 `[ordered]` 사전에 저장
- 값은 `Invoke-Expression`로 평가하지 않음
- 반복 키는 `List[string]`으로 보존
- 출력 순서는 스키마 순서
- 오류는 종료 코드 `3`으로 변환

- [x] **Step 4: 감지기와 초기화 진입점 구현**

Bash와 동일한 점수, 충돌, 후보 파일, 보고서, 종료 코드 규칙을 구현한다. 경로 비교 전에 `[IO.Path]::GetFullPath()`로 정규화하고 비교 시 플랫폼의 대소문자 규칙을 따른다.

- [x] **Step 5: 린터와 CI 진입점 구현**

기계 출력은 Bash와 같은 `RULE_ID|severity|path|line|message` 형식을 사용한다. `pending` 심각도 하향, `custom` 아키텍처 검사 생략과 기술 프로필 라우팅을 동일하게 구현한다.

- [x] **Step 6: PowerShell 단독 테스트 통과 확인**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/tests/run-tests.ps1
```

Expected: 실패 `0`.

- [x] **Step 7: Bash·PowerShell 결과 비교**

`run-tests.sh`는 `pwsh` 또는 `powershell`을 찾으면 동일 픽스처의 프로필을 정렬 없이 비교한다. 런타임이 없으면 `PowerShell 런타임 없음: 교차 검증 미실행`을 출력하고 건너뜀 수를 증가시킨다.

Run:

```bash
bash .agents/tests/run-tests.sh --group parity
```

Expected when PowerShell exists: `Bash/PowerShell 프로필 및 종료 코드 일치`.

Expected when absent: 건너뜀 `1`, 전체 종료 코드 `0`, 최종 검증 보고서에 미검증 경계 기록.

- [x] **Step 8: Task 5 체크포인트**

PowerShell 런타임이 있으면 모든 `.ps1`을 파서로 검사한다. 없으면 파일 존재와 금지 API만 정적으로 검사한다.

```bash
find .agents/scripts -name '*.ps1' -type f -exec grep -En 'Invoke-Expression|iex[[:space:]]' {} +
```

Expected: 검색 결과 없음.

---

### Task 6: 공통 규칙·최적화·선택 프로필 문서 분리

**Files:**
- Create: `.agents/docs/coding-standards/core/architecture-principles.md`
- Create: `.agents/docs/coding-standards/core/naming-and-documentation.md`
- Create: `.agents/docs/coding-standards/core/runtime-performance.md`
- Create: `.agents/docs/coding-standards/core/unity-safety.md`
- Create: `.agents/docs/coding-standards/optimization/rendering-techniques.md`
- Create: `.agents/docs/profiles/architecture/mvvm.md`
- Create: `.agents/docs/profiles/architecture/mvp.md`
- Create: `.agents/docs/profiles/architecture/mvc.md`
- Create: `.agents/docs/profiles/architecture/layered-clean.md`
- Create: `.agents/docs/profiles/architecture/custom.md`
- Create: `.agents/docs/profiles/dependency-injection.md`
- Create: `.agents/docs/profiles/async.md`
- Create: `.agents/docs/profiles/tween.md`
- Create: `.agents/docs/profiles/rendering.md`
- Modify: `.agents/docs/coding-standards/architecture-rules.md`
- Modify: `.agents/docs/coding-standards/naming-conventions.md`
- Modify: `.agents/docs/coding-standards/performance-rules.md`
- Modify: `.agents/docs/coding-standards/safety-rules.md`
- Modify: `.agents/docs/coding-standards/unity-specific.md`

- [x] **Step 1: 문서 라우팅 실패 검사 추가**

테스트 러너에 다음 검사를 추가한다.

```text
Core 문서에서 "MVVM 필수", "VContainer 필수", "URP 필수", "Assets/Scripts 고정" 표현이 없어야 한다.
모든 profile 값이 하나 이상의 프로필 문서에 연결되어야 한다.
GPU Resident Drawer, GPU Occlusion Culling, STP, Mesh LOD가 최적화 베이스 문서에 존재해야 한다.
```

- [x] **Step 2: 실패 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group docs
```

Expected: 기존 고정 전제 검출로 종료 코드 `1`.

- [x] **Step 3: Core 문서 작성**

Core 문서에 다음 경계를 적용한다.

- `architecture-principles.md`: Pure C# 분리, SOLID, No Singleton, 인터페이스 의존, 승인 전 구현 금지, 서드파티 원본 수정 금지
- `naming-and-documentation.md`: 프로필 키가 실제 규칙을 결정하며 기존 `m_`, `func_`, 한글, 윤승종은 기본 제안값임을 명시
- `runtime-performance.md`: 프레임 루프 할당·LINQ·Boxing 제한, 캐싱, 풀링, 측정 우선 원칙
- `unity-safety.md`: Fake Null, `FormerlySerializedAs`, Unity 이벤트 구독 해제, 직렬화 안전

- [x] **Step 4: 최적화 베이스 문서 작성**

기존 네 가지 렌더링 최적화 설명을 보존하면서 각 항목을 다음 순서로 통일한다.

```text
목적 → 작동 원리 → 적용 사전 조건 → applicable 판정 → not_applicable 판정 → unknown 판정 → 프로파일링 검증 → 부작용과 롤백
```

Unity 버전·렌더 파이프라인 조건을 만족하지 않으면 활성화를 강제하지 않는다.

- [x] **Step 5: 아키텍처 프로필 문서 작성**

각 문서는 `책임`, `허용 의존 방향`, `금지 의존 방향`, `감지 증거`, `검사 ID`, `VContainer 비의존 예시`를 포함한다. `custom.md`는 Core만 강제하고 사용자가 프로젝트 경계를 기록하는 방법을 설명한다.

- [x] **Step 6: 기술 프로필 문서 작성**

- `dependency-injection.md`: VContainer, Zenject, Custom, None, Unknown 분기
- `async.md`: UniTask, Coroutine, Task, Mixed, Unknown 분기와 공통 취소·수명 원칙
- `tween.md`: DOTween, LeanTween, Custom, None, Unknown 분기와 파괴 시 정리 원칙
- `rendering.md`: URP, HDRP, Built-in, Custom, Unknown 분기와 최적화 문서 연결

- [x] **Step 7: 기존 문서를 호환 인덱스로 전환**

기존 다섯 문서 경로는 삭제하지 않는다. 상단에 새 문서 구조와 프로필 우선순위를 안내하고, 기존 예시 중 특정 기술을 필수로 표현한 문장은 선택 프로필 예시로 이동한다.

- [x] **Step 8: 문서 검사 통과 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group docs
```

Expected: 고정 전제 누락 `0`, 최적화 기법 누락 `0`, 프로필 라우팅 누락 `0`.

- [x] **Step 9: Task 6 체크포인트**

Run:

```bash
find .agents/docs/coding-standards .agents/docs/profiles -type f -print | sort
```

Expected: Core 4개, Optimization 1개, Profile 9개와 호환 문서 5개가 출력된다.

---

### Task 7: 진입점·온보딩·설계 템플릿 범용화

**Files:**
- Modify: `.agents/AGENTS.md`
- Modify: `.agents/ARCHITECTURE.md`
- Modify: `.agents/docs/design-docs/README.md`
- Modify: `.agents/docs/design-docs/_TEMPLATE.md`
- Modify: `.agents/docs/exec-plans/README.md`
- Modify: `.agents/docs/exec-plans/_TEMPLATE.md`
- Modify: `.agents/docs/product-specs/README.md`
- Modify: `.agents/docs/product-specs/_TEMPLATE.md`
- Modify: `.agents/docs/onboarding/agent-quickstart.md`
- Modify: `.agents/docs/onboarding/developer-quickstart.md`
- Modify: `.agents/docs/onboarding/tech-stack-overview.md`
- Modify: `.agents/scripts/README.md`

- [x] **Step 1: 진입점 실패 검사 추가**

테스트 러너가 다음 문구와 경로를 검사한다.

```text
AGENTS.md: project-profile.conf, pending, confirmed, Custom
ARCHITECTURE.md: Core, Optimization Base, Profiles
agent-quickstart.md: 초기화 → 보고서 검토 → 프로필 확정 → 검사
scripts/README.md: Bash와 PowerShell 실행 예시
```

또한 템플릿의 생성·수정·테스트 경로가 `Assets/Scripts`가 아니라 `source_root`, `test_root`를 참조해야 한다.

- [x] **Step 2: 실패 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group entrypoints
```

Expected: 기존 MVVM·VContainer·`Assets/Scripts` 고정 문구로 종료 코드 `1`.

- [x] **Step 3: `AGENTS.md`와 `ARCHITECTURE.md` 개편**

`AGENTS.md` 읽기 순서를 다음으로 고정한다.

```text
1. config/project-profile.conf 상태 확인
2. Core 규칙 로드
3. Optimization Base 로드
4. confirmed일 때만 선택 Profiles 로드
5. pending 또는 Custom이면 강제 범위 축소
6. 구현 전 전체 계획 승인 확인
```

`ARCHITECTURE.md`는 하네스 모듈 구조, 감지·확정 흐름, 규칙 활성화 방향과 생성 파일 경계를 설명한다.

- [x] **Step 4: 설계·계획·제품 스펙 템플릿 개편**

- 레이어 표는 `선택 프로필의 역할`과 `클래스` 열을 사용한다.
- 데이터 흐름은 MVVM 고정 다이어그램 대신 선택 프로필 문서를 링크한다.
- DI 섹션은 `dependency_injection` 값이 `none`일 수 있음을 허용한다.
- 파일 경로는 `${source_root}`와 `${test_root}` 표기로 통일한다.
- 최적화 섹션은 적용 상태, 측정 근거, 롤백 조건을 기록한다.
- Open Questions는 실제 미결정 사항이 있을 때만 사용하도록 안내한다.

- [x] **Step 5: 온보딩과 스크립트 가이드 개편**

Bash와 PowerShell 예시를 모두 제공한다.

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root .
bash .agents/scripts/lint/check-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot .
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/lint/check-harness.ps1 -ProjectRoot .
```

- [x] **Step 6: 진입점 검사 통과 확인**

Run:

```bash
bash .agents/tests/run-tests.sh --group entrypoints
```

Expected: 필수 라우팅 문구와 경로가 모두 존재하고 고정 기술 전제 없음.

- [x] **Step 7: Task 7 체크포인트**

Run:

```bash
grep -REn 'Assets/Scripts|MVVM.*필수|VContainer.*필수|URP.*필수' .agents/AGENTS.md .agents/ARCHITECTURE.md .agents/docs/onboarding .agents/docs/design-docs/_TEMPLATE.md .agents/docs/exec-plans/_TEMPLATE.md
```

Expected: 특정 프로필의 반례나 마이그레이션 설명을 제외하고 하드코딩된 필수 전제 없음.

---

### Task 8: 기본 하네스 검증과 누락 감사

**Files:**
- Modify: `.agents/tests/README.md`
- Modify: `.agents/docs/exec-plans/completed/2026-07-16-universal-unity-harness-plan.md`

- [x] **Step 1: 전체 셸 문법 검사**

Run:

```bash
find .agents/scripts .agents/tests -name '*.sh' -type f -exec bash -n {} \;
```

Expected: 출력 없음, 종료 코드 `0`.

- [x] **Step 2: Bash 전체 기능 테스트**

Run:

```bash
bash .agents/tests/run-tests.sh --runtime bash
```

Expected: 실패 `0`, 건너뜀은 PowerShell 부재 항목만 허용.

- [x] **Step 3: PowerShell 문법·기능 테스트**

PowerShell 런타임이 있으면 실행한다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/tests/run-tests.ps1
```

Expected: 실패 `0`.

PowerShell 런타임이 없으면 테스트 README와 최종 결과에 `PowerShell 실행 검증 미실시`를 기록하고 정적 금지 API 검사 결과를 함께 남긴다.

- [x] **Step 4: 독립 하네스 폴더에서 비Unity 동작 확인**

Run:

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root .
```

Expected: Unity 프로젝트가 아니므로 종료 코드 `2`, `project-profile.conf` 신규 생성 없음.

- [x] **Step 5: 임시 Unity 프로젝트에서 종단 검증**

테스트 러너가 만든 MVVM 픽스처에 `.agents`를 복사하지 않고 `detect_project`와 진입점의 `--project-root`를 사용한다.

검증 순서:

```text
감지 → pending 프로필 생성 → 프로필 위반 warning → confirm → 같은 위반 error → redetect → candidate 생성 → 기존 confirmed 프로필 체크섬 유지
```

Expected: 모든 상태 전이와 종료 코드가 설계 문서와 일치.

- [x] **Step 6: `.agents` 외부 변경 금지 재검증**

Run:

```bash
bash .agents/tests/run-tests.sh --group readonly
```

Expected: 감지 전후 프로젝트 파일 체크섬 동일.

- [x] **Step 7: 설계 요구사항 누락 감사**

다음 항목을 설계서와 파일에 일대일로 대조한다.

```text
읽기 전용 감지
확정 프로필 보호
MVVM/MVP/MVC/Layered-Clean/Custom
Core와 Profile 분리
최적화 네 기법 유지
applicable/not_applicable/unknown
Bash/PowerShell
공백·한글 경로
공백과 한글이 함께 포함된 경로
종료 코드 0~4
외부 의존성 없음
Unity 프로젝트 자동 수정 없음
```

누락이 있으면 해당 Task의 파일과 테스트를 보완한 뒤 전체 검증을 다시 실행한다.

- [x] **Step 8: 문서 링크와 파일 참조 검사**

문서에 등장하는 `.agents/` 상대 경로를 추출하여 실제 파일 존재 여부를 확인한다. 템플릿 변수 `${source_root}`, `${test_root}`는 파일 경로 검증 대상에서 제외한다.

Expected: 깨진 실제 경로 `0`.

- [x] **Step 9: 기본 하네스 체크포인트**

이 Task까지의 체크박스를 실제 결과에 맞게 갱신하되, 전역 에이전트 도구 통합과 최종 재검증이 남아 있으므로 계획서를 아직 `completed`로 이동하지 않는다.

- [x] **Step 10: 최종 체크포인트**

최종 보고 내용:

```text
변경 파일 목록
Bash 테스트 통과 수
PowerShell 테스트 통과 수 또는 미검증 사유
문서 링크 검사 결과
Unity 프로젝트 파일 무변경 증거
에디터 참조 필요 버튼 목록: 없음
SerializeField 참조 목록: 없음
이벤트 구독 안내: 없음
잔여 위험과 수동 확인 항목
```

---

### Task 9: 전역 에이전트 도구 통합과 설치 안전장치

**Files:**
- Create: `.agents/config/agent-tooling.conf`
- Create: `.agents/scripts/setup/check-agent-tooling.sh`
- Create: `.agents/scripts/setup/check-agent-tooling.ps1`
- Create: `.agents/docs/onboarding/agent-tooling.md`
- Modify: `.agents/AGENTS.md`
- Modify: `.agents/ARCHITECTURE.md`
- Modify: `.agents/scripts/README.md`
- Modify: `.agents/tests/run-tests.sh`
- Modify: `.agents/tests/run-tests.ps1`
- Modify: `.agents/tests/README.md`

- [x] **Step 1: 설치 상태 계약 테스트 작성**

다음 상태를 독립 임시 `CODEX_HOME`과 사용자 홈 픽스처로 검증한다.

```text
세 도구 모두 설치·활성화
스킬 파일만 존재하고 플러그인 비활성화
플러그인 설정만 있고 실제 SKILL.md 누락
버전 폴더가 복수인 플러그인 캐시
CODEX_HOME에 공백·한글이 포함된 경우
상태 확인 모드에서 홈·전역 설정 무변경
```

Expected: Bash와 PowerShell이 각 도구에 대해 `installed`, `disabled`, `broken`, `missing`을 동일하게 출력한다.

- [x] **Step 2: 공통 도구 설정 계약 작성**

`agent-tooling.conf`는 다음 항목을 단일 출처로 관리한다.

```text
karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required
superpowers|superpowers|obra/superpowers|required
understand_anything|understand-anything|Egonex-AI/Understand-Anything|required
```

Understand-Anything은 `Lum1104/Understand-Anything`을 원작자 출처 별칭으로 문서화하고, 현재 설치본과 호환되는 `Egonex-AI/Understand-Anything` 계승본을 기본 설치 소스로 사용한다.

- [x] **Step 3: Bash 상태 확인 구현**

`check-agent-tooling.sh --check`는 다음 근거를 모두 확인한다.

```text
Codex CLI 존재
~/.codex/config.toml의 플러그인 enabled 상태
~/.codex/skills 또는 플러그인 캐시의 SKILL.md
~/.understand-anything/repo 또는 전역 understand 스킬 진입점
```

플러그인 캐시의 구체적 버전 경로를 하드코딩하지 않고, 설정 ID와 실제 스킬 진입점을 함께 검증한다. 상태 확인은 읽기 전용이며 누락 시 종료 코드 `1`을 반환한다.

- [x] **Step 4: 명시적 부트스트랩 모드 구현**

`--install-missing`을 사용한 경우에만 전역 설정과 네트워크를 변경한다. 일반 `initialize-harness`, 린트, CI에서는 이 모드를 암시적으로 호출하지 않는다.

```text
Karpathy Guidelines: Codex 글로벌 skill-installer 또는 확정된 로컬 설치 진입점
Superpowers: 공식 저장소를 임시 경로에 clone·검증한 뒤 CODEX_HOME으로 원자 이동하고 사용자 홈의 전역 스킬 디렉터리에 연결
Understand-Anything: 저장소를 로컬에 확인 가능하게 받은 뒤 install.sh codex 실행
```

원격 스크립트를 `curl | bash`로 즉시 실행하지 않는다. 설치는 실패한 도구에서 중단하고, 이미 작동하는 도구나 사용자 설정을 제거·하향·교체하지 않는다.

- [x] **Step 5: PowerShell 동등 구현**

PowerShell 5.1+에서 동일 설정 파일, 상태, 종료 코드, 설치 안전장치를 사용한다. Bash와 PowerShell은 도구 ID와 상태 출력 순서까지 동일해야 한다.

- [x] **Step 6: 에이전트 워크플로 문서화**

`.agents/AGENTS.md`와 온보딩 문서에 다음 적용 시점을 명시한다.

```text
모든 구현·리팩토링: karpathy-guidelines로 가정, 최소 변경, 검증 기준 고정
창의적 변경·버그 수정·완료 전: 해당 superpowers 스킬 필수 적용
초기 프로젝트 파악: understand
아키텍처 질문: understand-chat / understand-explain
변경 영향 검수: understand-diff
온보딩: understand-onboard
```

도구 누락은 Unity 코드 린트 실패로 간주하지 않고, 에이전트 사전 준비 경고와 정확한 복구 명령으로 보고한다.

- [x] **Step 7: Understand-Anything 실사용 구조 감사**

완성된 하네스를 임시 미러로 복제한 뒤 `understand --language ko`로 분석하여 설정→공유 로직→진입점→테스트→문서 관계를 검수한다. 지식 그래프 산출물은 원본 하네스에 저장하지 않는다.

Understand-Anything이 `.understandignore` 확인을 요구하는 시점에는 스킬 규칙에 따라 대상 내역을 제시하고 확인을 받은 후 계속한다.

- [x] **Step 8: 통합 검증**

```bash
bash .agents/tests/run-tests.sh --group tooling
bash .agents/scripts/setup/check-agent-tooling.sh --check
```

Expected: 픽스처 기반 설치 계약 테스트 실패 `0`, 현재 환경의 세 도구 상태 `installed`, 전역 파일 무변경. PowerShell이 있으면 동등 테스트도 실행한다.

---

### Task 10: 최종 통합 재검증과 계획 완료

**Files:**
- Modify: `.agents/tests/README.md`
- Modify: `.agents/docs/exec-plans/completed/2026-07-16-universal-unity-harness-plan.md`

- [x] **Step 1: 전체 테스트 재실행**

```bash
find .agents/scripts .agents/tests -name '*.sh' -type f -exec bash -n {} \;
bash .agents/tests/run-tests.sh --runtime bash
bash .agents/tests/run-tests.sh --group tooling
bash .agents/scripts/setup/check-agent-tooling.sh --check
```

Expected: Bash 실패 `0`, 세 도구 `installed`. PowerShell 런타임이 있으면 PowerShell 전체 테스트도 실패 `0`.

- [x] **Step 2: 산출물·문서·읽기 전용 경계 재감사**

Task 8의 누락 목록에 세 에이전트 도구 설정, Bash/PowerShell 동등성, 전역 설정 무변경, Understand-Anything 임시 미러 경계를 추가하여 재검증한다.

- [x] **Step 3: 최종 독립 코드 리뷰**

`superpowers:requesting-code-review`와 `karpathy-guidelines`를 적용하여 요구사항 누락, 과설계, 비관련 변경, 검증 사각지대를 독립 검수한다. Critical·Important 지적은 수정 후 재검수한다.

- [x] **Step 4: 계획 완료 처리**

모든 체크박스를 실제 결과에 맞게 갱신하고 `.agents/docs/exec-plans/completed/2026-07-16-universal-unity-harness-plan.md`로 이동한다. PowerShell 런타임 부재는 완료 차단이 아니며, 정적 검증 결과와 잔여 위험을 명시한다.

---

## 최종 검증 기록

- 검증일: 2026-07-16
- 안정화 스냅샷 인벤토리: `.agents` 파일 59개, `.agents` 외부 산출물 없음
- Bash 전체 계약 테스트: `통과 102 / 실패 0 / 건너뜀 1`
- 도구 통합 테스트: `통과 23 / 실패 0 / 건너뜀 79`
- 문서 계약 테스트: `통과 19 / 실패 0 / 건너뜀 83`
- PowerShell 동등성 계약: `통과 1 / 실패 0 / 건너뜀 102`
- Bash 문법 검사: 모든 `.sh` 파일 통과
- 현재 전역 도구 상태: `karpathy_guidelines`, `superpowers`, `understand_anything` 모두 `installed`
- 읽기 전용 도구 확인 전후 `$CODEX_HOME/config.toml` SHA-256: `362bda0d9109f90905e24a8512f6c00aa84bc46e2603f2c992219077406c19de`로 동일
- Superpowers 전역 보강: 엄격한 물리 경로 검사에서 기존 plugin cache 경로가 `CODEX_HOME` 밖으로 이탈한 것으로 판정되어, 기존 설정·캐시를 변경하지 않고 공식 저장소를 `$CODEX_HOME/superpowers`에 추가하고 사용자 전역 skills 링크를 연결했다. 이후 세 도구가 모두 `installed`임을 확인했다.
- PowerShell 실행 경계: 현재 호스트에 `powershell`과 `pwsh`가 없어 런타임 검증은 미실시했다. UTF-8 BOM, 금지 API, 계약 문자열, Bash 구현과의 정적 동등성 검사를 통과했으며 Windows PowerShell 5.1+ 실제 실행은 잔여 수동 검증 항목이다.
- Understand-Anything 구조 감사: 임시 미러의 파일 `61/61` 분석, 노드 `440`, 엣지 `408`, 레이어 `9`, 한국어 투어 `14`단계, 오류 `0`, 경고 `21`을 확인했다. 경고는 고립 문서·설정 노드와 그래프 밀도 정보이며 파일·노드 손실이나 dangling/self edge는 없었다.
- Understand-Anything 산출물 경계: 지식 그래프와 중간 산출물은 임시 감사 미러에만 유지했고 안정화 스냅샷에는 `.ua` 또는 `.understand-anything`을 포함하지 않았다.
- 독립 최종 리뷰: 초기 Important 2건과 재검수 Important 1건을 테스트 우선으로 수정했으며 최종 재검수 결과 `Critical 없음 / Important 없음 / Ready Yes`를 확인했다.

---

## 완료 기준

- [x] 모든 Task의 테스트 우선 순서를 지켰다.
- [x] Bash 전체 테스트가 통과했다.
- [x] PowerShell 전체 테스트가 통과했거나 런타임 부재 경계를 명확히 기록했다.
- [x] 확정 프로필을 재감지가 덮어쓰지 않는다.
- [x] `.agents` 외부 Unity 프로젝트 파일이 변경되지 않는다.
- [x] 공통 문서와 린터에 특정 아키텍처·패키지·렌더 파이프라인·소스 경로 강제가 남아 있지 않다.
- [x] 기존 최적화 기법 네 가지가 조건부 베이스 지식으로 유지된다.
- [x] Karpathy Guidelines, Superpowers, Understand-Anything의 전역 설치 상태를 재현 가능하게 검증하고 누락 시 명시적 설치 경로를 제공한다.
- [x] 구현·리뷰·최종 산출물 검수에 세 도구를 실제로 사용했다.
- [x] 설계 문서의 모든 수용 기준을 하나 이상의 자동 또는 정적 검증이 담당한다.

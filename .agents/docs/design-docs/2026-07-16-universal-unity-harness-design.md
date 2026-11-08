# 범용 Unity 하네스 설계 문서

> 파일명: `2026-07-16-universal-unity-harness-design.md`

---

## 개요

- **기능명**: 프로필 기반 범용 Unity 하네스
- **작성자**: 윤승종
- **작성일**: 2026-07-16
- **상태**: 리뷰 중

### 배경

현재 하네스는 `.agents` 내부에 문서와 검사 스크립트를 완결된 형태로 제공하지만, Unity 6.x, URP, MVVM, VContainer, UniTask, DOTween과 `Assets/Scripts` 경로를 사실상 고정한다. 이 구조는 해당 조합을 사용하는 프로젝트에는 유효하지만 다른 Unity 버전, 렌더 파이프라인, 아키텍처 또는 소스 구조에 적용하면 오탐과 검사 누락을 만들 수 있다.

### 목표

1. `.agents` 폴더를 Unity 프로젝트에 복사한 뒤 읽기 전용 감지로 프로젝트 프로필을 생성한다.
2. SOLID, Unity 안전성, 서드파티 보호, 승인 절차와 기본 성능 원칙은 모든 프로젝트에 공통 적용한다.
3. MVVM, MVP, MVC, Layered/Clean과 기술 스택 규칙은 감지·확정된 프로필에만 적용한다.
4. 기존 GPU 최적화 지식은 공통 베이스로 유지하되 사전 조건을 만족할 때만 적용 대상으로 권고한다.
5. macOS·Linux용 Bash와 Windows용 PowerShell에서 같은 프로필, 상태값, 종료 코드와 판정 결과를 사용한다.

### 비목표

- Unity 패키지를 설치하거나 제거하지 않는다.
- `ProjectSettings`, 씬, 프리팹, 소스코드를 자동 수정하지 않는다.
- 폴더명만으로 아키텍처를 확정하지 않는다.
- 감지 결과가 불명확할 때 MVVM, URP 또는 특정 패키지를 기본값으로 강제하지 않는다.
- Unity 컴파일, 플레이 모드 또는 빌드를 자동 실행하지 않는다.

---

## 핵심 설계 결정

### 공통 코어와 선택 프로필 분리

하네스 규칙은 다음 세 계층으로 분리한다.

1. **Core**: 모든 Unity 프로젝트에 적용되는 규칙
2. **Optimization Base**: 항상 제공하되 적용 가능성을 별도로 판정하는 최적화 지식
3. **Profiles**: 확정된 아키텍처와 기술 스택에만 적용되는 규칙

`AGENTS.md`는 짧은 진입점으로 유지하며, `project-profile.conf`를 먼저 읽고 Core와 선택된 Profile 문서로 라우팅한다. `ARCHITECTURE.md`는 특정 프로젝트의 MVVM 구조도가 아니라 범용 하네스의 계층, 프로필 선택 원리와 의존성 경계를 설명한다.

### 읽기 전용 자동 감지

초기화 스크립트가 읽는 대상은 Unity 프로젝트의 실제 파일로 제한한다.

- `ProjectSettings/ProjectVersion.txt`
- `ProjectSettings/GraphicsSettings.asset`
- `Packages/manifest.json`
- `Packages/packages-lock.json`
- `Assets` 아래의 `.cs`, `.asmdef`, 렌더 파이프라인 관련 `.asset`과 `.meta`

감지는 `.agents/config/`와 `.agents/reports/`에만 결과를 쓴다. Unity 프로젝트 파일은 변경하지 않는다.

### 안전한 설정 형식

`project-profile.conf`는 한 줄에 하나의 `key=value`를 저장하는 형식을 사용한다. Bash는 이 파일을 `source`하지 않으며, Bash와 PowerShell 모두 허용 키 목록과 값 열거형을 기준으로 직접 파싱한다.

반복 가능한 경로 값은 같은 키를 여러 줄 작성한다.

```text
profile_version=1
confirmation_status=pending
project_name=SampleGame
unity_version=6000.3.16f1
render_pipeline=urp
architecture=mvvm
source_root=Assets/_Game/Scripts
source_root=Assets/Shared/Scripts
test_root=Assets/_Game/Tests
dependency_injection=vcontainer
async_backend=unitask
tween_backend=dotween
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
```

허용되지 않은 키, 허용되지 않은 열거형 값, 중복될 수 없는 키의 중복은 구성 오류로 처리한다.

아키텍처·패키지처럼 실제 파일에서 확인할 수 있는 항목은 감지 결과를 사용한다. 작성자, 응답·로그 언어, 접두사와 문서화 수준처럼 프로젝트 파일만으로 확정할 수 없는 정책은 기존 베이스 규칙을 초기값으로 제안하고 보고서에서 사용자 확인 항목으로 표시한다.

---

## 디렉터리 구조

```text
.agents/
├── AGENTS.md
├── ARCHITECTURE.md
├── config/
│   ├── project-profile.example.conf
│   └── project-profile.conf
├── docs/
│   ├── coding-standards/
│   │   ├── core/
│   │   └── optimization/
│   ├── profiles/
│   │   ├── architecture/
│   │   ├── dependency-injection/
│   │   ├── async/
│   │   ├── tween/
│   │   └── rendering/
│   ├── design-docs/
│   ├── exec-plans/
│   ├── product-specs/
│   └── onboarding/
├── scripts/
│   ├── init/
│   ├── lint/
│   ├── ci/
│   └── shared/
└── reports/
    └── detection-report.md
```

### 주요 구성요소

| 구성요소 | 책임 | 의존성 |
|---|---|---|
| `AGENTS.md` | 에이전트 진입점과 문서 라우팅 | 확정 프로필 |
| `ARCHITECTURE.md` | 하네스 구조와 규칙 활성화 원리 설명 | Core, Profiles |
| 프로필 초기화기 | 실제 프로젝트 증거 수집과 후보 프로필 생성 | Unity 직렬화 파일, 패키지 매니페스트 |
| 프로필 파서 | 허용 키와 값 검증 | 프로필 스키마 |
| 공통 린터 | 안전성·성능·서드파티·기본 코딩 규칙 검사 | source root |
| 프로필 린터 | 확정된 아키텍처·기술 규칙 검사 | confirmed profile |
| 감지 보고서 | 근거, 신뢰도, 충돌, 미확정 항목 기록 | 감지 결과 |

---

## 프로필 모델

### 아키텍처 프로필

초기 지원 프로필은 `mvvm`, `mvp`, `mvc`, `layered_clean`, `custom`이다.

아키텍처 감지는 다음 증거를 함께 사용한다.

- 폴더와 네임스페이스 명명
- `View`, `ViewModel`, `Presenter`, `Controller`, `UseCase` 등 클래스 역할 접미사
- Unity `MonoBehaviour`와 Pure C# 클래스의 분리
- 어셈블리 정의 참조 방향
- `using`과 타입 참조로 확인 가능한 계층 간 의존 방향

복수 프로필의 강한 증거가 충돌하면 `custom`으로 폴백한다. `custom`에서는 특정 UI 아키텍처 위반을 차단하지 않고 Core 규칙만 강제한다.

### 기술 프로필

초기 기술 프로필은 다음 값을 지원한다.

- 의존성 주입: `vcontainer`, `zenject`, `custom`, `none`, `unknown`
- 비동기: `unitask`, `coroutine`, `task`, `mixed`, `unknown`
- 트윈: `dotween`, `leantween`, `custom`, `none`, `unknown`
- 렌더링: `urp`, `hdrp`, `builtin`, `custom`, `unknown`

패키지가 설치돼 있다는 사실과 프로젝트에서 실제 사용한다는 사실을 구분한다. 설치만 확인되면 감지 근거에는 포함하지만 단독으로 프로필을 확정하지 않는다.

---

## 감지 및 확정 흐름

1. 실행 위치에서 Unity 프로젝트 루트를 찾는다.
2. Unity 버전, 패키지, 렌더 파이프라인, 소스·테스트 루트를 수집한다.
3. 폴더, 네임스페이스, 타입 역할과 참조 방향으로 아키텍처 후보를 평가한다.
4. 항목별 결과를 `high`, `medium`, `low`, `unknown` 신뢰도로 분류한다.
5. 신규 프로필을 `pending` 상태로 생성한다.
6. 사람이 읽을 수 있는 감지 근거와 확인 항목을 보고서로 생성한다.
7. 사용자가 프로필을 확인하고 `confirmed` 상태로 전환한다.
8. 공통 린터는 항상 실행하고, 프로필 린터는 `confirmed` 이후 차단 규칙으로 실행한다.

`pending` 상태에서도 프로필 린터를 진단 모드로 실행할 수 있지만 발견 사항은 경고로만 보고한다.

### 기존 프로필 보호

확정된 `project-profile.conf`가 존재하면 자동 감지는 이를 덮어쓰지 않는다. 재감지 결과는 `project-profile.candidate.conf`와 비교 보고서로 생성한다. 명시적인 사용자 승인 없이 확정 프로필을 교체하지 않는다.

---

## 최적화 베이스

### 항상 적용하는 원칙

- 매 프레임 경로에서 불필요한 GC 할당, Boxing과 LINQ를 제한한다.
- 반복 생성·파괴 대상에는 풀링 가능성을 검토한다.
- 빈번한 조회와 컴포넌트 접근은 캐싱한다.
- 프로파일링 결과 없이 추측만으로 복잡한 최적화를 도입하지 않는다.
- Unity `Object` 파생 타입의 Fake Null 특성을 고려한다.

### 조건부 최적화 지식

다음 기법은 베이스 문서에 항상 포함하지만 자동 활성화하거나 필수 설정으로 강제하지 않는다.

- GPU Resident Drawer
- GPU Occlusion Culling
- STP 업스케일링
- Mesh LOD

각 기법은 `applicable`, `not_applicable`, `unknown` 상태로 평가한다. 판정에는 Unity 버전, 렌더 파이프라인, 타겟 환경과 필요한 프로젝트 설정 증거를 사용한다. 씬의 가림 구조나 실제 GPU 병목처럼 정적 파일만으로 확정할 수 없는 조건은 `unknown`으로 남기고 프로파일링 확인을 권고한다.

---

## 검사 정책

### 공통 검사

- Unity `Object` 파생 타입의 널 조건부 연산자 오용 의심
- 직렬화 필드 이름 변경 시 `FormerlySerializedAs` 검토
- 매 프레임 메서드의 할당, LINQ, Boxing 의심
- 서드파티·패키지 원본 수정 여부
- 설정된 소스 루트와 테스트 루트의 존재 여부
- 사용자 지정 네이밍·문서화 규칙

### 프로필 검사

- MVVM: View에서 Model 직접 참조 금지
- MVP: View와 Model의 직접 결합 및 Presenter 경계 검사
- MVC: View·Controller·Model 역할 경계 검사
- Layered/Clean: 안쪽 계층이 바깥쪽 계층에 의존하는 참조 검사
- VContainer: 등록 방식과 LifetimeScope 구성 규칙
- UniTask·DOTween·렌더링: 실제 활성 프로필에 해당하는 규칙만 검사

정규식만으로 확정할 수 없는 위반은 경고로 보고한다. 명확한 금지 패턴과 잘못된 프로필 구성만 실패를 발생시킨다.

### 제외 경계

기본 제외 대상은 `Library`, `Temp`, `Logs`, `obj`, `UserSettings`, `Packages`, `.git`, `.agents`와 감지된 서드파티·플러그인 루트다. 프로젝트가 자체적으로 관리하는 패키지나 플러그인은 프로필에서 예외를 해제할 수 있다.

---

## 크로스플랫폼 규약

- Bash와 PowerShell은 동일한 프로필 키와 열거형을 사용한다.
- 두 구현은 동일한 검사 ID, 심각도, 종료 코드를 출력한다.
- 경로 구분자는 내부 비교 전에 정규화한다.
- 공백과 한글이 포함된 경로를 지원한다.
- 외부 도구인 `jq`, Python, Node.js 설치를 요구하지 않는다.
- PowerShell이 없는 환경에서는 Bash 검증만 수행하고 미검증 경계를 명시한다.

### 종료 코드

| 코드 | 의미 |
|---:|---|
| 0 | 감지 또는 검사 완료, 차단 위반 없음 |
| 1 | 규칙 위반 발견 |
| 2 | Unity 프로젝트 루트를 찾지 못함 |
| 3 | 프로필 구성 오류 |
| 4 | 필수 입력 파일을 읽을 수 없음 |

---

## 오류 처리

- Unity 프로젝트가 아니면 프로필과 보고서를 생성하지 않는다.
- 필수 입력 파일 파싱 실패는 성공으로 위장하지 않는다.
- 일부 선택 정보가 없으면 전체 감지를 실패시키지 않고 해당 항목만 `unknown`으로 격리한다.
- 경로 후보가 여러 개면 모두 기록하고 소스 파일 수와 어셈블리 근거를 보고한다.
- 기존 확정 프로필은 자동으로 덮어쓰지 않는다.
- 프로필이 잘못되면 프로필 전용 검사를 실행하지 않고 구성 오류를 반환한다.
- Unity 프로젝트에 대한 패키지 설치, 설정 변경 또는 파일 이동을 수행하지 않는다.

---

## 문서와 템플릿 개편

- 설계·실행 계획·제품 스펙 템플릿에서 MVVM, VContainer, `Assets/Scripts`를 고정한 예시를 제거한다.
- 예시는 선택된 아키텍처와 `source_root`, `test_root`를 참조하도록 변경한다.
- 작성자, 로그 언어, UI 콜백 접두사와 리전 사용 정책은 프로필 설정으로 이동한다.
- 기존 최적화 설명은 보존하되 적용 전제, 검증 방법과 비적용 조건을 함께 제시한다.
- 온보딩 문서는 `초기화 → 보고서 검토 → 프로필 확정 → 검사 실행` 순서로 통일한다.

---

## 테스트 설계

### 정적 검증

- 모든 Bash 스크립트에 `bash -n`을 실행한다.
- PowerShell 사용 가능 환경에서는 파서로 모든 `.ps1` 문법을 검사한다.
- 문서 링크와 상대 경로가 실제 파일을 가리키는지 검사한다.
- 고정된 `Assets/Scripts`, MVVM, VContainer, URP 전제가 Core 문서나 공통 린터에 남아 있지 않은지 검색한다.

### 감지 픽스처

임시 디렉터리에 최소 Unity 프로젝트 픽스처를 구성한다.

1. MVVM + VContainer + UniTask + URP
2. MVP + Built-in + Coroutine
3. MVC + HDRP
4. Layered/Clean + Custom DI
5. 아키텍처 충돌로 `custom`이 되어야 하는 프로젝트
6. Unity 프로젝트가 아닌 디렉터리
7. 공백과 한글이 포함된 경로
8. 기존 확정 프로필이 있는 재감지 상황

각 픽스처에서 Bash와 PowerShell의 정규화된 프로필과 종료 코드가 같아야 한다.

### 린터 픽스처

- 명확한 위반과 정상 코드의 쌍을 규칙별로 제공한다.
- `pending`에서는 프로필 위반이 경고인지 확인한다.
- `confirmed`에서는 같은 위반이 차단되는지 확인한다.
- `custom`에서는 특정 아키텍처 규칙이 강제되지 않는지 확인한다.
- 제외 디렉터리의 코드가 검사 결과를 오염시키지 않는지 확인한다.

### 변경 금지 검증

감지 전후에 `.agents` 외부 파일 목록과 체크섬을 비교하여 Unity 프로젝트 파일이 변경되지 않았음을 검증한다.

---

## 수용 기준

- [ ] Unity 프로젝트에서 버전, 렌더 파이프라인, 패키지, 소스·테스트 루트를 읽기 전용으로 감지한다.
- [ ] MVVM, MVP, MVC, Layered/Clean을 구분하고 충돌 시 `custom`으로 폴백한다.
- [ ] 공통 린터가 특정 소스 경로와 기술 스택을 가정하지 않는다.
- [ ] 최적화 베이스 문서가 유지되고 조건부 기법은 적용 가능 상태를 구분한다.
- [ ] 확정 프로필을 자동으로 덮어쓰지 않는다.
- [ ] Bash와 PowerShell이 동일한 프로필 스키마와 종료 코드 규약을 따른다.
- [ ] 공백과 한글이 포함된 경로에서 동작한다.
- [ ] 감지 전후 `.agents` 외부의 프로젝트 파일이 변경되지 않는다.
- [ ] 기존 문서와 템플릿에서 하드코딩된 MVVM, VContainer, URP, `Assets/Scripts` 전제가 제거된다.
- [ ] 자동 검증이 실패하면 원인과 미검증 경계를 명확히 보고한다.

---

## 구현 경계

이번 작업은 기존 `.agents` 패키지의 문서, 템플릿, 프로필 설정과 검사·초기화 스크립트만 변경한다. Unity 프로젝트 소스, 패키지와 설정은 범위 밖이다.

현재 대상 폴더는 Git 저장소가 아니므로 설계 문서와 이후 구현 변경을 커밋하는 단계는 수행하지 않는다.

---

## 변경 이력

| 날짜 | 작성자 | 변경 내용 |
|---|---|---|
| 2026-07-16 | 윤승종 | 프로필 기반 범용 Unity 하네스 설계 초안 작성 |

# 프로필 기반 기술 스택 안내

기술 스택의 권위는 `.agents/config/project-profile.conf`입니다. 패키지 설치 흔적과 실제 코드 사용이 다를 수 있으므로 감지 보고서를 검토한 뒤 선택을 확정합니다.

## 프로필 준비 흐름

### 1. 초기화

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot .
```

### 2. 감지 보고서 검토

`.agents/reports/detection-report.md`에서 패키지 근거와 코드 사용 근거를 구분해 확인합니다. 충돌하거나 증거가 부족한 값은 `unknown` 또는 사용자가 정의한 custom 분기로 유지합니다.

### 3. 프로필 확정

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root . --confirm
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot . -Confirm
```

### 4. 검사 명령 준비

다음 검사 명령은 사용자가 현재 요청한 경우에만 실행하는 예시입니다. 요청하지 않았다면 `not_run`으로 기록하며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거로 사용하지 않습니다.

```bash
bash .agents/scripts/lint/check-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/lint/check-harness.ps1 -ProjectRoot .
```

## 기술 프로필 라우팅

| 프로필 키 | 지원 분기 예 | 규칙 문서 |
|-----------|--------------|-----------|
| `architecture` | mvvm, mvp, mvc, layered_clean, custom | [아키텍처](../profiles/architecture/) |
| `dependency_injection` | vcontainer, zenject, custom, none, unknown | [DI](../profiles/dependency-injection.md) |
| `async_backend` | unitask, coroutine, task, mixed, unknown | [비동기](../profiles/async.md) |
| `tween_backend` | dotween, leantween, custom, none, unknown | [트윈](../profiles/tween.md) |
| `render_pipeline` | urp, hdrp, builtin, custom, unknown | [렌더링](../profiles/rendering.md) |

이 표는 지원 가능한 조건부 분기이며 설치 목록이 아닙니다. `confirmed` 값의 문서만 구현 규칙으로 활성화합니다.

## 선택별 공통 확인

- DI: `none`이면 Composition Root에서 명시적으로 조립하고 수명 소유자를 기록합니다.
- 비동기: 작업 소유, 취소, 예외 관찰, Unity 객체 수명 확인을 기록합니다.
- 트윈: 생성 주체와 종료·해제 책임을 기록합니다.
- 렌더링: 파이프라인과 플랫폼 호환성을 확인한 뒤 설정합니다.
- 경로: `${source_root}`와 `${test_root}`를 사용하며 값이 없다고 관습 경로를 추정하지 않습니다.

## Optimization Base

[렌더링 최적화 기법](../coding-standards/optimization/rendering-techniques.md)은 선택 기술과 별도로 적용 의무를 확인하고, 렌더링·최적화 영향이 있을 때 분석·판정 전에 읽습니다. 상세 읽기 시점은 [AGENTS 읽기 라우팅](../../AGENTS.md)을 따르며 미로딩은 정책 면제가 아닙니다. 각 항목의 적용 상태를 확인하고 Profiler 측정 근거와 롤백 조건이 있을 때만 변경합니다.

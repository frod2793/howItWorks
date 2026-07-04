# 프로젝트명 — AI 에이전트 가이드

> 이 파일은 AI 에이전트가 프로젝트에서 **가장 먼저** 읽어야 하는 진입점입니다.
> ~100줄 이내를 유지하며, 세부 규칙은 하위 문서를 참조하십시오.

---

## 프로젝트 개요

- **프로젝트명**: HowItWorks
- **장르/유형**: 스토리텔링 비주얼 노벨 / 루프 기반 텍스트 어드벤처
- **타겟 플랫폼**: PC & Mobile (Multi-platform)
- **Unity 버전**: 6000.3.18f1 (Unity 6)
- **렌더 파이프라인**: URP

## 기술 스택

| 영역 | 기술 | 비고 |
|------|------|------|
| DI 컨테이너 | VContainer | LifetimeScope 기반, 씬 당 1개 |
| UI 아키텍처 | MVVM | Model → ViewModel → View 단방향 |
| 비동기 처리 | UniTask | 코루틴 사용 금지 |
| 트윈 | DOTween | — |
| 렌더링 | URP | GPU Resident Drawer 활성화 |

## 절대 금지 사항 (Critical)

1. ❌ **싱글톤(Singleton) 패턴** 사용 금지
2. ❌ **View → Model 직접 참조** 금지 (반드시 ViewModel 경유)
3. ❌ **UnityEngine.Object에 `?.`, `??` 연산자** 사용 금지
4. ❌ **Update 루프 내 `new`, Boxing, LINQ** 사용 금지
5. ❌ **코루틴** 사용 금지 (UniTask 사용)
6. ❌ **AI 에이전트를 작성자로 표기** 금지 (작성자: 윤승종)

## 문서 맵 (Document Map)

에이전트는 필요에 따라 아래 문서를 **점진적으로** 로딩하십시오.
3000줄짜리 문서를 한 번에 읽지 말고, 필요한 것만 찾아가십시오.

| 문서 | 경로 | 용도 |
|------|------|------|
| 🏗️ 전체 아키텍처 | `ARCHITECTURE.md` | 레이어 구조, 네임스페이스, 의존성 그래프 |
| 📝 네이밍 규칙 | `docs/coding-standards/naming-conventions.md` | m_, PascalCase, func_ 등 |
| 🧱 아키텍처 규칙 | `docs/coding-standards/architecture-rules.md` | MVVM, VContainer, SOLID, DI |
| ⚡ 성능 규칙 | `docs/coding-standards/performance-rules.md` | Zero Alloc, UniTask, DOTween |
| 🛡️ 안전성 규칙 | `docs/coding-standards/safety-rules.md` | Fake Null, 직렬화 안전성 |
| 🎮 Unity 특화 | `docs/coding-standards/unity-specific.md` | URP, GPU Resident Drawer, STP |
| 📐 설계 문서 | `docs/design-docs/` | 기능별 설계 문서 |
| 📋 실행 계획 | `docs/exec-plans/active/` | 진행 중인 작업 계획 |
| 📦 제품 스펙 | `docs/product-specs/` | 기능 요구사항 정의 |

## 에이전트 온보딩

처음 이 프로젝트에 투입된 에이전트는 `docs/onboarding/agent-quickstart.md`를 읽으십시오.

## 소스코드 구조 (요약)

```
Assets/
├── Scripts/
│   ├── Core/               ← 핵심 시스템 (DI 설정, 이벤트 버스, 씬 로더)
│   ├── Models/             ← 순수 데이터 클래스 (POCO, MonoBehaviour 금지)
│   ├── ViewModels/         ← UI 상태 가공 및 Command (순수 C#)
│   ├── Views/              ← MonoBehaviour (데이터 바인딩 + 입력 전달만)
│   ├── Services/           ← 비즈니스 로직 서비스 (순수 C#)
│   ├── DTOs/               ← 데이터 전송 객체 (씬 전환용)
│   └── Utilities/          ← 헬퍼, 확장 메서드
├── Scenes/
├── Prefabs/
└── ScriptableObjects/
```

## 검증 스크립트

아키텍처 위반을 자동 감지하는 스크립트는 `.agents/scripts/` 디렉토리를 참조하십시오.

```bash
# 아키텍처 규칙 검증
bash .agents/scripts/lint/check-architecture.sh

# 커밋 전 전체 검증
bash .agents/scripts/ci/pre-commit-checks.sh
```

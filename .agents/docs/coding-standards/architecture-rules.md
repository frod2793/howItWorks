# 아키텍처 규칙 — 호환 인덱스

> 기존 링크를 깨지 않기 위한 호환 인덱스입니다. 실제 강제 규칙은 Core와 `project-profile.conf`가 선택한 프로필 문서를 따릅니다.

## 새 문서 라우팅

| 기존 내용 | 새 위치 |
|---|---|
| SOLID, Pure C#, No Singleton, 인터페이스 의존 | [공통 아키텍처 원칙](core/architecture-principles.md) |
| DTO 씬 전환, 디자인 패턴 선택 기준 | [공통 아키텍처 원칙](core/architecture-principles.md) |
| Model·ViewModel·View 책임, 단방향 흐름과 예제 | [MVVM 프로필](../profiles/architecture/mvvm.md) |
| Presenter·Controller·Layered/Clean·Custom 경계 | [아키텍처 프로필](../profiles/architecture/) |
| LifetimeScope, View·Service·EntryPoint 등록 예제 | [의존성 주입 프로필](../profiles/dependency-injection.md) |
| 이름, 한글 로그, XML 문서 예제 | [네이밍·문서화 공통 규칙](core/naming-and-documentation.md) |

## 호환 안내

- 기존 MVVM과 VContainer 예시는 삭제된 것이 아니라 각각 선택 프로필 문서로 이동했습니다.
- 아키텍처 프로필이 `pending`이면 프로필 전용 발견 사항은 경고이며, `confirmed` 이후 명확한 위반만 차단합니다.
- 프로젝트가 다른 구조를 사용하면 해당 프로필을 선택합니다. 특정 UI 구조나 DI 제품을 이 호환 경로만 보고 강제하지 않습니다.

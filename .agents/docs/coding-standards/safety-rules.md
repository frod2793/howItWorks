# 안전성 규칙 — 호환 인덱스

> 기존 경로를 유지하는 호환 인덱스입니다. Unity 안전성은 Core로, 외부 의존 경계는 공통 아키텍처 원칙으로 이동했습니다.

## 새 문서 라우팅

| 기존 내용 | 새 위치 |
|---|---|
| Fake Null과 명시적 Unity null 비교 | [Unity 안전성 공통 규칙](core/unity-safety.md) |
| `FormerlySerializedAs`와 직렬화 변경 | [Unity 안전성 공통 규칙](core/unity-safety.md) |
| `UnityEvent`, C# 이벤트 구독·해제 | [Unity 안전성 공통 규칙](core/unity-safety.md) |
| Wrapper, Adapter, 확장 메서드와 원본 보호 | [공통 아키텍처 원칙](core/architecture-principles.md) |

## 호환 안내

기존 Fake Null, 필드명 변경, 오디오 Adapter와 DOTween 확장 예시의 의도는 새 문서의 안전 경계와 프로젝트 소유 Wrapper 원칙으로 보존했습니다. 서드파티 제품별 구현 예시는 확정 프로필과 설치 버전을 우선합니다.


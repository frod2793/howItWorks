# 성능 규칙 — 호환 인덱스

> 기존 경로를 유지하는 호환 인덱스입니다. 공통 런타임 원칙과 선택 기술 규칙을 분리했습니다.

## 새 문서 라우팅

| 기존 내용 | 새 위치 |
|---|---|
| 프레임 루프 할당·LINQ·Boxing, `for` 예제 | [런타임 성능 공통 규칙](core/runtime-performance.md) |
| 캐싱, Object Pool과 측정 우선 | [런타임 성능 공통 규칙](core/runtime-performance.md) |
| UniTask 예제, Coroutine·Task·Mixed 분기 | [비동기 프로필](../profiles/async.md) |
| DOTween 예제와 파괴 시 Kill, 다른 트윈 분기 | [트윈 프로필](../profiles/tween.md) |
| GPU 기반 네 가지 조건부 기법 | [조건부 렌더링 최적화](optimization/rendering-techniques.md) |

## 호환 안내

기존 UniTask와 DOTween 예시는 해당 백엔드가 확정된 프로젝트의 선택 예시로 이동했습니다. 다른 비동기·트윈 프로필에는 제품별 금지를 적용하지 않습니다.

# Unity 특화 규칙 — 호환 인덱스

> 기존 경로를 유지하는 호환 인덱스입니다. 렌더링 기술은 파이프라인 고정 규칙이 아니라 조건부 최적화 지식으로 이동했습니다.

## 새 문서 라우팅

| 기존 내용 | 새 위치 |
|---|---|
| GPU Resident Drawer 원리·설정·검증·롤백 | [조건부 렌더링 최적화](optimization/rendering-techniques.md) |
| GPU Occlusion Culling 투패스·Hi-Z·적용 기준 | [조건부 렌더링 최적화](optimization/rendering-techniques.md) |
| STP, TAA, Render Scale, Motion Vectors 디버깅 | [조건부 렌더링 최적화](optimization/rendering-techniques.md) |
| Mesh LOD, QEM, 버전별 기본 LOD·cross-fade 조건 | [조건부 렌더링 최적화](optimization/rendering-techniques.md) |
| URP·HDRP·Built-in·Custom·Unknown 분기 | [렌더링 프로필](../profiles/rendering.md) |

## 호환 안내

기존 네 기법의 목적과 메커니즘, 설정 예시, 효과·비효과 조건과 디버깅 정보는 새 최적화 문서에 보존했습니다. 현재 Unity 버전과 렌더 파이프라인의 지원 여부가 확인되지 않으면 활성화를 강제하지 않습니다.

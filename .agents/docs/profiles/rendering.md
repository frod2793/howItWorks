# 렌더링 프로필

> `render_pipeline` 값은 패키지 설치, Graphics 설정과 실제 렌더 파이프라인 에셋 근거를 함께 사용합니다. 감지된 파이프라인은 기능 지원의 첫 조건일 뿐 최적화 활성화 명령이 아닙니다.

## `urp`

Universal Render Pipeline 에셋의 실제 연결이 확인된 경우입니다. Renderer, Camera, Shader와 Renderer Feature의 현재 프로젝트 설정을 기준으로 검사합니다. GPU Resident Drawer, STP, GPU Occlusion Culling, Mesh LOD는 버전·플랫폼·씬 조건을 각각 판정한 뒤에만 권고합니다.

## `hdrp`

High Definition Render Pipeline 에셋의 실제 연결이 확인된 경우입니다. HDRP 전용 설정과 셰이더 경계를 따르며 URP Inspector 경로를 적용하지 않습니다. 조건부 최적화 기법은 현재 HDRP 버전에서 기능이 확인된 항목만 평가합니다.

## `builtin`

Scriptable Render Pipeline 에셋 연결 없이 Built-in 경로를 사용하는 근거가 확인된 경우입니다. SRP 전용 설정을 강제하지 않으며 Built-in에서 제공되지 않는 기능은 `not_applicable`로 판정할 수 있습니다.

## `custom`

프로젝트 소유 SRP 또는 사전 정의 분기에 맞지 않는 렌더 구조입니다. 렌더 파이프라인 에셋, 카메라·셰이더 계약, 지원 플랫폼과 디버깅 도구를 프로젝트 문서에 기록합니다. 이름이 비슷하다는 이유로 다른 파이프라인 절차를 적용하지 않습니다.

## `unknown`

Graphics 설정을 읽을 수 없거나 복수 에셋 충돌, 동적 선택 등으로 확정할 수 없는 상태입니다. 파이프라인별 설정 변경을 금지하고 감지 보고서에 필요한 확인 항목을 남깁니다.

네 기법의 `applicable`, `not_applicable`, `unknown` 판정과 롤백 절차는 [조건부 렌더링 최적화 베이스](../coding-standards/optimization/rendering-techniques.md)를 따릅니다.


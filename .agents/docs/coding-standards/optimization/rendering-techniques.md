# 조건부 렌더링 최적화 베이스

> 네 기법은 지식 베이스로 항상 제공하지만 자동 활성화하거나 필수 설정으로 강제하지 않습니다. Unity 버전, [렌더링 프로필](../../profiles/rendering.md), 하드웨어와 씬 병목을 확인한 뒤 각 프로필 값을 `applicable`, `not_applicable`, `unknown` 중 하나로 기록합니다.

## 1. GPU Resident Drawer

#### 목적

동일하거나 호환되는 렌더 상태를 가진 오브젝트가 많은 씬에서 CPU의 드로우 제출 비용과 드로우콜 수를 줄입니다. 기존 베이스의 “수만 개에서 수백 개”, 4K 마을 씬의 약 30fps에서 60fps 사례는 특정 테스트 사례이며 프로젝트 성능을 보장하지 않습니다.

#### 작동 원리

렌더 데이터를 GPU 메모리에 상주시켜 CPU의 오브젝트별 명령 생성 부담을 낮춥니다. 기존 베이스는 BRG(Batch Renderer Group) 자동화, 컴퓨트 셰이더 기반 인스턴스 처리와 동일 필터 설정의 묶음 처리를 핵심 메커니즘으로 설명합니다.

#### 적용 사전 조건

- 현재 Unity 버전과 선택된 렌더 파이프라인에서 기능을 제공하는지 Editor와 프로젝트 문서로 확인합니다.
- 컴퓨트 셰이더와 필요한 플랫폼 기능을 타겟 기기가 지원해야 합니다.
- 기존 베이스의 URP 경로에서는 Graphics의 `GPU Resident Drawer=Instanced Drawing`, Shader Stripping의 `Batch Renderer Group=Keep`, Player Settings의 Static Batching 비활성화를 함께 검토합니다.
- 위 설정명과 위치는 버전에 따라 달라질 수 있으므로 현재 Inspector에서 확인합니다.

#### `applicable` 판정

지원 버전·파이프라인·플랫폼이 확인되고, 반복 렌더러가 많으며 CPU 렌더 제출이 실제 병목이고, 시험 설정에서 드로우 제출 시간과 프레임 타임이 개선되면 선택합니다.

#### `not_applicable` 판정

기능 미지원 버전·파이프라인·플랫폼이거나, 씬에 배치 가능한 반복 렌더러가 적거나, 병목이 GPU 셰이딩·대역폭 등 다른 구간이고 시험 결과 이득이 없으면 선택합니다.

#### `unknown` 판정

정적 파일에서 설정 존재만 확인됐거나 목표 기기 측정, 실제 활성 여부, 셰이더 호환성 또는 CPU 병목 근거가 없으면 유지합니다.

#### 프로파일링 검증

대표 씬에서 CPU Render Thread/Main Thread, Batches·SetPass, GPU 프레임 시간과 메모리를 활성화 전후 동일 조건으로 비교합니다. Frame Debugger와 플랫폼 GPU 도구로 배치가 실제 구성됐는지 확인합니다.

#### 부작용과 롤백

Static Batching과 셰이더 스트리핑 정책 변화, 호환되지 않는 머티리얼·셰이더, GPU 메모리 증가를 점검합니다. 회귀가 있으면 변경한 Drawer, BRG 보존과 Static Batching 설정을 기록된 이전 값으로 되돌리고 프로필을 `unknown` 또는 `not_applicable`로 갱신합니다.

## 2. GPU Occlusion Culling

#### 목적

카메라 절두체 안에 있지만 건물 등 큰 물체에 가려진 렌더러를 GPU에서 제외하여 불필요한 렌더링 비용을 줄입니다.

#### 작동 원리

기존 베이스는 이전 프레임 깊이로 1차 판정하고 현재 프레임 깊이로 보정하는 투패스 방식, 메시를 감싸는 바운딩 스피어, 단계적으로 축소한 Hi-Z 깊이 피라미드를 설명합니다. 실제 내부 구현은 Unity 버전과 파이프라인에 따라 확인해야 합니다.

#### 적용 사전 조건

- 현재 Unity 버전, 렌더 파이프라인과 타겟 GPU에서 해당 기능과 필요한 깊이 처리를 지원해야 합니다.
- URP(Unity 6.0 공식 절차)에서는 Graphics의 URP 탭 Render Graph 절에서 Compatibility Mode(Render Graph Disabled)를 끄고, GPU Resident Drawer를 활성화한 뒤, 활성 Universal Renderer에서 GPU Occlusion을 켭니다. 다른 버전은 해당 버전 문서로 확인합니다: https://docs.unity3d.com/6000.0/Documentation/Manual/urp/gpu-culling.html
- 건물 사이 이동처럼 큰 차폐물이 많고, 가려지는 렌더러가 충분한 대표 씬이 필요합니다.
- 깊이·투패스 비용을 감당할 GPU 여유와 비교 가능한 기준 캡처를 준비합니다.

#### `applicable` 판정

지원 조건이 확인되고, 차폐가 많은 씬에서 컬링된 렌더러 수 증가와 GPU 프레임 시간 감소가 반복 측정되며 시각 오류가 없으면 선택합니다.

#### `not_applicable` 판정

탁 트인 지형처럼 차폐가 적어 투패스 오버헤드가 이득보다 크거나, 가로등·창살처럼 얇고 긴 물체의 큰 바운딩 스피어 때문에 효율이 낮거나, 기능이 지원되지 않으면 선택합니다.

#### `unknown` 판정

씬 차폐 구조, 목표 카메라 경로, 실제 GPU 병목과 타겟 기기 측정이 없으면 정적 설정만으로 확정하지 않습니다.

#### 프로파일링 검증

차폐가 많은 구간과 열린 구간을 각각 캡처해 GPU 시간, 렌더러·삼각형 수, 깊이·오클루전 패스 비용과 프레임 안정성을 비교합니다. 카메라 급회전과 빠른 이동에서 잘못된 컬링이 없는지 확인합니다.

#### 부작용과 롤백

추가 깊이 패스 비용, 일시적 팝인, 얇은 메시의 비효율과 플랫폼별 편차가 생길 수 있습니다. 이득이 없거나 시각 회귀가 있으면 오클루전 기능을 이전 설정으로 되돌리고 씬·플랫폼별 판정을 분리합니다.

## 3. STP (Spatial-Temporal Post-processing)

#### 목적

내부 해상도를 낮춰 렌더링한 뒤 시간(Temporal)과 공간(Spatial) 정보를 사용해 출력 해상도로 업스케일하여 GPU 비용과 화질의 균형을 맞춥니다. 기존 베이스의 발전 흐름은 `SSAA → TAA → TAAU → STP`입니다.

#### 작동 원리

이전 프레임 히스토리, 모션 벡터와 현재 프레임 주변 픽셀 관계를 결합해 고해상도 출력을 재구성합니다. 기존 베이스의 플랫폼별 자동 최적화 설명에 따르면 고성능 PC·콘솔은 추가 보정으로 화질을 높이고, 저사양 기기는 무거운 보정 일부를 생략할 수 있습니다. 실제 분기는 현재 Unity 버전과 타겟 기기에서 확인합니다.

#### 적용 사전 조건

- 현재 Unity 버전과 렌더 파이프라인에서 STP가 노출되어야 합니다.
- 기존 베이스의 URP 경로에서는 Upscale Filter를 STP, Render Scale을 1.0 미만(예: 0.5~0.75), 카메라 AA를 TAA로 설정합니다.
- 움직이는 오브젝트와 커스텀 셰이더가 올바른 Motion Vectors 패스를 제공해야 합니다.
- Screen Space - Camera UI는 업스케일 대상이 될 수 있으므로 텍스트 품질을 확인합니다. Overlay UI는 일반적으로 이후 합성되지만 현재 파이프라인에서 검증합니다.

#### `applicable` 판정

지원 조건과 모션 벡터가 확인되고, 목표 해상도·기기에서 허용 가능한 화질을 유지하면서 GPU 프레임 시간이 개선되면 선택합니다.

#### `not_applicable` 판정

지원되지 않는 파이프라인, TAA 또는 모션 벡터를 사용할 수 없는 프로젝트, 고스팅·흐림·깜빡임이 품질 기준을 넘거나 업스케일 패스 비용이 더 크면 선택합니다. Render Scale 1.0 이상처럼 STP 이득을 사용하지 않는 설정도 활성 대상으로 강제하지 않습니다.

#### `unknown` 판정

커스텀 셰이더의 `MotionVectors`, 실제 카메라 AA, Render Scale, 목표 기기 품질·성능 캡처가 확인되지 않으면 유지합니다.

#### 프로파일링 검증

Frame Debugger와 GPU Profiler에서 STP Upscale, History Copy 등 관련 패스 시간을 확인합니다. 0.5, 0.75 등 후보 Render Scale을 대표 동작에서 비교하고 고스팅, 텍스트 선명도, 서브 픽셀 깜빡임을 영상으로 검수합니다. 저사양 모바일에서 관련 패스가 병목이면 Render Scale을 상향하여 재검증하고, 이득이 없으면 STP를 비활성화합니다.

#### 부작용과 롤백

모션 벡터 누락 시 고스팅, 낮은 Render Scale에서 흐림, 가는 선·철망의 깜빡임, Camera UI 선명도 저하가 생길 수 있습니다. 서브 픽셀 디테일의 Flickering은 알파 클리핑 대신 알파 블렌딩을 시험하되 정렬·오버드로우 부작용도 함께 측정합니다. Render Scale을 올리거나 TAA 품질을 조절한 뒤에도 기준을 못 맞추면 기존 Upscale Filter와 AA 설정으로 되돌립니다.

## 4. Mesh LOD

#### 목적

Unity 6.2 이상에서 제공되는 것으로 기존 베이스에 기록된 자동 메시 LOD를 활용해, 거리별 메시를 따로 보관하는 방식보다 정점 데이터 중복을 줄이면서 원거리 정점 처리량을 낮춥니다.

#### 작동 원리

기존 베이스는 QEM(Quadric Error Metrics) 기반 단순화로 인접 정점을 병합하고, 하나의 정점 버퍼를 공유하면서 LOD별 인덱스 버퍼를 교체하는 구조로 설명합니다. 실제 생성 결과와 메모리 공유 방식은 현재 Unity 버전에서 확인합니다.

#### 적용 사전 조건

- `unity_version`이 기능을 제공하는 버전인지 확인합니다. 기존 기준은 Unity 6.2+입니다.
- Unity 6.3(6000.3) [공식 Introduction](https://docs.unity3d.com/6000.3/Documentation/Manual/lod/mesh-lod-introduction.html)에서 기본 Mesh LOD와 LOD cross-fade 조건을 분리합니다. GPU Resident Drawer 활성화는 Mesh LOD cross-fade의 조건이며 기본 Mesh LOD의 일괄 필수 조건으로 쓰지 않습니다.
- cross-fade를 사용할 때는 GPU Resident Drawer 지원·활성화를 확인합니다. 다른 Unity 버전에서 미확인 조건은 `unknown`이며, 6.3 확인 결과를 모든 6.2+에 일반화하거나 프로젝트 버전을 자동 승격하지 않습니다.
- 모델 Importer에 Mesh LOD 생성 기능이 보여야 하며, 원본 메시와 품질 검수 환경이 필요합니다.
- Generate Mesh LOD, Limit LOD와 Quality/Inspector 바이어스는 시험 에셋에서 먼저 조정합니다.

#### `applicable` 판정

현재 버전의 기본 Mesh LOD 지원과, cross-fade를 사용할 경우 해당 GPU Resident Drawer 조건이 확인되고, 바위·나무 수관처럼 덩어리 형태의 반복 에셋에서 허용 품질을 유지하며 메모리 또는 GPU 지표가 개선되면 선택합니다.

#### `not_applicable` 판정

Unity 버전이나 필수 렌더링 조건이 맞지 않거나, 길쭉하고 각진 메시·중요 영웅 에셋에서 자동 결과가 품질 기준을 못 맞추거나, 기존 수동 LOD가 더 효율적이면 선택합니다.

#### `unknown` 판정

현재 버전의 Importer 기능과 지원 조건, cross-fade 사용 시 GPU Resident Drawer 활성 상태, 타겟 에셋 형태, 생성 결과와 목표 기기 측정이 확인되지 않으면 유지합니다.

#### 프로파일링 검증

LOD 단계별 정점·삼각형 수, 전환 거리, 팝핑, 메모리와 GPU 프레임 시간을 수동 LOD 또는 LOD 없음 기준과 비교합니다. 카메라 속도·FOV·해상도별 전환 품질도 확인합니다.

#### 부작용과 롤백

자동 단순화로 실루엣·UV·셰이딩 품질이 저하되거나 전환 팝핑이 생길 수 있습니다. 같은 에셋에 Mesh LOD와 LOD Group을 병행하지 않고 에셋 단위로 택일하며, 실패 시 생성된 Mesh LOD 설정을 제거한 뒤 기존 LOD Group 또는 원본 메시 경로로 복구합니다.

> 기존 베이스에 기록된 참고 출처: https://www.youtube.com/watch?v=wvXzRverJIY

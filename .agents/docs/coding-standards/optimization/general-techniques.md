# 일반 최적화 기법 베이스

> 이 문서는 렌더링 조건부 기법 외의 공통 최적화 지식 베이스입니다. 모든 기법은 프로파일링 증거를 확인한 뒤 적용하며, 측정 없이 코드 모양이나 설정만 보고 비용을 단정하지 않습니다. 적용 전후 수치와 롤백 조건 없이 설정을 변경하지 않습니다. GPU Resident Drawer, GPU Occlusion Culling, STP와 Mesh LOD는 [조건부 렌더링 최적화 베이스](rendering-techniques.md)를 따릅니다.

## 프로파일링 우선 워크플로

- 성능 Task의 원인 분리·설정 변경 전 [Unity Performance Tuning Bible 적용 가이드](performance-tuning-bible.md)의 측정 절과 관련 분야를 읽습니다. 책은 스마트폰·Unity 2020.3.24f1 기준이므로 현재 버전·패키지·플랫폼 지원을 재확인합니다.
- 최적화 전에 대상·최저 보장 기기, OS·Unity·패키지·렌더 파이프라인·빌드 설정과 프레임 예산(예: 60fps ≈ 16.67ms), 메모리·전환시간·발열·배터리 예산을 정합니다. 관련 Task는 [실행 계획 템플릿](../../exec-plans/_TEMPLATE.md)의 선택형 성능 측정 카드로 조건과 결과를 남깁니다.
- 실제 측정·빌드·기기 실행은 현재 사용자 승인 범위에서만 수행합니다. 미승인 측정은 `not_run`, 지원 조건이나 비교 근거 미확인은 `unknown`이며 문서 반영을 성능 개선으로 보고하지 않습니다.
- Editor 수치는 원인 탐색용으로 구분하고, 승인된 목표 기기의 Development Build 프로파일과 최저 보장 기기 결과를 기준으로 판단합니다. Development·Deep Profile 계측 비용과 릴리스 결과를 구분합니다.
- Deep Profile은 전체 호출을 계측해 결과를 왜곡하므로 일반 용도로 쓰지 않고, 의심 구간에 `ProfilerMarker`를 추가합니다.
- CPU·GPU·대기와 순간 스파이크·지속 부하·메모리를 먼저 분리합니다. wait 마커 하나로 GPU bound를 확정하지 않으며, 현재 버전에서 지원하는 Profiler Highlights·Timeline 등으로 병목과 동기화·프레임 제한 대기를 대조합니다.
- Memory Profiler 스냅샷 비교로 누수·중복 에셋·과대 텍스처를 찾고, Frame Debugger로 배칭이 실제로 성립하는지 확인합니다. 개선 주장은 Profile Analyzer 등 변경 전후 비교 측정으로 뒷받침합니다.
- 재현 입력·warm-up·기기 상태·측정 구간을 고정하고 한 번에 하나를 변경합니다. 변경 부위뿐 아니라 전체 프레임·메모리·로딩·기능·화질 회귀를 비교하고, 이득이 없거나 승인된 예산을 넘으면 기록한 이전 값으로 롤백합니다. 전후 조건이 다르면 개선 판정은 `unknown`입니다.

## CPU·메모리

프레임 경로 할당 규칙은 [런타임 성능 공통 규칙](../core/runtime-performance.md)을 따릅니다. 추가 기준은 다음과 같습니다.

- 고빈도 프레임 경로의 불필요한 관리 힙 할당 0바이트를 최적화 목표로 검토하되 모든 초기화·로딩 할당을 0으로 강제하지 않습니다. GC.Alloc뿐 아니라 프레임 시간과 풀·캐시 상주 메모리를 함께 비교합니다. Unity 예시 기준 프레임당 1KB는 60fps에서 분당 3.6MB의 가비지입니다.
- 생성 빈도가 높고 수명이 짧은 오브젝트(투사체, VFX)는 `Instantiate`/`Destroy` 대신 내장 `UnityEngine.Pool`(`ObjectPool<T>`, `ListPool` 등)을 검토합니다. 풀은 메인 스레드 전용이며, 반환 시 상태를 초기화하고 레벨 전환 시 `Clear()`를 검토합니다.
- Incremental GC는 mark 단계를 프레임에 분산해 스파이크를 줄이는 대신 참조 쓰기마다 배리어 비용을 추가합니다. 기본값을 유지하고, 변경은 GC 스파이크 측정 결과가 있을 때만 검토합니다.
- 대규모 데이터의 병렬 순회 핫스팟이 측정으로 확인되면 C# Job System과 Burst(값 타입·`NativeContainer` 기반)를 검토합니다. 사소한 작업을 Job으로 옮기지 않습니다.

## 드로우콜 절감

- URP·HDRP에서는 SRP Batcher가 기본이며 드로우콜 수가 아니라 호출당 준비 비용을 줄입니다. 같은 셰이더 변형을 쓰는 오브젝트가 배칭되며, `MaterialPropertyBlock`은 SRP Batcher 호환을 깨뜨립니다.
- 같은 메시·머티리얼 복제가 많으면 GPU Instancing을, 움직이지 않는 지오메트리는 Static Batching(결합 메시 메모리 비용 존재)을 검토합니다. Static Batching이 적용된 오브젝트는 Instancing이 비활성화되므로 인스턴싱 대상 프리팹을 static으로 표시하지 않습니다.
- Dynamic Batching은 CPU 정점 변환 비용 때문에 최신 기기에서 권장되지 않습니다.
- 텍스처 아틀라스(2D·UI는 Sprite Atlas)로 머티리얼을 공유시켜 렌더 상태 변경을 줄입니다.

## uGUI

- 요소 변경으로 해당 Canvas의 배치 재분석 비용이 생길 수 있습니다. 정적 UI와 함께 변하는 동적 요소를 갱신 빈도 기준으로 분리하되 Canvas 간 배칭 단절·드로우콜과 재구성 비용을 함께 측정합니다. 이 절은 uGUI 대상이며 UI Toolkit에 일반화하지 않습니다.
- 상호작용하지 않는 모든 Graphic의 Raycast Target을 해제하고, 상호작용 없는 Canvas에서는 GraphicRaycaster를 제거합니다.
- Layout Group은 dirty 시 재계산 비용이 크므로 불필요한 중첩을 줄입니다. 정적 레이아웃은 앵커 또는 그룹 제거를 검토하되 SafeArea·다국어·가변 텍스트·해상도 대응이 필요한 동적 배치를 보존합니다.
- 보이지 않는 전체 화면 UI는 기존 UI 수명·Stack 정책 안에서 Canvas 또는 GameObject 비활성화를 검토합니다. Canvas 비활성화나 CanvasGroup alpha=0은 입력·Update·Coroutine·비동기 작업 중지를 보장하지 않습니다. UI Animator의 반복 dirty 비용이 확인되면 기존 승인된 코드·트윈 방식을 검토합니다.

## 물리

- Fixed Timestep과 Maximum Allowed Timestep은 물리 호출 횟수·스파이크를 측정한 뒤 조정합니다. 충돌 누락·판정 주기·시간 진행 등 기능을 보존하고 승인된 전후 검증과 롤백 조건을 둡니다.
- Layer Collision Matrix는 충돌·트리거·게임플레이 의존을 확인해 불필요한 레이어 쌍만 비활성화합니다.
- 콜라이더는 프리미티브(Box·Sphere·Capsule)와 프리미티브 조합(Compound)을 우선합니다. Unity 6.0 문서 기준 일반적인 비용 경향은 Sphere·Capsule → Box → Convex Mesh → Non-convex Mesh이지만, 실제 비용은 형상·개수·접촉·cooking 조건에 따라 달라지므로 대상 Unity 버전과 목표 기기에서 Profiler로 측정해 판단합니다.
- Mesh Collider는 조건별로 구분합니다. Convex Mesh Collider는 프리미티브·Compound로 형상을 근사할 수 없을 때 non-kinematic(동적) Rigidbody에도 사용할 수 있습니다. Non-convex Mesh Collider는 정적 지오메트리 또는 kinematic Rigidbody에만 사용하며 non-kinematic Rigidbody에는 붙일 수 없습니다. 움직이는 오목 형상은 Compound 또는 볼록 분해로 구성합니다.
- 물리 오브젝트 이동은 Transform이 아니라 Rigidbody API로 수행하고, 반복 쿼리 비용이 확인되면 거리·layerMask·trigger 조건과 Non-Alloc·배치 쿼리를 검토합니다. `RaycastNonAlloc`은 반환 count 범위만 읽고 결과 순서를 가정하지 않습니다. 버퍼 포화 시 전체 결과나 가장 가까운 hit를 보장하지 않으므로 누락 대응을 먼저 정합니다.

## 에셋 파이프라인

- 텍스처는 플랫폼별 오버라이드를 사용합니다. Android·iOS는 ASTC를 우선 검토하되 GPU 지원·화질을 확인하고 구형 기기 대응은 ETC2·PVRTC를, 데스크톱은 DXT·BC 계열을 검토합니다. Max Size는 허용 품질 안에서 낮추고, 3D 밉맵·UI 밉맵 비활성화도 실제 축소 표시와 메모리·화질 요구에 맞춰 결정합니다.
- 오디오는 스테레오 요구가 없는 3D·모바일 SFX에 Force To Mono를 검토합니다. PCM·ADPCM·Vorbis 압축과 짧은 SFX의 Decompress On Load, 중간 길이의 Compressed In Memory, 긴 음악·앰비언스의 Streaming은 음질·지연·동시 재생 CPU·메모리를 비교해 선택합니다.
- 메시는 Mesh Compression을 검토하고, 런타임 CPU 접근·변형·collider cooking 등 사용처를 확인한 뒤 Read/Write와 사용하지 않는 Rig·BlendShape를 비활성화합니다. Read/Write의 CPU 사본 비용과 실제 절감량을 측정하고 필요한 데이터·품질을 보존합니다.
- Resources 폴더는 시작 시간·빌드 시간·메모리 관리에 불리하므로 신규 로드 경로는 승인된 구조 안에서 Addressables를 검토합니다. 모든 로드와 해제의 소유자를 기록하며 Addressables release는 즉시 메모리 해제를 뜻하지 않습니다. 번들·의존 참조와 unload/reload churn을 함께 확인하고, 로컬 LZ4·원격 LZMA도 전송·해제·재압축 비용을 비교한 뒤 선택합니다.

## 스크립팅·빌드

- 릴리스는 대상 플랫폼 지원과 프로젝트 빌드 정책 안에서 IL2CPP를 검토하고, 지원되는 Code Generation의 Faster runtime·Faster (smaller) builds와 C++ Compiler Configuration의 Master를 실행 성능·크기·빌드 시간에 맞춰 비교합니다. 책의 권고만으로 backend·설정을 일괄 변경하지 않습니다.
- Managed Stripping Level을 높이면 바이너리가 줄지만 리플렉션 접근 코드가 제거될 수 있습니다. `link.xml` 또는 `[Preserve]`로 보호하고 상향 후 전체 동작을 검증합니다.
- `GetComponent`·`Camera.main` 결과를 캐싱하고, 매 프레임 `Find` 계열을 금지하며, `CompareTag`를 사용하고, 빈 `Update()`는 삭제합니다.

## 모바일

- `Application.targetFrameRate`를 기기 등급별로 명시합니다. 모바일에서 `vSyncCount`는 무시되며, 불안정한 높은 목표보다 안정적인 낮은 목표가 낫습니다. 메뉴·일시정지에서는 목표 프레임을 낮춥니다.
- 지속 부하는 발열로 강제 클럭 저하를 부릅니다. Adaptive Performance 패키지의 열 경고·bound 피드백으로 LOD·그림자·해상도를 단계적으로 낮추는 대응을 검토합니다.
- GPU 픽셀 처리 병목이 확인되면 3D 렌더 해상도를 URP Render Scale 등으로 낮추고 UI는 네이티브를 유지하는 방식을 검토합니다. 파이프라인·UI 합성 경로의 지원, 화질과 실제 GPU·배터리 이득을 확인합니다.

## 출처

Unity 6 공식 최적화 가이드와 문서를 근거로 합니다.

- Unity Performance Tuning Bible(장별 출처·적용 제한은 [적용 가이드](performance-tuning-bible.md)): https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/
- RaycastNonAlloc 결과 계약: https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Physics.RaycastNonAlloc.html
- Unity 6 Mobile·XR·Web 최적화 e-book: https://unity.com/resources/mobile-xr-web-game-performance-optimization-unity-6
- Unity 6 Console·PC 최적화 e-book: https://unity.com/resources/console-pc-game-performance-optimization-unity-6
- 오브젝트 풀·재사용: https://docs.unity3d.com/6000.4/Documentation/Manual/performance-reusable-code.html
- GC와 Incremental GC: https://docs.unity3d.com/6000.4/Documentation/Manual/performance-garbage-collector.html
- 드로우콜 최적화: https://docs.unity3d.com/6000.4/Documentation/Manual/optimizing-draw-calls.html
- SRP Batcher: https://docs.unity3d.com/Manual/SRPBatcher.html
- UI 최적화: https://unity.com/how-to/unity-ui-optimization-tips
- 물리 성능: https://unity.com/how-to/enhanced-physics-performance-smooth-gameplay
- 콜라이더 종류와 성능(Unity 6.0): https://docs.unity3d.com/6000.0/Documentation/Manual/physics-optimization-cpu-collider-types.html
- Rigidbody 콜라이더 구성(Unity 6.0): https://docs.unity3d.com/6000.0/Documentation/Manual/rigidbody-configure-colliders.html
- MeshCollider.convex(Unity 6.0): https://docs.unity3d.com/6000.0/Documentation/ScriptReference/MeshCollider-convex.html
- 에셋 설정: https://unity.com/how-to/project-configuration-and-assets
- Addressables 메모리: https://docs.unity3d.com/Packages/com.unity.addressables@2.0/manual/MemoryManagement.html
- IL2CPP: https://docs.unity3d.com/6000.4/Documentation/Manual/il2cpp-introduction.html
- Managed Stripping: https://docs.unity3d.com/6000.4/Documentation/Manual/managed-code-stripping.html
- targetFrameRate: https://docs.unity3d.com/6000.1/Documentation/ScriptReference/Application-targetFrameRate.html
- Adaptive Performance: https://docs.unity3d.com/6000.5/Documentation/Manual/adaptive-performance/cpu-gpu-performance-control.html
- 프로파일링 모범 사례: https://unity.com/how-to/best-practices-for-profiling-game-performance

# Unity Performance Tuning Bible 적용 가이드

> CyberAgent Game & Entertainment의 [Unity Performance Tuning Bible](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/) 1~12장을 기존 하네스와 대조한 조건부 참고입니다. 확인일: **2026-10-17**. [서문](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/preface.html)의 기준은 **스마트폰·Unity 2020.3.24f1**이며, 사례 수치·API·메뉴·도구 버전을 현재 프로젝트의 보편 규칙으로 사용하지 않습니다.

## 읽기 경로와 권한

[일반 최적화](general-techniques.md)에서 성능 Task를 시작할 때 아래 측정 절과 해당 분야를 읽습니다. 기초가 필요하면 2장, 도구 선택은 3장, 원인별 후보는 4~12장을 참조합니다. 원문 번역·예제 복사 대신 적용 판단에 필요한 요지만 유지합니다.

- [Core 런타임 성능](../core/runtime-performance.md)·[Unity 안전성](../core/unity-safety.md)·[조건부 렌더링](rendering-techniques.md)과 확정된 [Profiles](../../profiles/)를 함께 적용합니다. 기존 아키텍처·DI·비동기·Canvas Stack 정책을 최적화 이유로 바꾸지 않습니다. 업무용의 Layered Architecture·MVP·VContainer·UniTask·콘텐츠별 Canvas와 중앙 Stack 책임도 유지합니다.
- 도구 설치, 계측 코드, 제품·에셋·설정 수정, 빌드·실기기·장시간 발열/배터리 측정은 현재 승인된 대상과 동작에 한정합니다. 이 문서나 계획 템플릿을 읽은 것만으로 실행 권한을 얻지 않습니다. Unity 실행 수단과 identity는 기존 [CLI 가이드](../../onboarding/unity-cli.md)·[Editor 격리](../../onboarding/unity-worktree-cli.md)를 따릅니다.
- [선택형 성능 측정 카드](../../exec-plans/_TEMPLATE.md)에 조건·원시 기록·판정을 연결합니다. 미승인 실행은 `not_run`, 미확인 지원·병목·비교는 `unknown`입니다. `not_applicable`은 확인된 비적용 이유가 있을 때 쓰며, 기법의 `applicable`도 승인과 비교 증거를 대신하지 않습니다.

## 1. 측정 → 원인 분리 → 단일 변경 → 전체 재비교

근거: [1장](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_start.html) 1.1~1.10, [2장](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/basic.html) 2.1·2.2·2.4·2.6, [3장](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/profile_tool.html).

1. 목표 기기와 최저 보장 기기·OS·Unity/패키지 버전·파이프라인·backend·Development/릴리스 설정을 기록합니다. 프레임 시간, 최대 메모리, 화면 전환/로딩 시간, 지속 플레이 발열·배터리 예산과 허용 화질을 승인 범위에서 정합니다. 책의 fps·GB·초·배터리 비율은 예시이며 기본 합격선이 아닙니다.
2. 동일 scene·데이터 hash·입력 순서·난수 조건·해상도·품질·warm-up·샘플 구간·반복수·기기 열/충전 상태를 고정합니다. Editor는 원인 탐색 증거로 구분하고 대상 기기 결과로 승격하지 않습니다. Development·Profiler 연결·Deep Profile·스냅샷의 계측 비용도 기록하고, 서로 다른 빌드 설정의 수치를 직접 비교하지 않습니다.
3. 순간 스파이크와 지속 부하를 나눈 뒤 CPU Main/Render/Worker Thread, GPU, 동기화·I/O·프레임 제한 대기와 메모리를 분리합니다. Timeline으로 대기의 상대 스레드·작업을 확인하고 Hierarchy의 Total/Self/Calls/GC.Alloc을 대조합니다. `Gfx.WaitForPresent` 같은 마커나 해상도 감소 반응 하나만으로 GPU 병목을 확정하지 않습니다.
4. 실제 병목의 큰 비용부터 한 번에 하나를 바꿉니다. 데이터 수·알고리즘 복잡도·호출 빈도·중복 작업을 먼저 검토하고, 캐싱·풀링·배칭·병렬화의 추가 상주 메모리와 유지 비용을 비교합니다. Deep Profile은 일반 캡처로 부족한 구간에 제한하고 기존 marker 계측을 우선합니다.
5. 같은 조건·집계 방식으로 기준/변경 후를 비교합니다. 평균·중앙값만으로 스파이크를 숨기지 않고 승인한 p95/p99·최대값 등과 샘플 수·구간을 함께 남깁니다. 수정한 함수뿐 아니라 전체 프레임·메모리·전환·기능·화질 회귀를 확인하며, 조건 불일치는 `unknown`, 이득 없음·예산 초과·기능 회귀는 기록한 이전 코드/설정으로 롤백합니다. 미승인 회귀 실행은 `not_run`이며 개선 확정 근거가 아닙니다.

도구는 질문에 맞춰 고릅니다. Unity Profiler는 프레임·스레드·할당, Profile Analyzer는 구간 통계·전후 비교, Frame Debugger는 실제 draw·batch·render target, Memory Profiler는 객체·참조·스냅샷 비교에 사용합니다. OS/native footprint와 플러그인 등은 승인된 Xcode/Instruments·Android 도구로 보완합니다. Frame Debugger의 draw 수만으로 GPU 시간 개선을 주장하지 않습니다. 책의 Heap Explorer·RenderDoc 등은 선택 참고이며 새 설치를 요구하지 않습니다. 최신 조작법과 지원 조건은 설치된 도구 버전의 공식 문서로 재확인합니다.

## 2. 메모리 증가와 큰 점유량을 구분

근거: 1장 1.4~1.6, 2장 2.4~2.5, 3장 3.1·3.4~3.8.

- **같은 상태로 돌아오는 화면 전환을 3~5회 반복**하는 것은 누수 후보 수집 절차입니다. warm-up, 최초 로드 캐시, 해제 지연, allocator의 reserved/pool 보존, 캡처 자체의 메모리를 구분합니다. 총량 증가만으로 누수를 확정하지 않고 반복 후 남는 객체·에셋과 root reference/소유자의 예상 수명을 추적합니다. 반복 횟수만 채웠다고 누수 없음도 판정하지 않습니다.
- 비교하는 counter·단위·도구·시점의 정의를 기록합니다. managed heap/GC.Alloc, Unity tracked의 in-use/reserved, untracked, graphics/driver, OS/native footprint는 같은 수치가 아닙니다. 플러그인·런타임 metadata·실행 코드 등이 어느 counter에 포함되는지는 버전·플랫폼·도구에 따라 확인하며, Unity 수치가 OS 전체 사용량과 같거나 모든 native 할당을 설명한다고 가정하지 않습니다. 캡처 전후 계측 overhead도 분리합니다.
- 누수 후보와 별개로 큰 bytes부터 불필요/중복 에셋·텍스처/메시 CPU 사본·번들 의존·managed heap·native 플러그인 순으로 실제 점유를 살핍니다. 객체 수 감소만으로 byte 절감을 추정하지 않습니다. 풀·캐시의 보존량과 무효화·종료 시 정리 책임을 기록합니다.
- `UnityEngine.Object`의 native 파괴 후 관리 참조가 남을 수 있으므로 기존 Fake Null 비교와 이벤트/비동기/캐시 정리를 지킵니다. `Destroy`나 GC가 모든 참조·native 자원을 즉시 해제한다는 근거로 쓰지 않습니다.

현재 교차확인: [Unity 6.0 Memory 모듈](https://docs.unity3d.com/6000.0/Documentation/Manual/ProfilerMemory.html), [Memory Profiler 1.1 문서](https://docs.unity3d.com/Packages/com.unity.memoryprofiler@1.1/manual/index.html). 책의 0.5/0.6 UI·Preview 설치법이나 counter 명칭을 최신 절차로 강제하지 않습니다.

## 3. 분야별 적용 후보와 보존 조건

### 에셋·로딩·AssetBundle — 4·5장

- 텍스처의 크기·GPU 지원 압축·mipmap·anisotropic과 메시의 Read/Write·vertex/mesh compression·미사용 채널을 실제 접근 경로와 대조합니다. CPU 픽셀/메시 접근, 런타임 변형·collider cooking·shader 전환에 필요한 데이터를 보존합니다. Read/Write의 CPU 사본을 줄일 수 있어도 모든 에셋이 정확히 절반이 된다고 주장하지 않습니다. Animation key/skin weight/culling은 root motion·offscreen 상태 갱신·외형을, Particle/SubEmitter/noise는 최대 발생량과 연출을, Audio load type/압축/sample rate/mono는 지연·CPU·메모리와 스테레오 요구를 함께 비교합니다.
- `Renderer.material`·`MeshFilter.mesh` 접근은 인스턴스를 만들 수 있으므로 소유자와 수명 종료 시 `Destroy`를 추적합니다. 런타임 생성 Texture/Sprite/Material/Mesh와 PlayableGraph 등도 해당 API의 해제 책임을 둡니다. shared 자산을 대신 수정·파괴하지 않습니다. 현재 근거: [Renderer.material](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Renderer-material.html), [MeshFilter.mesh](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/MeshFilter-mesh.html).
- Resources/StreamingAssets의 불필요 포함과 시작 비용을 살피되 로더·직렬화 구조를 자동 교체하지 않습니다. ScriptableObject의 binary 저장 권고도 기존 diff/merge·데이터 보존 계약보다 우선하지 않습니다.
- 번들은 동시 사용 수명·공유 의존·중복·갱신 다운로드량·파일 수·메모리 overhead를 함께 비교합니다. file/memory/stream 로드 경로와 압축/재압축의 CPU·임시 메모리·I/O를 측정해 선택합니다. load마다 release 소유자를 두고 번들·의존 참조와 unload/reload churn을 확인합니다. Addressables release는 즉시 메모리 반환을 뜻하지 않습니다. 현재 근거: [Addressables 2.0 메모리 관리](https://docs.unity3d.com/Packages/com.unity.addressables@2.0/manual/MemoryManagement.html).
- 책의 `AssetBundle.Unload(true)` 선호나 동시 번들 **150~200개**를 공통 정책·안전 임계값으로 채택하지 않습니다. `true`는 사용 중 에셋까지 파괴할 수 있고 `false`도 별도 에셋 수명·중복 로드 관리가 필요합니다. 기존 로더 소유권과 OS/버전별 제약을 확인하며 전역 unload·강제 GC·OS 파일 한도 조정을 자동 권고하지 않습니다.

### 물리 — 6장

PhysX 3D 중심의 권고를 2D/ECS Physics에 그대로 적용하지 않습니다. Fixed/Maximum timestep·simulation·collision matrix·충돌 모드·sleep·transform sync·callback 재사용은 호출 횟수와 실제 비용이 확인됐을 때만 후보로 삼습니다. 변경 전후 충돌/trigger·고속 이동 관통·판정 주기·게임 시간·이동/동기화 의미를 보존합니다. 최신 API 지원과 현재 프로젝트 설정을 먼저 확인하고 프레임 목표에 timestep을 기계적으로 맞추지 않습니다. Collider 구성은 [일반 최적화](general-techniques.md)의 동적/kinematic·convex 제약을 유지합니다.

반복 쿼리는 필요한 거리·layerMask·trigger 조건을 좁히고 NonAlloc/배치를 검토합니다. **`RaycastNonAlloc`은 반환 count 미만만 읽으며 결과 순서는 미정**입니다. count가 버퍼 길이와 같으면 누락 가능성이 있고 가장 가까운 hit 집합도 보장되지 않습니다. 첫 원소를 nearest로 취급하거나 포화 버퍼를 정렬한 것만으로 전체 nearest를 확정하지 않습니다. 전체 결과가 필요한 호출자는 재조회/용량/대체 쿼리 정책을 정하고 비용·정확도를 비교합니다. 책의 예제 코드는 복사하지 않고 현재 [Unity 6.0 API 계약](https://docs.unity3d.com/6000.0/Documentation/ScriptReference/Physics.RaycastNonAlloc.html)을 기준으로 확인합니다.

### 그래픽스·uGUI — 7·8장

- 해상도·overdraw·셰이더/variant warm-up·그림자·lighting bake·LOD·texture streaming은 CPU/GPU·메모리·로딩과 화질을 함께 비교합니다. Static/Dynamic batching·Instancing·SRP Batcher의 대상과 비용을 구분하고, 현재 파이프라인의 [렌더링 최적화 베이스](rendering-techniques.md) 지원/판정 조건을 유지합니다. 책의 Built-in 셰이더·SpriteAtlas V1 예제와 과거 하드웨어 수치를 최신 파이프라인에 일반화하지 않습니다.
- **UI 항목은 uGUI/TextMeshPro 대상**입니다. Canvas를 갱신 빈도로 나눌 때 rebuild 절감과 Canvas 간 배칭 단절·draw 수를 같이 비교합니다. 업무의 콘텐츠별 Canvas·Full Screen/Popup/Dimmed 흐름·중앙 sortingOrder 책임을 합치거나 대체하지 않습니다.
- Layout 제거/앵커 치환은 실제 정적 배치일 때 검토합니다. SafeArea·다국어·가변 길이/크기·해상도·스크롤 요구를 보존하고 강제 Layout rebuild와 중첩 비용을 확인합니다. Raycast Target/Raycaster 축소는 입력·차단·스크롤에 필요 없는 대상에 한정합니다.
- atlas의 흰 sprite·Mask/RectMask2D·TextMeshPro 문자열 갱신은 실제 batch break·overdraw·culling·할당이 확인될 때 검토합니다. clipping 모양·입력·화질·텍스트 정밀도/서식 요구를 보존하며 특정 mask를 전역 금지하거나 ZString 등 새 의존성을 강제하지 않습니다.
- Canvas 비활성화·GameObject 비활성화·CanvasGroup alpha=0의 표시 비용과 수명 의미는 다릅니다. **alpha=0만으로 입력, Update, Coroutine, 비동기 작업이 멈추지 않습니다.** Canvas 숨김도 자식 스크립트 중지를 보장하지 않습니다. 기존 입력 차단·취소·Presenter Dispose 정책을 유지하고 재표시 비용까지 비교합니다. 책의 1280개 Image 예제 시간은 일반 합격선이 아닙니다. 현재 근거: [Unity uGUI 최적화](https://unity.com/how-to/unity-ui-optimization-tips).

### Unity/C#·빌드·사용 중 라이브러리 — 9~12장

- 반복 component/name/tag/string ID 조회, 빈 Unity event 함수, 로그 문자열 생성, 직렬화·collection 확장·boxing·closure·LINQ 재열거/결과 생성·async state machine을 실제 hot path에서 확인합니다. 기존 [런타임 성능](../core/runtime-performance.md)의 캐시 무효화·pool 용량/초기화/반환/종료 정리를 유지합니다. 0 GC.Alloc만을 위해 모든 객체를 struct/static으로 바꾸거나 모든 foreach/LINQ를 금지하지 않습니다. struct 복사와 풀 상주량도 비용이며 compiler/backend/데이터 규모에 따라 비교합니다.
- 비동기 최적화는 기존 [비동기 프로필](../../profiles/async.md)의 소유자·취소·예외 관찰·Unity main thread 경계를 보존합니다. `ConfigureAwait(false)`·Task.Run·불필요 async 제거를 일괄 적용하지 않습니다. `unsafe`·`stackalloc`·Burst/Jobs·sealed/inlining은 지원 버전·AOT·수명·stack 크기·코드 크기와 실제 병목 확인 후 별도 승인 범위에서 검토합니다. 예제 benchmark 배수와 과거 IL 생성 결과를 현재 이득으로 주장하지 않습니다.
- IL2CPP/Code Generation/C++ 최적화·stripping은 지원 플랫폼과 빌드 목적·시간·크기의 tradeoff로 판단합니다. reflection·동적 생성·직렬화·플러그인 타입 보존과 `link.xml`/`Preserve` 필요성을 확인합니다. 센서 주기 축소/비활성화도 실제 센서 사용을 확인합니다. 미승인 빌드·전체 동작 검증은 `not_run`이며 설정을 검증 완료로 보고하지 않습니다.
- DOTween·UniRx·UniTask는 사용 중인 제품/설치 버전과 확정 프로필에서만 확인합니다. DOTween 재사용·무한 반복은 기존 [트윈 프로필](../../profiles/tween.md)의 소유 Kill/대상 수명을, UniRx는 구독 Dispose를, UniTask는 종료 조건·CancellationToken·예외 관찰을 점검합니다. Tracker/Inspector를 켠 진단 비용과 일반 측정을 구분합니다. 풀 반환은 Destroy와 다를 수 있으므로 반환 때도 작업·구독·트윈 정리가 필요합니다. 책의 v2 업그레이드 권고나 `SetLink`만으로 모든 수명 문제가 해결된다고 가정하지 않습니다.

## 4. 장별 반영·기존 연결·보류

| 원문 장 | 반영한 판단 기준 | 기존 연결 | 보류·현재 확인 필요 |
|---|---|---|---|
| [1. 시작](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_start.html) | KPI/보장 기기, 추정 금지, 전체 전후 비교, 반복 전환 누수 후보 | 일반 최적화·측정 카드 | 사례 메모리 상한·기기 등급·합격 수치 |
| [2. 기초](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/basic.html) | CPU/GPU/대기·native/managed·수명·복잡도 | Core 성능·Unity 안전성 | 과거 SoC/OS 용량·속도·stack 크기의 보편화 |
| [3. 도구](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/profile_tool.html) | 프레임/구간/참조/OS별 도구 선택·계측 비용 | CLI·Editor 격리·측정 카드 | Preview/설치/메뉴·인증·연결 절차는 현 버전 확인 |
| [4. 에셋](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_asset.html) | 큰 bytes·CPU 사본·인스턴스 수명·품질/지연 보존 | 일반 최적화 에셋·Unity 안전성 | 압축·mipmap·mono·binary 저장 일괄 변경 |
| [5. AssetBundle](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_assetbundle.html) | 공유 의존·중복·해제 책임·churn | 일반 최적화 로딩 | Unload(true) 전역 권고·150~200개 임계값 |
| [6. 물리](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_physics.html) | timestep/충돌 기능 보존·NonAlloc count/포화/순서 | 일반 최적화 물리 | 예제 API·과거 설정 기본값·2D/ECS 일반화 |
| [7. 그래픽스](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_graphics.html) | 해상도/overdraw·batch·CPU/GPU/메모리 tradeoff | 조건부 렌더링·렌더링 Profile | Built-in 셰이더·Atlas V1·수치/옵션 일괄 적용 |
| [8. UI](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_ui.html) | rebuild/batch·동적 Layout·숨김과 수명 분리 | 일반 최적화 uGUI·기존 Canvas Stack | UI Toolkit 일반화·mask/SetActive 일괄 금지 |
| [9. Unity 스크립트](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_script_unity.html) | 반복 조회·native 자원 해제·로그 비용 | Core 성능·안전성 | JsonUtility 과거 동작·Burst 예제 이득·일괄 로그 제거 |
| [10. C#](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_script_csharp.html) | 할당·복사·재열거·async/풀 수명 비용 | Core 성능·비동기 Profile | foreach/LINQ 전역 금지·unsafe/stackalloc 강제 |
| [11. Player Settings](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_player_settings.html) | backend·최적화/stripping·센서의 목적/기능 보존 | 일반 최적화 빌드·기존 검증 권한 | 설정 자동 변경·미실행 빌드/동작 검증 승격 |
| [12. Third Party](https://cyberagentgameentertainment.github.io/UnityPerformanceTuningBible/en/tuning_practice_third_party.html) | 사용 제품의 tween/구독/task 종료·진단 비용 | 트윈/비동기 Profile·수명 정책 | 새 도입·일괄 업그레이드·업무 기술 교체 |

이 가이드의 반영은 문서 정책의 적용입니다. 실제 성능 개선·누수 해소·플랫폼 지원 판정은 승인된 동일 조건 측정과 기능 회귀 증거가 있어야 별도로 보고할 수 있습니다.

# 기술 스택 기술 설명 (Tech Stack Overview)

> 이 문서는 프로젝트의 핵심 기술 아키텍처와 라이브러리 사용 지침을 정리한 레퍼런스입니다.
> 에이전트와 개발자 모두 협업 시 이 기술 표준을 따라야 합니다.

---

## 1. VContainer (의존성 주입)

VContainer는 Unity에 특화된 고성능, 저할당(Low-allocation) DI 솔루션입니다. 이 프로젝트는 객체 간의 결합을 방지하고 테스트 용이성을 극대화하기 위해 VContainer를 적극 도입하였습니다.

### Lifetime 범위와 구조
1. **Root LifetimeScope**: 앱의 전역 매니저, 데이터 영속 계층, 플랫폼 연동 서비스를 바인딩합니다.
2. **Scene LifetimeScope**: 각 씬의 Presentation 레이어(View), 씬 내 흐름 제어, 로컬 ViewModel 및 도메인 서비스를 바인딩합니다.

### 인젝션 방식
- **생성자 주입 (Constructor Injection)**: MonoBehaviour가 아닌 순수 C# 도메인 클래스나 ViewModel에 기본적으로 적용합니다.
- **프로퍼티/필드 주입 (Property/Field Injection)**: MonoBehaviour를 상속받은 View 컴포넌트에 주입할 때 사용하며, `[Inject]` 애트리뷰트를 마크합니다.

```csharp
// 생성자 주입 예시
public class InventoryService : IInventoryService
{
    private readonly IRepository m_repository;

    public InventoryService(IRepository repository)
    {
        m_repository = repository;
    }
}

// 프로퍼티 주입 예시 (View)
public class InventoryView : MonoBehaviour
{
    [Inject]
    public InventoryViewModel ViewModel { get; set; }
}
```

---

## 2. UniTask (비동기 제어)

전통적인 코루틴은 프레임 기반의 연산에 유리하지만, 값 반환이 어렵고 가비지 컬렉션(GC) 할당을 유발하는 구조적 단점이 있습니다. 이 프로젝트는 모든 비동기 작업을 UniTask로 표준화합니다.

### 비동기 구현 표준 가이드
- **대기 처리**: `yield return` 대신 `await` 키워드를 사용합니다.
- **예외 처리**: `async UniTaskVoid` 내에서 발생하는 예외는 호출스택 밖으로 전파되므로 반드시 `try-catch`로 묶거나 에러를 핸들링합니다.
- **취소 지원**: 씬 전환이나 오브젝트 파괴 시 리소스 누수 및 NullReferenceException을 막기 위해 모든 비동기 태스크에 `CancellationToken`을 명시적으로 전달합니다.

```csharp
public async UniTask<PlayerData> FetchPlayerDataAsync(string userId, CancellationToken ct)
{
    try
    {
        // 1초 대기
        await UniTask.Delay(TimeSpan.FromSeconds(1f), cancellationToken: ct);
        return new PlayerData { Id = userId };
    }
    catch (OperationCanceledException)
    {
        Debug.LogWarning("[InventoryService] 비동기 데이터 펫칭이 취소되었습니다.");
        throw;
    }
}
```

---

## 3. URP 및 GPU 성능 아키텍처

이 프로젝트는 대규모 인스턴스 렌더링 및 모바일/콘솔 환경 대응을 위해 최신 URP 그래픽스 기능들을 기본 활성화합니다.

### GPU Resident Drawer (GPU 레지던트 드로어)
- 대량의 반복적 프리팹이나 맵 에셋이 존재할 때 CPU가 수행하던 드로우콜 검사 오버헤드를 줄이고, 배칭 렌더러 그룹(BRG)을 통해 GPU가 직접 병렬 드로잉하도록 최적화합니다.
- 런타임 드로우콜 연산을 줄이기 위해 static 배칭 등 구형 기법 대신 본 방식을 우선 적용합니다.

### STP (Spatial-Temporal Post-processing)
- 화면 화질과 프레임 확보 사이의 타협을 위해 STP 업스케일 기술을 사용합니다.
- 카메라에 Anti-Aliasing 옵션이 **TAA(Temporal Anti-Aliasing)**로 선택되어 있는지 반드시 검증하고, 모션 벡터 생성이 누락되지 않도록 커스텀 셰이더 작성 시 유의하십시오.

# 아키텍처 규칙 (Architecture Rules)

> GEMINI.md §2.1~2.5 기반
> 이 문서는 프로젝트의 핵심 아키텍처 원칙, MVVM 패턴, VContainer 사용법, 디자인 패턴 카탈로그를 정의합니다.

---

## 1. SOLID 원칙 & Pure C# Logic

### Decoupling (분리)

인게임 비즈니스 로직, 계산, 상태 관리는 `MonoBehaviour`를 상속받지 않는 **일반 C# 클래스(POCO)**로 작성합니다:

```csharp
// ✅ 올바른 예시 — 순수 C# 클래스
public class DamageCalculator
{
    public int Calculate(int baseDamage, float multiplier)
    {
        return (int)(baseDamage * multiplier);
    }
}

// ❌ 잘못된 예시 — MonoBehaviour에 비즈니스 로직
public class DamageManager : MonoBehaviour
{
    public int Calculate(int baseDamage, float multiplier)
    {
        return (int)(baseDamage * multiplier);
    }
}
```

### No Singleton (절대 금지)

**싱글톤(Singleton) 패턴은 절대 사용하지 마십시오.**

```csharp
// ❌ 절대 금지
public class GameManager : MonoBehaviour
{
    public static GameManager Instance { get; private set; }
    private void Awake() { Instance = this; }
}

// ✅ VContainer DI로 대체
public class GameLifetimeScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder)
    {
        builder.Register<GameService>(Lifetime.Singleton)
               .AsImplementedInterfaces();
    }
}
```

### Dependency Injection (의존성 주입)

로직 클래스의 의존성은 **프로퍼티 주입(Property Injection)**을 기본으로 합니다:

```csharp
public class PlayerViewModel
{
    // VContainer가 자동 주입
    [Inject]
    public IPlayerService PlayerService { get; set; }

    [Inject]
    public IInventoryService InventoryService { get; set; }
}
```

### ISP & DIP (인터페이스 분리 및 의존성 역전)

구체적인 클래스보다 **인터페이스에 의존**하도록 설계합니다:

```csharp
// ✅ 인터페이스 의존
public interface IMovable
{
    void Move(Vector3 direction);
}

public interface IDamageable
{
    void TakeDamage(int amount);
}

public class PlayerService
{
    private readonly IMovable m_movable;
    private readonly IDamageable m_damageable;

    public PlayerService(IMovable movable, IDamageable damageable)
    {
        m_movable = movable;
        m_damageable = damageable;
    }
}
```

---

## 2. UI 아키텍처 — MVVM

### A. Model (순수 데이터)

- View나 Unity 엔진에 대해 **전혀 모르는** 순수 데이터 클래스
- 비즈니스 도메인 데이터와 규칙만을 포함
- UI 표현 방식에 대한 어떠한 정보도 포함하지 않음

```csharp
/// <summary>
/// [기능]: 플레이어의 기본 스탯 데이터를 관리하는 모델
/// [작성자]: 윤승종
/// </summary>
public class PlayerModel
{
    public string Name { get; set; }
    public int Level { get; set; }
    public int CurrentHp { get; set; }
    public int MaxHp { get; set; }

    public bool IsDead => CurrentHp <= 0;

    public void ApplyDamage(int damage)
    {
        CurrentHp = Math.Max(0, CurrentHp - damage);
    }
}
```

### B. ViewModel (상태 가공 + 명령)

- Model 데이터를 View가 사용하기 좋은 형태로 **가공하여 제공**
- View가 구독할 **상태(State)**와 **명령(Command)** 보유
- Model을 직접 참조하여 데이터를 읽고 가공 가능
- **View에 대해서는 전혀 알지 못함**

```csharp
/// <summary>
/// [기능]: 플레이어 UI에 필요한 상태를 가공하여 제공하는 ViewModel
/// [작성자]: 윤승종
/// </summary>
public class PlayerViewModel
{
    #region 내부 필드 (Private Fields)
    private readonly PlayerModel m_model;
    #endregion

    #region 상태 변경 이벤트 (State Events)
    public event Action<string> OnNameChanged;
    public event Action<float> OnHpRatioChanged;
    public event Action<string> OnLevelTextChanged;
    public event Action OnPlayerDied;
    #endregion

    public PlayerViewModel(PlayerModel model)
    {
        m_model = model;
    }

    #region 공개 메서드 — Command (Public Methods)
    /// <summary>
    /// [기능]: 플레이어에게 데미지를 적용하고 UI 상태를 갱신합니다.
    /// [작성자]: 윤승종
    /// [수정 날짜]: 2026-07-02
    /// [마지막 수정 작성자]: 윤승종
    /// [수정 내용]: 사망 이벤트 발행 추가
    /// </summary>
    public void ApplyDamage(int damage)
    {
        m_model.ApplyDamage(damage);
        NotifyHpChanged();

        if (m_model.IsDead)
        {
            OnPlayerDied?.Invoke();
        }
    }
    #endregion

    #region 내부 메서드 (Private Methods)
    private void NotifyHpChanged()
    {
        float ratio = (float)m_model.CurrentHp / m_model.MaxHp;
        OnHpRatioChanged?.Invoke(ratio);
    }
    #endregion
}
```

### C. View (바인딩 + 입력 전달)

- `MonoBehaviour`를 상속
- 오직 **데이터 바인딩(시각화)**과 **입력 전달**만 수행
- **View → Model 직접 참조 절대 금지**

```csharp
/// <summary>
/// [기능]: 플레이어 HUD UI를 표시하는 View
/// [작성자]: 윤승종
/// </summary>
public class PlayerView : MonoBehaviour
{
    #region UI 참조 (Inspector)
    [SerializeField] private TextMeshProUGUI m_nameText;
    [SerializeField] private Slider m_hpSlider;
    [SerializeField] private Button m_attackButton;
    #endregion

    #region 내부 필드 (Private Fields)
    private PlayerViewModel m_viewModel;
    #endregion

    #region 초기화 (Initialization)
    [Inject]
    public void Construct(PlayerViewModel viewModel)
    {
        m_viewModel = viewModel;
    }

    private void Start()
    {
        // 이벤트 구독
        m_viewModel.OnNameChanged += HandleNameChanged;
        m_viewModel.OnHpRatioChanged += HandleHpRatioChanged;

        // 입력 전달
        m_attackButton.onClick.AddListener(func_OnAttackButtonClick);
    }
    #endregion

    #region 유니티 생명주기 (Unity Lifecycle)
    private void OnDestroy()
    {
        m_viewModel.OnNameChanged -= HandleNameChanged;
        m_viewModel.OnHpRatioChanged -= HandleHpRatioChanged;
        m_attackButton.onClick.RemoveListener(func_OnAttackButtonClick);
    }
    #endregion

    #region 이벤트 핸들러 (Event Handlers)
    private void HandleNameChanged(string name)
    {
        m_nameText.text = name;
    }

    private void HandleHpRatioChanged(float ratio)
    {
        m_hpSlider.value = ratio;
    }

    public void func_OnAttackButtonClick()
    {
        m_viewModel.ApplyDamage(10);
    }
    #endregion
}
```

### D. 데이터 흐름 (단방향 — 절대 준수)

```
[사용자 입력] → View → ViewModel.Command() → Model 갱신
                                               ↓
[UI 갱신]    ← View ← ViewModel.StateChanged ←
```

> ⚠️ **View가 Model을 직접 읽거나 수정하는 양방향 흐름은 엄격히 금지합니다.**

---

## 3. Data Persistence & Scene Transition (DTO)

씬 전환 시 유지해야 할 데이터는 **순수 데이터 클래스인 DTO**로 캡슐화합니다:

```csharp
/// <summary>
/// [기능]: 씬 전환 시 플레이어 상태를 전달하는 DTO
/// [작성자]: 윤승종
/// </summary>
public class PlayerStatsDTO
{
    public string PlayerName { get; set; }
    public int Level { get; set; }
    public int CurrentHp { get; set; }
    public int MaxHp { get; set; }
    public List<string> InventoryItemIds { get; set; }
}
```

### DTO 규칙

- 전역 의존성(싱글톤, static) 절대 배제
- 씬 로더 또는 컨텍스트 매니저를 통해 다음 씬의 Initializer에 직접 주입
- `~DTO` 접미사 필수

---

## 4. 디자인 패턴 카탈로그

### A. Creational (생성)

| 패턴 | 용도 | 적용 예시 |
|------|------|----------|
| Factory Method | 객체 생성 로직 분리 | `EnemyFactory.Create(EnemyType)` |
| Abstract Factory | 관련 객체 그룹 생성 | 무기 + 투사체 조합 팩토리 |
| Builder | 복잡한 객체 생성 | 캐릭터 스탯 빌더 |
| Object Pool | 빈번한 생성/파괴 최적화 | 투사체, 이펙트, 데미지 텍스트 |

### B. Structural (구조)

| 패턴 | 용도 | 적용 예시 |
|------|------|----------|
| Facade | 서브시스템 통합 인터페이스 | `AudioFacade`, `SaveFacade` |
| Flyweight | 공유 데이터 | ScriptableObject 기반 스탯 데이터 |
| Decorator | 기능 동적 추가 | 버프/디버프 시스템 |
| Adapter | 인터페이스 변환 | 서드파티 SDK 래퍼 |
| Proxy | 지연 로딩 | 대용량 리소스 프록시 |

### C. Behavioral (행동)

| 패턴 | 용도 | 적용 예시 |
|------|------|----------|
| State/FSM | 상태 제어 (**필수**) | 캐릭터 상태 머신, UI 상태 |
| Strategy | 런타임 알고리즘 교체 | AI 행동 전략, 정렬 알고리즘 |
| Observer | 이벤트 기반 통신 | `Action`, `UnityAction` 구독 |
| Command | 명령 캡슐화 | Undo/Redo, 입력 버퍼링 |
| Behavior Tree | AI 의사결정 | NPC AI 트리 |

### 절대 사용 금지

| 패턴 | 이유 |
|------|------|
| ❌ Singleton | 전역 상태 오염, 테스트 불가, 의존성 숨김 |

---

## 5. VContainer 사용 규칙

### LifetimeScope 구성

씬 당 하나의 LifetimeScope를 배치하고, 기능 영역별로 `private` 메서드를 분리합니다:

```csharp
public class GameLifetimeScope : LifetimeScope
{
    protected override void Configure(IContainerBuilder builder)
    {
        ConfigureModels(builder);
        ConfigureViewModels(builder);
        ConfigureViews(builder);
        ConfigureServices(builder);
        ConfigureEntryPoints(builder);
    }

    private void ConfigureModels(IContainerBuilder builder)
    {
        builder.Register<PlayerModel>(Lifetime.Singleton);
    }

    private void ConfigureViewModels(IContainerBuilder builder)
    {
        builder.Register<PlayerViewModel>(Lifetime.Singleton)
               .AsImplementedInterfaces();
    }

    private void ConfigureViews(IContainerBuilder builder)
    {
        builder.RegisterComponentInHierarchy<PlayerView>();
    }

    private void ConfigureServices(IContainerBuilder builder)
    {
        builder.Register<CombatService>(Lifetime.Singleton)
               .As<ICombatService>();
    }

    private void ConfigureEntryPoints(IContainerBuilder builder)
    {
        builder.RegisterEntryPoint<GameEntryPoint>();
    }
}
```

### 등록 규칙 요약

| 대상 | 등록 방식 | 비고 |
|------|----------|------|
| View (MonoBehaviour) | `RegisterComponentInHierarchy<T>()` | **필수** |
| 동적 View | `RegisterComponentOnNewGameObject<T>()` | **허용** |
| ViewModel/Service | `Register<T>(Lifetime)` | `.AsImplementedInterfaces()` 체이닝 |
| EntryPoint | `RegisterEntryPoint<T>()` | `IStartable`, `ITickable` 구현 |

> ⚠️ **금지**: `[SerializeField]`로 뷰 컴포넌트를 직접 참조 → `RegisterInstance` 등록

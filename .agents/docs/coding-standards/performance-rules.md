# 성능 규칙 (Performance Rules)

> GEMINI.md §4.1 기반
> 이 문서는 C# 런타임 성능 최적화 규칙, 비동기 처리 패턴, 트윈 처리 규칙을 정의합니다.

---

## 1. Zero Allocation 규칙

### Update 루프 내 할당 금지

`Update`, `LateUpdate`, `FixedUpdate` 루프 내에서 다음을 **엄격히 금지**합니다:

| 금지 항목 | 이유 | 대안 |
|----------|------|------|
| `new` 키워드 | GC 할당 발생 | 사전 할당 또는 Object Pool |
| Boxing | 값 타입 → 참조 타입 변환 시 GC 할당 | 제네릭 사용 |
| LINQ | 이터레이터 + 델리게이트 할당 | `for` 루프로 직접 구현 |

```csharp
// ❌ 금지 — Update 내 할당
private void Update()
{
    var enemies = m_enemies.Where(e => e.IsAlive).ToList();  // LINQ + new List
    var direction = new Vector3(1, 0, 0);                     // new 키워드
    object boxed = m_currentHp;                               // Boxing
}

// ✅ 올바른 예시 — 사전 할당, for 루프
private readonly List<Enemy> m_aliveEnemies = new List<Enemy>();
private Vector3 m_cachedDirection;

private void Update()
{
    m_aliveEnemies.Clear();
    for (int i = 0; i < m_enemies.Count; i++)
    {
        if (m_enemies[i].IsAlive)
        {
            m_aliveEnemies.Add(m_enemies[i]);
        }
    }

    m_cachedDirection.Set(1f, 0f, 0f);
}
```

### 루프 최적화 — for vs foreach

빈번하게 호출되는 로직에서는 `foreach` 대신 **`for` 루프**를 사용합니다:

```csharp
// ✅ for 루프 — GC 할당 없음
for (int i = 0; i < m_items.Count; i++)
{
    m_items[i].Process();
}

// ❌ foreach — 이터레이터 오버헤드 (Update 등 빈번한 호출 시)
foreach (var item in m_items)
{
    item.Process();
}
```

> **참고**: `foreach`가 완전히 금지되는 것은 아닙니다. 초기화, 이벤트 핸들러 등 빈번하지 않은 호출에서는 가독성을 위해 `foreach`를 사용할 수 있습니다. **핵심은 매 프레임 호출되는 코드에서 피하는 것**입니다.

---

## 2. 비동기 처리 — UniTask

### 코루틴 금지

코루틴(`StartCoroutine`, `IEnumerator`) 대신 **UniTask**를 사용합니다:

```csharp
// ❌ 금지 — 코루틴
private IEnumerator LoadDataCoroutine()
{
    yield return new WaitForSeconds(1f);
    // 데이터 로드
}

private void Start()
{
    StartCoroutine(LoadDataCoroutine());
}

// ✅ UniTask 사용
private async UniTaskVoid LoadDataAsync(CancellationToken ct)
{
    await UniTask.Delay(TimeSpan.FromSeconds(1f), cancellationToken: ct);
    // 데이터 로드
    Debug.Log($"[DataLoader] 데이터 로드가 완료되었습니다.");
}

private void Start()
{
    LoadDataAsync(this.GetCancellationTokenOnDestroy()).Forget();
}
```

### UniTask 필수 규칙

| 규칙 | 설명 |
|------|------|
| `async UniTaskVoid` | 반환값이 없는 비동기 메서드 |
| `async UniTask` | 반환값이 있거나 await 가능한 비동기 메서드 |
| `async UniTask<T>` | 결과를 반환하는 비동기 메서드 |
| `CancellationToken` 필수 | 모든 비동기 메서드에 `CancellationToken` 매개변수 포함 |
| `.Forget()` | `UniTaskVoid` 호출 시 경고 억제 |
| `this.GetCancellationTokenOnDestroy()` | MonoBehaviour에서 자동 취소 토큰 |

### 비동기 패턴 예시

```csharp
/// <summary>
/// [기능]: 씬을 비동기로 로드합니다.
/// [작성자]: 윤승종
/// [수정 날짜]: 2026-07-02
/// [마지막 수정 작성자]: 윤승종
/// [수정 내용]: CancellationToken 지원 추가
/// </summary>
public async UniTask LoadSceneAsync(string sceneName, CancellationToken ct)
{
    Debug.Log($"[SceneLoader] 씬 로드를 시작합니다: {sceneName}");

    AsyncOperation operation = SceneManager.LoadSceneAsync(sceneName);

    while (!operation.isDone)
    {
        ct.ThrowIfCancellationRequested();
        float progress = operation.progress;
        OnLoadProgressChanged?.Invoke(progress);
        await UniTask.Yield(ct);
    }

    Debug.Log($"[SceneLoader] 씬 로드가 완료되었습니다: {sceneName}");
}
```

---

## 3. 트윈 처리 — DOTween

DOTween을 기본 트윈 엔진으로 사용합니다:

```csharp
using DG.Tweening;

// 기본 트윈
m_transform.DOMove(targetPosition, 0.5f).SetEase(Ease.OutQuad);
m_canvasGroup.DOFade(1f, 0.3f);
m_transform.DOScale(Vector3.one * 1.2f, 0.2f).SetLoops(2, LoopType.Yoyo);

// 시퀀스
Sequence sequence = DOTween.Sequence();
sequence.Append(m_transform.DOMove(pos1, 0.3f));
sequence.Append(m_transform.DORotate(rot1, 0.2f));
sequence.AppendCallback(() => Debug.Log($"[UIEffect] 트윈 시퀀스가 완료되었습니다."));
sequence.Play();
```

### DOTween 주의사항

| 규칙 | 설명 |
|------|------|
| Kill on Destroy | `OnDestroy()`에서 실행 중인 트윈을 반드시 Kill |
| SetAutoKill | 기본값 true, 완료 후 자동 정리 |
| Cache 활용 | 반복 트윈은 `SetRecyclable(true)` |
| Update 루프 내 생성 금지 | 트윈은 이벤트 기반으로만 생성 |

```csharp
private Tween m_moveTween;

private void OnDestroy()
{
    if (m_moveTween != null)
    {
        m_moveTween.Kill();
        m_moveTween = null;
    }
}
```

---

## 4. 오브젝트 풀링

빈번하게 생성/파괴되는 오브젝트(투사체, 이펙트, 데미지 텍스트 등)는 **Object Pool 패턴**을 적용합니다:

```csharp
/// <summary>
/// [기능]: 제네릭 오브젝트 풀 구현
/// [작성자]: 윤승종
/// </summary>
public class ObjectPool<T> where T : class
{
    private readonly Func<T> m_createFunc;
    private readonly Action<T> m_onGet;
    private readonly Action<T> m_onRelease;
    private readonly Stack<T> m_pool;

    public ObjectPool(Func<T> createFunc, Action<T> onGet, Action<T> onRelease, int initialCapacity = 10)
    {
        m_createFunc = createFunc;
        m_onGet = onGet;
        m_onRelease = onRelease;
        m_pool = new Stack<T>(initialCapacity);

        for (int i = 0; i < initialCapacity; i++)
        {
            m_pool.Push(m_createFunc());
        }
    }

    public T Get()
    {
        T item = m_pool.Count > 0 ? m_pool.Pop() : m_createFunc();
        m_onGet?.Invoke(item);
        return item;
    }

    public void Release(T item)
    {
        m_onRelease?.Invoke(item);
        m_pool.Push(item);
    }
}
```

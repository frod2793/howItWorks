# MVP 아키텍처 프로필

프로필 분기 `mvp`: `architecture=mvp`

## 책임

- Model은 도메인 상태와 규칙을 소유합니다.
- View는 표시와 입력 이벤트를 인터페이스로 노출합니다.
- Presenter는 View 입력을 처리하고 Model 또는 UseCase를 호출한 뒤 View를 갱신합니다.

## 허용 의존 방향

허용 의존 방향은 Presenter에서 View 인터페이스와 Model·UseCase 인터페이스를 향합니다. 구체 View는 Presenter에 입력을 전달하며 도메인 결과는 Presenter를 통해 표시합니다.

## 금지 의존 방향

View가 Model을 직접 조회·수정하거나, Model이 Presenter 또는 View를 참조하거나, Presenter가 구체 `MonoBehaviour` View 타입에 결합하는 방향을 금지합니다.

## 감지 증거

`Presenter` 역할 타입, View 인터페이스, 입력 이벤트 구독, Presenter의 렌더 호출, Model·UseCase 경계와 어셈블리 참조를 함께 봅니다. `Presenter` 이름만으로 `mvp`를 확정하지 않습니다.

## 검사 ID

- `MVP001`: View-Model 직접 결합 또는 Presenter 경계 위반 의심
- `SOLID001`: 전역 Singleton 의심
- `UNITYNULL001`: Unity Object의 null 조건부 연산 의심

`pending`에서는 진단, `confirmed`에서는 명확한 위반만 차단합니다.

## VContainer 비의존 예시

```csharp
public interface IPlayerView
{
    event Action AttackRequested;
    void SetHpRatio(float ratio);
}

public interface IPlayerModel
{
    float HpRatio { get; }
    void ApplyDamage(int damage);
}

public sealed class PlayerPresenter : IDisposable
{
    private readonly IPlayerView m_view;
    private readonly IPlayerModel m_model;

    public PlayerPresenter(IPlayerView view, IPlayerModel model)
    {
        m_view = view;
        m_model = model;
        m_view.AttackRequested += HandleAttackRequested;
    }

    private void HandleAttackRequested()
    {
        m_model.ApplyDamage(10);
        m_view.SetHpRatio(m_model.HpRatio);
    }

    public void Dispose()
    {
        m_view.AttackRequested -= HandleAttackRequested;
    }
}
```

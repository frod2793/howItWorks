# MVVM 아키텍처 프로필

프로필 분기 `mvvm`: `architecture=mvvm`

## 책임

- Model은 UI 표현과 Unity View를 모르는 도메인 데이터·규칙을 소유합니다.
- ViewModel은 Model을 View용 상태로 가공하고 상태 이벤트와 Command를 제공합니다.
- View는 `MonoBehaviour` 기반 표시·바인딩과 사용자 입력 전달만 담당합니다.

## 허용 의존 방향

허용 의존 방향은 `View → ViewModel → Model`입니다. Model 변경은 ViewModel의 상태 이벤트를 거쳐 View로 전달합니다. 객체 조립은 별도 Composition Root가 담당할 수 있습니다.

## 금지 의존 방향

View가 Model 타입을 import·필드·캐스팅으로 직접 참조하거나, Model과 ViewModel이 구체 View를 참조하는 방향을 금지합니다. UI 입력에서 도메인 상태를 직접 수정하지 않습니다.

## 감지 증거

`View`, `ViewModel`, `Model` 역할 타입, ViewModel의 상태 이벤트·Command, View의 ViewModel 참조, Model의 Unity UI 비의존성, 어셈블리·네임스페이스 참조 방향을 함께 봅니다. 폴더명 하나로 `mvvm`을 확정하지 않습니다.

## 검사 ID

- `MVVM001`: View에서 Model 직접 참조 의심
- `SOLID001`: 전역 Singleton 의심
- `UNITYNULL001`: Unity Object의 null 조건부 연산 의심

`pending`에서는 진단, `confirmed`에서는 명확한 위반만 차단합니다.

## VContainer 비의존 예시

```csharp
public sealed class PlayerViewModel
{
    private readonly PlayerModel m_model;

    public event Action<float> HpRatioChanged;

    public PlayerViewModel(PlayerModel model)
    {
        m_model = model;
    }

    public void ApplyDamage(int damage)
    {
        m_model.ApplyDamage(damage);
        HpRatioChanged?.Invoke(m_model.HpRatio);
    }
}

public sealed class PlayerView : MonoBehaviour
{
    private PlayerViewModel m_viewModel;

    public void Initialize(PlayerViewModel viewModel)
    {
        m_viewModel = viewModel;
    }

    public void HandleAttackButton()
    {
        m_viewModel.ApplyDamage(10);
    }
}
```

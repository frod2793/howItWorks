# MVC 아키텍처 프로필

프로필 분기 `mvc`: `architecture=mvc`

## 책임

- Model은 도메인 상태와 규칙을 소유합니다.
- View는 화면 표현을 담당합니다.
- Controller는 사용자 입력을 해석하고 Model의 명령을 호출하며 필요한 표시 갱신을 조정합니다.

## 허용 의존 방향

허용 의존 방향은 Controller에서 Model과 View 인터페이스를 향하며, View는 입력을 Controller로 전달합니다. 프로젝트가 Observer 기반 Model 알림을 채택했다면 View는 읽기 전용 표현 계약을 통해 알림을 받을 수 있습니다.

## 금지 의존 방향

View에서 비즈니스 규칙을 실행하거나, Model이 구체 View·Controller 또는 Unity UI에 의존하거나, Controller가 입력·표시·도메인 상태를 모두 소유하는 비대화를 금지합니다.

## 감지 증거

`Controller`, `View`, `Model` 역할 타입, 입력 콜백의 Controller 전달, Model의 UI 비의존성, Controller의 명령 호출과 참조 방향을 함께 봅니다. 이름만 같은 Unity 컴포넌트는 증거로 확정하지 않습니다.

## 검사 ID

- `MVC001`: View·Controller·Model 역할 경계 위반 의심
- `SOLID001`: 전역 Singleton 의심
- `UNITYNULL001`: Unity Object의 null 조건부 연산 의심

`pending`에서는 진단, `confirmed`에서는 명확한 위반만 차단합니다.

## VContainer 비의존 예시

```csharp
public interface IScoreView
{
    void SetScore(int score);
}

public sealed class ScoreController
{
    private readonly ScoreModel m_model;
    private readonly IScoreView m_view;

    public ScoreController(ScoreModel model, IScoreView view)
    {
        m_model = model;
        m_view = view;
    }

    public void AddScore(int amount)
    {
        m_model.Add(amount);
        m_view.SetScore(m_model.Value);
    }
}
```

# Custom 아키텍처 프로필

프로필 분기 `custom`: `architecture=custom`

## 책임

자동 감지 증거가 충돌하거나 프로젝트가 사전 정의 프로필과 다른 구조를 사용할 때 선택합니다. 하네스는 일반 아키텍처 전용 검사만 사용자 경계로 축소하며 특정 UI·레이어 아키텍처를 추정하지 않습니다. [Core 규칙](../../coding-standards/core/architecture-principles.md)·Optimization Base와 확정된 DI·비동기·트윈·렌더링 Profiles는 그대로 적용합니다. 사용자는 프로젝트 문서에 역할, 경계와 예외를 기록합니다.

## 허용 의존 방향

프로젝트 문서와 `.asmdef` 계약이 확정한 의존 방향을 허용합니다. `project-profile.conf` 옆 감지 보고서에 근거 파일과 선택 이유를 기록하고, 상세 구조 문서의 상대 경로를 프로젝트 온보딩 문서에 연결합니다.

## 금지 의존 방향

금지되는 의존 방향은 사용자가 확정한 프로젝트 경계에서 정의합니다. Custom이라는 이유로 Singleton, Unity 안전성, 서드파티 원본 보호와 승인 절차를 우회할 수 없으며, 문서화한 경계를 정규식 추측으로 바꾸거나 다른 아키텍처 규칙을 자동 차단하지 않습니다.

## 감지 증거

복수 아키텍처의 강한 증거 충돌, 이름과 실제 참조 방향 불일치, 자체 역할 접미사·어셈블리 경계 또는 감지 불충분을 기록합니다. 충돌 파일, 신뢰도와 사용자 확인 항목을 보고서에 남깁니다.

## 검사 ID

- 별도의 Custom 아키텍처 차단 ID는 없습니다.
- `SOLID001`, `PERF001`, `PERF002`, `UNITYNULL001`, `STYLE001`, `DOC001` 등 Core 검사와 확정된 기술 프로필 검사(`VCONTAINER001`, `UNITASK001`, `DOTWEEN001` 등)를 계속 적용합니다.
- `MVVM001`, `MVP001`, `MVC001`, `LAYER001`은 `custom`에서 강제하지 않습니다.

## VContainer 비의존 예시

```csharp
public interface IGameAction
{
    void Execute();
}

public sealed class GameActionRunner
{
    private readonly IGameAction m_action;

    public GameActionRunner(IGameAction action)
    {
        m_action = action;
    }

    public void Run()
    {
        m_action.Execute();
    }
}
```

이 예시는 Core의 인터페이스 의존만 보여 줍니다. 프로젝트 고유 UI 또는 레이어 구조를 암시하지 않습니다.

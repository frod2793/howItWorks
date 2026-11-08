# Layered/Clean 아키텍처 프로필

프로필 분기 `layered_clean`: `architecture=layered_clean`

## 책임

- Domain은 엔진과 외부 시스템에 독립적인 규칙·엔티티·값 객체를 소유합니다.
- Application은 UseCase와 포트 인터페이스로 작업 흐름을 조정합니다.
- Presentation은 Unity 입력과 표시를 Application 계약에 연결합니다.
- Infrastructure는 저장소, 네트워크, SDK와 Unity 세부 구현을 제공합니다.

레이어 이름은 프로젝트마다 달라도 되며 실제 의존 방향이 기준입니다.

## 허용 의존 방향

바깥 계층이 안쪽 계층의 추상화에 의존하는 방향을 허용합니다. 일반적인 예는 `Presentation → Application → Domain`이며 Infrastructure는 Application 또는 Domain이 선언한 포트를 구현합니다.

## 금지 의존 방향

Domain이 Presentation, Infrastructure, Unity UI나 서드파티 SDK를 참조하거나, Application이 구체 Infrastructure 구현을 직접 생성하는 안쪽에서 바깥쪽으로의 의존을 금지합니다.

## 감지 증거

Domain/Application/Presentation/Infrastructure 또는 동등 역할의 어셈블리, `UseCase`, Repository 포트, 네임스페이스와 `.asmdef` 참조 방향을 함께 봅니다. 폴더만 있고 참조가 역전되어 있으면 강한 증거로 보지 않습니다.

## 검사 ID

- `LAYER001`: 안쪽 계층의 바깥 계층 참조 의심
- `SOLID001`: 전역 Singleton 의심
- `UNITYNULL001`: Unity Object의 null 조건부 연산 의심

`pending`에서는 진단, `confirmed`에서는 명확한 위반만 차단합니다.

## VContainer 비의존 예시

```csharp
public interface ISavePort
{
    void Save(PlayerSnapshotDTO snapshot);
}

public sealed class SavePlayerUseCase
{
    private readonly ISavePort m_savePort;

    public SavePlayerUseCase(ISavePort savePort)
    {
        m_savePort = savePort;
    }

    public void Execute(Player player)
    {
        m_savePort.Save(player.CreateSnapshot());
    }
}
```

# 의존성 주입 프로필

> `dependency_injection` 값이 실제 사용 근거와 사용자 확인을 거쳐 `confirmed`일 때만 제품별 검사를 차단 규칙으로 적용합니다. 패키지 설치만으로 사용을 확정하지 않습니다.

## `vcontainer`

- 기존 베이스는 씬당 하나의 `LifetimeScope`를 두고 `Configure`에서 기능별 private `ConfigureXxx` 메서드를 호출하는 구성을 사용합니다.
- 씬 View는 `RegisterComponentInHierarchy<T>()`, 런타임 생성 View는 `RegisterComponentOnNewGameObject<T>(Lifetime, string)` 경로를 사용합니다.
- 순수 C# ViewModel·Service는 `Register<T>(Lifetime)`와 `.AsImplementedInterfaces()` 또는 `.As<IInterface>()`로 등록합니다.
- `IStartable`, `ITickable` 등 수명주기 진입점은 `RegisterEntryPoint<T>()`를 사용합니다.
- LifetimeScope의 `[SerializeField]` View를 `RegisterInstance`로 등록하는 기존 금지 규칙은 `VCONTAINER001`로 검사합니다.
- 프로퍼티 주입을 사용하는 기존 프로젝트에서는 `[Inject]` 계약과 필수 주입 검증을 유지합니다. 새 코드는 프로젝트의 현재 VContainer 사용 방식과 테스트 가능성을 확인합니다.

```csharp
protected override void Configure(IContainerBuilder builder)
{
    ConfigureServices(builder);
    ConfigureViews(builder);
    ConfigureEntryPoints(builder);
}
```

## `zenject`

Zenject 패키지와 실제 Container 조립 코드 사용이 확인된 경우입니다. Installer 또는 프로젝트의 동등한 Composition Root에 바인딩을 모으고, 구체 View·서비스가 컨테이너를 직접 조회하는 Service Locator 흐름을 만들지 않습니다. 정확한 API와 수명은 설치 버전 및 기존 프로젝트 코드를 기준으로 문서화합니다.

## `custom`

프로젝트 소유 Container 또는 Factory가 객체를 조립하는 경우입니다. 등록 지점, 수명 범위, Dispose 순서, 순환 의존 실패 정책과 테스트 대체 방법을 프로젝트 문서에 기록합니다. 특정 외부 제품 API를 강제하지 않습니다.

## `none`

DI 컨테이너를 사용하지 않는 경우입니다. 수동 Composition Root, 생성자·프로퍼티 전달 또는 Factory로 의존성을 명시합니다. Singleton이나 변경 가능한 전역 상태로 대체하지 않습니다.

```csharp
IPlayerRepository repository = new LocalPlayerRepository();
PlayerService service = new PlayerService(repository);
PlayerPresenter presenter = new PlayerPresenter(view, service);
```

## `unknown`

패키지 설치와 실제 사용이 불명확하거나 복수 방식이 충돌하는 상태입니다. 제품별 등록 규칙을 강제하지 않고 Core의 인터페이스 의존과 No Singleton만 적용하며, 조립 지점 증거를 감지 보고서에 요청합니다.

아키텍처 역할 경계는 [선택 아키텍처 프로필](architecture/), 공통 원칙은 [공통 아키텍처 원칙](../coding-standards/core/architecture-principles.md)을 따릅니다.


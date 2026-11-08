# 공통 아키텍처 원칙

> 이 문서는 모든 프로젝트에 적용하는 최소 경계만 정의합니다. UI 구조, DI 제품, 렌더 파이프라인과 소스 경로는 확정 프로필 문서가 결정합니다.

## 프로필 적용 경계

- 스키마 버전 값은 `1`이며 `profile_version=1`로 기록합니다.
- 확인 상태 `pending`(`confirmation_status=pending`)에서는 선택 프로필 검사를 진단으로만 다룹니다.
- 확인 상태 `confirmed`(`confirmation_status=confirmed`)일 때만 선택 프로필의 차단 규칙을 적용합니다.
- 아키텍처는 `architecture` 값에 따라 [아키텍처 프로필](../../profiles/architecture/)로 라우팅합니다.
- 감지 근거가 충돌하거나 경계를 확정할 수 없으면 `custom`을 사용합니다. `custom`은 일반 아키텍처 전용 검사만 사용자 경계로 축소하며, Core·Optimization Base와 확정된 DI·비동기·트윈·렌더링 Profiles는 그대로 적용합니다.

## Pure C#과 SOLID

- 비즈니스 규칙, 계산과 지속 상태는 반드시 Unity 엔진에 의존하지 않는 Pure C# 타입으로 분리합니다.
- Unity 어댑터의 예외 책임은 표현, 입력과 수명주기로 한정하며, 이 경계를 통해 비즈니스 규칙을 실행하지 않습니다.
- 클래스는 한 가지 변경 이유를 갖게 하고, 큰 인터페이스보다 소비자가 실제로 쓰는 작은 인터페이스를 선호합니다.
- 고수준 정책은 구체 구현이 아니라 인터페이스에 의존합니다. 객체 조립 방식은 확정된 DI 프로필 또는 프로젝트의 Composition Root를 따릅니다.
- 상속보다 합성을 우선하며, 확장 가능성은 실제 요구가 있을 때만 추가합니다.

```csharp
public interface IDamageRule
{
    int Calculate(int baseDamage, int defense);
}

public sealed class CombatService
{
    private readonly IDamageRule m_damageRule;

    public CombatService(IDamageRule damageRule)
    {
        m_damageRule = damageRule;
    }

    public int CalculateDamage(int baseDamage, int defense)
    {
        return m_damageRule.Calculate(baseDamage, defense);
    }
}
```

## 전역 상태 금지

- Singleton 패턴과 변경 가능한 전역 `static` 상태를 사용하지 않습니다.
- 필요한 수명과 공유 범위는 명시적인 조립 지점에서 정하고 의존성으로 전달합니다.
- 씬 전환 데이터는 순수 DTO로 캡슐화하여 다음 씬의 Initializer 또는 동등한 진입점에 전달합니다.
- 기존 베이스의 `~DTO` 접미사는 호환 권장안입니다. 프로젝트가 별도 명명 규칙을 확정했다면 그 규칙을 우선합니다.

## 변경 승인과 서드파티 경계

- 전체 구현 계획에 대한 사용자의 명시적 승인 전에는 소스나 프로젝트 파일을 수정하지 않습니다.
- 일부 질문에 대한 답변이나 문서 코멘트는 전체 구현 승인으로 해석하지 않습니다.
- UPM 패키지와 에셋 스토어 원본은 직접 수정하지 않습니다. Wrapper, Adapter, 확장 메서드 또는 프로젝트 소유 패치 계층으로 격리합니다.
- 기존 주석과 문서의 내용을 이동할 때는 새 위치와 호환 경로를 남기며 조용히 삭제하지 않습니다.

## 패턴 선택 기준

| 목적 | 우선 검토 패턴 |
|---|---|
| 생성 책임 분리 | Factory Method, Abstract Factory, Builder |
| 반복 생성 비용 완화 | Object Pool, Prototype |
| 외부 API 격리 | Adapter, Facade, Proxy |
| 기능 조합 | Decorator, Strategy |
| 상태 전이 | State/FSM, 필요 시 Behavior Tree |
| 이벤트와 명령 전달 | Observer, Command |
| 공유 불변 데이터 | Flyweight, 프로젝트가 허용할 때 ScriptableObject |

패턴은 문제와 검증 가능한 이득이 있을 때만 채택합니다. 특정 패턴을 폴더명만으로 강제하지 않습니다.

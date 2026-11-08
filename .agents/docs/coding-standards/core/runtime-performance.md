# 런타임 성능 공통 규칙

> 성능 규칙은 프로파일링 증거를 우선합니다. 코드 모양만으로 비용을 단정하지 않습니다.

## 프레임 경로

- `Update`, `LateUpdate`, `FixedUpdate`와 고빈도 콜백에서 불필요한 관리 힙 할당, Boxing과 LINQ 열거 비용을 제한합니다.
- `new`가 항상 GC 할당을 뜻하지는 않습니다. 값 타입 생성과 JIT/AOT 최적화 차이를 고려하고 Unity Profiler의 GC Alloc으로 판정합니다.
- 컬렉션 결과가 필요하면 재사용 버퍼를 검토하고, 단순 순회는 프로파일러와 대상 런타임 결과를 근거로 `for` 또는 `foreach`를 선택합니다.
- 문자열 보간, 캡처 람다, 매 프레임 로그와 반복적인 컴포넌트 조회를 주의합니다.

```csharp
private readonly List<Enemy> m_aliveEnemies = new List<Enemy>();

private void Update()
{
    m_aliveEnemies.Clear();
    for (int i = 0; i < m_enemies.Count; i++)
    {
        Enemy enemy = m_enemies[i];
        if (enemy.IsAlive)
        {
            m_aliveEnemies.Add(enemy);
        }
    }
}
```

## 캐싱

- 고빈도 경로에서 반복 조회하는 컴포넌트, 변하지 않는 설정과 계산 결과는 수명과 무효화 조건이 명확할 때 캐싱합니다.
- 캐시가 오래된 참조를 보유하지 않도록 씬 전환, 파괴와 설정 변경 시점을 정의합니다.
- 측정되지 않은 캐시를 무분별하게 늘려 메모리와 상태 동기화 비용을 키우지 않습니다.

## 풀링

- 투사체, 이펙트, 데미지 텍스트처럼 반복 생성·파괴되는 객체는 측정 결과에 따라 Object Pool을 검토합니다.
- 반환 시 이벤트, 타이머, 트윈과 상태를 초기화합니다.
- 최대 용량, 풀 미스 정책과 씬 종료 시 정리를 정의합니다.
- 생성 빈도가 낮거나 객체가 큰 경우에는 풀의 상주 메모리가 더 비쌀 수 있으므로 적용하지 않을 수 있습니다.

## 측정 순서

1. 목표 플랫폼과 대표 씬에서 CPU, GPU, 메모리, GC 기준값을 기록합니다.
2. 병목 구간과 재현 조건을 고정합니다.
3. 한 번에 하나의 변경을 적용합니다.
4. 같은 조건으로 전후 수치를 비교하고 회귀를 확인합니다.
5. 이득이 없거나 부작용이 크면 변경을 롤백합니다.

렌더링 기법은 [조건부 렌더링 최적화](../optimization/rendering-techniques.md), 비동기와 트윈의 제품별 규칙은 각각 [비동기 프로필](../../profiles/async.md)과 [트윈 프로필](../../profiles/tween.md)을 따릅니다.


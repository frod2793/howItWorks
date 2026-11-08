# Unity 안전성 공통 규칙

## Fake Null

`UnityEngine.Object` 파생 객체는 파괴 뒤 관리 참조가 남아도 Unity의 오버로드된 비교에서는 null로 취급될 수 있습니다. 해당 객체에는 `?.`와 `??`가 Unity의 Fake Null 판정을 우회할 수 있으므로 명시적인 Unity null 비교를 사용합니다.

```csharp
if (m_targetObject != null)
{
    m_targetObject.SetActive(true);
}
```

일반 C# 객체에는 일반 null 연산자를 사용할 수 있습니다. 인터페이스 참조의 실제 구현이 `UnityEngine.Object`일 수 있다면 수명 계약을 확인합니다.

## 직렬화 변경

- `[SerializeField]` 또는 직렬화되는 public 필드의 이름을 바꿀 때 `[FormerlySerializedAs("이전이름")]`를 추가합니다.
- 타입 변경, 필드 삭제, 클래스·네임스페이스 이동 전에는 씬·프리팹·ScriptableObject의 역직렬화 영향을 확인합니다.
- 필드명을 연속 변경했다면 필요한 이전 이름을 모두 보존합니다.
- 직렬화 자산을 텍스트로 일괄 수정하기 전 백업과 Unity 재직렬화 검증 절차를 정합니다.

```csharp
using UnityEngine.Serialization;

[FormerlySerializedAs("m_hpBar")]
[SerializeField] private Slider m_healthSlider;
```

## 이벤트와 수명

- C# 이벤트, `UnityEvent`, 버튼 리스너와 메시지 버스 구독은 소유자의 활성·파괴 수명과 쌍을 맞춰 해제합니다.
- 등록이 `OnEnable`이면 해제는 `OnDisable`, 등록이 초기화 시 한 번이면 해제는 `OnDestroy` 또는 명시적 `Dispose`에서 수행합니다.
- 발행자가 구독자보다 오래 사는 경우 해제 누락은 참조 유지와 중복 호출을 만들 수 있습니다.
- 비동기 작업과 타이머에는 소유 수명에 연결된 취소 경로를 둡니다.

```csharp
private void OnEnable()
{
    m_button.onClick.AddListener(HandleClick);
}

private void OnDisable()
{
    if (m_button != null)
    {
        m_button.onClick.RemoveListener(HandleClick);
    }
}
```

## Inspector 참조

- 필수 참조는 초기화 시 검증하고 누락된 오브젝트와 컴포넌트 이름을 진단합니다.
- 런타임에 파괴될 수 있는 참조는 사용 직전에 Unity null 상태를 확인합니다.
- 필드 변경 후 Inspector, 씬, 프리팹 Variant와 런타임 생성 경로를 함께 확인합니다.

## 외부 코드

패키지와 에셋 원본 수정은 업데이트 시 덮어쓰기와 라이선스 문제를 만들 수 있습니다. 프로젝트 소유 Wrapper나 Adapter에 변경을 격리하고, 업그레이드 시 그 경계만 재검증합니다.


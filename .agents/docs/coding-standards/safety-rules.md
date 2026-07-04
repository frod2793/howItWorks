# 안전성 규칙 (Safety Rules)

> GEMINI.md §3.2~3.3 기반
> 이 문서는 Unity 특유의 안전성 이슈와 서드파티 정책을 정의합니다.

---

## 1. Fake Null 방지

### UnityEngine.Object의 특수한 null 동작

Unity의 `UnityEngine.Object` 파생 타입(GameObject, Component, MonoBehaviour 등)은 C#의 일반적인 null과 다른 **Fake Null** 상태를 가집니다. Destroy된 오브젝트는 C# 참조는 남아있으나 Unity 내부에서는 null로 취급됩니다.

### 널 조건부 연산자 절대 금지

`UnityEngine.Object` 파생 타입에는 `?.`(널 조건부)와 `??`(널 병합) 연산자를 **절대 사용하지 마십시오**:

```csharp
// ❌ 절대 금지 — Fake Null을 감지하지 못함
m_gameObject?.SetActive(true);           // Destroy된 오브젝트에서 동작 불예측
var obj = m_transform ?? defaultTransform; // Fake Null 상태 무시

// ✅ 올바른 예시 — 명시적 null 체크
if (m_gameObject != null)
{
    m_gameObject.SetActive(true);
}

if (m_transform != null)
{
    m_transform.position = targetPosition;
}
else
{
    m_transform = defaultTransform;
}
```

### 적용 범위

| 타입 | `?.` / `??` 사용 | 명시적 null 체크 |
|------|:---:|:---:|
| `UnityEngine.Object` 파생 | ❌ 금지 | ✅ 필수 |
| 일반 C# 클래스 (POCO) | ✅ 허용 | ✅ 허용 |
| 인터페이스 | ⚠️ 주의 | ✅ 권장 |

> **인터페이스 주의**: 인터페이스를 통해 참조하더라도 실제 구현체가 `UnityEngine.Object` 파생일 수 있으므로, 안전을 위해 명시적 null 체크를 권장합니다.

---

## 2. 직렬화 유실 방지

### FormerlySerializedAs

`[SerializeField]` 또는 `public` 필드의 이름을 변경할 때, 기존 직렬화 데이터가 유실되지 않도록 `[FormerlySerializedAs]`를 추가합니다:

```csharp
using UnityEngine.Serialization;

public class PlayerView : MonoBehaviour
{
    // 필드명 변경: m_hpBar → m_healthSlider
    [FormerlySerializedAs("m_hpBar")]
    [SerializeField] private Slider m_healthSlider;

    // 필드명 변경: m_nameLabel → m_playerNameText
    [FormerlySerializedAs("m_nameLabel")]
    [SerializeField] private TextMeshProUGUI m_playerNameText;
}
```

### 적용 기준

| 상황 | FormerlySerializedAs 필요 여부 |
|------|:---:|
| `[SerializeField]` private 필드 이름 변경 | ✅ 필수 |
| `public` 필드 이름 변경 | ✅ 필수 |
| 새 필드 추가 | ❌ 불필요 |
| 필드 삭제 | ❌ 불필요 (데이터 자동 무시) |
| 필드 타입 변경 | ⚠️ 주의 (호환 타입만 가능) |

---

## 3. 서드파티 정책

### 원본 코드 수정 금지

UPM 패키지나 에셋 스토어의 **서드파티 원본 코드는 직접 수정하지 않습니다**.

### 대응 방법

| 방법 | 용도 | 예시 |
|------|------|------|
| **래퍼(Wrapper)** | 서드파티 API를 감싸는 자체 클래스 | `AudioWrapper` → FMOD API 래핑 |
| **어댑터(Adapter)** | 인터페이스 변환 | `IInputAdapter` → Rewired ↔ Input System |
| **확장 메서드** | 기능 추가 | `DOTweenExtensions.FadeAndDisable()` |

```csharp
// ✅ 래퍼 패턴 예시
/// <summary>
/// [기능]: 서드파티 오디오 라이브러리를 래핑하는 어댑터
/// [작성자]: 윤승종
/// </summary>
public class AudioAdapter : IAudioService
{
    private readonly ThirdPartyAudioSystem m_audioSystem;

    public AudioAdapter(ThirdPartyAudioSystem audioSystem)
    {
        m_audioSystem = audioSystem;
    }

    public void PlaySfx(string clipName)
    {
        m_audioSystem.Play(clipName, AudioChannel.SFX);
    }

    public void StopAll()
    {
        m_audioSystem.StopAllChannels();
    }
}

// ✅ 확장 메서드 예시
public static class DOTweenExtensions
{
    public static Tween FadeAndDisable(this CanvasGroup canvasGroup, float duration)
    {
        return canvasGroup.DOFade(0f, duration)
                          .OnComplete(() => canvasGroup.gameObject.SetActive(false));
    }
}
```

### 서드파티 업데이트 대응

```
서드파티 업데이트 → 래퍼/어댑터만 수정 → 비즈니스 로직 영향 없음
```

이 구조를 통해 서드파티 변경이 프로젝트 전체로 전파되는 것을 방지합니다.

---

## 4. 기타 안전성 규칙

### UnityEvent vs C# Event

| 구분 | 사용 시기 |
|------|----------|
| `UnityEvent` | Inspector에서 시각적으로 연결할 때 |
| `Action` / `event Action` | 코드에서 동적으로 구독할 때 (권장) |

### null 체크 가이드라인

```csharp
// MonoBehaviour / UnityEngine.Object 파생
if (m_targetObject != null)                    // ✅ 명시적 체크
if (m_targetObject)                            // ✅ 허용 (implicit bool)

// 순수 C# 객체
if (m_service?.IsReady ?? false)               // ✅ 허용
var name = m_playerData?.Name ?? "Unknown";    // ✅ 허용
```

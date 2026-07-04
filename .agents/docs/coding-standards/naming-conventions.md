# 네이밍 규칙 (Naming Conventions)

> GEMINI.md §3.1, §3.5, §3.6 기반
> 이 문서는 프로젝트의 모든 코드 식별자, 주석, 로그에 적용되는 네이밍 규칙을 정의합니다.

---

## 1. 식별자 네이밍

### 필드 & 프로퍼티

| 유형 | 규칙 | 예시 |
|------|------|------|
| Private 필드 | `m_` 접두사 + camelCase | `m_playerData`, `m_currentHealth` |
| Public 프로퍼티 | PascalCase | `PlayerLevel`, `MaxHealth` |
| Public 메서드 | PascalCase | `TakeDamage()`, `Initialize()` |
| Private 메서드 | PascalCase | `CalculateDamage()` |
| 로컬 변수 | camelCase | `damageAmount`, `targetEnemy` |
| 상수 | PascalCase 또는 UPPER_SNAKE | `MaxPlayerCount`, `MAX_RETRY` |
| 매개변수 | camelCase | `targetPosition`, `damageValue` |

### 특수 접두사/접미사

| 유형 | 규칙 | 예시 |
|------|------|------|
| 인터페이스 | `I` 접두사 | `IMovable`, `IDamageable`, `IViewModel` |
| DTO 클래스 | `~DTO` 접미사 | `PlayerStatsDTO`, `SceneTransitionDTO` |
| Bool 변수 | `is`, `has`, `can` 접두사 | `m_isDead`, `m_hasWeapon`, `m_canMove` |
| UI 이벤트 콜백 | `func_` 접두사 | `func_OnStartButtonClick()`, `func_OnSettingsOpen()` |

### UI 이벤트 콜백 상세

Inspector에서 `Button.OnClick()` 등에 직접 연결하는 public 메서드:

```csharp
// ✅ 올바른 예시
public void func_OnStartButtonClick()
{
    m_viewModel.StartGame();
}

public void func_OnSettingsOpen()
{
    m_viewModel.OpenSettings();
}

// ❌ 잘못된 예시
public void OnStartClick()     // func_ 접두사 누락
public void StartGame()        // 이벤트 콜백인지 구분 불가
```

---

## 2. 코드 포맷팅

### 중괄호 스타일 — Allman Style

중괄호는 항상 **새 줄**에서 시작합니다:

```csharp
// ✅ Allman Style (필수)
if (m_isDead)
{
    HandleDeath();
}
else
{
    TakeDamage(damage);
}

// ❌ K&R Style (금지)
if (m_isDead) {
    HandleDeath();
} else {
    TakeDamage(damage);
}
```

### 들여쓰기

- **4개의 공백(Space)** 사용
- 탭(Tab) 사용 금지

### 중괄호 생략 금지

모든 `if`, `else if`, `else`, `for`, `while` 문에는 로직이 단 한 줄이더라도 **예외 없이** 중괄호를 사용합니다:

```csharp
// ✅ 올바른 예시
if (m_isDead)
{
    return;
}

for (int i = 0; i < m_enemies.Count; i++)
{
    m_enemies[i].Update();
}

// ❌ 잘못된 예시
if (m_isDead) return;

for (int i = 0; i < m_enemies.Count; i++)
    m_enemies[i].Update();
```

---

## 3. using 지시문 활용

### 적극적 사용 원칙

파일 최상단에 `using` 지시문을 명시하고, 본문 내에서는 클래스명을 간결하게 호출합니다:

```csharp
// ✅ 권장
using UnityEngine.SceneManagement;

// 본문
SceneManager.LoadScene("GameScene");

// ❌ 금지
// 본문 내 전체 경로 반복
UnityEngine.SceneManagement.SceneManager.LoadScene("GameScene");
```

### 정적 유틸리티 활용

```csharp
// 자주 사용하는 정적 클래스
using static UnityEngine.Mathf;

// 본문 내 직접 호출
float clamped = Clamp(value, 0f, 1f);
```

### 타입 별칭 활용

```csharp
// 긴 제네릭 타입 축약
using PlayerList = System.Collections.Generic.List<PlayerData>;
using EnemyDict = System.Collections.Generic.Dictionary<string, EnemyData>;
```

---

## 4. 주석 및 리전 (#region)

### #region 적극 사용

`#region`으로 코드 섹션을 명확히 구분하며, 리전 이름은 **한글**로 작성합니다:

```csharp
#region UI 참조 (Inspector)
[SerializeField] private Button m_startButton;
[SerializeField] private TextMeshProUGUI m_scoreText;
#endregion

#region 내부 필드 (Private Fields)
private PlayerViewModel m_viewModel;
private bool m_isInitialized;
#endregion

#region 유니티 생명주기 (Unity Lifecycle)
private void Awake() { /* ... */ }
private void OnDestroy() { /* ... */ }
#endregion

#region 초기화 (Initialization)
public void Initialize(PlayerViewModel viewModel) { /* ... */ }
#endregion

#region 공개 메서드 (Public Methods)
public void UpdateScore(int score) { /* ... */ }
#endregion

#region 이벤트 핸들러 (Event Handlers)
private void OnScoreChanged(int newScore) { /* ... */ }
#endregion
```

### 권장 리전 목록

| 리전 이름 | 용도 |
|----------|------|
| `#region UI 참조 (Inspector)` | `[SerializeField]` 필드 |
| `#region 내부 필드 (Private Fields)` | private 필드 |
| `#region 유니티 생명주기 (Unity Lifecycle)` | Awake, Start, OnDestroy 등 |
| `#region 초기화 (Initialization)` | 초기화 메서드 |
| `#region 공개 메서드 (Public Methods)` | public 메서드 |
| `#region 이벤트 핸들러 (Event Handlers)` | 이벤트 콜백 |

### 기존 주석 보존

기존 코드에 이미 존재하는 주석이나 `#region` 블록은 **절대 삭제하거나 훼손하지 않습니다**.

---

## 5. 로그 작성 규칙

### 한글 로그 강제

모든 `Debug.Log` 메시지는 `[클래스명]` 접두사를 포함하여 한글로 작성합니다:

```csharp
// ✅ 올바른 예시
Debug.Log($"[PlayerController] 플레이어가 데미지를 입었습니다: {damage}");
Debug.LogWarning($"[InventoryService] 인벤토리가 가득 찼습니다. 최대 용량: {m_maxCapacity}");
Debug.LogError($"[SceneLoader] 씬 로드에 실패했습니다: {sceneName}");

// ❌ 잘못된 예시
Debug.Log("Player took damage: " + damage);      // 영어, 클래스명 누락
Debug.Log($"Damage: {damage}");                   // 영어, 클래스명 누락
Debug.Log($"[PlayerController] Took damage");     // 영어 메시지
```

---

## 6. XML 문서 주석

### 파일/클래스 헤더

```csharp
/// <summary>
/// [기능]: 플레이어의 전투 관련 데이터를 관리하는 모델 클래스
/// [작성자]: 윤승종
/// </summary>
public class PlayerCombatModel
{
    // ...
}
```

### 메서드 헤더

```csharp
/// <summary>
/// [기능]: 지정된 데미지만큼 플레이어의 체력을 감소시킵니다.
/// [작성자]: 윤승종
/// [수정 날짜]: 2026-07-02
/// [마지막 수정 작성자]: 윤승종
/// [수정 내용]: 방어력 계산 로직 추가
/// </summary>
/// <param name="damage">적용할 데미지 량</param>
/// <returns>실제 적용된 데미지 량</returns>
public int TakeDamage(int damage)
{
    // ...
}
```

# 네이밍·문서화 공통 규칙

> 실제 값은 `project-profile.conf`가 결정합니다. 아래 기존 값은 새 프로필을 만들 때의 기본 제안이며, 프로젝트 고유 규칙으로 교체할 수 있습니다.

## 프로필이 결정하는 값

| 프로필 키 | 허용 값 또는 형식 | 기존 베이스의 제안값 |
|---|---|---|
| `private_field_prefix` | 텍스트 | `m_` |
| `ui_callback_prefix` | 텍스트 | `func_` |
| `response_language` | `ko`, `en`, `project_default` | `ko` |
| `log_language` | `ko`, `en`, `project_default` | `ko` |
| `author_name` | 텍스트 | `윤승종` |
| `region_policy` | `required`, `encouraged`, `disabled` | `encouraged` |
| `xml_documentation_policy` | `all_methods`, `public_api`, `disabled` | `all_methods` |

`m_`, `func_`, 한글 응답·로그와 `윤승종`은 하네스의 기본 제안값이지 감지되지 않은 프로젝트에 대한 고정 사실이 아닙니다. 에이전트 이름을 사람 작성자로 기재해서는 안 되며, 확정된 `author_name`을 사용합니다.

## 식별자 기본안

프로젝트에 별도 규칙이 없을 때 다음 호환 기본안을 제안합니다.

| 유형 | 기본안 | 예시 |
|---|---|---|
| private 필드 | `private_field_prefix` + camelCase | `m_playerData` |
| public 타입·프로퍼티·메서드 | PascalCase | `PlayerLevel`, `TakeDamage()` |
| 지역 변수·매개변수 | camelCase | `damageAmount` |
| 인터페이스 | `I` 접두사 | `IDamageable` |
| DTO | `DTO` 접미사 | `SceneTransitionDTO` |
| bool | `is`, `has`, `can` 계열 | `m_isDead` |
| Inspector UI 콜백 | `ui_callback_prefix` | `func_OnStartButtonClick()` |

UI 콜백 접두사는 Inspector에서 직접 연결되는 public 메서드를 일반 도메인 명령과 구분하기 위한 제안입니다. 코드에서만 구독하는 핸들러에는 프로젝트의 일반 이벤트 명명 규칙을 적용합니다.

## 포맷과 using 호환 지침

- 프로젝트 포매터나 `.editorconfig`가 있으면 그것을 우선합니다.
- 별도 규칙이 없을 때 기존 베이스는 Allman Style, 공백 4칸, 제어문 중괄호 생략 금지를 제안합니다.
- 반복되는 완전 수식 이름보다 명확한 `using`, `using static`, 타입 별칭을 사용하되 이름 충돌을 숨기지 않습니다.
- 기존 주석과 `#region`은 목적 없이 삭제하지 않습니다.
- 주석과 코드 파일(소스, 셰이더, 스크립트, 코드 내 문자열·로그 포함)에 이모지를 쓰지 않습니다. 기존 이모지를 발견하면 변경 범위 안에서 텍스트로 바꿉니다.

## 리전 정책

- `required`: 프로젝트가 정한 섹션에 리전을 작성하고 검사합니다.
- `encouraged`: 긴 Unity View나 수명주기 코드에서 가독성에 도움이 될 때 사용합니다.
- `disabled`: 새 리전을 만들지 않으며 기존 리전은 별도 승인 없이 제거하지 않습니다.

기존 베이스의 `UI 참조 (Inspector)`, `내부 필드 (Private Fields)`, `유니티 생명주기 (Unity Lifecycle)`, `초기화 (Initialization)`, `공개 메서드 (Public Methods)`, `이벤트 핸들러 (Event Handlers)`는 `encouraged`일 때 사용할 수 있는 예시입니다.

## 로그 규칙

- 로그 언어는 `log_language`를 따릅니다. `project_default`이면 기존 프로젝트 로그의 주 언어를 따릅니다.
- 기존 베이스는 `[클래스명] 메시지` 형식을 제안합니다.
- 민감 정보, 인증 토큰과 불필요한 매 프레임 로그를 남기지 않습니다.

```csharp
Debug.Log($"[PlayerController] 플레이어가 데미지를 입었습니다: {damage}");
```

## XML 문서 정책

- `all_methods`: 클래스와 모든 메서드에 프로젝트 템플릿의 XML 문서를 작성합니다.
- `public_api`: 외부에 노출되는 타입과 public/protected API를 문서화합니다.
- `disabled`: XML 문서를 강제하지 않되 복잡한 계약과 안전상 주의는 일반 문서로 남깁니다.

기존 베이스의 `[기능]`, `[작성자]`, `[수정 날짜]`, `[마지막 수정 작성자]`, `[수정 내용]` 항목은 `all_methods` 기본 제안입니다. 적용 시 작성자에는 `author_name`을 사용합니다.

테스트 소스(`Tests`·`Test` 경로 또는 `[UnityTest]`·NUnit·TestRunner 마커)는 테스트 이름 자체가 명세 역할을 하므로 정책 값과 무관하게 `DOC001` 검사에서 제외합니다. 프로덕션 코드의 문서화 정책은 변하지 않습니다.

### 클래스 XML 기본 예시

아래 `윤승종`은 예시 프로필의 `author_name` 기본 제안값입니다. 확정 프로필의 값이 다르면 그 값을 사용합니다.

```csharp
/// <summary>
/// [기능]: 플레이어의 전투 관련 데이터를 관리합니다.
/// [작성자]: 윤승종
/// </summary>
public class PlayerCombatModel
{
}
```

### 메서드 XML 기본 예시

```csharp
/// <summary>
/// [기능]: 지정된 피해량을 플레이어에게 적용합니다.
/// [작성자]: 윤승종
/// [수정 날짜]: YYYY-MM-DD
/// [마지막 수정 작성자]: 윤승종
/// [수정 내용]: 피해 적용 규칙을 기록합니다.
/// </summary>
public void ApplyDamage(int damage)
{
}
```

# NULLOVE 기(起) 단계 분기 및 시스템 리팩토링 상세 작업 내역서

본 문서는 **"HowItWorks"** 프로젝트의 인게임 대사 시스템 연출 버그 수정, 텍스트 가독성 최적화, OCP(개방-폐쇄 원칙) 기반 캐릭터 이미지 연동, 그리고 데이터 주도형(Data-Driven) 선택지 분기 시스템 구축에 대한 상세 설계 및 변경 이력을 기술합니다.

---

## 1. 작업 개요

- **목적**: 기(起) 단계 씬 1~3의 테스트와 대사 진행, 선택지 연동을 위한 시스템 고도화 및 버그 척결.
- **작성자**: 윤승종
- **작성일**: 2026-06-19
- **핵심 아키텍처 원칙**: SOLID(OCP/DIP), Data-Driven, MVVM, Zero-Allocation, Unity Safety.

---

## 2. 세부 시스템 개선 내역

### 2.1. 대사 및 UI 가독성 개선
#### [씬 정보 메타데이터 파싱 및 분리]
- **기존 문제**: 대사 지문 앞부분에 포함되던 `[씬 씬코드: 씬제목]` 문자열이 대사창 내용물에 그대로 노출되어 UI 레이아웃을 해치고 몰입감을 깨뜨리는 버그가 있었습니다.
- **해결 방안**: [DialogueFlowController.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/InGame/Core/DialogueFlowController.cs)의 `PlayDialogueAtIndex` 진입점에서 정규식을 사용하여 메타데이터를 파싱하고 본문에서 제거했습니다.
  - **정규식 패턴**: `^\[씬\s*([^\]:]+?)\s*:\s*([^\]]+?)\]\s*[\r\n]*`
  - **작동 방식**: 매칭 성공 시 씬 코드(예: `씬1-A`)에서 숫자만 추출해 씬 번호(`sceneNum`)를 연산하고, 씬 번호 범위에 따라 장(`ActName`) 정보(`1~3`: 기(起), `4~8`: 승(承), `9~12`: 전(轉), `13~`: 결(結)) 및 시간대(`timeOfDay`)를 동적 연산하여 `ISceneInfoViewModel.UpdateSceneInfo`로 갱신한 뒤, 본문 내용은 `content.Substring(match.Length)`를 통해 분리된 대사만 출력합니다.

#### [시스템 메시지 텍스트 겹침 현상 해결]
- **기존 문제**: `InGameDialogueView.cs`에서 시스템 메시지(`DialogueType.SystemMessage`)를 출력할 때, 텍스트 필드에 `<mspace=16px>` 서식이 인라인으로 삽입되어 텍스트가 겹쳐서 알아볼 수 없는 문제가 발생했습니다.
- **해결 방안**: [InGameDialogueView.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/InGame/Dialogue/InGameDialogueView.cs)의 `UpdateDialogue` 메서드를 수정하여 시스템 메시지일 경우 타이프라이터 효과를 중지하고 서식 태그 없이 순수 텍스트 데이터를 즉시 화면에 표출하여 가독성을 온전히 확보했습니다.

#### [괄호 연출 지문의 나레이션 강제 전환 및 대사 제외]
- **기존 문제**: `(없음. 이 장면에는 대사가 없다. 침묵 자체가 대사다.)` 처럼 괄호로 이루어진 지문이 일반 대사(`DialogueType.Normal`) 데이터로 들어올 경우, 대사창 상에 화자의 이름 상자가 뜬 상태에서 지문이 출력되어 인물의 발화 대사인지 연출용 침묵 묘사인지 구분되지 않는 연출 버그가 있었습니다. 또한 연출 지시문이 대사 텍스트로 화면에 그대로 출력되어 가독성을 저해했습니다.
- **해결 방안**: [DialogueFlowController.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/InGame/Core/DialogueFlowController.cs)에서 대사 씬 정보 제거 후, 텍스트를 공백 제거한 상태(`trimmedContent`)가 `(`로 시작하고 `)`로 끝나는지 검사하여 이에 해당하는 경우 `parsedType`을 강제로 `DialogueType.Narration`으로 변환 처리하고, `content` 값을 완전히 빈 문자열(`""`)로 설정하여 대사창 출력 텍스트에서 완전히 배제하도록 설계했습니다.
- **기대 효과**: 화자가 설정되어 있더라도 괄호 지문일 시 나레이션 판정을 받아 대사창 내 이름 박스와 캐릭터 아이콘이 자동으로 비활성화되고, 연출 지문 텍스트가 대사창에 전혀 표시되지 않아 순수하게 화면(배경, 캐릭터 스프라이트 페이드)만 묘사되는 완벽한 침묵 연출 상태를 유지합니다.

#### [선택지 카드 UI 미출력 및 비율 왜곡 버그 수정 (CanvasGroup 제어)]
- **기존 문제**: 대사 진행 중 선택지 카드가 노출되지 않던 버그와, 이를 자식 활성화 방식으로 임시 수정했을 때 선택지 개수(예: 2개)에 따라 가로 비율이 좌우로 비정상적으로 거대해져 UI 레이아웃이 깨지던 중대 결함을 해결했습니다.
- **원인 분석**: `InGameDialogueOptionCardView_Group` 부모의 `HorizontalLayoutGroup`은 자식 오브젝트 중 활성화(`activeSelf == true`) 상태인 요소만 기준으로 폭을 쪼갭니다. 따라서 선택지가 2개일 때 3~4번 카드를 `SetActive(false)` 해버리면 남은 1~2번 카드가 가로 50%씩 강제 팽창하여 비율이 왜곡되었습니다.
- **해결 방안**:
  - `InGameDialogueOptionsManager.cs`에서 모든 자식 카드의 `gameObject.SetActive(true)` 상태를 항시 보장하여 유니티 엔진이 4분할 그리드(각 25% 가로폭)를 유지하게 강제했습니다.
  - `InGameDialogueOptionCardView.cs`에 `Hide()` 메서드를 추가하고 내부 `CanvasGroup` 컴포넌트의 투명도를 `alpha = 0f`, 상호작용 검출을 `blocksRaycasts = false`, `interactable = false`로 설정하여 미사용 카드가 투명해지고 클릭이 무시되도록 격리했습니다.
- **결과**: 기획서 의도대로 선택지가 2개 혹은 3개만 존재하더라도 버튼 카드 크기가 찌그러지거나 팽창하지 않고 4분할 당시의 컴팩트한 규격을 그대로 유지하면서 정밀하게 렌더링됩니다.

#### [선택지 내부 텍스트 글자 겹침 버그 수정 (에디터 단 사전 배치)]
- **기존 문제**: 선택지 버튼 카드 내에서 타이틀 텍스트와 세부 설명 텍스트가 서로의 영역을 덮고 완전히 겹쳐서 출력되어 텍스트 판독이 불가능한 현상이 있었습니다.
- **원인 분석**: 씬 내 각 `DialogueOptionCard` 하위 자식 오브젝트인 `Text (TMP)_title`와 `Text (TMP)_descriptionText`의 `localPosition` y축 좌표가 완전히 동일하게 세팅되어 있어 글자가 겹쳐 렌더링되었습니다.
- **해결 방안**: 코드 상에서 컴포넌트를 동적으로 생성하는 지저분한 방식을 배제하고, 유니티 에디터(씬 하이어라키) 내의 `DialogueOptionCard_1~4` (ID: 48764, 48742, 49030, 49416) 오브젝트에 직접 **`VerticalLayoutGroup` 컴포넌트를 에디터 단에서 수동 추가 및 배치**했습니다.
  - 패딩(`RectOffset(20, 20, 20, 20)`) 및 간격(`spacing = 15f`), 정렬(`MiddleCenter`) 속성을 에디터 프리셋으로 세팅한 뒤 씬을 저장하여, 텍스트가 상하로 정돈되도록 버그를 최종 해결했습니다. (InGameDialogueOptionCardView.cs의 Awake는 복원하여 코드의 순수성을 보존했습니다.)

#### [Line Progress Text 실시간 동적 연동]
- **기존 문제**: 대사는 계속 흘러가는데 화면 하단 구석에 진행 상황을 알려주는 진행률 텍스트(`Line_Progress_Text`)가 최초값 그대로 멈춰서 갱신되지 않는 오류가 있었습니다.
- **해결 방안**: DTO와 뷰모델, 뷰 간의 단방향 데이터 바인딩(MVVM)을 완성했습니다.
  - `InGameDTOs.cs`의 `DialogueDTO` 내에 `CurrentLine`(현재 라인) 및 `TotalLines`(전체 라인) 정수 필드를 추가했습니다.
  - `DialogueFlowController.cs`에서 다음 대사를 화면에 송출할 때 `CurrentLine = index + 1`, `TotalLines = m_loadedDialogues.Count` 데이터를 주입하여 전달합니다.
  - `InGameDialogueView.cs`의 `UpdateDialogue` 콜백에서 `m_lineProgressText != null` 검사 통과 시 `m_lineProgressText.text = $"{dialogue.CurrentLine} / {dialogue.TotalLines}";` 연산으로 문자열을 대입하여 대사가 흘러감에 따라 실시간으로 동적 갱신되도록 연동했습니다.

#### [선택지 버튼 크기 및 레이아웃 제어 정책]
- **개발 정책**: 코드 단에서 선택지 버튼의 물리적 크기나 위치 좌표를 조절하는 하드코딩 요소를 배제하고, 원본 씬에 배치된 `HorizontalLayoutGroup` 및 `RectTransform` 자동 레이아웃 엔진의 크기 제어 방식을 그대로 사용하여 해상도 대응성과 유연성을 완벽하게 보장합니다.

#### [기능 테스트를 위한 대사 분량 단축 설정]
- **설정 변경**: 첫 번째 핵심 선택 분기점인 49번 "노인과의 눈맞춤"에 빠르게 도달하여 상호작용 및 자원 가산을 신속히 테스트할 수 있도록, 대사 시작 지점(`m_currentDialogueIndex`)을 48번 대사로 설정했습니다. 이에 따라 한 번의 클릭/터치만으로 선택지 카드 UI를 즉시 호출해 볼 수 있는 고속 검증 경로가 마련되었습니다.

---

## 2.2. 캐릭터 이미지 연동 및 OCP 설계 전환
#### [캐릭터 원화 이미지 생성 및 에셋 파이프라인 구축]
- **생성 에셋**: 연출에 사용할 핵심 캐릭터 4종(주인공, 아라, 제이, 교사)의 리얼 일러스트 스프라이트를 생성하여 다음 경로에 배치했습니다.
  - `Assets/Game/Resources/Sprites/Characters/`
  - 에디터 임포터 설정을 통해 스프라이트 2D 모드로 포맷 변환 및 셋업을 완료했습니다.
- **OCP 기반 컴포넌트 리팩토링**:
  - 캐릭터가 추가될 때마다 필드를 새로 추가하고 코드를 수정해야 했던 구조에서 탈피하기 위해 [InGameCharacterView.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/InGame/Dialogue/InGameCharacterView.cs)를 수정했습니다.
  - `CharacterSpriteMap` 구조체 리스트(`List<CharacterSpriteMap> m_characterSpriteMaps`)를 선언하여 인스펙터 에셋 대입 방식으로 전환했습니다.
  - 가비지 컬렉터(GC) 할당 방지를 위해 `foreach` 대신 `for` 루프를 적용하여 성능 오버헤드를 줄였습니다.
  - **DOTween 페이드 효과 적용**: `FadeInImage` 및 `FadeOutImage` 헬퍼 메서드를 통해 `DOFade`를 0.3초간 적용하여 부드러운 이미지 전환과 비활성화를 처리합니다.
  - 에디터 스크립트를 사용해 씬 내부의 비활성화된 `InGameCharacterView` 컴포넌트를 수집하여 4종 캐릭터의 매핑 정보를 직렬화 필드에 자동 입력 및 세이브 완료했습니다.

---

## 2.3. 데이터 기반(Data-Driven) 선택지 시스템 구축
- **핵심 목표**: 다수의 분기점과 선택지를 코드 수정 없이 확장할 수 있도록 선택지 데이터 구조를 완전히 데이터화 및 격리합니다.

```
[동작 프로세스 단방향 흐름]
DialogueFlowController.PlayNextDialogue() 
  ↓ (현재 인덱스가 choices_data.json의 TriggerDialogueIndex와 일치하는지 검사)
DialogueChoice UI 호출 (화면에 카드 형태로 선택지 렌더링)
  ↓ (사용자가 특정 카드 선택)
DialogueFlowController.HandleChoiceSelected(ChoiceId)
  ↓ (선택 결과 DTO 갱신 및 자원/감정 수치 누적 계산)
ApplyChoiceResult(ChoiceResultDTO) ──> NextDialogueIndex로 대사 포인터 점프 및 피드백 출력
```

#### [DTO 설계 명세 ([InGameDTOs.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/02_Domain/InGame/InGameDTOs.cs))]
- **`ChoiceResultDTO`**: 선택 후 게임 상태 변화 정보를 가지는 객체
```csharp
[Serializable]
public class ChoiceResultDTO
{
    public int NextDialogueIndex;     // 선택 후 이동할 대사 인덱스
    public int CatoDelta;             // 카토 소지량 변동폭
    public int MonitoringDelta;       // 감시도 변동폭
    public int CuriosityDelta;        // 호기심 변동폭
    public int ConfusionDelta;        // 혼란 변동폭
    public int FearDelta;             // 공포 변동폭
    public int SadnessDelta;          // 슬픔 변동폭
    public int JoyDelta;              // 기쁨 변동폭
    public string FeedbackMessage;    // 선택 후 출력할 시스템 피드백 텍스트
    public string ItemRewardKey;      // 획득 시 제공할 아이템 키값 (예: ITEM_STRAW_DOLL)
}
```
- **`GameChoiceDTO`**: 개별 선택지 카드 정보
```csharp
[Serializable]
public class GameChoiceDTO
{
    public int ChoiceId;
    public string Title;
    public string Subtitle;
    public string Description;
    public string Condition;
    public bool IsLocked;
    public string ColorType;
    public ChoiceResultDTO Result;
}
```
- **`ChoiceTriggerDTO`**: 대사 인덱스 매칭을 위한 컨테이너 DTO
```csharp
[Serializable]
public class ChoiceTriggerDTO
{
    public int TriggerDialogueIndex;
    public List<GameChoiceDTO> Choices;
}
```

#### [JSON 데이터 스키마 설계 ([choices_data.json](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/StreamingAssets/Data/choices_data.json))]
- 씬 1~3 내부의 4대 핵심 분기 선택지를 다음과 같이 정의하여 연동했습니다.

| 대사 인덱스 | 분기 명칭 | 선택지 ID | 선택지 제목 (Title) | 분기별 피드백 및 결과 데이터 |
| :--- | :--- | :--- | :--- | :--- |
| **49** | **눈맞춤 분기** | 101<br>102 | 시선을 피한다<br>고개를 끄덕인다 | - 101: 카토 소지 변동 없음, 대사 50번 이동<br>- 102: 호기심+1, 혼란+1, 대사 50번 이동 |
| **55** | **짚인형 분기** | 201<br>202 | 받는다<br>뒤로 물러난다 | - 201: 호기심+1, `ITEM_STRAW_DOLL` 아이템 획득<br>- 202: 변동 없음, 대사 56번 이동 |
| **58** | **카토 복용 분기** | 301<br>302 | 카토를 먹는다<br>카토를 내려놓는다 | - 301: 카토 소지량 -1, 65번 이동 (아침 기상)<br>- 302: 감시도+1, 59번 이동 (꿈 시퀀스 진입) |
| **73** | **이탈 분기** | 401<br>402 | 학교로 간다<br>야만인 구역으로 간다 | - 401: 최초 씬(인덱스 0)으로 리다이렉트 (루프 반복)<br>- 402: 혼란+1, 공포+2, 74번 이동 (최초 규칙 이탈) |

---

### 2.4. 멀티탭 설정화면(Settings Panel) 구성 및 볼륨 연동
#### [사운드 시스템 고도화 및 PlayerPrefs 연동]
- **BGM/SFX 볼륨 마스터 제어**: [ISoundService.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/01_Core/Sound/ISoundService.cs) 및 [SoundService.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/01_Core/Sound/SoundService.cs)에 마스터, BGM, SFX, 보이스 음량에 대한 개별 접근자 프로퍼티와 제어 메서드를 추가하고, 재생 시 최종 볼륨에 연산 곱을 적용하도록 개선했습니다.
- **영구 저장 및 자동 로드**: `Awake()` 시 로컬 저장소(`PlayerPrefs`)에서 볼륨 데이터 및 윈도우 비활성 시 음소거 설정을 로드하고, 적용 시점에 `SaveSettings()`를 통해 영구 저장합니다.
- **포커스 감지 음소거**: 윈도우 비활성화 시 자동 음소거 여부를 토글 스위치와 바인딩하고, Unity의 `OnApplicationFocus(bool hasFocus)` 라이프사이클을 통해 `AudioListener.pause = !hasFocus`를 처리합니다.

#### [설정 모듈 MVVM 설계]
- **ViewModel 구현**: [SettingsViewModel.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/Settings/SettingsViewModel.cs)는 볼륨 조절 슬라이더 드래그 중에는 실시간 사운드 피드백을 전달하되, "취소" 시에는 최초 백업 데이터로 사운드 상태를 롤백(Rollback)하는 견고한 트랜잭션 백업 로직을 탑재했습니다.
- **View 구현**: [SettingsView.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/Settings/SettingsView.cs)는 오디오 탭 내의 슬라이더(0~100) 및 토글 컴포넌트를 ViewModel 속성과 단방향 연동하며, 사이드바 버튼 클릭 시 해당하는 탭 콘텐츠 패널이 활성화되는 탭 전환 구조를 가지고 있습니다.
- **타이틀 씬 통합**: [TitleViewModel.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/Title/TitleViewModel.cs)의 환경설정 버튼 클릭 이벤트를 신규 `OnRequestSettings`와 연동하고, [TitleLifetimeScope.cs](file:///e:/Unity_workSpace/Projects/howItWorks/Assets/Game/Scripts/03_Features/Title/TitleLifetimeScope.cs)에서 의존성 바인딩을 마쳐 `SettingsView`의 `func_Open()`이 호출되도록 설계했습니다.

### 2.5. 대사 백로그(Backlog) 시스템 구축 및 스크롤 뷰 레이아웃 개선
- **목적**: 인게임 진행 도중 사용자가 `LOG_Button` 또는 `Tab` 키를 누르면 이전 대사 내역(화자 이름, 대화 내용, 분기 영향 여부)을 팝업 형태로 조회할 수 있도록 함.
- **핵심 아키텍처 (MVVM & DTO)**:
  - **`BacklogItemDTO`**: 화자 명칭, 대화 내용, 분기 영향 여부를 담는 데이터 전송용 DTO 정의.
  - **`BacklogViewModel`**: `DialogueViewModel.OnDialogueUpdated` 이벤트를 구독하여 실시간으로 발화된 대사를 내부 DTO 리스트에 수집하고 누적. `choices_data.json` 데이터 상에 정의된 `TriggerDialogueIndex`와 현재 대사 인덱스를 비교하여 분기점 직전의 대사에 `HasBranchEffect = true` 마크업 적용.
  - **`BacklogView`**: 팝업 렌더링 시점에 누적된 DTO 목록을 복제 생성하여 UI 갱신.
- **ScrollRect 아이템 찌그러짐 및 앵커 잠금 버그 해결 (에디터 사전 세팅)**:
  - **현상**: 스크롤 뷰 `Content` 하위의 `ItemPrefab` 복제 시 가로 앵커가 `(0, 0)`으로 초기화되고 마진이 비틀려 가로 영역이 극도로 축소되며 텍스트가 뭉개지는 현상 발생. 부모의 `Vertical Layout Group`에 의해 에디터에서 자식의 앵커 변경이 차단(Lock)됨.
  - **해결 방안**: `ItemPrefab`을 레이아웃 그룹 간섭 밖인 `BacklogPanel` 바로 하위 계층으로 이동시켜 앵커 잠금을 강제 해제함. 앵커를 가로 Stretch `(0, 1) ~ (1, 1)`, 좌우 오프셋 `0f`, 기본 세로 높이 `80f`로 설정한 뒤 씬(`InGame.unity`) 파일에 영구 저장함.
  - **코드 롤백 및 안정성**: `BacklogView.cs`에 추가했던 임시 런타임 RectTransform 보정 로직을 완전 삭제하여 씬 디자인과의 의존성을 배제했으며, 유니티 Fake Null 방지를 위해 삼항 연산자를 이용한 안정성 널체크 구조로 개편함.

---

## 3. 연출 대사 제외 계획 (Staging Direction Exclusion Plan)

기획 설계서 및 원본 대사 스크립트 중 대사창 텍스트로 사용자에게 노출되지 않고 순수 배경/사운드 연출 및 타이밍 제어용으로만 소비해야 하는 연출 괄호 지문들의 정의와 필터링 목록입니다.

### 3.1. 연출 제외 텍스트 분류 체계
1. **대괄호 형태 연출 노티스** (`[^\]]+` 패턴):
   - **`[비주얼]`**: 그래픽 페이드, 화면 흔들림, 색조 변환 등 (예: *[비주얼] 화면 완전히 검은 상태*)
   - **`[카메라]`**: 카메라 앵글 및 포커스 지시문 (예: *[카메라] 천장 시점에서 시작*)
   - **`[사운드]`**: 음향 효과 및 BGM 교체 타이밍 (예: *[사운드] 알람음 -> 일제히 이불 젖히는 소리*)
   - **`[연출 의도]`**: 기획자나 연출가의 연출 의도 지침 (예: *[연출 의도] 플레이어에게 이상함을 직접 말하지 않는다*)
2. **소괄호 형태 침묵/행동 지시문** (`\(.+?\)` 패턴):
   - 대화 내의 인물이 직접 발화하지 않는 정적 묘사 (예: *(없음. 이 장면에는 대사가 없다. 침묵 자체가 대사다.)*)

### 3.2. 대사 텍스트 실시간 제외 처리 규칙
- 대사 데이터를 화면에 표출하기 직전, 대화내용 트리밍 값의 형태에 따라 아래와 같이 제외 필터링을 가동합니다.

```
                  대사 텍스트 로드
                        │
                        ▼
            ┌───────────────────────┐
            │   [씬 정보] 헤더가    │  ── Yes ──> 씬 헤더 제거 후 ISceneInfoVM에
            │    존재하는가?        │             씬 메타데이터 갱신
            └───────────────────────┘
                        │ No
                        ▼
            ┌───────────────────────┐
            │  소괄호 ( ... ) 로    │  ── Yes ──> 대사창 텍스트 내용물 content = "" 변경
            │  둘러싸인 연출인가?    │             및 DialogueType.Narration 강제 변환
            └───────────────────────┘
                        │ No
                        ▼
            ┌───────────────────────┐
            │  대괄호 [ ... ] 로    │  ── Yes ──> 대사창 텍스트 내용물 content = "" 변경
            │  시작하는 연출인가?    │             및 해당 연출 플래그 발생 (추후 구현)
            └───────────────────────┘
                        │ No
                        ▼
                  일반 대사 출력
```

---

## 4. 포스트 구현 가이드 (Post-Implementation Guide)

### 4.1. 에디터 Inspector 참조 및 할당 현황
- `Assets/Game/Scenes/InGame.unity` 내 **`InGameCharacterView`**의 직렬화 필드 `m_characterSpriteMaps`에 다음 키와 스프라이트 에셋이 저장되어 있습니다.
  1. `Hero` (주인공) -> `character_hero` (Placement: Right)
  2. `Ara` (아라) -> `character_ara` (Placement: Left)
  3. `Jay` (제이) -> `character_jay` (Placement: Left)
  4. `Teacher` (교사) -> `character_teacher` (Placement: Left)

### 4.2. 이벤트 구독 구조
- **`DialogueFlowController` 생성자**:
  - `m_dialogueVM.OnNextRequested += PlayNextDialogue;`
  - `m_dialogueVM.OnChoiceSelected += HandleChoiceSelected;`
- **`InGameCharacterView` 의존성 주입**:
  - `Construct(IDialogueViewModel viewModel)`에서 `OnDialogueUpdated += UpdateCharacterIllustration;`
- **`InGameDialogueView` 의존성 주입**:
  - `OnDialogueUpdated += UpdateDialogue;`
  - `OnChoicesUpdated += HandleChoicesUpdated;`

### 4.3. 설정화면 에디터 세팅 가이드
- **TitleLifetimeScope 인스펙터 바인딩**: `Title` 씬 내 **`TitleLifetimeScope`**의 `m_settingsView` 필드에 설정 패널의 `SettingsView` 컴포넌트를 할당해야 의존성 주입이 가능합니다.
- **SettingsView 컴포넌트 직렬화 필드 설정**:
  - `m_settingsPanel`: 설정 윈도우 전체 오브젝트
  - `Sidebar Tabs`: 좌측 사이드바 각 탭 버튼들 (`m_audioTabButton` 등)
  - `Content Panels`: 우측 콘텐츠 영역 각 패널 오브젝트들 (`m_audioPanel` 등)
  - `Audio UI Elements`: 오디오 패널 내 각 슬라이더, 텍스트, 토글 오브젝트들
  - `Bottom Action Buttons`: 하단 복원/취소/적용 버튼들
- **이벤트 구독 구조**:
  - `SettingsViewModel.OnStateChanged += UpdateUIValues;`
  - `SettingsViewModel.OnCloseRequested += func_Close;`
  - `TitleViewModel.OnRequestSettings += SettingsView.func_Open;`
- **UI 레이아웃 및 겹침 간섭 해결**:
  - 설정 화면이 팝업으로 오픈되어 있는 동안 뒤에 깔린 타이틀 메뉴 UI 버튼에 클릭 및 마우스 호버 등 인터랙션이 겹쳐서 전달되는 간섭 버그가 발생했습니다.
  - 이를 해결하기 위해 `TitleViewModel`에서 설정 창의 오픈/클로즈 요청 라이프사이클을 구독하도록 바인딩하고, 설정 화면 활성화 시 타이틀 메뉴 버튼들의 Interactable 상태 및 전체 UI 활성화 상태를 제어하여 UI 중복 처리를 원천 방지하였습니다.
  - uGUI 슬라이더(Slider)의 기본 비주얼 뼈대(Background, Fill Area, Fill, Handle Slide Area, Handle)가 누락되어 순수 하얀색 사각형으로 렌더링되던 문제를 해결하고자, 에디터 상에서 VContainer 라이프사이클에 맞물리게 실제 비주얼 요소를 계층형 uGUI 구조로 자동 배치하는 C# 스크립트를 빌드 및 가동하여 슬라이더 UI 렌더링을 시각적으로 구현 완료했습니다.

---

### 4.4. 대사 백로그 에디터 세팅 가이드
- **BacklogView 컴포넌트 직렬화 필드 설정**:
  - `m_backlogPanel`: 백로그 윈도우 전체 오브젝트 (`BacklogPanel`)
  - `m_sceneInfoText`: 백로그 탭 상단의 씬 요약 정보 텍스트 컴포넌트 (`InfoText`)
  - `m_itemPrefab`: 자식 대사 항목 템플릿 (`ItemPrefab` - 이제 `BacklogPanel` 하위에 계층 배치됨)
  - `m_contentParent`: `ScrollView/Viewport/Content` (수직 스크롤 배치 부모)
- **이벤트 구독 구조**:
  - 대사 진행 시: `DialogueFlowController` -> `IDialogueViewModel.OnDialogueUpdated` -> `BacklogViewModel` (데이터 누적)
  - 로그 요청 시: `LOG_Button` / `Tab` 키 -> `IDialogueViewModel.OnRequestBacklog` -> `InGameLifetimeScope` -> `BacklogView.func_Open()` (동적 리스트 렌더링 및 팝업 활성화)

---

## 5. 예정 작업 (Planned Tasks)

### 5.1. 대사 백로그 및 스크롤뷰 레이아웃 고도화
- [ ] **가변 높이 레이아웃 보완**: 대사 내용이 길어져 2줄 이상이 될 경우 `ContentText` 자동 줄바꿈 및 전체 백로그 항목 높이가 유동적으로 늘어나는 레이아웃 검증 (필요시 Layout Element의 preferredHeight 적용).
- [ ] **자동 스크롤 기능**: 대사가 대량으로 쌓였을 때 스크롤 뷰 영역이 하단으로 자동 스크롤(Auto-scroll to bottom)되는 조작 편의성 기능 추가 검토.
- [ ] **데이터 무결성 최종 검토**: 씬 전환 및 세이브/로드(Save/Load) 전후의 백로그 대사 목록 유실 여부 검증.

### 5.2. 인게임 시스템 통합 테스트
- [ ] **팝업 내비게이션 스택 관리**: 설정 윈도우와 백로그 UI 간의 중첩 활성화 시의 ESC 키 바인딩 및 뒤로가기 팝업 스택 제어 상태 검증.

---

본 상세 작업 내역은 "HowItWorks" 프로젝트의 핵심 연출 및 분기 확장 데이터 관리 표준으로 활용되며, 어떠한 소스 코드 수정 없이도 신규 분기를 추가할 수 있는 무결한 기초 구조를 가집니다.

---

## 6. 추가 시스템 개선 내역 (2026-06-20 작업)

### 6.1. 인트로 스킵 제어 아키텍처 개선 (DI 주입 전환)
- **기존 문제**: 인스펙터의 설정에 무관하게 항상 인트로 스킵이 발생하던 하드코딩 논리 오류(`m_skipIntro = true;`)가 존재했습니다.
- **해결 방안**: 스킵 여부 제어권을 최상위 DI 계층인 `InGameLifetimeScope`로 이전하였습니다.
  - **`IIntroViewModel.cs`**: `bool SkipIntro { get; }` 읽기 전용 프로퍼티를 인터페이스에 노출했습니다.
  - **`IntroViewModel.cs`**: 생성자로 `bool skipIntro` 값을 주입받아 읽기 전용 속성 `SkipIntro`에 바인딩했습니다.
  - **`IntroView.cs`**: 하드코딩을 제거하고 뷰모델로부터 이 스킵 설정을 주입받아 동기화하였습니다 (`m_skipIntro = viewModel.SkipIntro;`).
  - **`InGameLifetimeScope.cs`**: `[SerializeField] private bool m_skipIntro = true;` 직렬화 필드를 추가하여 뷰모델 등록 시 설정값을 파라미터로 넘겨주도록 변경하였습니다.

### 6.2. MVVM 결합도 리팩토링 (씬 정보 뷰 단방향 바인딩)
- **기존 문제**: `InGameSceneInfoView`가 `OnSceneInfoChanged(SceneInfoDTO)` 이벤트를 통해 `SceneInfoDTO` 모델/데이터 구조를 직접 구독하고, UI 텍스트 문자열 가공을 뷰(View) 내부에서 직접 처리하고 있어 MVVM 의존성 분리 원칙에 위배되었습니다.
- **해결 방안**:
  - **`ISceneInfoViewModel.cs`**: `event Action OnSceneInfoUpdated;` 이벤트와 `DisplaySceneTitle`, `DisplayLocation`, `DisplayPlaythrough` 가공 속성을 선언했습니다.
  - **`SceneInfoViewModel.cs`**: `UpdateSceneInfo(SceneInfoDTO)` 호출 시 UI에 표현될 문자열 포맷팅을 미리 가공하여 속성에 저장하고 `OnSceneInfoUpdated` 이벤트를 호출하도록 책임을 가져갔습니다.
  - **`InGameSceneInfoView.cs`**: `OnSceneInfoUpdated` 이벤트를 구독하여 매개변수 없이 뷰모델의 가공 속성을 단방향 바인딩하여 UI를 갱신합니다. 이로써 뷰의 모델 DTO 직접 참조를 완전히 제거했습니다.

### 6.3. VContainer 생명주기 및 의존성 최적화
- **기존 문제**: 뷰가 인트로 종료 후 다이얼로그 시스템 구동을 위해 외부에 직접 결합해 있거나 명확한 중개 주체가 없었습니다.
- **해결 방안**: `InGameLifetimeScope.Start()`에서 `IIntroViewModel.OnIntroFinished` 이벤트를 구독하여 인트로가 종료되는 시점에 `DialogueFlowController.StartDialogueFlowAsync().Forget()`을 비동기 실행하도록 제어 흐름을 중개했습니다.
- **using 최적화**: C# 파일 내에서 완전한 수식 네임스페이스 경로(예: `UnityEngine.UI.Button`)의 반복을 피하고 파일 최상단에 `using UnityEngine.UI;`를 명시하며, `System.Exception` -> `Exception` 등으로 코드를 최적화하고 가독성을 높였습니다.

### 6.4. 플레이모드 통합 테스트 및 어셈블리 빌드 종속성 해결
- **종속성 격리**: `DOTween` 및 `EasyTransitions`가 어셈블리 정의 파일(`.asmdef`) 없이 배치되어 커스텀 테스트 어셈블리(`Tests.asmdef`)에서 참조가 불가능한 문제를 해결하기 위해, `DOTween.Modules.asmdef` 및 `easytransitions.asmdef` 등을 신규 생성하고 `Game.asmdef` 및 `Tests.asmdef` 간의 참조 계층을 명확히 설정했습니다.
- **통합 테스트 작성 (`IntegrationTest.cs`)**:
  - 타이틀 씬 시작 -> 새 게임 버튼 클릭 및 로드 검증 -> 인트로 화면 스킵 클릭 -> 인게임 다이얼로그 진입 -> 49번/55번/58번 선택지 응답 및 스탯 변화 검증 -> 인벤토리 내 `ITEM_STRAW_DOLL` (짚 인형) 획득 정합성 검증까지의 플레이모드 통합 시나리오 테스트를 통과시켰습니다.

### 6.5. 기능 명세서 작성
- 프로젝트 에이전트 문서폴더 하위에 [functional_spec.md](file:///e:/Unity_workSpace/Projects/howItWorks/.agents/documents/functional_spec.md)를 생성 및 작성하여 타이틀, 인트로 스킵, 다이얼로그 감정 스탯, 선택지 분기, 설정창의 세부 동작 메커니즘을 명세화했습니다.

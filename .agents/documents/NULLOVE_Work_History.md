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

---

### 2.2. 캐릭터 이미지 연동 및 OCP 설계 전환
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

### 2.3. 데이터 기반(Data-Driven) 선택지 시스템 구축
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

## 3. 포스트 구현 가이드 (Post-Implementation Guide)

### 3.1. 에디터 Inspector 참조 및 할당 현황
- `Assets/Game/Scenes/InGame.unity` 내 **`InGameCharacterView`**의 직렬화 필드 `m_characterSpriteMaps`에 다음 키와 스프라이트 에셋이 저장되어 있습니다.
  1. `Hero` (주인공) -> `character_hero` (Placement: Right)
  2. `Ara` (아라) -> `character_ara` (Placement: Left)
  3. `Jay` (제이) -> `character_jay` (Placement: Left)
  4. `Teacher` (교사) -> `character_teacher` (Placement: Left)

### 3.2. 이벤트 구독 구조
- **`DialogueFlowController` 생성자**:
  - `m_dialogueVM.OnNextRequested += PlayNextDialogue;`
  - `m_dialogueVM.OnChoiceSelected += HandleChoiceSelected;`
- **`InGameCharacterView` 의존성 주입**:
  - `Construct(IDialogueViewModel viewModel)`에서 `OnDialogueUpdated += UpdateCharacterIllustration;`
- **`InGameDialogueView` 의존성 주입**:
  - `OnDialogueUpdated += UpdateDialogue;`
  - `OnChoicesUpdated += HandleChoicesUpdated;`

---

본 상세 작업 내역은 "HowItWorks" 프로젝트의 핵심 연출 및 분기 확장 데이터 관리 표준으로 활용되며, 어떠한 소스 코드 수정 없이도 신규 분기를 추가할 수 있는 무결한 기초 구조를 가집니다.

# HowItWorks 기능 명세서 (Functional Specification)

이 문서는 프로젝트의 핵심 기능 사양을 명세합니다.

---

## 1. 타이틀 시스템 (Title Scene)
타이틀 화면은 게임의 첫 진입점으로, 사용자가 게임 시작, 로드, 설정 및 종료를 수행하는 영역입니다.

- **새 게임 (New Game)**
  - `func_OnNewGameButtonClicked` 트리거 시 `TitleViewModel`이 호출되어 `ISceneLoader`를 통해 인게임 씬(`InGame`)으로 비동기 전환됩니다.
- **게임 로드 (Load Game)**
  - 기존 세이브 데이터를 불러오기 위해 팝업을 요청합니다.
- **설정 (Settings)**
  - 설정창 리스너를 실행하여 볼륨 및 환경 설정을 제어할 수 있는 설정창을 화면에 노출합니다.
- **종료 (Quit Game)**
  - 플랫폼 환경(Editor 또는 Application)에 따라 세션을 종료합니다.

---

## 2. 인트로 스토리 시스템 (Intro Scene)
인게임 로드 완료 직후 진행되는 도입부로, 연출 및 스토리 전달 역할을 수행합니다.

- **스킵 기능 (Skip Intro)**
  - 사용자가 `ESC` 키를 입력하거나 스킵 버튼을 클릭(`func_OnSkipIntroClick`)하면 인트로 연출 시퀀스를 취소하고 즉시 인게임 다이얼로그 시스템으로 진입합니다.
  - 인트로 스킵 여부(`m_skipIntro`)는 하드코딩되지 않고 `InGameLifetimeScope` 단에서 DI(의존성 주입)를 통해 `IntroViewModel`에 동적으로 전달되도록 개선되었습니다.

---

## 3. InGame 다이얼로그 및 감정 스탯 시스템 (InGame Dialogue & SidePanel)
인게임 핵심 비즈니스 로직으로, 시나리오 스크립트 진행과 플레이어 스탯 및 감정 상태를 관리합니다.

- **다이얼로그 진행**
  - 스페이스바, 엔터 또는 마우스 클릭 시 다음 대화 줄(`RequestNext`)이 재생됩니다.
- **감정 및 스탯 시스템**
  - 사이드 패널(`InGameSidePanelView`)을 통해 실시간으로 Cato Stocks, 감시도(Monitoring), 혼란도(Confusion), 공포(Fear), 슬픔(Sadness), 기쁨(Joy) 등이 누적 또는 변경되어 시각화됩니다.

---

## 4. 분기점 및 아이템 획득 시스템 (Branching & Inventory)
대화 도중 나타나는 특정 트리거 지점에서의 플레이어 선택(Choice) 및 그에 따른 스토리 분기와 아이템 보상 메커니즘을 정의합니다.

- **스토리 분기점 검증**
  - **49번 대화 선택지**: 49번 다이얼로그 진행 시 선택지 UI(`AVOID`, `NOD`)가 팝업되며, 선택에 따라 스탯 변화 및 다음 다이얼로그(50번)로 진행됩니다.
  - **58번 대화 선택지 (카토 분기)**: 301번(`TAKE CATO`, 카토 복용)을 선택할 시 `NextDialogueIndex`가 **65**로 분기 점프하며, 302번(`REFUSE CATO`, 카토 미복용)을 선택할 시 **59**번 다이얼로그(꿈 루트)로 분기 진입합니다.
- **아이템 획득 및 인벤토리 연동**
  - **55번 대화 선택지**: 201번(`ACCEPT`, 짚 인형 수락)을 선택하면 다이얼로그 분기 결과(`ItemRewardKey`)인 `ITEM_STRAW_DOLL` 정보를 참조하여 `IInGameInventorySystem`에 아이템이 자동으로 지급 및 추가되며, 202번(`REFUSE`, 뒤로 물러난다) 선택 시 아이템이 추가되지 않습니다.

---

## 5. 설정 화면 시스템 (Settings Dialog UI)
인게임 도중 설정을 변경하거나 창을 제어하는 UI 컴포넌트입니다.

- **열기 동작**
  - 설정 버튼 클릭 시 `ISceneInfoViewModel.RequestSettings` 이벤트를 경유하여 `SettingsView` GameObject 자체를 활성화(`gameObject.SetActive(true)`)하고 내부 판넬을 노출합니다.
- **닫기 및 취소 동작**
  - 설정 패널 내부 취소 버튼 클릭 시 `gameObject.SetActive(false)`를 호출하여 설정 윈도우를 다시 비활성화 상태로 전환합니다.

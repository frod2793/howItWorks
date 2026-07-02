# 사이드 패널 기획 일치화 작업

## 목표
- 사이드 패널의 UI 구조와 표시 데이터를 기획 이미지 사양에 맞게 보정한다.
- 그리움 상태를 단순 텍스트가 아닌 독립 뱃지 오브젝트로 표시한다.
- 대사 진행 수치를 `씬 03 ㆍ 줄 X / Y` 형식으로 실시간 동기화한다.
- 구역 명칭 표시를 `구역 ㆍ 제3 보존구` 기준으로 맞춘다.

## 적용 범위
- `Assets/Game/Scripts/03_Features/InGame/SidePanel/InGameSidePanelView.cs`

## 구현 항목
- `m_yearningBadgeGo`, `m_yearningBadgeText` 직렬화 필드 추가
- `m_dialogueProgressText` 직렬화 필드 추가
- `IDialogueViewModel.OnDialogueUpdated` 구독 및 해제 추가
- 대사 진행 텍스트 실시간 갱신 메서드 추가
- 우세 감정 계산의 배열 할당 제거
- 그리움 활성 상태의 뱃지 오브젝트 On/Off 처리
- 에디터 및 초기 모크 데이터의 구역 명칭과 대사 진행 문구 보정

## 검증 항목
- Unity 컴파일 오류 여부 확인
- 아키텍처 검증 스크립트 실행
- Inspector에서 신규 직렬화 필드 연결 여부 확인

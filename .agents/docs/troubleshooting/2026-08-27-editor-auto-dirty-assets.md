---
id: 2026-08-27-editor-auto-dirty-assets
status: promoted
tags: [unity, editor, projectsettings, git, commit]
symptoms: ["Editor를 열기만 해도 ProjectSettings·폰트 아틀라스가 수정 상태", "의도 외 변경이 커밋에 혼입될 위험"]
error_signatures: ["m_EnterPlayModeOptions 자동 변경", "PackageManagerSettings.asset 자동 변경"]
---

# Editor 실행만으로 공유 자산 자동 변경

- 증상: Unity Editor를 열기만 해도 `ProjectSettings/**`의 일부 파일과 폰트 아틀라스 등 공유 자산이 수정 상태가 되어, 에이전트 의도와 무관한 변경이 커밋에 섞일 위험이 생겼습니다.
- 환경: macOS, Unity Editor. 오염되는 파일 집합은 실행 조건에 따라 달라져 고정 목록이 없습니다(실측: EditorSettings, ProjectSettings, PackageManagerSettings, 폰트 아틀라스가 회차별로 다르게 관측됨).
- 원인: Editor가 기동·포커스 과정에서 설정과 생성 자산을 자체 갱신합니다.
- 해결: 커밋 전 `git status`로 의도 외 변경을 전수 확인하고 되돌렸습니다. 알려진 파일 목록을 되돌리는 방식은 새 항목을 놓치므로 사용하지 않습니다.
- 검증: Editor 기동 회차별로 오염 파일 집합이 달라짐을 두 회차 실측으로 재현하고, 커밋 전 전수 확인·되돌리기 적용 후 의도 외 변경 혼입이 사라짐을 확인했습니다.
- 재발 방지: 공유 핫스팟 규칙에 전수 확인·되돌리기 절차를 명시했습니다.
- 승격 상태: 승격 완료 — [병렬 작업 규칙](../onboarding/parallel-work.md)의 공유 핫스팟 섹션.

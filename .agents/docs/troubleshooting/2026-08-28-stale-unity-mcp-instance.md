---
id: 2026-08-28-stale-unity-mcp-instance
status: promoted
tags: [unity, mcp, editor, readiness, worktree, verification]
symptoms: ["MCP 목록에 running으로 표기되나 heartbeat가 갱신되지 않음", "project/info·editor/state 요청이 응답하지 않음", "UI 캡처·PlayMode 검증이 무한 대기 상태로 남음"]
error_signatures: ["heartbeat stale", "no response: mcpforunity://project/info", "no response: mcpforunity://editor/state"]
---

# stale Unity MCP instance를 정상으로 오인해 무한 대기

- 증상: 전용 Editor 프로세스와 MCP 목록 항목은 남아 있으나 heartbeat가 갱신되지 않고 `project/info`·`editor/state`가 응답하지 않습니다. 이 상태에서 Game View 캡처, 컴파일 상태 확인, PlayMode 검증, 해상도 비교가 전부 진행되지 않습니다.
- 환경: macOS, worktree별 전용 Unity Editor, dirty 항목 다수(관측 사례 209개) 보유.
- 원인: 프로세스 존재와 MCP 목록의 `running` 표기를 준비 완료로 오인했습니다. 실제 준비 판정에는 exact `Name@hash`, 물리 project root 일치, 현재 heartbeat, `ready_for_tools=true`, `is_compiling=false`가 모두 필요합니다. 연결 불가 상태에 timeout·복구 순서·에스컬레이션 기준이 없어 대기만 반복됐습니다.
- 해결: (후보) 준비 판정을 게이트로 고정합니다. ① `project/info`와 `editor/state`가 각각 30초 내 성공해야 정상. ② 하나라도 실패하면 2분 내 동일 `Name@hash`로 1회만 재확인. ③ 재확인도 실패하면 즉시 `stale` 기록. ④ dirty가 많아 강제 종료가 위험하면 재기동하지 않고 `저장 후 재기동` / `현재 상태 보존` 선택을 사용자에게 요청. ⑤ 복구 후 exact `Name@hash`·물리 project root·`ready_for_tools=true`·`is_compiling=false`를 재통과해야 작업을 재개.
- 검증: `not_run`. 게이트 절차는 정의했으나 stale 재현과 복구 후 재통과를 실측하지 못했습니다. 프로세스 식별 스코핑만 실측 확인했습니다(자기 worktree Editor만 선택).
- 재발 방지: pid·port·목록 `running` 표기는 보조 신호로만 취급하고, 위 게이트를 통과하지 못한 UI 캡처·테스트 증거는 `not_proven`으로 기록합니다. dirty 범위를 확인하기 전에는 재기동 승인을 받지 않습니다.
- 승격 상태: 승격 완료 — [외부 대기 타임아웃](../onboarding/agent-tooling.md) 규칙(기본 3분 상한·중단·기록·복구)으로 일반화 승격. 개별 해결안 상세 검증은 후속.

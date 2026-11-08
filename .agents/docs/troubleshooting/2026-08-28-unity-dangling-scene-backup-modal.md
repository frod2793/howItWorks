---
id: 2026-08-28-unity-dangling-scene-backup-modal
status: promoted
tags: [unity, editor, macos, modal, mcp, worktree, automation]
symptoms: ["Unity 프로세스는 실행되지만 MCP instance 목록에 등록되지 않음", "Editor 로그가 라이선스 완료 이후 진행하지 않음", "PlayMode·Game View 캡처·컴파일 확인이 모두 불가"]
error_signatures: ["HandleDanglingSceneBackups", "NSAlert runModal", "Application::InitializeProject", "GetDialogResponse"]
---

# Unity Editor가 씬 백업 복구 모달에서 정지

- 증상: 전용 Editor 프로세스는 살아 있으나 stdio `mcpforunity://instances`에 등록되지 않고, Editor 로그가 라이선스 완료 뒤 멈춥니다. 모달이 해결되기 전에는 MCP identity·컴파일·PlayMode·Game View 캡처가 모두 무효입니다.
- 환경: macOS, Unity `6000.3.19f1`, 다중 linked worktree에 worktree별 전용 Editor 운용.
- 원인: 이전 비정상 종료가 남긴 씬 백업에 대해 Unity가 `Recover/Delete` 선택을 모달로 요구합니다. 메인 스레드가 `Application::InitializeProject() -> HandleDanglingSceneBackups() -> GetDialogResponse() -> NSAlert runModal`에서 블록되며, 이 선택은 미저장 씬 데이터를 보존하거나 폐기하므로 자동화가 임의로 누르면 안 됩니다.
- 해결: (후보) 준비 상태 확인이 30초 내 실패하면 `sample`로 메인 스레드를 떠서 모달 여부를 판정하고, 모달이면 재기동·`Temp`/`Library` 삭제를 중단한 뒤 백업 대상과 선택지를 사용자에게 보고합니다. 대상은 자기 worktree 프로세스로 한정합니다.

```bash
WT="$(git rev-parse --show-toplevel)"
for pid in $(pgrep -f "MacOS/Unity.*-projectPath $WT"); do
  sample "$pid" 2 -f /tmp/unity-$pid.sample >/dev/null 2>&1
  grep -qE "HandleDanglingSceneBackups|NSAlert runModal" /tmp/unity-$pid.sample \
    && echo "$pid MODAL" || echo "$pid ok"
done
```

- 검증: 부분 검증. 정상 Editor 10개에서 두 패턴 0건이고 Unity 심볼이 정상 출력돼 오탐이 없음을 확인했으며, worktree 스코핑은 자기 Editor 3건만 선택하고 타 worktree 7건을 제외함을 실측했습니다. 실제 모달 상태는 재현하지 못해 탐지 성공은 위 스택을 담은 합성 sample 대조로만 확인했습니다(`not_run`: 실모달 재현).
- 재발 방지: Editor 기동 후 `mcpforunity://project/info`, `mcpforunity://editor/state`, `ready_for_tools=true`, `is_compiling=false`를 먼저 통과시키고, 30초 무응답이면 위 모달 판정을 수행합니다. 모달 상태에서 씬 저장·PlayMode·재기동 반복·`Temp`/`Library` 삭제를 금지합니다.
- 승격 상태: 승격 완료 — [외부 대기 타임아웃](../onboarding/agent-tooling.md) 규칙으로 일반화 승격(해당 실행 루트 Editor 강제 종료 허용 포함). 실모달 재현 검증은 후속.

---
id: 2026-08-28-unity-mcp-build-job-disappears
status: collected
tags: [unity, mcp, stdio, android, build, worktree]
symptoms: ["Android build job가 예약 직후 조회되지 않음", "대상 Editor Console 조회가 응답하지 않음", "빌드 요청 뒤 Resources JSON untracked 파일 생성"]
error_signatures: ["No job found with ID: build-1a7950f435", "Unity instance 'TASK-71-android-logcat-remediation@4fa2b557' not found", "read_console target timed out after 92s"]
---

# Unity stdio Android 빌드 job 소실과 Editor 무응답

- 증상: 정확한 linked worktree Unity stdio 인스턴스에서 Android build를 요청한 뒤 build job 조회가 실패했고, 대상 인스턴스는 목록에서 일시적으로 사라졌다가 재등록됐지만 Console 조회가 92초 이상 응답하지 않았습니다. 이후 동일 현상에서 대상 Unity PID는 계속 실행 중이고 MCP loopback listener도 열려 있었지만, `manage_build`는 `Could not connect to Unity`를 반환했습니다. `Assets/Resources/PerformanceTestRunInfo.json`과 Settings JSON 및 meta 파일 4개가 untracked로 생성됐습니다.
- 환경: macOS, Unity 6000.3.19f1, Android, linked worktree, MCP stdio, 실제 Android 기기 연결 상태.
- 원인: 미확정. Unity 프로세스와 MCP listener 생존만으로 MCP bridge 요청 처리 가능 상태가 보장되지 않는 관찰이 있습니다. build 요청 처리 또는 Unity MCP bridge 연결 상태가 build job 추적과 Console 응답을 유지하지 못한 원인을 추가 조사해야 합니다.
- 해결: 미확정. 다른 worktree Editor·HTTP·batch로 우회하지 않고, 정확한 대상 stdio 인스턴스의 응답 복구 후 새 build job 상태와 산출물 시간을 다시 확인해야 합니다.
- 검증: build job 소실과 대상 인스턴스 일시 미발견을 관찰했습니다. 해결 적용·재확인은 `not_run`입니다.
- 재발 방지: build 요청 직후 job 상태, target instance 재등록 여부, APK 산출물 시간을 순서대로 확인하고 생성된 untracked 파일은 소유 확인 전 보존합니다.
- 승격 상태: 미승격(원인 미확정) — 무한 대기 측면은 [외부 대기 타임아웃](../onboarding/agent-tooling.md) 규칙이 커버.

---
id: 2026-08-26-korean-path-android-build
status: promoted
tags: [unity, android, worktree, path, build]
symptoms: ["한글 경로 worktree에서 Android 빌드 실패", "GUI에서 prerequisites 단계 고착으로 위장"]
error_signatures: ["Android 빌드 prerequisites 고착", "비ASCII 경로 빌드 실패"]
---

# 한글 경로 worktree Android 빌드 불가

- 증상: 한글 이름 경로의 linked worktree에서 Android 빌드가 실패하고, GUI에서는 prerequisites 단계 고착으로 위장되어 원인 파악이 어려웠습니다.
- 환경: macOS, Unity Android 빌드 파이프라인, 한글 디렉터리명 git worktree.
- 원인: Android 빌드 도구 체인이 비ASCII 경로를 처리하지 못합니다.
- 해결: 빌드가 필요한 작업은 ASCII 이름 worktree를 생성해 수행하고, Library는 clonefile 복사로 초기화해 재임포트를 회피했습니다.
- 검증: 한글 경로에서 빌드 실패를 재현하고, 동일 변경분을 ASCII 경로 worktree로 옮겨 빌드 성공을 확인했습니다.
- 재발 방지: worktree 생성 규칙 1단계에 "경로는 ASCII로 만든다"를 명시했습니다.
- 승격 상태: 승격 완료 — [병렬 작업 규칙](../onboarding/parallel-work.md)의 worktree 생성 규칙.

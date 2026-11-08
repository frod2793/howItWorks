---
id: 2026-08-27-harness-recopy-local-state-loss
status: verified
tags: [harness, deploy, worktree, local-state, profile]
symptoms: ["project-profile.conf 소실", "reports 디렉터리 비어 있음", "프로필 부재로 린트·검증 실패 가능 상태"]
error_signatures: ["프로필 파일을 읽을 수 없습니다", "No such file or directory: project-profile.conf"]
---

# 하네스 재복제 시 로컬 상태 소실

- 증상: 실행 루트의 `.agents`에서 확정 프로필(`config/project-profile.conf`)과 감지 리포트(`reports/`)가 사라져, 린트·검증이 프로필 부재로 실패할 수 있는 상태가 되었습니다.
- 환경: 하네스 갱신 배포가 반복되는 다중 worktree 운영 환경.
- 원인: 하네스를 갱신할 때 기존 `.agents`를 통삭제한 뒤 원본을 새로 복사하면, 원본에 없는 로컬 상태 파일이 함께 사라집니다. 원본에는 `project-profile.example.conf`만 있고 확정 프로필은 실행 루트의 로컬 상태입니다.
- 해결: 다른 worktree들에 남은 프로필 사본의 해시를 대조해 다수 일치 사본을 권위로 복원했습니다. 당시에는 `rsync -a --delete`와 P 필터로 로컬 상태 삭제를 보호했습니다. 이 명령은 덮어쓰기를 막지 못하므로 현재 갱신 절차로 재사용하지 않습니다. 현재는 아래 양방향 제외 절차를 적용합니다.
- 검증: 메인 실행 루트에서 소실을 실측 확인 후, worktree 3곳의 동일 해시 사본으로 복원하고 전 실행 루트의 프로필 존재와 배포 diff 0을 재확인했습니다. 당시 스크래치 확인은 삭제 보호에 한정하며, P 필터만으로 기존 로컬 내용의 덮어쓰기 방지를 증명하지는 않습니다.
- 재발 방지: 배포 절차는 삭제 없는 동기화를 기본으로 하고 로컬 상태 경로를 양방향 exclude(또는 H+P)로 제외하며, 통삭제 후 재복사는 hook(`scripts/hooks/protect-agents-dir.sh`)이 결정론적으로 차단합니다. 배포 후 전 실행 루트의 프로필 존재를 점검합니다.
- 승격 상태: 미승격 — 반복 확인 시 worktree 생성·갱신 규칙으로 승격 예정.

현재 권장 절차는 [병렬 작업 규칙](../onboarding/parallel-work.md)의 양방향 exclude 또는 H+P 보호를 따릅니다. P 단독은 삭제만 막고 덮어쓰기는 막지 못합니다. 기존 명령은 당시 사건 기록입니다.

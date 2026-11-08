---
id: 2026-08-28-merged-feature-remerge-detection
status: verified
tags: [git, merge, worktree, regression, verification]
symptoms: ["이미 Dev에 반영된 기능을 브랜치 전체 재병합으로 되살림", "Git 충돌은 없으나 제품 회귀 위험 발생", "cherry-mark 대조에서 중복이 검출되지 않음"]
error_signatures: ["git log --cherry-mark 결과에 중복 없음", "merge-tree=ok", "이미 반영된 기능 재병합"]
---

# 스쿼시·병합으로 반영된 중복 기능이 patch-id 대조를 통과

- 증상: 작업 브랜치 전체를 병합 대상으로 삼아, 이미 상위 브랜치에 반영된 기능을 다시 병합했습니다. Git 충돌이 0건이어도 제품 회귀 위험이 생깁니다. 표준 `git log --cherry-mark` 중복 대조는 이 중복을 검출하지 못했습니다.
- 환경: linked worktree 다수, 기준 브랜치와 작업 브랜치가 크게 분기(기준 전용 92커밋 / 브랜치 전용 23커밋).
- 원인: 두 가지가 겹칩니다. ① 기능 단위가 아니라 브랜치 전체를 병합 단위로 간주했습니다. ② 상위 브랜치가 브랜치 커밋을 그대로 옮기지 않고 병합·재작성해 반영했기 때문에 patch-id가 달라져 `--cherry-mark`의 `=` 표시가 뜨지 않습니다. 즉 patch-id 대조는 체리픽·리베이스만 잡고 스쿼시·병합 반영은 놓칩니다.
- 해결: 중복 판정의 주 검사를 patch-id 대조에서 **파일 겹침 대조**로 교체하고, patch-id 대조는 보조로만 둡니다.

```bash
BASE=Dev
MB=$(git merge-base $BASE HEAD)
# 주 검사: 기준 브랜치가 같은 파일을 이미 고쳤는지 (스쿼시·병합까지 검출)
git diff --name-only $MB HEAD > /tmp/bf.txt
git log --oneline $MB..$BASE -- $(tr '\n' ' ' < /tmp/bf.txt) || echo "겹침 없음"
# 보조 검사: 동일 패치 재적용 (체리픽·리베이스만 검출)
git log --oneline --cherry-mark --left-right $BASE...HEAD | grep '^=' || echo "동일 패치 없음"
```

- 검증: 재현 — 문제 브랜치에서 보조 검사는 무관한 패키지 커밋 4건만 표시하고 실제 중복 병합 커밋을 놓쳤습니다. 적용 — 주 검사로 교체. 재확인 — 같은 브랜치에서 중복 병합 커밋 1건을 정확히 단독 검출했고, 정상 브랜치 3개(기능 브랜치 2개, 대규모 브랜치 1개)에서는 0건으로 오탐이 없었습니다.
- 재발 방지: 병합 선언 전 위 두 검사를 모두 실행합니다. 주 검사 출력이 있으면 해당 커밋과 브랜치 변경을 파일 단위로 대조한 뒤에만 병합 후보를 정하고, 이미 반영된 기능은 재병합하지 않습니다. dirty 변경은 역할별로 분리하며 preview/확정 ID 계약 변경 같은 항목은 별도 테스트·별도 커밋으로 다룹니다.
- 승격 상태: 미승격 — 병합 전 검사 스크립트로 승격 예정.

---
id: 2026-08-28-merge-candidate-scope-pollution
status: verified
tags: [git, merge, packages, unity, scope, harness]
symptoms: ["fast-forward 가능하지만 병합 후보에 기능 삭제·패키지 삭제·하네스 변경이 섞임", "필수 패키지가 manifest에서 제거됨", "PlayMode·빌드 검증이 not_run인 채 병합 후보로 올라옴"]
error_signatures: ["packages-lock.json 필수 패키지 삭제", "manifest.json 패키지 제거", "47 commits 83 files changed"]
---

# 병합 후보 브랜치의 범위 오염(패키지 삭제·기능 삭제 혼입)

- 증상: Git상 fast-forward가 가능해 병합 가능해 보이지만, 실제 범위에 패키지 정책 변경·하네스 변경·기능 삭제·문서 변경이 함께 누적돼 있습니다. 관측 사례는 47커밋 83파일 `5027+ / 3824-`이며, 기준 브랜치의 필수 패키지가 `Packages/manifest.json`과 `packages-lock.json`에서 삭제되고 관련 PlayMode 테스트도 제거됐습니다.
- 환경: 작업용 linked worktree에서 소규모 개선으로 시작한 브랜치가 장기간 누적된 상태.
- 원인: 작은 개선을 별도·최소 커밋으로 유지하지 않아, 병합 가능성(Git)과 제품 승인 가능성(회귀·정책)이 분리됐습니다. Git 충돌 0건은 텍스트 병합만 증명하며 정책·기능 삭제는 증명하지 않습니다.
- 해결: 병합 선언 전 범위 검사를 게이트로 고정합니다.

```bash
BASE=Dev
# 금지 파일이 범위에 있는지 (출력 있으면 별도 브랜치로 분리)
git diff --name-only $BASE...HEAD -- Packages/manifest.json Packages/packages-lock.json .agents/
# 필수 패키지 삭제 즉시 차단
git diff $BASE...HEAD -- Packages/manifest.json | grep '^-.*com\.unity\.pipeline' && echo "BLOCK: 필수 패키지 삭제"
# 규모 확인 (파일 20개 또는 커밋 15개 초과 → 기능 단위로 분리)
git diff --shortstat $BASE...HEAD; git rev-list --count $BASE..HEAD
# 기존 dirty가 스테이지에 섞였는지
git diff --cached --name-only
```

- 검증: 재현 — 문제 브랜치에서 위 검사가 하네스 문서·`manifest.json`·`packages-lock.json` 변경을 검출하고, 필수 패키지 삭제 라인 `-"com.unity.pipeline": "0.5.0-exp.1"`를 직접 검출했으며, 규모를 83파일 47커밋으로 보고했습니다. 재확인 — 정상 기능 브랜치 2개(변경 3파일·2파일)에서는 금지 파일·패키지 삭제 검출이 0건으로 오탐이 없었습니다.
- 재발 방지: 패키지 매니페스트와 하네스 디렉터리 변경은 제품 기능 커밋과 분리합니다. 기준 브랜치 필수 패키지 삭제는 즉시 차단합니다. 병합 후보는 기능별 커밋만 선택하고, 빌드 타깃에 영향을 주는 변경은 PlayMode·Build·산출물 확인 증거가 모두 있어야 통과입니다.
- 승격 상태: 미승격 — 병합 전 검사 스크립트로 승격 예정.

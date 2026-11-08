# 병렬 작업 개선 실행 계획

## 문서 정보

- **작성자**: 윤승종
- **작성일**: 2026-08-24
- **상태**: 진행 중
- **현재 테스트 권한**: none — 아래 검증 명세는 사용자가 요청할 때 실행하며, 그 전에는 `not_run`으로 기록합니다.

## 배경과 목표

`.agents/docs/onboarding/parallel-work.md`가 병렬 작업 규칙(비충돌 write scope 동시 기능 개발, worktree별·shard별 동시 테스트, Unity 프로세스 예산)을 정의했다. 남은 개선은 규칙을 문서에서 실행 가능한 검사와 도구로 끌어올리는 것이다. 모든 단계는 기존 Editor·CLI 격리 게이트, 검증 실행 권한과 증거 권위를 변경하지 않는다.

## 단계

### 1. write scope 이탈 검사 스크립트

- Create: `.agents/scripts/validation/check-write-scope.sh`
- Task 선언의 write scope 목록과 base ref 대비 실제 변경 파일 목록을 비교해 이탈을 차단한다. Git 수집 실패는 통과가 아니라 실패로 처리한다(fail closed).
- 공유 핫스팟 경로가 기능 Task의 write scope에 들어오면 거부한다.

### 2. 병렬 배치 계획 명령 이식

- 범용 v1.2.0 병렬 오케스트레이션의 `plan`(의존 Wave 계산, 통합 lane 마지막 배치)과 `verify-task`를 현행 하네스 구조로 이식한다.
- Create: `.agents/scripts/workflow/parallel-plan.sh`
- 배치 상태는 제품 diff를 오염시키지 않는 위치에 저장하고, worktree 생성·삭제와 merge·commit은 자동화하지 않는다.

### 3. 동시 테스트 실행 헬퍼 — 1차 구현 완료

- `.agents/scripts/validation/run-parallel-tests.sh`가 worktree별 `unity test`를 Unity 프로세스 예산(기본 2, 최대 4) 안에서 동시 실행하고 실행 루트별 NUnit XML 증거를 수집한다. 실행 전 `unity doctor --ci` preflight를 수행한다.
- 실제 Unity 프로젝트에서의 실행 검증은 `not_run`이다. 남은 작업: 같은 프로젝트 내 `--shard n/m` 자동 분할과 `unity status --format json` 기반 예산 점검 통합.

## 검증 명세

- 각 스크립트는 Bash 3.2에서 `bash -n`과 자체 계약 테스트를 통과해야 한다.
- 신규 검사·명령은 `.agents/tests/run-tests.sh` 계약 그룹에 추가한다.
- 위 검증은 사용자가 현재 요청한 경우에만 실행하며, 실행하지 않은 항목은 `not_run`이다.

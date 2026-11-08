# 트러블슈팅 사례 관리

실패 사례를 수집·검증해 같은 문제의 재진단 비용을 없애고, 검증된 해결안을 검색 가능한 RAG 데이터로 재사용하며, 반복되는 사례를 규칙·린트·테스트로 승격하기 위한 저장소입니다.

## 수집 정책

- 작업 중 만난 실패는 원인 확정 여부와 관계없이 관찰 증거(에러 문자열, 로그, 재현 조건)와 함께 사례로 수집합니다. 원인 미확정 사례는 `status: collected`로 기록하고 추측을 사실처럼 쓰지 않습니다.
- 파일명은 `YYYY-MM-DD-슬러그.md`이며 날짜는 최초 확인일입니다.
- 프로젝트 고유 명칭·경로·자격 증명은 일반화해 기록합니다.

## 수명주기와 검증

사례는 frontmatter의 `status`로 수명주기를 관리합니다.

- `collected`: 실패와 증거만 수집된 상태. 해결안 없음 또는 미탐색.
- `proposed`: 후보 해결안을 탐색해 기록한 상태. 유효성 미검증이며 적용 권고가 아닙니다.
- `verified`: 해결안을 실측으로 검증한 상태. 실패 재현, 해결안 적용, 재확인(실패 소멸)의 세 증거를 `검증` 항목에 모두 기록해야 하며, 검증하지 않은 해결안을 `verified`로 표시하지 않습니다.
- `promoted`: 검증된 해결안이 정식 규칙·린트·테스트로 승격된 상태. 승격 위치 링크를 남기고 사례 파일은 삭제하지 않습니다.

승격 판단은 transferable(다른 작업에도 적용 가능), surprising(사전에 알지 못했던 것), specific(일반론이 아닌 구체적 패턴)의 세 기준을 함께 충족하는 사례를 우선합니다.

## RAG 데이터 형식

각 사례 파일은 검색용 메타데이터 frontmatter로 시작하고, 본문은 고정 라벨을 사용합니다.

```markdown
---
id: YYYY-MM-DD-슬러그
status: collected | proposed | verified | promoted
tags: [영역 키워드]
symptoms: ["관찰 증상 요약"]
error_signatures: ["실제 에러·로그 문자열 조각"]
---

# <한 줄 제목>

- 증상: 관찰된 실패 현상
- 환경: OS·도구 버전·실행 조건
- 원인: 확정된 근본 원인. 미확정이면 "미확정"과 관찰 근거
- 해결: 적용한 조치 또는 후보 해결안(후보/검증 구분 명시)
- 검증: 재현·적용·재확인 증거. 미검증이면 `not_run`
- 재발 방지: 절차·스크립트·규칙 변경 사항
- 승격 상태: 미승격 | 승격 완료(위치 링크)
```

## 검색·사용 규칙

- 실패를 만나면 먼저 에러 문자열·증상 키워드로 이 디렉터리를 검색합니다: `grep -ril "<키워드>" .agents/docs/troubleshooting/`
- `verified`·`promoted` 사례의 해결안만 그대로 적용합니다. `collected`·`proposed`는 참고 후보일 뿐이며 적용 전에 재현·적용·재확인 검증을 거칩니다.
- 해결안이 검증되면 `status`·`검증` 항목과 색인 표를 함께 갱신합니다.

## 색인

| 날짜 | 사례 | status |
| --- | --- | --- |
| 2026-08-24 | [macOS BSD awk 한글 문자열 비교 오판](2026-08-24-macos-awk-korean-compare.md) | promoted |
| 2026-08-26 | [한글 경로 worktree Android 빌드 불가](2026-08-26-korean-path-android-build.md) | promoted |
| 2026-08-27 | [Editor 실행만으로 공유 자산 자동 변경](2026-08-27-editor-auto-dirty-assets.md) | promoted |
| 2026-08-27 | [하네스 재복제 시 로컬 상태 소실](2026-08-27-harness-recopy-local-state-loss.md) | verified |
| 2026-08-28 | [기존 보고를 재개 계약으로 쓰지 않아 작업이 중복 생성됨](2026-08-28-lost-resume-contract-duplicate-work.md) | proposed |
| 2026-08-28 | [병합 후보 브랜치의 범위 오염](2026-08-28-merge-candidate-scope-pollution.md) | verified |
| 2026-08-28 | [스쿼시·병합 반영 중복 기능이 patch-id 대조를 통과](2026-08-28-merged-feature-remerge-detection.md) | verified |
| 2026-08-28 | [PlayMode 검증이 MCP instance 소실·helper 타입 오류로 중단](2026-08-28-playmode-identity-and-test-residue.md) | proposed |
| 2026-08-28 | [stale Unity MCP instance를 정상으로 오인해 무한 대기](2026-08-28-stale-unity-mcp-instance.md) | promoted |
| 2026-08-28 | [Unity Editor가 씬 백업 복구 모달에서 정지](2026-08-28-unity-dangling-scene-backup-modal.md) | promoted |
| 2026-08-28 | [Unity stdio Android 빌드 job 소실과 Editor 무응답](2026-08-28-unity-mcp-build-job-disappears.md) | collected |

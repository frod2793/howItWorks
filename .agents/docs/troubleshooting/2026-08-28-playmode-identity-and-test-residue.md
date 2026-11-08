---
id: 2026-08-28-playmode-identity-and-test-residue
status: proposed
tags: [unity, playmode, mcp, test, reflection, git-hygiene]
symptoms: ["PlayMode 테스트가 초기화 timeout으로 0건 종료", "실행 중 전용 MCP instance가 목록에서 사라짐", "테스트 helper 타입 불일치 컴파일 오류", "테스트가 만든 씬 파일이 untracked로 남음"]
error_signatures: ["CS1503", "initialization timeout", "InitTestScene", "instance not found"]
---

# PlayMode 검증이 MCP instance 소실과 helper 타입 오류로 중단

- 증상: 구현 중 전용 Unity MCP instance가 목록에서 사라져 PlayMode RED 테스트가 초기화 timeout으로 0건 종료됐습니다. 이어진 테스트 수정에서는 reflection helper가 다른 타입의 view를 전용 helper에 전달해 `CS1503` 컴파일 오류가 났고, 테스트 초기화가 만든 `Assets/InitTestScene*.unity`와 meta가 untracked로 남아 제품 커밋과 분리해야 했습니다.
- 환경: worktree별 전용 Unity Editor, MCP 경유 PlayMode 실행, reflection 기반 private field 접근 테스트.
- 원인: MCP instance 존재를 테스트 실행 **직전에** 다시 identity-gate하지 않았고, 테스트 helper의 대상 타입 제약을 호출부 변경 전에 확인하지 않았습니다. 그 결과 실제 RED 계약을 실행하기도 전에 인프라 실패와 컴파일 실패가 연속 발생했습니다.
- 해결: (후보) PlayMode 실행 전 게이트를 고정합니다. ① 실행 직전 exact `Name@hash`·물리 project root·`ready_for_tools=true`·`is_compiling=false` 재확인. ② 컴파일 성공 후에만 실행하고 CS 오류 상태에서 실행을 재시도하지 않음. ③ reflection helper는 대상 타입이 다르면 제네릭 공통 helper로 넓히거나 호출부 전용 helper 사용. ④ instance 소실 시 재시도 반복 금지, 전용 Editor 재등록 후 동일 RED 계약을 1회 재실행. ⑤ 실행 후 `git status --porcelain`으로 테스트 잔재를 확인하고 `git add -A`를 금지, 제품 커밋과 분리.
- 검증: `not_run`. 게이트 절차는 정의했으나 instance 소실 재현과 복구 후 RED 계약 재실행을 실측하지 못했습니다.
- 재발 방지: PlayMode 실행 전 identity 재확인과 컴파일 확인을 순서대로 통과시키고, Unity 테스트가 생성한 씬 파일은 제품 변경으로 취급하지 않습니다. 최종 병합 판단은 제품 커밋과 환경·테스트 잔재를 분리한 뒤 동일 worktree의 focused test와 독립 리뷰 결과로만 합니다.
- 승격 상태: 미승격.

# 실행 계획 관리 가이드

## 디렉토리 구조

```
docs/exec-plans/
├── active/         ← 현재 진행 중인 실행 계획
├── completed/      ← 완료된 실행 계획 (아카이브)
├── _TEMPLATE.md    ← 실행 계획 템플릿
└── README.md       ← 이 파일
```

## 워크플로우

1. `_TEMPLATE.md`를 복사하여 `active/YYYY-MM-DD-기능명-plan.md` 생성
2. 상태를 `🟡 진행 중`으로 설정
3. Task별로 Step을 순서대로 실행
4. 모든 Task 완료 후 상태를 `✅ 완료`로 변경
5. 파일을 `completed/` 디렉토리로 이동

## 파일 네이밍 규칙

```
YYYY-MM-DD-기능명-plan.md
```

## 실행 원칙

- 각 Step은 **2~5분** 단위의 작은 작업
- **TDD**: 테스트 먼저 → 구현 → 테스트 통과 → 커밋
- 각 Task는 독립적으로 테스트 가능한 단위
- 커밋 메시지는 Conventional Commits 형식

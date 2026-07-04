# [기능명] 실행 계획

> 파일명 규칙: `YYYY-MM-DD-기능명-plan.md`
> 이 템플릿을 복사하여 새 실행 계획을 작성하십시오.
> 완료 시 `completed/` 디렉토리로 이동합니다.

---

**상태**: 🟡 진행 중 / ✅ 완료
**생성일**: YYYY-MM-DD
**담당자**: [이름]
**관련 설계 문서**: `docs/design-docs/YYYY-MM-DD-기능명-design.md`

---

## 목표

[이 실행 계획이 달성할 구체적인 목표를 한 줄로 기술합니다.]

## 아키텍처 요약

[사용할 기술적 접근 방식을 2~3줄로 기술합니다.]

---

## 작업 단위 (Tasks)

### Task 1: [컴포넌트명]

**파일:**
- Create: `Assets/Scripts/[경로]/[파일명].cs`
- Modify: `Assets/Scripts/[경로]/[파일명].cs`
- Test: `Assets/Tests/[경로]/[테스트파일명].cs`

- [ ] **Step 1: 실패하는 테스트 작성**

```csharp
[Test]
public void SpecificBehavior_WhenCondition_ShouldExpectedResult()
{
    // Arrange
    var sut = new TargetClass();

    // Act
    var result = sut.Method(input);

    // Assert
    Assert.AreEqual(expected, result);
}
```

- [ ] **Step 2: 테스트 실행하여 실패 확인**

```bash
# Unity Test Runner에서 실행
# 기대: FAIL — "TargetClass not found"
```

- [ ] **Step 3: 최소 구현 코드 작성**

```csharp
/// <summary>
/// [기능]: [클래스 역할 설명]
/// [작성자]: 윤승종
/// </summary>
public class TargetClass
{
    public ResultType Method(InputType input)
    {
        return expected;
    }
}
```

- [ ] **Step 4: 테스트 실행하여 통과 확인**

```bash
# 기대: PASS
```

- [ ] **Step 5: 커밋**

```bash
git add [파일 목록]
git commit -m "feat([scope]): [한국어 설명]"
```

### Task 2: [다음 컴포넌트명]

[위와 동일한 구조로 반복]

---

## 검증 계획

### 자동화 테스트

```bash
# 단위 테스트 전체 실행
# Unity Test Runner → EditMode Tests

# 아키텍처 검증
bash .agents/scripts/lint/check-architecture.sh
```

### 수동 검증

- [ ] [수동 검증 항목 1]
- [ ] [수동 검증 항목 2]

---

## 완료 기준

- [ ] 모든 Task의 Step이 완료됨
- [ ] 모든 테스트 통과
- [ ] 아키텍처 검증 스크립트 통과
- [ ] 코드 리뷰 완료
- [ ] 이 파일을 `completed/` 디렉토리로 이동

---

## 변경 이력

| 날짜 | 작성자 | 변경 내용 |
|------|--------|----------|
| YYYY-MM-DD | [작성자] | 초안 작성 |

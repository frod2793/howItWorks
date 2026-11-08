# 트윈 프로필

> `tween_backend` 값과 관계없이 트윈 소유자, 대상 파괴, 중복 실행, 완료·취소 시 정리를 정의합니다. `Update`에서 트윈을 반복 생성하지 않습니다.

## `dotween`

DOTween API의 실제 코드 사용이 확인된 경우입니다. 기존 베이스는 이벤트 경계에서 `DOMove`, `DOFade`, `DOScale`, `Sequence` 등을 만들고 완료 후 자동 정리 또는 명시적 `Kill()`을 사용합니다. 반복 트윈은 측정 후 재사용을 검토합니다. `DOTWEEN001`은 선택 프로필이 확정됐을 때 파괴 수명 정리 누락 등 명확한 위반을 검사합니다.

```csharp
private Tween m_moveTween;

private void OnDestroy()
{
    if (m_moveTween != null)
    {
        m_moveTween.Kill();
        m_moveTween = null;
    }
}
```

## `leantween`

LeanTween API의 실제 사용이 확인된 경우입니다. 반환 식별자 또는 프로젝트 Wrapper로 소유권을 추적하고 대상 비활성화·파괴 시 취소합니다. 정확한 정리 API는 설치 버전과 기존 프로젝트 코드를 기준으로 확인합니다.

## `custom`

프로젝트 소유 트윈 시스템인 경우입니다. Handle, 취소, 완료 콜백, 대상 파괴, 시간 스케일과 풀링 계약을 문서화합니다. 공통 인터페이스는 복수 구현 또는 테스트 대체 요구가 있을 때만 도입합니다.

## `none`

트윈 엔진을 사용하지 않는 경우입니다. 트윈 패키지 설치나 제품별 코드를 권고하지 않습니다. 애니메이션 요구는 Animator, 직접 보간 또는 프로젝트가 승인한 방식으로 해결하고 수명 정리를 유지합니다.

## `unknown`

사용 근거가 부족하거나 복수 엔진 증거가 충돌하는 상태입니다. 제품별 `Kill` API를 강제하지 않고 대상 파괴 후 실행 위험과 반복 생성만 진단합니다.


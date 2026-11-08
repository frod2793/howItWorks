# 비동기 프로필

> `async_backend` 선택과 관계없이 작업 소유자, 취소, 예외 관찰, 씬·오브젝트 수명 종료 시 정리 경로를 명시합니다.

## 공통 수명 원칙

- 작업 소유자는 시작, 취소와 완료 관찰의 책임을 가집니다.
- 파괴된 Unity 객체를 continuation에서 사용하기 전에 수명과 Unity null 상태를 확인합니다.
- fire-and-forget은 예외 처리 정책이 있는 명시적 경계에서만 사용합니다.
- 매 프레임 비동기 작업을 반복 생성하지 말고 실제 병목과 할당을 측정합니다.

## `unitask`

UniTask API의 실제 코드 사용이 확인된 경우입니다. 기존 베이스는 `UniTask`, `UniTask<T>`, 반환값 없는 경계의 `UniTaskVoid`, `CancellationToken`, `GetCancellationTokenOnDestroy()`와 명시적 `.Forget()`을 사용합니다. `UNITASK001`은 선택 프로필이 확정됐을 때 취소 토큰 누락 등 명확한 계약 위반을 검사합니다. 테스트 소스(`Tests`·`Test` 경로 또는 `[UnityTest]`·NUnit·TestRunner 마커)는 Unity Test Framework가 `IEnumerator`와 `yield return`을 강제하므로 `UNITASK001` 검사에서 제외합니다.

```csharp
private async UniTask LoadAsync(CancellationToken cancellationToken)
{
    await UniTask.Yield(cancellationToken);
}
```

## `coroutine`

`IEnumerator`, `StartCoroutine` 사용이 프로젝트의 표준인 경우입니다. Coroutine 핸들을 소유하고 `OnDisable`, `OnDestroy` 또는 명시적 상태 종료에서 중단합니다. Coroutine은 자동으로 성공·실패 값을 전달하지 않으므로 오류·취소·중복 시작 정책을 별도로 둡니다. 이 분기에서는 Coroutine을 일괄 금지하지 않습니다.

## `task`

`System.Threading.Tasks.Task` 사용이 확인된 경우입니다. Unity API 호출이 필요한 continuation의 실행 컨텍스트를 명시하고 `CancellationToken`과 예외 관찰을 유지합니다. 백그라운드 스레드에서 Unity 객체를 직접 조작하지 않습니다.

## `mixed`

둘 이상의 백엔드가 역할별로 공존하는 경우입니다. 예를 들어 SDK의 Task를 경계 Adapter에서 프로젝트 표준으로 변환합니다. 변환 위치, 취소 전파와 예외 매핑을 문서화하고 기능 코드가 임의로 백엔드를 섞지 않게 합니다.

## `unknown`

사용 근거가 부족하거나 서로 충돌하는 상태입니다. 특정 비동기 제품이나 Coroutine 금지를 강제하지 않고, 실제 호출과 수명 정리 증거를 수집합니다.

# 범용 Unity 하네스 테스트

- **작성자**: 윤승종
- **목적**: Bash 3.2와 PowerShell 5.1+ 구현이 같은 프로필·감지·린트 계약을 지키는지 확인합니다.

## 실행 권한

이 문서의 테스트 명령은 사용자가 해당 검증을 현재 요청한 경우에만 실행하는 예시입니다. 요청하지 않은 테스트는 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거가 아닙니다. 테스트 러너 코드·스크립트를 수정한 경우 아래 `bash -n`과 같은 컴파일·구문 오류 확인은 별도의 필수 예외이고, 문서만 변경하면 `N/A`입니다.

## 검증 선택과 시간 기록

관련 기존 그룹만 선정 이유와 함께 실행하며 자동 추측 실행하지 않습니다. [실행 계획 템플릿](../docs/exec-plans/_TEMPLATE.md)의 검증 표에 명령·그룹, 입력 revision/hash, 환경, 예상 초·실제 초, 결과·로그, 재실행 이유를 기록합니다. 작업 전체 시간과 검증 실행 시간은 분리합니다. timeout·중단은 PASS가 아니며 미실행은 `not_run`입니다. 같은 입력·환경에서 통과한 검증은 새 변경·실패·미해결 우려가 없으면 반복하지 않습니다. 표는 본문 증거이며 workflow schema·상태·진입점 변경이나 실행 권한 추가가 아닙니다.

## Bash 실행

사용자가 Bash 테스트를 현재 요청한 경우 프로젝트 루트에서 다음 명령을 실행합니다.

```bash
bash .agents/tests/run-tests.sh
bash .agents/tests/run-tests.sh --group profile --runtime bash
bash .agents/tests/run-tests.sh --group validation --runtime bash
```

지원 그룹은 `profile`, `detection`, `readonly`, `lint`, `docs`, `entrypoints`, `tooling`, `validation`, `parity`이며 기본값 `all`은 모든 그룹을 실행합니다. Bash 러너의 런타임 필터는 `all`, `bash`만 지원합니다. `--runtime powershell`, 알 수 없는 그룹 또는 선택된 테스트가 0개인 요청은 거짓 성공을 막기 위해 종료 코드 `2`로 거부합니다.

## PowerShell 실행

사용자가 PowerShell 테스트를 현재 요청한 경우 Windows PowerShell 5.1에서 다음 명령을 실행합니다.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/tests/run-tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/tests/run-tests.ps1 -Group profile -Runtime powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .agents/tests/run-tests.ps1 -Group validation -Runtime powershell
```

PowerShell 7 이상에서는 `powershell` 대신 `pwsh`를 사용할 수 있습니다.

PowerShell 러너의 런타임 필터는 `all`, `powershell`만 지원합니다. `-Runtime bash`, 알 수 없는 그룹 또는 선택된 테스트가 0개인 요청은 종료 코드 `2`로 거부합니다.

## 검증 범위

각 테스트는 임시 프로필·Unity 프로젝트·린트 위반 픽스처를 만들고 공개 API를 실제로 호출하여 반환 코드, 출력, 파일 생성·보호 상태를 검증합니다.

- `profile`: 설정 파싱, 검증, 원자적 쓰기와 확정
- `detection`: Unity·패키지·코드 증거, 아키텍처, 보고서와 오류 코드. 패키지 키 캐시는 각 `detect_project` 실행 안에서만 유효합니다.
- `readonly`: `.agents` 외부 프로젝트 파일 무변경. 파일 목록·각 체크섬 생성 실패도 검증 실패로 처리합니다.
- `lint`: Core·선택 프로필 규칙과 진입점
- `docs`: 규칙 의미 계약, 링크·파일 참조와 외부 런타임 의존 금지. `.agents/` 참조 검사는 전체 동기화 제외 계약의 프로젝트 로컬 기록(`artifacts/`·`reports/`·`work-items/`, `docs/exec-plans/` 하위의 날짜별 계획)을 제외하고, exec-plans의 README·`_TEMPLATE`을 포함한 하네스 문서의 누락 경로는 실패합니다.
- `entrypoints`: AGENTS·아키텍처·온보딩·템플릿 라우팅
- `tooling`: 전역 도구 상태, 안전한 설정 파싱, 독립 스킬·복수 캐시 버전, 캐시·설치 자식 경로의 물리 루트 감금, 읽기 전용 확인과 명시적 설치 경계
- `validation`: `module_scope`·`interaction_scope`와 결과의 exact match, 누락·예상 밖·중복·잘못된 레코드 차단, prebuild/built의 `build_run_id`와 lowercase artifact hash, 동일 change-id 및 read-only 증거 검증
- `parity`: PowerShell 정적 계약과 런타임이 있을 때 Bash 비교

종단 계약은 `감지 → pending 경고 → 확정 → error → 재감지 후보` 순서를 같은 임시 프로젝트에서 실행하며, 확정 프로필 체크섬과 `.agents` 외부 체크섬이 유지되는지 확인합니다.

테스트 러너 스크립트를 변경한 경우 자체 문법은 다음 명령으로 반드시 별도 확인합니다. 문서만 변경한 경우에는 실행하지 않고 `N/A`로 기록합니다.

```bash
bash -n .agents/tests/run-tests.sh
```

## UTF-8 인코딩 계약

- `run-tests.ps1`은 Windows PowerShell 5.1에서 한글이 안전하게 해석되도록 **UTF-8 BOM 포함**으로 저장합니다.
- `.agents/config/*.conf`와 테스트가 만드는 모든 설정·픽스처 파일은 **UTF-8 BOM 없음**으로 저장하며, 줄 끝은 LF와 CRLF를 모두 허용합니다.
- PowerShell 테스트는 `System.Text.UTF8Encoding(false, true)`을 명시해 설정을 읽고 씁니다.
- 프로필과 스키마의 첫 키에 BOM 문자가 섞이는 것을 허용하지 않습니다. BOM 포함 프로필은 지원 대상이 아닙니다.

## PowerShell 미검증 경계

실행 환경에 `powershell` 또는 `pwsh` 런타임이 없으면 결과에 **PowerShell 실행 검증 미실시**라고 기록합니다. 이 경우 BOM, 구분자 균형, 금지 API와 계약 문자열의 정적 검사만 수행하며 이를 PowerShell 5.1+ 동작의 실행 증거로 간주하지 않습니다. PowerShell이 설치된 Windows 환경에서 위 명령을 다시 실행해야 교차 플랫폼 검증이 완료됩니다.

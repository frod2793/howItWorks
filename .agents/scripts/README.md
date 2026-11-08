# 범용 하네스 스크립트 가이드

스크립트는 프로젝트를 감지하고 확정 프로필에 맞는 규칙을 검사합니다. Bash와 PowerShell 진입점은 같은 작업 흐름과 종료 코드 계약을 제공합니다. 기준 플랫폼은 macOS이며 canonical 런타임은 Bash입니다. PowerShell 스크립트는 Windows 참고용이고 PowerShell 실행 검증 미실시 상태이므로 결과가 다르면 bash 결과를 기준으로 합니다. Unity Editor 설치 확인과 요청된 테스트·빌드 실행은 [Unity CLI 실행 가이드](../docs/onboarding/unity-cli.md)를 따릅니다.

이 문서의 검사·CI·검증기·테스트 명령은 사용자가 해당 실행을 현재 요청한 경우에만 사용하는 예시입니다. 요청하지 않은 항목은 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거로 사용하지 않습니다. 적용 가능한 코드·스크립트를 수정했을 때의 컴파일·구문 오류 확인은 별도의 필수 예외이고, 문서만 변경하면 `N/A`입니다.

## 초기화·검토·확정·검사

### 1. 초기화

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot .
```

최초 감지는 `pending` 프로필을 만들며 게임 소스를 수정하지 않습니다.

### 2. 감지 보고서 검토

`.agents/reports/detection-report.md`의 신뢰도와 근거를 검토하고 `.agents/config/project-profile.conf`의 선택값, `${source_root}`, `${test_root}`, `exclude_root`를 실제 프로젝트와 맞춥니다.

### 3. 프로필 확정

```bash
bash .agents/scripts/init/initialize-harness.sh --project-root . --confirm
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot . -Confirm
```

확정 프로필은 일반 초기화로 덮어쓰지 않습니다. 새 감지 결과와 비교하려면 Bash의 `--redetect` 또는 PowerShell의 `-Redetect`를 사용합니다.

### 4. 검사 명령 준비

다음 명령은 사용자가 현재 하네스 검사를 요청한 경우에만 실행합니다.

```bash
bash .agents/scripts/lint/check-harness.sh --project-root .
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/lint/check-harness.ps1 -ProjectRoot .
```

기계 판독 출력은 Bash의 `--format machine`, PowerShell의 `-Format machine`을 사용합니다.

## 진입점

| 역할 | Bash | PowerShell |
|------|------|------------|
| 감지·확정 | `scripts/init/initialize-harness.sh` | `scripts/init/initialize-harness.ps1` |
| 프로필 검사 | `scripts/lint/check-harness.sh` | `scripts/lint/check-harness.ps1` |
| 전체 CI 검사 | `scripts/ci/pre-commit-checks.sh` | `scripts/ci/pre-commit-checks.ps1` |
| 에이전트 도구 확인 | `scripts/setup/check-agent-tooling.sh` | `scripts/setup/check-agent-tooling.ps1` |

`scripts/lint/check-architecture.sh`는 기존 호출자를 위한 Bash 호환 래퍼입니다. 새 문서와 자동화는 `check-harness`를 직접 사용합니다.

## 프로필 상태와 검사

- `pending`: Core 위반은 오류, 선택 Profiles 위반은 경고로 보고합니다.
- `confirmed`: Core와 확정된 Profiles 위반을 해당 심각도로 보고합니다.
- `architecture=custom`: 일반 아키텍처 전용 검사를 건너뛰고 프로젝트가 기록한 경계를 사용합니다.
- Optimization Base는 설정을 자동 변경하지 않으며 측정·롤백 판단 자료로 사용합니다.

## 코드 검사 경계

코드 검사는 `project-profile.conf`의 `source_root`를 사용하며 모든 `source_root`는 `Assets/_Game` 또는 그 하위 경로여야 합니다. `Assets/_Game` 밖의 Asset Store, UPM과 기타 외부 에셋 코드는 검사하지 않습니다. `_Game` 내부의 외부 원본만 `exclude_root`로 명시합니다.

## 종료 코드

| 코드 | 의미 |
|------|------|
| `0` | 정상 완료 또는 차단 오류 없음 |
| `1` | 확정 규칙 위반 발견 |
| `2` | Unity 프로젝트 아님 또는 안전하지 않은 출력 경계 |
| `3` | 인자·프로필·확정 입력 오류 |
| `4` | 필수 파일·도구·읽기 오류 |

## Unity 기능·마일스톤 검증기

다음 검증기 명령은 사용자가 현재 기능·마일스톤 검증을 요청한 경우에만 실행합니다. 미요청 결과는 `not_run`으로 유지하며 게이트 통과 증거로 사용하지 않습니다.

검증기는 증거 파일만 읽는 pure read-only gate이며, Unity Editor·Player Build·프로젝트 파일을 변경하지 않고 `change_id`도 계산하지 않습니다. 호출자는 실제 무효화 범위에서 직전에 계산한 expected change id를 증거와 인자로 전달해야 하며 stale 값을 재사용하면 안 됩니다.

### 증거 필드

| 필드 | 계약 |
|------|------|
| `coverage_status` | 실제 project-owned inventory를 확정한 `confirmed`만 허용 |
| `module_scope` | 프로젝트 소유 모듈의 실제 식별자 목록 |
| `interaction_scope` | 프로젝트 소유 모듈 상호작용의 실제 식별자 목록 |
| `module_result`, `interaction_result` | 각 scope와 exact match인 통과 결과 |
| `build_authority` | selected build_authority인 `local` 또는 `unity_ci` 한 값 |
| `build_run_id` | prebuild는 `pending`, built는 실제 실행 ID (앞뒤 공백·대소문자 정규화 후 `n/a`, `none`, `unknown`, `not_run`, `pending`, `tbd`, `-` 금지) |
| `build_artifact_hash` | prebuild는 `pending`, built는 lowercase 64-hex SHA-256 |

missing/unexpected/duplicate/invalid scope·result, 실패하거나 실행하지 않은 자동화 테스트는 게이트 실패입니다. generic consumer가 같은 evidence path와 prebuild 다음 built의 phase sequence를 보장합니다. prebuild에서 선택 권위를 보관하고 built의 필수 `--expected-authority`/`-ExpectedAuthority` 인자로 전달합니다. 누락은 인자 오류이며 다른 권위는 게이트 실패입니다.

### prebuild

```bash
bash .agents/scripts/validation/check-unity-milestone.sh \
  --evidence .agents/reports/[milestone-evidence].conf \
  --phase prebuild \
  --change-id [change-id]
```

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .agents/scripts/validation/check-unity-milestone.ps1 `
  -Evidence .agents/reports/[milestone-evidence].conf `
  -Phase prebuild `
  -ExpectedChangeId [change-id]
```

### built

```bash
bash .agents/scripts/validation/check-unity-milestone.sh \
  --evidence .agents/reports/[milestone-evidence].conf \
  --phase built \
  --change-id [change-id] --expected-authority [prebuild에서-선택한-local-또는-unity_ci]
```

```powershell
powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File .agents/scripts/validation/check-unity-milestone.ps1 `
  -Evidence .agents/reports/[milestone-evidence].conf `
  -Phase built `
  -ExpectedChangeId [change-id] -ExpectedAuthority [prebuild에서-선택한-local-또는-unity_ci]
```

`--phase`/`-Phase`는 `prebuild` 또는 `built`입니다. 두 검증기의 본문 종료 코드는 성공 `0`, 게이트 실패 `1`, 정의된 인자 오류 `3`, 입력 파일·스키마 오류 `4`입니다. PowerShell 검증기는 정의된 빈/누락 값을 본문에서 3으로 종료합니다. 알 수 없는 매개변수 또는 토큰 구문 오류는 CmdletBinder native nonzero로 종료되므로 모든 자동 호출은 `-NonInteractive`를 포함해야 합니다.

## 테스트

다음 테스트 명령은 사용자가 현재 요청한 범위에서만 실행합니다. 미요청 테스트는 `not_run`입니다.

```bash
bash .agents/tests/run-tests.sh --group entrypoints
bash .agents/tests/run-tests.sh --group all --runtime bash
```

PowerShell 런타임이 설치되어 있고 사용자가 동등성 테스트를 현재 요청한 경우에만 `.agents/tests/run-tests.ps1`을 실행합니다.

## 에이전트 도구 확인

다음 상태 확인·도구 테스트 명령도 사용자가 현재 요청한 범위에서만 실행합니다.

```bash
bash .agents/scripts/setup/check-agent-tooling.sh --check
bash .agents/tests/run-tests.sh --group tooling
```

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup/check-agent-tooling.ps1 -Check
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/tests/run-tests.ps1 -Group tooling
```

누락 설치는 `--install-missing` 또는 `-InstallMissing`을 명시한 경우에만 수행합니다. 일반 초기화·검사·CI는 네트워크나 전역 설정을 변경하지 않습니다. 상세 정책은 [에이전트 도구 준비](../docs/onboarding/agent-tooling.md)를 참조합니다.

도구 확인 진입점에서 `--check`의 미준비 상태와 `disabled`·`broken` 자동 복구 거부는 종료 코드 `1`, 설정·인자 오류는 `2`, 실제 설치 명령 실패는 `3`을 반환합니다. Superpowers는 공식 저장소를 임시 경로에 clone해 필수 스킬을 검증한 뒤 `${CODEX_HOME:-$HOME/.codex}/superpowers`로 이동하고 사용자 홈의 전역 `superpowers` 스킬 링크를 연결합니다.

도구 캐시와 설치 대상의 물리 경로가 사용자 홈 또는 `CODEX_HOME` 밖으로 이탈하면 설치 명령 실행 전에 종료 코드 `3`으로 중단합니다. `disabled`·`broken` 복구 안내는 설정 비파괴 백업 → 설정 활성화·교정 → 충돌 경로 이동 → 설치 → `--check`/`-Check` 재검증 순서로 제공합니다.

## 보호 hook의 셸 문법 파서

`hooks/protect-agents-dir.py`는 PreToolUse JSON의 Bash·zsh 명령을 동봉된 CST 파서로 정적 검사합니다. 명령을 실행하지 않으며, 지원하는 복합 구문에서 실행 가능한 명령·치환·리다이렉션을 기존 보호 정책에 전달합니다. 이 hook은 실수 방지 장치이며 같은 OS 권한으로 실행되는 임의 코드에 대한 보안 경계가 아닙니다.

검사 보장 범위와 검수 기준은 다음과 같습니다.

- 범위 안(결함으로 수정): 에이전트가 일반적인 셸 형태(직접 명령·리다이렉션, git 쓰기 명령, 파이프·heredoc으로 셸에 넘긴 스크립트, 복합문·치환)로 보호 경로를 쓰기·삭제·이동하는 명령을 통과시키는 경우와, 정상 명령을 차단하는 경우입니다.
- 범위 밖(한계로 기록): 사용자 함수·alias·`enable`로 셸 내장 명령을 가리거나 바꾸기, `eval`·동적으로 만든 명령 이름, interpreter 안의 동적 코드, 파서가 받지 못하는 비표준 인용 조합처럼 검사를 피하도록 구성한 입력입니다. 새 우회가 발견되어도 hook을 확장하지 않습니다.
- 동봉 파서가 지원하지 않는 문법(한 명령의 다중 heredoc, escape가 있는 `$'...'` 구분자 등)은 정상 명령이어도 차단을 유지하며 한계로 기록합니다.
- 판정할 수 없는 형태는 차단합니다(fail-closed). hook이 놓친 변경은 `git status`·`git diff`로 확인합니다.

- 런타임은 Python 3.9 이상, `hooks/shell_cst.py`, `hooks/shell-parser/`의 여섯 파일(`bin/tsparse-macos-universal`, `tsparse.c`, `build.sh`, `manifest.json`, `THIRD_PARTY_NOTICES.md`, `sources.tar.gz`)을 사용합니다. 실행 중 pip·빌드·네트워크가 필요하지 않습니다.
- 배포 대상은 macOS 11 이상 universal 바이너리입니다. arm64 실행은 검증했고 x86_64 실행과 Windows는 `not_run`입니다.
- 번들 문법은 `!` 뒤의 brace/if/while/subshell 실행 본문과 비인용 heredoc의 backtick 명령 치환을 CST 자식으로 보존합니다. 인용 delimiter와 escape된 backtick은 자료로 유지합니다. `sources.tar.gz`의 `grammar.patch`·`scanner.patch`와 `tree-sitter.json`은 생성 경로를 고정하며, Bash·Zsh 각각의 `src/parser.c`를 빌드에 사용합니다.
- 생성기 provenance: 고정 tree-sitter-cli 0.25.10 (SHA-256 `374f6f9733a3f3e2dff72fcc1640b35c7d75ab60f531c8dc5865af3a12a28411`)으로 소스 아카이브를 푼 뒤 Bash 디렉터리에서 `tree-sitter generate --abi 15 grammar.js`, Zsh 디렉터리에서 같은 명령을 각각 실행합니다. 각 dialect의 `src/parser.c`·`src/grammar.json`·`src/node-types.json` 생성물과 manifest hash를 대조한 다음 빌드합니다.
- 재현 빌드는 Apple clang 21.0.0·macOS SDK 26.5와 동봉 소스가 같을 때 `REBUILD_DIR=$(mktemp -d) && sh .agents/scripts/hooks/shell-parser/build.sh universal "$REBUILD_DIR/tsparse-macos-universal" && shasum -a 256 "$REBUILD_DIR/tsparse-macos-universal"`로 확인합니다(기대 SHA-256: `a400104f76a4d2d16e01e42ae9bdd45ca656192f7bfd2c3fcab83d8e66c95e04`). 기존 `arm64`·`x86_64` 인자도 유지합니다. 이 명령은 오프라인 빌드 재현 검사이며 hook 실행 중 자동 빌드가 아닙니다. x86_64 바이너리의 실제 실행과 Windows는 `not_run`입니다.
- 패키지가 없거나 해시가 맞지 않거나 실행 플랫폼·문법을 판정할 수 없으면 hook은 종료 코드 2로 차단합니다. 동봉 패키지와 manifest를 함께 복원하거나 하네스를 동기화해야 합니다.
- 파서는 첫 CST에서 따옴표·주석·here 문서 범위를 확인하고 줄 연결을 정규화한 뒤 같은 native 파서로 다시 검사합니다. 분석할 수 없는 here 문서 줄 연결과 재파싱 후 남는 활성 줄 연결은 차단합니다. Bash·zsh의 정적으로 확인한 stdin 스크립트는 검사하고, `sh`·`dash`·`ksh`의 stdin 스크립트는 지원하지 않아 차단합니다. `cat`의 stdin은 자료로 취급합니다. fd 번호가 0이 아닌 here 문서·herestring·입력 리다이렉트는 stdin을 바꾸지 않으므로 부모 stdin을 그대로 상속하고, `<&N` 복제는 stdin을 알 수 없음으로, `exec` 입력 리다이렉트가 이후 stdin을 바꾸는지는 무해 대조로 확인한 셸별 표를 따릅니다: Bash는 인용·escape·`command` 접두의 `exec`만(`command`의 `-p` 뒤 `--`는 옵션을 끝내므로 그다음 단어가 명령 이름), zsh는 인용·escape·`builtin`·`noglob`·`nocorrect`·`-` 접두의 `exec`만 지속으로 보고(zsh는 파이프라인 마지막 단계 포함), 첫 단어가 사용자 함수면 지속하지 않고, zsh에서 접두어 뒤의 `builtin`·`exec`가 사용자 함수면 stdin을 알 수 없음으로 두며, 앞서 정의된 alias 이름이 그 명령의 단어에 있거나, 이름을 확정할 수 없는 alias 정의(`$1`·명령 치환 등)·`enable`·`disable`·`eval`·`source` 뒤이면 stdin을 알 수 없음으로 두고, 표에 없는 형태(zsh의 인자 있는 `exec` 등)는 stdin을 알 수 없음으로 둡니다. 문법이 `! for`·`! select`·`! time`·`! case` 등을 잘못 나누거나 파싱하지 못하면 `!` 한 바이트만 공백으로 바꿔 다시 파싱해 본문을 검사하고, 그 복합문의 종료 상태는 참·거짓 두 경우를, 상태는 본문이 실행된 경우와 실행되지 않은 경우(Bash 3.2의 `! time f`는 함수를 실행하지 않음)를 모두 이어서 검사합니다(사용자 `true`/`false` 함수나 Bash의 `! time` 특성에 의존하지 않음). 파싱이 실패하면 문법이 받지 못하는 인용 here 문서 구분자(`'! 'E`처럼 나뉜 인용, `<<-`의 앞 공백, escape 없는 `$'...'`)와 그 종료 줄을 같은 길이의 `'ZZ..'`·`ZZ..`로 바꿔 다시 파싱하며, 바꾼 위치가 최종 트리에서 한 리다이렉트의 `heredoc_start`·`heredoc_end`와 정확히 일치할 때만 사용하고 아니면 차단합니다. 파싱 실패 대체 경로에서는 here 문서 구분자와 종료 줄의 `!`는 처음부터 제외하고, 문자열·주석·here 문서 본문·명령 인자 안의 `!`는 되돌리며, `!` 바로 뒤 줄 연결은 공백으로 바꿔 위치를 유지합니다(분류가 실패하면 줄 연결 없이 다시 분류). 최종 트리에서도 문장 위치가 아닌 `!`는 차단합니다. 그래도 명령 이름 자리에 셸 예약어가 남으면 차단합니다. `exec_command`의 `tool_input.workdir`는 세션 cwd 기준으로 명령 기준 경로에 적용하며 문자열이 아니면 차단합니다. `time`·`/usr/bin/time`은 wrapper로 벗겨 실제 명령을 검사하며 `-o`/`--output` 파일은 보호 쓰기 검사를 거칩니다.
- 확인된 Bash·zsh 복합 명령은 정상 읽기와 허용된 쓰기를 유지합니다. `git apply`는 로컬 정규 patch의 변경 경로를 Git의 읽기 전용 `--numstat`으로 양방향 검사합니다. 분석할 수 없는 `git am`·`patch`의 쓰기는 보호 대상 프로젝트에서 차단합니다. 임의 interpreter·동적 코드 실행은 검사 보장 범위 밖이며, 모든 셸 문법을 지원한다고 주장하지 않습니다.

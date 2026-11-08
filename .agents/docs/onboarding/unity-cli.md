# Unity CLI 실행 가이드

## 목적과 경계

이 문서는 Unity 공식 CLI(`unity` 명령)를 하네스 검증 흐름의 실행 수단으로 쓰는 기준입니다. CLI는 실행 도구일 뿐 권한이 아닙니다. 기존 검증 실행 권한, 증거 권위와 상태 전이 기준을 변경하거나 확대하지 않습니다.

- 기준 플랫폼은 macOS이며 기본 설치 경로는 `~/.unity/bin/unity`입니다.
- 사용자가 현재 요청한 검증·빌드만 CLI로 실행합니다. 요청하지 않은 항목은 `not_run`입니다.
- `unity install`, `unity upgrade`, `install-modules`와 `--allow-install` 등 설치·다운로드성 동작은 외부 도구 경계에 따라 사용자가 현재 명시적으로 요청한 경우에만 사용합니다.
- CLI 출력은 검증 증거의 입력일 뿐입니다. 권위 증거 형식과 무효화 기준은 [Unity 기능·마일스톤 검증 정책](../coding-standards/core/unity-validation.md)을 그대로 따릅니다.

## CLI 단일 원칙

Unity 검증·빌드·실행 중 Editor 상호작용은 Unity CLI(`unity` 명령)와 Pipeline으로 수행합니다. Unity MCP는 사용하지 않으며, 실행 중 Editor와의 상호작용도 Pipeline 패키지(`com.unity.pipeline`)가 등록한 명령을 `unity command`로 호출해 수행합니다. Editor가 없어도 되는 작업은 배치로, Editor 상호작용이 필요한 작업은 상주 Editor의 Pipeline 인스턴스 또는 headless `unity run --command`로 수행합니다.

- 배치(Editor 상주 불요): 테스트 실행(`unity test`), 빌드(`unity build`), 등록 명령 headless 실행(`unity run <물리 경로> --command <명령>`), 환경 진단(`unity doctor --ci`), Editor 설치 확인(`unity editors --installed`), 인스턴스·프로세스 확인(`unity status --format json`, `unity pipeline list`)
- 상주 Editor(Pipeline 인스턴스): 씬·GameObject·프리팹·컴포넌트·에셋 조작, Console 조회(`unity command console`), 강제 컴파일(`unity command recompile` → `recompile_status`), Editor 상태(`unity command editor_status`), 테스트(`unity command run_tests` → `test_status`), 스크린샷, 프로젝트가 등록한 명령(`unity list`로 확인). Console 실시간 관측은 `console` 응답의 cursor를 다음 동일 프로젝트 호출의 `since`로 전달하고 종료 조건을 정합니다. Overlay UI 시각 검증은 승인된 PlayMode에서 `capture_game_view source=screen`을 사용하며 camera 출력이나 headless 결과를 같은 증거로 인정하지 않습니다. `build`·베이크류는 `queued`를 반환하므로 `build_status`·`*_status`로 완료를 확인합니다. 사용 전에 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)의 identity 게이트를 통과합니다.
- 상주 Editor를 쓰는 작업을 시작할 때만 Editor 바인딩 준비 절차를 수행합니다. 배치만으로 완결되는 작업은 Editor 실행과 바인딩을 요구하지 않습니다.
- 상주 Editor가 없거나 불가하면(인스턴스 없음·exact match 실패·`editor_status`가 `ready`도 아니고 현재 승인된 PlayMode 관측·정지·캡처 작업의 `playing`도 아님·연결 상실) 중단하지 않고 배치 **백그라운드 경로**로 진행합니다 — 구현은 파일 수준, 검증은 물리 경로를 명시한 CLI, Editor 상호작용 항목은 `unity run --command`로 headless 수행하고 그것도 불가하면 `not_run: editor_unavailable`. 기준은 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)의 "Editor 불가 시 백그라운드 경로"입니다.
- Editor 비의존 변경의 컴파일 확인(정의는 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)의 적용 범위): ① 대상 워크트리에 상주 전용 Editor가 있으면 `unity command recompile --project-path <물리 경로>` 후 `recompile_status`와 `console`로 판정합니다(이 순간 identity 게이트 적용). ② 상주 Editor가 없으면 `ProjectVersion.txt` 버전의 Editor 실행파일(`unity editors --installed`로 경로 확인)로 `-batchmode -nographics -quit -projectPath <물리 절대 경로> -logFile <경로>`를 실행해 종료코드와 로그의 컴파일 오류로 판정합니다. ③ 둘 다 불가(Library 잠금 충돌 등)하면 `not_run`으로 기록하고 성공으로 주장하지 않습니다.
- 반복 검증 루프 예외: 같은 실행 루트에서 동일 작업의 검증을 2회 이상 반복할 때는 2회차부터 상주 Editor 경로(`unity command run_tests`)를 우선해 배치 Editor 재기동 비용을 제거할 수 있습니다. 증거 기준과 기록 형식은 불변이며 실행 수단을 함께 기록합니다. 도메인 리로드 시간이 눈에 띄게 증가하면 해당 Editor를 재시작합니다.
- 이 원칙은 도구 선택 기준일 뿐 검증 실행 권한, Editor identity·격리 게이트와 증거 기준을 변경하지 않습니다.

## Editor 앱 직접 실행 예외

Editor 프로세스 기동은 아래 helper를 최초 진입점으로 사용합니다. helper 내부에서 CLI를 한 번 시도하고 없거나 실패하면 `ProjectVersion.txt`와 일치하는 설치된 Unity 앱을 한 번 직접 실행합니다. 이미 CLI 실패를 확인했다면 `--skip-cli`를 붙여 재실행하지 않습니다. 실행 중 Editor API·컴파일·테스트·빌드의 도구·권한·증거 기준은 바꾸지 않습니다.

```bash
bash .agents/scripts/setup/open-unity-editor.sh --project-root "/프로젝트/물리 경로"
# 이미 unity open 실패를 확인한 경우
bash .agents/scripts/setup/open-unity-editor.sh --project-root "/프로젝트/물리 경로" --skip-cli
# 자동 발견하지 못한 설치 앱을 직접 지정할 때
bash .agents/scripts/setup/open-unity-editor.sh --project-root "/프로젝트/물리 경로" --unity-app "/설치/Unity.app"
```

macOS에서 CLI 실패 뒤 `open -gna <검증한 Unity.app> --args -projectPath <물리 절대 경로>`를 한 번 호출합니다(`-g`: 앱을 앞으로 가져오지 않음). 앱 부재·버전 불일치·같은 프로젝트의 잠금/실행 중 Editor는 자동 설치·버전 대체·잠금 삭제·프로세스 종료로 우회하지 않습니다. helper는 macOS용이며 다른 OS에서 성공으로 처리하지 않습니다.

앱은 명시한 `--unity-app`을 우선하며, 없으면 Unity Hub의 `secondaryInstallPath.json`에 설정된 설치 경로와 기본 `/Applications/Unity/Hub/Editor`에서 정확한 버전을 찾습니다. 빈 Hub 설정 파일이나 빈 JSON 문자열은 추가 설치 경로 미설정으로 보고 기본 Hub 경로를 확인합니다. 읽을 수 없거나 인코딩·문법이 잘못된 Hub JSON은 실패로 반환하며 `--unity-app`으로 정확한 설치 앱을 지정하도록 안내합니다. 실제 plist의 `CFBundleVersion`을 우선 확인합니다. 설치 경로를 못 찾으면 사용자가 설치된 앱 경로를 지정하며 다운로드하지 않습니다. CLI 대기는 기본 180초(`--cli-timeout <초>`)로 제한합니다. 프로세스·잠금 조회는 순간 상태이므로 비동기 Hub 기동과의 완전한 원자적 배타를 보장하지 않습니다. 시간 초과는 부분 기동 여부가 불명확하므로 앱을 중복 실행하지 않고 실패로 반환합니다. 인스턴스·잠금을 확인한 뒤 재시도 여부를 결정하며 잠금 삭제나 Editor 종료는 자동 수행하지 않습니다.

`ps`는 인자 경계를 평문으로 합치므로 `/w/my -game`이 경로인지 `/w/my` 뒤 옵션인지 구분할 수 없습니다. 가능한 해석 중 대상 프로젝트와 일치하는 경로가 있으면 모호성 메시지와 함께 추가 기동을 보수적으로 차단하며, 같은 프로젝트가 실행 중이라고 확정한 것은 아닙니다. 실제 인스턴스와 물리 경로를 확인한 뒤 재시도 여부를 결정합니다.

잠금 파일 때문에 중단되면 대상 물리 경로의 Editor 프로세스와 `unity status`를 먼저 확인하고, 소유 Editor 및 실제 종료 여부를 확인한 뒤 프로젝트의 승인된 수동 복구 절차를 따릅니다. 남아 있다는 이유만으로 잠금을 삭제하거나 다른 Editor를 종료하지 않습니다.

출력 `launched_via=cli|app`, `identity=unverified`는 프로세스 실행 요청만 뜻합니다. 이후 `unity status --format json` → 동일 `project`·버전 확인 → `unity command editor_status --project-path <물리 절대 경로> --format json`의 `projectPath`·`unityVersion`·`status=ready`·`compiling=false` 확인 → `unity list --project-path <물리 절대 경로>` 순서를 통과해야 합니다. 승인된 PlayMode 관측의 기존 예외는 그대로입니다. 직접 실행 후에도 identity를 확정할 수 없으면 `background: editor_unavailable`로 전환하고 확인하지 못한 항목은 `not_run`으로 기록합니다. 다른 checkout이나 임의의 최신 Editor를 사용하지 않습니다.

## 상태 확인

상태 확인은 읽기 전용이며 사용자 홈과 전역 설정을 변경하지 않습니다.

```bash
bash .agents/scripts/setup/check-unity-cli.sh --check
bash .agents/scripts/setup/check-unity-cli.sh --preflight
```

`--check`는 `installed`, `missing`, `broken` 상태와 버전을 출력합니다. `--preflight`는 `unity doctor --ci`로 라이선스, 디스크, 네트워크 등 빌드·테스트 사전 조건을 진단합니다. CLI 누락은 Unity 코드 린트 실패가 아니며, 설치·복구는 사용자 지시를 기다립니다.

## 명령과 하네스 게이트 매핑

| 명령 | 하네스에서의 용도 | 경계 |
|---|---|---|
| `unity doctor --ci` | 검증·빌드 전 환경 preflight | 읽기 전용 진단 |
| `unity editors --installed` | `ProjectVersion.txt` 요구 버전의 Editor 설치 확인 | 조회만, 설치는 요청 시만 |
| `bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리경로>` | 올바른 버전 Editor 기동의 최초 진입점 | CLI 실패 확인 후에는 `--skip-cli`; 동일 버전 앱 기동 뒤에도 identity 게이트 유지 |
| `unity status --format json` | 실행 중 Pipeline 인스턴스의 `project`·`pid`·`port`·`version`·`state` 조회 | identity 판정의 입력, `project` exact match로만 확정 |
| `unity pipeline list` | 프로젝트별 Editor 실행·Pipeline 패키지 설치·서버 연결 가능 여부 확인 | 읽기 전용 |
| `unity command <명령> --project-path <물리경로>` | 상주 Editor의 Pipeline 명령 실행(씬·에셋 조작, `console`, `recompile`, `editor_status`, `run_tests`, 스크린샷 등) | identity 게이트 통과 후, `--project-path` 필수 |
| `unity list --project-path <물리경로>` | 대상 Editor에 등록된 명령(내장 + 프로젝트 등록) 확인 | 읽기 전용, 프로젝트 등록 명령을 먼저 확인 |
| `unity run <물리경로> --command <명령>` | 상주 Editor 없이 등록 명령을 headless 배치 Editor에서 실행 | 백그라운드 경로, Library 잠금 없을 때 |
| `unity job` | `--detach`로 제출한 장시간 명령의 반환 대기 | `unity job wait`는 명령 반환까지의 수단이다. 결과가 `queued`/`in_progress`이면 같은 프로젝트의 `build_status` 또는 해당 `*_status`로 실제 완료와 최종 결과를 확인한다 |
| `unity test --mode EditMode\|PlayMode --output <경로>` | 요청된 Unit·Integration 테스트 실행과 NUnit XML 증거 생성 | 요청된 범위만 |
| `unity build --profile\|--target --log-file <경로> -o <경로>` | 요청된 Build Validation 1회 실행, 로그·산출물 증거 생성 | 사전 게이트 통과 후 1회 |
| Editor 실행파일 `-batchmode -nographics -quit -projectPath <물리 경로> -logFile <경로>` | Editor 비의존 변경의 스크립트 컴파일 확인 | 같은 프로젝트를 연 Editor가 없을 때만, 종료코드·로그의 컴파일 오류로 판정 |

모든 명령은 대상 실행 루트의 물리 절대 경로를 project 인자로 명시해 실행합니다. 이름·glob 해석이나 현재 디렉터리 기본값에 의존해 다른 checkout을 대상으로 삼지 않습니다.

## batchmode 경계

기존 정책의 우회 금지는 다른 Editor·checkout·인스턴스로 대상을 바꾸는 행위를 뜻합니다. 같은 물리 경로를 명시한 batchmode·CLI는 상주 Editor가 없거나 불가할 때의 기본 백그라운드 경로이며 우회가 아닙니다. `unity test`와 `unity build`는 사용자가 해당 검증을 현재 요청했을 때의 공식 실행 수단이며, 다음 조건을 모두 충족할 때만 사용합니다. Editor 비의존 변경의 CLI·batchmode 컴파일 확인은 게이트 대상이 아니므로 우회가 아닙니다.

- 대상 실행 루트의 물리 경로에서 실행하고, `ProjectVersion.txt` 버전과 일치하는 Editor를 사용합니다.
- CLI가 스폰하는 batch Editor도 Unity 프로세스 1개로 계산해 동시 Unity 프로세스 예산에 포함합니다.
- 같은 프로젝트를 연 대화형 Editor가 있으면 Library 잠금 충돌이 발생할 수 있습니다. 전용 Editor를 정지한 뒤 실행하거나 실행 순서를 사용자와 조정하며, 충돌 상태의 결과를 증거로 쓰지 않습니다. 백그라운드 경로에서 그 Editor가 `editor_status`에도 응답하지 않으면 `unity status --format json`으로 물리 `project` exact match를 확인한 프로세스만 종료한 뒤 실행합니다(프로젝트 지침의 사전 승인이 없으면 종료 전 사용자 확인).
- 다른 checkout·worktree에서 실행한 CLI 결과는 대상 변경의 증거가 아닙니다. Editor 격리 기준은 [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)를 따릅니다.

## 증거 통합

### 검증 전후 입력 기록

승인된 검증의 import·package resolution 전후에 dirty/untracked를 기록하고 Unity 생성·삭제 파일을 검토한 뒤 최종 입력 manifest·SHA를 고정하고 `change_id`를 계산합니다. Git 예시는 대상 물리 루트에서 `git status --porcelain=v1 -z --untracked-files=all`로 경로·상태를 보관하고, manifest에 각 입력 경로·상태·SHA-256(부재는 명시)을 기록하는 것입니다. `shasum -a 256 -- <실제 파일 경로>`로 파일·manifest 및 `git rev-parse --git-path index`가 가리키는 실제 index 바이트의 hash를 보관하고, `git rev-parse HEAD`는 별도 provenance로 남깁니다. 비Git은 소비자가 정한 입력 manifest·내용 hash를 사용합니다. 증거 파일은 소비자의 입력 제외 범위에 보관합니다.

검증 후 같은 명령·범위로 manifest·SHA·`change_id`를 재계산해 전후를 대조합니다. status 목록이나 HEAD만 같아서는 충분하지 않습니다. `link.xml`·`.meta` 부재·복원도 내용 변경으로 검토하며 원인을 단정하지 않습니다. 입력이 달라지면 로그·기존 증거를 보존하고 해당 단계의 증거를 무효화한 뒤 새 검증 권한을 확인합니다. [검증 정책](../coding-standards/core/unity-validation.md)의 입력 안정화·증거 무효화 계약을 따릅니다.

- `unity test --output`의 NUnit XML과 `unity build --log-file`의 로그, `-o` 산출물은 검증 결과 기록의 입력입니다.
- 권위 증거는 기존 정책 그대로 `.agents/reports/unity-milestone-validation.conf` 하나이며, `build_artifact_hash`는 CLI가 만든 실제 빌드 산출물에서 계산합니다.
- CLI 종료 코드만으로 통과를 주장하지 않습니다. 리포트 파일과 로그의 실제 결과를 확인해 기록하고, 실행하지 않은 항목은 `not_run`으로 남깁니다.

## macOS 기준 플랫폼

- 하네스 스크립트의 canonical 런타임은 macOS의 Bash이며, 모든 예시는 bash 진입점을 우선합니다.
- PowerShell 스크립트는 Windows 참고용으로 유지하며 PowerShell 실행 검증 미실시 상태입니다. 결과가 다르면 bash 결과를 기준으로 합니다.

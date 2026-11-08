# 병렬 작업 규칙

## 목적과 경계

이 문서는 충돌하지 않는 범위에서 기능 개발과 검증을 동시에 진행하는 기준입니다. 병렬화는 실행 순서의 최적화일 뿐이며, [Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)의 안전 게이트, 검증 실행 권한과 증거 권위를 변경하거나 완화하지 않습니다.

## 계획 단계 병렬화 원칙

작업 계획을 수립할 때는 항상 병렬 처리를 우선 검토해 소요 시간 단축을 계획의 기본 목표로 삼습니다.

- 계획 단계에서 작업을 충돌하지 않는 write scope 단위로 분해할 수 있는지 먼저 판단하고, 가능하면 병렬 배정을 기본으로 합니다.
- 설계 단계에서도 같은 조건을 적용합니다: 병렬 작업이 가능하면 병렬 작업이 가능한 구조(충돌 없는 write scope 분해)로 설계하는 방향을 우선합니다.
- 순차 진행은 의존 관계(`depends_on`), 공유 핫스팟, Editor·프로세스 예산 등 구체적 근거가 있을 때만 선택하고 그 근거를 계획에 기록합니다.
- 검증도 동시 실행 규칙 범위에서 병렬로 계획합니다(예: `scripts/validation/run-parallel-tests.sh`).
- 병렬화는 시간 최적화일 뿐 안전 게이트, 검증 권한과 증거 기준을 변경하지 않습니다.

## 작업 단위와 소유권

- 병렬 단위는 `1 Task = 1 Branch = 1 linked worktree = 1 구현 에이전트`입니다.
- 각 Task는 생성·수정 가능한 경로 목록(write scope)을 시작 전에 명시합니다. write scope 밖의 파일은 수정하지 않으며, 서로 겹치는 write scope를 가진 Task를 동시에 배정하지 않습니다.
- 읽기는 자유이나, 다른 Task의 write scope에 있는 파일을 근거로 한 가정은 통합 시 재검증합니다.
- 의존 관계(`depends_on`)가 있는 Task는 선행 Task의 통합이 끝난 뒤에 시작합니다. 통합 Task는 항상 마지막 순서입니다.
- 역할 간 핸드오프는 관리자 폴링 대신 실행 루트 로컬 작업 큐(하네스 `work-items` 하위 `queue/` 디렉터리)로 자동화할 수 있습니다: 완료한 역할이 다음 역할의 태스크 파일을 큐에 기록하고, 다음 역할 세션이 파일 이동(rename) 방식의 self-claim으로 집어가 동시 클레임 경쟁을 방지합니다. 큐 사용 여부와 무관하게 역할 경계와 증거 기준은 불변입니다.

## worktree 생성 규칙

새 worktree는 아래 절차를 전부 마쳐야 작업 투입 가능 상태로 간주합니다. git 추적 파일은 자동으로 따라오지만, 하네스와 에이전트 설정은 gitignore 대상이라 복제하지 않으면 빈 상태로 시작합니다.

병렬(병행) 작업의 등록·준비도 별도의 생성 방식이 아니라 이 절차를 그대로 사용합니다. 전체 프로젝트 복제본을 만들어 병행 작업을 등록하지 않습니다 — 프로젝트 복제는 라이선스·디스크·동기화 문제를 일으키며, git worktree와 아래 복사 항목(2단계 하네스·에이전트 설정, 3단계 빌드 세팅 확인, 4단계 Library 초기화)으로 충분합니다.

워크트리 생성·보유 개수에는 상한을 두지 않습니다. 동시 실행 예산은 실행 중인 Unity 프로세스에만 적용되며 워크트리 생성을 제한하지 않으므로, Task 수요만큼 워크트리를 만들고 실행 순서만 예산 안에서 스케줄링합니다.

1. **경로는 ASCII로 만듭니다.** 한글 경로 worktree는 Android 빌드가 불가하며, GUI에서는 prerequisites 단계 고착으로 위장되어 원인을 찾기 어렵습니다.

   ```bash
   git worktree add ../<워크트리-상위-경로>/<ascii-name> -b <브랜치명>
   ```

2. **승인된 하네스 변경 파일만 동기화합니다.** 기존 worktree에는 변경 파일의 패치 배포를 우선하고 프로젝트별 프로필·상태·증거·계획을 보존합니다. 전체 하네스 동기화가 승인된 경우에만 다음 제외 계약으로 먼저 dry-run을 검토한 뒤 같은 명령에서 `--dry-run`만 제거합니다.

   ```bash
   rsync -a --dry-run \
     --exclude=config/project-profile.conf \
     --exclude=reports/ --exclude=work-items/ --exclude=artifacts/ \
     --exclude=docs/exec-plans/ --exclude=docs/product-specs/ --exclude=docs/troubleshooting/ \
     .agents/ ../<워크트리-상위-경로>/<ascii-name>/.agents/
   ```

   제외는 송신·수신 양쪽에 적용합니다. receiver `protect`(`P`)만 사용하면 삭제는 막아도 덮어쓰기를 막지 못합니다. 삭제 옵션은 기본으로 사용하지 않으며, 승인된 삭제 동기화에서도 `--delete-excluded`는 금지합니다. 보호 hook은 `--exclude`와 `-f`/`--filter`의 `- `·`H`·`P` 규칙만 허용하며, clear(`!`)·`R`·`S`·include·merge 규칙과 `--exclude-from`·`--files-from`·`-F`·`-C` 등은 거부합니다. 빈 새 worktree에는 계획 템플릿 등 필요한 파일만 별도로 초기화하고 부모의 work-items·증거를 복제하지 않습니다. `.claude`는 통째로 덮어쓰지 않고 기존 설정에 필요한 hooks만 병합합니다. settings.json이 없으면 `.agents/templates/claude-settings.json`으로 초기화합니다.

3. **빌드 세팅을 확인합니다.** `ProjectSettings/**`·`Packages/**`는 git 추적이라 자동으로 따라오므로 복사하지 않습니다. 기능 Task의 worktree에서는 공유 핫스팟을 수정하지 않습니다. 통합 담당(Integration Owner)만 사전에 확정된 write scope 안에서 자신의 통합 worktree에서 수정할 수 있습니다. 다만 gitignore 대상인 생성 에셋(라이브 자격 증명 등)은 따라오지 않으므로, 빌드·서버 검증이 필요한 Task는 루트와 대조해 필요분만 옮깁니다.

4. **Library는 복사로 초기화할 수 있습니다.** 빈 상태로 열면 전체 재임포트가 걸립니다. APFS에서는 clonefile 복사가 빠르고 디스크를 거의 쓰지 않습니다.

   ```bash
   cp -Rc Library ../<워크트리-상위-경로>/<ascii-name>/Library
   ```

5. **투입 전 확인.** `.agents/AGENTS.md`와 에이전트 설정이 존재하고 승인된 공통 변경이 반영됐으며 로컬 상태가 보존됐는지, Editor가 해당 worktree 경로로 열리는지 확인한 뒤 Task를 배정합니다.

worktree를 제거할 때는 작업 트리가 깨끗한지 확인하고 `git worktree remove`를 사용하며, 병합이 끝난 브랜치만 삭제합니다. squash 등 히스토리 재작성 전에는 `git branch --contains <분기점>`으로 하류 worktree 분기가 없는지 확인합니다.

worktree 재사용: 작업이 끝난 worktree는 즉시 제거하지 않고 정리(변경 커밋·병합 확인, 산출물 정리, 브랜치 전환) 후 유휴 풀로 유지할 수 있습니다. 새 Task는 새 worktree 생성보다 유휴 worktree 재할당을 우선해 Library 재복사·Editor 재기동 고정비를 회피합니다. 정리로 복구할 수 없는 오염(잠금·손상·추적 불가 변경)이 확인되면 폐기하고 새로 생성합니다.

## 공유 핫스팟

다음 경로·자산은 충돌 비용이 커서 통합 담당(Integration Owner) 한 명만 수정합니다. 기능 Task의 write scope에 포함하지 않습니다.

- `ProjectSettings/**`, `Packages/**`(manifest 포함)
- 메인·부트 씬(`Main*.unity`, `Boot*.unity` 등 프로젝트가 지정한 공유 씬)
- `*.inputactions`, `AddressableAssetsData/**`
- 공유 LifetimeScope·Composition Root, 공유 UI Stack·Canvas Root, Save Schema, Event Registry, Localization 테이블

기능 Task가 공유 핫스팟 변경을 요구하면 변경 요청만 기록하고, 통합 담당이 순차 반영합니다.

Unity Editor는 실행만으로 `ProjectSettings/EditorSettings.asset`이나 폰트 아틀라스 같은 공유 자산을 자동 변경할 수 있고, 오염되는 파일 집합은 실행 조건에 따라 달라집니다. 알려진 목록을 되돌리는 방식 대신 커밋 전 `git status`로 의도 외 변경을 전수 확인하고 되돌려 공유 핫스팟 비수정 원칙을 유지합니다.

## Editor 모드와 동시 실행 예산

Task 종류별 Unity Editor 필요 수준을 먼저 정합니다.

| Task 종류 | Editor 모드 |
|---|---|
| 문서 | 불필요 |
| 순수 코드 | 필요 시에만(on demand) |
| 에셋·씬 | 전용 Editor |
| 설정·빌드·통합 | 통합 담당 전용 |

- 동시 Unity 프로세스(대화형 Editor와 CLI가 스폰하는 batch Editor 모두 포함)는 최대 4개를 넘지 않습니다. 머신 성능이 확인되기 전에는 2개(통합 1 + 기능 1)로 시작해 상향합니다.
- 이 예산은 동시 실행 중인 프로세스에만 적용됩니다. 워크트리 생성·보유 개수는 제한하지 않습니다.
- 각 worktree는 자신의 전용 Editor와 `Library/`를 사용합니다. `Library/` 공유, symlink, junction과 강제 복사를 금지합니다.
- 실행 중 프로세스 현황은 `unity status --format json`으로 보조 확인합니다. 이 출력의 `project` exact match가 Editor identity의 입력이며, port·개수만으로 대상을 확정하지 않습니다.

## 동시 검증 실행

사용자가 요청한 검증 범위 안에서 다음 병렬화를 사용할 수 있습니다. 실행 수단은 [Unity CLI 실행 가이드](unity-cli.md)를 따릅니다.

- worktree 간 병렬 테스트: 서로 다른 물리 프로젝트이므로 `unity test`를 worktree별로 동시에 실행할 수 있습니다. 각 실행은 Unity 프로세스 예산 1개를 사용합니다.
- 같은 프로젝트 안의 대규모 스위트: `unity test --shard n/m`으로 분할해 병렬 실행할 수 있습니다. shard마다 Editor 프로세스 1개를 사용하므로 예산 안에서만 분할하고, `--output` 경로를 shard별로 분리합니다.
- 검증 배칭: 연관 Task의 테스트 요청은 모아서 배치 Editor 1회 기동으로 실행하는 것을 우선합니다. 콜드스타트 고정비를 Task 수로 분할하되, 증거(NUnit XML)는 Task별로 분리 기록합니다.
- 같은 물리 프로젝트에 대화형 Editor가 열려 있으면 batch 실행과 Library 잠금이 충돌할 수 있습니다. 순서를 조정하고 충돌 상태의 결과를 증거로 쓰지 않습니다.
- Player Build는 병렬화하지 않습니다. 기능·마일스톤의 사전 게이트를 통과한 동일 변경분에 1회만 수행하는 기존 정책을 유지합니다.

## 병렬 실행 헬퍼

여러 worktree의 테스트를 프로세스 예산 안에서 한 번에 실행하려면 다음 헬퍼를 사용합니다. 사용자가 해당 테스트 실행을 현재 요청한 경우에만 실행합니다.

```bash
bash .agents/scripts/validation/run-parallel-tests.sh --mode EditMode --max-procs 2 <worktree-1-물리경로> <worktree-2-물리경로>
```

- 실행 전 `unity doctor --ci` preflight를 수행하고, 각 실행 루트의 NUnit XML을 해당 루트의 `.agents/reports/`에 남깁니다.
- 예산 상한은 4이며 기본값은 2입니다. 하나라도 실패하면 종료 코드 1과 함께 실패한 루트를 보고합니다.
- 순차 실행 대비 소요 시간은 대략 `가장 느린 루트의 시간` 수준으로 줄어듭니다. worktree가 없는 단일 프로젝트에서는 `unity test --shard n/m`을 직접 사용합니다.

## 증거와 통합

- 각 worktree의 컴파일·테스트 증거는 해당 실행 루트에서 수집한 결과만 인정합니다. 다른 worktree의 결과로 대체하지 않습니다.
- 기능 lane이 완료되면 통합 담당이 공유 핫스팟 반영과 충돌 해소를 수행한 뒤, 통합된 변경분으로 기능·마일스톤 검증을 진행합니다.
- 병렬로 얻은 개별 증거는 통합 후 재계산된 change 기준의 검증을 대체하지 않습니다.

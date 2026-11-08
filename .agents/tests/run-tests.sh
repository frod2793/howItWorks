#!/bin/bash

# ==============================================================================
# [기능]: 범용 Unity 하네스의 Bash 계약 테스트를 실행하고 결과를 집계합니다.
# [작성자]: 윤승종
# ==============================================================================

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
AGENTS_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
SCHEMA_PATH="$AGENTS_ROOT/config/profile-schema.conf"
SIGNATURES_PATH="$AGENTS_ROOT/config/detection-signatures.conf"
PROFILE_SCRIPT="$AGENTS_ROOT/scripts/shared/profile.sh"
DETECT_SCRIPT="$AGENTS_ROOT/scripts/shared/detect.sh"
LINT_SCRIPT="$AGENTS_ROOT/scripts/shared/lint.sh"
INITIALIZER_SCRIPT="$AGENTS_ROOT/scripts/init/initialize-harness.sh"
CHECK_HARNESS_SCRIPT="$AGENTS_ROOT/scripts/lint/check-harness.sh"
LEGACY_LINT_SCRIPT="$AGENTS_ROOT/scripts/lint/check-architecture.sh"
PRE_COMMIT_SCRIPT="$AGENTS_ROOT/scripts/ci/pre-commit-checks.sh"
POWERSHELL_PROFILE_SCRIPT="$AGENTS_ROOT/scripts/shared/profile.ps1"
POWERSHELL_DETECT_SCRIPT="$AGENTS_ROOT/scripts/shared/detect.ps1"
POWERSHELL_LINT_SCRIPT="$AGENTS_ROOT/scripts/shared/lint.ps1"
POWERSHELL_INITIALIZER_SCRIPT="$AGENTS_ROOT/scripts/init/initialize-harness.ps1"
POWERSHELL_CHECK_HARNESS_SCRIPT="$AGENTS_ROOT/scripts/lint/check-harness.ps1"
POWERSHELL_PRE_COMMIT_SCRIPT="$AGENTS_ROOT/scripts/ci/pre-commit-checks.ps1"
POWERSHELL_TEST_SCRIPT="$AGENTS_ROOT/tests/run-tests.ps1"
TOOLING_CONFIG="$AGENTS_ROOT/config/agent-tooling.conf"
TOOLING_SCRIPT="$AGENTS_ROOT/scripts/setup/check-agent-tooling.sh"
POWERSHELL_TOOLING_SCRIPT="$AGENTS_ROOT/scripts/setup/check-agent-tooling.ps1"
MILESTONE_VALIDATOR="$AGENTS_ROOT/scripts/validation/check-unity-milestone.sh"
MILESTONE_SCHEMA="$AGENTS_ROOT/config/unity-milestone-validation-schema.conf"
DOCS_ROOT="$AGENTS_ROOT/docs"

SELECTED_GROUP="all"
SELECTED_RUNTIME="all"
SELECTED_COUNT=0
PASSED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0
TEST_SEQUENCE=0

print_usage()
{
    echo "사용법: bash .agents/tests/run-tests.sh [--group all|profile|detection|readonly|lint|docs|entrypoints|tooling|validation|parity] [--runtime all|bash]"
}

parse_arguments()
{
    while [ "$#" -gt 0 ]; do
        case "$1" in
            --group)
                if [ "$#" -lt 2 ]; then
                    echo "--group 뒤에 값을 지정해야 합니다." >&2
                    print_usage >&2
                    return 2
                fi

                SELECTED_GROUP=$2
                shift 2
                ;;
            --runtime)
                if [ "$#" -lt 2 ]; then
                    echo "--runtime 뒤에 값을 지정해야 합니다." >&2
                    print_usage >&2
                    return 2
                fi

                SELECTED_RUNTIME=$2
                shift 2
                ;;
            -h|--help)
                print_usage
                return 10
                ;;
            *)
                echo "알 수 없는 인자입니다: $1" >&2
                print_usage >&2
                return 2
                ;;
        esac
    done

    case "$SELECTED_GROUP" in
        all|profile|detection|readonly|lint|docs|entrypoints|tooling|validation|parity)
            ;;
        *)
            echo "지원하지 않는 테스트 그룹입니다: $SELECTED_GROUP" >&2
            return 2
            ;;
    esac

    case "$SELECTED_RUNTIME" in
        all|bash)
            ;;
        powershell)
            echo "Bash 러너에서는 PowerShell 테스트를 실행할 수 없습니다." >&2
            return 2
            ;;
        *)
            echo "지원하지 않는 런타임입니다: $SELECTED_RUNTIME" >&2
            return 2
            ;;
    esac

    return 0
}

ARGUMENT_STATUS=0
parse_arguments "$@" || ARGUMENT_STATUS=$?
if [ "$ARGUMENT_STATUS" -eq 10 ]; then
    exit 0
fi

if [ "$ARGUMENT_STATUS" -ne 0 ]; then
    exit "$ARGUMENT_STATUS"
fi

TEST_TEMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/unity-harness-tests.XXXXXX")
if [ ! -d "$TEST_TEMP_ROOT" ]; then
    echo "테스트 임시 디렉터리를 만들 수 없습니다." >&2
    exit 1
fi

cleanup()
{
    if [ -d "$TEST_TEMP_ROOT" ]; then
        rm -rf "$TEST_TEMP_ROOT"
    fi
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

assert_equal()
{
    local expected=$1
    local actual=$2
    local message=$3

    if [ "$expected" != "$actual" ]; then
        echo "$message: 기대값=[$expected], 실제값=[$actual]" >&2
        return 1
    fi

    return 0
}

assert_contains()
{
    local actual=$1
    local expected_fragment=$2
    local message=$3

    case "$actual" in
        *"$expected_fragment"*)
            return 0
            ;;
        *)
            echo "$message: [$expected_fragment] 문자열이 없습니다." >&2
            return 1
            ;;
    esac
}

assert_not_contains()
{
    local actual=$1
    local unexpected_fragment=$2
    local message=$3

    case "$actual" in
        *"$unexpected_fragment"*)
            echo "$message: 허용되지 않은 [$unexpected_fragment] 문자열이 있습니다." >&2
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

assert_file_exists()
{
    local path=$1
    local message=$2

    if [ ! -f "$path" ]; then
        echo "$message: 파일이 없습니다: $path" >&2
        return 1
    fi

    return 0
}

assert_file_not_exists()
{
    local path=$1
    local message=$2

    if [ -e "$path" ]; then
        echo "$message: 파일이 생성되었습니다: $path" >&2
        return 1
    fi

    return 0
}

assert_crlf_file()
{
    local path=$1
    local carriage_return_count
    local line_feed_count

    carriage_return_count=$(LC_ALL=C tr -cd '\r' < "$path" | wc -c | tr -d ' ')
    line_feed_count=$(LC_ALL=C tr -cd '\n' < "$path" | wc -c | tr -d ' ')
    if [ "$line_feed_count" -eq 0 ] || [ "$carriage_return_count" -ne "$line_feed_count" ]; then
        echo "CRLF 픽스처의 줄 끝 바이트가 올바르지 않습니다: $path" >&2
        return 1
    fi

    return 0
}

require_file()
{
    local path=$1
    local label=$2

    if [ ! -f "$path" ]; then
        echo "$label 파일을 찾을 수 없습니다: $path" >&2
        return 1
    fi

    return 0
}

require_function()
{
    local function_name=$1

    if ! command -v "$function_name" >/dev/null 2>&1; then
        echo "필수 함수를 찾을 수 없습니다: $function_name" >&2
        return 1
    fi

    return 0
}

load_profile_api()
{
    require_file "$PROFILE_SCRIPT" "profile.sh" || return 1
    . "$PROFILE_SCRIPT"

    require_function profile_reset || return 1
    require_function profile_load || return 1
    require_function profile_validate || return 1
    require_function profile_get || return 1
    require_function profile_get_all || return 1
    require_function profile_set_single || return 1
    require_function profile_write || return 1
    require_function profile_confirm || return 1
}

load_detection_api()
{
    load_profile_api || return 1
    require_file "$DETECT_SCRIPT" "detect.sh" || return 1
    . "$DETECT_SCRIPT"
    require_function find_unity_project_root || return 1
    require_function detect_unity_version || return 1
    require_function detect_source_roots || return 1
    require_function detect_test_roots || return 1
    require_function detect_render_pipeline || return 1
    require_function detect_dependency_injection || return 1
    require_function detect_async_backend || return 1
    require_function detect_tween_backend || return 1
    require_function detect_target_platforms || return 1
    require_function detect_architecture || return 1
    require_function detect_optimization_states || return 1
    require_function write_detection_report || return 1
    require_function detect_project || return 1
}

load_lint_api()
{
    load_profile_api || return 1
    require_file "$LINT_SCRIPT" "lint.sh" || return 1
    . "$LINT_SCRIPT"
    require_function lint_reset || return 1
    require_function lint_emit || return 1
    require_function lint_core_rules || return 1
    require_function lint_architecture_rules || return 1
    require_function lint_technology_rules || return 1
    require_function lint_project || return 1
    require_function lint_exit_code || return 1
}

write_valid_profile()
{
    local path=$1
    local confirmation_status=$2
    local architecture=$3
    local project_name=$4
    local second_source_root=$5

    printf '%s\n' \
        'profile_version=1' \
        "confirmation_status=$confirmation_status" \
        "project_name=$project_name" \
        'unity_version=6000.3.16f1' \
        'render_pipeline=urp' \
        "architecture=$architecture" \
        'source_root=Assets/_Game' \
        'dependency_injection=vcontainer' \
        'async_backend=unitask' \
        'tween_backend=dotween' \
        'target_platform=unknown' \
        'response_language=ko' \
        'log_language=ko' \
        'author_name=윤승종' \
        'private_field_prefix=m_' \
        'ui_callback_prefix=func_' \
        'region_policy=encouraged' \
        'xml_documentation_policy=all_methods' \
        'gpu_resident_drawer=unknown' \
        'gpu_occlusion_culling=unknown' \
        'stp=unknown' \
        'mesh_lod=unknown' \
        'exclude_root=Assets/Plugins' \
        'exclude_root=Assets/ThirdParty' > "$path"

    if [ -n "$second_source_root" ]; then
        printf 'source_root=%s\n' "$second_source_root" >> "$path"
    fi
}

write_milestone_evidence()
{
    local output_path=$1
    local integration_result=$2
    local build_result=$3

    printf '%s\n' \
        'validation_version=1' \
        'milestone_id=login-flow' \
        'change_id=commit-abc123' \
        'coverage_status=confirmed' \
        'build_authority=local' \
        'compile=passed' \
        'unit_test=passed' \
        "integration_test=$integration_result" \
        'module_scope=Login' \
        'module_scope=Profile' \
        'interaction_scope=Login>Profile' \
        'module_result=Login|Game.Tests.LoginModuleTests|passed' \
        'module_result=Profile|Game.Tests.ProfileModuleTests|passed' \
        'interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed' \
        "build_validation=$build_result" \
        'build_run_id=pending' \
        'build_artifact_hash=pending' > "$output_path"
}

create_milestone_validator_fixture()
{
    local fixture_root=$1
    local fixture_agents_root="$fixture_root/.agents"

    mkdir -p "$fixture_agents_root/config" "$fixture_agents_root/scripts/shared" "$fixture_agents_root/scripts/validation" || return 1
    cp "$MILESTONE_VALIDATOR" "$fixture_agents_root/scripts/validation/check-unity-milestone.sh" || return 1
    cp "$PROFILE_SCRIPT" "$fixture_agents_root/scripts/shared/profile.sh" || return 1
    cp "$MILESTONE_SCHEMA" "$fixture_agents_root/config/unity-milestone-validation-schema.conf" || return 1
    cp "$AGENTS_ROOT/config/unity-milestone-validation.example.conf" "$fixture_agents_root/config/evidence.conf" || return 1
}

create_milestone_validator_v2_fixture()
{
    local fixture_root=$1
    local fixture_agents_root="$fixture_root/.agents"
    local fixture_schema="$fixture_agents_root/config/unity-milestone-validation-schema.conf"
    local fixture_evidence="$fixture_agents_root/config/evidence.conf"

    create_milestone_validator_fixture "$fixture_root" || return 1

    if ! grep -q '^module_scope|' "$fixture_schema"; then
        printf '%s\n' \
            'module_scope|required|multiple|text|' \
            'interaction_scope|required|multiple|text|' \
            'build_run_id|required|single|text|' \
            'build_artifact_hash|required|single|text|' >> "$fixture_schema"
    fi

    if ! grep -q '^module_scope=' "$fixture_evidence"; then
        printf '%s\n' \
            'module_scope=Login' \
            'module_scope=Profile' \
            'interaction_scope=Login>Profile' \
            'build_run_id=pending' \
            'build_artifact_hash=pending' >> "$fixture_evidence"
    fi
}

create_unity_fixture()
{
    local project_root=$1
    local fixture_kind=$2

    mkdir -p "$project_root/ProjectSettings" "$project_root/Packages"
    printf '%s\n' 'm_EditorVersion: 6000.3.16f1' > "$project_root/ProjectSettings/ProjectVersion.txt"
    printf '%s\n' 'm_CustomRenderPipeline: {fileID: 0}' > "$project_root/ProjectSettings/GraphicsSettings.asset"

    if [ "$fixture_kind" = "mvvm" ]; then
        mkdir -p "$project_root/Assets/_Game/Scripts/Views" \
            "$project_root/Assets/_Game/Scripts/ViewModels" \
            "$project_root/Assets/_Game/Scripts/Models" \
            "$project_root/Assets/_Game/Tests/Editor" \
            "$project_root/Assets/Plugins/Foreign/Presenters" \
            "$project_root/Assets/ThirdParty/Foreign/Controllers" \
            "$project_root/Library/Generated/Presenters"
        printf '%s\n' \
            '{' \
            '  "dependencies": {' \
            '    "com.unity.render-pipelines.universal": "17.0.3",' \
            '    "jp.hadashikick.vcontainer": "1.16.8",' \
            '    "com.cysharp.unitask": "2.5.10"' \
            '  }' \
            '}' > "$project_root/Packages/manifest.json"
        printf '%s\n' \
            'using VContainer;' \
            'using Cysharp.Threading.Tasks;' \
            'using DG.Tweening;' \
            'public sealed class GameView { }' > "$project_root/Assets/_Game/Scripts/Views/GameView.cs"
        printf '%s\n' 'public sealed class GameViewModel { }' > "$project_root/Assets/_Game/Scripts/ViewModels/GameViewModel.cs"
        printf '%s\n' 'public sealed class GameModel { }' > "$project_root/Assets/_Game/Scripts/Models/GameModel.cs"
        printf '%s\n' '{ "name": "Game.Runtime" }' > "$project_root/Assets/_Game/Scripts/Game.Runtime.asmdef"
        printf '%s\n' 'public sealed class GameViewModelTests { }' > "$project_root/Assets/_Game/Tests/Editor/GameViewModelTests.cs"
        printf '%s\n' 'public sealed class ForeignPresenter { }' > "$project_root/Assets/Plugins/Foreign/Presenters/ForeignPresenter.cs"
        printf '%s\n' 'public sealed class ForeignController { }' > "$project_root/Assets/ThirdParty/Foreign/Controllers/ForeignController.cs"
        printf '%s\n' 'public sealed class GeneratedPresenter { }' > "$project_root/Library/Generated/Presenters/GeneratedPresenter.cs"
    else
        mkdir -p "$project_root/Assets/_Game/Scripts/Views" \
            "$project_root/Assets/_Game/Scripts/ViewModels" \
            "$project_root/Assets/_Game/Scripts/Presenters" \
            "$project_root/Assets/_Game/Scripts/Models"
        printf '%s\n' '{ "dependencies": {} }' > "$project_root/Packages/manifest.json"
        printf '%s\n' 'public sealed class GameView { }' > "$project_root/Assets/_Game/Scripts/Views/GameView.cs"
        printf '%s\n' 'public sealed class GameViewModel { }' > "$project_root/Assets/_Game/Scripts/ViewModels/GameViewModel.cs"
        printf '%s\n' 'public sealed class GamePresenter { }' > "$project_root/Assets/_Game/Scripts/Presenters/GamePresenter.cs"
        printf '%s\n' 'public sealed class GameModel { }' > "$project_root/Assets/_Game/Scripts/Models/GameModel.cs"
    fi
}

create_architecture_fixture()
{
    local project_root=$1
    local architecture=$2

    mkdir -p "$project_root/ProjectSettings" "$project_root/Packages"
    printf '%s\n' 'm_EditorVersion: 6000.3.16f1' > "$project_root/ProjectSettings/ProjectVersion.txt"
    printf '%s\n' 'm_CustomRenderPipeline: {fileID: 0}' > "$project_root/ProjectSettings/GraphicsSettings.asset"

    case "$architecture" in
        mvp)
            mkdir -p "$project_root/Assets/_Game/Scripts/Views" \
                "$project_root/Assets/_Game/Scripts/Presenters" \
                "$project_root/Assets/_Game/Scripts/Models"
            printf '%s\n' '{ "dependencies": {} }' > "$project_root/Packages/manifest.json"
            printf '%s\n' 'public sealed class BattleView { }' > "$project_root/Assets/_Game/Scripts/Views/BattleView.cs"
            printf '%s\n' \
                'using System.Collections;' \
                'public sealed class BattlePresenter' \
                '{' \
                '    public IEnumerator Present() { yield return null; }' \
                '}' > "$project_root/Assets/_Game/Scripts/Presenters/BattlePresenter.cs"
            printf '%s\n' 'public sealed class BattleModel { }' > "$project_root/Assets/_Game/Scripts/Models/BattleModel.cs"
            ;;
        mvc)
            mkdir -p "$project_root/Assets/_Game/Scripts/Views" \
                "$project_root/Assets/_Game/Scripts/Controllers" \
                "$project_root/Assets/_Game/Scripts/Models"
            printf '%s\n' \
                '{' \
                '  "dependencies": {' \
                '    "com.unity.render-pipelines.high-definition": "17.0.3"' \
                '  }' \
                '}' > "$project_root/Packages/manifest.json"
            printf '%s\n' 'public sealed class WorldView { }' > "$project_root/Assets/_Game/Scripts/Views/WorldView.cs"
            printf '%s\n' 'public sealed class WorldController { }' > "$project_root/Assets/_Game/Scripts/Controllers/WorldController.cs"
            printf '%s\n' 'public sealed class WorldModel { }' > "$project_root/Assets/_Game/Scripts/Models/WorldModel.cs"
            ;;
        layered_clean)
            mkdir -p "$project_root/Assets/_Game/Scripts/Domain" \
                "$project_root/Assets/_Game/Scripts/Application" \
                "$project_root/Assets/_Game/Scripts/Infrastructure"
            printf '%s\n' \
                '{' \
                '  "dependencies": {' \
                '    "jp.hadashikick.vcontainer": "1.16.8",' \
                '    "com.svermeulen.extenject": "9.2.0"' \
                '  }' \
                '}' > "$project_root/Packages/manifest.json"
            printf '%s\n' 'public sealed class PlayerDomain { }' > "$project_root/Assets/_Game/Scripts/Domain/PlayerDomain.cs"
            printf '%s\n' \
                'using VContainer;' \
                'using Zenject;' \
                'public sealed class StartBattleUseCase' \
                '{' \
                '    private IObjectResolver m_resolver;' \
                '    private DiContainer m_container;' \
                '}' > "$project_root/Assets/_Game/Scripts/Application/StartBattleUseCase.cs"
            printf '%s\n' 'public sealed class PlayerInfrastructure { }' > "$project_root/Assets/_Game/Scripts/Infrastructure/PlayerInfrastructure.cs"
            ;;
        *)
            return 1
            ;;
    esac
}

create_neutral_unity_fixture()
{
    local project_root=$1

    mkdir -p "$project_root/ProjectSettings" "$project_root/Packages" "$project_root/Assets/_Game/Scripts"
    printf '%s\n' 'm_EditorVersion: 6000.3.16f1' > "$project_root/ProjectSettings/ProjectVersion.txt"
    printf '%s\n' 'm_CustomRenderPipeline: {fileID: 0}' > "$project_root/ProjectSettings/GraphicsSettings.asset"
    printf '%s\n' '{ "dependencies": {} }' > "$project_root/Packages/manifest.json"
    printf '%s\n' 'public sealed class NeutralProjectClass { }' > "$project_root/Assets/_Game/Scripts/NeutralProjectClass.cs"
}

create_lint_fixture()
{
    local project_root=$1

    mkdir -p "$project_root/Assets/_Game/Views"
    printf '%s\n' \
        'using Sample.Models;' \
        'namespace Sample.Views' \
        '{' \
        '    public sealed class InventoryView' \
        '    {' \
        '        private InventoryModel m_model;' \
        '    }' \
        '}' > "$project_root/Assets/_Game/Views/InventoryView.cs"
}

create_full_lint_fixture()
{
    local project_root=$1

    mkdir -p "$project_root/Assets/_Game/Views" "$project_root/Assets/_Game/Core"
    printf '%s\n' \
        'using System.Collections.Generic;' \
        'using System.Linq;' \
        'using DG.Tweening;' \
        'using UnityEngine;' \
        'public sealed class RuleProbe' \
        '{' \
        '    public static RuleProbe Instance { get; private set; }' \
        '    private Transform m_target;' \
        '    private List<int> m_values;' \
        '    private int wrongName;' \
        '    private void Update()' \
        '    {' \
        '        var filtered = m_values.Where(value => value > 0);' \
        '        var copy = new List<int>();' \
        '        m_target.DOMove(Vector3.zero, 1f);' \
        '    }' \
        '    private void ProbeNull()' \
        '    {' \
        '        m_target?.gameObject.SetActive(true);' \
        '    }' \
        '    private System.Collections.IEnumerator Load()' \
        '    {' \
        '        yield return null;' \
        '    }' \
        '}' > "$project_root/Assets/_Game/Core/RuleProbe.cs"
    printf '%s\n' \
        'using Sample.Models;' \
        'public sealed class InventoryView' \
        '{' \
        '    private InventoryModel m_model;' \
        '}' > "$project_root/Assets/_Game/Views/InventoryView.cs"
    printf '%s\n' \
        'using UnityEngine;' \
        'using VContainer;' \
        'public sealed class GameLifetimeScope' \
        '{' \
        '    [SerializeField] private InventoryView m_inventoryView;' \
        '    private void Configure(IContainerBuilder builder)' \
        '    {' \
        '        builder.RegisterInstance(m_inventoryView);' \
        '    }' \
        '}' > "$project_root/Assets/_Game/Core/GameLifetimeScope.cs"
}

snapshot_project_files()
{
    local project_root=$1
    local output_path=$2
    local list_path
    local sorted_path
    local snapshot_path
    local file_path
    local status=0

    list_path=$(mktemp "${output_path}.files.XXXXXX") || return 1
    sorted_path=$(mktemp "${output_path}.sorted.XXXXXX") || {
        rm -f "$list_path"
        return 1
    }
    snapshot_path=$(mktemp "${output_path}.snapshot.XXXXXX") || {
        rm -f "$list_path" "$sorted_path"
        return 1
    }

    (
        cd "$project_root" || exit 1
        find . -path './.agents' -prune -o -type f -print > "$list_path"
    ) || status=1
    if [ "$status" -eq 0 ]; then
        LC_ALL=C sort "$list_path" > "$sorted_path" || status=1
    fi
    if [ "$status" -eq 0 ]; then
        : > "$snapshot_path" || status=1
    fi
    if [ "$status" -eq 0 ]; then
        while IFS= read -r file_path || [ -n "$file_path" ]
        do
            (
                cd "$project_root" || exit 1
                cksum "$file_path"
            ) >> "$snapshot_path" || {
                status=1
                break
            }
        done < "$sorted_path"
    fi
    if [ "$status" -eq 0 ]; then
        mv "$snapshot_path" "$output_path" || status=1
    fi
    rm -f "$list_path" "$sorted_path" "$snapshot_path"
    return "$status"
}

assert_detection_report_headings()
{
    local report_path=$1
    local actual_headings
    local expected_headings

    actual_headings=$(grep '^#' "$report_path" 2>/dev/null)
    expected_headings=$(printf '%s\n' \
        '# Unity 하네스 감지 보고서' \
        '## 요약' \
        '## 감지 근거와 신뢰도' \
        '## 소스 및 테스트 루트' \
        '## 조건부 최적화 적용 가능성' \
        '## 충돌 및 미확정 항목' \
        '## 사용자 확인 절차')

    assert_equal "$expected_headings" "$actual_headings" "감지 보고서 헤딩은 제목 포함 정확히 7개여야 합니다"
}

load_and_validate_profile()
{
    local profile_path=$1
    local status

    profile_reset
    profile_load "$profile_path" "$SCHEMA_PATH"
    status=$?
    assert_equal "0" "$status" "프로필 로드 종료 코드가 다릅니다" || return 1
    profile_validate "$SCHEMA_PATH"
    status=$?
    assert_equal "0" "$status" "프로필 검증 종료 코드가 다릅니다" || return 1
}

run_profile_subcase()
{
    local case_name=$1
    local case_function=$2
    shift 2

    echo "[하위 실행] $case_name"
    if "$case_function" "$@"; then
        echo "[하위 통과] $case_name"
        return 0
    fi

    echo "[하위 실패] $case_name" >&2
    return 1
}

get_file_mode()
{
    local path=$1
    local mode

    mode=$(stat -f '%Lp' "$path" 2>/dev/null)
    if [ "$?" -eq 0 ] && [ -n "$mode" ]; then
        printf '%s\n' "$mode"
        return 0
    fi

    stat -c '%a' "$path" 2>/dev/null
}

count_profile_temp_files()
{
    local directory=$1

    find "$directory" -maxdepth 1 -name '.*.tmp.*' -print | wc -l | tr -d ' '
}

assert_profile_memory_state()
{
    local expected_data=$1
    local expected_schema_path=$2
    local expected_schema_key=$3
    local expected_schema_required=$4
    local expected_schema_cardinality=$5
    local expected_schema_type=$6
    local expected_schema_allowed=$7
    local expected_line=$8
    local expected_line_set=$9
    local message=${10}
    local actual_line_set=0

    assert_equal "$expected_data" "$_PROFILE_DATA" "$message: 프로필 데이터" || return 1
    assert_equal "$expected_schema_path" "$_PROFILE_SCHEMA_PATH" "$message: 스키마 경로" || return 1
    assert_equal "$expected_schema_key" "$_PROFILE_SCHEMA_KEY" "$message: 스키마 키" || return 1
    assert_equal "$expected_schema_required" "$_PROFILE_SCHEMA_REQUIRED" "$message: 필수 상태" || return 1
    assert_equal "$expected_schema_cardinality" "$_PROFILE_SCHEMA_CARDINALITY" "$message: 반복 상태" || return 1
    assert_equal "$expected_schema_type" "$_PROFILE_SCHEMA_TYPE" "$message: 값 형식" || return 1
    assert_equal "$expected_schema_allowed" "$_PROFILE_SCHEMA_ALLOWED" "$message: 허용값" || return 1

    if [ "${_PROFILE_LINE+x}" = "x" ]; then
        actual_line_set=1
    fi
    assert_equal "$expected_line_set" "$actual_line_set" "$message: 전역 줄 set 상태" || return 1
    if [ "$expected_line_set" -eq 1 ]; then
        assert_equal "$expected_line" "$_PROFILE_LINE" "$message: 전역 줄 값" || return 1
    fi

    return 0
}

assert_profile_load_failure_preserves_memory()
{
    local profile_path=$1
    local schema_path=$2
    local expected_status=$3
    local expected_fragment=$4
    local diagnostic_path=$5
    local label=$6
    local expected_data=$_PROFILE_DATA
    local expected_schema_path=$_PROFILE_SCHEMA_PATH
    local expected_schema_key=$_PROFILE_SCHEMA_KEY
    local expected_schema_required=$_PROFILE_SCHEMA_REQUIRED
    local expected_schema_cardinality=$_PROFILE_SCHEMA_CARDINALITY
    local expected_schema_type=$_PROFILE_SCHEMA_TYPE
    local expected_schema_allowed=$_PROFILE_SCHEMA_ALLOWED
    local expected_line=""
    local expected_line_set=0
    local diagnostic
    local status

    if [ "${_PROFILE_LINE+x}" = "x" ]; then
        expected_line=$_PROFILE_LINE
        expected_line_set=1
    fi

    profile_load "$profile_path" "$schema_path" > "$diagnostic_path" 2>&1
    status=$?
    assert_equal "$expected_status" "$status" "$label 종료 코드" || return 1
    assert_profile_memory_state "$expected_data" "$expected_schema_path" "$expected_schema_key" "$expected_schema_required" "$expected_schema_cardinality" "$expected_schema_type" "$expected_schema_allowed" "$expected_line" "$expected_line_set" "$label 후 호출 전 메모리 복원" || return 1

    if [ -n "$expected_fragment" ]; then
        diagnostic=$(sed -n '1,20p' "$diagnostic_path")
        assert_contains "$diagnostic" "$expected_fragment" "$label 진단" || return 1
    fi

    return 0
}

profile_case_load_failure_preserves_memory()
(
    local case_root=$1
    local failure_kind=$2
    local caller_profile="$case_root/caller.conf"
    local invalid_profile="$case_root/invalid.conf"
    local diagnostic_path="$case_root/diagnostic.log"
    local expected_status=3
    local expected_fragment=""
    local line

    mkdir -p "$case_root"
    write_valid_profile "$caller_profile" "pending" "custom" "호출전메모리" ""
    profile_load "$caller_profile" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    _PROFILE_SCHEMA_KEY="호출전키"
    _PROFILE_SCHEMA_REQUIRED="호출전필수"
    _PROFILE_SCHEMA_CARDINALITY="호출전반복"
    _PROFILE_SCHEMA_TYPE="호출전형식"
    _PROFILE_SCHEMA_ALLOWED="호출전허용"
    _PROFILE_LINE="호출전줄"

    case "$failure_kind" in
        unknown)
            write_valid_profile "$invalid_profile" "pending" "custom" "Unknown" ""
            printf '%s\n' 'unknown_key=value' >> "$invalid_profile"
            expected_fragment="unknown_key"
            ;;
        duplicate)
            write_valid_profile "$invalid_profile" "pending" "custom" "Duplicate" ""
            printf '%s\n' 'architecture=custom' >> "$invalid_profile"
            expected_fragment="중복"
            ;;
        required)
            write_valid_profile "$case_root/source.conf" "pending" "custom" "Missing" ""
            sed '/^author_name=/d' "$case_root/source.conf" > "$invalid_profile"
            expected_fragment="author_name"
            ;;
        bom)
            printf '\357\273\277' > "$invalid_profile"
            while IFS= read -r line || [ -n "$line" ]; do
                printf '%s\n' "$line" >> "$invalid_profile"
            done < "$caller_profile"
            expected_fragment="BOM"
            ;;
        enum)
            write_valid_profile "$case_root/source.conf" "pending" "custom" "Enum" ""
            sed 's/^render_pipeline=.*/render_pipeline=invalid_pipeline/' "$case_root/source.conf" > "$invalid_profile"
            expected_fragment="invalid_pipeline"
            ;;
        read)
            invalid_profile="$case_root/missing.conf"
            expected_status=2
            expected_fragment="읽을 수 없습니다"
            ;;
        *)
            return 1
            ;;
    esac

    assert_profile_load_failure_preserves_memory "$invalid_profile" "$SCHEMA_PATH" "$expected_status" "$expected_fragment" "$diagnostic_path" "profile_load $failure_kind"
)

profile_case_schema_order_and_set_single()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"
    local output_path="$case_root/output.conf"
    local status

    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "SchemaOrder" "Assets/Shared"
    profile_load "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    profile_set_single "architecture" "mvvm" >/dev/null 2>&1 || return 1
    assert_equal "mvvm" "$(profile_get "architecture")" "single 키 교체값" || return 1
    profile_write "$output_path" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "스키마 순서 출력 종료 코드" || return 1
    assert_equal "profile_version=1" "$(sed -n '1p' "$output_path")" "스키마 순서 1번" || return 1
    assert_equal "architecture=mvvm" "$(sed -n '6p' "$output_path")" "스키마 순서 architecture" || return 1
    assert_equal "source_root=Assets/_Game" "$(sed -n '7p' "$output_path")" "첫 source_root 순서" || return 1
    assert_equal "source_root=Assets/Shared" "$(sed -n '8p' "$output_path")" "둘째 source_root 순서" || return 1
    assert_equal "dependency_injection=vcontainer" "$(sed -n '9p' "$output_path")" "스키마 순서 후속 키"
)

profile_case_write_relative_path()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"
    local output_path="$case_root/relative-profile.conf"

    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "RelativePath" ""
    profile_load "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    (
        cd "$case_root" || return 1
        profile_write "relative-profile.conf" >/dev/null 2>&1
    ) || return 1
    assert_file_exists "$output_path" "상대 출력 경로 파일이 생성되지 않았습니다" || return 1
    assert_equal "profile_version=1" "$(sed -n '1p' "$output_path")" "상대 출력 경로 내용" || return 1
    assert_equal "0" "$(count_profile_temp_files "$case_root" "relative-profile.conf")" "상대 출력 경로 임시 파일"
)

profile_case_write_rejects_directory_targets()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"
    local directory_path="$case_root/output-directory"
    local linked_directory_path="$case_root/linked-directory"
    local directory_link_path="$case_root/output-directory-link"
    local status

    mkdir -p "$directory_path" "$linked_directory_path"
    write_valid_profile "$profile_path" "pending" "custom" "DirectoryTarget" ""
    profile_load "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1

    profile_write "$directory_path" >/dev/null 2>&1
    status=$?
    assert_equal "2" "$status" "디렉터리 출력 거부 종료 코드" || return 1
    assert_equal "0" "$(find "$directory_path" -mindepth 1 -print | wc -l | tr -d ' ')" "디렉터리 출력 내부 파일" || return 1

    ln -s "$linked_directory_path" "$directory_link_path" || return 1
    profile_write "$directory_link_path" >/dev/null 2>&1
    status=$?
    assert_equal "2" "$status" "디렉터리 심볼릭 링크 출력 거부 종료 코드" || return 1
    if [ ! -L "$directory_link_path" ]; then
        echo "디렉터리 심볼릭 링크 출력이 보존되지 않았습니다." >&2
        return 1
    fi
    assert_equal "0" "$(find "$linked_directory_path" -mindepth 1 -print | wc -l | tr -d ' ')" "디렉터리 링크 대상 내부 파일" || return 1
    assert_equal "0" "$(count_profile_temp_files "$case_root" "output-directory")" "디렉터리 출력 거부 후 임시 파일"
)

profile_case_write_partial_failure()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"
    local output_path="$case_root/output.conf"
    local before_checksum
    local before_mode
    local expected_data
    local expected_schema_path
    local expected_schema_key
    local expected_schema_required
    local expected_schema_cardinality
    local expected_schema_type
    local expected_schema_allowed
    local expected_line
    local status

    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "PartialWrite" ""
    profile_load "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    _PROFILE_SCHEMA_KEY="호출전키"
    _PROFILE_SCHEMA_REQUIRED="호출전필수"
    _PROFILE_SCHEMA_CARDINALITY="호출전반복"
    _PROFILE_SCHEMA_TYPE="호출전형식"
    _PROFILE_SCHEMA_ALLOWED="호출전허용"
    _PROFILE_LINE="호출전줄"
    expected_data=$_PROFILE_DATA
    expected_schema_path=$_PROFILE_SCHEMA_PATH
    expected_schema_key=$_PROFILE_SCHEMA_KEY
    expected_schema_required=$_PROFILE_SCHEMA_REQUIRED
    expected_schema_cardinality=$_PROFILE_SCHEMA_CARDINALITY
    expected_schema_type=$_PROFILE_SCHEMA_TYPE
    expected_schema_allowed=$_PROFILE_SCHEMA_ALLOWED
    expected_line=$_PROFILE_LINE
    printf '%s\n' '기존 출력 보존' > "$output_path"
    chmod 640 "$output_path" || return 1
    before_checksum=$(cksum "$output_path")
    before_mode=$(get_file_mode "$output_path") || return 1

    _profile_render_to_file()
    {
        printf '%s\n' '부분 기록' > "$1"
        return 2
    }

    profile_write "$output_path" >/dev/null 2>&1
    status=$?
    assert_equal "2" "$status" "부분 렌더링 실패 종료 코드" || return 1
    assert_equal "$before_checksum" "$(cksum "$output_path")" "부분 렌더링 실패 후 기존 출력" || return 1
    assert_equal "$before_mode" "$(get_file_mode "$output_path")" "부분 렌더링 실패 후 mode" || return 1
    assert_profile_memory_state "$expected_data" "$expected_schema_path" "$expected_schema_key" "$expected_schema_required" "$expected_schema_cardinality" "$expected_schema_type" "$expected_schema_allowed" "$expected_line" "1" "부분 렌더링 실패 후 메모리" || return 1
    assert_equal "0" "$(count_profile_temp_files "$case_root" "output.conf")" "부분 렌더링 실패 후 임시 파일"
)

profile_case_write_symlink_target_protected()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"
    local target_path="$case_root/target.conf"
    local output_path="$case_root/output.conf"
    local before_checksum

    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "Symlink" ""
    profile_load "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    printf '%s\n' '심볼릭 링크 대상 보존' > "$target_path"
    before_checksum=$(cksum "$target_path")
    ln -s "$target_path" "$output_path" || return 1
    profile_write "$output_path" >/dev/null 2>&1 || return 1
    assert_equal "$before_checksum" "$(cksum "$target_path")" "심볼릭 링크 대상 checksum" || return 1
    if [ -L "$output_path" ] || [ ! -f "$output_path" ]; then
        echo "심볼릭 링크 출력 경로가 regular file로 교체되지 않았습니다." >&2
        return 1
    fi
    assert_equal "0" "$(count_profile_temp_files "$case_root" "output.conf")" "심볼릭 링크 교체 후 임시 파일"
)

profile_case_write_hardlink_target_protected()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"
    local target_path="$case_root/target.conf"
    local output_path="$case_root/output.conf"
    local before_checksum

    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "Hardlink" ""
    profile_load "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    printf '%s\n' '하드 링크 대상 보존' > "$target_path"
    before_checksum=$(cksum "$target_path")
    ln "$target_path" "$output_path" || return 1
    profile_write "$output_path" >/dev/null 2>&1 || return 1
    assert_equal "$before_checksum" "$(cksum "$target_path")" "하드 링크 대상 checksum" || return 1
    if [ "$output_path" -ef "$target_path" ]; then
        echo "하드 링크 출력 엔트리가 새 파일로 교체되지 않았습니다." >&2
        return 1
    fi
    if [ -L "$output_path" ] || [ ! -f "$output_path" ]; then
        echo "하드 링크 출력 경로가 regular file로 교체되지 않았습니다." >&2
        return 1
    fi
    assert_equal "0" "$(count_profile_temp_files "$case_root" "output.conf")" "하드 링크 교체 후 임시 파일"
)

profile_case_write_preserves_mode()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"
    local output_path="$case_root/output.conf"
    local before_mode

    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "Mode" ""
    profile_load "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    printf '%s\n' '기존 mode' > "$output_path"
    chmod 640 "$output_path" || return 1
    before_mode=$(get_file_mode "$output_path") || return 1
    profile_write "$output_path" >/dev/null 2>&1 || return 1
    assert_equal "$before_mode" "$(get_file_mode "$output_path")" "기존 출력 mode 보존"
)

profile_case_confirm_success()
(
    local case_root=$1
    local profile_path="$case_root/profile.conf"

    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "ConfirmSuccess" ""
    profile_confirm "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    assert_equal "confirmed" "$(profile_get "confirmation_status")" "성공 확정 메모리 상태" || return 1
    if ! grep -Fqx 'confirmation_status=confirmed' "$profile_path"; then
        echo "성공 확정 파일 상태가 confirmed가 아닙니다." >&2
        return 1
    fi
    assert_equal "0" "$(count_profile_temp_files "$case_root" "profile.conf")" "성공 확정 후 임시 파일"
)

profile_case_confirm_failure()
(
    local case_root=$1
    local failure_kind=$2
    local caller_path="$case_root/caller.conf"
    local target_path="$case_root/target.conf"
    local expected_data
    local expected_schema_path
    local expected_schema_key
    local expected_schema_required
    local expected_schema_cardinality
    local expected_schema_type
    local expected_schema_allowed
    local expected_line
    local expected_line_set=1
    local before_checksum
    local external_mv_path
    local status

    mkdir -p "$case_root"
    write_valid_profile "$caller_path" "pending" "custom" "호출전메모리" ""
    write_valid_profile "$target_path" "pending" "custom" "확정대상" ""
    profile_load "$caller_path" "$SCHEMA_PATH" >/dev/null 2>&1 || return 1
    _PROFILE_SCHEMA_KEY="호출전키"
    _PROFILE_SCHEMA_REQUIRED="호출전필수"
    _PROFILE_SCHEMA_CARDINALITY="호출전반복"
    _PROFILE_SCHEMA_TYPE="호출전형식"
    _PROFILE_SCHEMA_ALLOWED="호출전허용"
    _PROFILE_LINE="호출전줄"
    expected_data=$_PROFILE_DATA
    expected_schema_path=$_PROFILE_SCHEMA_PATH
    expected_schema_key=$_PROFILE_SCHEMA_KEY
    expected_schema_required=$_PROFILE_SCHEMA_REQUIRED
    expected_schema_cardinality=$_PROFILE_SCHEMA_CARDINALITY
    expected_schema_type=$_PROFILE_SCHEMA_TYPE
    expected_schema_allowed=$_PROFILE_SCHEMA_ALLOWED
    expected_line=$_PROFILE_LINE
    before_checksum=$(cksum "$target_path")

    case "$failure_kind" in
        mktemp_nonzero)
            mktemp()
            {
                local generated_path=${1%XXXXXX}injected
                : > "$generated_path"
                printf '%s\n' "$generated_path"
                return 1
            }
            ;;
        cp)
            cp()
            {
                return 1
            }
            ;;
        write)
            profile_write()
            {
                return 2
            }
            ;;
        mv)
            external_mv_path=$(command -v mv)
            PROFILE_TEST_MV_CALL_COUNT=0
            mv()
            {
                PROFILE_TEST_MV_CALL_COUNT=$((PROFILE_TEST_MV_CALL_COUNT + 1))
                if [ "$PROFILE_TEST_MV_CALL_COUNT" -eq 1 ]; then
                    "$external_mv_path" "$@"
                    return $?
                fi
                return 1
            }
            ;;
        *)
            return 1
            ;;
    esac

    profile_confirm "$target_path" "$SCHEMA_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "2" "$status" "profile_confirm $failure_kind 종료 코드" || return 1
    assert_profile_memory_state "$expected_data" "$expected_schema_path" "$expected_schema_key" "$expected_schema_required" "$expected_schema_cardinality" "$expected_schema_type" "$expected_schema_allowed" "$expected_line" "$expected_line_set" "profile_confirm $failure_kind" || return 1
    assert_equal "$before_checksum" "$(cksum "$target_path")" "profile_confirm $failure_kind 디스크 원본" || return 1
    assert_equal "0" "$(count_profile_temp_files "$case_root" "target.conf")" "profile_confirm $failure_kind 임시 파일"
)

test_profile_accepts_repeated_source_roots()
{
    local case_root="$TEST_TEMP_ROOT/profile-repeated-roots"
    local lf_profile_path="$case_root/project-profile-lf.conf"
    local profile_path="$case_root/project-profile-crlf.conf"
    local output_path="$case_root/written-profile.conf"
    local roots
    local expected_roots
    local expected_project_name="  반복 프로젝트  "
    local status
    local line_ending_bytes
    local subcase_failed=0

    mkdir -p "$case_root"
    write_valid_profile "$lf_profile_path" "pending" "custom" "$expected_project_name" "Assets/Shared"
    printf '\n   \n\t\n' >> "$lf_profile_path"
    sed 's/$/\r/' "$lf_profile_path" > "$profile_path"
    assert_crlf_file "$profile_path" || return 1
    line_ending_bytes=$(tail -c 2 "$profile_path" | od -An -tx1 | tr -d ' \n')
    assert_equal "0d0a" "$line_ending_bytes" "CRLF 픽스처의 마지막 줄 끝 바이트가 다릅니다" || return 1
    echo "CRLF 픽스처 줄 끝 바이트 확인: $line_ending_bytes"
    load_profile_api || return 1
    load_and_validate_profile "$profile_path" || return 1

    roots=$(profile_get_all "source_root")
    expected_roots=$(printf '%s\n' 'Assets/_Game' 'Assets/Shared')
    assert_equal "$expected_roots" "$roots" "반복 source_root 순서가 보존되지 않았습니다" || return 1
    assert_equal "custom" "$(profile_get "architecture")" "architecture 조회 결과가 다릅니다" || return 1
    assert_equal "$expected_project_name" "$(profile_get "project_name")" "값 내부 공백이 보존되지 않았습니다" || return 1

    profile_write "$output_path"
    status=$?
    assert_equal "0" "$status" "프로필 쓰기 종료 코드가 다릅니다" || return 1
    assert_file_exists "$output_path" "프로필 쓰기 결과가 없습니다" || return 1
    roots=$(grep '^source_root=' "$output_path" | sed 's/^source_root=//')
    assert_equal "$expected_roots" "$roots" "작성된 source_root 순서가 다릅니다" || return 1

    run_profile_subcase "schema_order_and_set_single" profile_case_schema_order_and_set_single "$case_root/schema-order" || subcase_failed=1
    run_profile_subcase "profile_write_relative_path" profile_case_write_relative_path "$case_root/write-relative" || subcase_failed=1
    run_profile_subcase "profile_write_rejects_directory_targets" profile_case_write_rejects_directory_targets "$case_root/write-directory" || subcase_failed=1
    run_profile_subcase "profile_write_partial_failure" profile_case_write_partial_failure "$case_root/write-partial" || subcase_failed=1
    run_profile_subcase "profile_write_symlink_target_protected" profile_case_write_symlink_target_protected "$case_root/write-symlink" || subcase_failed=1
    run_profile_subcase "profile_write_hardlink_target_protected" profile_case_write_hardlink_target_protected "$case_root/write-hardlink" || subcase_failed=1
    run_profile_subcase "profile_write_preserves_mode" profile_case_write_preserves_mode "$case_root/write-mode" || subcase_failed=1
    run_profile_subcase "profile_confirm_success" profile_case_confirm_success "$case_root/confirm-success" || subcase_failed=1

    [ "$subcase_failed" -eq 0 ]
}

test_profile_rejects_unknown_key()
{
    local case_root="$TEST_TEMP_ROOT/profile-unknown-key"
    local profile_path="$case_root/project-profile.conf"
    local output
    local status
    local subcase_failed=0

    load_profile_api || return 1
    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "UnknownKey" ""
    printf '%s\n' 'unknown_key=value' >> "$profile_path"

    profile_reset
    output=$(profile_load "$profile_path" "$SCHEMA_PATH" 2>&1)
    status=$?
    if [ "$status" -eq 0 ]; then
        output=$(profile_validate "$SCHEMA_PATH" 2>&1)
        status=$?
    fi

    assert_equal "3" "$status" "알 수 없는 키의 종료 코드가 다릅니다" || return 1
    assert_contains "$output" "unknown_key" "알 수 없는 키 진단이 없습니다" || return 1

    run_profile_subcase "profile_load_unknown_preserves_memory" profile_case_load_failure_preserves_memory "$case_root/load-unknown" "unknown" || subcase_failed=1
    run_profile_subcase "profile_load_duplicate_preserves_memory" profile_case_load_failure_preserves_memory "$case_root/load-duplicate" "duplicate" || subcase_failed=1
    run_profile_subcase "profile_load_required_preserves_memory" profile_case_load_failure_preserves_memory "$case_root/load-required" "required" || subcase_failed=1
    run_profile_subcase "profile_load_bom_preserves_memory" profile_case_load_failure_preserves_memory "$case_root/load-bom" "bom" || subcase_failed=1
    run_profile_subcase "profile_load_read_failure_preserves_memory" profile_case_load_failure_preserves_memory "$case_root/load-read" "read" || subcase_failed=1

    [ "$subcase_failed" -eq 0 ]
}

test_profile_rejects_invalid_enum()
{
    local case_root="$TEST_TEMP_ROOT/profile-invalid-enum"
    local profile_path="$case_root/project-profile.conf"
    local output
    local status
    local subcase_failed=0

    load_profile_api || return 1
    mkdir -p "$case_root"
    write_valid_profile "$profile_path" "pending" "custom" "InvalidEnum" ""
    sed 's/^render_pipeline=.*/render_pipeline=invalid_pipeline/' "$profile_path" > "$case_root/invalid.conf"
    profile_path="$case_root/invalid.conf"

    profile_reset
    output=$(profile_load "$profile_path" "$SCHEMA_PATH" 2>&1)
    status=$?
    if [ "$status" -eq 0 ]; then
        output=$(profile_validate "$SCHEMA_PATH" 2>&1)
        status=$?
    fi

    assert_equal "3" "$status" "잘못된 열거형의 종료 코드가 다릅니다" || return 1
    assert_contains "$output" "invalid_pipeline" "잘못된 열거형 진단이 없습니다" || return 1

    run_profile_subcase "profile_load_enum_preserves_memory" profile_case_load_failure_preserves_memory "$case_root/load-enum" "enum" || subcase_failed=1

    [ "$subcase_failed" -eq 0 ]
}

test_profile_does_not_execute_values()
{
    local case_root="$TEST_TEMP_ROOT/profile-command-value"
    local profile_path="$case_root/project-profile.conf"
    local output_path="$case_root/written-profile.conf"
    local marker_path="$case_root/profile-value-executed"
    local backtick_marker_path="$case_root/profile-backtick-executed"
    local caller_profile_path="$case_root/caller-profile.conf"
    local payload
    local actual
    local caller_data
    local caller_schema_path
    local caller_confirmation_status
    local caller_project_name
    local status
    local subcase_failed=0

    load_profile_api || return 1
    mkdir -p "$case_root"
    payload='$(touch "'"$marker_path"'");`touch "'"$backtick_marker_path"'"`;printf 안전'
    write_valid_profile "$profile_path" "pending" "custom" "$payload" ""

    load_and_validate_profile "$profile_path" || return 1
    actual=$(profile_get "project_name")
    assert_equal "$payload" "$actual" "프로필 값이 문자열 그대로 보존되지 않았습니다" || return 1

    profile_write "$output_path"
    status=$?
    assert_equal "0" "$status" "명령 문자열 프로필 쓰기가 실패했습니다" || return 1
    assert_file_exists "$output_path" "명령 문자열 프로필 출력이 없습니다" || return 1
    if ! grep -Fqx "project_name=$payload" "$output_path"; then
        echo "명령 문자열이 출력 파일에 그대로 기록되지 않았습니다." >&2
        return 1
    fi

    assert_file_not_exists "$marker_path" "프로필 값이 명령으로 실행되었습니다" || return 1
    assert_file_not_exists "$backtick_marker_path" "백틱 프로필 값이 명령으로 실행되었습니다" || return 1

    write_valid_profile "$caller_profile_path" "pending" "custom" "호출전메모리" ""
    load_and_validate_profile "$caller_profile_path" || return 1
    caller_data=$_PROFILE_DATA
    caller_schema_path=$_PROFILE_SCHEMA_PATH
    caller_confirmation_status=$(profile_get "confirmation_status")
    caller_project_name=$(profile_get "project_name")

    mktemp()
    {
        return 1
    }

    profile_confirm "$profile_path" "$SCHEMA_PATH" >/dev/null 2>&1
    status=$?
    unset -f mktemp
    assert_equal "2" "$status" "임시 파일 생성 실패의 종료 코드가 다릅니다" || return 1
    assert_equal "$caller_data" "$_PROFILE_DATA" "임시 파일 생성 실패 후 프로필 메모리가 복원되지 않았습니다" || return 1
    assert_equal "$caller_schema_path" "$_PROFILE_SCHEMA_PATH" "임시 파일 생성 실패 후 스키마 상태가 복원되지 않았습니다" || return 1
    assert_equal "$caller_confirmation_status" "$(profile_get "confirmation_status")" "임시 파일 생성 실패 후 확정 상태가 바뀌었습니다" || return 1
    assert_equal "$caller_project_name" "$(profile_get "project_name")" "임시 파일 생성 실패 후 호출 전 프로젝트명이 복원되지 않았습니다" || return 1

    profile_confirm "$case_root/missing-profile.conf" "$SCHEMA_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "2" "$status" "프로필 로드 실패의 종료 코드가 다릅니다" || return 1
    assert_equal "$caller_data" "$_PROFILE_DATA" "프로필 로드 실패 후 프로필 메모리가 복원되지 않았습니다" || return 1
    assert_equal "$caller_schema_path" "$_PROFILE_SCHEMA_PATH" "프로필 로드 실패 후 스키마 상태가 복원되지 않았습니다" || return 1
    assert_equal "$caller_confirmation_status" "$(profile_get "confirmation_status")" "프로필 로드 실패 후 확정 상태가 바뀌었습니다" || return 1
    assert_equal "$caller_project_name" "$(profile_get "project_name")" "프로필 로드 실패 후 호출 전 프로젝트명이 복원되지 않았습니다" || return 1

    unset _PROFILE_LINE
    profile_confirm "$case_root/missing-profile.conf" "$SCHEMA_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "2" "$status" "전역 줄 상태가 없는 경우의 로드 실패 종료 코드가 다릅니다" || return 1
    if [ "${_PROFILE_LINE+x}" = "x" ]; then
        echo "프로필 로드 실패 후 원래 없던 전역 줄 상태가 생성되었습니다." >&2
        return 1
    fi

    run_profile_subcase "profile_confirm_mktemp_output_nonzero" profile_case_confirm_failure "$case_root/confirm-mktemp" "mktemp_nonzero" || subcase_failed=1
    run_profile_subcase "profile_confirm_cp_failure" profile_case_confirm_failure "$case_root/confirm-cp" "cp" || subcase_failed=1
    run_profile_subcase "profile_confirm_write_failure" profile_case_confirm_failure "$case_root/confirm-write" "write" || subcase_failed=1
    run_profile_subcase "profile_confirm_mv_failure" profile_case_confirm_failure "$case_root/confirm-mv" "mv" || subcase_failed=1

    [ "$subcase_failed" -eq 0 ]
}

test_detect_rejects_non_unity_directory()
{
    local case_root="$TEST_TEMP_ROOT/detect-not-unity"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local output
    local status

    load_detection_api || return 1
    mkdir -p "$project_root" "$case_root/output"
    printf '%s\n' '# Unity 프로젝트가 아닌 픽스처' > "$project_root/README.md"

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "2" "$status" "비Unity 디렉터리 감지 종료 코드가 다릅니다" || return 1
    assert_contains "$output" "Unity 프로젝트" "비Unity 디렉터리 진단이 없습니다" || return 1
    assert_file_not_exists "$profile_path" "비Unity 디렉터리에 프로필이 생성되었습니다" || return 1
    assert_file_not_exists "$report_path" "비Unity 디렉터리에 보고서가 생성되었습니다"
}

test_detects_mvvm_vcontainer_unitask_urp()
{
    local case_root="$TEST_TEMP_ROOT/detect-mvvm"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local output
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_unity_fixture "$project_root" "mvvm"

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "MVVM 픽스처 감지 종료 코드가 다릅니다" || return 1
    assert_file_exists "$profile_path" "감지 프로필이 없습니다" || return 1
    assert_file_exists "$report_path" "감지 보고서가 없습니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "mvvm" "$(profile_get "architecture")" "아키텍처 감지값이 다릅니다" || return 1
    assert_equal "vcontainer" "$(profile_get "dependency_injection")" "DI 감지값이 다릅니다" || return 1
    assert_equal "unitask" "$(profile_get "async_backend")" "비동기 감지값이 다릅니다" || return 1
    assert_equal "urp" "$(profile_get "render_pipeline")" "렌더 파이프라인 감지값이 다릅니다" || return 1
    assert_equal "dotween" "$(profile_get "tween_backend")" "트윈 감지값이 다릅니다" || return 1
    assert_equal "pending" "$(profile_get "confirmation_status")" "최초 프로필 상태가 pending이 아닙니다" || return 1
    assert_equal "6000.3.16f1" "$(profile_get "unity_version")" "Unity 버전 감지값이 다릅니다" || return 1
    assert_equal "Assets/_Game" "$(profile_get_all "source_root")" "소스 루트 경계가 다릅니다" || return 1
    assert_equal "Assets/_Game/Tests" "$(profile_get_all "test_root")" "테스트 루트 감지값이 다릅니다" || return 1
    assert_equal "unknown" "$(profile_get_all "target_platform")" "타겟 플랫폼은 정적 미확정이어야 합니다" || return 1
    assert_equal "ko" "$(profile_get "response_language")" "응답 언어 베이스 정책이 다릅니다" || return 1
    assert_equal "윤승종" "$(profile_get "author_name")" "작성자 베이스 정책이 다릅니다" || return 1
    assert_equal "m_" "$(profile_get "private_field_prefix")" "필드 접두사 베이스 정책이 다릅니다" || return 1
    assert_equal "func_" "$(profile_get "ui_callback_prefix")" "UI 콜백 접두사 베이스 정책이 다릅니다" || return 1
    assert_equal "encouraged" "$(profile_get "region_policy")" "리전 베이스 정책이 다릅니다" || return 1
    assert_equal "all_methods" "$(profile_get "xml_documentation_policy")" "XML 문서화 베이스 정책이 다릅니다" || return 1
    assert_equal "applicable" "$(profile_get "gpu_resident_drawer")" "GPU Resident Drawer 적용 가능성 값이 다릅니다" || return 1
    assert_equal "unknown" "$(profile_get "gpu_occlusion_culling")" "GPU Occlusion Culling 값이 다릅니다" || return 1
    assert_equal "applicable" "$(profile_get "stp")" "STP 적용 가능성 값이 다릅니다" || return 1
    assert_equal "unknown" "$(profile_get "mesh_lod")" "Mesh LOD 값이 다릅니다"
}

test_detection_uses_assets_game_as_only_code_scope()
{
    local case_root="$TEST_TEMP_ROOT/detect-assets-game-scope"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"

    load_detection_api || return 1
    mkdir -p "$case_root/output" \
        "$project_root/ProjectSettings" \
        "$project_root/Packages" \
        "$project_root/Assets/_Game/Runtime" \
        "$project_root/Assets/SomeVendor"
    printf '%s\n' 'm_EditorVersion: 6000.3.16f1' > "$project_root/ProjectSettings/ProjectVersion.txt"
    printf '%s\n' '{"dependencies":{"com.svermeulen.extenject":"9.2.0"}}' > "$project_root/Packages/manifest.json"
    printf '%s\n' 'public sealed class OwnedCode { }' > "$project_root/Assets/_Game/Runtime/OwnedCode.cs"
    printf '%s\n' 'using Zenject; public sealed class VendorCode { }' > "$project_root/Assets/SomeVendor/VendorCode.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal 'Assets/_Game' "$(profile_get_all source_root)" "감지 소스 루트" || return 1
    assert_equal 'unknown' "$(profile_get dependency_injection)" "외부 에셋 코드가 DI 감지에 포함되었습니다"
}

test_detection_rejects_missing_assets_game()
{
    local case_root="$TEST_TEMP_ROOT/detect-missing-assets-game"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output" "$project_root/ProjectSettings" "$project_root/Packages" "$project_root/Assets/Scripts"
    printf '%s\n' 'm_EditorVersion: 6000.3.16f1' > "$project_root/ProjectSettings/ProjectVersion.txt"
    printf '%s\n' '{"dependencies":{}}' > "$project_root/Packages/manifest.json"
    printf '%s\n' 'public sealed class LegacyCode { }' > "$project_root/Assets/Scripts/LegacyCode.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" > /dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "Assets/_Game 누락 종료 코드" || return 1
    assert_file_not_exists "$profile_path" "Assets/_Game 없이 프로필이 생성되었습니다"
}

test_architecture_conflict_falls_back_to_custom()
{
    local case_root="$TEST_TEMP_ROOT/detect-conflict"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local output
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_unity_fixture "$project_root" "conflict"

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "충돌 픽스처 감지 종료 코드가 다릅니다" || return 1
    assert_file_exists "$profile_path" "충돌 감지 프로필이 없습니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "custom" "$(profile_get "architecture")" "충돌 시 custom 폴백이 적용되지 않았습니다" || return 1
    assert_contains "$(LC_ALL=C sed -n '1,240p' "$report_path")" "충돌" "충돌 근거가 보고서에 없습니다"
}

test_architecture_ignores_comment_and_string_content_mentions()
{
    local case_root="$TEST_TEMP_ROOT/detect-architecture-text-only"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_neutral_unity_fixture "$project_root"
    printf '%s\n' \
        '// ViewModel' \
        'public sealed class ArchitectureTextOnly' \
        '{' \
        '    private const string Name = "ViewModel";' \
        '}' > "$project_root/Assets/_Game/Scripts/ArchitectureTextOnly.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "아키텍처 텍스트-only 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "custom" "$(profile_get "architecture")" "주석·문자열 ViewModel 언급을 아키텍처 근거로 오인했습니다"
}

test_existing_confirmed_profile_is_not_overwritten()
{
    local case_root="$TEST_TEMP_ROOT/detect-confirmed-profile"
    local project_root="$case_root/project"
    local profile_path="$project_root/.agents/config/project-profile.conf"
    local before_checksum
    local after_checksum
    local output
    local status

    load_detection_api || return 1
    require_file "$INITIALIZER_SCRIPT" "initialize-harness.sh" || return 1
    create_unity_fixture "$project_root" "mvvm"
    mkdir -p "$project_root/.agents/config"
    write_valid_profile "$profile_path" "confirmed" "custom" "ConfirmedProfile" ""
    before_checksum=$(cksum "$profile_path")

    output=$(bash "$INITIALIZER_SCRIPT" --project-root "$project_root" 2>&1)
    status=$?
    after_checksum=$(cksum "$profile_path")
    assert_equal "0" "$status" "확정 프로필 보호 종료 코드가 다릅니다" || return 1
    assert_contains "$output" "확정" "확정 프로필 보호 안내가 없습니다" || return 1
    assert_equal "$before_checksum" "$after_checksum" "확정 프로필이 덮어써졌습니다" || return 1
    assert_file_not_exists "$project_root/.agents/config/project-profile.candidate.conf" "승인 없는 후보 프로필이 생성되었습니다" || return 1

    output=$(bash "$INITIALIZER_SCRIPT" --project-root "$project_root" --redetect 2>&1)
    status=$?
    after_checksum=$(cksum "$profile_path")
    assert_equal "0" "$status" "명시적 재감지 종료 코드가 다릅니다" || return 1
    assert_contains "$output" "후보" "재감지 후보 안내가 없습니다" || return 1
    assert_equal "$before_checksum" "$after_checksum" "재감지 중 확정 프로필이 변경되었습니다" || return 1
    assert_file_exists "$project_root/.agents/config/project-profile.candidate.conf" "재감지 후보 프로필이 없습니다" || return 1
    assert_contains "$(sed -n '1,260p' "$project_root/.agents/reports/detection-report.md")" "비교" "재감지 비교 보고서가 없습니다" || return 1
    assert_detection_report_headings "$project_root/.agents/reports/detection-report.md"
}

test_detection_rejects_malformed_inputs()
{
    local case_root="$TEST_TEMP_ROOT/detect-malformed"
    local project_root
    local profile_path
    local report_path
    local output
    local status

    load_detection_api || return 1

    for fixture_name in double-comma trailing-comma unclosed-string bad-escape
    do
        project_root="$case_root/$fixture_name/project"
        profile_path="$case_root/$fixture_name/output/project-profile.conf"
        report_path="$case_root/$fixture_name/output/detection-report.md"
        mkdir -p "$case_root/$fixture_name/output"
        create_unity_fixture "$project_root" "mvvm"
        case "$fixture_name" in
            double-comma)
                printf '%s\n' '{"dependencies":{"a":"1",,"b":"2"}}' > "$project_root/Packages/manifest.json"
                ;;
            trailing-comma)
                printf '%s\n' '{"dependencies":{"a":"1",}}' > "$project_root/Packages/manifest.json"
                ;;
            unclosed-string)
                printf '%s\n' '{"dependencies":{"a":"1}}' > "$project_root/Packages/manifest.json"
                ;;
            bad-escape)
                printf '%s\n' '{"dependencies":{"a":"\q"}}' > "$project_root/Packages/manifest.json"
                ;;
        esac

        output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
        status=$?
        assert_equal "4" "$status" "$fixture_name manifest 종료 코드가 다릅니다" || return 1
        assert_contains "$output" "manifest.json" "$fixture_name manifest 진단이 없습니다" || return 1
        assert_file_not_exists "$profile_path" "$fixture_name manifest에서 프로필이 생성되었습니다" || return 1
        assert_file_not_exists "$report_path" "$fixture_name manifest에서 보고서가 생성되었습니다" || return 1
    done

    project_root="$case_root/valid-escaped/project"
    profile_path="$case_root/valid-escaped/output/project-profile.conf"
    report_path="$case_root/valid-escaped/output/detection-report.md"
    mkdir -p "$case_root/valid-escaped/output"
    create_unity_fixture "$project_root" "mvvm"
    printf '%s\n' '{"dependencies":{"pkg":"1.0.0"},"text":"quote \" slash \\ solidus \/ controls \b\f\n\r\t unicode \uAC00","number":-12.3e+4,"array":[true,false,null,{"nested":0}]}' > "$project_root/Packages/manifest.json"
    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "escape와 전체 JSON 값이 유효한 manifest 종료 코드가 다릅니다" || return 1
    assert_file_exists "$profile_path" "유효한 escaped manifest 프로필이 없습니다" || return 1
    assert_file_exists "$report_path" "유효한 escaped manifest 보고서가 없습니다" || return 1

    project_root="$case_root/project-version/project"
    profile_path="$case_root/project-version/output/project-profile.conf"
    report_path="$case_root/project-version/output/detection-report.md"
    mkdir -p "$case_root/project-version/output"
    create_unity_fixture "$project_root" "mvvm"
    printf '%s\n' 'm_EditorVersionWithRevision: invalid' > "$project_root/ProjectSettings/ProjectVersion.txt"
    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "4" "$status" "손상된 ProjectVersion 종료 코드가 다릅니다" || return 1
    assert_contains "$output" "ProjectVersion.txt" "손상된 ProjectVersion 진단이 없습니다" || return 1
    assert_file_not_exists "$profile_path" "손상된 ProjectVersion에서 프로필이 생성되었습니다" || return 1
    assert_file_not_exists "$report_path" "손상된 ProjectVersion에서 보고서가 생성되었습니다"
}

test_detection_handles_package_conflicts_and_exclusions()
{
    local case_root="$TEST_TEMP_ROOT/detect-package-conflicts"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local output
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_unity_fixture "$project_root" "mvvm"
    printf '%s\n' \
        '{' \
        '  "dependencies": {' \
        '    "com.unity.render-pipelines.universal": "17.0.3",' \
        '    "com.unity.render-pipelines.high-definition": "17.0.3",' \
        '    "jp.hadashikick.vcontainer": "1.16.8",' \
        '    "com.svermeulen.extenject": "9.2.0"' \
        '  }' \
        '}' > "$project_root/Packages/manifest.json"
    printf '%s\n' \
        'using System.Collections;' \
        'using System.Threading.Tasks;' \
        'using Zenject;' \
        'public sealed class AsyncBridge' \
        '{' \
        '    public Task RunAsync() { return Task.CompletedTask; }' \
        '    public IEnumerator RunRoutine() { yield return null; }' \
        '    public void Tween() { LeanTween.cancelAll(); }' \
        '}' > "$project_root/Assets/_Game/Scripts/AsyncBridge.cs"

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "패키지 충돌 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "custom" "$(profile_get "render_pipeline")" "URP/HDRP 충돌이 custom이 아닙니다" || return 1
    assert_equal "custom" "$(profile_get "dependency_injection")" "DI 충돌이 custom이 아닙니다" || return 1
    assert_equal "mixed" "$(profile_get "async_backend")" "복수 비동기 증거가 mixed가 아닙니다" || return 1
    assert_equal "custom" "$(profile_get "tween_backend")" "복수 트윈 증거가 custom이 아닙니다" || return 1
    assert_equal "mvvm" "$(profile_get "architecture")" "제외 루트의 강한 시그니처가 아키텍처에 반영되었습니다" || return 1
    assert_not_contains "$(profile_get_all "source_root")" "Assets/Plugins" "Plugins가 소스 루트에 포함되었습니다" || return 1
    assert_not_contains "$(profile_get_all "source_root")" "Assets/ThirdParty" "ThirdParty가 소스 루트에 포함되었습니다" || return 1
    assert_contains "$(sed -n '1,260p' "$report_path")" "충돌" "패키지 충돌 근거가 보고서에 없습니다"
}

test_detection_requires_code_usage_for_package_backends()
{
    local case_root="$TEST_TEMP_ROOT/detect-package-usage"
    local project_root="$case_root/package-only/project"
    local profile_path="$case_root/package-only/output/project-profile.conf"
    local report_path="$case_root/package-only/output/detection-report.md"
    local report
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/package-only/output"
    create_unity_fixture "$project_root" "conflict"
    printf '%s\n' \
        '{' \
        '  "dependencies": {' \
        '    "jp.hadashikick.vcontainer": "1.16.8",' \
        '    "com.svermeulen.extenject": "9.2.0",' \
        '    "com.cysharp.unitask": "2.5.10",' \
        '    "com.demigiant.dotween": "1.2.0",' \
        '    "com.vendor.leantween": "2.51"' \
        '  }' \
        '}' > "$project_root/Packages/manifest.json"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "패키지만 있는 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unknown" "$(profile_get "dependency_injection")" "패키지만 있는 DI를 사용 확정했습니다" || return 1
    assert_equal "unknown" "$(profile_get "async_backend")" "패키지만 있는 UniTask를 사용 확정했습니다" || return 1
    assert_equal "unknown" "$(profile_get "tween_backend")" "패키지만 있는 트윈을 사용 확정했습니다" || return 1
    report=$(sed -n '1,300p' "$report_path")
    assert_contains "$report" "설치만 확인" "패키지 설치-only 보고가 없습니다" || return 1
    assert_contains "$report" "사용 미확정" "패키지 사용 미확정 보고가 없습니다" || return 1

    project_root="$case_root/code-only/project"
    profile_path="$case_root/code-only/output/project-profile.conf"
    report_path="$case_root/code-only/output/detection-report.md"
    mkdir -p "$case_root/code-only/output"
    create_unity_fixture "$project_root" "conflict"
    printf '%s\n' \
        'using VContainer;' \
        'using Cysharp.Threading.Tasks;' \
        'using DG.Tweening;' \
        'public sealed class VendoredBackendUsage { }' > "$project_root/Assets/_Game/Scripts/VendoredBackendUsage.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "코드-only 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "vcontainer" "$(profile_get "dependency_injection")" "코드-only VContainer 근거가 허용되지 않았습니다" || return 1
    assert_equal "unitask" "$(profile_get "async_backend")" "코드-only UniTask 근거가 허용되지 않았습니다" || return 1
    assert_equal "dotween" "$(profile_get "tween_backend")" "코드-only DOTween 근거가 허용되지 않았습니다" || return 1

    project_root="$case_root/code-only-alternate/project"
    profile_path="$case_root/code-only-alternate/output/project-profile.conf"
    report_path="$case_root/code-only-alternate/output/detection-report.md"
    mkdir -p "$case_root/code-only-alternate/output"
    create_unity_fixture "$project_root" "conflict"
    printf '%s\n' \
        'using Zenject;' \
        'public sealed class AlternateVendoredBackendUsage' \
        '{' \
        '    private DiContainer m_container;' \
        '    public void Play() { LeanTween.cancelAll(); }' \
        '}' > "$project_root/Assets/_Game/Scripts/AlternateVendoredBackendUsage.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "대체 코드-only 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "zenject" "$(profile_get "dependency_injection")" "코드-only Zenject 근거가 허용되지 않았습니다" || return 1
    assert_equal "leantween" "$(profile_get "tween_backend")" "코드-only LeanTween 근거가 허용되지 않았습니다"
}

test_packages_lock_dependencies_are_merged_and_validated()
{
    local case_root="$TEST_TEMP_ROOT/detect-packages-lock"
    local project_root="$case_root/merged/project"
    local profile_path="$case_root/merged/output/project-profile.conf"
    local report_path="$case_root/merged/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/merged/output"
    create_neutral_unity_fixture "$project_root"
    printf '%s\n' \
        '{' \
        '  "dependencies": {' \
        '    "com.unity.render-pipelines.universal": { "version": "17.0.3" },' \
        '    "jp.hadashikick.vcontainer": { "version": "1.16.8" },' \
        '    "com.cysharp.unitask": { "version": "2.5.10" },' \
        '    "com.demigiant.dotween": { "version": "1.2.0" }' \
        '  }' \
        '}' > "$project_root/Packages/packages-lock.json"
    printf '%s\n' \
        'using VContainer;' \
        'using Cysharp.Threading.Tasks;' \
        'using DG.Tweening;' \
        'public sealed class LockBackedUsage { }' > "$project_root/Assets/_Game/Scripts/LockBackedUsage.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "packages-lock 병합 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "urp" "$(profile_get "render_pipeline")" "packages-lock 렌더 패키지가 병합되지 않았습니다" || return 1
    assert_equal "vcontainer" "$(profile_get "dependency_injection")" "packages-lock DI와 코드 사용 근거가 결합되지 않았습니다" || return 1
    assert_equal "unitask" "$(profile_get "async_backend")" "packages-lock 비동기와 코드 사용 근거가 결합되지 않았습니다" || return 1
    assert_equal "dotween" "$(profile_get "tween_backend")" "packages-lock 트윈과 코드 사용 근거가 결합되지 않았습니다" || return 1
    assert_contains "$(sed -n '1,260p' "$report_path")" "Packages/packages-lock.json" "보고서에 packages-lock 근거가 없습니다" || return 1

    project_root="$case_root/package-only/project"
    profile_path="$case_root/package-only/output/project-profile.conf"
    report_path="$case_root/package-only/output/detection-report.md"
    mkdir -p "$case_root/package-only/output"
    create_neutral_unity_fixture "$project_root"
    printf '%s\n' \
        '{ "dependencies": {' \
        '  "jp.hadashikick.vcontainer": { "version": "1.16.8" },' \
        '  "com.cysharp.unitask": { "version": "2.5.10" },' \
        '  "com.demigiant.dotween": { "version": "1.2.0" }' \
        '} }' > "$project_root/Packages/packages-lock.json"
    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "packages-lock 설치-only 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unknown" "$(profile_get "dependency_injection")" "packages-lock 설치만으로 DI 사용을 확정했습니다" || return 1
    assert_equal "unknown" "$(profile_get "async_backend")" "packages-lock 설치만으로 비동기 사용을 확정했습니다" || return 1
    assert_equal "unknown" "$(profile_get "tween_backend")" "packages-lock 설치만으로 트윈 사용을 확정했습니다" || return 1

    for fixture_name in malformed invalid-dependencies unreadable
    do
        project_root="$case_root/$fixture_name/project"
        profile_path="$case_root/$fixture_name/output/project-profile.conf"
        report_path="$case_root/$fixture_name/output/detection-report.md"
        mkdir -p "$case_root/$fixture_name/output"
        create_neutral_unity_fixture "$project_root"
        case "$fixture_name" in
            malformed)
                printf '%s\n' '{"dependencies":{"broken":}}' > "$project_root/Packages/packages-lock.json"
                ;;
            invalid-dependencies)
                printf '%s\n' '{"dependencies":[]}' > "$project_root/Packages/packages-lock.json"
                ;;
            unreadable)
                printf '%s\n' '{"dependencies":{}}' > "$project_root/Packages/packages-lock.json"
                chmod 000 "$project_root/Packages/packages-lock.json" || return 1
                ;;
        esac
        detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
        status=$?
        if [ "$fixture_name" = "unreadable" ]; then
            chmod 600 "$project_root/Packages/packages-lock.json" || return 1
        fi
        assert_equal "4" "$status" "$fixture_name packages-lock 종료 코드가 다릅니다" || return 1
        assert_file_not_exists "$profile_path" "$fixture_name packages-lock에서 프로필이 생성되었습니다" || return 1
        assert_file_not_exists "$report_path" "$fixture_name packages-lock에서 보고서가 생성되었습니다" || return 1
    done
}

test_detection_package_cache_is_scoped_to_detect_project()
{
    local case_root="$TEST_TEMP_ROOT/detect-package-cache-scope"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local physical_root
    local actual

    load_detection_api || return 1
    mkdir -p "$case_root/output" "$case_root/non-unity"
    create_unity_fixture "$project_root" "mvvm"
    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1 || return 1
    physical_root=$(find_unity_project_root "$project_root") || return 1

    printf '%s\n' '{ "dependencies": { "com.unity.render-pipelines.high-definition": "17.0.3" } }' > "$project_root/Packages/manifest.json"
    actual=$(detect_render_pipeline "$physical_root") || return 1
    assert_equal "hdrp" "$actual" "성공한 detect_project가 standalone 감지에 오래된 패키지 캐시를 남겼습니다" || return 1

    printf '%s\n' '{ "dependencies": { "com.unity.render-pipelines.universal": "17.0.3" } }' > "$project_root/Packages/manifest.json"
    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1 || return 1
    printf '%s\n' '{ "dependencies": { "com.unity.render-pipelines.high-definition": "17.0.3" } }' > "$project_root/Packages/manifest.json"
    detect_project "$case_root/non-unity" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    actual=$(detect_render_pipeline "$physical_root") || return 1
    assert_equal "hdrp" "$actual" "실패한 detect_project가 이전 패키지 캐시를 남겼습니다"
}

test_detection_covers_supported_architecture_matrix()
{
    local case_root="$TEST_TEMP_ROOT/detect-architecture-matrix"
    local architecture
    local project_root
    local profile_path
    local report_path
    local status

    load_detection_api || return 1
    for architecture in mvp mvc layered_clean
    do
        project_root="$case_root/$architecture/project"
        profile_path="$case_root/$architecture/output/project-profile.conf"
        report_path="$case_root/$architecture/output/detection-report.md"
        mkdir -p "$case_root/$architecture/output"
        create_architecture_fixture "$project_root" "$architecture" || return 1
        detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
        status=$?
        assert_equal "0" "$status" "$architecture 감지 종료 코드가 다릅니다" || return 1
        load_and_validate_profile "$profile_path" || return 1
        assert_equal "$architecture" "$(profile_get "architecture")" "$architecture 아키텍처가 직접 감지되지 않았습니다" || return 1
        case "$architecture" in
            mvp)
                assert_equal "builtin" "$(profile_get "render_pipeline")" "MVP Built-in 감지가 다릅니다" || return 1
                assert_equal "coroutine" "$(profile_get "async_backend")" "MVP Coroutine 감지가 다릅니다" || return 1
                assert_equal "not_applicable" "$(profile_get "gpu_resident_drawer")" "Built-in GPU Resident Drawer 상태가 다릅니다" || return 1
                assert_equal "not_applicable" "$(profile_get "stp")" "Built-in STP 상태가 다릅니다" || return 1
                ;;
            mvc)
                assert_equal "hdrp" "$(profile_get "render_pipeline")" "MVC HDRP 감지가 다릅니다" || return 1
                ;;
            layered_clean)
                assert_equal "custom" "$(profile_get "dependency_injection")" "Layered/Clean Custom DI 감지가 다릅니다" || return 1
                ;;
        esac
    done
}

test_detection_uses_only_top_level_dependency_keys()
{
    local case_root="$TEST_TEMP_ROOT/detect-manifest-key-boundary"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_neutral_unity_fixture "$project_root"
    printf '%s\n' \
        '{' \
        '  "dependencies": {' \
        '    "com.example.helper": "https://example.invalid/vcontainer/unitask/dotween"' \
        '  },' \
        '  "note": "jp.hadashikick.vcontainer com.svermeulen.extenject com.cysharp.unitask com.demigiant.dotween com.vendor.leantween",' \
        '  "nested": {' \
        '    "dependencies": {' \
        '      "com.unity.render-pipelines.universal": "17.0.3",' \
        '      "com.unity.render-pipelines.high-definition": "17.0.3",' \
        '      "com.cysharp.unitask": "2.5.10"' \
        '    },' \
        '    "jp.hadashikick.vcontainer": "1.16.8"' \
        '  }' \
        '}' > "$project_root/Packages/manifest.json"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "manifest key 경계 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "builtin" "$(profile_get "render_pipeline")" "note·nested·값 문자열을 렌더 패키지 key로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "dependency_injection")" "note·nested·값 문자열을 DI 패키지 key로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "async_backend")" "note·nested·값 문자열을 UniTask 패키지 key로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "tween_backend")" "note·nested·값 문자열을 트윈 패키지 key로 오인했습니다"
}

test_detection_ignores_comment_only_backend_mentions()
{
    local case_root="$TEST_TEMP_ROOT/detect-comment-only-backends"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_unity_fixture "$project_root" "conflict"
    printf '%s\n' \
        '// VContainer Zenject UniTask Cysharp.Threading.Tasks DG.Tweening DOTween LeanTween' \
        '/* VContainer Zenject' \
        'UniTask DG.Tweening DOTween LeanTween */' \
        'public sealed class CommentOnlyBackendMentions { }' > "$project_root/Assets/_Game/Scripts/CommentOnlyBackendMentions.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "주석-only 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unknown" "$(profile_get "dependency_injection")" "주석-only DI 언급을 사용 근거로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "async_backend")" "주석-only UniTask 언급을 사용 근거로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "tween_backend")" "주석-only 트윈 언급을 사용 근거로 오인했습니다"
}

test_detection_ignores_string_only_backend_mentions()
{
    local case_root="$TEST_TEMP_ROOT/detect-string-only-backends"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_unity_fixture "$project_root" "conflict"
    printf '%s\n' \
        'public sealed class StringOnlyBackendMentions' \
        '{' \
        '    private const string Names = "VContainer Zenject UniTask Cysharp.Threading.Tasks DG.Tweening DOTween LeanTween";' \
        '    private const string VerbatimNames = @"VContainer Zenject UniTask DG.Tweening DOTween LeanTween";' \
        '    private const string InterpolatedNames = $"VContainer Zenject UniTask DG.Tweening DOTween LeanTween";' \
        '    private const string RawNames = """VContainer Zenject UniTask DG.Tweening DOTween LeanTween""";' \
        '}' > "$project_root/Assets/_Game/Scripts/StringOnlyBackendMentions.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "문자열-only 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unknown" "$(profile_get "dependency_injection")" "문자열-only DI 언급을 사용 근거로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "async_backend")" "문자열-only UniTask 언급을 사용 근거로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "tween_backend")" "문자열-only 트윈 언급을 사용 근거로 오인했습니다"
}

test_detection_preserves_interpolation_expression_code()
{
    local case_root="$TEST_TEMP_ROOT/detect-interpolation-expression"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_neutral_unity_fixture "$project_root"
    printf '%s\n' \
        'public sealed class InterpolationExpressionBackendUsage' \
        '{' \
        '    public string Value => $"{global::Cysharp.Threading.Tasks.UniTask.CompletedTask}";' \
        '}' > "$project_root/Assets/_Game/Scripts/InterpolationExpressionBackendUsage.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "보간식 코드 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unitask" "$(profile_get "async_backend")" "보간 문자열 내부 C# 식을 코드 근거에서 제거했습니다"
}

test_detection_respects_raw_and_format_interpolation_boundaries()
{
    local case_root="$TEST_TEMP_ROOT/detect-interpolation-boundaries"
    local project_root="$case_root/raw/project"
    local profile_path="$case_root/raw/output/project-profile.conf"
    local report_path="$case_root/raw/output/detection-report.md"
    local failure_count=0
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/raw/output"
    create_neutral_unity_fixture "$project_root"
    printf '%s\n' \
        'public sealed class RawInterpolationExpressionBackendUsage' \
        '{' \
        '    public string Value => $"""{global::Cysharp.Threading.Tasks.UniTask.CompletedTask}""";' \
        '}' > "$project_root/Assets/_Game/Scripts/RawInterpolationExpressionBackendUsage.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "raw 보간식 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unitask" "$(profile_get "async_backend")" "raw 보간 문자열 내부 C# 식을 코드 근거에서 제거했습니다" || failure_count=$((failure_count + 1))

    project_root="$case_root/format/project"
    profile_path="$case_root/format/output/project-profile.conf"
    report_path="$case_root/format/output/detection-report.md"
    mkdir -p "$case_root/format/output"
    create_neutral_unity_fixture "$project_root"
    printf '%s\n' \
        'public sealed class InterpolationFormatOnlyBackendMention' \
        '{' \
        '    public string Value => $"{value:UniTask}";' \
        '}' > "$project_root/Assets/_Game/Scripts/InterpolationFormatOnlyBackendMention.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "보간 format 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unknown" "$(profile_get "async_backend")" "보간 format 문자열을 C# 코드 근거로 오인했습니다" || failure_count=$((failure_count + 1))

    [ "$failure_count" -eq 0 ]
}

test_detection_ignores_path_only_backend_mentions()
{
    local case_root="$TEST_TEMP_ROOT/detect-path-only-backends"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local mention_root
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_unity_fixture "$project_root" "conflict"
    mention_root="$project_root/Assets/_Game/VContainer/Zenject/UniTask/DG.Tweening/DOTween/LeanTween"
    mkdir -p "$mention_root"
    printf '%s\n' 'public sealed class NeutralBackendClass { }' > "$mention_root/NeutralBackendClass.cs"

    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "경로-only 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "unknown" "$(profile_get "dependency_injection")" "경로-only DI 언급을 사용 근거로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "async_backend")" "경로-only UniTask 언급을 사용 근거로 오인했습니다" || return 1
    assert_equal "unknown" "$(profile_get "tween_backend")" "경로-only 트윈 언급을 사용 근거로 오인했습니다"
}

test_detection_scans_nested_names_and_excludes_agent_backups()
{
    local case_root="$TEST_TEMP_ROOT/detect-directory-boundaries"
    local project_root="$case_root/nested/project"
    local profile_path="$case_root/nested/output/project-profile.conf"
    local report_path="$case_root/nested/output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/nested/output"
    create_unity_fixture "$project_root" "mvvm"
    mkdir -p "$project_root/Assets/_Game/Library/Presenters"
    printf '%s\n' 'public sealed class NestedPresenter { }' > "$project_root/Assets/_Game/Library/Presenters/NestedPresenter.cs"
    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "중첩 동명 폴더 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "custom" "$(profile_get "architecture")" "Assets/_Game/Library의 코드 근거가 감지에서 누락되었습니다" || return 1

    project_root="$case_root/backups/project"
    profile_path="$case_root/backups/output/project-profile.conf"
    report_path="$case_root/backups/output/detection-report.md"
    mkdir -p "$case_root/backups/output"
    create_unity_fixture "$project_root" "mvvm"
    mkdir -p "$project_root/.agents/Presenters" "$project_root/.agents-backup/Presenters"
    printf '%s\n' 'public sealed class AgentPresenter { }' > "$project_root/.agents/Presenters/AgentPresenter.cs"
    printf '%s\n' 'public sealed class BackupPresenter { }' > "$project_root/.agents-backup/Presenters/BackupPresenter.cs"
    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "에이전트 백업 제외 픽스처 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "mvvm" "$(profile_get "architecture")" "루트 .agents 또는 .agents-backup 코드가 감지에 포함되었습니다"
}

test_detection_sanitizes_500_files_once()
{
    local case_root="$TEST_TEMP_ROOT/detect-500-file-performance"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local index=1
    local previous_tmpdir=${TMPDIR-}
    local started_at
    local finished_at
    local elapsed_seconds
    local failure_count=0
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/output" "$case_root/cache" "$project_root/Assets/_Game/Generated"
    create_neutral_unity_fixture "$project_root"
    while [ "$index" -le 500 ]
    do
        printf '%s\n' \
            "public sealed class NeutralGenerated${index}" \
            '{' \
            "    public int Value => ${index};" \
            '}' > "$project_root/Assets/_Game/Generated/NeutralGenerated${index}.cs"
        index=$((index + 1))
    done

    TMPDIR="$case_root/cache"
    started_at=$(date +%s)
    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    finished_at=$(date +%s)
    if [ -n "$previous_tmpdir" ]; then
        TMPDIR=$previous_tmpdir
    else
        unset TMPDIR
    fi
    elapsed_seconds=$((finished_at - started_at))

    assert_equal "0" "$status" "500파일 성능 픽스처 감지 종료 코드가 다릅니다" || return 1
    assert_equal "1" "$_DETECT_SANITIZER_INVOCATIONS" "500파일 감지에서 sanitizer가 단일 실행되지 않았습니다" || failure_count=$((failure_count + 1))
    assert_equal "1" "$_DETECT_CODE_LIST_COLLECTIONS" "500파일 감지에서 코드 파일 목록을 한 번만 수집하지 않았습니다" || failure_count=$((failure_count + 1))
    assert_equal "0" "$(find "$case_root/cache" -type f -print | wc -l | tr -d ' ')" "500파일 정상 완료 후 코드 캐시 임시 파일" || failure_count=$((failure_count + 1))
    printf '%s\n' "[진단] 500파일 단일 감지: ${elapsed_seconds}초, 파일 목록 ${_DETECT_CODE_LIST_COLLECTIONS}회, sanitizer ${_DETECT_SANITIZER_INVOCATIONS}회" >&2
    if [ "$elapsed_seconds" -gt 20 ]; then
        printf '%s\n' "[진단] 500파일 단일 감지가 20초 예산을 초과했습니다: ${elapsed_seconds}초" >&2
        failure_count=$((failure_count + 1))
    fi

    [ "$failure_count" -eq 0 ]
}

test_detection_rejects_missing_or_unreadable_required_files()
{
    local case_root="$TEST_TEMP_ROOT/detect-required-files"
    local fixture_name
    local project_root
    local profile_path
    local report_path
    local schema_path
    local signatures_path
    local output
    local status

    load_detection_api || return 1

    for fixture_name in missing-manifest missing-version missing-schema missing-signatures unreadable-manifest
    do
        project_root="$case_root/$fixture_name/project"
        profile_path="$case_root/$fixture_name/output/project-profile.conf"
        report_path="$case_root/$fixture_name/output/detection-report.md"
        schema_path=$SCHEMA_PATH
        signatures_path=$SIGNATURES_PATH
        mkdir -p "$case_root/$fixture_name/output"
        create_unity_fixture "$project_root" "mvvm"

        case "$fixture_name" in
            missing-manifest)
                rm "$project_root/Packages/manifest.json"
                ;;
            missing-version)
                rm "$project_root/ProjectSettings/ProjectVersion.txt"
                ;;
            missing-schema)
                schema_path="$case_root/$fixture_name/missing-schema.conf"
                ;;
            missing-signatures)
                signatures_path="$case_root/$fixture_name/missing-signatures.conf"
                ;;
            unreadable-manifest)
                chmod 000 "$project_root/Packages/manifest.json" || return 1
                ;;
        esac

        output=$(detect_project "$project_root" "$profile_path" "$report_path" "$schema_path" "$signatures_path" 2>&1)
        status=$?
        if [ "$fixture_name" = "unreadable-manifest" ]; then
            chmod 600 "$project_root/Packages/manifest.json" || return 1
        fi
        assert_equal "4" "$status" "$fixture_name 필수 파일 종료 코드가 다릅니다" || return 1
        assert_contains "$output" "읽을 수 없습니다" "$fixture_name 필수 파일 진단이 없습니다" || return 1
        assert_file_not_exists "$profile_path" "$fixture_name 필수 파일 오류에서 프로필이 생성되었습니다" || return 1
        assert_file_not_exists "$report_path" "$fixture_name 필수 파일 오류에서 보고서가 생성되었습니다" || return 1
    done
}

test_detection_report_has_required_evidence()
{
    local case_root="$TEST_TEMP_ROOT/detect-report"
    local project_root="$case_root/project"
    local profile_path="$case_root/output/project-profile.conf"
    local report_path="$case_root/output/detection-report.md"
    local report
    local status
    local heading

    load_detection_api || return 1
    mkdir -p "$case_root/output"
    create_unity_fixture "$project_root" "mvvm"
    detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "보고서 감지 종료 코드가 다릅니다" || return 1
    report=$(sed -n '1,320p' "$report_path")
    for heading in \
        '# Unity 하네스 감지 보고서' \
        '## 요약' \
        '## 감지 근거와 신뢰도' \
        '## 소스 및 테스트 루트' \
        '## 조건부 최적화 적용 가능성' \
        '## 충돌 및 미확정 항목' \
        '## 사용자 확인 절차'
    do
        assert_contains "$report" "$heading" "필수 보고서 헤딩이 없습니다" || return 1
    done
    assert_detection_report_headings "$report_path" || return 1
    assert_contains "$report" "ProjectSettings/ProjectVersion.txt" "Unity 버전 근거 파일이 없습니다" || return 1
    assert_contains "$report" "Packages/manifest.json" "패키지 근거 파일이 없습니다" || return 1
    assert_contains "$report" "신뢰도" "항목별 신뢰도가 없습니다" || return 1
    assert_contains "$report" '- 프로젝트: `project` (신뢰도: high, 근거 파일: 프로젝트 루트 디렉터리명)' "요약의 프로젝트 값·신뢰도·근거가 없습니다" || return 1
    assert_contains "$report" '- Unity: `6000.3.16f1` (신뢰도: high, 근거 파일: `ProjectSettings/ProjectVersion.txt`)' "요약의 Unity 값·신뢰도·근거가 없습니다" || return 1
    assert_contains "$report" "target_platform" "타겟 플랫폼 확인 항목이 없습니다"
}

test_detection_rolls_back_profile_when_report_fails()
(
    local case_root="$TEST_TEMP_ROOT/detect-output-transaction"
    local project_root="$case_root/project"
    local profile_path="$case_root/commit-failure/project-profile.conf"
    local report_path="$case_root/commit-failure/detection-report.md"
    local directory_profile_path="$case_root/directory-failure/project-profile.conf"
    local report_directory="$case_root/directory-failure/detection-report.md"
    local external_mv_path
    local before_profile_checksum
    local before_report_checksum
    local before_profile_mode
    local before_report_mode
    local before_directory_profile_checksum
    local before_directory_profile_mode
    local before_report_directory_mode
    local output
    local status
    local final_argument

    load_detection_api || return 1
    create_unity_fixture "$project_root" "mvvm"
    mkdir -p "$case_root/commit-failure" "$case_root/directory-failure" "$report_directory"
    write_valid_profile "$profile_path" "pending" "custom" "기존 프로필" ""
    printf '%s\n' '기존 보고서' > "$report_path"
    chmod 640 "$profile_path" || return 1
    chmod 600 "$report_path" || return 1
    before_profile_checksum=$(cksum "$profile_path")
    before_report_checksum=$(cksum "$report_path")
    before_profile_mode=$(get_file_mode "$profile_path") || return 1
    before_report_mode=$(get_file_mode "$report_path") || return 1

    external_mv_path=$(command -v mv)
    mv()
    {
        for final_argument in "$@"
        do
            :
        done
        if [ "$final_argument" = "$report_path" ]; then
            return 1
        fi
        "$external_mv_path" "$@"
    }

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "2" "$status" "보고서 커밋 실패 종료 코드가 다릅니다" || return 1
    assert_equal "$before_profile_checksum" "$(cksum "$profile_path")" "보고서 커밋 실패 후 기존 프로필이 롤백되지 않았습니다" || return 1
    assert_equal "$before_report_checksum" "$(cksum "$report_path")" "보고서 커밋 실패 후 기존 보고서가 변경되었습니다" || return 1
    assert_equal "$before_profile_mode" "$(get_file_mode "$profile_path")" "보고서 커밋 실패 후 프로필 권한이 변경되었습니다" || return 1
    assert_equal "$before_report_mode" "$(get_file_mode "$report_path")" "보고서 커밋 실패 후 보고서 권한이 변경되었습니다" || return 1

    write_valid_profile "$directory_profile_path" "pending" "custom" "디렉터리 실패 기존 프로필" ""
    printf '%s\n' '보고서 디렉터리 보존' > "$report_directory/sentinel.txt"
    chmod 640 "$directory_profile_path" || return 1
    chmod 750 "$report_directory" || return 1
    before_directory_profile_checksum=$(cksum "$directory_profile_path")
    before_directory_profile_mode=$(get_file_mode "$directory_profile_path") || return 1
    before_report_directory_mode=$(get_file_mode "$report_directory") || return 1

    detect_project "$project_root" "$directory_profile_path" "$report_directory" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "2" "$status" "보고서 디렉터리 주입 종료 코드가 다릅니다" || return 1
    assert_equal "$before_directory_profile_checksum" "$(cksum "$directory_profile_path")" "보고서 디렉터리 주입 후 기존 프로필이 변경되었습니다" || return 1
    assert_equal "$before_directory_profile_mode" "$(get_file_mode "$directory_profile_path")" "보고서 디렉터리 주입 후 프로필 권한이 변경되었습니다" || return 1
    assert_equal "$before_report_directory_mode" "$(get_file_mode "$report_directory")" "보고서 디렉터리 권한이 변경되었습니다" || return 1
    assert_equal "보고서 디렉터리 보존" "$(sed -n '1p' "$report_directory/sentinel.txt")" "보고서 디렉터리 내용이 변경되었습니다" || return 1

    assert_equal "0" "$(find "$case_root/commit-failure" "$case_root/directory-failure" -type f \( -name '.*.tmp.*' -o -name '.*.seed.*' -o -name '.*.prepare.*' -o -name '.*.rollback.*' \) -print | wc -l | tr -d ' ')" "출력 트랜잭션 임시 파일"
)

test_detection_preserves_backup_when_rollback_fails()
(
    local case_root="$TEST_TEMP_ROOT/detect-rollback-double-failure"
    local project_root="$case_root/project"
    local output_root="$case_root/output"
    local profile_path="$output_root/project-profile.conf"
    local report_path="$output_root/detection-report.md"
    local external_mv_path
    local before_profile_checksum
    local before_profile_mode
    local before_report_checksum
    local backup_path
    local rollback_argument=0
    local argument
    local final_argument
    local output
    local status

    load_detection_api || return 1
    create_unity_fixture "$project_root" "mvvm"
    mkdir -p "$output_root"
    write_valid_profile "$profile_path" "pending" "custom" "이중 실패 원본 프로필" ""
    printf '%s\n' '이중 실패 원본 보고서' > "$report_path"
    chmod 640 "$profile_path" || return 1
    before_profile_checksum=$(cksum < "$profile_path")
    before_profile_mode=$(get_file_mode "$profile_path") || return 1
    before_report_checksum=$(cksum "$report_path")

    external_mv_path=$(command -v mv)
    mv()
    {
        rollback_argument=0
        for argument in "$@"
        do
            final_argument=$argument
            case "$argument" in
                "$output_root"/.project-profile.conf.rollback.*)
                    rollback_argument=1
                    ;;
            esac
        done
        if [ "$final_argument" = "$report_path" ]; then
            return 1
        fi
        if [ "$rollback_argument" -eq 1 ] && [ "$final_argument" = "$profile_path" ]; then
            return 1
        fi
        "$external_mv_path" "$@"
    }

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "4" "$status" "롤백 이중 실패 종료 코드가 다릅니다" || return 1
    assert_equal "$before_report_checksum" "$(cksum "$report_path")" "롤백 이중 실패에서 기존 보고서가 변경되었습니다" || return 1
    assert_file_exists "$profile_path" "롤백 이중 실패에서 현재 프로필도 유실되었습니다" || return 1

    backup_path=$(find "$output_root" -maxdepth 1 -type f -name '.project-profile.conf.rollback.*' -print)
    assert_file_exists "$backup_path" "롤백 이중 실패에서 유일한 원본 백업이 유실되었습니다" || return 1
    assert_equal "$before_profile_checksum" "$(cksum < "$backup_path")" "보존된 롤백 백업이 원본과 다릅니다" || return 1
    assert_equal "$before_profile_mode" "$(get_file_mode "$backup_path")" "보존된 롤백 백업 권한이 원본과 다릅니다" || return 1
    assert_contains "$output" "수동 복구" "롤백 이중 실패 수동 복구 안내가 없습니다" || return 1
    assert_contains "$output" "$backup_path" "롤백 이중 실패 복구 경로가 없습니다" || return 1
    assert_equal "0" "$(find "$output_root" -type f \( -name '.*.tmp.*' -o -name '.*.seed.*' -o -name '.*.prepare.*' \) -print | wc -l | tr -d ' ')" "롤백 이중 실패 준비 임시 파일"
)

test_detection_cleans_transaction_files_on_signals()
{
    local case_root="$TEST_TEMP_ROOT/detect-signal-cleanup"
    local signal_case
    local signal_name
    local expected_status
    local project_root
    local output_root
    local profile_path
    local report_path
    local output
    local status

    for signal_case in HUP:129 INT:130 TERM:143
    do
        signal_name=${signal_case%%:*}
        expected_status=${signal_case#*:}
        project_root="$case_root/$signal_name/project"
        output_root="$case_root/$signal_name/output"
        profile_path="$output_root/project-profile.conf"
        report_path="$output_root/detection-report.md"

        mkdir -p "$output_root"
        create_neutral_unity_fixture "$project_root"
        write_valid_profile "$profile_path" "pending" "custom" "시그널 이전 프로필" ""
        printf '%s\n' '시그널 이전 보고서' > "$report_path"

        output=$(bash -c '
            . "$1"
            . "$2"
            signal_name=$3
            project_root=$4
            profile_path=$5
            report_path=$6
            schema_path=$7
            signatures_path=$8
            TMPDIR=$9
            external_mv_path=$(command -v mv)
            has_signalled=0
            trap - HUP INT TERM
            detect_install_signal_handlers
            mv()
            {
                local final_argument
                for final_argument in "$@"
                do
                    :
                done
                if [ "$final_argument" = "$report_path" ] && [ "$has_signalled" -eq 0 ]; then
                    has_signalled=1
                    kill -s "$signal_name" "$$"
                fi
                "$external_mv_path" "$@"
            }
            detect_project "$project_root" "$profile_path" "$report_path" "$schema_path" "$signatures_path"
        ' signal-probe "$PROFILE_SCRIPT" "$DETECT_SCRIPT" "$signal_name" "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" "$output_root" 2>&1)
        status=$?

        assert_equal "$expected_status" "$status" "$signal_name 시그널 종료 코드가 보존되지 않았습니다" || return 1
        assert_file_exists "$profile_path" "$signal_name 시그널 후 프로필이 유실되었습니다" || return 1
        assert_file_exists "$report_path" "$signal_name 시그널 후 보고서가 유실되었습니다" || return 1
        assert_equal "0" "$(find "$output_root" -type f \( -name '.*.tmp.*' -o -name '.*.seed.*' -o -name '.*.prepare.*' -o -name '.*.rollback.*' -o -name 'unity-harness-code-list.*' -o -name 'unity-harness-csharp-corpus.*' \) -print | wc -l | tr -d ' ')" "$signal_name 시그널 후 트랜잭션·코드 캐시 임시 파일"
    done
}

test_initializer_confirms_pending_profile()
{
    local case_root="$TEST_TEMP_ROOT/init-confirm"
    local project_root="$case_root/한글 프로젝트"
    local profile_path="$project_root/.agents/config/project-profile.conf"
    local output
    local status

    require_file "$INITIALIZER_SCRIPT" "initialize-harness.sh" || return 1
    load_profile_api || return 1
    create_unity_fixture "$project_root" "mvvm"

    output=$(bash "$INITIALIZER_SCRIPT" --project-root "$project_root" 2>&1)
    status=$?
    assert_equal "0" "$status" "초기화 감지 종료 코드가 다릅니다" || return 1
    assert_file_exists "$profile_path" "초기화 프로필이 없습니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "pending" "$(profile_get "confirmation_status")" "초기 프로필이 pending이 아닙니다" || return 1

    output=$(bash "$INITIALIZER_SCRIPT" --project-root "$project_root" --confirm 2>&1)
    status=$?
    assert_equal "0" "$status" "프로필 확정 종료 코드가 다릅니다" || return 1
    assert_contains "$output" "확정" "프로필 확정 안내가 없습니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "confirmed" "$(profile_get "confirmation_status")" "프로필 상태가 confirmed로 바뀌지 않았습니다" || return 1

    bash "$INITIALIZER_SCRIPT" --project-root >/dev/null 2>&1
    status=$?
    assert_equal "3" "$status" "누락된 --project-root 값 종료 코드가 다릅니다" || return 1
    bash "$INITIALIZER_SCRIPT" --unknown-option >/dev/null 2>&1
    status=$?
    assert_equal "3" "$status" "알 수 없는 인자 종료 코드가 다릅니다"
}

run_lint_scenario()
{
    local confirmation_status=$1
    local architecture=$2
    local expected_status=$3
    local expected_fragment=$4
    local forbidden_fragment=$5
    local case_name=$6
    local case_root="$TEST_TEMP_ROOT/$case_name"
    local project_root="$case_root/project"
    local profile_path="$case_root/project-profile.conf"
    local output
    local status

    load_lint_api || return 1
    mkdir -p "$case_root"
    create_lint_fixture "$project_root"
    write_valid_profile "$profile_path" "$confirmation_status" "$architecture" "LintFixture" ""

    output=$(lint_project "$project_root" "$profile_path" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "$expected_status" "$status" "린터 종료 코드가 다릅니다" || return 1
    if [ -n "$expected_fragment" ]; then
        assert_contains "$output" "$expected_fragment" "필수 린터 결과가 없습니다" || return 1
    fi
    if [ -n "$forbidden_fragment" ]; then
        assert_not_contains "$output" "$forbidden_fragment" "비활성 규칙이 실행되었습니다" || return 1
    fi
}

test_pending_profile_downgrades_profile_violation_to_warning()
{
    run_lint_scenario "pending" "mvvm" "0" "MVVM001|warning|" "MVVM001|error|" "lint-pending"
}

test_confirmed_profile_blocks_profile_violation()
{
    run_lint_scenario "confirmed" "mvvm" "1" "MVVM001|error|" "" "lint-confirmed"
}

test_custom_profile_skips_architecture_specific_rules()
{
    run_lint_scenario "confirmed" "custom" "0" "" "MVVM001|" "lint-custom"
}

test_lint_rejects_source_root_outside_assets_game()
{
    local case_root="$TEST_TEMP_ROOT/lint-source-outside-assets-game"
    local project_root="$case_root/project"
    local profile_path="$case_root/project-profile.conf"
    local output
    local status

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/Vendor"
    printf '%s\n' 'public sealed class VendorCode { }' > "$project_root/Assets/Vendor/VendorCode.cs"
    write_valid_profile "$profile_path" "confirmed" "layered_clean" "LintOutside" ""
    sed 's@^source_root=.*@source_root=Assets/Vendor@' "$profile_path" > "$case_root/outside-profile.conf"

    output=$(lint_project "$project_root" "$case_root/outside-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "1" "$status" "Assets/_Game 외부 source_root 종료 코드" || return 1
    assert_contains "$output" 'CONFIG001|error|Assets/Vendor|0|' "Assets/_Game 외부 source_root 진단이 없습니다"
}

test_lint_emits_all_rule_ids_and_routes_profiles()
{
    local case_root="$TEST_TEMP_ROOT/lint-all-rules"
    local project_root="$case_root/mvvm-project"
    local profile_path="$case_root/mvvm-profile.conf"
    local output
    local combined_output
    local status
    local expected_rule

    load_lint_api || return 1
    create_full_lint_fixture "$project_root"
    write_valid_profile "$profile_path" "confirmed" "mvvm" "AllRules" ""
    output=$(lint_project "$project_root" "$profile_path" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "1" "$status" "전체 규칙 MVVM 종료 코드" || return 1
    combined_output=$output

    project_root="$case_root/mvp-project"
    profile_path="$case_root/mvp-profile.conf"
    create_lint_fixture "$project_root"
    write_valid_profile "$profile_path" "confirmed" "mvp" "MvpRules" ""
    output=$(lint_project "$project_root" "$profile_path" "$SCHEMA_PATH" 2>&1)
    combined_output="$combined_output
$output"

    project_root="$case_root/mvc-project"
    profile_path="$case_root/mvc-profile.conf"
    mkdir -p "$project_root/Assets/_Game/Views"
    printf '%s\n' \
        'public sealed class ScoreView' \
        '{' \
        '    private ScoreModel m_model;' \
        '    private void Apply()' \
        '    {' \
        '        m_model.Score = 10;' \
        '    }' \
        '}' > "$project_root/Assets/_Game/Views/ScoreView.cs"
    write_valid_profile "$profile_path" "confirmed" "mvc" "MvcRules" ""
    output=$(lint_project "$project_root" "$profile_path" "$SCHEMA_PATH" 2>&1)
    combined_output="$combined_output
$output"

    project_root="$case_root/layered-project"
    profile_path="$case_root/layered-profile.conf"
    mkdir -p "$project_root/Assets/_Game/Domain"
    printf '%s\n' \
        'using UnityEngine;' \
        'namespace Sample.Domain' \
        '{' \
        '    public sealed class DomainRule { }' \
        '}' > "$project_root/Assets/_Game/Domain/DomainRule.cs"
    write_valid_profile "$profile_path" "confirmed" "layered_clean" "LayeredRules" ""
    output=$(lint_project "$project_root" "$profile_path" "$SCHEMA_PATH" 2>&1)
    combined_output="$combined_output
$output"

    project_root="$case_root/config-project"
    profile_path="$case_root/invalid-profile.conf"
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' 'public sealed class Neutral { }' > "$project_root/Assets/_Game/Neutral.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "InvalidProfile" ""
    printf '%s\n' 'unknown_key=value' >> "$profile_path"
    output=$(lint_project "$project_root" "$profile_path" "$SCHEMA_PATH" 2>&1)
    combined_output="$combined_output
$output"

    profile_path="$case_root/missing-root-profile.conf"
    write_valid_profile "$profile_path" "confirmed" "custom" "MissingRoot" ""
    sed 's@^source_root=.*@source_root=Assets/_Game/Missing@' "$profile_path" > "$case_root/missing-root.conf"
    output=$(lint_project "$project_root" "$case_root/missing-root.conf" "$SCHEMA_PATH" 2>&1)
    combined_output="$combined_output
$output"

    for expected_rule in \
        'CONFIG001|error|' \
        'PATH001|error|' \
        'SOLID001|error|' \
        'PERF001|warning|' \
        'PERF002|warning|' \
        'UNITYNULL001|warning|' \
        'MVVM001|error|' \
        'MVP001|error|' \
        'MVC001|warning|' \
        'LAYER001|error|' \
        'VCONTAINER001|warning|' \
        'UNITASK001|error|' \
        'DOTWEEN001|warning|' \
        'STYLE001|warning|' \
        'DOC001|warning|'
    do
        assert_contains "$combined_output" "$expected_rule" "필수 RULE_ID 또는 심각도 누락" || return 1
    done

    if ! printf '%s\n' "$combined_output" | awk -F'|' '
        NF != 5 || $1 == "" || ($2 != "error" && $2 != "warning") || $3 == "" || $4 !~ /^[0-9]+$/ || $5 == "" { exit 1 }
    '; then
        echo "린터 기계 출력 계약이 RULE_ID|severity|path|line|message 형식과 다릅니다." >&2
        return 1
    fi

    project_root="$case_root/pending-project"
    profile_path="$case_root/pending-profile.conf"
    create_full_lint_fixture "$project_root"
    write_valid_profile "$profile_path" "pending" "mvvm" "PendingCore" ""
    output=$(lint_project "$project_root" "$profile_path" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "1" "$status" "pending에서도 Core error는 차단해야 합니다" || return 1
    assert_contains "$output" 'SOLID001|error|' "pending Core error가 유지되지 않았습니다" || return 1
    assert_contains "$output" 'MVVM001|warning|' "pending 프로필 error가 warning으로 낮아지지 않았습니다" || return 1

    sed \
        -e 's/^architecture=.*/architecture=custom/' \
        -e 's/^dependency_injection=.*/dependency_injection=custom/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=none/' \
        "$profile_path" > "$case_root/skipped-profile.conf"
    output=$(lint_project "$project_root" "$case_root/skipped-profile.conf" "$SCHEMA_PATH" 2>&1)
    assert_not_contains "$output" 'MVVM001|' "custom 아키텍처 규칙이 실행되었습니다" || return 1
    assert_not_contains "$output" 'VCONTAINER001|' "custom DI 기술 규칙이 실행되었습니다" || return 1
    assert_not_contains "$output" 'UNITASK001|' "unknown 비동기 기술 규칙이 실행되었습니다" || return 1
    assert_not_contains "$output" 'DOTWEEN001|' "none 트윈 기술 규칙이 실행되었습니다"
}

test_lint_respects_source_exclusions_and_method_boundaries()
{
    local case_root="$TEST_TEMP_ROOT/lint-boundaries"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output

    load_lint_api || return 1
    mkdir -p \
        "$project_root/Assets/_Game" \
        "$project_root/Assets/_Game/Library" \
        "$project_root/Assets/Plugins" \
        "$project_root/Library" \
        "$project_root/Other"
    printf '%s\n' 'public sealed class InScope { public static InScope Instance { get; } }' > "$project_root/Assets/_Game/InScope.cs"
    printf '%s\n' 'public sealed class NestedLibrary { public static NestedLibrary Instance { get; } }' > "$project_root/Assets/_Game/Library/NestedLibrary.cs"
    printf '%s\n' 'public sealed class PluginCode { public static PluginCode Instance { get; } }' > "$project_root/Assets/Plugins/PluginCode.cs"
    printf '%s\n' 'public sealed class RootLibrary { public static RootLibrary Instance { get; } }' > "$project_root/Library/RootLibrary.cs"
    printf '%s\n' 'public sealed class Outside { public static Outside Instance { get; } }' > "$project_root/Other/Outside.cs"
    printf '%s\n' \
        'using System.Collections.Generic;' \
        'using System.Linq;' \
        'public sealed class MethodBoundaryProbe' \
        '{' \
        '    private List<int> m_values;' \
        '    private const string Text = "void Update() { new List<int>(); values.Where(x => true); DOTween.Sequence(); }";' \
        '    // void FixedUpdate() { new List<int>(); values.Where(x => true); DOTween.Sequence(); }' \
        '    private void Update()' \
        '    {' \
        '        int count = m_values.Count;' \
        '    }' \
        '    private void Helper()' \
        '    {' \
        '        var copy = new List<int>();' \
        '        var filtered = m_values.Where(value => value > 0);' \
        '        DG.Tweening.DOTween.Sequence();' \
        '    }' \
        '}' > "$project_root/Assets/_Game/MethodBoundaryProbe.cs"

    write_valid_profile "$profile_path" "confirmed" "custom" "Boundaries" ""
    sed \
        -e 's@^source_root=.*@source_root=Assets/_Game@' \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        "$profile_path" > "$case_root/boundary-profile.conf"

    output=$(lint_project "$project_root" "$case_root/boundary-profile.conf" "$SCHEMA_PATH" 2>&1)
    assert_contains "$output" 'Assets/_Game/InScope.cs' "source_root 내부 파일이 누락되었습니다" || return 1
    assert_contains "$output" 'Assets/_Game/Library/NestedLibrary.cs' "중첩 동명 기본 폴더를 잘못 제외했습니다" || return 1
    assert_not_contains "$output" 'Assets/Plugins/PluginCode.cs' "exclude_root 파일이 검사되었습니다" || return 1
    assert_not_contains "$output" 'Library/RootLibrary.cs' "정확한 기본 제외 루트가 검사되었습니다" || return 1
    assert_not_contains "$output" 'Other/Outside.cs' "source_root 외부 파일이 검사되었습니다" || return 1
    assert_not_contains "$output" 'PERF001|' "Update 계열 밖 LINQ 또는 문자열을 오탐했습니다" || return 1
    assert_not_contains "$output" 'PERF002|' "Update 계열 밖 new 또는 문자열을 오탐했습니다" || return 1
    assert_not_contains "$output" 'DOTWEEN001|' "Update 계열 밖 Tween 또는 문자열을 오탐했습니다"
}

test_lint_entrypoints_and_legacy_wrapper()
{
    local case_root="$TEST_TEMP_ROOT/lint-entrypoints"
    local project_root="$case_root/한글 프로젝트"
    local profile_path="$case_root/프로필 폴더/project-profile.conf"
    local output
    local first_line
    local notice_count
    local status

    require_file "$CHECK_HARNESS_SCRIPT" "check-harness.sh" || return 1
    require_file "$LEGACY_LINT_SCRIPT" "check-architecture.sh" || return 1
    create_full_lint_fixture "$project_root"
    mkdir -p "$case_root/프로필 폴더"
    write_valid_profile "$profile_path" "confirmed" "mvvm" "EntryPoint" ""

    output=$(bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --profile "$profile_path" --format machine 2>&1)
    status=$?
    assert_equal "1" "$status" "machine 진입점 종료 코드" || return 1
    assert_contains "$output" 'SOLID001|error|Assets/_Game/Core/RuleProbe.cs|' "machine 출력이 정규화되지 않았습니다" || return 1

    output=$(bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --profile "$profile_path" --format human 2>&1)
    status=$?
    assert_equal "1" "$status" "human 진입점 종료 코드" || return 1
    assert_contains "$output" 'SOLID001' "human 출력에 규칙 ID가 없습니다" || return 1
    assert_contains "$output" '오류' "human 출력에 심각도 설명이 없습니다" || return 1

    bash "$CHECK_HARNESS_SCRIPT" --project-root >/dev/null 2>&1
    status=$?
    assert_equal "3" "$status" "누락된 --project-root 값 종료 코드" || return 1
    bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --profile "$profile_path" --format json >/dev/null 2>&1
    status=$?
    assert_equal "3" "$status" "지원하지 않는 format 종료 코드" || return 1

    output=$(bash "$LEGACY_LINT_SCRIPT" --project-root "$project_root" --profile "$profile_path" --format machine 2>&1)
    status=$?
    assert_equal "1" "$status" "legacy wrapper 위임 종료 코드" || return 1
    first_line=$(printf '%s\n' "$output" | sed -n '1p')
    assert_equal '[check-architecture] 범용 검사기로 위임합니다: check-harness.sh' "$first_line" "legacy 안내 문구" || return 1
    notice_count=$(printf '%s\n' "$output" | grep -Fxc '[check-architecture] 범용 검사기로 위임합니다: check-harness.sh')
    assert_equal "1" "$notice_count" "legacy 안내 문구 출력 횟수"
}

test_pre_commit_is_git_independent_and_read_only()
{
    local case_root="$TEST_TEMP_ROOT/lint-pre-commit"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local branch_before
    local branch_after
    local staging_before
    local staging_after
    local status

    require_file "$PRE_COMMIT_SCRIPT" "pre-commit-checks.sh" || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' '/// <summary>중립 클래스</summary>' 'public sealed class Neutral { }' > "$project_root/Assets/_Game/Neutral.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "PreCommit" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=none/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=custom/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/pre-commit-profile.conf"

    (
        cd "$case_root" || exit 1
        bash "$PRE_COMMIT_SCRIPT" --project-root "$project_root" --profile "$case_root/pre-commit-profile.conf" --format machine >/dev/null 2>&1
    )
    status=$?
    assert_equal "0" "$status" "비Git 디렉터리 pre-commit 종료 코드" || return 1

    git -C "$project_root" init -q || return 1
    git -C "$project_root" add Assets/_Game/Neutral.cs || return 1
    branch_before=$(git -C "$project_root" symbolic-ref --short HEAD)
    staging_before=$(git -C "$project_root" diff --cached --name-status)
    bash "$PRE_COMMIT_SCRIPT" --project-root "$project_root" --profile "$case_root/pre-commit-profile.conf" --format machine >/dev/null 2>&1
    status=$?
    branch_after=$(git -C "$project_root" symbolic-ref --short HEAD)
    staging_after=$(git -C "$project_root" diff --cached --name-status)
    assert_equal "0" "$status" "Git 디렉터리 pre-commit 종료 코드" || return 1
    assert_equal "$branch_before" "$branch_after" "pre-commit이 현재 브랜치를 변경했습니다" || return 1
    assert_equal "$staging_before" "$staging_after" "pre-commit이 스테이징 상태를 변경했습니다"
}

test_lint_singleton_requires_exact_instance_name()
{
    local case_root="$TEST_TEMP_ROOT/lint-singleton-name"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output
    local solid_count

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' \
        'public sealed class FactoryProbe' \
        '{' \
        '    public static FactoryProbe CreateInstance() { return null; }' \
        '    public static FactoryProbe GetInstance() { return null; }' \
        '}' > "$project_root/Assets/_Game/FactoryProbe.cs"
    printf '%s\n' \
        'public sealed class InstanceFieldProbe' \
        '{' \
        '    public static InstanceFieldProbe Instance;' \
        '}' > "$project_root/Assets/_Game/InstanceFieldProbe.cs"
    printf '%s\n' \
        'public sealed class InstancePropertyProbe' \
        '{' \
        '    public static InstancePropertyProbe Instance' \
        '    {' \
        '        get;' \
        '        private set;' \
        '    }' \
        '}' > "$project_root/Assets/_Game/InstancePropertyProbe.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "SingletonName" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    solid_count=$(printf '%s\n' "$output" | grep -c '^SOLID001|')
    assert_equal "2" "$solid_count" "정확한 Instance 필드·프로퍼티 탐지 건수" || return 1
    assert_not_contains "$output" 'FactoryProbe.cs' "Factory method를 싱글톤으로 오탐했습니다" || return 1
    assert_contains "$output" 'InstanceFieldProbe.cs' "Instance 필드를 누락했습니다" || return 1
    assert_contains "$output" 'InstancePropertyProbe.cs' "Instance 프로퍼티를 누락했습니다"
}

test_lint_solid_and_unitask_respect_framework_idioms()
{
    local case_root="$TEST_TEMP_ROOT/lint-framework-idioms"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game/Domain" "$project_root/Assets/_Game/Tests/PlayMode" "$project_root/Assets/_Game/Scripts"
    printf '%s\n' \
        'public sealed class CachedComparer { public static readonly CachedComparer Instance = new CachedComparer(); }' \
        'public static class GlobalHolder { public static string MutableGlobal; }' \
        'public readonly struct OpKey { public static bool operator ==(OpKey l, OpKey r) => true; public static bool operator !=(OpKey l, OpKey r) => false; }' \
        > "$project_root/Assets/_Game/Domain/GlobalProbe.cs"
    printf '%s\n' \
        'using System.Collections;' \
        'public sealed class FlowTests' \
        '{' \
        '    public IEnumerator Wait() { yield return null; }' \
        '}' > "$project_root/Assets/_Game/Tests/PlayMode/FlowTests.cs"
    printf '%s\n' \
        'using System.Collections;' \
        'using NUnit.Framework;' \
        'public sealed class MarkerTests' \
        '{' \
        '    public IEnumerator Wait() { yield return null; }' \
        '}' > "$project_root/Assets/_Game/Scripts/MarkerTests.cs"
    printf '%s\n' \
        'using System.Collections;' \
        'public sealed class ProductionFlow' \
        '{' \
        '    public IEnumerator Wait() { yield return null; }' \
        '    public object Build()' \
        '    {' \
        '        return CreateHelper(' \
        '            new ProductionFlow(),' \
        '            new ProductionFlow());' \
        '    }' \
        '    private object CreateHelper(object a, object b) { return a; }' \
        '    public new string ToString() { return "flow"; }' \
        '    private void StoreIndexed(System.Collections.Hashtable map)' \
        '    {' \
        '        map[new ProductionFlow()] = 1;' \
        '    }' \
        '}' > "$project_root/Assets/_Game/Scripts/ProductionFlow.cs"

    write_valid_profile "$profile_path" "confirmed" "custom" "FrameworkIdioms" ""
    sed \
        -e 's/^async_backend=.*/async_backend=unitask/' \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=all_methods/' \
        "$profile_path" > "$case_root/idioms-profile.conf"

    output=$(lint_project "$project_root" "$case_root/idioms-profile.conf" "$SCHEMA_PATH" 2>&1)
    assert_contains "$output" 'SOLID001|warning|Assets/_Game/Domain/GlobalProbe.cs|1|' "readonly Instance가 warning으로 강등되지 않았습니다" || return 1
    assert_contains "$output" 'SOLID001|error|Assets/_Game/Domain/GlobalProbe.cs|2|' "가변 public static 전역이 error로 보고되지 않았습니다" || return 1
    assert_not_contains "$output" 'UNITASK001|error|Assets/_Game/Tests/PlayMode/FlowTests.cs' "Tests 경로가 UNITASK001에서 제외되지 않았습니다" || return 1
    assert_not_contains "$output" 'UNITASK001|error|Assets/_Game/Scripts/MarkerTests.cs' "NUnit 마커 테스트 파일이 UNITASK001에서 제외되지 않았습니다" || return 1
    assert_not_contains "$output" 'SOLID001|error|Assets/_Game/Domain/GlobalProbe.cs|3' "operator == 오버로드를 가변 전역으로 오탐했습니다" || return 1
    assert_contains "$output" 'UNITASK001|error|Assets/_Game/Scripts/ProductionFlow.cs' "생산 코드 Coroutine이 UNITASK001로 보고되지 않았습니다" || return 1
    assert_not_contains "$output" 'DOC001|warning|Assets/_Game/Tests/PlayMode/FlowTests.cs' "Tests 경로가 DOC001에서 제외되지 않았습니다" || return 1
    assert_not_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/MarkerTests.cs' "NUnit 마커 테스트 파일이 DOC001에서 제외되지 않았습니다" || return 1
    assert_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/ProductionFlow.cs|4|' "생산 코드 문서화 누락이 DOC001로 보고되지 않았습니다" || return 1
    assert_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/ProductionFlow.cs|11|' "private 메서드 문서화 누락이 DOC001로 보고되지 않았습니다" || return 1
    assert_not_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/ProductionFlow.cs|7' "return 호출 문장을 메서드 선언으로 오탐했습니다" || return 1
    assert_not_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/ProductionFlow.cs|8' "new 생성자 호출 인자를 메서드 선언으로 오탐했습니다" || return 1
    assert_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/ProductionFlow.cs|12|' "메서드 하이딩 선언이 DOC001 검사에서 누락되었습니다" || return 1
    assert_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/ProductionFlow.cs|13|' "인덱서 사용 메서드 선언이 DOC001 검사에서 누락되었습니다" || return 1
    assert_not_contains "$output" 'DOC001|warning|Assets/_Game/Scripts/ProductionFlow.cs|15' "인덱서 new 키 할당문을 메서드 선언으로 오탐했습니다"
}

test_lint_supports_update_modifiers_expression_bodies_and_new_forms()
{
    local case_root="$TEST_TEMP_ROOT/lint-update-forms"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output
    local status

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' \
        'using System.Collections.Generic;' \
        'using System.Linq;' \
        'public sealed class AsyncUpdateProbe' \
        '{' \
        '    private List<int> m_values;' \
        '    private async void Update()' \
        '    {' \
        '        var values = m_values.Distinct();' \
        '    }' \
        '}' > "$project_root/Assets/_Game/AsyncUpdateProbe.cs"
    printf '%s\n' \
        'public class VirtualLateUpdateProbe' \
        '{' \
        '    protected virtual void LateUpdate()' \
        '    {' \
        '        object value = new();' \
        '    }' \
        '}' > "$project_root/Assets/_Game/VirtualLateUpdateProbe.cs"
    printf '%s\n' \
        'using System.Collections.Generic;' \
        'using System.Linq;' \
        'public sealed class FixedUpdateProbe' \
        '{' \
        '    private List<int> m_values;' \
        '    private void FixedUpdate()' \
        '    {' \
        '        object value = new();' \
        '        var values = m_values.Distinct();' \
        '    }' \
        '}' > "$project_root/Assets/_Game/FixedUpdateProbe.cs"
    printf '%s\n' \
        'public sealed class ExpressionUpdateProbe' \
        '{' \
        '    private void Update() => DG.Tweening.DOTween.Sequence();' \
        '}' > "$project_root/Assets/_Game/ExpressionUpdateProbe.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "UpdateForms" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "Update 복합 선언 경고 종료 코드" || return 1
    assert_equal "2" "$(printf '%s\n' "$output" | grep -c '^PERF001|warning|')" "Distinct 탐지 건수" || return 1
    assert_equal "2" "$(printf '%s\n' "$output" | grep -c '^PERF002|warning|')" "target-typed new 탐지 건수" || return 1
    assert_equal "1" "$(printf '%s\n' "$output" | grep -c '^DOTWEEN001|warning|')" "expression-bodied Update Tween 탐지 건수" || return 1
    assert_not_contains "$output" 'STYLE001|' "Update 메서드 선언을 private 필드로 오탐했습니다"
}

test_lint_machine_output_percent_escapes_fields()
{
    local case_root="$TEST_TEMP_ROOT/lint-machine-escape"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local missing_profile='/tmp/누락|프로필.conf'
    local carriage_return
    local direct_message
    local output
    local status

    load_lint_api || return 1
    carriage_return=$(printf '\r')
    direct_message="메시지%|앞${carriage_return}
뒤"
    lint_reset
    output=$(lint_emit 'CONFIG001' 'warning' '경로%|값.cs' '7' "$direct_message")
    assert_equal '경로%25%7C값.cs' "$(printf '%s\n' "$output" | awk -F'|' '{ print $3 }')" "path percent escape" || return 1
    assert_equal '메시지%25%7C앞%0D%0A뒤' "$(printf '%s\n' "$output" | awk -F'|' '{ print $5 }')" "message percent escape" || return 1
    assert_equal "5" "$(printf '%s\n' "$output" | awk -F'|' '{ print NF }')" "직접 lint_emit 필드 수" || return 1

    require_file "$CHECK_HARNESS_SCRIPT" "check-harness.sh" || return 1
    mkdir -p "$project_root"
    output=$(bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --profile "$missing_profile" --format machine 2>&1)
    status=$?
    assert_equal "1" "$status" "구분자 포함 누락 프로필 machine 종료 코드" || return 1
    assert_contains "$output" '/tmp/누락%7C프로필.conf' "machine path의 pipe가 escape되지 않았습니다" || return 1
    assert_equal "5" "$(printf '%s\n' "$output" | awk -F'|' '{ print NF }')" "machine 누락 프로필 필드 수" || return 1

    output=$(bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --profile "$missing_profile" --format human 2>&1)
    status=$?
    assert_equal "1" "$status" "구분자 포함 누락 프로필 human 종료 코드" || return 1
    assert_contains "$output" "$missing_profile" "human 출력이 escape된 path를 안전하게 역표시하지 않았습니다" || return 1
    assert_not_contains "$output" '%7C' "human 출력에 machine escape가 남았습니다" || return 1

    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' 'public sealed class EscapedPathProbe { public static EscapedPathProbe Instance; }' > "$project_root/Assets/_Game/Probe%|Value.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "EscapedPath" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"
    output=$(bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --profile "$case_root/lint-profile.conf" --format machine 2>&1)
    status=$?
    assert_equal "1" "$status" "구분자 포함 C# path machine 종료 코드" || return 1
    assert_contains "$output" 'Assets/_Game/Probe%25%7CValue.cs' "C# path의 percent·pipe escape가 올바르지 않습니다" || return 1
    assert_equal "5" "$(printf '%s\n' "$output" | awk -F'|' '{ print NF }')" "C# path machine 필드 수"
}

test_lint_style_excludes_properties_but_keeps_fields()
{
    local case_root="$TEST_TEMP_ROOT/lint-style-property"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' \
        'public sealed class StyleProbe' \
        '{' \
        '    private int Count { get; set; }' \
        '    private int m_validCount;' \
        '    private int invalidCount;' \
        '}' > "$project_root/Assets/_Game/StyleProbe.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "StyleProperty" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    assert_equal "1" "$(printf '%s\n' "$output" | grep -c '^STYLE001|warning|')" "private 필드 STYLE001 건수" || return 1
    assert_contains "$output" 'StyleProbe.cs|5|' "private 필드 위반을 누락했습니다" || return 1
    assert_not_contains "$output" 'StyleProbe.cs|3|' "private 프로퍼티를 필드로 오탐했습니다"
}

test_lint_fails_closed_on_file_and_tool_errors()
(
    local case_root="$TEST_TEMP_ROOT/lint-fail-closed"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local source_path="$project_root/Assets/_Game/Unreadable.cs"
    local output
    local status

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' 'public sealed class Unreadable { }' > "$source_path"
    write_valid_profile "$profile_path" "confirmed" "custom" "FailClosed" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    chmod 000 "$source_path" || return 1
    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    chmod 600 "$source_path" || return 1
    assert_equal "4" "$status" "읽을 수 없는 C# 파일 종료 코드" || return 1
    assert_contains "$output" 'PATH001|error|Assets/_Game/Unreadable.cs|0|' "읽을 수 없는 C# 파일 정규화 진단" || return 1
    assert_not_contains "$output" 'awk:' "AWK 원시 stderr가 누출되었습니다" || return 1
    if ! printf '%s\n' "$output" | awk -F'|' 'NF != 5 { exit 1 }'; then
        echo "읽을 수 없는 C# 진단이 machine 5필드가 아닙니다." >&2
        return 1
    fi

    find()
    {
        printf '%s\n' 'raw find failure' >&2
        return 7
    }
    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    unset -f find
    assert_equal "4" "$status" "find 실패 종료 코드" || return 1
    assert_contains "$output" 'PATH001|error|' "find 실패 정규화 진단" || return 1
    assert_not_contains "$output" 'raw find failure' "find 원시 stderr가 누출되었습니다" || return 1

    awk()
    {
        printf '%s\n' 'raw awk failure' >&2
        return 9
    }
    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    unset -f awk
    assert_equal "4" "$status" "awk 실패 종료 코드" || return 1
    assert_contains "$output" 'CONFIG001|error|' "awk 실패 정규화 진단" || return 1
    assert_not_contains "$output" 'raw awk failure' "awk 원시 stderr가 누출되었습니다"
)

test_lint_normalizes_and_confines_exclude_roots()
{
    local case_root="$TEST_TEMP_ROOT/lint-exclude-normalization"
    local project_root="$case_root/project"
    local base_profile="$case_root/base-profile.conf"
    local output
    local status
    local invalid_profile

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game/Generated" "$project_root/Assets/_Game/Included" "$case_root/outside"
    printf '%s\n' 'public sealed class GeneratedBad { public static GeneratedBad Instance; }' > "$project_root/Assets/_Game/Generated/GeneratedBad.cs"
    printf '%s\n' 'public sealed class IncludedBad { public static IncludedBad Instance; }' > "$project_root/Assets/_Game/Included/IncludedBad.cs"
    write_valid_profile "$case_root/profile.conf" "confirmed" "custom" "ExcludeNormalization" ""
    sed \
        -e 's@^source_root=.*@source_root=Assets/_Game@' \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$case_root/profile.conf" > "$base_profile"

    cp "$base_profile" "$case_root/relative-profile.conf" || return 1
    printf '%s\n' 'exclude_root=Assets/_Game/../_Game/Generated' >> "$case_root/relative-profile.conf"
    output=$(lint_project "$project_root" "$case_root/relative-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "1" "$status" "정규화 상대 exclude_root 종료 코드" || return 1
    assert_contains "$output" 'Assets/_Game/Included/IncludedBad.cs' "포함 대상 파일이 누락되었습니다" || return 1
    assert_not_contains "$output" 'Assets/_Game/Generated/GeneratedBad.cs' "정규화된 exclude_root가 적용되지 않았습니다" || return 1

    cp "$base_profile" "$case_root/absolute-profile.conf" || return 1
    printf 'exclude_root=%s\n' "$project_root/Assets/_Game/Generated" >> "$case_root/absolute-profile.conf"
    output=$(lint_project "$project_root" "$case_root/absolute-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "1" "$status" "프로젝트 내부 절대 exclude_root 종료 코드" || return 1
    assert_not_contains "$output" 'CONFIG001|' "프로젝트 내부 절대 exclude_root를 경계 외부로 오판했습니다" || return 1
    assert_contains "$output" 'Assets/_Game/Included/IncludedBad.cs' "절대 exclude_root 적용 후 포함 대상 파일이 스캔되지 않았습니다" || return 1
    assert_not_contains "$output" 'Assets/_Game/Generated/GeneratedBad.cs' "프로젝트 내부 절대 exclude_root가 적용되지 않았습니다" || return 1

    for invalid_profile in traversal absolute symlink
    do
        cp "$base_profile" "$case_root/$invalid_profile-profile.conf" || return 1
        case "$invalid_profile" in
            traversal)
                printf '%s\n' 'exclude_root=../Outside' >> "$case_root/$invalid_profile-profile.conf"
                ;;
            absolute)
                printf '%s\n' 'exclude_root=/tmp' >> "$case_root/$invalid_profile-profile.conf"
                ;;
            symlink)
                ln -s "$case_root/outside" "$project_root/Assets/LinkedOutside" || return 1
                printf '%s\n' 'exclude_root=Assets/LinkedOutside' >> "$case_root/$invalid_profile-profile.conf"
                ;;
        esac
        output=$(lint_project "$project_root" "$case_root/$invalid_profile-profile.conf" "$SCHEMA_PATH" 2>&1)
        status=$?
        assert_equal "1" "$status" "$invalid_profile exclude_root 차단 종료 코드" || return 1
        case "$output" in
            *'CONFIG001|error|'*|*'PATH001|error|'*)
                ;;
            *)
                echo "$invalid_profile exclude_root의 정규화 오류 진단이 없습니다." >&2
                return 1
                ;;
        esac
        assert_not_contains "$output" 'SOLID001|' "$invalid_profile exclude_root 오류 후 소스 검사가 실행되었습니다" || return 1
    done
}

test_lint_physicalizes_absolute_exclude_roots()
{
    local case_root="$TEST_TEMP_ROOT/lint-physical-absolute-exclude"
    local physical_root="$case_root/physical-project"
    local linked_root="$case_root/linked-project"
    local profile_path="$case_root/profile.conf"
    local output
    local status
    local physical_case_root
    local physical_project_root
    local var_alias_root

    load_lint_api || return 1
    mkdir -p "$physical_root/Assets/_Game/Generated" "$physical_root/Assets/_Game/Included"
    printf '%s\n' 'public sealed class GeneratedBad { public static GeneratedBad Instance; }' > "$physical_root/Assets/_Game/Generated/GeneratedBad.cs"
    printf '%s\n' 'public sealed class IncludedWarning { private int invalidField; }' > "$physical_root/Assets/_Game/Included/IncludedWarning.cs"
    ln -s "$physical_root" "$linked_root" || return 1
    write_valid_profile "$profile_path" "confirmed" "custom" "PhysicalAbsoluteExclude" ""
    sed \
        -e 's@^source_root=.*@source_root=Assets/_Game@' \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/linked-profile.conf"
    printf 'exclude_root=%s\n' "$linked_root/Assets/_Game/./Generated/../Generated" >> "$case_root/linked-profile.conf"

    output=$(lint_project "$linked_root" "$case_root/linked-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "심볼릭 프로젝트 루트의 절대 exclude_root 종료 코드" || return 1
    assert_not_contains "$output" 'CONFIG001|' "논리 루트 절대 exclude_root를 경계 외부로 오판했습니다" || return 1
    assert_contains "$output" 'STYLE001|warning|Assets/_Game/Included/IncludedWarning.cs' "포함 대상 소스가 스캔되지 않았습니다" || return 1
    assert_not_contains "$output" 'SOLID001|' "절대 exclude_root 내부 싱글톤이 검사되었습니다" || return 1

    physical_case_root=$(cd -P "$case_root" 2>/dev/null && pwd -P)
    physical_project_root=$(cd -P "$physical_root" 2>/dev/null && pwd -P)
    case "$physical_case_root" in
        /private/var/*)
            var_alias_root="/var/${physical_project_root#/private/var/}"
            cp "$case_root/linked-profile.conf" "$case_root/var-alias-profile.conf" || return 1
            sed "s@^exclude_root=.*@exclude_root=$var_alias_root/Assets/_Game/Generated@" "$case_root/var-alias-profile.conf" > "$case_root/var-alias-profile.tmp" || return 1
            mv "$case_root/var-alias-profile.tmp" "$case_root/var-alias-profile.conf" || return 1
            output=$(lint_project "$physical_root" "$case_root/var-alias-profile.conf" "$SCHEMA_PATH" 2>&1)
            status=$?
            assert_equal "0" "$status" "macOS /var 별칭 exclude_root 종료 코드" || return 1
            assert_not_contains "$output" 'CONFIG001|' "macOS /var 별칭을 경계 외부로 오판했습니다" || return 1
            assert_contains "$output" 'STYLE001|warning|Assets/_Game/Included/IncludedWarning.cs' "macOS /var 별칭 적용 후 포함 소스가 누락되었습니다" || return 1
            assert_not_contains "$output" 'SOLID001|' "macOS /var 별칭 exclude_root가 적용되지 않았습니다" || return 1
            ;;
    esac
}

test_lint_preserves_interpolation_expressions_in_update()
{
    local case_root="$TEST_TEMP_ROOT/lint-interpolation-expression"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output
    local status

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' \
        'public sealed class InterpolationProbe' \
        '{' \
        '    private void Update()' \
        '    {' \
        '        var allocation = $"{new object()}";' \
        '        var plain = "new object()";' \
        '        var interpolatedBody = $"new object()";' \
        '        // $"{new object()}"' \
        '    }' \
        '}' > "$project_root/Assets/_Game/InterpolationProbe.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "InterpolationExpression" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "보간식 Update 경고 종료 코드" || return 1
    assert_equal "1" "$(printf '%s\n' "$output" | grep -c '^PERF002|warning|')" "보간식 내부 new 탐지 건수" || return 1
    assert_contains "$output" 'InterpolationProbe.cs|5|' "보간식 내부 표현식의 new를 누락했습니다" || return 1
    assert_not_contains "$output" 'InterpolationProbe.cs|6|' "일반 문자열 본문을 코드로 오탐했습니다" || return 1
    assert_not_contains "$output" 'InterpolationProbe.cs|7|' "보간 문자열 본문을 코드로 오탐했습니다"
}

test_lint_all_methods_recognizes_implicit_and_generic_methods()
{
    local case_root="$TEST_TEMP_ROOT/lint-all-methods"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output
    local status

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' \
        'public sealed class DocumentationProbe' \
        '{' \
        '    void Awake() { }' \
        '    private T Convert<T>(T value) { return value; }' \
        '}' > "$project_root/Assets/_Game/DocumentationProbe.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "AllMethods" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "all_methods 문서화 경고 종료 코드" || return 1
    assert_equal "2" "$(printf '%s\n' "$output" | grep -c '^DOC001|warning|')" "암시적 void와 제네릭 메서드 DOC001 건수" || return 1
    assert_contains "$output" 'DocumentationProbe.cs|3|' "void Awake() 문서화 위반을 누락했습니다" || return 1
    assert_contains "$output" 'DocumentationProbe.cs|4|' "Convert<T> 문서화 위반을 누락했습니다"
}

test_lint_detects_multiline_register_instance_for_serialized_view()
{
    local case_root="$TEST_TEMP_ROOT/lint-multiline-register-instance"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local output
    local status

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    printf '%s\n' \
        'using UnityEngine;' \
        'public sealed class InventoryLifetimeScope' \
        '{' \
        '    [SerializeField]' \
        '    private InventoryView m_inventoryView;' \
        '    protected void Configure()' \
        '    {' \
        '        builder.RegisterInstance(' \
        '            m_inventoryView);' \
        '    }' \
        '}' > "$project_root/Assets/_Game/InventoryLifetimeScope.cs"
    write_valid_profile "$profile_path" "confirmed" "custom" "MultilineRegisterInstance" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=vcontainer/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "여러 줄 RegisterInstance 경고 종료 코드" || return 1
    assert_equal "1" "$(printf '%s\n' "$output" | grep -c '^VCONTAINER001|warning|')" "직렬화 View 여러 줄 RegisterInstance 탐지 건수" || return 1
    assert_contains "$output" 'InventoryLifetimeScope.cs|8|' "RegisterInstance 호출 시작 줄을 누락했습니다"
}

test_lint_sanitized_lines_strip_comments_and_strings()
{
    local project_root="$TEST_TEMP_ROOT/lint-sanitized-lines"
    local output

    load_lint_api || return 1
    mkdir -p "$project_root"
    printf '%s\n' \
        '// PlayerPrefs in a line comment' \
        '/* Firebase' \
        '   block comment */' \
        'var label = "PlayFab"; var path = @"IAuthRepository ""x""";' \
        'var value = PlayerPrefs.GetString(key);' > "$project_root/Sample.cs"
    _LINT_PROJECT_ROOT=$project_root
    output=$(lint_sanitized_lines "$project_root/Sample.cs") || return 1
    if printf '%s\n' "$output" | grep -Eq 'comment|Firebase|PlayFab|IAuthRepository'; then
        echo "sanitize 결과에 주석·문자열 내용이 남았습니다: $output" >&2
        return 1
    fi
    assert_contains "$output" '4|var label =' "문자열을 제거한 코드 줄 번호가 다릅니다" || return 1
    assert_contains "$output" '5|var value = PlayerPrefs.GetString(key);' "실제 코드 줄을 보존하지 않았습니다"
}

test_lint_scans_1000_files_with_one_awk_invocation()
(
    local case_root="$TEST_TEMP_ROOT/lint-1000-file-performance"
    local project_root="$case_root/project"
    local profile_path="$case_root/profile.conf"
    local counter_path="$case_root/awk-invocations"
    local real_awk
    local output
    local status
    local index
    local started_at
    local finished_at
    local elapsed_seconds
    local invocation_count

    load_lint_api || return 1
    mkdir -p "$project_root/Assets/_Game"
    index=1
    while [ "$index" -le 1000 ]; do
        printf 'public sealed class Probe%s { }\n' "$index" > "$project_root/Assets/_Game/Probe$index.cs"
        index=$((index + 1))
    done
    write_valid_profile "$profile_path" "confirmed" "custom" "LintStreaming" ""
    sed \
        -e 's/^dependency_injection=.*/dependency_injection=unknown/' \
        -e 's/^async_backend=.*/async_backend=unknown/' \
        -e 's/^tween_backend=.*/tween_backend=unknown/' \
        -e 's/^xml_documentation_policy=.*/xml_documentation_policy=disabled/' \
        "$profile_path" > "$case_root/lint-profile.conf"

    real_awk=$(command -v awk) || return 1
    awk()
    {
        printf '1' >> "$counter_path"
        command "$real_awk" "$@"
    }

    started_at=$(date +%s)
    output=$(lint_project "$project_root" "$case_root/lint-profile.conf" "$SCHEMA_PATH" 2>&1)
    status=$?
    finished_at=$(date +%s)
    unset -f awk

    elapsed_seconds=$((finished_at - started_at))
    invocation_count=$(wc -c < "$counter_path" | tr -d '[:space:]')
    assert_equal "0" "$status" "1000파일 린트 종료 코드" || return 1
    assert_equal "1" "$invocation_count" "1000파일 단일 AWK 스트리밍 호출 횟수" || return 1
    assert_equal "" "$output" "정상 1000파일에서 린트 진단이 발생했습니다" || return 1
    if [ "$elapsed_seconds" -gt 20 ]; then
        printf '%s\n' "[diag] 1000파일 린트가 20초 예산을 초과했습니다: ${elapsed_seconds}초" >&2
        return 1
    fi
)

test_korean_and_space_path_is_supported()
{
    local case_root="$TEST_TEMP_ROOT/한글 및 공백 경로"
    local project_root="$case_root/한글 프로젝트"
    local profile_path="$case_root/출력 폴더/project-profile.conf"
    local report_path="$case_root/출력 폴더/detection-report.md"
    local output
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/출력 폴더"
    create_unity_fixture "$project_root" "mvvm"

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "한글·공백 경로 감지 종료 코드가 다릅니다" || return 1
    assert_file_exists "$profile_path" "한글·공백 경로의 프로필이 없습니다" || return 1
    assert_file_exists "$report_path" "한글·공백 경로의 보고서가 없습니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "한글 프로젝트" "$(profile_get "project_name")" "한글 프로젝트명이 보존되지 않았습니다"
}

test_symlink_project_root_matches_physical_root()
{
    local case_root="$TEST_TEMP_ROOT/detect-symlink-root"
    local project_root="$case_root/physical-project"
    local linked_root="$case_root/linked-project"
    local physical_profile="$case_root/physical-output/project-profile.conf"
    local physical_report="$case_root/physical-output/detection-report.md"
    local linked_profile="$case_root/linked-output/project-profile.conf"
    local linked_report="$case_root/linked-output/detection-report.md"
    local status

    load_detection_api || return 1
    mkdir -p "$case_root/physical-output" "$case_root/linked-output"
    create_unity_fixture "$project_root" "mvvm"
    ln -s "$project_root" "$linked_root" || return 1

    detect_project "$project_root" "$physical_profile" "$physical_report" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "물리 프로젝트 루트 감지 종료 코드가 다릅니다" || return 1
    detect_project "$linked_root" "$linked_profile" "$linked_report" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "심볼릭 프로젝트 루트 감지 종료 코드가 다릅니다" || return 1

    if ! cmp -s "$physical_profile" "$linked_profile"; then
        echo "물리 루트와 심볼릭 루트의 프로필 결과가 다릅니다." >&2
        return 1
    fi
    if ! cmp -s "$physical_report" "$linked_report"; then
        echo "물리 루트와 심볼릭 루트의 보고서 결과가 다릅니다." >&2
        return 1
    fi
}

test_detection_does_not_modify_project_files()
{
    local case_root="$TEST_TEMP_ROOT/detect-readonly"
    local project_root="$case_root/project"
    local profile_path="$project_root/.agents/config/project-profile.conf"
    local report_path="$project_root/.agents/reports/detection-report.md"
    local before_snapshot="$case_root/before.cksum"
    local after_snapshot="$case_root/after.cksum"
    local output
    local status

    load_detection_api || return 1
    create_unity_fixture "$project_root" "mvvm"
    mkdir -p "$project_root/.agents/config" "$project_root/.agents/reports" "$project_root/.agents-backup"
    printf '%s\n' '백업 파일도 읽기 전용으로 보존합니다.' > "$project_root/.agents-backup/README.md"
    snapshot_project_files "$project_root" "$before_snapshot" || return 1
    assert_contains "$(sed -n '1,240p' "$before_snapshot")" "./.agents-backup/README.md" "readonly 스냅샷에서 .agents-backup이 누락되었습니다" || return 1

    output=$(detect_project "$project_root" "$profile_path" "$report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" 2>&1)
    status=$?
    assert_equal "0" "$status" "읽기 전용 감지 종료 코드가 다릅니다" || return 1
    snapshot_project_files "$project_root" "$after_snapshot" || return 1
    if ! cmp -s "$before_snapshot" "$after_snapshot"; then
        echo "감지 과정에서 .agents 외부 프로젝트 파일이 변경되었습니다." >&2
        return 1
    fi

    assert_file_exists "$profile_path" "읽기 전용 감지 프로필이 없습니다" || return 1
    assert_file_exists "$report_path" "읽기 전용 감지 보고서가 없습니다"
}

test_end_to_end_profile_state_transition_is_read_only()
{
    local case_root="$TEST_TEMP_ROOT/end-to-end-state"
    local project_root="$case_root/한글 및 공백 프로젝트"
    local profile_path="$project_root/.agents/config/project-profile.conf"
    local candidate_path="$project_root/.agents/config/project-profile.candidate.conf"
    local before_snapshot="$case_root/before.cksum"
    local after_snapshot="$case_root/after.cksum"
    local before_checksum
    local output
    local status

    require_file "$INITIALIZER_SCRIPT" "initialize-harness.sh" || return 1
    require_file "$CHECK_HARNESS_SCRIPT" "check-harness.sh" || return 1
    load_profile_api || return 1
    create_unity_fixture "$project_root" "mvvm"
    printf '%s\n' \
        'using Sample.Models;' \
        'public sealed class InventoryView' \
        '{' \
        '    private InventoryModel m_model;' \
        '}' > "$project_root/Assets/_Game/Scripts/Views/InventoryView.cs"
    snapshot_project_files "$project_root" "$before_snapshot" || return 1

    bash "$INITIALIZER_SCRIPT" --project-root "$project_root" >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "종단 감지 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "pending" "$(profile_get "confirmation_status")" "종단 최초 상태가 pending이 아닙니다" || return 1

    output=$(bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --format machine 2>&1)
    status=$?
    assert_equal "0" "$status" "pending 프로필 위반이 차단되었습니다" || return 1
    assert_contains "$output" 'MVVM001|warning|' "pending 프로필 위반 경고가 없습니다" || return 1

    bash "$INITIALIZER_SCRIPT" --project-root "$project_root" --confirm >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "종단 프로필 확정 종료 코드가 다릅니다" || return 1
    load_and_validate_profile "$profile_path" || return 1
    assert_equal "confirmed" "$(profile_get "confirmation_status")" "종단 프로필이 confirmed가 아닙니다" || return 1

    output=$(bash "$CHECK_HARNESS_SCRIPT" --project-root "$project_root" --format machine 2>&1)
    status=$?
    assert_equal "1" "$status" "confirmed 프로필 위반이 차단되지 않았습니다" || return 1
    assert_contains "$output" 'MVVM001|error|' "confirmed 프로필 위반 오류가 없습니다" || return 1

    before_checksum=$(cksum "$profile_path")
    bash "$INITIALIZER_SCRIPT" --project-root "$project_root" --redetect >/dev/null 2>&1
    status=$?
    assert_equal "0" "$status" "종단 재감지 종료 코드가 다릅니다" || return 1
    assert_equal "$before_checksum" "$(cksum "$profile_path")" "재감지가 confirmed 프로필을 변경했습니다" || return 1
    assert_file_exists "$candidate_path" "종단 재감지 후보가 생성되지 않았습니다" || return 1
    load_and_validate_profile "$candidate_path" || return 1
    assert_equal "pending" "$(profile_get "confirmation_status")" "재감지 후보가 pending이 아닙니다" || return 1

    snapshot_project_files "$project_root" "$after_snapshot" || return 1
    if ! cmp -s "$before_snapshot" "$after_snapshot"; then
        echo "종단 상태 전이 중 .agents 외부 프로젝트 파일이 변경되었습니다." >&2
        return 1
    fi
}

test_snapshot_project_files_fails_closed_on_tool_errors()
{
    local case_root="$TEST_TEMP_ROOT/snapshot-fail-closed"
    local project_root="$case_root/project"
    local tool_root="$case_root/tools"
    local output_path="$case_root/snapshot.txt"
    local status

    mkdir -p "$project_root/Assets" "$tool_root"
    printf '%s\n' 'snapshot' > "$project_root/Assets/data.txt"

    printf '%s\n' '#!/bin/sh' 'exit 7' > "$tool_root/find"
    chmod +x "$tool_root/find" || return 1
    PATH="$tool_root:$PATH" snapshot_project_files "$project_root" "$output_path" >/dev/null 2>&1
    status=$?
    if [ "$status" -eq 0 ]; then
        echo "파일 목록 생성 실패가 스냅샷 성공으로 숨겨졌습니다." >&2
        return 1
    fi

    rm "$tool_root/find"
    printf '%s\n' '#!/bin/sh' 'exit 8' > "$tool_root/cksum"
    chmod +x "$tool_root/cksum" || return 1
    PATH="$tool_root:$PATH" snapshot_project_files "$project_root" "$output_path" >/dev/null 2>&1
    status=$?
    if [ "$status" -eq 0 ]; then
        echo "체크섬 실패가 스냅샷 성공으로 숨겨졌습니다." >&2
        return 1
    fi
}

assert_powershell_utf8_bom()
{
    local file_path=$1
    local actual_bytes

    actual_bytes=$(od -An -t x1 -N 3 "$file_path" 2>/dev/null | tr -d ' \n')
    assert_equal "efbbbf" "$actual_bytes" "PowerShell 파일에 UTF-8 BOM이 없습니다: $file_path"
}

assert_powershell_delimiters()
{
    local file_path=$1

    awk '
        BEGIN {
            braces = 0
            parentheses = 0
            brackets = 0
            in_block_comment = 0
            in_single = 0
            in_double = 0
            in_here = ""
        }
        {
            text = $0
            # Here-string bodies are literal text up to a line starting with the closing quote and @.
            if (in_here != "")
            {
                if (substr(text, 1, 2) != in_here "@")
                {
                    next
                }
                in_here = ""
                text = substr(text, 3)
            }
            for (index_value = 1; index_value <= length(text); index_value++)
            {
                character = substr(text, index_value, 1)
                next_character = substr(text, index_value + 1, 1)
                if (character == "@" && (next_character == "\047" || next_character == "\"") &&
                    !in_block_comment && !in_single && !in_double &&
                    substr(text, index_value + 2) ~ /^[ \t]*$/)
                {
                    in_here = next_character
                    break
                }
                if (in_block_comment)
                {
                    if (character == "#" && next_character == ">")
                    {
                        in_block_comment = 0
                        index_value++
                    }
                    continue
                }
                if (in_single)
                {
                    if (character == "\047" && next_character == "\047")
                    {
                        index_value++
                    }
                    else if (character == "\047")
                    {
                        in_single = 0
                    }
                    continue
                }
                if (in_double)
                {
                    if (character == "`")
                    {
                        index_value++
                    }
                    else if (character == "\"")
                    {
                        in_double = 0
                    }
                    continue
                }
                if (character == "<" && next_character == "#")
                {
                    in_block_comment = 1
                    index_value++
                    continue
                }
                if (character == "#")
                {
                    break
                }
                if (character == "\047")
                {
                    in_single = 1
                    continue
                }
                if (character == "\"")
                {
                    in_double = 1
                    continue
                }
                if (character == "{") braces++
                if (character == "}") braces--
                if (character == "(") parentheses++
                if (character == ")") parentheses--
                if (character == "[") brackets++
                if (character == "]") brackets--
                if (braces < 0 || parentheses < 0 || brackets < 0)
                {
                    exit 1
                }
            }
        }
        END {
            if (in_here != "" || in_block_comment || in_single || in_double || braces != 0 || parentheses != 0 || brackets != 0)
            {
                exit 1
            }
        }
    ' "$file_path" || {
        echo "PowerShell 구분자 휴리스틱 검사에 실패했습니다: $file_path" >&2
        return 1
    }
}

assert_powershell_static_contract()
{
    local file_path
    local function_name
    local rule_id
    local report_heading

    for file_path in \
        "$POWERSHELL_PROFILE_SCRIPT" \
        "$POWERSHELL_DETECT_SCRIPT" \
        "$POWERSHELL_LINT_SCRIPT" \
        "$POWERSHELL_INITIALIZER_SCRIPT" \
        "$POWERSHELL_CHECK_HARNESS_SCRIPT" \
        "$POWERSHELL_PRE_COMMIT_SCRIPT" \
        "$POWERSHELL_TOOLING_SCRIPT" \
        "$POWERSHELL_TEST_SCRIPT"
    do
        assert_file_exists "$file_path" "PowerShell 계약 파일이 없습니다" || return 1
        assert_powershell_utf8_bom "$file_path" || return 1
        assert_powershell_delimiters "$file_path" || return 1
    done

    if grep -EIn 'Invoke-Expression|(^|[^A-Za-z0-9_])iex([[:space:]]|$)|ForEach-Object[[:space:]]+-Parallel|ConvertFrom-Json[[:space:]]+-AsHashtable|\?\?' \
        "$POWERSHELL_PROFILE_SCRIPT" \
        "$POWERSHELL_DETECT_SCRIPT" \
        "$POWERSHELL_LINT_SCRIPT" \
        "$POWERSHELL_INITIALIZER_SCRIPT" \
        "$POWERSHELL_CHECK_HARNESS_SCRIPT" \
        "$POWERSHELL_PRE_COMMIT_SCRIPT" \
        "$POWERSHELL_TOOLING_SCRIPT"
    then
        echo "PowerShell 5.1 비호환 또는 금지 API가 발견되었습니다." >&2
        return 1
    fi

    if grep -En 'Write-Error' \
        "$POWERSHELL_INITIALIZER_SCRIPT" \
        "$POWERSHELL_CHECK_HARNESS_SCRIPT" \
        "$POWERSHELL_PRE_COMMIT_SCRIPT"
    then
        echo "PowerShell 진입점에서 Write-Error가 명시적 종료 코드를 선점할 수 있습니다." >&2
        return 1
    fi

    if grep -En 'Get-ChildItem[^\r\n]*-Recurse|-Recurse[^\r\n]*Get-ChildItem' \
        "$POWERSHELL_DETECT_SCRIPT" \
        "$POWERSHELL_LINT_SCRIPT"
    then
        echo "PowerShell 순회가 제외 경계 진입 후 필터링하고 있습니다." >&2
        return 1
    fi

    if grep -En '\[regex\]::Replace\(\$Text' "$POWERSHELL_DETECT_SCRIPT"
    then
        echo "PowerShell 감지가 raw 정규식 문자열 제거기로 회귀했습니다." >&2
        return 1
    fi

    for function_name in \
        Read-HarnessProfile \
        Test-HarnessProfile \
        Write-HarnessProfile \
        Confirm-HarnessProfile
    do
        grep -Eq "^function[[:space:]]+$function_name([[:space:]]|$)" "$POWERSHELL_PROFILE_SCRIPT" || {
            echo "PowerShell 프로필 공개 함수가 없습니다: $function_name" >&2
            return 1
        }
    done

    for function_name in Find-UnityProjectRoot Invoke-ProjectDetection Write-DetectionReport
    do
        grep -Eq "^function[[:space:]]+$function_name([[:space:]]|$)" "$POWERSHELL_DETECT_SCRIPT" || {
            echo "PowerShell 감지 공개 함수가 없습니다: $function_name" >&2
            return 1
        }
    done
    grep -Eq '^function[[:space:]]+Invoke-HarnessLint([[:space:]]|$)' "$POWERSHELL_LINT_SCRIPT" || {
        echo "PowerShell 린트 공개 함수가 없습니다: Invoke-HarnessLint" >&2
        return 1
    }

    grep -Fq '[ordered]' "$POWERSHELL_PROFILE_SCRIPT" || return 1
    grep -Fq 'System.Collections.Generic.List[string]' "$POWERSHELL_PROFILE_SCRIPT" || return 1
    grep -Fq 'System.Web.Script.Serialization.JavaScriptSerializer' "$POWERSHELL_DETECT_SCRIPT" || return 1
    grep -Fq 'ReparsePoint' "$POWERSHELL_PROFILE_SCRIPT" || return 1
    grep -Fq 'HarnessDetectionReportWriter' "$POWERSHELL_DETECT_SCRIPT" || return 1
    grep -Fq 'Packages/packages-lock.json' "$POWERSHELL_DETECT_SCRIPT" || {
        echo "PowerShell 감지기에 packages-lock.json 계약이 없습니다." >&2
        return 1
    }
    grep -Fq 'ConvertTo-HarnessDetectionSanitizedCSharp' "$POWERSHELL_DETECT_SCRIPT" || return 1
    grep -Fq 'InClause' "$POWERSHELL_DETECT_SCRIPT" || return 1
    grep -Fq 'HarnessDefaultExcludeRoots' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'ConvertTo-HarnessSanitizedCSharp' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'Get-HarnessUpdateRanges' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'Get-HarnessCanonicalPath' "$POWERSHELL_DETECT_SCRIPT" || return 1
    grep -Fq 'Get-HarnessLintCanonicalPath' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'Test-HarnessReparseAncestor' "$POWERSHELL_PROFILE_SCRIPT" || return 1
    grep -Fq 'Get-HarnessProfileCanonicalPath' "$POWERSHELL_PROFILE_SCRIPT" || return 1
    grep -Fq 'Distinct' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'Where|Select|SelectMany|Distinct|OrderBy|OrderByDescending|ThenBy|GroupBy|ToList|ToArray|Any|All|First|FirstOrDefault|Single|SingleOrDefault|Count' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'Enumerable\.' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'Vector2|Vector3|Vector4|Quaternion|Color|Color32|Rect|Bounds|Ray|Plane|Matrix4x4' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'Skip-CurrentTest' "$POWERSHELL_TEST_SCRIPT" || return 1
    grep -Fq 'HarnessProductionApisImported' "$POWERSHELL_TEST_SCRIPT" || return 1
    grep -Fq 'ParityInputsProvided' "$POWERSHELL_TEST_SCRIPT" || return 1
    grep -Fq 'test_packages_lock_dependencies_are_merged_and_validated' "$POWERSHELL_TEST_SCRIPT" || {
        echo "PowerShell 테스트에 packages-lock 계약이 없습니다." >&2
        return 1
    }

    for report_heading in \
        '# Unity 하네스 감지 보고서' \
        '## 요약' \
        '## 감지 근거와 신뢰도' \
        '## 소스 및 테스트 루트' \
        '## 조건부 최적화 적용 가능성' \
        '## 충돌 및 미확정 항목' \
        '## 사용자 확인 절차'
    do
        grep -Fq "$report_heading" "$POWERSHELL_DETECT_SCRIPT" || {
            echo "PowerShell 감지 보고서 헤딩이 없습니다: $report_heading" >&2
            return 1
        }
    done

    for rule_id in \
        CONFIG001 PATH001 SOLID001 PERF001 PERF002 UNITYNULL001 MVVM001 MVP001 \
        MVC001 LAYER001 VCONTAINER001 UNITASK001 DOTWEEN001 STYLE001 DOC001
    do
        grep -Fq "\"$rule_id\"" "$LINT_SCRIPT" || {
            echo "Bash 린트 규칙 ID가 없습니다: $rule_id" >&2
            return 1
        }
        grep -Fq "\"$rule_id\"" "$POWERSHELL_LINT_SCRIPT" || {
            echo "PowerShell 린트 규칙 ID가 없습니다: $rule_id" >&2
            return 1
        }
    done

    grep -Fq '%25' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq '%7C' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq '%0D' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq '%0A' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'RULE_ID|severity|path|line|message' "$POWERSHELL_LINT_SCRIPT" || return 1
    grep -Fq 'exit 4' "$POWERSHELL_INITIALIZER_SCRIPT" || return 1
    grep -Fq 'exit 3' "$POWERSHELL_CHECK_HARNESS_SCRIPT" || return 1
    grep -Fq 'karpathy_guidelines' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'Test-AgentToolingConfinedChildPath' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq '$PathComparison = if ($env:OS -eq "Windows_NT")' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq '[StringComparison]::OrdinalIgnoreCase' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq '[StringComparison]::Ordinal' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'config.toml을 비파괴 백업' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'enabled = false' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq '충돌 경로를 이동한 후' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'check-agent-tooling.ps1 -Check' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'Test-SuperpowersRepoLink' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq '.superpowers.install-' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'AgentToolingExitCode"] = 3' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'git clone https://github.com/obra/superpowers.git' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    if grep -Fq 'codex plugin marketplace add' "$POWERSHELL_TOOLING_SCRIPT"; then
        echo "PowerShell Superpowers 설치에 폐기된 marketplace 명령이 남아 있습니다." >&2
        return 1
    fi
    grep -Fq 'understand_anything' "$POWERSHELL_TOOLING_SCRIPT" || return 1
    grep -Fq 'test_tooling_reports_installed_disabled_broken_and_missing' "$POWERSHELL_TEST_SCRIPT" || return 1
    grep -Fq 'test_tooling_rejects_symlinked_cache_and_escaped_install_roots' "$POWERSHELL_TEST_SCRIPT" || return 1
}

test_powershell_parity_contract()
{
    local powershell_command=""
    local case_root
    local project_root
    local bash_profile_path
    local bash_report_path
    local powershell_profile_path
    local powershell_report_path
    local output
    local status

    assert_powershell_static_contract || return 1

    if command -v pwsh >/dev/null 2>&1; then
        powershell_command=pwsh
    elif command -v powershell >/dev/null 2>&1; then
        powershell_command=powershell
    else
        echo "PowerShell 런타임 없음: 교차 검증 미실행"
        return 77
    fi

    load_detection_api || return 1
    case_root="$TEST_TEMP_ROOT/powershell-parity"
    project_root="$case_root/한글 및 공백 프로젝트"
    bash_profile_path="$case_root/bash/project-profile.conf"
    bash_report_path="$case_root/bash/detection-report.md"
    powershell_profile_path="$case_root/powershell/project-profile.conf"
    powershell_report_path="$case_root/powershell/detection-report.md"
    mkdir -p "$case_root/bash" "$case_root/powershell"
    create_unity_fixture "$project_root" "mvvm"

    detect_project "$project_root" "$bash_profile_path" "$bash_report_path" "$SCHEMA_PATH" "$SIGNATURES_PATH" >/dev/null 2>&1 || return 1
    output=$($powershell_command -NoProfile -ExecutionPolicy Bypass -File "$POWERSHELL_TEST_SCRIPT" \
        -Group parity \
        -Runtime powershell \
        -ParityProjectRoot "$project_root" \
        -ParityProfilePath "$powershell_profile_path" \
        -ParityReportPath "$powershell_report_path" 2>&1)
    status=$?
    assert_equal "0" "$status" "PowerShell parity 실행 코드가 다릅니다" || {
        printf '%s\n' "$output" >&2
        return 1
    }
    cmp -s "$bash_profile_path" "$powershell_profile_path" || {
        echo "Bash/PowerShell 프로필 출력 순서 또는 값이 다릅니다." >&2
        return 1
    }
    echo "Bash/PowerShell 프로필 및 종료 코드 일치"
}

assert_schema_enum_values_documented()
{
    local schema_key=$1
    local document_path=$2
    local schema_line
    local enum_values
    local enum_value
    local old_ifs
    local enum_document
    local enum_section="$TEST_TEMP_ROOT/task6-enum-section.txt"
    local enum_section_size
    local enum_heading_count
    local enum_action_count

    schema_line=$(grep "^$schema_key|" "$SCHEMA_PATH" | head -1)
    if [ -z "$schema_line" ]; then
        echo "프로필 스키마 키가 없습니다: $schema_key" >&2
        return 1
    fi

    enum_values=$(printf '%s\n' "$schema_line" | awk -F'|' '{ print $5 }')
    old_ifs=$IFS
    IFS=,
    for enum_value in $enum_values
    do
        IFS=$old_ifs
        case "$schema_key" in
            dependency_injection|async_backend|tween_backend|render_pipeline)
                if [ ! -f "$document_path" ]; then
                    echo "프로필 라우팅 문서가 없습니다: $document_path" >&2
                    return 1
                fi
                extract_markdown_h2_section "$document_path" "## \`$enum_value\`" "$enum_section" || {
                    echo "enum 전용 H2가 누락되었습니다: $schema_key=$enum_value" >&2
                    return 1
                }
                enum_section_size=$(wc -c < "$enum_section" | tr -d ' ')
                if [ "$enum_section_size" -lt 30 ] || ! grep -Eq '(합니다|않습니다|경우입니다|상태입니다)' "$enum_section"; then
                    echo "enum H2에 동작 설명이 없습니다: $schema_key=$enum_value" >&2
                    return 1
                fi
                ;;
            architecture)
                case "$enum_value" in
                    layered_clean)
                        enum_document="$document_path/layered-clean.md"
                        ;;
                    *)
                        enum_document="$document_path/$enum_value.md"
                        ;;
                esac
                if [ ! -f "$enum_document" ]; then
                    echo "아키텍처 enum 전용 문서가 없습니다: $enum_value" >&2
                    return 1
                fi
                grep -Fq "프로필 분기 \`$enum_value\`: \`architecture=$enum_value\`" "$enum_document" || {
                    echo "아키텍처 enum 선언이 전용 문서에 없습니다: $enum_value" >&2
                    return 1
                }
                extract_markdown_h2_section "$enum_document" '## 책임' "$enum_section" || return 1
                enum_section_size=$(wc -c < "$enum_section" | tr -d ' ')
                if [ "$enum_section_size" -lt 50 ]; then
                    echo "아키텍처 enum 책임 설명이 비어 있습니다: $enum_value" >&2
                    return 1
                fi
                ;;
            gpu_resident_drawer|gpu_occlusion_culling|stp|mesh_lod)
                enum_heading_count=$(grep -Fc "#### \`$enum_value\` 판정" "$document_path")
                if [ "$enum_heading_count" -ne 4 ]; then
                    echo "최적화 enum 판정 섹션이 기법별로 존재하지 않습니다: $schema_key=$enum_value" >&2
                    return 1
                fi
                enum_action_count=$(LC_ALL=C awk -v heading="#### \`$enum_value\` 판정" '
                    $0 == heading {
                        inside = 1
                        next
                    }
                    inside && /^#/ {
                        inside = 0
                    }
                    inside && /선택합니다|유지합니다|확정하지 않습니다/ {
                        count++
                        inside = 0
                    }
                    END {
                        print count + 0
                    }
                ' "$document_path")
                if [ "$enum_action_count" -ne 4 ]; then
                    echo "최적화 enum 판정 섹션에 동작 설명이 없습니다: $schema_key=$enum_value" >&2
                    return 1
                fi
                ;;
            *)
                grep -Fq "\`$enum_value\`" "$document_path" || {
                    echo "프로필 분기 문서화가 누락되었습니다: $schema_key=$enum_value ($document_path)" >&2
                    return 1
                }
                ;;
        esac
        IFS=,
    done
    IFS=$old_ifs

    return 0
}

assert_document_contains_all()
{
    local document_path=$1
    local contract_name=$2
    local required_text
    shift 2

    if [ ! -f "$document_path" ]; then
        echo "$contract_name 문서가 없습니다: $document_path" >&2
        return 1
    fi

    for required_text in "$@"
    do
        grep -Fq -- "$required_text" "$document_path" || {
            echo "$contract_name 의미 계약이 누락되었습니다: $required_text" >&2
            return 1
        }
    done

    return 0
}

extract_markdown_h2_section()
{
    local document_path=$1
    local section_heading=$2
    local output_path=$3

    LC_ALL=C awk -v heading="$section_heading" '
        $0 == heading {
            found = 1
            inside = 1
            next
        }
        inside && /^##[[:space:]]/ {
            exit
        }
        inside {
            print
        }
        END {
            if (!found) {
                exit 1
            }
        }
    ' "$document_path" > "$output_path"
}

assert_h2_section_contains_all()
{
    local document_path=$1
    local section_heading=$2
    local contract_name=$3
    local section_path="$TEST_TEMP_ROOT/task6-section.txt"
    local required_text
    local section_line
    local line_matches
    shift 3

    extract_markdown_h2_section "$document_path" "$section_heading" "$section_path" || {
        echo "$contract_name 섹션이 없습니다: $section_heading" >&2
        return 1
    }

    while IFS= read -r section_line || [ -n "$section_line" ]
    do
        line_matches=1
        for required_text in "$@"
        do
            case "$section_line" in
                *"$required_text"*)
                    ;;
                *)
                    line_matches=0
                    break
                    ;;
            esac
        done
        if [ "$line_matches" -eq 1 ]; then
            return 0
        fi
    done < "$section_path"

    echo "$contract_name 섹션의 같은 문장에 의미 계약이 없습니다: $section_heading" >&2
    return 1
}

assert_architecture_allowed_direction()
{
    local document_path=$1
    local architecture_name=$2

    case "$architecture_name" in
        mvvm)
            assert_h2_section_contains_all "$document_path" '## 허용 의존 방향' "MVVM 허용 방향" \
                'View → ViewModel → Model' '허용 의존 방향' || return 1
            assert_h2_section_contains_all "$document_path" '## 금지 의존 방향' "MVVM 금지 방향" \
                'View가 Model' '직접 참조' '금지' || return 1
            ;;
        mvp)
            assert_h2_section_contains_all "$document_path" '## 허용 의존 방향' "MVP 허용 방향" \
                'Presenter' 'View 인터페이스' 'Model·UseCase 인터페이스' '향합니다' || return 1
            assert_h2_section_contains_all "$document_path" '## 금지 의존 방향' "MVP 금지 방향" \
                'View가 Model' '직접 조회·수정' '금지' || return 1
            ;;
        mvc)
            assert_h2_section_contains_all "$document_path" '## 허용 의존 방향' "MVC 허용 방향" \
                'Controller' 'Model' 'View 인터페이스' '향하며' || return 1
            assert_h2_section_contains_all "$document_path" '## 금지 의존 방향' "MVC 금지 방향" \
                'View' '비즈니스 규칙' 'Model' '구체 View·Controller' '금지' || return 1
            ;;
        layered_clean)
            assert_h2_section_contains_all "$document_path" '## 허용 의존 방향' "Layered/Clean 허용 방향" \
                'Presentation → Application → Domain' '바깥 계층' '안쪽 계층' || return 1
            assert_h2_section_contains_all "$document_path" '## 금지 의존 방향' "Layered/Clean 금지 방향" \
                'Domain' 'Presentation' 'Infrastructure' '금지' || return 1
            ;;
        custom)
            assert_h2_section_contains_all "$document_path" '## 허용 의존 방향' "Custom 허용 방향" \
                '프로젝트 문서' '.asmdef' '확정한 의존 방향' '허용' || return 1
            assert_h2_section_contains_all "$document_path" '## 금지 의존 방향' "Custom 금지 방향" \
                '금지되는 의존 방향' '사용자가 확정한 프로젝트 경계' || return 1
            ;;
        *)
            return 2
            ;;
    esac
}

assert_async_lifecycle_contract()
{
    local document_path=$1
    local section_path="$TEST_TEMP_ROOT/task6-async-contract.txt"

    assert_h2_section_contains_all "$document_path" '## 공통 수명 원칙' "비동기 소유·취소 계약" \
        '작업 소유자' '취소' '책임' || return 1
    assert_h2_section_contains_all "$document_path" '## 공통 수명 원칙' "비동기 Unity 수명 계약" \
        'Unity 객체' '수명' '확인' || return 1
    assert_h2_section_contains_all "$document_path" '## 공통 수명 원칙' "비동기 예외 계약" \
        'fire-and-forget' '예외 처리 정책' || return 1

    extract_markdown_h2_section "$document_path" '## 공통 수명 원칙' "$section_path" || return 1
    if grep -Eq '(취소|해제|정리|관찰)하지' "$section_path"; then
        echo "비동기 수명 섹션에 부정 정리 계약이 있습니다." >&2
        return 1
    fi
}

assert_tween_cleanup_contract()
{
    local document_path=$1
    local section_path="$TEST_TEMP_ROOT/task6-tween-contract.txt"

    assert_h2_section_contains_all "$document_path" '## `dotween`' "DOTween 파괴 콜백" 'OnDestroy' || return 1
    assert_h2_section_contains_all "$document_path" '## `dotween`' "DOTween Kill" '.Kill();' || return 1

    extract_markdown_h2_section "$document_path" '## `dotween`' "$section_path" || return 1
    if grep -Eq 'Kill하지|해제하지|정리하지|취소하지' "$section_path"; then
        echo "DOTween 섹션에 부정 정리 계약이 있습니다." >&2
        return 1
    fi
}

assert_compatibility_route()
{
    local document_path=$1
    local preserved_item=$2
    local target_path=$3

    local route_line

    while IFS= read -r route_line || [ -n "$route_line" ]
    do
        case "$route_line" in
            *"$preserved_item"*"]($target_path)"*)
                return 0
                ;;
        esac
    done < "$document_path"

    echo "호환 보존 항목과 링크 target이 같은 표 행에 없습니다: $preserved_item -> $target_path" >&2
    return 1
}

assert_markdown_table_row_contains_all()
{
    local document_path=$1
    local row_key=$2
    local contract_name=$3
    local table_line
    local required_text
    local line_matches
    shift 3

    while IFS= read -r table_line || [ -n "$table_line" ]
    do
        case "$table_line" in
            *"$row_key"*)
                line_matches=1
                for required_text in "$@"
                do
                    case "$table_line" in
                        *"$required_text"*)
                            ;;
                        *)
                            line_matches=0
                            break
                            ;;
                    esac
                done
                if [ "$line_matches" -eq 1 ]; then
                    return 0
                fi
                ;;
        esac
    done < "$document_path"

    echo "$contract_name 표 행 계약이 없습니다: $row_key" >&2
    return 1
}

assert_no_fixed_profile_assumptions()
{
    local search_path=$1
    local prohibited_pattern

    for prohibited_pattern in \
        '(MVVM|VContainer|URP|Assets/Scripts).{0,80}(필수|반드시|강제|고정|만[[:space:]]*사용|기본[[:space:]]*(값|아키텍처|DI|파이프라인)|표준)' \
        '(필수|반드시|강제|고정|모든[[:space:]]*프로젝트|기본|표준).{0,80}(MVVM|VContainer|URP|Assets/Scripts)' \
        '(MVVM|VContainer|URP|Assets/Scripts).{0,80}(is[[:space:]]+required|must[[:space:]]+be[[:space:]]+used|only|default|standard)' \
        '(all[[:space:]]+projects|must[[:space:]]+use|only|default|standard).{0,80}(MVVM|VContainer|URP|Assets/Scripts)'
    do
        if grep -REin "$prohibited_pattern" "$search_path"; then
            echo "Core 문서에 위장된 고정 프로필 전제가 남아 있습니다: $prohibited_pattern" >&2
            return 1
        fi
    done

    return 0
}

test_docs_have_exact_task6_inventory()
{
    local actual_inventory="$TEST_TEMP_ROOT/task6-docs-actual.txt"
    local expected_inventory="$TEST_TEMP_ROOT/task6-docs-expected.txt"
    local required_directory

    for required_directory in \
        "$DOCS_ROOT/coding-standards/core" \
        "$DOCS_ROOT/coding-standards/optimization" \
        "$DOCS_ROOT/profiles/architecture"
    do
        if [ ! -d "$required_directory" ]; then
            echo "Task 6 문서 디렉터리가 없습니다: $required_directory" >&2
            return 1
        fi
    done

    (
        cd "$AGENTS_ROOT" || exit 1
        find docs/coding-standards/core docs/coding-standards/optimization docs/profiles -type f -name '*.md' -print
        printf '%s\n' \
            docs/coding-standards/architecture-rules.md \
            docs/coding-standards/naming-conventions.md \
            docs/coding-standards/performance-rules.md \
            docs/coding-standards/safety-rules.md \
            docs/coding-standards/unity-specific.md
    ) | LC_ALL=C sort > "$actual_inventory"

    printf '%s\n' \
        docs/coding-standards/architecture-rules.md \
        docs/coding-standards/core/architecture-principles.md \
        docs/coding-standards/core/naming-and-documentation.md \
        docs/coding-standards/core/runtime-performance.md \
        docs/coding-standards/core/unity-safety.md \
        docs/coding-standards/core/unity-validation.md \
        docs/coding-standards/naming-conventions.md \
        docs/coding-standards/optimization/general-techniques.md \
        docs/coding-standards/optimization/performance-tuning-bible.md \
        docs/coding-standards/optimization/rendering-techniques.md \
        docs/coding-standards/performance-rules.md \
        docs/coding-standards/safety-rules.md \
        docs/coding-standards/unity-specific.md \
        docs/profiles/architecture/custom.md \
        docs/profiles/architecture/layered-clean.md \
        docs/profiles/architecture/mvc.md \
        docs/profiles/architecture/mvp.md \
        docs/profiles/architecture/mvvm.md \
        docs/profiles/async.md \
        docs/profiles/dependency-injection.md \
        docs/profiles/rendering.md \
        docs/profiles/tween.md \
        | LC_ALL=C sort > "$expected_inventory"

    if ! cmp -s "$expected_inventory" "$actual_inventory"; then
        echo "Task 6 문서 목록이 Core 5개, Optimization 3개, Profile 9개, 호환 5개와 다릅니다." >&2
        diff "$expected_inventory" "$actual_inventory" >&2 || true
        return 1
    fi

    return 0
}

test_docs_define_milestone_build_gate()
{
    local validation_document="$DOCS_ROOT/coding-standards/core/unity-validation.md"
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"
    local agent_quickstart="$DOCS_ROOT/onboarding/agent-quickstart.md"
    local developer_quickstart="$DOCS_ROOT/onboarding/developer-quickstart.md"
    local plan_template="$DOCS_ROOT/exec-plans/_TEMPLATE.md"
    local plans_readme="$DOCS_ROOT/exec-plans/README.md"
    local scripts_readme="$AGENTS_ROOT/scripts/README.md"
    local tests_readme="$AGENTS_ROOT/tests/README.md"

    assert_file_exists "$validation_document" "Unity 기능·마일스톤 검증 정책" || return 1
    assert_document_contains_all "$validation_document" "Unity 기능·마일스톤 검증 정책" \
        '# Unity 기능·마일스톤 검증 정책' \
        '개별 Task 검증에서는 Player Build를 수행하지 않습니다.' \
        '전체 자동화 통합 테스트' \
        'missing' \
        'not_run' \
        '동일 change_id' \
        'Assets/_Game' \
        '같은 논리적 빌드 입력에 동일한 식별자' \
        '`coverage_status=confirmed`' \
        '`module_scope`' \
        '`interaction_scope`' \
        'exact match' \
        'missing/unexpected/duplicate/invalid' \
        'imported package' \
        'Asset Store' \
        'UPM' \
        'third-party originals' \
        '`build_run_id=pending`' \
        '`build_artifact_hash=pending`' \
        'prebuild에서 선택한 `build_authority`' \
        '`--expected-authority` 또는 `-ExpectedAuthority`' \
        '실제 실행을 식별하는 build_run_id' \
        'lowercase 64-hex artifact hash' \
        'pure read-only gate' \
        'expected change-id argument' \
        'stale change-id' \
        '같은 evidence path' \
        'phase sequence' || return 1

    assert_document_contains_all "$agents_document" "AGENTS Unity 검증 라우팅" \
        'unity-validation.md' \
        '개별 Task' \
        'Player Build를 포함하지 않습니다' \
        '기능·마일스톤' \
        '전체 자동화 통합 테스트' \
        '사전 게이트를 통과한 동일 변경분에만 1회 수행' \
        'Unity CI Build Validation이 있으면 로컬 중복 빌드를 수행하지 않습니다' || return 1

    for document_path in "$agent_quickstart" "$developer_quickstart"
    do
        assert_document_contains_all "$document_path" "온보딩 Unity 검증 계약" \
            '개별 Task' \
            '정적 검사' \
            '대상 테스트' \
            'Unity 컴파일' \
            'Player Build를 포함하지 않습니다' \
            '기능·마일스톤' \
            '전체 자동화 통합 테스트' \
            '사전 게이트를 통과한 동일 변경분에만 1회 수행' \
            'Unity CI Build Validation이 있으면 로컬 중복 빌드를 수행하지 않습니다' || return 1
    done

    assert_document_contains_all "$plan_template" "실행 계획 기능·마일스톤 검증 계약" \
        '## 기능·마일스톤 선언' \
        'milestone_id' \
        '포함 Task' \
        '수용 기준' \
        'target_platform' \
        'local|unity_ci' \
        'Git change set' \
        '비Git checksum' \
        '## 모듈 scope inventory' \
        '`module_scope`' \
        '## 상호작용 scope inventory' \
        '`interaction_scope`' \
        '## 통합 테스트 매트릭스' \
        'exact match' \
        'failed/missing/not_run' \
        'evidence path' \
        'change-id 계산 절차·명령' \
        '--phase prebuild' \
        '-Phase prebuild' \
        '--phase built' \
        '-Phase built' \
        '`build_authority`' \
        '`build_run_id`' \
        '`build_artifact_hash`' \
        '## 최종 Player Build' \
        'Compile+all Unit+all Integration' \
        'same change' \
        'Unity CI Build Validation once' || return 1

    assert_document_contains_all "$plans_readme" "실행 계획 작성 안내" \
        '대괄호' \
        '실제 값으로 교체' \
        '개별 Task step' \
        'Player Build 명령 금지' \
        '`module_scope`' \
        '`interaction_scope`' \
        'exact match' \
        'evidence path' \
        'change-id 계산 절차·명령' \
        '`build_run_id`' \
        '`build_artifact_hash`' || return 1

    assert_document_contains_all "$scripts_readme" "Unity 마일스톤 검증기 안내" \
        'check-unity-milestone.sh' \
        'check-unity-milestone.ps1' \
        'read-only' \
        '본문에서 3' \
        'CmdletBinder native nonzero' \
        '-NonInteractive' \
        '`module_scope`' \
        '`interaction_scope`' \
        '`build_run_id`' \
        '`build_artifact_hash`' \
        'selected build_authority' \
        'pure read-only gate' \
        'expected change id' \
        'phase sequence' || return 1

    assert_document_contains_all "$tests_readme" "validation 테스트 그룹 안내" \
        '`validation`' \
        'bash .agents/tests/run-tests.sh --group validation --runtime bash' \
        'powershell -NoProfile -NonInteractive' \
        '.agents/tests/run-tests.ps1 -Group validation -Runtime powershell' \
        'module_scope' \
        'interaction_scope' \
        'exact match' \
        'build_run_id' \
        'artifact hash' || return 1

    assert_document_contains_all "$agent_tooling_document" "Karpathy 작업 경계" \
        'karpathy-guidelines' \
        '가정' \
        '범위' \
        '검증 기준' \
        '최소 변경' || return 1

    return 0
}

test_docs_define_subagent_implementation_and_validation_authority()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local agent_quickstart="$DOCS_ROOT/onboarding/agent-quickstart.md"
    local developer_quickstart="$DOCS_ROOT/onboarding/developer-quickstart.md"
    local tech_stack_overview="$DOCS_ROOT/onboarding/tech-stack-overview.md"
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"
    local validation_document="$DOCS_ROOT/coding-standards/core/unity-validation.md"
    local plans_readme="$DOCS_ROOT/exec-plans/README.md"
    local plan_template="$DOCS_ROOT/exec-plans/_TEMPLATE.md"
    local scripts_readme="$AGENTS_ROOT/scripts/README.md"
    local tests_readme="$AGENTS_ROOT/tests/README.md"

    assert_document_contains_all "$agents_document" "AGENTS 구현·검증 권한 정책" \
        '## 최우선 구현·검증 권한 정책' \
        '구현 파일을 직접 생성하거나 수정하지 않습니다.' \
        '모든 구현 파일 생성·수정은 구현 서브 에이전트가 수행합니다.' \
        '1. 사용자 요구와 목표' \
        '2. 승인된 계획과 변경 범위' \
        '3. 프로젝트 `.agents/AGENTS.md` 및 연결된 최우선 규칙' \
        '4. 적용할 아키텍처·코딩·명명 규칙과 Karpathy Guidelines' \
        '5. 생성·수정 가능한 정확한 대상 파일' \
        '6. 관련 없는 변경, 서드파티, 외부 서비스 등 금지 범위' \
        '7. 현재 요청에서 허용된 검증·테스트 목록 또는 `none`' \
        '8. `unity command recompile`·배치 컴파일·프로젝트 명령 등 컴파일·구문 오류 확인 방법' \
        '9. 변경 파일, 구현 요약, 컴파일 결과, `not_run`, 남은 위험을 포함한 완료 보고 형식' \
        '문서만 변경하면 `N/A`로 기록하고' \
        '실행이 막히면 원인을 보고하며 성공으로 주장하지 않습니다' \
        '하네스 린트, 정적 정책 검사, 계약·Unit·Integration 테스트, Unity EditMode·PlayMode 테스트, 런타임·씬·Inspector·시각 검증, Player Build와 외부 CI는 사용자가 현재 명시한 범위에서만 실행합니다.' \
        '사용자가 요청하지 않은 검증은 `not_run`으로 기록합니다.' \
        '`ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done 상태로 전환하지 않습니다.' \
        '구현 서브 에이전트가 완료를 보고하면 메인 에이전트가 요구사항 일치와 코드 품질을 독립적으로 정적 리뷰합니다.' \
        '중요한 리뷰 지적은 같은 구현 서브 에이전트가 수정하고 메인 에이전트가 재리뷰합니다.' \
        '정적 리뷰는 테스트나 런타임 검증을 대체하지 않습니다.' || return 1

    assert_document_contains_all "$agent_quickstart" "에이전트 온보딩 구현·검증 권한 정책" \
        '메인 에이전트 규칙 전달' \
        '서브 에이전트 구현' \
        '컴파일·구문 오류 확인' \
        '메인 에이전트 독립 리뷰' \
        '사용자가 요청한 검증' \
        'not_run 포함 최종 보고' \
        '모든 구현 파일 생성·수정은 필수 전달 패킷을 받은 구현 서브 에이전트가 수행하며 메인 에이전트는 구현하지 않습니다.' \
        '적용 가능한 코드·스크립트는 컴파일·구문 오류 확인까지 필수이고 문서만 변경하면 `N/A`입니다.' \
        '중요한 리뷰 지적은 같은 구현 서브 에이전트가 수정하고 메인 에이전트가 재리뷰합니다.' || return 1

    assert_document_contains_all "$agent_tooling_document" "에이전트 도구 구현·검증 권한 정책" \
        '모든 구현 파일 생성·수정은 `superpowers:subagent-driven-development` 성격으로 구현 서브 에이전트가 수행합니다.' \
        '메인 에이전트는 계획·규칙 전달·리뷰를 담당하고 직접 구현하지 않습니다.' \
        '`superpowers:test-driven-development`는 사용자가 RED·테스트 실행을 현재 요청한 범위에서만 실행합니다.' \
        '권한이 `none`이면 해당 단계는 `not_run`으로 남기고 향후 검증 명세만 유지합니다.' \
        '`superpowers:verification-before-completion`은 사용자가 현재 요청한 검증 범위에서만 실행합니다.' \
        '컴파일·구문 오류 확인은 별도의 필수 단계' \
        '스킬 적용은 린트, 테스트, 런타임 검증, Player Build 또는 외부 CI 실행 권한을 추가하지 않습니다.' \
        '요청하지 않은 검증은 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done으로 주장하거나 전환하지 않습니다.' \
        '중요한 지적은 같은 구현 서브 에이전트가 수정하고 메인 에이전트가 재리뷰합니다.' || return 1

    assert_document_contains_all "$validation_document" "Unity 검증 실행 권한 정책" \
        '적용 가능한 코드·스크립트 변경의 컴파일·구문 오류 확인과 구현 후 메인 에이전트 정적 리뷰는 필수입니다.' \
        '문서만 변경하면 컴파일 확인은 `N/A`' \
        '확인 진입점이 없거나 막히면 성공으로 처리하지 않습니다.' \
        '하네스 린트, 정적 정책 검사, 계약·Unit·Integration 테스트, Unity EditMode·PlayMode 테스트, 런타임·씬·Inspector·시각 검증은 사용자가 현재 명시한 범위에서만 실행합니다.' \
        'Player Build와 외부 Unity CI는 사용자가 현재 명시적으로 요청한 경우에만 실행합니다.' \
        '요청하지 않은 필수 검증은 `not_run`으로 기록하며 `passed`나 검증 완료로 간주하지 않고 후속 상태를 차단합니다.' \
        '개별 Task에서 Player Build는 검증 비대상' \
        '메인 에이전트의 정적 리뷰는 테스트·런타임·빌드 검증을 대체하지 않습니다.' || return 1

    assert_document_contains_all "$plan_template" "실행 계획 템플릿 구현·검증 권한 정책" \
        '## 현재 실행 권한과 역할' \
        '| 현재 테스트 권한 | `none` 또는 [사용자가 현재 요청한 정확한 검증·테스트 목록] |' \
        '| 구현 서브 에이전트 | [모든 구현 파일 생성·수정 담당자] |' \
        '| 컴파일 확인 | [`unity command recompile`·배치 컴파일·언어별 구문 명령 또는 문서 변경 `N/A`] |' \
        '| 메인 리뷰 | [독립 정적 코드 리뷰 담당자와 중요 지적 재작업·재리뷰 절차] |' \
        '| `not_run` | [현재 요청하지 않아 실행하지 않을 린트·테스트·런타임·빌드·외부 CI] |' \
        '메인 에이전트는 사용자 요구, 승인 범위, 최우선 규칙, 아키텍처·코딩·명명·Karpathy 규칙, 정확한 대상 파일, 금지 범위, 테스트 권한, 컴파일 확인 방법과 완료 보고 형식을 구현 서브 에이전트에게 전달하고 직접 구현하지 않습니다.' \
        '적용 가능한 코드·스크립트의 컴파일·구문 오류 확인은 필수이며, 문서만 변경하면 `N/A`입니다.' \
        '확인 진입점이 없거나 막히면 성공으로 주장하지 않습니다.' \
        '현재 테스트 권한이 `none`이면 아래 RED, 테스트, 린트, 런타임, Player Build와 외부 CI 단계는 실행하지 않고 `not_run`으로 기록합니다.' \
        '서브 에이전트 완료 보고 후 메인 에이전트 독립 정적 리뷰' \
        '중요한 리뷰 지적을 같은 구현 서브 에이전트가 수정했고 메인 에이전트가 재리뷰함' \
        '미요청 검증이 `not_run`으로 기록되었고 검증 완료·CI 통과·`ci_tests_passed`·`ci_passed`·Approve·Merge·Done으로 오인되지 않음' || return 1

    assert_document_contains_all "$plans_readme" "실행 계획 안내 구현·검증 권한 정책" \
        '현재 테스트 권한이 `none`이면 명세를 계획에 보존하되 실행 결과는 `not_run`으로 기록합니다.' \
        '모든 구현 파일 생성·수정은 필수 전달 패킷을 받은 구현 서브 에이전트가 수행하며, 메인 에이전트는 계획·규칙 전달·리뷰를 담당합니다.' \
        '적용 가능한 코드·스크립트의 컴파일·구문 오류 확인은 필수입니다.' \
        '문서만 변경하면 `N/A`이고 확인 진입점이 없거나 막히면 성공으로 주장하지 않습니다.' \
        '구현 후 메인 에이전트가 독립 정적 리뷰하고, 중요한 지적은 같은 구현 서브 에이전트가 수정한 뒤 메인 에이전트가 재리뷰합니다.' \
        '미요청 검증은 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done으로 전환하지 않습니다.' \
        '메인 에이전트가 요구·승인 범위·최우선 규칙·구현 규칙·대상 파일·금지 범위·테스트 권한·컴파일 방법·완료 보고 형식을 구현 서브 에이전트에게 전달' || return 1

    assert_document_contains_all "$developer_quickstart" "개발자 온보딩 구현·검증 권한 정책" \
        '현재 테스트 권한과 `not_run` 항목을 기록합니다.' \
        '실패 검증은 사용자가 요청한 경우에만 실행하도록 계획합니다.' \
        '전체 승인 후 메인 에이전트가 필수 전달 패킷을 구현 서브 에이전트에게 전달합니다.' \
        '구현 서브 에이전트가 최소 범위로 구현하고 적용 가능한 코드·스크립트의 컴파일·구문 오류를 확인합니다.' \
        '문서만 변경하면 `N/A`입니다.' \
        '메인 에이전트가 독립 정적 리뷰하고, 중요한 지적은 같은 구현 서브 에이전트가 수정한 뒤 메인 에이전트가 재리뷰합니다.' \
        '사용자가 현재 요청한 항목만 실행하고 나머지는 `not_run`으로 기록합니다.' \
        '`not_run`은 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거가 아닙니다.' || return 1

    assert_document_contains_all "$tech_stack_overview" "기술 스택 온보딩 검증 권한 정책" \
        '사용자가 현재 요청한 경우에만 실행하는 예시입니다.' \
        '요청하지 않았다면 `not_run`으로 기록' \
        '`ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거로 사용하지 않습니다.' || return 1

    assert_document_contains_all "$scripts_readme" "스크립트 안내 검증 권한 정책" \
        '사용자가 해당 실행을 현재 요청한 경우에만 사용하는 예시입니다.' \
        '요청하지 않은 항목은 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거로 사용하지 않습니다.' \
        '적용 가능한 코드·스크립트를 수정했을 때의 컴파일·구문 오류 확인은 별도의 필수 예외이고, 문서만 변경하면 `N/A`입니다.' \
        '다음 테스트 명령은 사용자가 현재 요청한 범위에서만 실행합니다.' \
        '미요청 테스트는 `not_run`입니다.' || return 1

    assert_document_contains_all "$tests_readme" "테스트 안내 검증 권한 정책" \
        '사용자가 해당 검증을 현재 요청한 경우에만 실행하는 예시입니다.' \
        '요청하지 않은 테스트는 `not_run`이며 `ci_tests_passed`, `ci_passed`, Approve, Merge 또는 Done의 근거가 아닙니다.' \
        '테스트 러너 코드·스크립트를 수정한 경우 아래 `bash -n`과 같은 컴파일·구문 오류 확인은 별도의 필수 예외이고, 문서만 변경하면 `N/A`입니다.' \
        '사용자가 Bash 테스트를 현재 요청한 경우' \
        '사용자가 PowerShell 테스트를 현재 요청한 경우' || return 1

    assert_document_contains_all "$plan_template" "실제 행동·검증시간 본문 증거" \
        '원문 요구 → 허용 파일 → 실제 diff → 지정 플랫폼·패턴 → 명령 로그 증거' \
        '허용 범위 유지 / 타파일 이탈 / 플랫폼·패턴 대체' \
        '제품 Task마다 실제 에이전트 재실행을 요구하지 않습니다' \
        '입력 revision/hash' \
        '예상 초' '실제 초' '재실행 이유' \
        '작업 전체 시간과 검증 실행 시간은 따로 기록합니다' \
        'timeout·중단·미실행을 PASS로 처리하지 않습니다' || return 1

    return 0
}

test_docs_define_unity_worktree_editor_cli_routing()
{
    local unity_worktree_cli_document="$DOCS_ROOT/onboarding/unity-worktree-cli.md"
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"
    local agent_quickstart="$DOCS_ROOT/onboarding/agent-quickstart.md"
    local developer_quickstart="$DOCS_ROOT/onboarding/developer-quickstart.md"
    local validation_document="$DOCS_ROOT/coding-standards/core/unity-validation.md"
    local plans_readme="$DOCS_ROOT/exec-plans/README.md"
    local plan_template="$DOCS_ROOT/exec-plans/_TEMPLATE.md"

    assert_file_not_exists "$DOCS_ROOT/onboarding/unity-worktree-mcp.md" "MCP 격리 문서는 삭제되어야 합니다" || return 1

    assert_document_fragments_in_order "$unity_worktree_cli_document" "Unity worktree Editor·CLI canonical 순서" \
        '## Pipeline 인스턴스 발견과 고정' \
        '1. `unity status --format json`으로 실행 중인 Pipeline 인스턴스 목록(`port`, `project`, `version`, `pid`, `state`)을 읽습니다.' \
        '2. 각 후보의 `project`를 물리 절대 경로로 비교하여 대상 Unity 프로젝트 루트와 exact match인 후보만 남깁니다.' \
        '3. 후보가 정확히 하나일 때 그 `pid`·`port`·`version`을 기록합니다. 후보가 없거나 둘 이상이면 백그라운드 경로로 진행합니다.' \
        '4. `unity command editor_status --project-path <물리 절대 경로> --format json`으로 `projectPath` exact match, `status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용), `compiling=false`, `unityVersion`이 `ProjectVersion.txt`와 같은지 다시 확인합니다.' \
        '5. `unity list --project-path <물리 절대 경로>`로 프로젝트가 등록한 명령과 추가 규칙을 확인합니다.' \
        '6. 물리 `projectPath`가 exact match이고 `editor_status`가 `ready`(승인된 PlayMode 관측·정지·캡처 작업은 `playing`)일 때만 바인딩을 `ready`로 기록합니다.' \
        '## 구현 차단과 복구' || return 1

    assert_document_contains_all "$unity_worktree_cli_document" "Unity worktree Editor·CLI canonical 정책" \
        '# Unity linked worktree Editor·CLI 격리' \
        '다른 온보딩·실행 계획 문서는 이 문서를 요약하고 연결하며, 절차가 충돌하면 이 문서를 따릅니다.' \
        'Unity MCP는 사용하지 않습니다' \
        'git rev-parse --git-dir' \
        'git rev-parse --git-common-dir' \
        'git rev-parse --show-superproject-working-tree' \
        'ProjectSettings/ProjectVersion.txt' \
        '워크트리 1개 : Unity Editor 1개 : Pipeline 인스턴스 1개' \
        'unity status --format json' \
        'unity command editor_status --project-path' \
        'unity list --project-path' \
        'unity run <물리 경로> --command <명령>' \
        'status=playing' \
        'pipeline_outdated' \
        'Pipeline 최신 유지 규칙에 따라' \
        '--project-path <물리 절대 경로>' \
        'port는 인스턴스 identity가 아니며 CLI와 Pipeline 서버가 관리합니다.' \
        '프로젝트 파일에 port나 endpoint 설정을 쓰지 않으므로 `ready` 전 쓰기 예외는 없습니다.' \
        '실행 루트·물리 경로를 확정할 수 없으면 Unity 구현 서브 에이전트를 파견하거나 Unity 구현 파일을 수정하지 않습니다. 바인딩만 `ready`가 아니면 백그라운드 경로로 진행합니다.' \
        '다른 Editor, 메인 checkout 또는 목록의 첫 인스턴스로 대상을 바꾸지 않습니다.' \
        'background: editor_unavailable' \
        'not_run: editor_unavailable' \
        '로컬 Unity Editor 컴파일과 Console 증거' \
        '동일 `change_id`' \
        '선택된 `build_authority`' \
        '`unity_ci` 증거' \
        '별도 권위로 인정합니다.' || return 1

    assert_document_contains_all "$agents_document" "AGENTS Unity worktree Editor·CLI 라우팅" \
        '## Worktree별 Unity Editor·CLI 격리' \
        '`unity status --format json`의 인스턴스 `project`와 대상 물리 프로젝트 루트의 exact match' \
        '워크트리 1개 : Unity Editor 1개 : Pipeline 인스턴스 1개' \
        'Unity 검증·빌드·실행 중 Editor 상호작용은 Unity CLI·Pipeline으로 수행합니다.' \
        'Unity MCP는 사용하지 않습니다' \
        'port를 identity로 사용하지 않습니다.' \
        '`unity status --format json` 조회, 물리 `project` exact match 선별, `unity command editor_status --project-path <물리 경로>`, `unity list --project-path <물리 경로>` 순서로' \
        '`background: editor_unavailable`' \
        '실행 루트·물리 경로를 확정할 수 없을 때만 구현 서브 에이전트를 파견하지 않고 Unity 구현 전체를 중단합니다.' \
        '다른 Editor, 메인 checkout 또는 목록의 첫 인스턴스로 대상을 바꾸지 않습니다.' \
        '백그라운드 경로의 컴파일·테스트·빌드는 동일 물리 경로·버전의 CLI 결과로 인정하며' \
        '[Unity linked worktree Editor·CLI 격리](docs/onboarding/unity-worktree-cli.md)' || return 1

    assert_document_contains_all "$agent_tooling_document" "에이전트 도구 Unity worktree Editor 순서" \
        '## Unity worktree·Editor 준비' \
        '실행 중 Editor가 필요한 작업에만 적용' \
        'Unity MCP 서버·클라이언트는 설치하거나 연결하지 않습니다' \
        '1. `git rev-parse --show-toplevel`, `--git-dir`, `--git-common-dir`, `--show-superproject-working-tree`' \
        '2. `linked_worktree`이면 `ProjectSettings/ProjectVersion.txt` 버전과 물리 `projectPath`로 전용 Unity Editor를 준비합니다(`bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`; 이미 CLI 실패를 확인했으면 `--skip-cli`).' \
        '3. `unity status --format json`에서 `project`가 대상 물리 프로젝트 루트와 exact match인 인스턴스 하나를 찾아 `pid`·`port`·`version`을 기록합니다.' \
        '4. `unity command editor_status --project-path <물리 경로> --format json`으로 `projectPath` exact match, `status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용), `compiling=false`, `unityVersion` 일치를 확인합니다.' \
        '5. `unity list --project-path <물리 경로>`로 프로젝트가 등록한 명령과 추가 규칙을 먼저 확인합니다.' \
        '6. 바인딩이 `ready`이면 상주 Editor 경로로, 아니면 `background: editor_unavailable`을 기록하고 백그라운드 경로로 Unity 구현 서브 에이전트를 파견합니다.' \
        '3~5단계의 identity 확인은 네 실행 루트 유형 모두에 적용' \
        'port는 identity가 아닙니다.' \
        '1단계(실행 루트·물리 경로) 실패만 Unity 구현 전체를 중단' \
        '다른 Editor, 메인 checkout 또는 첫 인스턴스로 대상을 바꾸지 않습니다.' \
        '[Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)' || return 1

    assert_document_contains_all "$agent_quickstart" "에이전트 온보딩 Unity worktree Editor 게이트" \
        '## Unity worktree·Editor 준비 게이트' \
        '`normal_checkout`, `linked_worktree`, `submodule`, `non_git`' \
        '`unity status --format json`의 인스턴스 `project`와 대상 물리 프로젝트 루트의 exact match' \
        'port는 identity가 아니며 CLI가 관리합니다.' \
        '모든 `unity command` 호출은 `--project-path <물리 절대 경로>`를 명시합니다.' \
        '`background: editor_unavailable`' \
        '실행 루트를 확정할 수 없을 때만 구현 서브 에이전트를 파견하지 않고 Unity 구현 전체를 중단합니다.' \
        '[Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)' || return 1

    assert_document_contains_all "$developer_quickstart" "개발자 온보딩 Unity worktree Editor 게이트" \
        '`unity status --format json`의 인스턴스 `project`와 대상 물리 프로젝트 루트의 exact match' \
        '전용 Editor를 사용합니다(`bash .agents/scripts/setup/open-unity-editor.sh --project-root <물리 절대 경로>`; 이미 CLI 실패를 확인했으면 `--skip-cli`). port는 identity가 아니며 CLI가 관리합니다.' \
        '`background: editor_unavailable`' \
        '실행 루트·물리 경로를 확정할 수 없을 때만 Unity 구현을 시작하지 않습니다.' \
        '[Unity linked worktree Editor·CLI 격리](unity-worktree-cli.md)' || return 1

    assert_document_contains_all "$validation_document" "Unity worktree Editor·CLI 증거 권위" \
        '## Worktree Editor·CLI 증거 권위' \
        '모든 Unity 실행 루트는 실행 중 Editor를 사용할 때 `unity status`의 `project` exact match와 `editor_status`의 `projectPath` exact match·`status=ready`(승인된 PlayMode 관측·정지·캡처는 `playing` 허용)를 확인합니다.' \
        'linked worktree는 전용 Editor 격리를 추가로 적용합니다.' \
        '로컬 Unity Editor 컴파일과 Console 증거' \
        '다른 checkout, 메인 checkout, 다른 worktree 또는 다른 Editor의 결과' \
        'port는 identity가 아니며' \
        '상주 Editor 경로를 중단' \
        '같은 물리 경로에 대한 Unity CLI·batchmode는 우회가 아니라 백그라운드 경로이며' \
        '사용자가 현재 승인한 `unity_ci` 증거' \
        '동일 `change_id`' \
        '선택된 `build_authority`' \
        '별도 권위로 인정합니다.' \
        '[Unity linked worktree Editor·CLI 격리](../../onboarding/unity-worktree-cli.md)' || return 1

    assert_document_contains_all "$plans_readme" "실행 계획 Unity worktree Editor 게이트" \
        '`unity status --format json`의 인스턴스 `project`와 대상 물리 프로젝트 루트의 exact match' \
        '`background: editor_unavailable`' \
        '[Unity linked worktree Editor·CLI 격리](../onboarding/unity-worktree-cli.md)' \
        '3. Unity 작업이면 모든 실행 루트의 Editor identity와 차단 조건을 기록하고' \
        '5. 승인 후 Unity 작업이면 모든 실행 루트의 Editor identity를 고정하고 `editor_status`의 `ready`를 확인.' || return 1

    assert_document_contains_all "$plan_template" "실행 계획 템플릿 Unity worktree Editor 게이트" \
        '| 실행 루트 | [물리 절대 경로와 `normal_checkout`, `linked_worktree`, `submodule`, `non_git` 중 하나 또는 비-Unity·문서 작업 `N/A`] |' \
        '| Unity Editor | [`ProjectSettings/ProjectVersion.txt` 버전과 대상 Editor 상태, `linked_worktree`의 전용 상태 또는 비-Unity·문서 작업 `N/A`] |' \
        '| Editor 바인딩 | [Pipeline 인스턴스 `pid`·`port`·`version`, exact match 물리 `projectPath`, `editor_status` 결과(`status`·`compiling`·`unityVersion`) 또는 비-Unity·문서 작업 `N/A`] |' \
        '| Unity 작업 차단 | [`ready`, `background: editor_unavailable 사유`, `blocked: 실행 루트 미확정 사유` 또는 비-Unity·문서 작업 `N/A`.' \
        '`blocked`이면 Unity 구현 파일 수정 금지, `background`면 CLI·batchmode 경로로 진행' \
        'Unity 작업은 `.agents/docs/onboarding/unity-worktree-cli.md`에 따라 바인딩이 `ready` 또는 `background: editor_unavailable`인 경우에 전달합니다' \
        '`blocked`(실행 루트 미확정)에서만 Unity 구현 파일 수정을 금지합니다. `ready` 또는 `background: editor_unavailable`이면 승인된 범위로 진행하며, Pipeline 인스턴스의 port는 CLI가 관리하므로 프로젝트 파일에 port·endpoint 설정을 쓰지 않습니다.' || return 1

    return 0
}

test_docs_require_karpathy_for_all_code_and_scripts()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"
    local document_path
    local required_sentence='모든 코드 작성, 기능 구현, 리팩토링, 테스트 및 Bash·PowerShell 스크립트 작성·수정에는 karpathy-guidelines를 적용합니다.'

    for document_path in "$agents_document" "$agent_tooling_document"
    do
        grep -Fxq "$required_sentence" "$document_path" || {
            echo "Karpathy 필수 적용 문장이 정확히 없습니다: $document_path" >&2
            return 1
        }
        assert_document_contains_all "$document_path" "Karpathy 명시 적용 계약" \
            '작업 전' \
            '가정' \
            '범위' \
            '검증 기준' \
            '최소 변경' \
            '자동 네트워크 설치하지 않습니다' \
            '사용자 현재 요청 범위' \
            '미설치' \
            '작업 전에 보고' || return 1
    done

    return 0
}

test_docs_define_style_plugin_usage()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"

    assert_document_contains_all "$agent_tooling_document" "스타일 플러그인 계약" \
        'Claude Code 스타일 플러그인' \
        '`ponytail`' \
        '`i-have-adhd`' \
        'installed_plugins.json' \
        '미설치는 실패가 아니며' \
        '하네스 표준 활용 대상이 아니며' \
        '백엔드와 무관하게 적용합니다' \
        'Codex 등 다른 백엔드에 Claude 설치 JSON을 요구하지 않습니다' \
        '설치 상태, 현재 세션 활성 상태, 실제 행동 준수 증거는 구분합니다' \
        'unknown' \
        '자동 설치하지 않습니다' \
        '사용자 목표·대상·플랫폼·지정 패턴·아키텍처·승인 범위·보호 경로·검증 증거 기준을 변경하지 않습니다' || return 1
    assert_document_contains_all "$agents_document" "스타일 플러그인 진입점 계약" \
        '스타일 플러그인' \
        '외부 서비스 MCP 경계' || return 1

    return 0
}

test_docs_define_role_model_assignment()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"

    assert_document_contains_all "$agent_tooling_document" "역할별 모델 분담 계약" \
        '각 역할의 매 파견 전 사용자에게 백엔드·모델·추론 강도를 질문하고 답변으로 배정을 확인합니다' \
        '현재 작업의 배정을 하네스 기본값으로 저장하지 않습니다' \
        '대체 파견 전 사용자에게 다시 질문하고 답변으로 배정을 확인합니다' \
        '현재 작업의 Codex 내부 권장 자동 선택을 명시적으로 허용하면' \
        '역할 경계, 검증 권한과 증거 기준을 변경하지 않습니다' \
        'orca skills get orchestration' \
        '현재 설치된 orca 버전의 가이드·preamble이 우선합니다' \
        '자동 깨우기가 없는 orca 버전에서만' \
        '새 Run의 감독자·알림 수신 터미널은 사용자가 입력 중인 대화 PTY와 분리된 전용 터미널로 둡니다' \
        'headless 실패를 headed 모드나 물리 입력으로 우회하지 않습니다' \
        '역할별 에이전트·모델 분담' \
        '기계적 검수·검증 실행' \
        '증거 기준을 변경하지 않습니다' \
        'orca CLI 단일 게이트웨이' \
        '에이전트 간 통신은 Orca 오케스트레이션을 우선 사용합니다' \
        '백엔드 다양성을 제한하지 않습니다' \
        '예외 경로로 사용하고 사유를 기록합니다' \
        '선택된 채널이 컨텍스트 fork를 지원하는 조사·검토에 한해 fork를 사용할 수 있습니다.' || return 1
    assert_document_contains_all "$agents_document" "모델 계약 정본 참조와 종료 경계" \
        'docs/onboarding/agent-tooling.md' \
        '역할별 모델 분담' \
        '동일 입력·동일 실패·동일 방법의 재실행은 금지합니다' \
        '재검수는 수정한 지적과 실제 영향 범위만' \
        '서브 에이전트 호출 채널' \
        '에이전트 간 통신은 Orca 오케스트레이션을 우선 사용합니다' \
        '진행을 막는 대기만 없애며' \
        '세션을 닫거나 작업을 중단하지 않고 해결을 시도합니다' \
        '재개 방법을 확보할 수 없으면 목표를 차단하지 않고 계속 진행합니다' \
        '최우선 규칙: 차단 금지와 차단 해결' \
        '차단 금지 중에도 같은 출력을 반복하지 않습니다' \
        '이 1회 보고는 `blocked` 전환이나 승인 대기가 아니므로' \
        '차단 금지 중에는 무의미한 대기도 허용하지 않습니다' \
        '대기 대신 방안을 모색합니다' \
        '같은 제한이 3턴 이상 반복되고 가능한 진전이 없으면' \
        '원문 목표·수용 조건별로 실제 변경 파일과 동작이 어떻게 충족하는지' \
        '간소화 권고는 목표·대상·패턴을 바꾸는 권한이 아니고' \
        '변경과 관련된 기존 테스트 그룹(`--group`·`--runtime`)만 선정 이유와 함께 실행합니다' \
        '이미 통과한 검증은 새 변경·실패·미해결 우려가 없으면 반복하지 않으며' \
        'unity pipeline upgrade --project-path' \
        '실행 중인 Editor에는 창 포커스 없이 `unity command package resolve --project-path <물리 절대 경로>`로 반영한 뒤' \
        '`--headed`, `focus`·`focus-window`·`launch --activate` 등 앱·창 활성화, 전역 물리 키보드·마우스 입력은 금지합니다' \
        'Unity Game 캔버스에 접근성 노드가 없으면 승인된 Unity CLI·Pipeline 자동화를 쓰고, 그것도 없으면 `not_run`으로 기록하며 물리 입력으로 전환하지 않습니다' || return 1
    local document fixed_selection
    for document in "$agents_document" "$agent_tooling_document"; do
        for fixed_selection in 'gpt-6.1-sol' '최상위 추론 모델을 사용' '경량 모델로 재시도' '차단 금지를 지시한 작업에서는 묻지 않고 권장 모델' '모델 할당 요청으로 멈추지'; do
            assert_not_contains "$(cat "$document")" "$fixed_selection" "고정 모델 선택 정책: $document" || return 1
        done
    done

    return 0
}

test_docs_define_cli_first_principle()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"
    local unity_cli_document="$DOCS_ROOT/onboarding/unity-cli.md"

    assert_document_contains_all "$unity_cli_document" "CLI 단일 원칙 계약" \
        'CLI 단일 원칙' \
        'Unity MCP는 사용하지 않으며' \
        'Editor가 없어도 되는 작업은 배치로' \
        '`unity command`' \
        '배치만으로 완결되는 작업은 Editor 실행과 바인딩을 요구하지 않습니다' \
        'unity run <물리 경로> --command <명령>' \
        '반복 검증 루프 예외' \
        '2회차부터' \
        '도메인 리로드 시간이 눈에 띄게 증가하면' \
        'identity·격리 게이트와 증거 기준을 변경하지 않습니다' || return 1
    assert_document_contains_all "$agent_tooling_document" "Editor 준비 게이트 계약" \
        '실행 중 Editor가 필요한 작업에만 적용' \
        'CLI 단일 원칙' \
        'Unity MCP 서버·클라이언트는 설치하거나 연결하지 않습니다' \
        'unity pipeline list' || return 1
    assert_document_contains_all "$agents_document" "CLI 단일 진입점 계약" \
        'Unity 검증·빌드·실행 중 Editor 상호작용은 Unity CLI·Pipeline으로 수행합니다.' \
        'open-unity-editor.sh --project-root' \
        '--skip-cli' \
        '앱 실행 성공만으로 `ready`를 인정하지 않습니다.' \
        'Pipeline 패키지 명령은 `unity command`로 호출합니다.' \
        'Unity MCP는 사용하지 않습니다' || return 1

    return 0
}

test_docs_require_parallel_first_planning()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local parallel_work_document="$DOCS_ROOT/onboarding/parallel-work.md"

    assert_document_contains_all "$parallel_work_document" "계획 병렬화 원칙 계약" \
        '계획 단계 병렬화 원칙' \
        '항상 병렬 처리를 우선 검토' \
        '시간 단축을 계획의 기본 목표' \
        '병렬 배정을 기본' \
        '구체적 근거가 있을 때만 선택' \
        '병렬 작업이 가능한 구조' \
        '설계하는 방향을 우선' \
        '유휴 worktree 재할당을 우선' \
        '배치 Editor 1회 기동' \
        'self-claim' \
        '증거 기준을 변경하지 않습니다' \
        '별도의 생성 방식이 아니라 이 절차를 그대로 사용합니다' \
        '전체 프로젝트 복제본을 만들어 병행 작업을 등록하지 않습니다' \
        '생성·보유 개수에는 상한을 두지 않습니다' \
        '실행 중인 Unity 프로세스에만 적용되며 워크트리 생성을 제한하지 않' || return 1
    assert_document_contains_all "$agents_document" "계획 병렬화 진입점 계약" \
        '계획 단계 병렬화 원칙' \
        '병렬 처리 우선' \
        '시간 단축' || return 1

    return 0
}

test_docs_manage_troubleshooting_cases()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local troubleshooting_index="$DOCS_ROOT/troubleshooting/README.md"
    local case_file

    assert_document_contains_all "$troubleshooting_index" "트러블슈팅 색인 계약" \
        '트러블슈팅 사례 관리' \
        '## 수집 정책' \
        '원인 확정 여부와 관계없이' \
        '## 수명주기와 검증' \
        '검증하지 않은 해결안을 `verified`로 표시하지 않습니다' \
        '## RAG 데이터 형식' \
        'error_signatures' \
        '## 검색·사용 규칙' \
        'grep -ril' \
        '규칙·린트·테스트로 승격' \
        '사례 파일은 삭제하지 않습니다' \
        '## 색인' || return 1
    for case_file in \
        "$DOCS_ROOT/troubleshooting/2026-08-24-macos-awk-korean-compare.md" \
        "$DOCS_ROOT/troubleshooting/2026-08-26-korean-path-android-build.md" \
        "$DOCS_ROOT/troubleshooting/2026-08-27-editor-auto-dirty-assets.md" \
        "$DOCS_ROOT/troubleshooting/2026-08-27-harness-recopy-local-state-loss.md"
    do
        assert_document_contains_all "$case_file" "트러블슈팅 사례 양식 계약" \
            'id: ' \
            'status: ' \
            'tags: [' \
            'symptoms: [' \
            'error_signatures: [' \
            '- 증상:' \
            '- 원인:' \
            '- 해결:' \
            '- 검증:' \
            '- 재발 방지:' \
            '- 승격 상태:' || return 1
    done
    assert_document_contains_all "$troubleshooting_index" "승격 판단 기준 계약" \
        'transferable' \
        'surprising' \
        'specific' || return 1
    assert_document_contains_all "$agents_document" "트러블슈팅 진입점 계약" \
        '트러블슈팅 사례 관리' \
        '수집 정책' \
        '검색·사용 규칙' || return 1

    return 0
}

test_docs_define_wait_timeout()
{
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"

    assert_document_contains_all "$agent_tooling_document" "외부 대기 타임아웃 계약" \
        '외부 대기 타임아웃' \
        '기본 3분' \
        '트러블슈팅 사례로 기록' \
        '다른 실행 루트의 Editor는 건드리지 않습니다' \
        '무한 대기하지 않습니다' \
        '완료 이벤트 수신을 우선' || return 1
    assert_document_contains_all "$agent_tooling_document" "보조 도구 계약" \
        'graphify' \
        'grep보다 graphify 쿼리로 먼저' \
        'headroom wrap claude' \
        'graphify로 일원화' \
        '미설치 환경에서만' \
        '일반 기동으로 폴백하고 트러블슈팅 사례로 기록' \
        '증거 기준과 검증 권한을 변경하지 않습니다' || return 1

    return 0
}

test_docs_require_solid_declaration_in_plan()
{
    local plan_template="$AGENTS_ROOT/docs/exec-plans/_TEMPLATE.md"

    assert_document_contains_all "$plan_template" "SOLID 준수 선언 계약" \
        '아키텍처·SOLID 준수 선언' \
        '단일 책임·역할 경계' \
        '의존 방향' \
        '전역 상태' \
        '준수 선언 없이 구현 Task로 진행하지 않습니다' || return 1

    return 0
}

test_docs_provide_claude_native_kit()
{
    local agent_tooling_document="$DOCS_ROOT/onboarding/agent-tooling.md"
    local claude_template="$AGENTS_ROOT/templates/CLAUDE.md"

    assert_document_contains_all "$claude_template" "Claude 진입점 템플릿 계약" \
        'Claude Code 진입점' \
        '하네스 준수 (최우선 — 이탈 금지)' \
        '.agents/AGENTS.md' \
        '읽지 않은 상태로 계획·구현·검증·커밋을 진행하지 않는다' \
        '프로젝트 확정 규칙' \
        '해당 값의 하네스 기본값보다 우선' || return 1
    assert_document_contains_all "$agent_tooling_document" "Claude 적용 키트 계약" \
        'Claude Code 적용 키트' \
        'templates/CLAUDE.md' \
        '섹션만 병합' \
        'claude-settings.json' \
        '실제 hook 등록 지원과 동일 JSON 입력 계약을 확인' \
        '증거 기준을 변경하지 않습니다' || return 1

    return 0
}

check_common_business_boundary()
{
    local common_root=$1
    local relative_path
    for relative_path in AGENTS.md docs/coding-standards/core/unity-validation.md docs/exec-plans/README.md docs/exec-plans/_TEMPLATE.md
    do
        [ -f "$common_root/$relative_path" ] || return 1
        if grep -En 'validation_scope|build_not_required|exception_evidence|work-harness|reopen|delivery_change_id|ci_build_authority|change-id\.py|사전 위임 블록' "$common_root/$relative_path"; then
            echo "공통 문서에 업무 전용 상태 계약이 있습니다: $relative_path" >&2
            return 1
        fi
    done
}

test_docs_keep_business_runtime_out_of_common()
{
    local common_root="$AGENTS_ROOT"
    local copy_root="$TEST_TEMP_ROOT/common-boundary"
    local relative_path
    case "$AGENTS_ROOT" in
        */2_AI_CommonHArness/.agents) ;;
        *) common_root="$AGENTS_ROOT/../../2_AI_CommonHArness/.agents" ;;
    esac
    [ -d "$common_root" ] || return 0
    check_common_business_boundary "$common_root" || return 1
    for relative_path in AGENTS.md docs/coding-standards/core/unity-validation.md docs/exec-plans/README.md docs/exec-plans/_TEMPLATE.md
    do
        mkdir -p "$copy_root/$(dirname "$relative_path")" || return 1
        cp "$common_root/$relative_path" "$copy_root/$relative_path" || return 1
    done
    printf '%s\n' 'validation_scope=task' >> "$copy_root/docs/exec-plans/README.md"
    if check_common_business_boundary "$copy_root" >/dev/null 2>&1; then
        echo "업무 전용 문구 주입을 공통 문서 경계 검사에서 놓쳤습니다." >&2
        return 1
    fi
    cp "$common_root/docs/exec-plans/README.md" "$copy_root/docs/exec-plans/README.md" || return 1
    printf '%s\n' 'change-id.py' >> "$copy_root/docs/exec-plans/README.md"
    if check_common_business_boundary "$copy_root" >/dev/null 2>&1; then
        echo "업무 change-id 구현 문구 주입을 놓쳤습니다." >&2
        return 1
    fi
    cp "$common_root/docs/exec-plans/README.md" "$copy_root/docs/exec-plans/README.md" || return 1
    printf '%s\n' '사전 위임 블록' >> "$copy_root/AGENTS.md"
    if check_common_business_boundary "$copy_root" >/dev/null 2>&1; then
        echo "공통 AGENTS의 업무 사전 위임 문구 주입을 놓쳤습니다." >&2
        return 1
    fi
}

test_hooks_protect_agents_dir()
{
    local hook_script="$AGENTS_ROOT/scripts/hooks/protect-agents-dir.sh"
    local settings_template="$AGENTS_ROOT/templates/claude-settings.json"
    local status

    assert_document_contains_all "$hook_script" "하네스 보호 hook 계약" \
        '보호 필터 동기화' \
        'exit 2' \
        'harness-recopy-local-state-loss' || return 1
    assert_document_contains_all "$settings_template" "hook 설정 템플릿 계약" \
        'PreToolUse' \
        'protect-agents-dir.sh' || return 1

    status=0
    printf '%s' '{"tool_input":{"command":"rm -rf .agents"}}' | bash "$hook_script" >/dev/null 2>&1 || status=$?
    [ "$status" -eq 2 ] || { echo ".agents 삭제 명령이 차단되지 않았습니다(exit=$status)." >&2; return 1; }

    status=0
    printf '%s' '{"tool_input":{"command":"ls .agents/docs"}}' | bash "$hook_script" >/dev/null 2>&1 || status=$?
    [ "$status" -eq 0 ] || { echo "무해한 .agents 조회가 오차단되었습니다(exit=$status)." >&2; return 1; }

    status=0
    printf '%s' '{"tool_input":{"command":"rm -rf /tmp/scratch-dir"}}' | bash "$hook_script" >/dev/null 2>&1 || status=$?
    [ "$status" -eq 0 ] || { echo ".agents 무관 rm이 오차단되었습니다(exit=$status)." >&2; return 1; }

    local case_root="$TEST_TEMP_ROOT/hook-project"
    local entry expected actual
    mkdir -p "$case_root/.agents/work-items/active" "$case_root/.agents/reports" "$case_root/.agents/scripts/hooks"
    cp "$hook_script" "$case_root/.agents/scripts/hooks/protect-agents-dir.sh"
    cp "$AGENTS_ROOT/scripts/hooks/protect-agents-dir.py" "$case_root/.agents/scripts/hooks/protect-agents-dir.py"
    cp -p "$AGENTS_ROOT/scripts/hooks/shell_cst.py" "$case_root/.agents/scripts/hooks/shell_cst.py" || return 1
    cp -Rp "$AGENTS_ROOT/scripts/hooks/shell-parser" "$case_root/.agents/scripts/hooks/shell-parser" || return 1
    hook_script="$case_root/.agents/scripts/hooks/protect-agents-dir.sh"
    mkdir -p "$case_root/external"
    ln -s "$case_root/external" "$case_root/.agents/link"
    ln -s "$case_root/.agents/scripts" "$case_root/.agents/reports/managed"
    while IFS='|' read -r expected entry; do
        [ -n "$expected" ] || continue
        actual=0
        (cd "$case_root" && printf '%s' "$entry" | bash "$hook_script" >/dev/null 2>&1) || actual=$?
        [ "$actual" -eq "$expected" ] || { echo "hook 판정 오류: 기대=$expected 실제=$actual 입력=$entry" >&2; return 1; }
    done <<'CASES'
2|{"tool_name":"Bash","tool_input":{"command":"/bin/rm -rf .agents/find"}}
2|{"tool_name":"Bash","tool_input":{"command":"mv '.agents' /tmp/x"}}
2|{"tool_name":"Bash","tool_input":{"command":"find .agents -delete"}}
2|{"tool_name":"Bash","tool_input":{"command":"git clean -fdx .agents"}}
2|{"tool_name":"Bash","tool_input":{"command":"git -C . clean -fdx .agents"}}
2|{"tool_name":"Bash","tool_input":{"command":"git -C .agents clean -fdx scripts"}}
2|{"tool_name":"Bash","tool_input":{"command":"cd .agents && rm -rf scripts"}}
2|{"tool_name":"Bash","tool_input":{"command":"cd .. && rm -rf hook-project"}}
2|{"tool_name":"Bash","tool_input":{"cwd":".agents","command":"rm -rf scripts"}}
2|{"tool_name":"Bash","cwd":".agents","tool_input":{"command":"rm -rf scripts"}}
2|{"tool_name":"Bash","tool_input":{"command":"rm .agents -rf"}}
2|{"tool_name":"Bash","tool_input":{"command":"rm -rf .agent[s]"}}
2|{"tool_name":"Bash","tool_input":{"command":"D=.agents; rm -rf \"$D\""}}
2|{"tool_name":"Bash","tool_input":{"command":"bash -c 'rm -rf .agents'"}}
2|{"tool_name":"Bash","tool_input":{"command":"rsync -a --delete source/ .agents/"}}
2|{"tool_name":"Bash","tool_input":{"command":"rsync -a /tmp/input .agents/scripts/"}}
2|{"tool_name":"Bash","tool_input":{"command":"rsync -a --delete --filter='P reports/' source/ .agents/"}}
2|{"tool_name":"Bash","tool_input":{"command":"rsync -a --delete-excluded --exclude=reports/ source/ .agents/"}}
2|{"tool_name":"Bash","tool_input":{"command":"rsync -a --delete --include=reports/ --exclude=config/project-profile.conf --exclude=reports/ --exclude=work-items/ --exclude=artifacts/ --exclude=docs/exec-plans/ --exclude=docs/product-specs/ --exclude=docs/troubleshooting/ source/ .agents/"}}
2|{"tool_name":"Bash","tool_input":{"command":"rm -rf ."}}
2|{"tool_name":"Bash","tool_input":{"command":"echo done > .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"> .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"echo ok >& .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"printf done >> .agents/scripts/config.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"sed -i '' 's/a/b/' .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"echo ok\nsed -i '' 's/a/b/' .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"cp /tmp/input .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"cp -t .agents/scripts /tmp/input"}}
2|{"tool_name":"Bash","tool_input":{"command":"cp -t.agents/scripts /tmp/input"}}
2|{"tool_name":"Bash","tool_input":{"command":"install /tmp/input .agents/scripts/config.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"tee .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"mv /tmp/input .agents/scripts/config.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"mv --target-directory=.agents/scripts /tmp/input"}}
2|{"tool_name":"Bash","tool_input":{"command":"perl -pi -e 's/x/y/' .agents/work-items/active/TASK-1.conf"}}
2|{"tool_name":"Bash","tool_input":{"command":"python3 -c 'open(\".agents/work-items/active/TASK-1.conf\",\"w\").write(\"x\")'"}}
2|{"tool_name":"Bash","tool_input":{"command":"python3 -c 'from pathlib import Path; Path(\".agents/scripts/config.conf\").write_text(\"x\")'"}}
2|{"tool_name":"Write","tool_input":{"file_path":".agents/work-items/active/TASK-1.conf","content":"status=done"}}
2|{"tool_name":"Edit","tool_input":{"file_path":".agents/AGENTS.md","old_string":"x","new_string":"y"}}
2|{"tool_name":"Write","tool_input":{"file_path":".agents/link/AGENTS.md","content":"x"}}
2|{"tool_name":"Write","tool_input":{"file_path":".agents/reports/managed/protect-agents-dir.sh","content":"x"}}
2|{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: .agents/scripts/hooks/protect-agents-dir.sh\n@@\n-x\n+y\n*** End Patch"}}
2|{"tool_name":"apply_patch","tool_input":{"patch":"*** Begin Patch\n*** Update File: note.md\n*** Move to: .agents/AGENTS.md\n*** End Patch"}}
2|{"tool_name":"Bash","tool_input":{}}
0|{"tool_name":"Write","tool_input":{"file_path":".agents/reports/check.md","content":"ok"}}
0|{"tool_name":"Write","tool_input":{"file_path":".agents/work-items/evidence/TASK-1/revision-1.conf","content":"ok"}}
0|{"tool_name":"Bash","tool_input":{"command":"bash .agents/scripts/workflow/work-harness.sh start --project-root . --task TASK-1"}}
0|{"tool_name":"Bash","tool_input":{"command":"find .agents/docs -type f"}}
0|{"tool_name":"Bash","tool_input":{"command":"echo rm -rf .agents"}}
0|{"tool_name":"Bash","tool_input":{"command":"echo 'text > .agents/work-items/active/TASK-1.conf'"}}
0|{"tool_name":"Bash","tool_input":{"command":"echo '>' .agents/work-items/active/TASK-1.conf"}}
0|{"tool_name":"Bash","tool_input":{"command":"echo '>&' .agents/work-items/active/TASK-1.conf"}}
0|{"tool_name":"Bash","tool_input":{"command":"python3 -c 'open(\".agents/AGENTS.md\").read()'"}}
0|{"tool_name":"Bash","tool_input":{"command":"perl -ne 'print' .agents/AGENTS.md"}}
0|{"tool_name":"Bash","tool_input":{"command":"perl -MFile::Find -e 'print' .agents/AGENTS.md"}}
0|{"tool_name":"Bash","tool_input":{"command":"echo 'python3 -c open(.agents/AGENTS.md,w)'"}}
0|{"tool_name":"Bash","tool_input":{"command":"echo done > .agents/reports/check.md"}}
0|{"tool_name":"Bash","tool_input":{"command":"cp /tmp/input .agents/work-items/evidence/TASK-1/proof.md"}}
0|{"tool_name":"Bash","tool_input":{"command":"mv /tmp/input .agents/reports/check.md"}}
0|{"tool_name":"Read","tool_input":{"file_path":".agents/AGENTS.md"}}
0|{"tool_name":"Bash","tool_input":{"command":"rsync -a --delete --exclude=config/project-profile.conf --exclude=reports/ --exclude=work-items/ --exclude=artifacts/ --exclude=docs/exec-plans/ --exclude=docs/product-specs/ --exclude=docs/troubleshooting/ source/ .agents/"}}
0|{"tool_name":"Bash","tool_input":{"command":"rsync -a --exclude=config/project-profile.conf --exclude=reports/ --exclude=work-items/ --exclude=artifacts/ --exclude=docs/exec-plans/ --exclude=docs/product-specs/ --exclude=docs/troubleshooting/ source/ .agents/"}}
0|{"tool_name":"Bash","tool_input":{"command":"rsync -a --delete --filter='H config/project-profile.conf' --filter='P config/project-profile.conf' --filter='H reports/' --filter='P reports/' --filter='H work-items/' --filter='P work-items/' --filter='H artifacts/' --filter='P artifacts/' --filter='H docs/exec-plans/' --filter='P docs/exec-plans/' --filter='H docs/product-specs/' --filter='P docs/product-specs/' --filter='H docs/troubleshooting/' --filter='P docs/troubleshooting/' source/ .agents/"}}
0|{"tool_name":"Bash","tool_input":{"command":"rm -rf /tmp/scratch-dir"}}
2|{bad json
CASES

    entry=$(printf '{"tool_name":"Bash","tool_input":{"command":"/bin/rm -rf %s/.agents"}}' "$case_root")
    actual=0
    (cd "$case_root" && printf '%s' "$entry" | bash "$hook_script" >/dev/null 2>&1) || actual=$?
    [ "$actual" -eq 2 ] || { echo "절대경로 .agents 삭제가 차단되지 않았습니다(exit=$actual)." >&2; return 1; }

    entry=$(printf '{"tool_name":"Write","tool_input":{"file_path":"%s/.agents/config/project-profile.conf","content":"x"}}' "$case_root")
    actual=0
    (cd "$case_root" && printf '%s' "$entry" | bash "$hook_script" >/dev/null 2>&1) || actual=$?
    [ "$actual" -eq 2 ] || { echo "절대경로 관리 파일 쓰기가 차단되지 않았습니다(exit=$actual)." >&2; return 1; }

    python3 "$AGENTS_ROOT/tests/test-protect-agents-dir.py" || return 1
    return 0
}

test_docs_require_harness_compliance_report()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"

    assert_document_contains_all "$agents_document" "하네스 준수 보고 계약" \
        '하네스 핵심 규칙 준수 여부' \
        'CLI 우선 실행' \
        '서브 에이전트 호출 채널' \
        '병렬 우선 계획' \
        '트러블슈팅 기록' \
        '백엔드와 무관하게' \
        '직접 다시 읽고 적용' \
        '전달 패킷 수신은 하네스 직접 재독을 대체하지 않습니다' || return 1

    return 0
}

test_docs_core_has_no_fixed_profile_assumptions()
{
    local core_directory="$DOCS_ROOT/coding-standards/core"
    local disguised_fixture="$TEST_TEMP_ROOT/disguised-fixed-assumption.md"
    local disguised_assumption

    if [ ! -d "$core_directory" ]; then
        echo "Core 문서 디렉터리가 없습니다: $core_directory" >&2
        return 1
    fi

    for disguised_assumption in \
        '모든 프로젝트의 아키텍처는 MVVM이어야 합니다.' \
        'VContainer만 사용합니다.' \
        '기본 렌더 파이프라인은 URP입니다.' \
        '소스 루트는 반드시 Assets/Scripts를 사용합니다.' \
        'All projects must use MVVM.' \
        'VContainer is required.' \
        'URP is the default pipeline.' \
        'Assets/Scripts is the standard source root.'
    do
        printf '%s\n' "$disguised_assumption" > "$disguised_fixture"
        if assert_no_fixed_profile_assumptions "$disguised_fixture" >/dev/null 2>&1; then
            echo "고정 전제 탐지기가 위장 표현을 놓쳤습니다: $disguised_assumption" >&2
            return 1
        fi
    done

    assert_no_fixed_profile_assumptions "$core_directory"
}

test_docs_route_every_profile_enum_branch()
{
    local architecture_directory="$DOCS_ROOT/profiles/architecture"
    local architecture_principles="$DOCS_ROOT/coding-standards/core/architecture-principles.md"
    local naming_document="$DOCS_ROOT/coding-standards/core/naming-and-documentation.md"
    local architecture_file
    local required_heading

    assert_schema_enum_values_documented profile_version "$architecture_principles" || return 1
    assert_schema_enum_values_documented confirmation_status "$architecture_principles" || return 1
    assert_schema_enum_values_documented architecture "$architecture_directory" || return 1
    assert_schema_enum_values_documented dependency_injection "$DOCS_ROOT/profiles/dependency-injection.md" || return 1
    assert_schema_enum_values_documented async_backend "$DOCS_ROOT/profiles/async.md" || return 1
    assert_schema_enum_values_documented tween_backend "$DOCS_ROOT/profiles/tween.md" || return 1
    assert_schema_enum_values_documented render_pipeline "$DOCS_ROOT/profiles/rendering.md" || return 1
    assert_schema_enum_values_documented response_language "$naming_document" || return 1
    assert_schema_enum_values_documented log_language "$naming_document" || return 1
    assert_schema_enum_values_documented region_policy "$naming_document" || return 1
    assert_schema_enum_values_documented xml_documentation_policy "$naming_document" || return 1
    assert_schema_enum_values_documented gpu_resident_drawer "$DOCS_ROOT/coding-standards/optimization/rendering-techniques.md" || return 1
    assert_schema_enum_values_documented gpu_occlusion_culling "$DOCS_ROOT/coding-standards/optimization/rendering-techniques.md" || return 1
    assert_schema_enum_values_documented stp "$DOCS_ROOT/coding-standards/optimization/rendering-techniques.md" || return 1
    assert_schema_enum_values_documented mesh_lod "$DOCS_ROOT/coding-standards/optimization/rendering-techniques.md" || return 1

    assert_h2_section_contains_all "$architecture_principles" '## 프로필 적용 경계' "profile_version 행위" \
        '스키마 버전 값' '`1`' '기록합니다' || return 1
    assert_h2_section_contains_all "$architecture_principles" '## 프로필 적용 경계' "pending 행위" \
        '`pending`' '진단' || return 1
    assert_h2_section_contains_all "$architecture_principles" '## 프로필 적용 경계' "confirmed 행위" \
        '`confirmed`' '차단 규칙' '적용합니다' || return 1

    assert_markdown_table_row_contains_all "$naming_document" '`response_language`' "response_language enum" \
        '`ko`' '`en`' '`project_default`' '| `ko` |' || return 1
    assert_markdown_table_row_contains_all "$naming_document" '`log_language`' "log_language enum" \
        '`ko`' '`en`' '`project_default`' '| `ko` |' || return 1
    assert_markdown_table_row_contains_all "$naming_document" '`region_policy`' "region_policy enum" \
        '`required`' '`encouraged`' '`disabled`' || return 1
    assert_markdown_table_row_contains_all "$naming_document" '`xml_documentation_policy`' "xml_documentation_policy enum" \
        '`all_methods`' '`public_api`' '`disabled`' || return 1

    assert_h2_section_contains_all "$naming_document" '## 리전 정책' "region required 행위" \
        '`required`' '작성하고 검사합니다' || return 1
    assert_h2_section_contains_all "$naming_document" '## 리전 정책' "region encouraged 행위" \
        '`encouraged`' '도움이 될 때 사용합니다' || return 1
    assert_h2_section_contains_all "$naming_document" '## 리전 정책' "region disabled 행위" \
        '`disabled`' '새 리전을 만들지 않으며' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "xml all_methods 행위" \
        '`all_methods`' '모든 메서드' '작성합니다' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "xml public_api 행위" \
        '`public_api`' 'public/protected API' '문서화합니다' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "xml disabled 행위" \
        '`disabled`' '강제하지 않되' || return 1

    for architecture_file in mvvm.md mvp.md mvc.md layered-clean.md custom.md
    do
        for required_heading in \
            '## 책임' \
            '## 허용 의존 방향' \
            '## 금지 의존 방향' \
            '## 감지 증거' \
            '## 검사 ID' \
            '## VContainer 비의존 예시'
        do
            grep -Fq "$required_heading" "$architecture_directory/$architecture_file" || {
                echo "아키텍처 프로필 필수 섹션이 없습니다: $architecture_file ($required_heading)" >&2
                return 1
            }
        done
    done

    return 0
}

test_docs_core_semantic_contracts()
{
    local core_directory="$DOCS_ROOT/coding-standards/core"

    assert_h2_section_contains_all "$core_directory/architecture-principles.md" '## Pure C#과 SOLID' "Pure C# 경계" \
        '비즈니스 규칙, 계산과 지속 상태' '반드시' 'Pure C#' || return 1
    assert_h2_section_contains_all "$core_directory/architecture-principles.md" '## Pure C#과 SOLID' "Unity 어댑터 경계" \
        'Unity 어댑터' '표현, 입력과 수명주기로 한정' || return 1
    assert_h2_section_contains_all "$core_directory/architecture-principles.md" '## Pure C#과 SOLID' "인터페이스 의존" \
        '고수준 정책' '구체 구현' '인터페이스에 의존' || return 1
    assert_h2_section_contains_all "$core_directory/architecture-principles.md" '## 전역 상태 금지' "No Singleton" \
        'Singleton' '사용하지 않습니다' || return 1
    assert_h2_section_contains_all "$core_directory/architecture-principles.md" '## 변경 승인과 서드파티 경계' "명시적 승인" \
        '명시적 승인 전' '수정하지 않습니다' || return 1
    assert_h2_section_contains_all "$core_directory/architecture-principles.md" '## 변경 승인과 서드파티 경계' "서드파티 원본 보호" \
        'UPM 패키지와 에셋 스토어 원본' '직접 수정하지 않습니다' || return 1

    assert_h2_section_contains_all "$core_directory/naming-and-documentation.md" '## 프로필이 결정하는 값' "프로필 기본 제안" \
        '`m_`' '`func_`' '한글 응답·로그' '`윤승종`' '기본 제안값' || return 1

    assert_h2_section_contains_all "$core_directory/runtime-performance.md" '## 프레임 경로' "프레임 할당" \
        '`Update`' '`LateUpdate`' '`FixedUpdate`' '관리 힙 할당' 'Boxing' 'LINQ' || return 1
    assert_h2_section_contains_all "$core_directory/runtime-performance.md" '## 캐싱' "캐싱 경계" \
        '고빈도 경로' '캐싱합니다' || return 1
    assert_h2_section_contains_all "$core_directory/runtime-performance.md" '## 풀링' "풀링 경계" \
        '반복 생성·파괴' 'Object Pool' '검토합니다' || return 1
    assert_h2_section_contains_all "$core_directory/runtime-performance.md" '## 측정 순서' "측정 우선" \
        'CPU' 'GPU' '메모리' 'GC' '기준값' || return 1

    assert_h2_section_contains_all "$core_directory/unity-safety.md" '## Fake Null' "Fake Null 연산자" \
        'UnityEngine.Object' 'Fake Null' '`?.`' '`??`' || return 1
    assert_h2_section_contains_all "$core_directory/unity-safety.md" '## 직렬화 변경' "직렬화 이름 변경" \
        '직렬화되는 public 필드' 'FormerlySerializedAs' || return 1
    assert_h2_section_contains_all "$core_directory/unity-safety.md" '## 이벤트와 수명' "이벤트 구독 해제" \
        'C# 이벤트' '구독' '해제' || return 1
}

test_docs_section_contract_helper_rejects_mutations()
{
    local fixture_path="$TEST_TEMP_ROOT/section-contract-mutation.md"

    printf '%s\n' \
        '# Fixture' \
        '## 대상 계약' \
        '실제 대상 본문입니다.' \
        '## 다른 계약' \
        '소유자는 작업을 취소하고 수명 종료 시 정리합니다.' \
        > "$fixture_path"
    if assert_h2_section_contains_all "$fixture_path" '## 대상 계약' "다른 H2 이동 mutation" \
        '소유자' '취소' '수명 종료 시 정리' >/dev/null 2>&1; then
        echo "섹션 helper가 다른 H2로 이동한 요구 토큰을 허용했습니다." >&2
        return 1
    fi

    printf '%s\n' \
        '# Fixture' \
        '## 대상 계약' \
        '## 다음 계약' \
        '소유자는 작업을 취소하고 수명 종료 시 정리합니다.' \
        > "$fixture_path"
    if assert_h2_section_contains_all "$fixture_path" '## 대상 계약' "빈 섹션 mutation" \
        '소유자' '취소' '수명 종료 시 정리' >/dev/null 2>&1; then
        echo "섹션 helper가 빈 대상 섹션을 허용했습니다." >&2
        return 1
    fi

    printf '%s\n' \
        '# Fixture' \
        '## 대상 계약' \
        '- 용어 목록: 소유자' \
        '- 무관한 메모: 취소' \
        '- 설명 없는 토큰: 수명 종료 시 정리' \
        '## 다음 계약' \
        > "$fixture_path"
    if assert_h2_section_contains_all "$fixture_path" '## 대상 계약' "토큰 샐러드 mutation" \
        '소유자' '취소' '수명 종료 시 정리' >/dev/null 2>&1; then
        echo "섹션 helper가 무관한 토큰 샐러드를 의미 계약으로 허용했습니다." >&2
        return 1
    fi

    printf '%s\n' \
        '# Fixture' \
        '## 대상 계약' \
        '작업 소유자는 수명 종료 시 작업을 취소하고 자원을 정리합니다.' \
        '## 다음 계약' \
        > "$fixture_path"
    assert_h2_section_contains_all "$fixture_path" '## 대상 계약' "정상 의미 계약" \
        '소유자' '취소' '수명 종료 시' '정리' || return 1
}

test_docs_enum_branch_helper_rejects_unbounded_tokens()
{
    local fixture_path="$TEST_TEMP_ROOT/enum-branch-mutation.md"

    printf '%s\n' \
        '# 비동기 프로필 Fixture' \
        '## 메모' \
        '`unitask`, `coroutine`, `task`, `mixed`, `unknown` 문자열만 나열합니다.' \
        > "$fixture_path"

    if assert_schema_enum_values_documented async_backend "$fixture_path" >/dev/null 2>&1; then
        echo "enum helper가 전용 H2 없는 토큰 나열을 분기 문서로 허용했습니다." >&2
        return 1
    fi
}

test_docs_architecture_direction_helper_rejects_reverse_flow()
{
    local fixture_path="$TEST_TEMP_ROOT/direction-mutation.md"

    printf '%s\n' \
        '# MVVM Fixture' \
        '## 허용 의존 방향' \
        '허용 의존 방향은 `Model → ViewModel → View`입니다.' \
        '## 금지 의존 방향' \
        'View가 Model을 직접 참조하는 방향을 금지합니다.' \
        > "$fixture_path"

    if assert_architecture_allowed_direction "$fixture_path" mvvm >/dev/null 2>&1; then
        echo "아키텍처 방향 helper가 MVVM 역방향 흐름을 허용했습니다." >&2
        return 1
    fi
}

test_docs_cleanup_helpers_reject_negative_contracts()
{
    local async_fixture="$TEST_TEMP_ROOT/async-negative-mutation.md"
    local tween_fixture="$TEST_TEMP_ROOT/tween-negative-mutation.md"

    printf '%s\n' \
        '# Async Fixture' \
        '## 공통 수명 원칙' \
        '작업 소유자는 수명 종료에도 작업을 취소하지 않고 예외를 관찰하지 않습니다.' \
        > "$async_fixture"
    if assert_async_lifecycle_contract "$async_fixture" >/dev/null 2>&1; then
        echo "비동기 helper가 취소하지 않는 부정 계약을 허용했습니다." >&2
        return 1
    fi

    printf '%s\n' \
        '# Tween Fixture' \
        '## `dotween`' \
        'OnDestroy에서도 실행 중 트윈을 Kill하지 않습니다.' \
        > "$tween_fixture"
    if assert_tween_cleanup_contract "$tween_fixture" >/dev/null 2>&1; then
        echo "트윈 helper가 Kill하지 않는 부정 계약을 허용했습니다." >&2
        return 1
    fi
}

test_docs_compatibility_route_helper_rejects_split_pairs()
{
    local fixture_path="$TEST_TEMP_ROOT/compatibility-route-mutation.md"

    printf '%s\n' \
        '# 호환 Fixture' \
        '| 기존 내용 | 새 위치 |' \
        '|---|---|' \
        '| MVVM 책임 | [잘못된 문서](core/runtime-performance.md) |' \
        '| 다른 내용 | [우연히 존재하는 링크](../profiles/architecture/mvvm.md) |' \
        > "$fixture_path"

    if assert_compatibility_route "$fixture_path" 'MVVM 책임' '../profiles/architecture/mvvm.md' >/dev/null 2>&1; then
        echo "호환 라우팅 helper가 서로 다른 행의 항목과 링크를 한 쌍으로 허용했습니다." >&2
        return 1
    fi
}

test_docs_architecture_sections_have_semantic_contracts()
{
    local architecture_directory="$DOCS_ROOT/profiles/architecture"
    local architecture_file
    local architecture_name
    local example_path="$TEST_TEMP_ROOT/task6-architecture-example.txt"
    local example_size

    for architecture_file in mvvm.md mvp.md mvc.md layered-clean.md custom.md
    do
        case "$architecture_file" in
            mvvm.md)
                architecture_name=mvvm
                ;;
            mvp.md)
                architecture_name=mvp
                ;;
            mvc.md)
                architecture_name=mvc
                ;;
            layered-clean.md)
                architecture_name=layered_clean
                ;;
            custom.md)
                architecture_name=custom
                ;;
        esac

        assert_architecture_allowed_direction "$architecture_directory/$architecture_file" "$architecture_name" || return 1

        extract_markdown_h2_section "$architecture_directory/$architecture_file" '## VContainer 비의존 예시' "$example_path" || return 1
        example_size=$(wc -c < "$example_path" | tr -d ' ')
        if [ "$example_size" -lt 200 ]; then
            echo "VContainer 비의존 예시 본문이 충분하지 않습니다: $architecture_file ($example_size bytes)" >&2
            return 1
        fi
        grep -Fq '```csharp' "$example_path" || {
            echo "VContainer 비의존 예시에 C# 본문이 없습니다: $architecture_file" >&2
            return 1
        }
        if grep -Eq 'LifetimeScope|IContainerBuilder|Register(Component|EntryPoint|Instance|<)' "$example_path"; then
            echo "VContainer 비의존 예시에 컨테이너 전용 API가 있습니다: $architecture_file" >&2
            return 1
        fi
    done

    assert_h2_section_contains_all "$architecture_directory/custom.md" '## 책임' "Custom 축소 범위" \
        '일반 아키텍처 전용 검사만' 'Core 규칙' 'Optimization Base' '그대로 적용합니다' || return 1
    assert_h2_section_contains_all "$DOCS_ROOT/coding-standards/core/architecture-principles.md" '## 프로필 적용 경계' "Custom 축소 범위" \
        '일반 아키텍처 전용 검사만' 'Optimization Base' '그대로 적용합니다' || return 1
    assert_h2_section_contains_all "$DOCS_ROOT/coding-standards/optimization/general-techniques.md" '## 물리' "Mesh Collider 조건" \
        'Non-convex Mesh Collider는 정적 지오메트리 또는 kinematic Rigidbody에만' 'non-kinematic Rigidbody에는 붙일 수 없습니다' || return 1
    assert_h2_section_contains_all "$DOCS_ROOT/coding-standards/optimization/general-techniques.md" '## 물리' "Convex Mesh Collider 동적 허용" \
        'Convex Mesh Collider는' 'non-kinematic(동적) Rigidbody에도' || return 1
    assert_h2_section_contains_all "$DOCS_ROOT/coding-standards/optimization/rendering-techniques.md" '## 2. GPU Occlusion Culling' "URP GPU Occlusion 절차" \
        'Render Graph Disabled' 'GPU Resident Drawer' 'GPU Occlusion' || return 1
    assert_h2_section_contains_all "$architecture_directory/custom.md" '## 검사 ID' "Custom 검사" \
        '`MVVM001`' '`MVP001`' '`MVC001`' '`LAYER001`' '강제하지 않습니다' || return 1
    assert_h2_section_contains_all "$architecture_directory/mvp.md" '## VContainer 비의존 예시' "MVP View 인터페이스" \
        'public interface IPlayerView' || return 1
    assert_h2_section_contains_all "$architecture_directory/mvp.md" '## VContainer 비의존 예시' "MVP Model 인터페이스" \
        'public interface IPlayerModel' || return 1
    assert_h2_section_contains_all "$architecture_directory/mvp.md" '## VContainer 비의존 예시' "MVP 인터페이스 의존 필드" \
        'private readonly IPlayerModel' 'm_model' || return 1
}

test_docs_technical_profiles_have_lifecycle_contracts()
{
    local profiles_directory="$DOCS_ROOT/profiles"

    assert_async_lifecycle_contract "$profiles_directory/async.md" || return 1
    assert_tween_cleanup_contract "$profiles_directory/tween.md" || return 1
    assert_h2_section_contains_all "$profiles_directory/tween.md" '## `leantween`' "LeanTween 파괴 정리" \
        '파괴' '취소' || return 1
    assert_h2_section_contains_all "$profiles_directory/tween.md" '## `custom`' "Custom 트윈 파괴 정리" \
        '파괴' '취소' || return 1
    assert_h2_section_contains_all "$profiles_directory/rendering.md" '## `unknown`' "렌더링 최적화 라우팅" \
        '[조건부 렌더링 최적화 베이스](../coding-standards/optimization/rendering-techniques.md)' || return 1
}

test_docs_compatibility_preserves_rules_and_xml_templates()
{
    local standards_directory="$DOCS_ROOT/coding-standards"
    local naming_document="$standards_directory/core/naming-and-documentation.md"

    assert_compatibility_route "$standards_directory/architecture-rules.md" 'SOLID, Pure C#, No Singleton' 'core/architecture-principles.md' || return 1
    assert_compatibility_route "$standards_directory/architecture-rules.md" 'DTO 씬 전환' 'core/architecture-principles.md' || return 1
    assert_compatibility_route "$standards_directory/architecture-rules.md" 'Model·ViewModel·View 책임' '../profiles/architecture/mvvm.md' || return 1
    assert_compatibility_route "$standards_directory/architecture-rules.md" 'Presenter·Controller·Layered/Clean·Custom 경계' '../profiles/architecture/' || return 1
    assert_compatibility_route "$standards_directory/architecture-rules.md" 'LifetimeScope, View·Service·EntryPoint' '../profiles/dependency-injection.md' || return 1
    assert_compatibility_route "$standards_directory/architecture-rules.md" '이름, 한글 로그, XML 문서' 'core/naming-and-documentation.md' || return 1

    assert_compatibility_route "$standards_directory/naming-conventions.md" 'private/public/인터페이스/DTO/bool' 'core/naming-and-documentation.md' || return 1
    assert_compatibility_route "$standards_directory/naming-conventions.md" '`m_`, `func_`, 한글, `윤승종`' 'core/naming-and-documentation.md' || return 1
    assert_compatibility_route "$standards_directory/naming-conventions.md" 'Allman Style, 공백 4칸, using·별칭' 'core/naming-and-documentation.md' || return 1
    assert_compatibility_route "$standards_directory/naming-conventions.md" '한글 리전 예시와 기존 주석 보존' 'core/naming-and-documentation.md' || return 1
    assert_compatibility_route "$standards_directory/naming-conventions.md" '`[클래스명]` 로그와 XML 헤더' 'core/naming-and-documentation.md' || return 1

    assert_compatibility_route "$standards_directory/performance-rules.md" '프레임 루프 할당·LINQ·Boxing' 'core/runtime-performance.md' || return 1
    assert_compatibility_route "$standards_directory/performance-rules.md" '캐싱, Object Pool과 측정 우선' 'core/runtime-performance.md' || return 1
    assert_compatibility_route "$standards_directory/performance-rules.md" 'UniTask 예제, Coroutine·Task·Mixed' '../profiles/async.md' || return 1
    assert_compatibility_route "$standards_directory/performance-rules.md" 'DOTween 예제와 파괴 시 Kill' '../profiles/tween.md' || return 1
    assert_compatibility_route "$standards_directory/performance-rules.md" 'GPU 기반 네 가지 조건부 기법' 'optimization/rendering-techniques.md' || return 1

    assert_compatibility_route "$standards_directory/safety-rules.md" 'Fake Null과 명시적 Unity null 비교' 'core/unity-safety.md' || return 1
    assert_compatibility_route "$standards_directory/safety-rules.md" '`FormerlySerializedAs`와 직렬화 변경' 'core/unity-safety.md' || return 1
    assert_compatibility_route "$standards_directory/safety-rules.md" '`UnityEvent`, C# 이벤트 구독·해제' 'core/unity-safety.md' || return 1
    assert_compatibility_route "$standards_directory/safety-rules.md" 'Wrapper, Adapter, 확장 메서드' 'core/architecture-principles.md' || return 1

    assert_compatibility_route "$standards_directory/unity-specific.md" 'GPU Resident Drawer 원리·설정·검증·롤백' 'optimization/rendering-techniques.md' || return 1
    assert_compatibility_route "$standards_directory/unity-specific.md" 'GPU Occlusion Culling 투패스·Hi-Z·적용 기준' 'optimization/rendering-techniques.md' || return 1
    assert_compatibility_route "$standards_directory/unity-specific.md" 'STP, TAA, Render Scale, Motion Vectors' 'optimization/rendering-techniques.md' || return 1
    assert_compatibility_route "$standards_directory/unity-specific.md" 'Mesh LOD, QEM, 버전별 기본 LOD·cross-fade 조건' 'optimization/rendering-techniques.md' || return 1
    assert_compatibility_route "$standards_directory/unity-specific.md" 'URP·HDRP·Built-in·Custom·Unknown 분기' '../profiles/rendering.md' || return 1

    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "XML 기능 템플릿" '[기능]:' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "XML 작성자 템플릿" '[작성자]:' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "XML 수정 날짜 템플릿" '[수정 날짜]:' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "XML 마지막 작성자 템플릿" '[마지막 수정 작성자]:' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "XML 수정 내용 템플릿" '[수정 내용]:' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "XML 클래스 템플릿" 'public class' || return 1
    assert_h2_section_contains_all "$naming_document" '## XML 문서 정책' "XML 메서드 템플릿" 'public void' || return 1
}

test_docs_stp_preserves_operational_guidance()
{
    local optimization_document="$DOCS_ROOT/coding-standards/optimization/rendering-techniques.md"

    assert_h2_section_contains_all "$optimization_document" '## 3. STP (Spatial-Temporal Post-processing)' "STP 플랫폼 최적화" \
        '플랫폼별 자동 최적화' || return 1
    assert_h2_section_contains_all "$optimization_document" '## 3. STP (Spatial-Temporal Post-processing)' "STP Flickering 처방" \
        '알파 클리핑' '알파 블렌딩' || return 1
    assert_h2_section_contains_all "$optimization_document" '## 3. STP (Spatial-Temporal Post-processing)' "STP 저사양 모바일 처방" \
        '저사양 모바일' 'Render Scale을 상향' 'STP를 비활성화' || return 1
}

test_docs_preserve_conditional_rendering_techniques()
{
    local optimization_document="$DOCS_ROOT/coding-standards/optimization/rendering-techniques.md"
    local technique_name
    local section_heading
    local section_count

    if [ ! -f "$optimization_document" ]; then
        echo "렌더링 최적화 베이스 문서가 없습니다: $optimization_document" >&2
        return 1
    fi

    for technique_name in 'GPU Resident Drawer' 'GPU Occlusion Culling' 'STP' 'Mesh LOD'
    do
        grep -Fq "$technique_name" "$optimization_document" || {
            echo "조건부 최적화 기법이 누락되었습니다: $technique_name" >&2
            return 1
        }
    done

    for section_heading in \
        '#### 목적' \
        '#### 작동 원리' \
        '#### 적용 사전 조건' \
        '#### `applicable` 판정' \
        '#### `not_applicable` 판정' \
        '#### `unknown` 판정' \
        '#### 프로파일링 검증' \
        '#### 부작용과 롤백'
    do
        section_count=$(grep -Fc "$section_heading" "$optimization_document")
        if [ "$section_count" -ne 4 ]; then
            echo "최적화 문서 섹션 수가 4가 아닙니다: $section_heading ($section_count)" >&2
            return 1
        fi
    done

    assert_h2_section_contains_all "$optimization_document" '## 4. Mesh LOD' "Mesh LOD 버전별 기본·cross-fade 조건" \
        '6000.3/Documentation/Manual/lod/mesh-lod-introduction.html' \
        'GPU Resident Drawer 활성화는 Mesh LOD cross-fade의 조건' \
        '기본 Mesh LOD의 일괄 필수 조건으로 쓰지 않습니다' || return 1
    assert_h2_section_contains_all "$optimization_document" '## 4. Mesh LOD' "Mesh LOD 버전별 unknown·승격 경계" \
        '다른 Unity 버전에서 미확인 조건은 `unknown`' \
        '모든 6.2+에 일반화하거나 프로젝트 버전을 자동 승격하지 않습니다' || return 1

    return 0
}

test_docs_legacy_paths_are_compatibility_indexes()
{
    local legacy_document

    for legacy_document in \
        "$DOCS_ROOT/coding-standards/architecture-rules.md" \
        "$DOCS_ROOT/coding-standards/naming-conventions.md" \
        "$DOCS_ROOT/coding-standards/performance-rules.md" \
        "$DOCS_ROOT/coding-standards/safety-rules.md" \
        "$DOCS_ROOT/coding-standards/unity-specific.md"
    do
        grep -Fq '호환 인덱스' "$legacy_document" || {
            echo "기존 문서가 호환 인덱스로 유지되지 않았습니다: $legacy_document" >&2
            return 1
        }
        grep -Eq '\[[^]]+\]\([^)]+' "$legacy_document" || {
            echo "호환 인덱스에 새 문서 링크가 없습니다: $legacy_document" >&2
            return 1
        }
    done

    return 0
}

test_docs_internal_links_resolve()
{
    local document_path
    local document_directory
    local links_path="$TEST_TEMP_ROOT/task6-doc-links.txt"
    local raw_link
    local link_target
    local resolved_target

    find "$DOCS_ROOT/coding-standards/core" \
        "$DOCS_ROOT/coding-standards/optimization" \
        "$DOCS_ROOT/profiles" \
        -type f -name '*.md' -print > "$links_path.documents" || return 1
    printf '%s\n' \
        "$DOCS_ROOT/coding-standards/architecture-rules.md" \
        "$DOCS_ROOT/coding-standards/naming-conventions.md" \
        "$DOCS_ROOT/coding-standards/performance-rules.md" \
        "$DOCS_ROOT/coding-standards/safety-rules.md" \
        "$DOCS_ROOT/coding-standards/unity-specific.md" \
        >> "$links_path.documents"

    while IFS= read -r document_path
    do
        : > "$links_path"
        grep -Eo '\[[^][]+\]\([^()]+\)' "$document_path" > "$links_path" || true
        document_directory=$(dirname "$document_path")
        while IFS= read -r raw_link || [ -n "$raw_link" ]
        do
            link_target=${raw_link#*](}
            link_target=${link_target%)}
            link_target=${link_target%%#*}
            case "$link_target" in
                ''|http://*|https://*|mailto:*)
                    continue
                    ;;
            esac
            resolved_target="$document_directory/$link_target"
            if [ ! -e "$resolved_target" ]; then
                echo "깨진 문서 링크입니다: $document_path -> $link_target" >&2
                return 1
            fi
        done < "$links_path"
    done < "$links_path.documents"

    return 0
}

# Project-local records excluded by the full-sync contract (docs/onboarding/parallel-work.md).
# exec-plans README·_TEMPLATE are harness-owned; every other exec-plans file is a project plan.
is_project_local_document()
{
    case "${2#"$1"/}" in
        artifacts/*|reports/*|work-items/*) return 0 ;;
        docs/exec-plans/README.md|docs/exec-plans/_TEMPLATE.md) return 1 ;;
        docs/exec-plans/*) return 0 ;;
    esac
    return 1
}

validate_document_links()
{
    local documents_root=$1
    local documents
    local document_path
    local document_directory
    local raw_link
    local link_target
    local links

    documents=$(find "$documents_root" -type f -name '*.md' -print) || return 1
    while IFS= read -r document_path || [ -n "$document_path" ]
    do
        if [ -z "$document_path" ] || is_project_local_document "$documents_root" "$document_path"; then
            continue
        fi
        links=$(grep -Eo '\[[^][]+\]\([^()]+\)' "$document_path" || true)
        document_directory=$(dirname "$document_path")
        while IFS= read -r raw_link || [ -n "$raw_link" ]
        do
            [ -n "$raw_link" ] || continue
            link_target=${raw_link#*](}
            link_target=${link_target%)}
            link_target=${link_target%%#*}
            case "$link_target" in
                ''|http://*|https://*|mailto:*|'${'*)
                    continue
                    ;;
            esac
            if [ ! -e "$document_directory/$link_target" ]; then
                echo "깨진 전체 문서 링크입니다: $document_path -> $link_target" >&2
                return 1
            fi
        done <<DOCUMENT_LINKS_EOF
$links
DOCUMENT_LINKS_EOF
    done <<DOCUMENT_PATHS_EOF
$documents
DOCUMENT_PATHS_EOF
}

validate_agent_document_references()
{
    local documents_root=$1
    local project_root=$2
    local documents
    local document_path
    local document_line
    local references
    local reference_path

    documents=$(find "$documents_root" -type f -name '*.md' -print) || return 1
    while IFS= read -r document_path || [ -n "$document_path" ]
    do
        if is_project_local_document "$documents_root" "$document_path"; then
            continue
        fi

        while IFS= read -r document_line || [ -n "$document_line" ]
        do
            references=$(printf '%s\n' "$document_line" | grep -Eo '\.agents/[[:alnum:]_.${}/-]+' || true)
            while IFS= read -r reference_path || [ -n "$reference_path" ]
            do
                reference_path=${reference_path%/}
                case "$reference_path" in
                    ''|*'${source_root}'*|*'${test_root}'*)
                        continue
                        ;;
                    .agents/config/project-profile*.conf|.agents/reports/*.md|.agents/reports/unity-milestone-validation.conf)
                        continue
                        ;;
                    .agents/reports/TASK-*-task-validation.conf)
                        if [[ "$reference_path" =~ ^\.agents/reports/TASK-[0-9]+-task-validation\.conf$ ]]; then
                            continue
                        fi
                        ;;
                esac
                if [ -e "$project_root/$reference_path" ]; then
                    continue
                fi
                echo "깨진 .agents 참조입니다: $document_path -> $reference_path" >&2
                return 1
            done <<DOCUMENT_REFERENCES_EOF
$references
DOCUMENT_REFERENCES_EOF
        done < "$document_path"
    done <<DOCUMENT_PATHS_EOF
$documents
DOCUMENT_PATHS_EOF
}

test_all_document_references_and_runtime_dependencies_are_safe()
{
    local script_path

    validate_document_links "$AGENTS_ROOT" || return 1
    validate_agent_document_references "$AGENTS_ROOT" "$AGENTS_ROOT/.." || return 1

    for script_path in "$AGENTS_ROOT"/scripts/*/*.sh "$AGENTS_ROOT"/scripts/*/*.ps1
    do
        case "$script_path" in
            "$AGENTS_ROOT"/scripts/setup/*|"$AGENTS_ROOT"/scripts/hooks/protect-agents-dir.sh)
                continue
                ;;
        esac
        case "$script_path" in
            "$AGENTS_ROOT"/scripts/shared/change-id.sh|"$AGENTS_ROOT"/scripts/shared/change-id.ps1|"$AGENTS_ROOT"/scripts/workflow/work-harness.sh)
                # 승인된 변경분 manifest와 업무 baseline 검사는 동봉한 Python 3 코드만 호출합니다.
                forbidden_tools='jq|node|npm|npx|perl|ruby|curl|wget|Invoke-WebRequest'
                ;;
            *) forbidden_tools='jq|python|python3|node|npm|npx|perl|ruby|curl|wget|Invoke-WebRequest' ;;
        esac
        if grep -Ein "(^|[^[:alnum:]_])($forbidden_tools)([^[:alnum:]_]|$)" "$script_path"; then
            echo "생산 스크립트에 외부 런타임 또는 네트워크 의존성이 있습니다: $script_path" >&2
            return 1
        fi
    done

    if grep -Fq '## 현재 RED 단계' "$AGENTS_ROOT/tests/README.md"; then
        echo "테스트 README에 완료된 RED 단계 설명이 남아 있습니다." >&2
        return 1
    fi
    for required_text in \
        '`profile`' '`detection`' '`readonly`' '`lint`' '`docs`' '`entrypoints`' '`parity`' \
        'PowerShell 실행 검증 미실시' \
        '감지 → pending 경고 → 확정 → error → 재감지 후보'
    do
        grep -Fq "$required_text" "$AGENTS_ROOT/tests/README.md" || {
            echo "테스트 README 현재 계약이 누락되었습니다: $required_text" >&2
            return 1
        }
    done
}

test_document_reference_audit_rejects_missing_regular_paths()
{
    local case_root="$TEST_TEMP_ROOT/document-reference-mutation"
    local documents_root="$case_root/docs"
    local document_path="$documents_root/missing.md"

    require_function validate_agent_document_references || return 1
    mkdir -p "$documents_root"
    printf '%s\n' '# 일반 문서' '누락 참조: `.agents/scripts/missing-command.sh`' > "$document_path"
    if validate_agent_document_references "$documents_root" "$case_root" >/dev/null 2>&1; then
        echo "일반 문서의 누락된 .agents 경로가 허용되었습니다." >&2
        return 1
    fi

    printf '%s\n' \
        '# 런타임 생성 증거' \
        '정확한 증거 경로: `.agents/reports/unity-milestone-validation.conf`' \
        > "$document_path"
    if ! validate_agent_document_references "$documents_root" "$case_root" >/dev/null 2>&1; then
        echo "정확한 런타임 마일스톤 증거 경로가 거부되었습니다." >&2
        return 1
    fi

    printf '%s\n' \
        '# 다른 누락 증거' \
        '허용되지 않는 경로: `.agents/reports/other.conf`' \
        > "$document_path"
    if validate_agent_document_references "$documents_root" "$case_root" >/dev/null 2>&1; then
        echo "다른 누락 .agents/reports/*.conf 경로가 허용되었습니다." >&2
        return 1
    fi

    printf '%s\n' \
        '# 런타임 Markdown 보고서' \
        '기존 허용 경로: `.agents/reports/runtime-note.md`' \
        > "$document_path"
    if ! validate_agent_document_references "$documents_root" "$case_root" >/dev/null 2>&1; then
        echo "기존 런타임 .agents/reports/*.md 경로 정책이 깨졌습니다." >&2
        return 1
    fi
}

test_document_reference_audit_skips_project_local_records()
{
    local case_root="$TEST_TEMP_ROOT/document-reference-scope"
    local documents_root="$case_root/.agents"
    local local_path

    require_function validate_agent_document_references || return 1
    require_function validate_document_links || return 1
    for local_path in artifacts/x.md reports/x.md work-items/active/x.md \
        docs/exec-plans/active/2026-01-01-plan.md docs/exec-plans/completed/2026-01-01-plan.md \
        docs/exec-plans/2026-01-01-plan.md; do
        mkdir -p "$documents_root/${local_path%/*}"
        printf '%s\n' '# 프로젝트 로컬 기록' '삭제된 경로: `.agents/scripts/deleted.sh`' \
            '[삭제된 증거](../../../other-worktree/missing.json)' > "$documents_root/$local_path"
    done
    if ! validate_agent_document_references "$documents_root" "$case_root" >/dev/null 2>&1; then
        echo "프로젝트 로컬 기록의 깨진 참조가 하네스 문서 실패로 처리되었습니다." >&2
        return 1
    fi
    if ! validate_document_links "$documents_root" >/dev/null 2>&1; then
        echo "프로젝트 로컬 기록의 깨진 상대 링크가 하네스 문서 실패로 처리되었습니다." >&2
        return 1
    fi
    mkdir -p "$documents_root/docs/onboarding"
    printf '%s\n' '# 하네스 문서' '[누락 링크](missing.md)' > "$documents_root/docs/onboarding/links.md"
    if validate_document_links "$documents_root" >/dev/null 2>&1; then
        echo "하네스 문서의 깨진 상대 링크가 허용되었습니다." >&2
        return 1
    fi
    rm -f "$documents_root/docs/onboarding/links.md"

    for local_path in docs/onboarding/guide.md docs/exec-plans/README.md docs/exec-plans/_TEMPLATE.md; do
        mkdir -p "$documents_root/${local_path%/*}"
        printf '%s\n' '# 하네스 문서' '누락 참조: `.agents/scripts/missing-command.sh`' > "$documents_root/$local_path"
        if validate_agent_document_references "$documents_root" "$case_root" >/dev/null 2>&1; then
            echo "하네스 문서의 깨진 참조가 허용되었습니다: $local_path" >&2
            return 1
        fi
        rm -f "$documents_root/$local_path"
    done
}

assert_document_fragments_in_order()
{
    local document_path=$1
    local contract_name=$2
    local previous_line=0
    local fragment
    local fragment_line
    shift 2

    for fragment in "$@"
    do
        fragment_line=$(grep -nF "$fragment" "$document_path" | head -1 | cut -d: -f1)
        if [ -z "$fragment_line" ]; then
            echo "$contract_name 순서 계약이 누락되었습니다: $fragment" >&2
            return 1
        fi
        if [ "$fragment_line" -le "$previous_line" ]; then
            echo "$contract_name 순서가 잘못되었습니다: $fragment" >&2
            return 1
        fi
        previous_line=$fragment_line
    done

    return 0
}

assert_task7_links_resolve()
{
    local document_path
    local document_directory
    local links_path="$TEST_TEMP_ROOT/task7-doc-links.txt"
    local raw_link
    local link_target
    local resolved_target

    for document_path in "$@"
    do
        : > "$links_path"
        grep -Eo '\[[^][]+\]\([^()]+\)' "$document_path" > "$links_path" || true
        document_directory=$(dirname "$document_path")
        while IFS= read -r raw_link || [ -n "$raw_link" ]
        do
            link_target=${raw_link#*](}
            link_target=${link_target%)}
            link_target=${link_target%%#*}
            case "$link_target" in
                ''|http://*|https://*|mailto:*|'${'*)
                    continue
                    ;;
            esac
            resolved_target="$document_directory/$link_target"
            if [ ! -e "$resolved_target" ]; then
                echo "깨진 Task 7 문서 링크입니다: $document_path -> $link_target" >&2
                return 1
            fi
        done < "$links_path"
    done

    return 0
}

assert_no_fixed_entrypoint_assumptions()
{
    awk '
        BEGIN {
            technology = "(MVVM|MVP|MVC|VContainer|Zenject|URP|HDRP|UniTask|Coroutine|DOTween|LeanTween)"
            source_path = "Assets(/[[:alnum:]_.-]+)*/Scripts"
            particle = "(을|를|은|는|이|가|으로|로)?"
            assertion = "(만[[:space:]]*(허용|사용)|기본([[:space:]]+(UI[[:space:]]+구조|구조|값|선택))?|표준([[:space:]]+(DI|구조|도구|백엔드))?|필수|반드시|강제|고정)"
        }
        function is_allowed_negative(line) {
            return line ~ /(허용|사용|강제|고정|표준|기본)[^.]*하지[[:space:]]*않/ ||
                line ~ /(필수|기본|표준)[^.]*아니/
        }
        function is_allowed_migration(line) {
            return line ~ /(기존|종전|레거시)[^.]*(고정|기본|표준)[^.]*(프로필|선택|가변)[^.]*(마이그레이션|전환|이관|제거|폐기)/
        }
        {
            suspicious = ($0 ~ technology particle "[^.]*" assertion) ||
                ($0 ~ assertion "[^.]*" technology) ||
                ($0 ~ source_path)
            if (suspicious && !is_allowed_negative($0) && !is_allowed_migration($0)) {
                print "고정 프로필 전제: " FILENAME ":" FNR ": " $0 > "/dev/stderr"
                failed = 1
            }
        }
        END {
            exit failed
        }
    ' "$@"
}

is_business_entrypoint_overlay()
{
    local agents_root=$1
    local policy_path="$agents_root/config/business-policy.conf"
    local agents_path="$agents_root/AGENTS.md"
    local architecture_path="$agents_root/ARCHITECTURE.md"
    local required_policy_line
    local required_path

    for required_path in "$policy_path" "$agents_path" "$architecture_path"
    do
        if [ -L "$required_path" ] || [ ! -f "$required_path" ] || [ ! -r "$required_path" ]; then
            return 1
        fi
    done

    grep -Fxq '# Unity 클라이언트 업무용 하네스 — AI 에이전트 가이드' "$agents_path" || return 1
    grep -Fxq '> 이 파일은 업무용 하네스의 첫 진입점입니다. 업무 원문 정책은 범용 Core와 프로젝트 감지 결과보다 우선합니다.' "$agents_path" || return 1
    grep -Fxq '# Unity 클라이언트 업무용 하네스 아키텍처' "$architecture_path" || return 1
    grep -Fxq '> 범용 Unity 하네스 위에 업무 원문 정책, 고정 기술 표준과 증거 기반 업무 상태 머신을 오버레이합니다.' "$architecture_path" || return 1

    for required_policy_line in \
        'policy_version=1' \
        'external_action_authorization=explicit_user_request' \
        'architecture=layered_clean' \
        'ui_pattern=mvp' \
        'dependency_injection=vcontainer' \
        'async_backend=unitask'
    do
        grep -Fxq "$required_policy_line" "$policy_path" || return 1
    done

    return 0
}

assert_business_entrypoint_contract()
{
    local agents_root=$1
    local docs_root=$2
    local agents_path="$agents_root/AGENTS.md"
    local architecture_path="$agents_root/ARCHITECTURE.md"
    local policy_path="$agents_root/config/business-policy.conf"
    local agent_quickstart="$docs_root/onboarding/agent-quickstart.md"
    local developer_quickstart="$docs_root/onboarding/developer-quickstart.md"

    if ! is_business_entrypoint_overlay "$agents_root"; then
        echo "업무 오버레이 파일 증거가 완전하지 않습니다: $agents_root" >&2
        return 1
    fi

    assert_document_fragments_in_order "$agents_path" "업무 AGENTS 읽기 우선순위" \
        '1. 자기 실행 루트의 `AGENTS.md`와 존재하는 `.agents/AGENTS.md`를 직접 읽습니다' \
        '2. 최신 사용자 요구·승인 범위·역할·보호 경로·검증 실행 권한을 확인합니다' \
        '3. `.agents/config/project-profile.conf`의 상태와 확정 프로필을 확인합니다' \
        '4. Core·Optimization Base와 확정 Profiles의 적용 의무를 확인합니다' \
        '5. 모호한 작업은 관련 경계를 먼저 확인한 뒤 분류합니다' \
        '6. 구현 전 전체 계획 승인' || return 1

    assert_h2_section_contains_all "$agents_path" '## 고정 업무 프로필' "업무 Layered 권위 행" \
        '| 전체 아키텍처 | Layered Architecture | 프로젝트 감지로 변경하지 않음 |' || return 1
    assert_h2_section_contains_all "$agents_path" '## 고정 업무 프로필' "업무 MVP 권위 행" \
        '| UI | MVP | View → Presenter → UseCase → Domain |' || return 1
    assert_h2_section_contains_all "$agents_path" '## 고정 업무 프로필' "업무 VContainer 권위 행" \
        '| DI | VContainer | 구체 구현은 Composition Root에서 조립 |' || return 1
    assert_h2_section_contains_all "$agents_path" '## 고정 업무 프로필' "업무 UniTask 권위 행" \
        '| 비동기 | UniTask | CancellationToken과 해제 책임 필수 |' || return 1
    assert_h2_section_contains_all "$agents_path" '## 외부 도구 경계' "업무 external manual 경계" \
        'Jira, Slack, GitHub와 Unity CI는 기본 `manual` 모드입니다.' || return 1
    assert_h2_section_contains_all "$agents_path" '## 외부 도구 경계' "업무 external 현재 요청 경계" \
        '사용자의 현재 요청에 명시된 범위' || return 1
    assert_h2_section_contains_all "$architecture_path" '## 1. 정책 계층' "업무 아키텍처 고정 권위" \
        '업무 원문은 Layered Architecture, MVP, VContainer, UniTask와 단일 Assembly를 고정합니다.' || return 1
    assert_h2_section_contains_all "$architecture_path" '## 6. 선택형 외부 연동' "업무 manual 모드 권위" \
        '`manual`' || return 1
    assert_h2_section_contains_all "$architecture_path" '## 6. 선택형 외부 연동' "업무 external authorization 권위" \
        '`external_action_authorization=explicit_user_request`' || return 1
    assert_h2_section_contains_all "$agent_quickstart" '## 규칙 로딩' "업무 에이전트 온보딩 고정 섹션" \
        'Layered Architecture, MVP, VContainer, UniTask와 단일 Assembly는 업무 고정값입니다.' || return 1
    assert_document_contains_all "$developer_quickstart" "업무 개발자 온보딩 고정 선언" \
        '이 업무용 하네스는 Layered Architecture, UI MVP, VContainer, UniTask와 단일 Assembly를 고정합니다.' || return 1
    assert_document_contains_all "$policy_path" "업무 정책 고정값" \
        'external_action_authorization=explicit_user_request' \
        'architecture=layered_clean' \
        'ui_pattern=mvp' \
        'dependency_injection=vcontainer' \
        'async_backend=unitask' || return 1

    return 0
}

assert_business_common_documents_have_no_fixed_defaults()
{
    local docs_root=$1
    local core_root="$docs_root/coding-standards/core"
    local profiles_root="$docs_root/profiles"
    local document_path
    local fixed_default_pattern='(Layered Architecture|MVP|VContainer|UniTask).{0,80}(업무[[:space:]]*(고정값|표준)|고정(합니다|한다|된|값)|기본[[:space:]]*(아키텍처|UI|DI|비동기|백엔드)|표준[[:space:]]*(아키텍처|UI|DI|비동기|백엔드)|필수로[[:space:]]*(사용|적용))'
    local reverse_fixed_default_pattern='(업무[[:space:]]*(고정값|표준)|고정(합니다|한다|된|값)|기본[[:space:]]*(아키텍처|UI|DI|비동기|백엔드)|표준[[:space:]]*(아키텍처|UI|DI|비동기|백엔드)|필수로[[:space:]]*(사용|적용)).{0,80}(Layered Architecture|MVP|VContainer|UniTask)'

    if [ ! -d "$core_root" ] || [ ! -d "$profiles_root" ]; then
        echo "업무 오버레이의 범용 Core/Profile 문서 경로가 없습니다: $docs_root" >&2
        return 1
    fi

    while IFS= read -r document_path || [ -n "$document_path" ]
    do
        if grep -Ein "$fixed_default_pattern|$reverse_fixed_default_pattern" "$document_path"; then
            echo "범용 Core/Profile 문서에 업무 고정 기본값이 있습니다: $document_path" >&2
            return 1
        fi
    done <<BUSINESS_COMMON_DOCUMENTS_EOF
$(find "$core_root" "$profiles_root" -type f -name '*.md' -print)
BUSINESS_COMMON_DOCUMENTS_EOF

    return 0
}

test_entrypoints_route_profile_states_in_required_order()
{
    local agents_document="$AGENTS_ROOT/AGENTS.md"
    local architecture_document="$AGENTS_ROOT/ARCHITECTURE.md"

    if is_business_entrypoint_overlay "$AGENTS_ROOT"; then
        assert_business_entrypoint_contract "$AGENTS_ROOT" "$DOCS_ROOT"
        return $?
    fi

    assert_document_fragments_in_order "$agents_document" "AGENTS 프로필 읽기" \
        '1. 자기 실행 루트의 `AGENTS.md`와 존재하는 `.agents/AGENTS.md`를 직접 읽습니다' \
        '2. 최신 사용자 요구·승인 범위·역할·보호 경로·검증 실행 권한을 확인합니다' \
        '3. `.agents/config/project-profile.conf`의 상태와 확정 프로필을 확인합니다' \
        '4. Core·Optimization Base와 확정 Profiles의 적용 의무를 확인합니다' \
        '5. 모호한 작업은 관련 경계를 먼저 확인한 뒤 분류합니다' \
        '6. 구현 전 전체 계획 승인' || return 1

    assert_document_contains_all "$agents_document" "AGENTS 상태 라우팅" \
        '| `confirmation_status=pending` | Core + Optimization Base | 모든 기술 Profiles는 참고만 하고 강제하지 않음 |' \
        '| `confirmation_status=confirmed` | Core + Optimization Base + 확정된 기술 Profiles | 프로필별 검사를 활성화 |' \
        '| `confirmed` + `architecture=custom` | Core + Optimization Base + 사용자 아키텍처 경계 + 확정된 DI·비동기·트윈·렌더링 Profiles | 일반 아키텍처 전용 검사만 축소 |' || return 1

    assert_document_contains_all "$architecture_document" "ARCHITECTURE 하네스 구조" \
        '## 1. 하네스 모듈 구조' \
        '## 2. 감지·검토·확정 흐름' \
        '## 3. 규칙 활성화 방향' \
        '## 4. 생성 파일 경계' \
        'project-profile.conf' \
        'detection-report.md' \
        'project-profile.candidate.conf' || return 1
}

test_entrypoint_templates_follow_profile_contract()
{
    local template_path

    for template_path in \
        "$DOCS_ROOT/design-docs/_TEMPLATE.md" \
        "$DOCS_ROOT/exec-plans/_TEMPLATE.md" \
        "$DOCS_ROOT/product-specs/_TEMPLATE.md"
    do
        assert_document_contains_all "$template_path" "Task 7 템플릿" \
            'project-profile.conf' \
            '${source_root}' \
            '${test_root}' \
            '선택 프로필의 역할' \
            'dependency_injection' \
            '`none`' \
            '적용 상태' \
            '측정 근거' \
            '롤백 조건' \
            '미결정 사항이 없으면 이 섹션을 삭제' || return 1
    done

    assert_document_contains_all "$DOCS_ROOT/design-docs/_TEMPLATE.md" "설계 템플릿 아키텍처 라우팅" \
        'docs/profiles/architecture/' \
        '| 선택 프로필의 역할 | 클래스 | 책임 |' || return 1
    assert_document_contains_all "$DOCS_ROOT/exec-plans/_TEMPLATE.md" "실행 계획 경로 변수" \
        '- Create: `${source_root}/[경로]/[파일명].cs`' \
        '- Modify: `${source_root}/[경로]/[파일명].cs`' \
        '- Test: `${test_root}/[경로]/[테스트파일명].cs`' \
        'test_root`가 없으면 경로를 발명하지 않고 `N/A`' || return 1

    for template_path in \
        "$DOCS_ROOT/design-docs/_TEMPLATE.md" \
        "$DOCS_ROOT/exec-plans/_TEMPLATE.md" \
        "$DOCS_ROOT/product-specs/_TEMPLATE.md"
    do
        if grep -Fq -- '- [ ] [해결되지 않은 질문' "$template_path"; then
            echo "조건과 무관한 Open Questions 기본 항목이 남아 있습니다: $template_path" >&2
            return 1
        fi
    done
}

test_entrypoint_readmes_explain_profile_driven_authoring()
{
    local readme_path

    for readme_path in \
        "$DOCS_ROOT/design-docs/README.md" \
        "$DOCS_ROOT/exec-plans/README.md" \
        "$DOCS_ROOT/product-specs/README.md"
    do
        assert_document_contains_all "$readme_path" "Task 7 작성 가이드" \
            'project-profile.conf' \
            '${source_root}' \
            '${test_root}' \
            '선택 프로필의 역할' \
            'dependency_injection=none' \
            '적용 상태' \
            '측정 근거' \
            '롤백 조건' \
            'Open Questions' \
            '미결정 사항이 있을 때만' || return 1
    done
}

test_onboarding_and_scripts_document_equal_platform_flow()
{
    local guide_path

    for guide_path in \
        "$DOCS_ROOT/onboarding/agent-quickstart.md" \
        "$DOCS_ROOT/onboarding/developer-quickstart.md" \
        "$DOCS_ROOT/onboarding/tech-stack-overview.md" \
        "$AGENTS_ROOT/scripts/README.md"
    do
        assert_document_fragments_in_order "$guide_path" "초기화·검토·확정·검사" \
            '### 1. 초기화' \
            '### 2. 감지 보고서 검토' \
            '### 3. 프로필 확정' \
            '### 4. 검사' || return 1
        assert_document_contains_all "$guide_path" "Bash·PowerShell 동등 흐름" \
            'bash .agents/scripts/init/initialize-harness.sh --project-root .' \
            'bash .agents/scripts/init/initialize-harness.sh --project-root . --confirm' \
            'bash .agents/scripts/lint/check-harness.sh --project-root .' \
            'powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot .' \
            'powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/init/initialize-harness.ps1 -ProjectRoot . -Confirm' \
            'powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/lint/check-harness.ps1 -ProjectRoot .' \
            '.agents/reports/detection-report.md' || return 1
    done
}

test_entrypoints_do_not_assert_fixed_profiles_or_paths()
{
    if is_business_entrypoint_overlay "$AGENTS_ROOT"; then
        assert_business_entrypoint_contract "$AGENTS_ROOT" "$DOCS_ROOT" || return 1
        assert_business_common_documents_have_no_fixed_defaults "$DOCS_ROOT"
        return $?
    fi

    assert_no_fixed_entrypoint_assumptions \
        "$AGENTS_ROOT/AGENTS.md" \
        "$AGENTS_ROOT/ARCHITECTURE.md" \
        "$DOCS_ROOT/design-docs/README.md" \
        "$DOCS_ROOT/design-docs/_TEMPLATE.md" \
        "$DOCS_ROOT/exec-plans/README.md" \
        "$DOCS_ROOT/exec-plans/_TEMPLATE.md" \
        "$DOCS_ROOT/product-specs/README.md" \
        "$DOCS_ROOT/product-specs/_TEMPLATE.md" \
        "$DOCS_ROOT/onboarding/agent-quickstart.md" \
        "$DOCS_ROOT/onboarding/developer-quickstart.md" \
        "$DOCS_ROOT/onboarding/tech-stack-overview.md" \
        "$AGENTS_ROOT/scripts/README.md"
}

test_entrypoint_fixed_assumption_helper_rejects_mutations()
{
    local fixture_root="$TEST_TEMP_ROOT/task7-fixed-assumption-mutations"
    local fixture_path
    local fixture_text

    mkdir -p "$fixture_root"

    for fixture_text in \
        'MVVM만 허용' \
        'MVVM을 기본 UI 구조로 사용한다' \
        'VContainer를 표준 DI로 사용한다' \
        'Assets/_Game/Scripts로 고정'
    do
        fixture_path="$fixture_root/rejected.md"
        printf '%s\n' "$fixture_text" > "$fixture_path"
        if assert_no_fixed_entrypoint_assumptions "$fixture_path" >/dev/null 2>&1; then
            echo "고정 전제 변이를 허용했습니다: $fixture_text" >&2
            return 1
        fi
    done

    fixture_path="$fixture_root/allowed-negative.md"
    printf '%s\n' 'Assets/Scripts를 고정 경로로 사용하지 않는다' > "$fixture_path"
    assert_no_fixed_entrypoint_assumptions "$fixture_path" || return 1

    fixture_path="$fixture_root/allowed-migration.md"
    printf '%s\n' '기존 MVVM 고정 규칙에서 프로젝트 프로필 선택으로 마이그레이션한다' > "$fixture_path"
    assert_no_fixed_entrypoint_assumptions "$fixture_path"
}

test_entrypoint_business_overlay_requires_complete_file_evidence()
{
    local fixture_root="$TEST_TEMP_ROOT/business-overlay-entrypoint"
    local fixture_agents_root="$fixture_root/.agents"
    local fixture_docs_root="$fixture_agents_root/docs"
    local policy_path="$fixture_agents_root/config/business-policy.conf"
    local agents_path="$fixture_agents_root/AGENTS.md"
    local architecture_path="$fixture_agents_root/ARCHITECTURE.md"

    require_function is_business_entrypoint_overlay || return 1
    require_function assert_business_entrypoint_contract || return 1
    require_function assert_business_common_documents_have_no_fixed_defaults || return 1

    mkdir -p \
        "$fixture_agents_root/config" \
        "$fixture_docs_root/business-standards" \
        "$fixture_docs_root/coding-standards/core" \
        "$fixture_docs_root/profiles" \
        "$fixture_docs_root/onboarding" || return 1

    printf '%s\n' \
        'policy_version=1' \
        'external_action_authorization=explicit_user_request' \
        'architecture=layered_clean' \
        'ui_pattern=mvp' \
        'dependency_injection=vcontainer' \
        'async_backend=unitask' \
        > "$policy_path"
    printf '%s\n' \
        '# Unity 클라이언트 업무용 하네스 — AI 에이전트 가이드' \
        '> 이 파일은 업무용 하네스의 첫 진입점입니다. 업무 원문 정책은 범용 Core와 프로젝트 감지 결과보다 우선합니다.' \
        '## 필수 읽기 순서' \
        '1. 자기 실행 루트의 `AGENTS.md`와 존재하는 `.agents/AGENTS.md`를 직접 읽습니다' \
        '2. 최신 사용자 요구·승인 범위·역할·보호 경로·검증 실행 권한을 확인합니다' \
        '3. `.agents/config/project-profile.conf`의 상태와 확정 프로필을 확인합니다' \
        '4. Core·Optimization Base와 확정 Profiles의 적용 의무를 확인합니다' \
        '5. 모호한 작업은 관련 경계를 먼저 확인한 뒤 분류합니다' \
        '6. 구현 전 전체 계획 승인' \
        '## 고정 업무 프로필' \
        '| 전체 아키텍처 | Layered Architecture | 프로젝트 감지로 변경하지 않음 |' \
        '| UI | MVP | View → Presenter → UseCase → Domain |' \
        '| DI | VContainer | 구체 구현은 Composition Root에서 조립 |' \
        '| 비동기 | UniTask | CancellationToken과 해제 책임 필수 |' \
        '## 외부 도구 경계' \
        '- Jira, Slack, GitHub와 Unity CI는 기본 `manual` 모드입니다.' \
        '- 외부 서비스는 사용자의 현재 요청에 명시된 범위에서만 수행합니다.' \
        > "$agents_path"
    printf '%s\n' \
        '# Unity 클라이언트 업무용 하네스 아키텍처' \
        '> 범용 Unity 하네스 위에 업무 원문 정책, 고정 기술 표준과 증거 기반 업무 상태 머신을 오버레이합니다.' \
        '## 1. 정책 계층' \
        '- 업무 원문은 Layered Architecture, MVP, VContainer, UniTask와 단일 Assembly를 고정합니다.' \
        '## 6. 선택형 외부 연동' \
        '- `manual`: 링크와 결과 문서를 사람이 제공하고 하네스가 형식을 검사합니다.' \
        '- 연결 모드와 실행 권한은 서로 독립적이며 `external_action_authorization=explicit_user_request`를 고정 적용합니다.' \
        > "$architecture_path"
    printf '%s\n' \
        '# AI 에이전트 온보딩' \
        '## 규칙 로딩' \
        '- Layered Architecture, MVP, VContainer, UniTask와 단일 Assembly는 업무 고정값입니다.' \
        > "$fixture_docs_root/onboarding/agent-quickstart.md"
    printf '%s\n' \
        '# 개발자 온보딩' \
        '이 업무용 하네스는 Layered Architecture, UI MVP, VContainer, UniTask와 단일 Assembly를 고정합니다.' \
        > "$fixture_docs_root/onboarding/developer-quickstart.md"
    printf '%s\n' '# 공통 Core' '특정 기술을 기본값으로 고정하지 않습니다.' > "$fixture_docs_root/coding-standards/core/core.md"
    printf '%s\n' '# 조건부 프로필' '실제 사용 증거가 있을 때만 적용합니다.' > "$fixture_docs_root/profiles/profile.md"

    if ! is_business_entrypoint_overlay "$fixture_agents_root"; then
        echo "완전한 파일 증거를 갖춘 업무 오버레이를 감지하지 못했습니다." >&2
        return 1
    fi
    assert_business_entrypoint_contract "$fixture_agents_root" "$fixture_docs_root" || return 1
    assert_business_common_documents_have_no_fixed_defaults "$fixture_docs_root" || return 1

    mv "$policy_path" "$policy_path.missing" || return 1
    if is_business_entrypoint_overlay "$fixture_agents_root"; then
        echo "business marker만으로 정책 파일 없는 오버레이를 허용했습니다." >&2
        return 1
    fi
    if assert_no_fixed_entrypoint_assumptions "$agents_path" >/dev/null 2>&1; then
        echo "정책 파일 없는 business marker가 고정 전제 검사를 우회했습니다." >&2
        return 1
    fi
    mv "$policy_path.missing" "$policy_path" || return 1

    printf '%s\n' '# 임의 일반 AGENTS' 'VContainer를 표준 DI로 사용한다' > "$agents_path"
    if is_business_entrypoint_overlay "$fixture_agents_root"; then
        echo "정책 파일만으로 임의 일반 AGENTS를 업무 오버레이로 감지했습니다." >&2
        return 1
    fi
    if assert_no_fixed_entrypoint_assumptions "$agents_path" >/dev/null 2>&1; then
        echo "임의 일반 AGENTS의 고정 전제를 허용했습니다." >&2
        return 1
    fi

    printf '%s\n' 'VContainer를 표준 DI로 사용한다' > "$fixture_docs_root/coding-standards/core/core.md"
    if assert_business_common_documents_have_no_fixed_defaults "$fixture_docs_root" >/dev/null 2>&1; then
        echo "업무 오버레이가 공통 Core의 고정 기본값을 허용했습니다." >&2
        return 1
    fi
}

test_entrypoint_document_links_resolve()
{
    assert_task7_links_resolve \
        "$AGENTS_ROOT/AGENTS.md" \
        "$AGENTS_ROOT/ARCHITECTURE.md" \
        "$DOCS_ROOT/design-docs/README.md" \
        "$DOCS_ROOT/design-docs/_TEMPLATE.md" \
        "$DOCS_ROOT/exec-plans/README.md" \
        "$DOCS_ROOT/exec-plans/_TEMPLATE.md" \
        "$DOCS_ROOT/product-specs/README.md" \
        "$DOCS_ROOT/product-specs/_TEMPLATE.md" \
        "$DOCS_ROOT/onboarding/agent-quickstart.md" \
        "$DOCS_ROOT/onboarding/developer-quickstart.md" \
        "$DOCS_ROOT/onboarding/tech-stack-overview.md" \
        "$AGENTS_ROOT/scripts/README.md"
}

write_tooling_codex_config()
{
    local path=$1
    local karpathy_state=$2
    local superpowers_state=$3
    local understand_state=$4
    local plugin_id
    local state

    mkdir -p "$(dirname "$path")"
    : > "$path"
    for plugin_id in andrej-karpathy-skills superpowers understand-anything; do
        case "$plugin_id" in
            andrej-karpathy-skills)
                state=$karpathy_state
                ;;
            superpowers)
                state=$superpowers_state
                ;;
            understand-anything)
                state=$understand_state
                ;;
        esac

        if [ "$state" = "absent" ]; then
            continue
        fi
        printf '[plugins."%s@test-marketplace"]\n' "$plugin_id" >> "$path"
        printf 'enabled = %s\n' "$state" >> "$path"
    done
}

create_tooling_cache_skill()
{
    local codex_home=$1
    local plugin_id=$2
    local version=$3
    local skill_name=$4
    local marketplace=${5:-test-marketplace}
    local skill_path="$codex_home/plugins/cache/$marketplace/$plugin_id/$version/skills/$skill_name/SKILL.md"

    mkdir -p "$(dirname "$skill_path")"
    printf '%s\n' "name: $skill_name" > "$skill_path"
}

create_tooling_standalone_skill()
{
    local codex_home=$1
    local skill_name=$2
    local skill_path="$codex_home/skills/$skill_name/SKILL.md"

    mkdir -p "$(dirname "$skill_path")"
    printf '%s\n' "name: $skill_name" > "$skill_path"
}

create_tooling_codex_stub()
{
    local bin_root=$1

    mkdir -p "$bin_root"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$bin_root/codex"
    chmod +x "$bin_root/codex"
}

create_superpowers_git_stub()
{
    local bin_root=$1

    mkdir -p "$bin_root"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "git|%s\n" "$*" >> "$TOOLING_CALL_LOG"' \
        'if [ "$1" != "clone" ]; then exit 8; fi' \
        'if [ "$TOOLING_GIT_EXIT" -ne 0 ]; then exit "$TOOLING_GIT_EXIT"; fi' \
        'target=$3' \
        'mkdir -p "$target/skills/using-superpowers" || exit 7' \
        'printf "%s\n" "name: using-superpowers" > "$target/skills/using-superpowers/SKILL.md"' \
        'exit 0' > "$bin_root/git"
    chmod +x "$bin_root/git"
}

assert_tooling_output()
{
    local output_path=$1
    local karpathy_status=$2
    local superpowers_status=$3
    local understand_status=$4
    local expected_path="$TEST_TEMP_ROOT/tooling-expected.txt"

    printf '%s\n' \
        "karpathy_guidelines|$karpathy_status" \
        "superpowers|$superpowers_status" \
        "understand_anything|$understand_status" > "$expected_path"
    if ! cmp -s "$expected_path" "$output_path"; then
        echo "에이전트 도구 상태 출력이 고정 계약과 다릅니다." >&2
        diff -u "$expected_path" "$output_path" >&2 || true
        return 1
    fi
}

create_tooling_installed_fixture()
{
    local home_root=$1
    local codex_home=$2
    local bin_root=$3

    mkdir -p "$home_root" "$codex_home"
    write_tooling_codex_config "$codex_home/config.toml" true true true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1.0.0 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" superpowers 1.0.0 using-superpowers
    create_tooling_cache_skill "$codex_home" understand-anything 1.0.0 understand
    create_tooling_codex_stub "$bin_root"
}

create_tooling_script_fixture()
{
    local fixture_agents_root=$1

    mkdir -p "$fixture_agents_root/scripts/setup" "$fixture_agents_root/config" || return 1
    cp "$TOOLING_SCRIPT" "$fixture_agents_root/scripts/setup/check-agent-tooling.sh"
}

test_tooling_reports_installed_disabled_broken_and_missing()
{
    local case_root="$TEST_TEMP_ROOT/tooling-state-matrix"
    local home_root
    local codex_home
    local bin_root
    local output_path
    local status

    require_file "$TOOLING_SCRIPT" "check-agent-tooling.sh" || return 1

    home_root="$case_root/installed/home"
    codex_home="$case_root/installed/codex"
    bin_root="$case_root/installed/bin"
    output_path="$case_root/installed/output.txt"
    create_tooling_installed_fixture "$home_root" "$codex_home" "$bin_root"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/installed/error.txt"
    status=$?
    assert_equal 0 "$status" "설치 완료 상태 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed installed installed || return 1

    home_root="$case_root/disabled/home"
    codex_home="$case_root/disabled/codex"
    bin_root="$case_root/disabled/bin"
    output_path="$case_root/disabled/output.txt"
    mkdir -p "$home_root"
    write_tooling_codex_config "$codex_home/config.toml" true false true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    create_tooling_codex_stub "$bin_root"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/disabled/error.txt"
    status=$?
    assert_equal 1 "$status" "비활성 상태 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed disabled installed || return 1

    home_root="$case_root/broken/home"
    codex_home="$case_root/broken/codex"
    bin_root="$case_root/broken/bin"
    output_path="$case_root/broken/output.txt"
    mkdir -p "$home_root"
    write_tooling_codex_config "$codex_home/config.toml" true true true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    create_tooling_codex_stub "$bin_root"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/broken/error.txt"
    status=$?
    assert_equal 1 "$status" "손상 상태 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed broken installed || return 1

    home_root="$case_root/missing/home"
    codex_home="$case_root/missing/codex"
    bin_root="$case_root/missing/bin"
    output_path="$case_root/missing/output.txt"
    mkdir -p "$home_root"
    write_tooling_codex_config "$codex_home/config.toml" true absent true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    create_tooling_codex_stub "$bin_root"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/missing/error.txt"
    status=$?
    assert_equal 1 "$status" "누락 상태 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed missing installed
}

test_tooling_supports_independent_skills_multiple_versions_and_unicode_paths()
{
    local case_root="$TEST_TEMP_ROOT/에이전트 도구 공백 경로"
    local home_root="$case_root/사용자 홈"
    local codex_home="$case_root/Codex 홈"
    local bin_root="$case_root/실행 파일"
    local output_path="$case_root/output.txt"
    local ua_source="$home_root/.understand-anything/repo/understand-anything-plugin/skills/understand"
    local status

    require_file "$TOOLING_SCRIPT" "check-agent-tooling.sh" || return 1
    write_tooling_codex_config "$codex_home/config.toml" absent absent absent
    create_tooling_standalone_skill "$codex_home" karpathy-guidelines
    create_tooling_standalone_skill "$codex_home" using-superpowers
    mkdir -p "$ua_source" "$home_root/.agents/skills"
    printf '%s\n' 'name: understand' > "$ua_source/SKILL.md"
    ln -s "$ua_source" "$home_root/.agents/skills/understand" || return 1
    create_tooling_codex_stub "$bin_root"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 0 "$status" "독립 스킬 상태 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed installed installed || return 1

    write_tooling_codex_config "$codex_home/config.toml" true true true
    rm -rf "$codex_home/skills" "$home_root/.agents"
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills old-version unrelated-skill
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills newest-version karpathy-guidelines
    create_tooling_cache_skill "$codex_home" superpowers old-version unrelated-skill
    create_tooling_cache_skill "$codex_home" superpowers newest-version using-superpowers
    create_tooling_cache_skill "$codex_home" understand-anything old-version unrelated-skill
    create_tooling_cache_skill "$codex_home" understand-anything newest-version understand
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error-multiple.txt"
    status=$?
    assert_equal 0 "$status" "복수 캐시 버전 상태 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed installed installed
}

test_tooling_warns_when_codex_sandbox_blocks_orca()
{
    local case_root="$TEST_TEMP_ROOT/tooling-codex-sandbox"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local name
    local expected
    local config
    local python_path
    local modern_python
    local search_paths="/usr/bin:/bin"

    require_file "$TOOLING_SCRIPT" "check-agent-tooling.sh" || return 1
    create_tooling_codex_stub "$bin_root"
    # Run every case with the system Python (pip's vendored tomli) and, when present, a tomllib Python.
    modern_python=$(command -v python3 2>/dev/null) || modern_python=""
    if [ -n "$modern_python" ] && "$modern_python" -I -B -c 'import tomllib' 2>/dev/null; then
        search_paths="$search_paths $(dirname "$modern_python"):/usr/bin:/bin"
    fi
    for python_path in $search_paths; do
    # name|warn expected|config (\n separated); comments, quoting, inline and dotted tables.
    while IFS='|' read -r name expected config; do
        write_tooling_codex_config "$codex_home/config.toml" true true true
        printf '%b\n' "$config" > "$case_root/sandbox.toml"
        cat "$codex_home/config.toml" >> "$case_root/sandbox.toml"
        mv "$case_root/sandbox.toml" "$codex_home/config.toml"
        # Without the runner-wide bytecode switch: the check itself must not write under HOME or CODEX_HOME.
        (cd "$case_root" && find home codex -type f -exec cksum {} \; 2>/dev/null | LC_ALL=C sort) > "$case_root/before-$name.txt"
        env -u PYTHONDONTWRITEBYTECODE HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:$python_path" bash "$TOOLING_SCRIPT" --check > /dev/null 2> "$case_root/error-$name.txt"
        (cd "$case_root" && find home codex -type f -exec cksum {} \; 2>/dev/null | LC_ALL=C sort) > "$case_root/after-$name.txt"
        if ! cmp -s "$case_root/before-$name.txt" "$case_root/after-$name.txt"; then
            echo "--check가 HOME 또는 CODEX_HOME에 파일을 만들거나 바꿨습니다: $name ($python_path)" >&2
            return 1
        fi
        if [ "$expected" = warn ]; then
            assert_contains "$(cat "$case_root/error-$name.txt")" 'runtime_access_denied' "샌드박스 경고 누락: $name ($python_path)" || return 1
        else
            assert_not_contains "$(cat "$case_root/error-$name.txt")" 'runtime_access_denied' "샌드박스 오경고: $name ($python_path)" || return 1
        fi
    done <<'CASES'
missing|warn|
readonly|warn|sandbox_mode = "read-only"
comment|warn|sandbox_mode = "read-only" # previously "danger-full-access"
write_only|warn|sandbox_mode = "workspace-write"
network_false|warn|sandbox_mode = "workspace-write"\n[sandbox_workspace_write]\nnetwork_access = false
table|ok|sandbox_mode = "workspace-write"\n[sandbox_workspace_write]\nnetwork_access = true
table_comment|ok|sandbox_mode = "workspace-write"\n[sandbox_workspace_write] # local\nnetwork_access = true
inline|ok|sandbox_mode = "workspace-write"\nsandbox_workspace_write = { network_access = true }
single_quote|ok|sandbox_mode = 'danger-full-access'
quoted_key|ok|"sandbox_mode" = "danger-full-access"
comment_quote|ok|sandbox_mode = "danger-full-access" # user's " config
inline_duplicate|warn|sandbox_mode = "workspace-write"\nsandbox_workspace_write = { network_access = false, network_access = true }
unicode_key|ok|"sandbox\\u005fmode" = "danger-full-access"
duplicate_table|warn|sandbox_mode = "workspace-write"\n[sandbox_workspace_write]\nnetwork_access = true\n[sandbox_workspace_write]
scalar_subkey|warn|sandbox_mode = "danger-full-access"\nsandbox_mode.extra = false
triple_quote_comment|ok|sandbox_mode = "danger-full-access" # example: """text"""
CASES
    done
}

test_tooling_repo_only_understand_is_broken_and_check_is_read_only()
{
    local case_root="$TEST_TEMP_ROOT/tooling-readonly"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local before_path="$case_root/before.txt"
    local after_path="$case_root/after.txt"
    local status

    require_file "$TOOLING_SCRIPT" "check-agent-tooling.sh" || return 1
    write_tooling_codex_config "$codex_home/config.toml" true true absent
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers
    mkdir -p "$home_root/.understand-anything/repo/understand-anything-plugin/skills/understand"
    printf '%s\n' 'name: understand' > "$home_root/.understand-anything/repo/understand-anything-plugin/skills/understand/SKILL.md"
    mkdir -p "$home_root/.agents/skills/understand"
    printf '%s\n' 'name: unrelated-understand' > "$home_root/.agents/skills/understand/SKILL.md"
    create_tooling_codex_stub "$bin_root"
    (cd "$case_root" && find home codex -type f -exec cksum {} \; | LC_ALL=C sort) > "$before_path"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 1 "$status" "UA 저장소 단독 상태 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed installed broken || return 1
    (cd "$case_root" && find home codex -type f -exec cksum {} \; | LC_ALL=C sort) > "$after_path"
    if ! cmp -s "$before_path" "$after_path"; then
        echo "--check가 사용자 홈 또는 CODEX_HOME을 변경했습니다." >&2
        return 1
    fi
}

test_tooling_each_required_tool_has_complete_state_matrix()
{
    local case_root="$TEST_TEMP_ROOT/tooling-each-tool-matrix"
    local tool_id
    local plugin_id
    local skill_name
    local target_state
    local config_state
    local home_root
    local codex_home
    local bin_root
    local output_path
    local status
    local expected_karpathy
    local expected_superpowers
    local expected_understand

    for tool_id in karpathy_guidelines superpowers understand_anything; do
        case "$tool_id" in
            karpathy_guidelines) plugin_id=andrej-karpathy-skills; skill_name=karpathy-guidelines ;;
            superpowers) plugin_id=superpowers; skill_name=using-superpowers ;;
            understand_anything) plugin_id=understand-anything; skill_name=understand ;;
        esac
        for target_state in installed disabled broken missing; do
            home_root="$case_root/$tool_id-$target_state/home"
            codex_home="$case_root/$tool_id-$target_state/codex"
            bin_root="$case_root/$tool_id-$target_state/bin"
            output_path="$case_root/$tool_id-$target_state/output.txt"
            mkdir -p "$home_root"
            case "$target_state" in
                installed|broken) config_state=true ;;
                disabled) config_state=false ;;
                missing) config_state=absent ;;
            esac
            case "$tool_id" in
                karpathy_guidelines) write_tooling_codex_config "$codex_home/config.toml" "$config_state" true true ;;
                superpowers) write_tooling_codex_config "$codex_home/config.toml" true "$config_state" true ;;
                understand_anything) write_tooling_codex_config "$codex_home/config.toml" true true "$config_state" ;;
            esac
            if [ "$tool_id" != karpathy_guidelines ] || { [ "$target_state" != broken ] && [ "$target_state" != missing ]; }; then
                create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
            fi
            if [ "$tool_id" != superpowers ] || { [ "$target_state" != broken ] && [ "$target_state" != missing ]; }; then
                create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers
            fi
            if [ "$tool_id" != understand_anything ] || { [ "$target_state" != broken ] && [ "$target_state" != missing ]; }; then
                create_tooling_cache_skill "$codex_home" understand-anything 1 understand
            fi
            create_tooling_codex_stub "$bin_root"
            HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/$tool_id-$target_state/error.txt"
            status=$?
            if [ "$target_state" = installed ]; then
                assert_equal 0 "$status" "$tool_id installed 종료 코드가 다릅니다" || return 1
            else
                assert_equal 1 "$status" "$tool_id $target_state 종료 코드가 다릅니다" || return 1
            fi
            expected_karpathy=installed
            expected_superpowers=installed
            expected_understand=installed
            case "$tool_id" in
                karpathy_guidelines) expected_karpathy=$target_state ;;
                superpowers) expected_superpowers=$target_state ;;
                understand_anything) expected_understand=$target_state ;;
            esac
            assert_tooling_output "$output_path" "$expected_karpathy" "$expected_superpowers" "$expected_understand" || return 1
        done
    done
}

test_tooling_binds_plugin_records_to_exact_marketplace_cache()
{
    local case_root="$TEST_TEMP_ROOT/tooling-marketplace-binding"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local status

    mkdir -p "$home_root"
    write_tooling_codex_config "$codex_home/config.toml" true true true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers other-marketplace
    create_tooling_codex_stub "$bin_root"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 1 "$status" "교차 marketplace 캐시 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed broken installed || return 1

    create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error-stale.txt"
    status=$?
    assert_equal 0 "$status" "유효 설치와 함께 남은 stale 캐시를 broken으로 처리했습니다" || return 1
    assert_tooling_output "$output_path" installed installed installed || return 1

    rm -rf "$codex_home/plugins/cache/other-marketplace"
    mkdir -p "$codex_home/plugins/cache/test-marketplace/extra/superpowers/1/skills/using-superpowers"
    printf '%s\n' 'name: using-superpowers' > "$codex_home/plugins/cache/test-marketplace/extra/superpowers/1/skills/using-superpowers/SKILL.md"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error-depth.txt"
    status=$?
    assert_equal 1 "$status" "잘못된 캐시 깊이 종료 코드가 다릅니다" || return 1
    assert_tooling_output "$output_path" installed broken installed
}

test_tooling_rejects_duplicate_plugin_installations_and_conflicts()
{
    local case_root="$TEST_TEMP_ROOT/tooling-duplicate-installations"
    local variant
    local home_root
    local codex_home
    local bin_root
    local output_path
    local status

    for variant in duplicate-section duplicate-key conflict; do
        home_root="$case_root/$variant/home"
        codex_home="$case_root/$variant/codex"
        bin_root="$case_root/$variant/bin"
        output_path="$case_root/$variant/output.txt"
        mkdir -p "$home_root"
        write_tooling_codex_config "$codex_home/config.toml" true true true
        case "$variant" in
            duplicate-section)
                printf '%s\n' '[plugins."superpowers@test-marketplace"]' 'enabled = true' >> "$codex_home/config.toml"
                ;;
            duplicate-key)
                printf '%s\n' 'enabled = true' >> "$codex_home/config.toml"
                ;;
            conflict)
                printf '%s\n' 'enabled = false' >> "$codex_home/config.toml"
                ;;
        esac
        create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
        create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers
        create_tooling_cache_skill "$codex_home" understand-anything 1 understand
        create_tooling_codex_stub "$bin_root"
        HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/$variant/error.txt"
        status=$?
        assert_equal 1 "$status" "$variant 종료 코드가 다릅니다" || return 1
        if [ "$variant" = duplicate-section ]; then
            assert_tooling_output "$output_path" installed broken installed || return 1
        else
            assert_tooling_output "$output_path" installed installed broken || return 1
        fi
    done
}

test_tooling_conf_parser_rejects_extra_and_indented_data()
{
    local case_root="$TEST_TEMP_ROOT/tooling-conf-strict"
    local fixture_root
    local script_path
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local status

    create_tooling_installed_fixture "$home_root" "$codex_home" "$bin_root"
    for fixture_root in "$case_root/trailing" "$case_root/indented"; do
        create_tooling_script_fixture "$fixture_root/.agents"
        script_path="$fixture_root/.agents/scripts/setup/check-agent-tooling.sh"
        printf '%s\n' \
            'karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required' \
            'superpowers|superpowers|obra/superpowers|required' \
            'understand_anything|understand-anything|Egonex-AI/Understand-Anything|required' > "$fixture_root/.agents/config/agent-tooling.conf"
        if [ "$fixture_root" = "$case_root/trailing" ]; then
            printf '%s\n' 'superpowers|superpowers|obra/superpowers|required|' >> "$fixture_root/.agents/config/agent-tooling.conf"
        else
            printf '%s\n' '  superpowers|superpowers|obra/superpowers|required' >> "$fixture_root/.agents/config/agent-tooling.conf"
        fi
        HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$script_path" --check >/dev/null 2>&1
        status=$?
        assert_equal 2 "$status" "엄격 도구 설정 파서가 잘못된 행을 허용했습니다" || return 1
    done

    fixture_root="$case_root/comments"
    create_tooling_script_fixture "$fixture_root/.agents"
    printf '%s\n' \
        '   ' \
        '    # 들여쓴 주석은 허용합니다.' \
        'karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required' \
        'superpowers|superpowers|obra/superpowers|required' \
        'understand_anything|understand-anything|Egonex-AI/Understand-Anything|required' > "$fixture_root/.agents/config/agent-tooling.conf"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$fixture_root/.agents/scripts/setup/check-agent-tooling.sh" --check >/dev/null 2>&1
    status=$?
    assert_equal 0 "$status" "공백·들여쓴 주석을 거부했습니다"
}

test_tooling_install_mode_stops_on_failure_and_never_repairs_nonmissing()
{
    local case_root="$TEST_TEMP_ROOT/tooling-install-boundary"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local call_log="$case_root/calls.log"
    local output_path="$case_root/output.txt"
    local status

    require_file "$TOOLING_SCRIPT" "check-agent-tooling.sh" || return 1
    mkdir -p "$home_root" "$codex_home/skills/.system/skill-installer/scripts" "$bin_root"
    printf '%s\n' '# placeholder' > "$codex_home/skills/.system/skill-installer/scripts/install-skill-from-github.py"
    : > "$codex_home/config.toml"
    printf '%s\n' '#!/bin/sh' 'printf "python3|%s\n" "$*" >> "$TOOLING_CALL_LOG"' 'exit 9' > "$bin_root/python3"
    printf '%s\n' '#!/bin/sh' 'printf "codex|%s\n" "$*" >> "$TOOLING_CALL_LOG"' 'exit 0' > "$bin_root/codex"
    printf '%s\n' '#!/bin/sh' 'printf "git|%s\n" "$*" >> "$TOOLING_CALL_LOG"' 'exit 0' > "$bin_root/git"
    chmod +x "$bin_root/python3" "$bin_root/codex" "$bin_root/git"
    TOOLING_CALL_LOG="$call_log" HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 3 "$status" "첫 설치 실패 종료 코드가 다릅니다" || return 1
    assert_contains "$(sed -n '1,20p' "$call_log")" 'python3|' "Karpathy 설치 경계를 호출하지 않았습니다" || return 1
    assert_not_contains "$(sed -n '1,20p' "$call_log")" 'codex|' "실패 후 Superpowers 설치를 계속했습니다" || return 1
    assert_not_contains "$(sed -n '1,20p' "$call_log")" 'git|' "실패 후 Understand-Anything 설치를 계속했습니다" || return 1

    : > "$call_log"
    write_tooling_codex_config "$codex_home/config.toml" false true true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    TOOLING_CALL_LOG="$call_log" HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/error-disabled.txt"
    status=$?
    if [ "$status" -eq 0 ]; then
        echo "비활성·손상 상태에서 설치를 성공으로 보고했습니다." >&2
        return 1
    fi
    if [ -s "$call_log" ]; then
        echo "disabled 또는 broken 도구에 설치 명령을 실행했습니다." >&2
        return 1
    fi
}

test_tooling_install_mode_runs_three_missing_branches_in_order()
{
    local case_root="$TEST_TEMP_ROOT/tooling-install-order"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local call_log="$case_root/calls.log"
    local output_path="$case_root/output.txt"
    local expected_log="$case_root/expected.log"
    local status

    mkdir -p "$home_root" "$codex_home/skills/.system/skill-installer/scripts" "$bin_root"
    : > "$codex_home/config.toml"
    printf '%s\n' '# placeholder' > "$codex_home/skills/.system/skill-installer/scripts/install-skill-from-github.py"
    printf '%s\n' \
        '#!/bin/sh' \
        'printf "%s\n" karpathy >> "$TOOLING_CALL_LOG"' \
        'mkdir -p "$CODEX_HOME/skills/karpathy-guidelines" || exit 7' \
        'printf "%s\n" "name: karpathy-guidelines" > "$CODEX_HOME/skills/karpathy-guidelines/SKILL.md"' > "$bin_root/python3"
    printf '%s\n' \
        '#!/bin/sh' \
        'if [ "$1" = plugin ] && [ "$2" = add ]; then' \
        '    printf "%s\n" superpowers >> "$TOOLING_CALL_LOG"' \
        '    mkdir -p "$CODEX_HOME/skills/using-superpowers" || exit 7' \
        '    printf "%s\n" "name: using-superpowers" > "$CODEX_HOME/skills/using-superpowers/SKILL.md"' \
        'fi' \
        'exit 0' > "$bin_root/codex"
    printf '%s\n' \
        '#!/bin/sh' \
        'case "$2" in' \
        '    *superpowers*)' \
        '        printf "%s\n" superpowers >> "$TOOLING_CALL_LOG"' \
        '        mkdir -p "$3/skills/using-superpowers" || exit 7' \
        '        printf "%s\n" "name: using-superpowers" > "$3/skills/using-superpowers/SKILL.md"' \
        '        ;;' \
        '    *Understand-Anything*)' \
        '        printf "%s\n" understand >> "$TOOLING_CALL_LOG"' \
        '        mkdir -p "$3" || exit 7' \
        '        printf "%s\n" "#!/bin/sh" "printf \"%s\\n\" understand-installer >> \"\$TOOLING_CALL_LOG\"" "source=\"\$HOME/.understand-anything/repo/understand-anything-plugin/skills/understand\"" "mkdir -p \"\$source\" \"\$HOME/.agents/skills\"" "printf \"%s\\n\" \"name: understand\" > \"\$source/SKILL.md\"" "ln -s \"\$source\" \"\$HOME/.agents/skills/understand\"" > "$3/install.sh"' \
        '        ;;' \
        '    *) exit 8 ;;' \
        'esac' > "$bin_root/git"
    chmod +x "$bin_root/python3" "$bin_root/codex" "$bin_root/git"

    TOOLING_CALL_LOG="$call_log" HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 0 "$status" "3개 누락 도구 순차 설치가 실패했습니다" || return 1
    assert_tooling_output "$output_path" installed installed installed || return 1
    printf '%s\n' karpathy superpowers understand understand-installer > "$expected_log"
    if ! cmp -s "$expected_log" "$call_log"; then
        echo "3개 누락 도구 설치 순서가 다릅니다." >&2
        diff -u "$expected_log" "$call_log" >&2 || true
        return 1
    fi
}

test_tooling_toml_target_sections_reject_conflicts_and_malformed_headers()
{
    local case_root="$TEST_TEMP_ROOT/tooling-toml-contract"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local status

    require_file "$TOOLING_SCRIPT" "check-agent-tooling.sh" || return 1
    mkdir -p "$home_root" "$codex_home" "$bin_root"
    create_tooling_codex_stub "$bin_root"
    create_tooling_standalone_skill "$codex_home" using-superpowers
    create_tooling_standalone_skill "$codex_home" understand

    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    printf '%s\n' \
        '[plugins."andrej-karpathy-skills@one"]' \
        'enabled = true' \
        '[plugins."andrej-karpathy-skills@two"]' \
        'enabled = true' > "$codex_home/config.toml"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/duplicate-error.txt"
    status=$?
    assert_equal 1 "$status" "TOML 중복 타겟 섹션을 broken으로 처리하지 않았습니다" || return 1
    assert_tooling_output "$output_path" broken installed installed || return 1

    printf '%s\n' \
        '[plugins."andrej-karpathy-skills@one"]' \
        'enabled = true' \
        '[plugins."andrej-karpathy-skills@two"]' \
        'enabled = false' > "$codex_home/config.toml"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/conflict-error.txt"
    status=$?
    assert_equal 1 "$status" "TOML enabled 충돌을 broken으로 처리하지 않았습니다" || return 1
    assert_tooling_output "$output_path" broken installed installed || return 1

    printf '%s\n' \
        '[plugins."andrej-karpathy-skills@one"]' \
        'name = "missing-enabled"' > "$codex_home/config.toml"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/missing-enabled-error.txt"
    status=$?
    assert_equal 1 "$status" "TOML enabled 누락을 broken으로 처리하지 않았습니다" || return 1
    assert_tooling_output "$output_path" broken installed installed || return 1

    rm -rf "$codex_home/plugins"
    printf '%s\n' \
        '[plugins."andrej-karpathy-skills@broken"' \
        'enabled = true' > "$codex_home/config.toml"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/malformed-header-error.txt"
    status=$?
    assert_equal 1 "$status" "손상된 TOML 타겟 헤더를 broken으로 처리하지 않았습니다" || return 1
    assert_tooling_output "$output_path" broken installed installed || return 1

    printf '%s\n' \
        '[plugins."superpowers"]' \
        'enabled = true' > "$codex_home/config.toml"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/missing-marketplace-error.txt"
    status=$?
    assert_equal 1 "$status" "marketplace가 빠진 타겟 헤더를 broken으로 처리하지 않았습니다" || return 1
    assert_tooling_output "$output_path" missing broken installed
}

test_tooling_cache_detection_requires_exact_directory_depth()
{
    local case_root="$TEST_TEMP_ROOT/tooling-cache-depth"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local deep_skill="$codex_home/plugins/cache/extra/depth/test-marketplace/andrej-karpathy-skills/1/skills/karpathy-guidelines/SKILL.md"
    local status

    mkdir -p "$(dirname "$deep_skill")"
    printf '%s\n' 'name: karpathy-guidelines' > "$deep_skill"
    write_tooling_codex_config "$codex_home/config.toml" true absent absent
    create_tooling_standalone_skill "$codex_home" using-superpowers
    create_tooling_standalone_skill "$codex_home" understand
    create_tooling_codex_stub "$bin_root"

    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 1 "$status" "깊은 가짜 캐시를 설치로 인정했습니다" || return 1
    assert_tooling_output "$output_path" broken installed installed
}

test_tooling_rejects_symlinked_cache_root()
{
    local case_root="$TEST_TEMP_ROOT/tooling-symlinked-cache-root"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local external_cache="$case_root/external-cache"
    local output_path="$case_root/output.txt"
    local status

    mkdir -p "$home_root" "$codex_home/plugins" "$external_cache" "$bin_root"
    ln -s "$external_cache" "$codex_home/plugins/cache" || return 1
    write_tooling_codex_config "$codex_home/config.toml" true true true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    create_tooling_codex_stub "$bin_root"

    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 1 "$status" "CODEX_HOME 밖으로 연결된 캐시 루트를 허용했습니다" || return 1
    assert_tooling_output "$output_path" broken broken broken
}

test_tooling_superpowers_official_install_creates_exact_repo_link()
{
    local case_root="$TEST_TEMP_ROOT/tooling-superpowers-install"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local call_log="$case_root/calls.log"
    local output_path="$case_root/output.txt"
    local expected_source="$codex_home/superpowers/skills"
    local actual_source
    local status

    mkdir -p "$home_root" "$codex_home" "$bin_root"
    write_tooling_codex_config "$codex_home/config.toml" absent absent absent
    create_tooling_standalone_skill "$codex_home" karpathy-guidelines
    create_tooling_standalone_skill "$codex_home" understand
    create_tooling_codex_stub "$bin_root"
    create_superpowers_git_stub "$bin_root"
    : > "$call_log"

    TOOLING_CALL_LOG="$call_log" TOOLING_GIT_EXIT=0 HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 0 "$status" "Superpowers 공식 설치 흐름이 실패했습니다" || return 1
    assert_tooling_output "$output_path" installed installed installed || return 1
    assert_file_exists "$codex_home/superpowers/skills/using-superpowers/SKILL.md" "Superpowers 검증 스킬" || return 1
    if [ ! -L "$home_root/.agents/skills/superpowers" ]; then
        echo "Superpowers 공식 스킬 링크가 없습니다." >&2
        return 1
    fi
    actual_source=$(cd "$home_root/.agents/skills/superpowers" 2>/dev/null && pwd -P) || return 1
    expected_source=$(cd "$expected_source" 2>/dev/null && pwd -P) || return 1
    assert_equal "$expected_source" "$actual_source" "Superpowers 스킬 링크 대상이 다릅니다" || return 1
    assert_contains "$(sed -n '1,10p' "$call_log")" "git|clone https://github.com/obra/superpowers.git" "Superpowers 공식 저장소를 clone하지 않았습니다" || return 1
    assert_not_contains "$(sed -n '1,10p' "$call_log")" 'codex|' "Superpowers 설치에 플러그인 마켓 명령을 호출했습니다" || return 1
    assert_not_contains "$(sed -n '1,760p' "$TOOLING_SCRIPT")" 'codex plugin marketplace add' "Superpowers 직접 마켓 설치 코드가 남아 있습니다"
}

test_tooling_superpowers_staging_failure_is_retryable()
{
    local case_root="$TEST_TEMP_ROOT/tooling-superpowers-retry"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local call_log="$case_root/calls.log"
    local output_path="$case_root/output.txt"
    local status

    mkdir -p "$home_root" "$codex_home" "$bin_root"
    write_tooling_codex_config "$codex_home/config.toml" absent absent absent
    create_tooling_standalone_skill "$codex_home" karpathy-guidelines
    create_tooling_standalone_skill "$codex_home" understand
    create_tooling_codex_stub "$bin_root"
    create_superpowers_git_stub "$bin_root"
    : > "$call_log"

    TOOLING_CALL_LOG="$call_log" TOOLING_GIT_EXIT=9 HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/first-error.txt"
    status=$?
    assert_equal 3 "$status" "Superpowers clone 실패 종료 코드가 다릅니다" || return 1
    assert_file_not_exists "$codex_home/superpowers" "clone 실패 후 완성 저장소" || return 1

    TOOLING_CALL_LOG="$call_log" TOOLING_GIT_EXIT=0 HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/retry-error.txt"
    status=$?
    assert_equal 0 "$status" "Superpowers clone 재시도가 실패했습니다" || return 1
    assert_tooling_output "$output_path" installed installed installed
}

test_tooling_understand_failure_cleans_link_and_is_retryable()
{
    local case_root="$TEST_TEMP_ROOT/tooling-understand-retry"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local link_path="$home_root/.agents/skills/understand"
    local status

    mkdir -p "$home_root" "$codex_home" "$bin_root"
    write_tooling_codex_config "$codex_home/config.toml" absent absent absent
    create_tooling_standalone_skill "$codex_home" karpathy-guidelines
    create_tooling_standalone_skill "$codex_home" using-superpowers
    create_tooling_codex_stub "$bin_root"
    printf '%s\n' \
        '#!/bin/sh' \
        'mkdir -p "$3/understand-anything-plugin/skills/understand"' \
        'printf "%s\n" "name: understand" > "$3/understand-anything-plugin/skills/understand/SKILL.md"' \
        'printf "%s\n" "#!/bin/sh" "source=\"\$HOME/.understand-anything/repo/understand-anything-plugin/skills/understand\"" "link=\"\$HOME/.agents/skills/understand\"" "mkdir -p \"\$HOME/.agents/skills\"" "ln -s \"\$source\" \"\$link\"" "if [ \"\$TOOLING_UA_FAIL\" = 1 ]; then exit 9; fi" > "$3/install.sh"' \
        'exit 0' > "$bin_root/git"
    chmod +x "$bin_root/git"

    TOOLING_UA_FAIL=1 HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/first-error.txt"
    status=$?
    assert_equal 3 "$status" "Understand installer 실패 종료 코드가 다릅니다" || return 1
    assert_file_not_exists "$home_root/.understand-anything/repo" "Understand 실패 후 완성 저장소" || return 1
    if [ -e "$link_path" ] || [ -L "$link_path" ]; then
        echo "Understand 실패 후 전역 스킬 링크가 남았습니다." >&2
        return 1
    fi

    TOOLING_UA_FAIL=0 HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/retry-error.txt"
    status=$?
    assert_equal 0 "$status" "Understand installer 실패 후 재시도가 실패했습니다" || return 1
    assert_tooling_output "$output_path" installed installed installed
}

test_tooling_install_rejects_unsafe_home_paths_before_commands()
{
    local case_root="$TEST_TEMP_ROOT/tooling-unsafe-home"
    local safe_home="$case_root/home"
    local safe_codex="$case_root/codex"
    local bin_root="$case_root/bin"
    local call_log="$case_root/calls.log"
    local status

    mkdir -p "$safe_home" "$safe_codex" "$bin_root"
    create_tooling_codex_stub "$bin_root"
    printf '%s\n' '#!/bin/sh' 'printf "git|%s\n" "$*" >> "$TOOLING_CALL_LOG"' 'exit 0' > "$bin_root/git"
    printf '%s\n' '#!/bin/sh' 'printf "python3|%s\n" "$*" >> "$TOOLING_CALL_LOG"' 'exit 0' > "$bin_root/python3"
    chmod +x "$bin_root/git" "$bin_root/python3"
    : > "$call_log"

    TOOLING_CALL_LOG="$call_log" HOME='relative-home' CODEX_HOME="$safe_codex" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing >/dev/null 2> "$case_root/relative-home-error.txt"
    status=$?
    assert_equal 2 "$status" "상대 HOME 거부 코드가 다릅니다" || return 1
    TOOLING_CALL_LOG="$call_log" HOME='relative-home' CODEX_HOME="$safe_codex" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check >/dev/null 2> "$case_root/relative-home-check-error.txt"
    status=$?
    assert_equal 2 "$status" "check 모드 상대 HOME 거부 코드가 다릅니다" || return 1

    TOOLING_CALL_LOG="$call_log" HOME="$safe_home" CODEX_HOME='relative-codex' PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing >/dev/null 2> "$case_root/relative-codex-error.txt"
    status=$?
    assert_equal 2 "$status" "상대 CODEX_HOME 거부 코드가 다릅니다" || return 1
    TOOLING_CALL_LOG="$call_log" HOME="$safe_home" CODEX_HOME='relative-codex' PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check >/dev/null 2> "$case_root/relative-codex-check-error.txt"
    status=$?
    assert_equal 2 "$status" "check 모드 상대 CODEX_HOME 거부 코드가 다릅니다" || return 1

    TOOLING_CALL_LOG="$call_log" HOME='/' CODEX_HOME="$safe_codex" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing >/dev/null 2> "$case_root/root-home-error.txt"
    status=$?
    assert_equal 2 "$status" "루트 HOME 거부 코드가 다릅니다" || return 1
    TOOLING_CALL_LOG="$call_log" HOME='/' CODEX_HOME="$safe_codex" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check >/dev/null 2> "$case_root/root-home-check-error.txt"
    status=$?
    assert_equal 2 "$status" "check 모드 루트 HOME 거부 코드가 다릅니다" || return 1

    TOOLING_CALL_LOG="$call_log" HOME="$safe_home" CODEX_HOME='/' PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing >/dev/null 2> "$case_root/root-codex-error.txt"
    status=$?
    assert_equal 2 "$status" "루트 CODEX_HOME 거부 코드가 다릅니다" || return 1
    TOOLING_CALL_LOG="$call_log" HOME="$safe_home" CODEX_HOME='/' PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check >/dev/null 2> "$case_root/root-codex-check-error.txt"
    status=$?
    assert_equal 2 "$status" "check 모드 루트 CODEX_HOME 거부 코드가 다릅니다" || return 1

    if [ -s "$call_log" ]; then
        echo "위험한 HOME/CODEX_HOME 거부 전에 설치 명령을 실행했습니다." >&2
        return 1
    fi
}

test_tooling_install_rejects_escaped_child_roots_before_commands()
{
    local case_root="$TEST_TEMP_ROOT/tooling-escaped-child-roots"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local external_agents="$case_root/external-agents"
    local external_understand="$case_root/external-understand"
    local call_log="$case_root/calls.log"
    local output_path="$case_root/output.txt"
    local status

    mkdir -p "$home_root" "$codex_home" "$bin_root" "$external_agents" "$external_understand"
    write_tooling_codex_config "$codex_home/config.toml" absent absent absent
    create_tooling_standalone_skill "$codex_home" karpathy-guidelines
    create_tooling_standalone_skill "$codex_home" understand
    create_tooling_codex_stub "$bin_root"
    create_superpowers_git_stub "$bin_root"
    ln -s "$external_agents" "$home_root/.agents" || return 1
    : > "$call_log"

    TOOLING_CALL_LOG="$call_log" TOOLING_GIT_EXIT=0 HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/agents-error.txt"
    status=$?
    assert_equal 3 "$status" "HOME 밖으로 연결된 .agents 하위에 설치했습니다" || return 1
    if [ -s "$call_log" ]; then
        echo "탈출한 .agents 경로를 거부하기 전에 설치 명령을 실행했습니다." >&2
        return 1
    fi

    rm -f "$home_root/.agents"
    ln -s "$external_understand" "$home_root/.understand-anything" || return 1
    create_tooling_standalone_skill "$codex_home" using-superpowers
    rm -rf "$codex_home/skills/understand"
    printf '%s\n' '#!/bin/sh' 'printf "git|%s\n" "$*" >> "$TOOLING_CALL_LOG"' 'exit 9' > "$bin_root/git"
    chmod +x "$bin_root/git"
    : > "$call_log"

    TOOLING_CALL_LOG="$call_log" HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing > "$output_path" 2> "$case_root/understand-error.txt"
    status=$?
    assert_equal 3 "$status" "HOME 밖으로 연결된 Understand 저장소 하위에 설치했습니다" || return 1
    if [ -s "$call_log" ]; then
        echo "탈출한 .understand-anything 경로를 거부하기 전에 설치 명령을 실행했습니다." >&2
        return 1
    fi
}

test_tooling_rejects_malformed_plugin_config_even_with_standalone_skills()
{
    local case_root="$TEST_TEMP_ROOT/tooling-malformed-with-standalone"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local status

    mkdir -p "$home_root" "$codex_home"
    printf '%s\n' \
        '[plugins."andrej-karpathy-skills@test-marketplace"]' 'enabled = invalid' \
        '[plugins."superpowers@test-marketplace"]' 'enabled = invalid' \
        '[plugins."understand-anything@test-marketplace"]' 'enabled = invalid' > "$codex_home/config.toml"
    create_tooling_standalone_skill "$codex_home" karpathy-guidelines
    create_tooling_standalone_skill "$codex_home" using-superpowers
    create_tooling_standalone_skill "$codex_home" understand
    create_tooling_codex_stub "$bin_root"

    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 1 "$status" "손상된 플러그인 설정을 독립 스킬로 가렸습니다" || return 1
    assert_tooling_output "$output_path" broken broken broken
}

test_tooling_accepts_exact_superpowers_repo_link()
{
    local case_root="$TEST_TEMP_ROOT/tooling-legacy-superpowers-link"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local legacy_source="$codex_home/superpowers/skills"
    local status

    mkdir -p "$home_root/.agents/skills" "$legacy_source/using-superpowers"
    printf '%s\n' 'name: using-superpowers' > "$legacy_source/using-superpowers/SKILL.md"
    ln -s "$legacy_source" "$home_root/.agents/skills/superpowers"
    create_tooling_standalone_skill "$codex_home" karpathy-guidelines
    create_tooling_standalone_skill "$codex_home" understand
    create_tooling_codex_stub "$bin_root"

    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 0 "$status" "Superpowers 공식 저장소 링크를 정상 설치로 인정하지 않았습니다" || return 1
    assert_tooling_output "$output_path" installed installed installed
}

test_tooling_rejects_symlinked_cache_versions()
{
    local case_root="$TEST_TEMP_ROOT/tooling-symlinked-cache-version"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local output_path="$case_root/output.txt"
    local external_version="$case_root/external-version"
    local plugin_root="$codex_home/plugins/cache/test-marketplace/superpowers"
    local status

    mkdir -p "$home_root" "$external_version/skills/using-superpowers" "$plugin_root"
    printf '%s\n' 'name: using-superpowers' > "$external_version/skills/using-superpowers/SKILL.md"
    ln -s "$external_version" "$plugin_root/1"
    write_tooling_codex_config "$codex_home/config.toml" true true true
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    create_tooling_codex_stub "$bin_root"

    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/error.txt"
    status=$?
    assert_equal 1 "$status" "캐시 버전 심볼릭 링크를 정상 설치로 인정했습니다" || return 1
    assert_tooling_output "$output_path" installed broken installed || return 1

    rm -f "$plugin_root/1"
    mkdir -p "$plugin_root/1"
    ln -s "$external_version/skills" "$plugin_root/1/skills"
    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --check > "$output_path" 2> "$case_root/nested-error.txt"
    status=$?
    assert_equal 1 "$status" "캐시 내부 skills 심볼릭 링크를 정상 설치로 인정했습니다" || return 1
    assert_tooling_output "$output_path" installed broken installed
}

test_tooling_config_rejects_leading_whitespace_rows_but_allows_comments()
{
    local case_root="$TEST_TEMP_ROOT/tooling-config-whitespace"
    local fixture_agents="$case_root/.agents"
    local fixture_script="$fixture_agents/scripts/setup/check-agent-tooling.sh"
    local status

    create_tooling_script_fixture "$fixture_agents" || return 1
    printf '%s\n' \
        '  # 앞 공백 주석은 허용' \
        '   ' \
        ' karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required' \
        'superpowers|superpowers|obra/superpowers|required' \
        'understand_anything|understand-anything|Egonex-AI/Understand-Anything|required' > "$fixture_agents/config/agent-tooling.conf"

    HOME="$case_root/home" CODEX_HOME="$case_root/codex" PATH="/usr/bin:/bin" bash "$fixture_script" --check >/dev/null 2> "$case_root/error.txt"
    status=$?
    assert_equal 2 "$status" "앞 공백 도구 설정 행 거부 코드가 다릅니다" || return 1
    assert_contains "$(sed -n '1,20p' "$case_root/error.txt")" '앞 공백' "앞 공백 설정 행 오류가 분명하지 않습니다"
}

test_tooling_recovery_commands_are_exact_and_lint_is_decoupled()
{
    local case_root="$TEST_TEMP_ROOT/tooling-recovery"
    local home_root="$case_root/home"
    local codex_home="$case_root/codex"
    local bin_root="$case_root/bin"
    local error_path="$case_root/error.txt"
    local status

    mkdir -p "$home_root" "$codex_home" "$bin_root"
    write_tooling_codex_config "$codex_home/config.toml" false false false
    create_tooling_cache_skill "$codex_home" andrej-karpathy-skills 1 karpathy-guidelines
    create_tooling_cache_skill "$codex_home" superpowers 1 using-superpowers
    create_tooling_cache_skill "$codex_home" understand-anything 1 understand
    create_tooling_codex_stub "$bin_root"

    HOME="$home_root" CODEX_HOME="$codex_home" PATH="$bin_root:/usr/bin:/bin" bash "$TOOLING_SCRIPT" --install-missing >/dev/null 2> "$error_path"
    status=$?
    assert_equal 1 "$status" "disabled/broken 자동 복구 거부 코드가 다릅니다" || return 1
    assert_contains "$(cat "$error_path")" 'disabled 상태' "disabled 복구 선행 조건이 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'config.toml을 비파괴 백업' "설정 비파괴 백업 안내가 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'enabled = false' "disabled 설정 활성화 안내가 없습니다" || return 1
    assert_contains "$(cat "$error_path")" '충돌 경로를 이동한 후' "기존 경로 충돌 해소 안내가 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'check-agent-tooling.sh --check' "복구 후 재검증 명령이 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'install-skill-from-github.py" --repo multica-ai/andrej-karpathy-skills --path skills/karpathy-guidelines' "Karpathy 실행 가능 복구 명령이 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'git clone https://github.com/obra/superpowers.git' "Superpowers clone 복구 명령이 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'ln -s "${CODEX_HOME:-$HOME/.codex}/superpowers/skills"' "Superpowers 스킬 링크 복구 명령이 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'git clone https://github.com/Egonex-AI/Understand-Anything.git' "Understand-Anything clone 복구 명령이 없습니다" || return 1
    assert_contains "$(cat "$error_path")" 'install.sh" codex' "Understand-Anything local install.sh 복구 명령이 없습니다" || return 1
    assert_not_contains "$(sed -n '1,260p' "$CHECK_HARNESS_SCRIPT"; sed -n '1,260p' "$PRE_COMMIT_SCRIPT")" 'check-agent-tooling' "Unity 린트가 도구 설치와 연동되었습니다" || return 1
    assert_document_contains_all "$DOCS_ROOT/onboarding/agent-tooling.md" "도구 복구 명령" \
        'install-skill-from-github.py' \
        'git clone https://github.com/obra/superpowers.git' \
        'AGENT_SKILLS_ROOT="$HOME/.agents"' \
        'ln -s "$CODEX_SUPERPOWERS/skills" "$AGENT_SKILLS/superpowers"' \
        'git clone https://github.com/Egonex-AI/Understand-Anything.git' \
        'install.sh" codex' \
        'Unity 코드 린트 실패로 간주하지 않습니다' || return 1
    assert_document_contains_all "$AGENTS_ROOT/ARCHITECTURE.md" "Superpowers 상태 계약" \
        '${CODEX_HOME:-$HOME/.codex}/superpowers' \
        '사용자 홈의 전역 `superpowers` 스킬 링크' || return 1
    assert_document_contains_all "$AGENTS_ROOT/scripts/README.md" "Superpowers 설치 계약" \
        '실제 설치 명령 실패는 `3`' \
        '공식 저장소를 임시 경로에 clone' \
        '사용자 홈의 전역 `superpowers` 스킬 링크' || return 1
    assert_document_contains_all "$DOCS_ROOT/exec-plans/completed/2026-07-16-universal-unity-harness-plan.md" "Superpowers 실행 계획" \
        'Superpowers: 공식 저장소를 임시 경로에 clone·검증' \
        '사용자 홈의 전역 스킬 디렉터리에 연결'
}

test_tooling_rejects_unknown_arguments_and_documents_workflow()
{
    local status

    require_file "$TOOLING_SCRIPT" "check-agent-tooling.sh" || return 1
    bash "$TOOLING_SCRIPT" --unknown >/dev/null 2>&1
    status=$?
    assert_equal 2 "$status" "알 수 없는 인자 종료 코드가 다릅니다" || return 1
    assert_document_contains_all "$TOOLING_CONFIG" "에이전트 도구 설정 소스" \
        'karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required' \
        'superpowers|superpowers|obra/superpowers|required' \
        'understand_anything|understand-anything|Egonex-AI/Understand-Anything|required' || return 1
    assert_document_contains_all "$DOCS_ROOT/onboarding/agent-tooling.md" "에이전트 도구 적용 시점" \
        'karpathy-guidelines' \
        'superpowers' \
        'understand-chat' \
        'understand-explain' \
        'understand-diff' \
        'understand-onboard' \
        'graphify가 없고 Understand 그래프(`.ua/knowledge-graph.json`)가 이미 있을 때만' \
        'Pipeline 최신 유지 규칙에 따라' \
        'Unity 코드 린트 실패로 간주하지 않습니다'
}

test_milestone_prebuild_requires_all_automated_tests()
{
    local integration_evidence_path="$TEST_TEMP_ROOT/milestone-prebuild-integration-test.conf"
    local compile_evidence_path="$TEST_TEMP_ROOT/milestone-prebuild-compile-test.conf"
    local unit_evidence_path="$TEST_TEMP_ROOT/milestone-prebuild-unit-test.conf"
    local status

    write_milestone_evidence "$integration_evidence_path" not_run pending
    bash "$MILESTONE_VALIDATOR" --evidence "$integration_evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "prebuild 자동 테스트 누락 종료 코드가 다릅니다" || return 1

    write_milestone_evidence "$compile_evidence_path" passed pending
    sed -i.bak 's/^compile=passed$/compile=not_run/' "$compile_evidence_path"
    rm -f "$compile_evidence_path.bak"
    bash "$MILESTONE_VALIDATOR" --evidence "$compile_evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "prebuild 컴파일 미실행 종료 코드가 다릅니다" || return 1

    write_milestone_evidence "$unit_evidence_path" passed pending
    sed -i.bak 's/^unit_test=passed$/unit_test=failed/' "$unit_evidence_path"
    rm -f "$unit_evidence_path.bak"
    bash "$MILESTONE_VALIDATOR" --evidence "$unit_evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "prebuild 단위 테스트 실패 종료 코드가 다릅니다"
}

test_milestone_prebuild_rejects_uncovered_records()
{
    local evidence_path="$TEST_TEMP_ROOT/milestone-prebuild-uncovered-record.conf"
    local status

    write_milestone_evidence "$evidence_path" passed pending
    printf '%s\n' 'interaction_result=Inventory>Reward|Game.Tests.InventoryRewardFlowTests|missing' >> "$evidence_path"
    bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "prebuild 미커버 기록 거부 종료 코드가 다릅니다"
}

test_milestone_build_requires_prebuild_contract()
{
    local evidence_path="$TEST_TEMP_ROOT/milestone-build-prebuild-contract.conf"
    local status

    write_milestone_evidence "$evidence_path" passed pending
    bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 0 "$status" "정상 prebuild 증거가 실패했습니다" || return 1

    bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase built --change-id commit-abc123 --expected-authority local >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "pending 빌드 검증 종료 코드가 다릅니다" || return 1

    sed -i.bak \
        -e 's/^build_validation=pending$/build_validation=passed/' \
        -e 's/^build_run_id=pending$/build_run_id=local-build-20260719-001/' \
        -e 's/^build_artifact_hash=pending$/build_artifact_hash=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef/' \
        "$evidence_path"
    rm -f "$evidence_path.bak"
    sed -i.bak 's/^integration_test=passed$/integration_test=not_run/' "$evidence_path"
    rm -f "$evidence_path.bak"
    bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase built --change-id commit-abc123 --expected-authority local >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "사전 조건이 깨진 빌드 검증 종료 코드가 다릅니다" || return 1

    sed -i.bak 's/^integration_test=not_run$/integration_test=passed/' "$evidence_path"
    rm -f "$evidence_path.bak"
    bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase built --change-id commit-abc123 --expected-authority local >/dev/null 2>&1
    status=$?
    assert_equal 0 "$status" "완료된 빌드 검증 증거가 실패했습니다"
}

test_milestone_rejects_different_change_id()
{
    local evidence_path="$TEST_TEMP_ROOT/milestone-change-id.conf"
    local status

    write_milestone_evidence "$evidence_path" passed pending
    bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase prebuild --change-id commit-other >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "다른 change_id 거부 종료 코드가 다릅니다"
}

test_milestone_rejects_invalid_arguments_and_nonregular_evidence()
{
    local case_root="$TEST_TEMP_ROOT/milestone-invalid-arguments"
    local evidence_path="$case_root/evidence.conf"
    local evidence_link="$case_root/evidence-link.conf"
    local status

    mkdir -p "$case_root/evidence-directory" || return 1
    write_milestone_evidence "$evidence_path" passed pending

    bash "$MILESTONE_VALIDATOR" --unknown >/dev/null 2>&1
    status=$?
    assert_equal 3 "$status" "알 수 없는 마일스톤 검증 인자 종료 코드가 다릅니다" || return 1

    bash "$MILESTONE_VALIDATOR" --evidence >/dev/null 2>&1
    status=$?
    assert_equal 3 "$status" "값이 누락된 evidence 인자 종료 코드가 다릅니다" || return 1

    bash "$MILESTONE_VALIDATOR" --evidence "$case_root/evidence-directory" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "디렉터리 evidence 종료 코드가 다릅니다" || return 1

    ln -s "$evidence_path" "$evidence_link" || return 1
    bash "$MILESTONE_VALIDATOR" --evidence "$evidence_link" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "심볼릭 링크 evidence 종료 코드가 다릅니다"
}

test_milestone_rejects_malformed_files_and_symlinked_profile()
{
    local case_root="$TEST_TEMP_ROOT/milestone-malformed-files"
    local malformed_evidence_path="$case_root/malformed-evidence.conf"
    local fixture_root="$case_root/fixture"
    local fixture_validator
    local fixture_profile
    local profile_target
    local status

    mkdir -p "$case_root" || return 1
    printf '%s\n' 'malformed evidence' > "$malformed_evidence_path"
    bash "$MILESTONE_VALIDATOR" --evidence "$malformed_evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "형식이 잘못된 evidence 종료 코드가 다릅니다" || return 1

    create_milestone_validator_fixture "$fixture_root" || return 1
    fixture_validator="$fixture_root/.agents/scripts/validation/check-unity-milestone.sh"
    printf '%s\n' 'malformed schema' > "$fixture_root/.agents/config/unity-milestone-validation-schema.conf"
    bash "$fixture_validator" --evidence "$fixture_root/.agents/config/evidence.conf" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "형식이 잘못된 schema 종료 코드가 다릅니다" || return 1

    create_milestone_validator_fixture "$fixture_root/symlink-profile" || return 1
    fixture_validator="$fixture_root/symlink-profile/.agents/scripts/validation/check-unity-milestone.sh"
    fixture_profile="$fixture_root/symlink-profile/.agents/scripts/shared/profile.sh"
    profile_target="$fixture_root/symlink-profile/profile-target.sh"
    mv "$fixture_profile" "$profile_target" || return 1
    ln -s "$profile_target" "$fixture_profile" || return 1
    bash "$fixture_validator" --evidence "$fixture_root/symlink-profile/.agents/config/evidence.conf" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "심볼릭 링크 profile.sh 종료 코드가 다릅니다"
}

test_milestone_rejects_invalid_result_records()
{
    local case_root="$TEST_TEMP_ROOT/milestone-invalid-records"
    local evidence_path="$case_root/evidence.conf"
    local replacement
    local status
    local test_case

    mkdir -p "$case_root" || return 1
    for test_case in missing-delimiter extra-delimiter blank-subject blank-test-id non-passed
    do
        write_milestone_evidence "$evidence_path" passed pending
        case "$test_case" in
            missing-delimiter)
                replacement='module_result=Login|Game.Tests.LoginModuleTests'
                sed -i.bak "s@^module_result=.*@$replacement@" "$evidence_path"
                ;;
            extra-delimiter)
                replacement='interaction_result=Login>Profile|Game.Tests.LoginProfileFlowTests|passed|extra'
                sed -i.bak "s@^interaction_result=.*@$replacement@" "$evidence_path"
                ;;
            blank-subject)
                replacement='module_result=|Game.Tests.LoginModuleTests|passed'
                sed -i.bak "s@^module_result=.*@$replacement@" "$evidence_path"
                ;;
            blank-test-id)
                replacement='interaction_result=Login>Profile||passed'
                sed -i.bak "s@^interaction_result=.*@$replacement@" "$evidence_path"
                ;;
            non-passed)
                replacement='module_result=Login|Game.Tests.LoginModuleTests|failed'
                sed -i.bak "s@^module_result=.*@$replacement@" "$evidence_path"
                ;;
        esac
        rm -f "$evidence_path.bak"

        bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
        status=$?
        assert_equal 1 "$status" "$test_case 결과 기록 거부 종료 코드가 다릅니다" || return 1
    done
}

test_milestone_rejects_whitespace_identifiers()
{
    local case_root="$TEST_TEMP_ROOT/milestone-whitespace-identifiers"
    local evidence_path="$case_root/evidence.conf"
    local expected_change_id
    local replacement
    local status
    local test_case

    mkdir -p "$case_root" || return 1
    for test_case in milestone-blank milestone-trim change-blank change-trim subject-blank subject-trim test-id-blank test-id-trim
    do
        write_milestone_evidence "$evidence_path" passed pending
        expected_change_id=commit-abc123
        case "$test_case" in
            milestone-blank)
                sed -i.bak 's/^milestone_id=.*/milestone_id=   /' "$evidence_path"
                ;;
            milestone-trim)
                sed -i.bak 's/^milestone_id=.*/milestone_id= login-flow /' "$evidence_path"
                ;;
            change-blank)
                sed -i.bak 's/^change_id=.*/change_id=   /' "$evidence_path"
                expected_change_id='   '
                ;;
            change-trim)
                sed -i.bak 's/^change_id=.*/change_id= commit-abc123 /' "$evidence_path"
                expected_change_id=' commit-abc123 '
                ;;
            subject-blank)
                replacement='module_result=   |Game.Tests.LoginModuleTests|passed'
                sed -i.bak "s@^module_result=.*@$replacement@" "$evidence_path"
                ;;
            subject-trim)
                replacement='module_result= Login |Game.Tests.LoginModuleTests|passed'
                sed -i.bak "s@^module_result=.*@$replacement@" "$evidence_path"
                ;;
            test-id-blank)
                replacement='interaction_result=Login>Profile|   |passed'
                sed -i.bak "s@^interaction_result=.*@$replacement@" "$evidence_path"
                ;;
            test-id-trim)
                replacement='interaction_result=Login>Profile| Game.Tests.LoginProfileFlowTests |passed'
                sed -i.bak "s@^interaction_result=.*@$replacement@" "$evidence_path"
                ;;
        esac
        rm -f "$evidence_path.bak"

        bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase prebuild --change-id "$expected_change_id" >/dev/null 2>&1
        status=$?
        assert_equal 1 "$status" "$test_case 공백 식별자 거부 종료 코드가 다릅니다" || return 1
    done
}

test_milestone_example_is_valid_and_read_only()
{
    local example_path="$AGENTS_ROOT/config/unity-milestone-validation.example.conf"
    local before_hash
    local after_hash
    local status

    before_hash=$(shasum -a 256 "$example_path") || return 1
    bash "$MILESTONE_VALIDATOR" --evidence "$example_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 0 "$status" "마일스톤 예제 prebuild 검증 종료 코드가 다릅니다" || return 1
    after_hash=$(shasum -a 256 "$example_path") || return 1
    assert_equal "$before_hash" "$after_hash" "마일스톤 예제 파일이 검증 중 변경되었습니다"
}

test_milestone_propagates_profile_api_failure_as_input_error()
{
    local fixture_root="$TEST_TEMP_ROOT/milestone-profile-api-failure"
    local fixture_agents_root="$fixture_root/.agents"
    local fixture_validator="$fixture_agents_root/scripts/validation/check-unity-milestone.sh"
    local status

    create_milestone_validator_fixture "$fixture_root" || return 1
    printf '%s\n' \
        'profile_load() { return 0; }' \
        'profile_get() { return 17; }' \
        'profile_get_all() { return 17; }' > "$fixture_agents_root/scripts/shared/profile.sh"

    bash "$fixture_validator" --evidence "$fixture_agents_root/config/evidence.conf" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "profile_get 실패가 입력 오류로 전파되지 않았습니다"
}

test_milestone_requires_exact_confirmed_scope_coverage()
{
    local case_root="$TEST_TEMP_ROOT/milestone-exact-scope-coverage"
    local fixture_root
    local fixture_validator
    local evidence_path
    local status
    local test_case

    for test_case in missing-module missing-interaction unexpected-result duplicate-result duplicate-scope blank-scope none-scope trimmed-scope delimiter-scope
    do
        fixture_root="$case_root/$test_case"
        create_milestone_validator_v2_fixture "$fixture_root" || return 1
        fixture_validator="$fixture_root/.agents/scripts/validation/check-unity-milestone.sh"
        evidence_path="$fixture_root/.agents/config/evidence.conf"

        case "$test_case" in
            missing-module)
                sed -i.bak '/^module_result=Profile|/d' "$evidence_path"
                ;;
            missing-interaction)
                printf '%s\n' 'interaction_scope=Profile>Home' >> "$evidence_path"
                ;;
            unexpected-result)
                printf '%s\n' 'module_result=Inventory|Game.Tests.InventoryModuleTests|passed' >> "$evidence_path"
                ;;
            duplicate-result)
                printf '%s\n' 'module_result=Login|Game.Tests.LoginModuleTests|passed' >> "$evidence_path"
                ;;
            duplicate-scope)
                printf '%s\n' 'module_scope=Login' >> "$evidence_path"
                ;;
            blank-scope)
                sed -i.bak 's/^interaction_scope=.*/interaction_scope=   /' "$evidence_path"
                ;;
            none-scope)
                sed -i.bak 's/^interaction_scope=.*/interaction_scope=none/' "$evidence_path"
                ;;
            trimmed-scope)
                sed -i.bak 's/^interaction_scope=.*/interaction_scope= Login>Profile /' "$evidence_path"
                ;;
            delimiter-scope)
                sed -i.bak 's/^interaction_scope=.*/interaction_scope=Login|Profile/' "$evidence_path"
                ;;
        esac
        rm -f "$evidence_path.bak"

        bash "$fixture_validator" --evidence "$evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
        status=$?
        assert_equal 1 "$status" "$test_case scope exact-match 종료 코드가 다릅니다" || return 1
    done
}

test_milestone_build_requires_run_and_artifact_evidence()
{
    local case_root="$TEST_TEMP_ROOT/milestone-build-evidence"
    local fixture_root
    local fixture_validator
    local evidence_path
    local valid_hash='0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
    local output
    local phase
    local expected_status
    local status
    local test_case

    for test_case in valid-built missing-authority wrong-authority prebuild-run-id prebuild-artifact-hash pending-run blank-run none-run na-run not-run unknown-run upper-pending-run upper-na-run tbd-run upper-tbd-run dash-run spaced-pending-run trimmed-run pending-hash blank-hash short-hash uppercase-hash
    do
        fixture_root="$case_root/$test_case"
        create_milestone_validator_v2_fixture "$fixture_root" || return 1
        fixture_validator="$fixture_root/.agents/scripts/validation/check-unity-milestone.sh"
        evidence_path="$fixture_root/.agents/config/evidence.conf"
        phase=built
        expected_status=1

        sed -i.bak \
            -e 's/^build_validation=pending$/build_validation=passed/' \
            -e 's/^build_run_id=pending$/build_run_id=local-build-20260719-001/' \
            -e "s/^build_artifact_hash=pending$/build_artifact_hash=$valid_hash/" \
            "$evidence_path"
        rm -f "$evidence_path.bak"

        case "$test_case" in
            prebuild-run-id)
                phase=prebuild
                sed -i.bak 's/^build_validation=passed$/build_validation=pending/' "$evidence_path"
                ;;
            prebuild-artifact-hash)
                phase=prebuild
                sed -i.bak \
                    -e 's/^build_validation=passed$/build_validation=pending/' \
                    -e 's/^build_run_id=local-build-20260719-001$/build_run_id=pending/' \
                    "$evidence_path"
                ;;
            pending-run)
                sed -i.bak 's/^build_run_id=local-build-20260719-001$/build_run_id=pending/' "$evidence_path"
                ;;
            blank-run)
                sed -i.bak 's/^build_run_id=local-build-20260719-001$/build_run_id=   /' "$evidence_path"
                ;;
            none-run)
                sed -i.bak 's/^build_run_id=local-build-20260719-001$/build_run_id=none/' "$evidence_path"
                ;;
            na-run|not-run|unknown-run)
                local placeholder=${test_case%-run}
                [ "$placeholder" = na ] && placeholder='n/a'
                [ "$placeholder" = not ] && placeholder='not_run'
                sed -i.bak "s|^build_run_id=local-build-20260719-001$|build_run_id=$placeholder|" "$evidence_path"
                ;;
            upper-pending-run|upper-na-run|tbd-run|upper-tbd-run|dash-run|spaced-pending-run)
                case "$test_case" in
                    upper-pending-run) placeholder='Pending' ;;
                    upper-na-run) placeholder='N/A' ;;
                    tbd-run) placeholder='tbd' ;;
                    upper-tbd-run) placeholder='TBD' ;;
                    dash-run) placeholder='-' ;;
                    spaced-pending-run) placeholder=' Pending ' ;;
                esac
                sed -i.bak "s|^build_run_id=local-build-20260719-001$|build_run_id=$placeholder|" "$evidence_path"
                ;;
            trimmed-run)
                sed -i.bak 's/^build_run_id=local-build-20260719-001$/build_run_id= local-build-20260719-001 /' "$evidence_path"
                ;;
            pending-hash)
                sed -i.bak "s/^build_artifact_hash=$valid_hash$/build_artifact_hash=pending/" "$evidence_path"
                ;;
            blank-hash)
                sed -i.bak "s/^build_artifact_hash=$valid_hash$/build_artifact_hash=   /" "$evidence_path"
                ;;
            short-hash)
                sed -i.bak "s/^build_artifact_hash=$valid_hash$/build_artifact_hash=0123456789abcdef/" "$evidence_path"
                ;;
            uppercase-hash)
                sed -i.bak "s/^build_artifact_hash=$valid_hash$/build_artifact_hash=ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789/" "$evidence_path"
                ;;
            valid-built)
                expected_status=0
                ;;
        esac
        rm -f "$evidence_path.bak"

        if [ "$test_case" = missing-authority ]; then
            expected_status=3
            output=$(bash "$fixture_validator" --evidence "$evidence_path" --phase "$phase" --change-id commit-abc123 2>&1)
        elif [ "$test_case" = wrong-authority ]; then
            output=$(bash "$fixture_validator" --evidence "$evidence_path" --phase "$phase" --change-id commit-abc123 --expected-authority unity_ci 2>&1)
        else
            output=$(bash "$fixture_validator" --evidence "$evidence_path" --phase "$phase" --change-id commit-abc123 --expected-authority local 2>&1)
        fi
        status=$?
        assert_equal "$expected_status" "$status" "$test_case 빌드 증거 종료 코드가 다릅니다" || return 1
        if [ "$test_case" = "valid-built" ]; then
            assert_contains "$output" 'authority=local' "성공 출력에 build_authority가 없습니다" || return 1
        fi
    done
}

test_milestone_schema_requires_new_evidence_keys()
{
    local fixture_root="$TEST_TEMP_ROOT/milestone-missing-schema-key"
    local fixture_validator
    local fixture_schema
    local evidence_path
    local status

    create_milestone_validator_fixture "$fixture_root" || return 1
    fixture_validator="$fixture_root/.agents/scripts/validation/check-unity-milestone.sh"
    fixture_schema="$fixture_root/.agents/config/unity-milestone-validation-schema.conf"
    evidence_path="$fixture_root/.agents/config/evidence.conf"
    sed -i.bak '/^build_artifact_hash|/d' "$fixture_schema"
    rm -f "$fixture_schema.bak"

    bash "$fixture_validator" --evidence "$evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
    status=$?
    assert_equal 4 "$status" "새 빌드 증거 키가 누락된 schema 종료 코드가 다릅니다"
}

test_milestone_rejects_trailing_empty_multiple_records()
{
    local case_root="$TEST_TEMP_ROOT/milestone-trailing-empty-records"
    local evidence_path
    local status
    local test_case

    mkdir -p "$case_root" || return 1
    for test_case in module-scope module-result
    do
        evidence_path="$case_root/$test_case.conf"
        write_milestone_evidence "$evidence_path" passed pending
        case "$test_case" in
            module-scope)
                printf '%s\n' 'module_scope=' >> "$evidence_path"
                ;;
            module-result)
                printf '%s\n' 'module_result=' >> "$evidence_path"
                ;;
        esac

        bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase prebuild --change-id commit-abc123 >/dev/null 2>&1
        status=$?
        assert_equal 1 "$status" "$test_case trailing empty 반복행 종료 코드가 다릅니다" || return 1
    done
}

test_milestone_artifact_hash_is_locale_independent()
{
    local evidence_path="$TEST_TEMP_ROOT/milestone-uppercase-hash.conf"
    local hash_locale=""
    local locale_candidate
    local status

    while IFS= read -r locale_candidate || [ -n "$locale_candidate" ]; do
        case "$locale_candidate" in
            en_US.UTF-8)
                hash_locale=$locale_candidate
                break
                ;;
            *.UTF-8)
                if [ -z "$hash_locale" ]; then
                    hash_locale=$locale_candidate
                fi
                ;;
        esac
    done <<AVAILABLE_LOCALES_EOF
$(locale -a)
AVAILABLE_LOCALES_EOF

    if [ -z "$hash_locale" ]; then
        hash_locale=C
    fi

    write_milestone_evidence "$evidence_path" passed passed
    sed -i.bak \
        -e 's/^build_run_id=pending$/build_run_id=locale-build-001/' \
        -e 's/^build_artifact_hash=pending$/build_artifact_hash=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA/' \
        "$evidence_path"
    rm -f "$evidence_path.bak"

    LC_ALL=$hash_locale bash "$MILESTONE_VALIDATOR" --evidence "$evidence_path" --phase built --change-id commit-abc123 --expected-authority local >/dev/null 2>&1
    status=$?
    assert_equal 1 "$status" "UTF-8 locale에서 대문자 artifact hash 종료 코드가 다릅니다"
}

test_open_unity_editor_mock_contract()
{
    python3 "$AGENTS_ROOT/tests/test-open-unity-editor.py"
}

test_check_unity_cli_reports_failed_version_as_broken()
{
    local stub_dir="$TEST_TEMP_ROOT/unity-cli-stub" output status
    mkdir -p "$stub_dir" || return 1
    printf '#!/bin/sh\necho "CLI runtime failed"\nexit 12\n' > "$stub_dir/unity"
    chmod +x "$stub_dir/unity"
    output=$(PATH="$stub_dir:$PATH" bash "$AGENTS_ROOT/scripts/setup/check-unity-cli.sh" --check 2>&1)
    status=$?
    assert_equal 1 "$status" "unity --version nonzero 종료 코드" || return 1
    assert_contains "$output" "상태: broken" "unity --version nonzero 상태" || return 1
    assert_not_contains "$output" "상태: installed" "unity --version nonzero 오보고" || return 1
    printf '#!/bin/sh\necho "1.2.3"\n' > "$stub_dir/unity"
    output=$(PATH="$stub_dir:$PATH" bash "$AGENTS_ROOT/scripts/setup/check-unity-cli.sh" --check 2>&1)
    status=$?
    assert_equal 0 "$status" "unity --version 정상 종료 코드" || return 1
    assert_contains "$output" "버전: 1.2.3" "unity --version 정상 버전"
}

test_parallel_tests_reject_duplicate_physical_roots()
{
    local base="$TEST_TEMP_ROOT/parallel-roots" output status
    mkdir -p "$base/bin" "$base/a/ProjectSettings" "$base/b/ProjectSettings" || return 1
    touch "$base/a/ProjectSettings/ProjectVersion.txt" "$base/b/ProjectSettings/ProjectVersion.txt"
    ln -s "$base/a" "$base/alias"
    printf '#!/bin/sh\necho "$*" >> "%s/calls.log"\n' "$base" > "$base/bin/unity"
    chmod +x "$base/bin/unity"
    for pair in "$base/a $base/a" "$base/a $base/alias" "$base/a $base/a/../a"; do
        rm -f "$base/calls.log"
        output=$(PATH="$base/bin:$PATH" bash "$AGENTS_ROOT/scripts/validation/run-parallel-tests.sh" --mode EditMode --max-procs 2 --skip-preflight $pair 2>&1)
        status=$?
        assert_equal 4 "$status" "중복 물리 실행 루트 종료 코드: $pair" || return 1
        assert_contains "$output" "중복" "중복 물리 실행 루트 메시지: $pair" || return 1
        [ ! -e "$base/calls.log" ] || { echo "중복 실행 루트에서 unity가 실행되었습니다: $pair" >&2; return 1; }
    done
    output=$(PATH="$base/bin:$PATH" bash "$AGENTS_ROOT/scripts/validation/run-parallel-tests.sh" --mode EditMode --max-procs 2 --skip-preflight "$base/a" "$base/b" 2>&1)
    status=$?
    assert_equal 1 "$status" "NUnit XML 없는 exit 0 종료 코드" || return 1
    assert_contains "$output" "not_verified" "NUnit XML 없는 실행 루트 표시" || return 1
    assert_contains "$output" "NUnit XML이 없는 실행 루트가 2개 있습니다" "NUnit XML 없는 실행 루트 요약" || return 1
    assert_not_contains "$output" "passed:" "NUnit XML 없는 실행 루트 통과 오보고" || return 1
    assert_equal 2 "$(grep -c '^test ' "$base/calls.log")" "서로 다른 실행 루트 실행 횟수" || return 1
    # Writes the --output NUnit XML like the real CLI.
    printf '#!/bin/sh\nwhile [ $# -gt 0 ]; do [ "$1" = --output ] && echo "<test-run/>" > "$2"; shift; done\n' > "$base/bin/unity"
    output=$(PATH="$base/bin:$PATH" bash "$AGENTS_ROOT/scripts/validation/run-parallel-tests.sh" --mode EditMode --max-procs 2 --skip-preflight "$base/a" "$base/b" 2>&1)
    status=$?
    assert_equal 0 "$status" "NUnit XML 있는 실행 루트 종료 코드" || return 1
    assert_equal 2 "$(printf '%s\n' "$output" | grep -c 'passed:')" "NUnit XML 있는 실행 루트 통과 수"
}

test_milestone_coverage_python_contract()
{
    python3 "$AGENTS_ROOT/tests/test-milestone-coverage.py"
}

is_selected()
{
    local test_group=$1
    local test_runtime=$2

    if [ "$SELECTED_GROUP" != "all" ] && [ "$SELECTED_GROUP" != "$test_group" ]; then
        return 1
    fi

    if [ "$SELECTED_RUNTIME" != "all" ] && [ "$SELECTED_RUNTIME" != "$test_runtime" ]; then
        return 1
    fi

    return 0
}

print_test_output()
{
    local test_name=$1
    local output_path=$2
    local line

    if [ ! -s "$output_path" ]; then
        return 0
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        printf '[진단:%s] %s\n' "$test_name" "$line"
    done < "$output_path"
}

run_registered_test()
{
    local test_name=$1
    local test_group=$2
    local test_runtime=$3
    local output_path
    local status

    if ! is_selected "$test_group" "$test_runtime"; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        echo "[건너뜀] $test_name"
        return 0
    fi

    SELECTED_COUNT=$((SELECTED_COUNT + 1))
    TEST_SEQUENCE=$((TEST_SEQUENCE + 1))
    output_path="$TEST_TEMP_ROOT/test-$TEST_SEQUENCE.log"
    echo "[실행] $test_name"

    if "$test_name" > "$output_path" 2>&1; then
        status=0
    else
        status=$?
    fi

    print_test_output "$test_name" "$output_path"
    if [ "$status" -eq 77 ]; then
        SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
        echo "[건너뜀] $test_name"
    elif [ "$status" -eq 0 ]; then
        PASSED_COUNT=$((PASSED_COUNT + 1))
        echo "[통과] $test_name"
    else
        FAILED_COUNT=$((FAILED_COUNT + 1))
        echo "[실패] $test_name"
    fi
}

run_registered_test test_profile_accepts_repeated_source_roots profile bash
run_registered_test test_profile_rejects_unknown_key profile bash
run_registered_test test_profile_rejects_invalid_enum profile bash
run_registered_test test_profile_does_not_execute_values profile bash
run_registered_test test_detect_rejects_non_unity_directory detection bash
run_registered_test test_detects_mvvm_vcontainer_unitask_urp detection bash
run_registered_test test_detection_uses_assets_game_as_only_code_scope detection bash
run_registered_test test_detection_rejects_missing_assets_game detection bash
run_registered_test test_architecture_conflict_falls_back_to_custom detection bash
run_registered_test test_architecture_ignores_comment_and_string_content_mentions detection bash
run_registered_test test_existing_confirmed_profile_is_not_overwritten detection bash
run_registered_test test_detection_rejects_malformed_inputs detection bash
run_registered_test test_detection_handles_package_conflicts_and_exclusions detection bash
run_registered_test test_detection_requires_code_usage_for_package_backends detection bash
run_registered_test test_packages_lock_dependencies_are_merged_and_validated detection bash
run_registered_test test_detection_package_cache_is_scoped_to_detect_project detection bash
run_registered_test test_detection_covers_supported_architecture_matrix detection bash
run_registered_test test_detection_uses_only_top_level_dependency_keys detection bash
run_registered_test test_detection_ignores_comment_only_backend_mentions detection bash
run_registered_test test_detection_ignores_string_only_backend_mentions detection bash
run_registered_test test_detection_preserves_interpolation_expression_code detection bash
run_registered_test test_detection_respects_raw_and_format_interpolation_boundaries detection bash
run_registered_test test_detection_ignores_path_only_backend_mentions detection bash
run_registered_test test_detection_scans_nested_names_and_excludes_agent_backups detection bash
run_registered_test test_detection_sanitizes_500_files_once detection bash
run_registered_test test_detection_rejects_missing_or_unreadable_required_files detection bash
run_registered_test test_detection_report_has_required_evidence detection bash
run_registered_test test_detection_rolls_back_profile_when_report_fails detection bash
run_registered_test test_detection_preserves_backup_when_rollback_fails detection bash
run_registered_test test_detection_cleans_transaction_files_on_signals detection bash
run_registered_test test_initializer_confirms_pending_profile detection bash
run_registered_test test_pending_profile_downgrades_profile_violation_to_warning lint bash
run_registered_test test_confirmed_profile_blocks_profile_violation lint bash
run_registered_test test_custom_profile_skips_architecture_specific_rules lint bash
run_registered_test test_lint_rejects_source_root_outside_assets_game lint bash
run_registered_test test_lint_emits_all_rule_ids_and_routes_profiles lint bash
run_registered_test test_lint_respects_source_exclusions_and_method_boundaries lint bash
run_registered_test test_lint_entrypoints_and_legacy_wrapper lint bash
run_registered_test test_pre_commit_is_git_independent_and_read_only lint bash
run_registered_test test_lint_singleton_requires_exact_instance_name lint bash
run_registered_test test_lint_solid_and_unitask_respect_framework_idioms lint bash
run_registered_test test_lint_supports_update_modifiers_expression_bodies_and_new_forms lint bash
run_registered_test test_lint_machine_output_percent_escapes_fields lint bash
run_registered_test test_lint_style_excludes_properties_but_keeps_fields lint bash
run_registered_test test_lint_fails_closed_on_file_and_tool_errors lint bash
run_registered_test test_lint_normalizes_and_confines_exclude_roots lint bash
run_registered_test test_lint_physicalizes_absolute_exclude_roots lint bash
run_registered_test test_lint_preserves_interpolation_expressions_in_update lint bash
run_registered_test test_lint_all_methods_recognizes_implicit_and_generic_methods lint bash
run_registered_test test_lint_detects_multiline_register_instance_for_serialized_view lint bash
run_registered_test test_lint_sanitized_lines_strip_comments_and_strings lint bash
run_registered_test test_lint_scans_1000_files_with_one_awk_invocation lint bash
run_registered_test test_korean_and_space_path_is_supported detection bash
run_registered_test test_symlink_project_root_matches_physical_root detection bash
run_registered_test test_detection_does_not_modify_project_files readonly bash
run_registered_test test_end_to_end_profile_state_transition_is_read_only readonly bash
run_registered_test test_snapshot_project_files_fails_closed_on_tool_errors readonly bash
run_registered_test test_docs_have_exact_task6_inventory docs bash
run_registered_test test_docs_define_milestone_build_gate docs bash
run_registered_test test_docs_keep_business_runtime_out_of_common docs bash
run_registered_test test_docs_define_subagent_implementation_and_validation_authority docs bash
run_registered_test test_docs_define_unity_worktree_editor_cli_routing docs bash
run_registered_test test_docs_require_karpathy_for_all_code_and_scripts docs bash
run_registered_test test_docs_define_style_plugin_usage docs bash
run_registered_test test_docs_define_role_model_assignment docs bash
run_registered_test test_docs_define_cli_first_principle docs bash
run_registered_test test_docs_require_parallel_first_planning docs bash
run_registered_test test_docs_manage_troubleshooting_cases docs bash
run_registered_test test_docs_require_harness_compliance_report docs bash
run_registered_test test_hooks_protect_agents_dir lint bash
run_registered_test test_docs_provide_claude_native_kit docs bash
run_registered_test test_docs_require_solid_declaration_in_plan docs bash
run_registered_test test_docs_define_wait_timeout docs bash
run_registered_test test_docs_core_has_no_fixed_profile_assumptions docs bash
run_registered_test test_docs_route_every_profile_enum_branch docs bash
run_registered_test test_docs_core_semantic_contracts docs bash
run_registered_test test_docs_section_contract_helper_rejects_mutations docs bash
run_registered_test test_docs_enum_branch_helper_rejects_unbounded_tokens docs bash
run_registered_test test_docs_architecture_direction_helper_rejects_reverse_flow docs bash
run_registered_test test_docs_cleanup_helpers_reject_negative_contracts docs bash
run_registered_test test_docs_compatibility_route_helper_rejects_split_pairs docs bash
run_registered_test test_docs_architecture_sections_have_semantic_contracts docs bash
run_registered_test test_docs_technical_profiles_have_lifecycle_contracts docs bash
run_registered_test test_docs_compatibility_preserves_rules_and_xml_templates docs bash
run_registered_test test_docs_stp_preserves_operational_guidance docs bash
run_registered_test test_docs_preserve_conditional_rendering_techniques docs bash
run_registered_test test_docs_legacy_paths_are_compatibility_indexes docs bash
run_registered_test test_docs_internal_links_resolve docs bash
run_registered_test test_all_document_references_and_runtime_dependencies_are_safe docs bash
run_registered_test test_document_reference_audit_rejects_missing_regular_paths docs bash
run_registered_test test_document_reference_audit_skips_project_local_records docs bash
run_registered_test test_entrypoints_route_profile_states_in_required_order entrypoints bash
run_registered_test test_entrypoint_templates_follow_profile_contract entrypoints bash
run_registered_test test_entrypoint_readmes_explain_profile_driven_authoring entrypoints bash
run_registered_test test_onboarding_and_scripts_document_equal_platform_flow entrypoints bash
run_registered_test test_entrypoints_do_not_assert_fixed_profiles_or_paths entrypoints bash
run_registered_test test_entrypoint_fixed_assumption_helper_rejects_mutations entrypoints bash
run_registered_test test_entrypoint_business_overlay_requires_complete_file_evidence entrypoints bash
run_registered_test test_entrypoint_document_links_resolve entrypoints bash
run_registered_test test_tooling_reports_installed_disabled_broken_and_missing tooling bash
run_registered_test test_tooling_supports_independent_skills_multiple_versions_and_unicode_paths tooling bash
run_registered_test test_open_unity_editor_mock_contract tooling bash
run_registered_test test_check_unity_cli_reports_failed_version_as_broken tooling bash
run_registered_test test_parallel_tests_reject_duplicate_physical_roots tooling bash
run_registered_test test_tooling_repo_only_understand_is_broken_and_check_is_read_only tooling bash
run_registered_test test_tooling_warns_when_codex_sandbox_blocks_orca tooling bash
run_registered_test test_tooling_each_required_tool_has_complete_state_matrix tooling bash
run_registered_test test_tooling_binds_plugin_records_to_exact_marketplace_cache tooling bash
run_registered_test test_tooling_rejects_duplicate_plugin_installations_and_conflicts tooling bash
run_registered_test test_tooling_conf_parser_rejects_extra_and_indented_data tooling bash
run_registered_test test_tooling_install_mode_stops_on_failure_and_never_repairs_nonmissing tooling bash
run_registered_test test_tooling_install_mode_runs_three_missing_branches_in_order tooling bash
run_registered_test test_tooling_toml_target_sections_reject_conflicts_and_malformed_headers tooling bash
run_registered_test test_tooling_cache_detection_requires_exact_directory_depth tooling bash
run_registered_test test_tooling_rejects_symlinked_cache_root tooling bash
run_registered_test test_tooling_superpowers_official_install_creates_exact_repo_link tooling bash
run_registered_test test_tooling_superpowers_staging_failure_is_retryable tooling bash
run_registered_test test_tooling_understand_failure_cleans_link_and_is_retryable tooling bash
run_registered_test test_tooling_install_rejects_unsafe_home_paths_before_commands tooling bash
run_registered_test test_tooling_install_rejects_escaped_child_roots_before_commands tooling bash
run_registered_test test_tooling_rejects_malformed_plugin_config_even_with_standalone_skills tooling bash
run_registered_test test_tooling_accepts_exact_superpowers_repo_link tooling bash
run_registered_test test_tooling_rejects_symlinked_cache_versions tooling bash
run_registered_test test_tooling_config_rejects_leading_whitespace_rows_but_allows_comments tooling bash
run_registered_test test_tooling_recovery_commands_are_exact_and_lint_is_decoupled tooling bash
run_registered_test test_tooling_rejects_unknown_arguments_and_documents_workflow tooling bash
run_registered_test test_milestone_prebuild_requires_all_automated_tests validation bash
run_registered_test test_milestone_coverage_python_contract validation bash
run_registered_test test_milestone_prebuild_rejects_uncovered_records validation bash
run_registered_test test_milestone_build_requires_prebuild_contract validation bash
run_registered_test test_milestone_rejects_different_change_id validation bash
run_registered_test test_milestone_rejects_invalid_arguments_and_nonregular_evidence validation bash
run_registered_test test_milestone_rejects_malformed_files_and_symlinked_profile validation bash
run_registered_test test_milestone_rejects_invalid_result_records validation bash
run_registered_test test_milestone_rejects_whitespace_identifiers validation bash
run_registered_test test_milestone_example_is_valid_and_read_only validation bash
run_registered_test test_milestone_propagates_profile_api_failure_as_input_error validation bash
run_registered_test test_milestone_requires_exact_confirmed_scope_coverage validation bash
run_registered_test test_milestone_build_requires_run_and_artifact_evidence validation bash
run_registered_test test_milestone_schema_requires_new_evidence_keys validation bash
run_registered_test test_milestone_rejects_trailing_empty_multiple_records validation bash
run_registered_test test_milestone_artifact_hash_is_locale_independent validation bash
run_registered_test test_powershell_parity_contract parity bash

if [ "$SELECTED_COUNT" -eq 0 ]; then
    echo "선택된 테스트가 없습니다." >&2
    echo "통과 $PASSED_COUNT / 실패 $FAILED_COUNT / 건너뜀 $SKIPPED_COUNT"
    exit 2
fi

echo "통과 $PASSED_COUNT / 실패 $FAILED_COUNT / 건너뜀 $SKIPPED_COUNT"

if [ "$FAILED_COUNT" -gt 0 ]; then
    exit 1
fi

exit 0

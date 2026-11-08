#!/bin/bash

# ==============================================================================
# [기능]: 범용 하네스에 필요한 전역 에이전트 도구의 설치 상태를 안전하게 확인합니다.
# [작성자]: 윤승종
# ==============================================================================

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
AGENTS_ROOT=$(cd "$SCRIPT_DIR/../.." && pwd)
TOOLING_CONFIG="$AGENTS_ROOT/config/agent-tooling.conf"
MODE="check"

KARPATHY_PLUGIN=""
KARPATHY_REPOSITORY=""
SUPERPOWERS_PLUGIN=""
SUPERPOWERS_REPOSITORY=""
UNDERSTAND_PLUGIN=""
UNDERSTAND_REPOSITORY=""

KARPATHY_STATUS="missing"
SUPERPOWERS_STATUS="missing"
UNDERSTAND_STATUS="missing"

print_usage()
{
    printf '%s\n' "사용법: bash .agents/scripts/setup/check-agent-tooling.sh [--check|--install-missing]"
}

print_error()
{
    printf '%s\n' "[에이전트 도구] $1" >&2
}

normalize_absolute_path()
{
    local input_path=$1

    awk -v path="$input_path" '
        BEGIN {
            count=split(path, parts, "/")
            depth=0
            for (index_value=1; index_value<=count; index_value++) {
                part=parts[index_value]
                if (part == "" || part == ".") continue
                if (part == "..") {
                    if (depth > 0) depth--
                    continue
                }
                stack[++depth]=part
            }
            if (depth == 0) {
                print "/"
                exit
            }
            result=""
            for (index_value=1; index_value<=depth; index_value++) result=result "/" stack[index_value]
            print result
        }
    '
}

resolve_path_for_safety()
{
    local input_path=$1
    local existing_path=$input_path
    local missing_suffix=""
    local segment
    local physical_path

    case "$input_path" in
        /*) ;;
        *) return 1 ;;
    esac
    while [ ! -e "$existing_path" ] && [ ! -L "$existing_path" ]; do
        segment=${existing_path##*/}
        missing_suffix="/$segment$missing_suffix"
        existing_path=${existing_path%/*}
        if [ -z "$existing_path" ]; then
            existing_path=/
        fi
    done
    if [ ! -d "$existing_path" ]; then
        return 1
    fi
    physical_path=$(cd "$existing_path" 2>/dev/null && pwd -P) || return 1
    normalize_absolute_path "$physical_path$missing_suffix"
}

path_is_confined_to_root()
{
    local child_path=$1
    local root_path=$2
    local resolved_child

    resolved_child=$(resolve_path_for_safety "$child_path") || return 1
    case "$resolved_child" in
        "$root_path"/*) return 0 ;;
        *) return 1 ;;
    esac
}

validate_install_roots()
{
    local resolved_home
    local resolved_codex_home

    resolved_home=$(resolve_path_for_safety "$USER_HOME_RESOLVED") || {
        print_error "HOME은 루트가 아닌 절대 경로여야 합니다."
        return 2
    }
    resolved_codex_home=$(resolve_path_for_safety "$CODEX_HOME_RESOLVED") || {
        print_error "CODEX_HOME은 루트가 아닌 절대 경로여야 합니다."
        return 2
    }
    if [ "$resolved_home" = / ] || [ "$resolved_codex_home" = / ]; then
        print_error "HOME과 CODEX_HOME에는 루트 경로를 사용할 수 없습니다."
        return 2
    fi
    USER_HOME_RESOLVED=$resolved_home
    CODEX_HOME_RESOLVED=$resolved_codex_home
}

tooling_line_is_ignored()
{
    local trimmed=$1

    while :; do
        case "$trimmed" in
            [[:space:]]*) trimmed=${trimmed#?} ;;
            *) break ;;
        esac
    done
    case "$trimmed" in
        ''|'#'*) return 0 ;;
        *) return 1 ;;
    esac
}

parse_arguments()
{
    if [ "$#" -eq 0 ]; then
        return 0
    fi
    if [ "$#" -ne 1 ]; then
        print_error "인자는 하나만 사용할 수 있습니다."
        return 2
    fi

    case "$1" in
        --check)
            MODE="check"
            ;;
        --install-missing)
            MODE="install"
            ;;
        -h|--help)
            print_usage
            return 10
            ;;
        *)
            print_error "알 수 없는 인자입니다: $1"
            print_usage >&2
            return 2
            ;;
    esac
}

load_tooling_config()
{
    local line
    local tool_id
    local plugin_id
    local repository
    local policy
    local remainder
    local separator_count
    local karpathy_seen=0
    local superpowers_seen=0
    local understand_seen=0

    if [ ! -f "$TOOLING_CONFIG" ] || [ ! -r "$TOOLING_CONFIG" ]; then
        print_error "도구 설정 파일을 읽을 수 없습니다."
        return 2
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        if tooling_line_is_ignored "$line"; then
            continue
        fi
        case "$line" in
            [[:space:]]*)
                print_error "도구 설정 데이터 행은 앞 공백을 허용하지 않습니다."
                return 2
                ;;
        esac
        remainder=$line
        separator_count=0
        while :; do
            case "$remainder" in
                *'|'*)
                    remainder=${remainder#*|}
                    separator_count=$((separator_count + 1))
                    ;;
                *)
                    break
                    ;;
            esac
        done
        if [ "$separator_count" -ne 3 ]; then
            print_error "도구 설정 행 형식이 올바르지 않습니다."
            return 2
        fi

        IFS='|' read -r tool_id plugin_id repository policy <<TOOLING_ROW_EOF
$line
TOOLING_ROW_EOF
        if [ -z "$tool_id" ] || [ -z "$plugin_id" ] || [ -z "$repository" ] || [ "$policy" != "required" ]; then
            print_error "도구 설정 행 형식이 올바르지 않습니다."
            return 2
        fi

        case "$tool_id|$plugin_id|$repository|$policy" in
            'karpathy_guidelines|andrej-karpathy-skills|multica-ai/andrej-karpathy-skills|required')
                if [ "$karpathy_seen" -eq 1 ]; then
                    print_error "Karpathy 도구 설정이 중복되었습니다."
                    return 2
                fi
                KARPATHY_PLUGIN=$plugin_id
                KARPATHY_REPOSITORY=$repository
                karpathy_seen=1
                ;;
            'superpowers|superpowers|obra/superpowers|required')
                if [ "$superpowers_seen" -eq 1 ]; then
                    print_error "Superpowers 도구 설정이 중복되었습니다."
                    return 2
                fi
                SUPERPOWERS_PLUGIN=$plugin_id
                SUPERPOWERS_REPOSITORY=$repository
                superpowers_seen=1
                ;;
            'understand_anything|understand-anything|Egonex-AI/Understand-Anything|required')
                if [ "$understand_seen" -eq 1 ]; then
                    print_error "Understand-Anything 도구 설정이 중복되었습니다."
                    return 2
                fi
                UNDERSTAND_PLUGIN=$plugin_id
                UNDERSTAND_REPOSITORY=$repository
                understand_seen=1
                ;;
            *)
                print_error "허용되지 않은 도구 설정입니다."
                return 2
                ;;
        esac
    done < "$TOOLING_CONFIG"

    if [ "$karpathy_seen" -ne 1 ] || [ "$superpowers_seen" -ne 1 ] || [ "$understand_seen" -ne 1 ]; then
        print_error "필수 도구 설정이 누락되었습니다."
        return 2
    fi
}

get_plugin_config_records()
{
    local plugin_id=$1
    local config_path=$2

    if [ ! -f "$config_path" ] || [ ! -r "$config_path" ]; then
        return 0
    fi

    awk -v expected="$plugin_id" '
        function trim(value) {
            sub(/^[ \t]+/, "", value)
            sub(/[ \t]+$/, "", value)
            return value
        }
        function remember(marketplace) {
            if (!(marketplace in remembered)) {
                remembered[marketplace]=1
                order[++order_count]=marketplace
            }
        }
        BEGIN { in_target=0; current=""; malformed_header=0 }
        {
            line=$0
            sub(/\r$/, "", line)
            stripped=trim(line)
            if (stripped == "" || substr(stripped, 1, 1) == "#") next
            if (substr(stripped, 1, 1) == "[") {
                in_target=0
                current=""
                prefix="[plugins.\"" expected "@"
                target_without_marketplace="[plugins.\"" expected "\""
                if (index(stripped, prefix) == 1 && substr(stripped, length(stripped) - 1, 2) == "\"]") {
                    marketplace=substr(stripped, length(prefix) + 1, length(stripped) - length(prefix) - 2)
                    if (marketplace !~ /^[A-Za-z0-9._-]+$/ || marketplace == "." || marketplace == "..") {
                        malformed_header=1
                    } else {
                        in_target=1
                        current=marketplace
                        remember(current)
                        sections[current]++
                    }
                } else if (index(stripped, prefix) == 1 || index(stripped, target_without_marketplace) == 1) {
                    malformed_header=1
                }
                next
            }
            if (!in_target) next
            if (stripped ~ /^enabled[ \t]*=[ \t]*true([ \t]*#.*)?$/) { keys[current]++; enabled[current]++ }
            else if (stripped ~ /^enabled[ \t]*=[ \t]*false([ \t]*#.*)?$/) { keys[current]++; disabled[current]++ }
            else if (stripped ~ /^enabled[ \t]*=/) { keys[current]++; malformed[current]++ }
        }
        END {
            if (malformed_header || order_count > 1) print "__invalid__|broken"
            for (index_value=1; index_value<=order_count; index_value++) {
                marketplace=order[index_value]
                state="broken"
                if (sections[marketplace] == 1 && keys[marketplace] == 1 && malformed[marketplace] == 0) {
                    if (enabled[marketplace] == 1) state="enabled"
                    else if (disabled[marketplace] == 1) state="disabled"
                }
                print marketplace "|" state
            }
        }
    ' "$config_path"
}

cache_has_exact_skill()
{
    local plugin_id=$1
    local marketplace=$2
    local skill_name=$3
    local cache_root="$CODEX_HOME_RESOLVED/plugins/cache"
    local marketplace_root="$cache_root/$marketplace"
    local plugin_root="$marketplace_root/$plugin_id"
    local version_root

    case "$marketplace" in
        ''|'.'|'..'|*[!A-Za-z0-9._-]*)
            return 1
            ;;
    esac
    if ! path_is_confined_to_root "$cache_root" "$CODEX_HOME_RESOLVED"; then
        return 1
    fi
    if [ -L "$marketplace_root" ] || [ -L "$plugin_root" ] || [ ! -d "$plugin_root" ]; then
        return 1
    fi
    for version_root in "$plugin_root"/*; do
        if [ -d "$version_root" ] && [ ! -L "$version_root" ] && \
            [ -d "$version_root/skills" ] && [ ! -L "$version_root/skills" ] && \
            [ -d "$version_root/skills/$skill_name" ] && [ ! -L "$version_root/skills/$skill_name" ] && \
            [ -f "$version_root/skills/$skill_name/SKILL.md" ] && \
            [ ! -L "$version_root/skills/$skill_name/SKILL.md" ]; then
            return 0
        fi
    done
    return 1
}

tooling_list_contains()
{
    local list=$1
    local expected=$2
    local item

    while IFS= read -r item || [ -n "$item" ]; do
        if [ "$item" = "$expected" ]; then
            return 0
        fi
    done <<TOOLING_LIST_EOF
$list
TOOLING_LIST_EOF
    return 1
}

cache_has_orphan_or_wrong_depth()
{
    local plugin_id=$1
    local configured_marketplaces=$2
    local cache_root="$CODEX_HOME_RESOLVED/plugins/cache"
    local plugin_roots
    local plugin_root
    local relative_path
    local marketplace
    local has_orphan=0

    if [ ! -d "$cache_root" ]; then
        return 1
    fi
    if ! path_is_confined_to_root "$cache_root" "$CODEX_HOME_RESOLVED"; then
        return 0
    fi
    plugin_roots=$(find "$cache_root" -type d -name "$plugin_id" -print 2>/dev/null) || return 0
    while IFS= read -r plugin_root || [ -n "$plugin_root" ]; do
        if [ -z "$plugin_root" ]; then
            continue
        fi
        relative_path=${plugin_root#"$cache_root"/}
        case "$relative_path" in
            */*/*) return 0 ;;
            */"$plugin_id") marketplace=${relative_path%/"$plugin_id"} ;;
            *) return 0 ;;
        esac
        if ! tooling_list_contains "$configured_marketplaces" "$marketplace"; then
            has_orphan=1
        fi
    done <<TOOLING_PLUGIN_ROOTS_EOF
$plugin_roots
TOOLING_PLUGIN_ROOTS_EOF
    if [ "$has_orphan" -eq 1 ]; then
        return 2
    fi
    return 1
}

has_standalone_skill()
{
    local skill_name=$1
    local allow_agents_root=$2

    if [ -f "$CODEX_HOME_RESOLVED/skills/$skill_name/SKILL.md" ]; then
        return 0
    fi
    if [ "$allow_agents_root" -eq 1 ] && [ -f "$USER_HOME_RESOLVED/.agents/skills/$skill_name/SKILL.md" ]; then
        return 0
    fi
    return 1
}

has_understand_repo_link()
{
    local link_path="$USER_HOME_RESOLVED/.agents/skills/understand"
    local source_path="$USER_HOME_RESOLVED/.understand-anything/repo/understand-anything-plugin/skills/understand"
    local link_physical
    local source_physical

    if [ ! -L "$link_path" ] || [ ! -f "$link_path/SKILL.md" ] || [ ! -f "$source_path/SKILL.md" ]; then
        return 1
    fi
    link_physical=$(cd "$link_path" 2>/dev/null && pwd -P) || return 1
    source_physical=$(cd "$source_path" 2>/dev/null && pwd -P) || return 1
    [ "$link_physical" = "$source_physical" ]
}

has_superpowers_repo_link()
{
    local link_path="$USER_HOME_RESOLVED/.agents/skills/superpowers"
    local source_path="$CODEX_HOME_RESOLVED/superpowers/skills"
    local link_physical
    local source_physical

    if [ ! -L "$link_path" ] || \
        [ ! -f "$link_path/using-superpowers/SKILL.md" ] || \
        [ ! -f "$source_path/using-superpowers/SKILL.md" ]; then
        return 1
    fi
    link_physical=$(cd "$link_path" 2>/dev/null && pwd -P) || return 1
    source_physical=$(cd "$source_path" 2>/dev/null && pwd -P) || return 1
    [ "$link_physical" = "$source_physical" ]
}

resolve_tool_status()
{
    local plugin_id=$1
    local skill_name=$2
    local tool_kind=$3
    local records
    local record
    local marketplace
    local record_state
    local configured_marketplaces=""
    local has_standalone=0
    local repo_only=0
    local has_installed=0
    local has_disabled=0
    local has_broken=0
    local config_is_broken=0
    local record_count=0
    local cache_issue_status

    if [ "$tool_kind" = "understand" ]; then
        has_standalone_skill "$skill_name" 0 && has_standalone=1
    elif [ "$tool_kind" = "superpowers" ]; then
        if has_superpowers_repo_link || has_standalone_skill "$skill_name" 1; then
            has_standalone=1
        fi
    elif has_standalone_skill "$skill_name" 1; then
        has_standalone=1
    fi
    if [ "$tool_kind" = "understand" ]; then
        if has_understand_repo_link; then
            has_standalone=1
        elif [ -f "$USER_HOME_RESOLVED/.understand-anything/repo/understand-anything-plugin/skills/understand/SKILL.md" ] || \
            [ -e "$USER_HOME_RESOLVED/.agents/skills/understand" ] || \
            [ -L "$USER_HOME_RESOLVED/.agents/skills/understand" ]; then
            repo_only=1
        fi
    elif [ "$tool_kind" = "superpowers" ] && \
        { [ -e "$CODEX_HOME_RESOLVED/superpowers" ] || \
          [ -L "$CODEX_HOME_RESOLVED/superpowers" ] || \
          [ -e "$USER_HOME_RESOLVED/.agents/skills/superpowers" ] || \
          [ -L "$USER_HOME_RESOLVED/.agents/skills/superpowers" ]; }; then
        repo_only=1
    fi

    records=$(get_plugin_config_records "$plugin_id" "$CODEX_HOME_RESOLVED/config.toml") || records="__invalid__|broken"
    while IFS= read -r record || [ -n "$record" ]; do
        if [ -z "$record" ]; then
            continue
        fi
        case "$record" in
            *'|'*)
                marketplace=${record%%|*}
                record_state=${record#*|}
                ;;
            *)
                marketplace=__invalid__
                record_state=broken
                ;;
        esac
        if [ "$marketplace" != "__invalid__" ]; then
            record_count=$((record_count + 1))
            if [ -z "$configured_marketplaces" ]; then
                configured_marketplaces=$marketplace
            else
                configured_marketplaces="$configured_marketplaces
$marketplace"
            fi
        fi
        case "$record_state" in
            enabled)
                if cache_has_exact_skill "$plugin_id" "$marketplace" "$skill_name"; then
                    has_installed=1
                else
                    has_broken=1
                fi
                ;;
            disabled)
                has_disabled=1
                ;;
            *)
                has_broken=1
                config_is_broken=1
                ;;
        esac
    done <<TOOLING_RECORDS_EOF
$records
TOOLING_RECORDS_EOF

    if [ "$record_count" -gt 1 ]; then
        has_broken=1
        config_is_broken=1
    fi
    if [ "$config_is_broken" -eq 1 ]; then
        printf '%s\n' "broken"
        return 0
    fi
    if [ "$has_standalone" -eq 1 ]; then
        printf '%s\n' "installed"
        return 0
    fi
    cache_has_orphan_or_wrong_depth "$plugin_id" "$configured_marketplaces"
    cache_issue_status=$?
    case "$cache_issue_status" in
        0) has_broken=1 ;;
        2)
            if [ "$has_installed" -eq 0 ]; then
                has_broken=1
            fi
            ;;
    esac
    if [ "$has_broken" -eq 1 ]; then
        printf '%s\n' "broken"
    elif [ "$has_installed" -eq 1 ]; then
        printf '%s\n' "installed"
    elif [ "$has_disabled" -eq 1 ]; then
        printf '%s\n' "disabled"
    elif [ "$repo_only" -eq 1 ]; then
        printf '%s\n' "broken"
    else
        printf '%s\n' "missing"
    fi
}

collect_states()
{
    KARPATHY_STATUS=$(resolve_tool_status "$KARPATHY_PLUGIN" "karpathy-guidelines" "skill")
    SUPERPOWERS_STATUS=$(resolve_tool_status "$SUPERPOWERS_PLUGIN" "using-superpowers" "superpowers")
    UNDERSTAND_STATUS=$(resolve_tool_status "$UNDERSTAND_PLUGIN" "understand" "understand")
}

print_states()
{
    printf '%s\n' \
        "karpathy_guidelines|$KARPATHY_STATUS" \
        "superpowers|$SUPERPOWERS_STATUS" \
        "understand_anything|$UNDERSTAND_STATUS"
}

check_codex_sandbox()
{
    # Warning only: read-only Codex sandboxes block the orca CLI runtime connection (EPERM).
    # The TOML is read only by a verified parser (tomllib, tomli or pip's vendored tomli);
    # a parse error or a missing parser warns. The exit status is unchanged.
    # -I -B: isolated and read-only (no user site, no bytecode or cache writes).
    local config="$CODEX_HOME_RESOLVED/config.toml"
    if [ -f "$config" ] && python3 -I -B - "$config" 2>/dev/null <<'CODEX_SANDBOX_PY'
import sys

# A verified TOML parser only: tomllib (3.11+), tomli, or the tomli that pip vendors
# (macOS /usr/bin/python3 3.9). Without one the setting cannot be confirmed, so warn.
for name in ('tomllib', 'tomli', 'pip._vendor.tomli'):
    try:
        parser = __import__(name, fromlist=['loads'])
        break
    except ImportError:
        continue
else:
    sys.exit(1)
data = parser.loads(open(sys.argv[1], encoding='utf-8').read())
table = data.get('sandbox_workspace_write')
mode, network = data.get('sandbox_mode'), table.get('network_access') if isinstance(table, dict) else None
sys.exit(0 if mode == 'danger-full-access' or (mode == 'workspace-write' and network is True) else 1)
CODEX_SANDBOX_PY
    then
        return 0
    fi
    print_error "경고: Codex 샌드박스가 orca 연결을 EPERM(runtime_access_denied)으로 막을 수 있습니다. $config 최상위에 sandbox_mode = \"workspace-write\"와 [sandbox_workspace_write] network_access = true를 두고 codex app-server daemon restart 후 실행 중인 Codex 세션을 재시작하세요. 설정을 읽을 수 없어도 이 경고를 표시합니다."
}

states_are_installed()
{
    [ "$KARPATHY_STATUS" = "installed" ] && \
        [ "$SUPERPOWERS_STATUS" = "installed" ] && \
        [ "$UNDERSTAND_STATUS" = "installed" ]
}

print_recovery()
{
    local tool_id=$1
    local state=$2

    print_error "$tool_id $state 상태: 기존 설정과 설치 경로를 자동으로 덮어쓰지 않습니다."
    if [ "$state" = "disabled" ]; then
        print_error "복구 준비 1: config.toml을 비파괴 백업한 뒤 대상 plugin@marketplace의 enabled = false를 enabled = true로 변경하십시오."
    else
        print_error "복구 준비 1: config.toml을 비파괴 백업하고 malformed 설정 또는 중복 plugin@marketplace 항목을 먼저 교정하십시오."
    fi
    print_error "복구 준비 2: 기존 저장소·스킬 링크의 충돌 경로를 이동한 후 아래 설치 명령을 실행하십시오. 원본은 별도 백업 위치에 보존하십시오."

    case "$tool_id|$state" in
        karpathy_guidelines\|disabled|karpathy_guidelines\|broken)
            print_error "Karpathy 복구: python3 \"\${CODEX_HOME:-\$HOME/.codex}/skills/.system/skill-installer/scripts/install-skill-from-github.py\" --repo multica-ai/andrej-karpathy-skills --path skills/karpathy-guidelines"
            ;;
        superpowers\|disabled|superpowers\|broken)
            print_error "Superpowers 복구 1: git clone https://github.com/obra/superpowers.git \"\${CODEX_HOME:-\$HOME/.codex}/superpowers\""
            print_error "Superpowers 복구 2: mkdir -p \"\$HOME/.agents/skills\""
            print_error "Superpowers 복구 3: ln -s \"\${CODEX_HOME:-\$HOME/.codex}/superpowers/skills\" \"\$HOME/.agents/skills/superpowers\""
            ;;
        understand_anything\|disabled|understand_anything\|broken)
            print_error "Understand-Anything 복구 1: git clone https://github.com/Egonex-AI/Understand-Anything.git \"\$HOME/.understand-anything/repo\""
            print_error "Understand-Anything 복구 2: bash \"\$HOME/.understand-anything/repo/install.sh\" codex"
            ;;
    esac
    print_error "복구 확인: bash .agents/scripts/setup/check-agent-tooling.sh --check"
}

has_nonmissing_failure()
{
    local found=1

    case "$KARPATHY_STATUS" in disabled|broken) print_recovery karpathy_guidelines "$KARPATHY_STATUS"; found=0 ;; esac
    case "$SUPERPOWERS_STATUS" in disabled|broken) print_recovery superpowers "$SUPERPOWERS_STATUS"; found=0 ;; esac
    case "$UNDERSTAND_STATUS" in disabled|broken) print_recovery understand_anything "$UNDERSTAND_STATUS"; found=0 ;; esac
    return "$found"
}

install_karpathy()
{
    local installer="$CODEX_HOME_RESOLVED/skills/.system/skill-installer/scripts/install-skill-from-github.py"
    local skills_root="$CODEX_HOME_RESOLVED/skills"

    if ! path_is_confined_to_root "$skills_root" "$CODEX_HOME_RESOLVED"; then
        print_error "CODEX_HOME 밖으로 연결된 skills 경로에는 설치할 수 없습니다."
        return 1
    fi
    if ! command -v python3 >/dev/null 2>&1 || [ ! -f "$installer" ]; then
        print_error "Codex 시스템 skill-installer를 찾을 수 없습니다."
        return 1
    fi
    python3 "$installer" --repo "$KARPATHY_REPOSITORY" --path "skills/karpathy-guidelines"
}

install_superpowers()
{
    local repository_root="$CODEX_HOME_RESOLVED/superpowers"
    local skills_parent="$USER_HOME_RESOLVED/.agents/skills"
    local link_path="$skills_parent/superpowers"
    local staging_root

    if ! command -v git >/dev/null 2>&1; then
        print_error "Superpowers 설치에 필요한 git을 찾을 수 없습니다."
        return 1
    fi
    if ! path_is_confined_to_root "$skills_parent" "$USER_HOME_RESOLVED"; then
        print_error "사용자 홈 밖으로 연결된 .agents/skills 경로에는 설치할 수 없습니다."
        return 1
    fi
    if [ -e "$repository_root" ] || [ -L "$repository_root" ]; then
        print_error "기존 Superpowers 경로가 있어 자동 설치를 중단합니다."
        return 1
    fi
    if [ -e "$link_path" ] || [ -L "$link_path" ]; then
        print_error "기존 Superpowers 스킬 경로가 있어 자동 설치를 중단합니다."
        return 1
    fi

    mkdir -p "$CODEX_HOME_RESOLVED" || return 1
    staging_root=$(mktemp -d "$CODEX_HOME_RESOLVED/.superpowers.install.XXXXXX") || return 1
    if ! git clone "https://github.com/$SUPERPOWERS_REPOSITORY.git" "$staging_root/repo"; then
        rm -rf "$staging_root"
        return 1
    fi
    if [ ! -f "$staging_root/repo/skills/using-superpowers/SKILL.md" ]; then
        print_error "Superpowers 필수 스킬을 확인할 수 없습니다."
        rm -rf "$staging_root"
        return 1
    fi
    if ! mv "$staging_root/repo" "$repository_root"; then
        rm -rf "$staging_root"
        return 1
    fi
    rm -rf "$staging_root"

    if ! mkdir -p "$skills_parent" || ! ln -s "$repository_root/skills" "$link_path"; then
        rm -rf "$repository_root"
        return 1
    fi
}

install_understand()
{
    local repo_root="$USER_HOME_RESOLVED/.understand-anything/repo"
    local repo_parent="$USER_HOME_RESOLVED/.understand-anything"
    local link_path="$USER_HOME_RESOLVED/.agents/skills/understand"
    local skills_parent="$USER_HOME_RESOLVED/.agents/skills"
    local staging_root

    if ! command -v git >/dev/null 2>&1; then
        print_error "Understand-Anything 설치에 필요한 git을 찾을 수 없습니다."
        return 1
    fi
    if ! path_is_confined_to_root "$repo_parent" "$USER_HOME_RESOLVED" || \
        ! path_is_confined_to_root "$skills_parent" "$USER_HOME_RESOLVED"; then
        print_error "사용자 홈 밖으로 연결된 Understand 저장소 또는 스킬 경로에는 설치할 수 없습니다."
        return 1
    fi
    if [ -e "$repo_root" ] || [ -L "$repo_root" ] || [ -e "$link_path" ] || [ -L "$link_path" ]; then
        print_error "기존 Understand-Anything 저장소 또는 스킬 경로가 있어 자동 설치를 중단합니다."
        return 1
    fi
    mkdir -p "$repo_parent" || return 1
    staging_root=$(mktemp -d "$repo_parent/.repo.install.XXXXXX") || return 1
    if ! git clone "https://github.com/$UNDERSTAND_REPOSITORY.git" "$staging_root/repo"; then
        rm -rf "$staging_root"
        return 1
    fi
    if [ ! -f "$staging_root/repo/install.sh" ]; then
        print_error "로컬 install.sh를 찾을 수 없습니다."
        rm -rf "$staging_root"
        return 1
    fi
    if ! mv "$staging_root/repo" "$repo_root"; then
        rm -rf "$staging_root"
        return 1
    fi
    rm -rf "$staging_root"
    if ! bash "$repo_root/install.sh" codex; then
        if [ -L "$link_path" ]; then
            rm -f "$link_path"
        fi
        rm -rf "$repo_root"
        return 1
    fi

    if ! has_understand_repo_link; then
        if [ -L "$link_path" ]; then
            rm -f "$link_path"
        fi
        rm -rf "$repo_root"
        return 1
    fi
}

install_missing_tools()
{
    if has_nonmissing_failure; then
        print_states
        return 1
    fi

    if [ "$KARPATHY_STATUS" = "missing" ]; then
        install_karpathy || return 3
    fi
    if [ "$SUPERPOWERS_STATUS" = "missing" ]; then
        install_superpowers || return 3
    fi
    if [ "$UNDERSTAND_STATUS" = "missing" ]; then
        install_understand || return 3
    fi

    collect_states
    print_states
    if states_are_installed; then
        return 0
    fi
    return 3
}

ARGUMENT_STATUS=0
parse_arguments "$@" || ARGUMENT_STATUS=$?
if [ "$ARGUMENT_STATUS" -eq 10 ]; then
    exit 0
fi
if [ "$ARGUMENT_STATUS" -ne 0 ]; then
    exit "$ARGUMENT_STATUS"
fi

if [ -z "${HOME:-}" ]; then
    print_error "사용자 홈을 확인할 수 없습니다."
    exit 2
fi
USER_HOME_RESOLVED=$HOME
CODEX_HOME_RESOLVED=${CODEX_HOME:-$HOME/.codex}

validate_install_roots || exit $?

load_tooling_config || exit $?
if ! command -v codex >/dev/null 2>&1; then
    print_error "Codex CLI를 찾을 수 없습니다."
    collect_states
    print_states
    exit 1
fi

collect_states
if [ "$MODE" = "install" ]; then
    install_missing_tools
    exit $?
fi

check_codex_sandbox
print_states
if states_are_installed; then
    exit 0
fi
exit 1

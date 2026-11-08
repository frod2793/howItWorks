#!/bin/bash

# ==============================================================================
# [기능]: Unity 프로젝트를 읽기 전용으로 분석하고 하네스 프로필 후보를 생성합니다.
# [작성자]: 윤승종
# ==============================================================================

_DETECT_RESULT=""
_DETECT_PROJECT_ROOT=""
_DETECT_PROJECT_NAME=""
_DETECT_UNITY_VERSION=""
_DETECT_SOURCE_ROOTS=""
_DETECT_TEST_ROOTS=""
_DETECT_RENDER_PIPELINE=""
_DETECT_ARCHITECTURE=""
_DETECT_DEPENDENCY_INJECTION=""
_DETECT_ASYNC_BACKEND=""
_DETECT_TWEEN_BACKEND=""
_DETECT_TARGET_PLATFORMS=""
_DETECT_GPU_RESIDENT_DRAWER=""
_DETECT_GPU_OCCLUSION_CULLING=""
_DETECT_STP=""
_DETECT_MESH_LOD=""
_DETECT_RENDER_CONFIDENCE="unknown"
_DETECT_ARCHITECTURE_CONFIDENCE="unknown"
_DETECT_DI_CONFIDENCE="unknown"
_DETECT_ASYNC_CONFIDENCE="unknown"
_DETECT_TWEEN_CONFIDENCE="unknown"
_DETECT_SOURCE_CONFIDENCE="unknown"
_DETECT_TEST_CONFIDENCE="unknown"
_DETECT_DI_EVIDENCE=""
_DETECT_ASYNC_EVIDENCE=""
_DETECT_TWEEN_EVIDENCE=""
_DETECT_MANIFEST_ROOT=""
_DETECT_MANIFEST_DEPENDENCY_KEYS=""
_DETECT_PACKAGE_EVIDENCE=""
_DETECT_ARCHITECTURE_EVIDENCE=""
_DETECT_ARCHITECTURE_CONFLICT=0
_DETECT_COMPARISON_PROFILE=""
_DETECT_PROFILE_OUTPUT=""
_DETECT_PREPARED_PROFILE=""
_DETECT_PREPARED_PROFILE_PREFIX=""
_DETECT_PREPARED_REPORT=""
_DETECT_PREPARED_REPORT_PREFIX=""
_DETECT_ACTIVE_PROFILE_SEED=""
_DETECT_ACTIVE_PROFILE_SEED_PREFIX=""
_DETECT_ACTIVE_PROFILE_TARGET=""
_DETECT_ACTIVE_PROFILE_BACKUP=""
_DETECT_ACTIVE_PROFILE_BACKUP_PREFIX=""
_DETECT_ACTIVE_PROFILE_HAD_EXISTING=0
_DETECT_ACTIVE_PROFILE_ORIGINAL_MOVED=0
_DETECT_ACTIVE_PROFILE_COMMITTED=0
_DETECT_DEFER_SIGNAL=0
_DETECT_PENDING_SIGNAL_STATUS=0
_DETECT_SANITIZER_INVOCATIONS=0
_DETECT_CODE_LIST_COLLECTIONS=0
_DETECT_CODE_CACHE_ROOT=""
_DETECT_CODE_LIST_PATH=""
_DETECT_CODE_LIST_PREFIX=""
_DETECT_CSHARP_CORPUS_PATH=""
_DETECT_CSHARP_CORPUS_PREFIX=""

_detect_print_error()
{
    printf '%s\n' "[감지] $1" >&2
}

_detect_is_ignored_line()
{
    local line=$1
    local trimmed=$1

    while :; do
        case "$trimmed" in
            [[:space:]]*)
                trimmed=${trimmed#?}
                ;;
            *)
                break
                ;;
        esac
    done

    case "$trimmed" in
        ''|\#*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_detect_list_contains()
{
    local list=$1
    local expected=$2
    local item

    while IFS= read -r item || [ -n "$item" ]; do
        if [ "$item" = "$expected" ]; then
            return 0
        fi
    done <<DETECT_LIST_EOF
$list
DETECT_LIST_EOF

    return 1
}

_detect_append_unique_line()
{
    local list=$1
    local value=$2

    if _detect_list_contains "$list" "$value"; then
        _DETECT_RESULT=$list
        return 0
    fi

    if [ -z "$list" ]; then
        _DETECT_RESULT=$value
    else
        _DETECT_RESULT="${list}
$value"
    fi

    return 0
}

_detect_relative_path()
{
    local project_root=$1
    local absolute_path=$2

    case "$absolute_path" in
        "$project_root"/*)
            printf '%s\n' "${absolute_path#"$project_root"/}"
            ;;
        *)
            printf '%s\n' "$absolute_path"
            ;;
    esac
}

_detect_project_code_files()
{
    local project_root=$1
    local code_root="$project_root/Assets/_Game"

    if [ ! -d "$code_root" ] || [ ! -r "$code_root" ]; then
        _detect_print_error "프로젝트 소유 코드 루트를 읽을 수 없습니다: $code_root"
        return 4
    fi

    find "$code_root" -type f \( -name '*.cs' -o -name '*.asmdef' \) -print
}

_detect_code_files()
{
    local project_root=$1
    local file_path

    if [ "$_DETECT_CODE_CACHE_ROOT" = "$project_root" ] && [ -f "$_DETECT_CODE_LIST_PATH" ]; then
        while IFS= read -r file_path || [ -n "$file_path" ]; do
            printf '%s\n' "$file_path"
        done < "$_DETECT_CODE_LIST_PATH"
        return 0
    fi

    _detect_project_code_files "$project_root"
}

_detect_has_code_below()
{
    local project_root=$1
    local directory=$2
    local file_path

    while IFS= read -r file_path || [ -n "$file_path" ]; do
        case "$file_path" in
            "$directory"/*.cs)
                return 0
                ;;
        esac
    done <<DETECT_CODE_FILES_EOF
$(_detect_code_files "$project_root")
DETECT_CODE_FILES_EOF

    return 1
}

_detect_any_code_path_match()
{
    local project_root=$1
    local pattern=$2
    local file_path
    local relative_path

    if [ "$_DETECT_CODE_CACHE_ROOT" = "$project_root" ] && [ -f "$_DETECT_CODE_LIST_PATH" ]; then
        LC_ALL=C awk -v project_prefix="$project_root/" -v path_pattern="$pattern" '
            {
                relative_path = $0
                if (substr(relative_path, 1, length(project_prefix)) == project_prefix)
                {
                    relative_path = substr(relative_path, length(project_prefix) + 1)
                }
                if (relative_path ~ path_pattern)
                {
                    found = 1
                    exit
                }
            }
            END {
                if (!found)
                {
                    exit 1
                }
            }
        ' "$_DETECT_CODE_LIST_PATH" >/dev/null 2>&1
        return $?
    fi

    while IFS= read -r file_path || [ -n "$file_path" ]; do
        if [ -z "$file_path" ]; then
            continue
        fi

        relative_path=$(_detect_relative_path "$project_root" "$file_path")
        if printf '%s\n' "$relative_path" | grep -Eq "$pattern" 2>/dev/null; then
            return 0
        fi

    done <<DETECT_CODE_FILES_EOF
$(_detect_code_files "$project_root")
DETECT_CODE_FILES_EOF

    return 1
}

_detect_build_csharp_corpus()
{
    local code_list_path=$1
    local output_path=$2

    _DETECT_SANITIZER_INVOCATIONS=$((_DETECT_SANITIZER_INVOCATIONS + 1))

    LC_ALL=C awk -v code_list_path="$code_list_path" '
        function quote_count(text, start,    count)
        {
            count = 0
            while (substr(text, start + count, 1) == "\"")
            {
                count++
            }
            return count
        }

        function character_count(text, start, expected,    count)
        {
            count = 0
            while (substr(text, start + count, 1) == expected)
            {
                count++
            }
            return count
        }

        function begin_interpolation(mode, closing_braces, raw_quotes)
        {
            interpolation_depth = 1
            interpolation_outer_mode = mode
            interpolation_closing_braces = closing_braces
            interpolation_parenthesis_depth = 0
            interpolation_bracket_depth = 0
            interpolation_ternary_depth = 0
            interpolation_in_clause = 0
            if (mode == 3)
            {
                raw_outer_delimiter = raw_quotes
                raw_outer_braces = raw_interpolation_braces
                raw_delimiter = 0
            }
        }

        function close_interpolation()
        {
            if (interpolation_outer_mode == 3)
            {
                raw_delimiter = raw_outer_delimiter
                raw_interpolation_braces = raw_outer_braces
            }
            else if (interpolation_outer_mode == 2)
            {
                in_verbatim_string = 1
                interpolated_string = 1
            }
            else
            {
                in_string = 1
                interpolated_string = 1
            }
            interpolation_depth = 0
            interpolation_outer_mode = 0
            interpolation_closing_braces = 0
            interpolation_parenthesis_depth = 0
            interpolation_bracket_depth = 0
            interpolation_ternary_depth = 0
            interpolation_in_clause = 0
        }

        function reset_sanitizer_state()
        {
            in_block_comment = 0
            raw_delimiter = 0
            raw_interpolation_braces = 0
            raw_outer_delimiter = 0
            raw_outer_braces = 0
            in_verbatim_string = 0
            in_string = 0
            in_character = 0
            interpolated_string = 0
            interpolation_depth = 0
            interpolation_outer_mode = 0
            interpolation_closing_braces = 0
            interpolation_parenthesis_depth = 0
            interpolation_bracket_depth = 0
            interpolation_ternary_depth = 0
            interpolation_in_clause = 0
        }

        function sanitize_text(text)
        {
            sanitized = ""
            position = 1

            while (position <= length(text))
            {
                character = substr(text, position, 1)
                next_character = substr(text, position + 1, 1)

                if (in_block_comment)
                {
                    if (character == "*" && next_character == "/")
                    {
                        in_block_comment = 0
                        position += 2
                    }
                    else
                    {
                        position++
                    }
                    continue
                }

                if (raw_delimiter > 0)
                {
                    if (raw_interpolation_braces > 0 && character == "{")
                    {
                        current_brace_count = character_count(text, position, "{")
                        if (current_brace_count >= raw_interpolation_braces)
                        {
                            begin_interpolation(3, raw_interpolation_braces, raw_delimiter)
                            sanitized = sanitized " "
                            position += raw_interpolation_braces
                        }
                        else
                        {
                            position += current_brace_count
                        }
                    }
                    else if (character == "\"")
                    {
                        current_quote_count = quote_count(text, position)
                        if (current_quote_count >= raw_delimiter)
                        {
                            raw_delimiter = 0
                            raw_interpolation_braces = 0
                        }
                        position += current_quote_count
                    }
                    else
                    {
                        position++
                    }
                    continue
                }

                if (in_verbatim_string)
                {
                    if (interpolated_string && character == "{")
                    {
                        if (next_character == "{")
                        {
                            position += 2
                        }
                        else
                        {
                            in_verbatim_string = 0
                            interpolated_string = 0
                            begin_interpolation(2, 1, 0)
                            sanitized = sanitized " "
                            position++
                        }
                    }
                    else if (character == "\"" && next_character == "\"")
                    {
                        position += 2
                    }
                    else if (character == "\"")
                    {
                        in_verbatim_string = 0
                        interpolated_string = 0
                        position++
                    }
                    else
                    {
                        position++
                    }
                    continue
                }

                if (in_string)
                {
                    if (interpolated_string && character == "{")
                    {
                        if (next_character == "{")
                        {
                            position += 2
                        }
                        else
                        {
                            in_string = 0
                            interpolated_string = 0
                            begin_interpolation(1, 1, 0)
                            sanitized = sanitized " "
                            position++
                        }
                    }
                    else if (character == "\\")
                    {
                        position += 2
                    }
                    else if (character == "\"")
                    {
                        in_string = 0
                        interpolated_string = 0
                        position++
                    }
                    else
                    {
                        position++
                    }
                    continue
                }

                if (in_character)
                {
                    if (character == "\\")
                    {
                        position += 2
                    }
                    else if (character == "\047")
                    {
                        in_character = 0
                        position++
                    }
                    else
                    {
                        position++
                    }
                    continue
                }

                if (interpolation_depth > 0 && interpolation_in_clause)
                {
                    if (character == "}" && interpolation_depth == 1)
                    {
                        current_brace_count = character_count(text, position, "}")
                        if (current_brace_count >= interpolation_closing_braces)
                        {
                            position += interpolation_closing_braces
                            close_interpolation()
                            sanitized = sanitized " "
                            continue
                        }
                    }
                    position++
                    continue
                }

                if (interpolation_depth > 0 && character == "{")
                {
                    interpolation_depth++
                    sanitized = sanitized character
                    position++
                    continue
                }
                if (interpolation_depth > 0 && character == "}")
                {
                    current_brace_count = character_count(text, position, "}")
                    if (interpolation_depth == 1 && current_brace_count >= interpolation_closing_braces)
                    {
                        position += interpolation_closing_braces
                        close_interpolation()
                        sanitized = sanitized " "
                    }
                    else if (interpolation_depth > 1)
                    {
                        interpolation_depth--
                        sanitized = sanitized character
                        position++
                    }
                    else
                    {
                        sanitized = sanitized character
                        position++
                    }
                    continue
                }

                if (interpolation_depth > 0)
                {
                    if (character == "(")
                    {
                        interpolation_parenthesis_depth++
                    }
                    else if (character == ")" && interpolation_parenthesis_depth > 0)
                    {
                        interpolation_parenthesis_depth--
                    }
                    else if (character == "[")
                    {
                        interpolation_bracket_depth++
                    }
                    else if (character == "]" && interpolation_bracket_depth > 0)
                    {
                        interpolation_bracket_depth--
                    }
                    else if (interpolation_depth == 1 && interpolation_parenthesis_depth == 0 && interpolation_bracket_depth == 0)
                    {
                        if (character == "?" && next_character != "?" && next_character != "." && next_character != "[")
                        {
                            interpolation_ternary_depth++
                        }
                        else if (character == ":" && substr(text, position - 1, 1) != ":" && next_character != ":")
                        {
                            if (interpolation_ternary_depth > 0)
                            {
                                interpolation_ternary_depth--
                            }
                            else
                            {
                                interpolation_in_clause = 1
                                position++
                                continue
                            }
                        }
                        else if (character == "," && interpolation_ternary_depth == 0)
                        {
                            interpolation_in_clause = 1
                            position++
                            continue
                        }
                    }
                }

                if (character == "/" && next_character == "/")
                {
                    break
                }
                if (character == "/" && next_character == "*")
                {
                    sanitized = sanitized " "
                    in_block_comment = 1
                    position += 2
                    continue
                }

                if (character == "@" && next_character == "\"")
                {
                    sanitized = sanitized " "
                    in_verbatim_string = 1
                    interpolated_string = 0
                    position += 2
                    continue
                }
                if (character == "@" && next_character == "$" && substr(text, position + 2, 1) == "\"")
                {
                    sanitized = sanitized " "
                    in_verbatim_string = 1
                    interpolated_string = 1
                    position += 3
                    continue
                }

                if (character == "$")
                {
                    prefix_end = position
                    while (substr(text, prefix_end, 1) == "$")
                    {
                        prefix_end++
                    }
                    if (substr(text, prefix_end, 1) == "@" && substr(text, prefix_end + 1, 1) == "\"")
                    {
                        sanitized = sanitized " "
                        in_verbatim_string = 1
                        interpolated_string = 1
                        position = prefix_end + 2
                        continue
                    }
                    if (substr(text, prefix_end, 1) == "\"")
                    {
                        current_quote_count = quote_count(text, prefix_end)
                        sanitized = sanitized " "
                        if (current_quote_count >= 3)
                        {
                            raw_delimiter = current_quote_count
                            raw_interpolation_braces = prefix_end - position
                            interpolated_string = 0
                        }
                        else
                        {
                            in_string = 1
                            interpolated_string = 1
                        }
                        position = prefix_end + current_quote_count
                        continue
                    }
                }

                if (character == "\"")
                {
                    current_quote_count = quote_count(text, position)
                    sanitized = sanitized " "
                    if (current_quote_count >= 3)
                    {
                        raw_delimiter = current_quote_count
                        raw_interpolation_braces = 0
                    }
                    else
                    {
                        in_string = 1
                    }
                    interpolated_string = 0
                    position += current_quote_count
                    continue
                }
                if (character == "\047")
                {
                    sanitized = sanitized " "
                    in_character = 1
                    position++
                    continue
                }

                sanitized = sanitized character
                position++
            }

            print sanitized
        }

        BEGIN {
            while ((file_list_status = getline file_path < code_list_path) > 0)
            {
                if (file_path !~ /[.]cs$/)
                {
                    continue
                }

                reset_sanitizer_state()
                while ((file_status = getline text < file_path) > 0)
                {
                    sanitize_text(text)
                }
                close(file_path)
                if (file_status < 0)
                {
                    exit 2
                }
            }
            close(code_list_path)
            if (file_list_status < 0)
            {
                exit 2
            }
        }
    ' /dev/null > "$output_path"
}

_detect_cleanup_code_cache()
{
    _profile_cleanup_temporary_file "$_DETECT_CODE_LIST_PATH" "$_DETECT_CODE_LIST_PREFIX"
    _profile_cleanup_temporary_file "$_DETECT_CSHARP_CORPUS_PATH" "$_DETECT_CSHARP_CORPUS_PREFIX"
    _DETECT_CODE_CACHE_ROOT=""
    _DETECT_CODE_LIST_PATH=""
    _DETECT_CODE_LIST_PREFIX=""
    _DETECT_CSHARP_CORPUS_PATH=""
    _DETECT_CSHARP_CORPUS_PREFIX=""
}

_detect_prepare_code_cache()
{
    local project_root=$1
    local temporary_root=${TMPDIR:-/tmp}
    local status

    _detect_cleanup_code_cache
    if [ ! -d "$temporary_root" ]; then
        _detect_print_error "코드 감지 임시 디렉터리를 찾을 수 없습니다: $temporary_root"
        return 4
    fi

    _DETECT_CODE_LIST_PREFIX="$temporary_root/unity-harness-code-list."
    _DETECT_CODE_LIST_PATH=$(mktemp "${_DETECT_CODE_LIST_PREFIX}XXXXXX" 2>/dev/null)
    status=$?
    if [ "$status" -ne 0 ] || [ -z "$_DETECT_CODE_LIST_PATH" ] || [ ! -f "$_DETECT_CODE_LIST_PATH" ]; then
        _detect_cleanup_code_cache
        _detect_print_error "코드 파일 목록 임시 파일을 만들 수 없습니다: $temporary_root"
        return 4
    fi

    _detect_project_code_files "$project_root" > "$_DETECT_CODE_LIST_PATH"
    _DETECT_CODE_LIST_COLLECTIONS=$((_DETECT_CODE_LIST_COLLECTIONS + 1))
    status=$?
    if [ "$status" -ne 0 ]; then
        _detect_cleanup_code_cache
        _detect_print_error "프로젝트 코드 파일 목록을 수집할 수 없습니다: $project_root"
        return 4
    fi

    _DETECT_CSHARP_CORPUS_PREFIX="$temporary_root/unity-harness-csharp-corpus."
    _DETECT_CSHARP_CORPUS_PATH=$(mktemp "${_DETECT_CSHARP_CORPUS_PREFIX}XXXXXX" 2>/dev/null)
    status=$?
    if [ "$status" -ne 0 ] || [ -z "$_DETECT_CSHARP_CORPUS_PATH" ] || [ ! -f "$_DETECT_CSHARP_CORPUS_PATH" ]; then
        _detect_cleanup_code_cache
        _detect_print_error "C# 정제 코퍼스 임시 파일을 만들 수 없습니다: $temporary_root"
        return 4
    fi

    _detect_build_csharp_corpus "$_DETECT_CODE_LIST_PATH" "$_DETECT_CSHARP_CORPUS_PATH" 2>/dev/null
    status=$?
    if [ "$status" -ne 0 ]; then
        _detect_cleanup_code_cache
        _detect_print_error "C# 정제 코퍼스를 생성할 수 없습니다: $project_root"
        return 4
    fi

    _DETECT_CODE_CACHE_ROOT=$project_root
    return 0
}

_detect_run_with_code_cache()
{
    local project_root=$1
    local callback=$2
    local owns_cache=0
    local status

    shift 2
    if [ "$_DETECT_CODE_CACHE_ROOT" != "$project_root" ] || [ ! -f "$_DETECT_CSHARP_CORPUS_PATH" ]; then
        _detect_prepare_code_cache "$project_root" || return $?
        owns_cache=1
    fi

    "$callback" "$project_root" "$@"
    status=$?
    if [ "$owns_cache" -eq 1 ]; then
        _detect_cleanup_code_cache
    fi
    return "$status"
}

_detect_any_csharp_code_match()
{
    local project_root=$1
    local pattern=$2

    if [ "$_DETECT_CODE_CACHE_ROOT" != "$project_root" ] || [ ! -f "$_DETECT_CSHARP_CORPUS_PATH" ]; then
        return 1
    fi

    grep -Eq "$pattern" "$_DETECT_CSHARP_CORPUS_PATH" 2>/dev/null
}

_detect_manifest_matches()
{
    local project_root=$1
    local pattern=$2
    local dependency_keys

    if [ "$_DETECT_MANIFEST_ROOT" = "$project_root" ]; then
        dependency_keys=$_DETECT_MANIFEST_DEPENDENCY_KEYS
    else
        dependency_keys=$(_detect_package_dependency_keys "$project_root" 2>/dev/null) || return 1
    fi

    grep -Eiq "^($pattern)$" <<DETECT_DEPENDENCY_KEYS_EOF
$dependency_keys
DETECT_DEPENDENCY_KEYS_EOF
}

_detect_json_scan()
{
    local json_path=$1
    local scan_mode=$2

    LC_ALL=C awk -v scan_mode="$scan_mode" '
        function skip_whitespace(    character)
        {
            while (position <= json_length)
            {
                character = substr(json_text, position, 1)
                if (character != " " && character != "\t" && character != "\r" && character != "\n")
                {
                    break
                }
                position++
            }
        }

        function is_digit(character)
        {
            return character ~ /^[0-9]$/
        }

        function parse_string(    character, escape_character, digit_index, hex_character, unicode_escape)
        {
            if (substr(json_text, position, 1) != "\"")
            {
                return 0
            }
            position++
            parsed_string = ""

            while (position <= json_length)
            {
                character = substr(json_text, position, 1)
                if (character == "\"")
                {
                    position++
                    return 1
                }
                if (character == "\\")
                {
                    position++
                    if (position > json_length)
                    {
                        return 0
                    }
                    escape_character = substr(json_text, position, 1)
                    if (escape_character == "u")
                    {
                        unicode_escape = "\\u"
                        for (digit_index = 1; digit_index <= 4; digit_index++)
                        {
                            position++
                            hex_character = substr(json_text, position, 1)
                            if (hex_character !~ /^[0-9A-Fa-f]$/)
                            {
                                return 0
                            }
                            unicode_escape = unicode_escape hex_character
                        }
                        parsed_string = parsed_string unicode_escape
                        position++
                        continue
                    }
                    if (index("\"\\/bfnrt", escape_character) == 0)
                    {
                        return 0
                    }
                    parsed_string = parsed_string escape_character
                    position++
                    continue
                }
                if (character ~ /[[:cntrl:]]/)
                {
                    return 0
                }
                parsed_string = parsed_string character
                position++
            }

            return 0
        }

        function parse_number(    character)
        {
            if (substr(json_text, position, 1) == "-")
            {
                position++
            }

            character = substr(json_text, position, 1)
            if (character == "0")
            {
                position++
            }
            else if (character ~ /^[1-9]$/)
            {
                position++
                while (is_digit(substr(json_text, position, 1)))
                {
                    position++
                }
            }
            else
            {
                return 0
            }

            if (substr(json_text, position, 1) == ".")
            {
                position++
                if (!is_digit(substr(json_text, position, 1)))
                {
                    return 0
                }
                while (is_digit(substr(json_text, position, 1)))
                {
                    position++
                }
            }

            character = substr(json_text, position, 1)
            if (character == "e" || character == "E")
            {
                position++
                character = substr(json_text, position, 1)
                if (character == "+" || character == "-")
                {
                    position++
                }
                if (!is_digit(substr(json_text, position, 1)))
                {
                    return 0
                }
                while (is_digit(substr(json_text, position, 1)))
                {
                    position++
                }
            }

            return 1
        }

        function parse_array(    character)
        {
            position++
            skip_whitespace()
            if (substr(json_text, position, 1) == "]")
            {
                position++
                return 1
            }

            while (position <= json_length)
            {
                if (!parse_value("other"))
                {
                    return 0
                }
                skip_whitespace()
                character = substr(json_text, position, 1)
                if (character == "]")
                {
                    position++
                    return 1
                }
                if (character != ",")
                {
                    return 0
                }
                position++
                skip_whitespace()
            }

            return 0
        }

        function parse_object(context,    character, member_name, value_context)
        {
            position++
            skip_whitespace()
            if (substr(json_text, position, 1) == "}")
            {
                position++
                return 1
            }

            while (position <= json_length)
            {
                if (!parse_string())
                {
                    return 0
                }
                member_name = parsed_string
                skip_whitespace()
                if (substr(json_text, position, 1) != ":")
                {
                    return 0
                }
                position++
                value_context = "other"
                if (context == "root" && member_name == "dependencies")
                {
                    dependencies_seen = 1
                    value_context = "dependencies"
                }
                else if (context == "dependencies")
                {
                    dependency_keys = dependency_keys member_name "\n"
                }
                if (!parse_value(value_context))
                {
                    return 0
                }
                skip_whitespace()
                character = substr(json_text, position, 1)
                if (character == "}")
                {
                    position++
                    return 1
                }
                if (character != ",")
                {
                    return 0
                }
                position++
                skip_whitespace()
            }

            return 0
        }

        function parse_value(context,    character)
        {
            skip_whitespace()
            character = substr(json_text, position, 1)
            if (character == "{")
            {
                return parse_object(context)
            }
            if (context == "dependencies")
            {
                return 0
            }
            if (character == "[")
            {
                return parse_array()
            }
            if (character == "\"")
            {
                return parse_string()
            }
            if (character == "-" || is_digit(character))
            {
                return parse_number()
            }
            if (substr(json_text, position, 4) == "true")
            {
                position += 4
                return 1
            }
            if (substr(json_text, position, 5) == "false")
            {
                position += 5
                return 1
            }
            if (substr(json_text, position, 4) == "null")
            {
                position += 4
                return 1
            }

            return 0
        }

        {
            json_text = json_text $0 "\n"
        }

        END {
            json_length = length(json_text)
            position = 1
            if (!parse_value("root"))
            {
                exit 1
            }
            skip_whitespace()
            if (position <= json_length)
            {
                exit 1
            }
            if (scan_mode == "dependencies")
            {
                if (!dependencies_seen)
                {
                    exit 2
                }
                printf "%s", dependency_keys
            }
        }
    ' "$json_path"
}

_detect_validate_json_file()
{
    _detect_json_scan "$1" "validate" >/dev/null 2>&1
}

_detect_manifest_dependency_keys()
{
    _detect_json_scan "$1" "dependencies"
}

_detect_package_dependency_keys()
{
    local project_root=$1
    local manifest_path="$project_root/Packages/manifest.json"
    local lock_path="$project_root/Packages/packages-lock.json"
    local manifest_keys
    local lock_keys=""

    manifest_keys=$(_detect_manifest_dependency_keys "$manifest_path") || return 1
    if [ -e "$lock_path" ]; then
        lock_keys=$(_detect_manifest_dependency_keys "$lock_path") || return 1
    fi
    printf '%s\n%s\n' "$manifest_keys" "$lock_keys" | sed '/^$/d' | LC_ALL=C sort -u
}

_detect_validate_signatures()
{
    local signatures_path=$1
    local line
    local profile
    local remainder
    local pattern
    local weight

    if [ ! -f "$signatures_path" ] || [ ! -r "$signatures_path" ]; then
        _detect_print_error "감지 시그니처 파일을 읽을 수 없습니다: $signatures_path"
        return 4
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        if _detect_is_ignored_line "$line"; then
            continue
        fi

        case "$line" in
            *'|'*)
                profile=${line%%|*}
                remainder=${line#*|}
                ;;
            *)
                _detect_print_error "감지 시그니처 형식이 올바르지 않습니다: $line"
                return 4
                ;;
        esac

        case "$remainder" in
            *'|'*)
                pattern=${remainder%%|*}
                weight=${remainder#*|}
                ;;
            *)
                _detect_print_error "감지 시그니처 형식이 올바르지 않습니다: $line"
                return 4
                ;;
        esac

        case "$weight" in
            *'|'*|''|*[!0-9]*)
                _detect_print_error "감지 시그니처 가중치가 올바르지 않습니다: $line"
                return 4
                ;;
        esac

        case "$profile" in
            mvvm|mvp|mvc|layered_clean)
                ;;
            *)
                _detect_print_error "지원하지 않는 감지 프로필입니다: $profile"
                return 4
                ;;
        esac

        if [ -z "$pattern" ]; then
            _detect_print_error "감지 시그니처 패턴이 비어 있습니다: $line"
            return 4
        fi

        printf '%s\n' '' | grep -Eq "$pattern" 2>/dev/null
        if [ "$?" -eq 2 ]; then
            _detect_print_error "감지 시그니처 정규식이 올바르지 않습니다: $pattern"
            return 4
        fi
    done < "$signatures_path"

    return 0
}

_detect_validate_project_inputs()
{
    local project_root=$1
    local schema_path=$2
    local signatures_path=$3
    local version_path="$project_root/ProjectSettings/ProjectVersion.txt"
    local manifest_path="$project_root/Packages/manifest.json"
    local lock_path="$project_root/Packages/packages-lock.json"
    local graphics_path="$project_root/ProjectSettings/GraphicsSettings.asset"
    local manifest_compact
    local dependency_keys

    if [ ! -f "$version_path" ] || [ ! -r "$version_path" ]; then
        _detect_print_error "ProjectVersion.txt 파일을 읽을 수 없습니다: $version_path"
        return 4
    fi

    if [ ! -f "$manifest_path" ] || [ ! -r "$manifest_path" ]; then
        _detect_print_error "manifest.json 파일을 읽을 수 없습니다: $manifest_path"
        return 4
    fi
    if [ -e "$lock_path" ] && { [ ! -f "$lock_path" ] || [ ! -r "$lock_path" ]; }; then
        _detect_print_error "packages-lock.json 파일을 읽을 수 없습니다: $lock_path"
        return 4
    fi

    if [ -e "$graphics_path" ] && { [ ! -f "$graphics_path" ] || [ ! -r "$graphics_path" ]; }; then
        _detect_print_error "GraphicsSettings.asset 파일을 읽을 수 없습니다: $graphics_path"
        return 4
    fi

    if ! grep -Eq '^m_EditorVersion:[[:space:]]*[^[:space:]]+' "$version_path" 2>/dev/null; then
        _detect_print_error "ProjectVersion.txt에서 m_EditorVersion을 읽을 수 없습니다: $version_path"
        return 4
    fi

    if ! _detect_validate_json_file "$manifest_path"; then
        _detect_print_error "manifest.json의 JSON 문법이 올바르지 않습니다: $manifest_path"
        return 4
    fi

    dependency_keys=$(_detect_manifest_dependency_keys "$manifest_path" 2>/dev/null)
    if [ "$?" -ne 0 ]; then
        _detect_print_error "manifest.json의 dependencies 형식이 올바르지 않습니다: $manifest_path"
        return 4
    fi
    _DETECT_PACKAGE_EVIDENCE='`Packages/manifest.json`'
    if [ -e "$lock_path" ]; then
        if ! _detect_validate_json_file "$lock_path"; then
            _detect_print_error "packages-lock.json의 JSON 문법이 올바르지 않습니다: $lock_path"
            return 4
        fi
        dependency_keys=$(_detect_package_dependency_keys "$project_root" 2>/dev/null)
        if [ "$?" -ne 0 ]; then
            _detect_print_error "packages-lock.json의 dependencies 형식이 올바르지 않습니다: $lock_path"
            return 4
        fi
        _DETECT_PACKAGE_EVIDENCE='`Packages/manifest.json`; `Packages/packages-lock.json`'
    fi
    _DETECT_MANIFEST_ROOT=$project_root
    _DETECT_MANIFEST_DEPENDENCY_KEYS=$dependency_keys

    manifest_compact=$(LC_ALL=C tr -d '[:space:]' < "$manifest_path" 2>/dev/null)
    case "$manifest_compact" in
        \{*\})
            ;;
        *)
            _detect_print_error "manifest.json의 최상위 JSON 형식이 올바르지 않습니다: $manifest_path"
            return 4
            ;;
    esac
    if [ ! -f "$schema_path" ] || [ ! -r "$schema_path" ]; then
        _detect_print_error "프로필 스키마를 읽을 수 없습니다: $schema_path"
        return 4
    fi

    _profile_check_schema "$schema_path" >/dev/null 2>&1
    if [ "$?" -ne 0 ]; then
        _detect_print_error "프로필 스키마 형식이 올바르지 않습니다: $schema_path"
        return 4
    fi

    _detect_validate_signatures "$signatures_path"
}

# [기능]: 시작 경로부터 상위로 이동하며 Unity 프로젝트 루트를 찾습니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: ProjectVersion.txt와 manifest.json의 동시 존재를 검증합니다.
find_unity_project_root()
{
    local start_path
    local candidate
    local parent
    local version_path
    local manifest_path

    if [ "$#" -ne 1 ]; then
        _detect_print_error "find_unity_project_root에는 시작 경로가 필요합니다."
        return 2
    fi

    start_path=$1
    if [ ! -e "$start_path" ]; then
        _detect_print_error "시작 경로를 찾을 수 없습니다: $start_path"
        return 2
    fi

    if [ -f "$start_path" ]; then
        start_path=${start_path%/*}
        if [ -z "$start_path" ]; then
            start_path=.
        fi
    fi

    candidate=$(cd -P "$start_path" 2>/dev/null && pwd -P)
    if [ "$?" -ne 0 ] || [ -z "$candidate" ]; then
        _detect_print_error "시작 경로를 읽을 수 없습니다: $start_path"
        return 4
    fi

    while :; do
        version_path="$candidate/ProjectSettings/ProjectVersion.txt"
        manifest_path="$candidate/Packages/manifest.json"

        if [ -e "$version_path" ] || [ -e "$manifest_path" ]; then
            if [ ! -f "$version_path" ] || [ ! -r "$version_path" ] || [ ! -f "$manifest_path" ] || [ ! -r "$manifest_path" ]; then
                _detect_print_error "Unity 프로젝트 필수 파일을 읽을 수 없습니다: $candidate"
                return 4
            fi

            printf '%s\n' "$candidate"
            return 0
        fi

        parent=${candidate%/*}
        if [ -z "$parent" ]; then
            parent=/
        fi
        if [ "$parent" = "$candidate" ]; then
            break
        fi
        candidate=$parent
    done

    _detect_print_error "Unity 프로젝트 루트를 찾을 수 없습니다: $start_path"
    return 2
}

_detect_unity_version_apply()
{
    local project_root=$1
    local version_path="$project_root/ProjectSettings/ProjectVersion.txt"
    local version

    version=$(sed -n 's/^m_EditorVersion:[[:space:]]*//p' "$version_path" 2>/dev/null | sed -n '1p')
    if [ -z "$version" ]; then
        _detect_print_error "ProjectVersion.txt에서 Unity 버전을 감지할 수 없습니다: $version_path"
        return 4
    fi

    _DETECT_RESULT=$version
    return 0
}

# [기능]: Unity 에디터 버전을 반환합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: m_EditorVersion 단일 값을 안전하게 추출합니다.
detect_unity_version()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_unity_version에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_unity_version_apply "$1" || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_source_roots_apply()
{
    local project_root=$1
    local code_root="$project_root/Assets/_Game"

    if [ ! -d "$code_root" ] || [ ! -r "$code_root" ]; then
        _detect_print_error "프로젝트 소유 코드 루트를 읽을 수 없습니다: $code_root"
        return 4
    fi

    _DETECT_RESULT='Assets/_Game'
    _DETECT_SOURCE_CONFIDENCE=high
    return 0
}

# [기능]: 프로젝트 소유 코드의 고정 경계인 Assets/_Game 소스 루트를 반환합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 외부 에셋을 배제하기 위해 Assets/_Game만 소스 루트로 사용합니다.
detect_source_roots()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_source_roots에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_run_with_code_cache "$1" _detect_source_roots_apply || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_test_root_from_path()
{
    local relative_path=$1
    local prefix

    case "$relative_path" in
        Tests/*)
            _DETECT_RESULT=Tests
            return 0
            ;;
        */Tests/*)
            prefix=${relative_path%%/Tests/*}
            _DETECT_RESULT="$prefix/Tests"
            return 0
            ;;
        Editor/*)
            _DETECT_RESULT=Editor
            return 0
            ;;
        */Editor/*)
            prefix=${relative_path%%/Editor/*}
            _DETECT_RESULT="$prefix/Editor"
            return 0
            ;;
        PlayMode/*)
            _DETECT_RESULT=PlayMode
            return 0
            ;;
        */PlayMode/*)
            prefix=${relative_path%%/PlayMode/*}
            _DETECT_RESULT="$prefix/PlayMode"
            return 0
            ;;
        EditMode/*)
            _DETECT_RESULT=EditMode
            return 0
            ;;
        */EditMode/*)
            prefix=${relative_path%%/EditMode/*}
            _DETECT_RESULT="$prefix/EditMode"
            return 0
            ;;
        *Tests/*)
            prefix=${relative_path%/*}
            _DETECT_RESULT=$prefix
            return 0
            ;;
    esac

    return 1
}

_detect_test_roots_apply()
{
    local project_root=$1
    local roots=""
    local file_path
    local relative_path

    while IFS= read -r file_path || [ -n "$file_path" ]; do
        case "$file_path" in
            *.cs)
                relative_path=$(_detect_relative_path "$project_root" "$file_path")
                if _detect_test_root_from_path "$relative_path"; then
                    _detect_append_unique_line "$roots" "$_DETECT_RESULT"
                    roots=$_DETECT_RESULT
                fi
                ;;
        esac
    done <<DETECT_CODE_FILES_EOF
$(_detect_code_files "$project_root")
DETECT_CODE_FILES_EOF

    if [ -n "$roots" ]; then
        _DETECT_RESULT=$(printf '%s\n' "$roots" | LC_ALL=C sort -u)
        _DETECT_TEST_CONFIDENCE=high
    else
        _DETECT_RESULT=""
        _DETECT_TEST_CONFIDENCE=unknown
    fi

    return 0
}

# [기능]: 실제 C# 파일이 있는 테스트 루트를 반환합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: Tests, Editor, PlayMode, EditMode 경로 증거를 사용합니다.
detect_test_roots()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_test_roots에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_run_with_code_cache "$1" _detect_test_roots_apply || return $?
    if [ -n "$_DETECT_RESULT" ]; then
        printf '%s\n' "$_DETECT_RESULT"
    fi
}

_detect_render_pipeline_apply()
{
    local project_root=$1
    local graphics_path="$project_root/ProjectSettings/GraphicsSettings.asset"
    local has_urp=0
    local has_hdrp=0

    if _detect_manifest_matches "$project_root" 'com\.unity\.render-pipelines\.universal'; then
        has_urp=1
    fi
    if _detect_manifest_matches "$project_root" 'com\.unity\.render-pipelines\.high-definition'; then
        has_hdrp=1
    fi

    if [ "$has_urp" -eq 1 ] && [ "$has_hdrp" -eq 1 ]; then
        _DETECT_RESULT=custom
        _DETECT_RENDER_CONFIDENCE=high
        return 0
    fi
    if [ "$has_urp" -eq 1 ]; then
        _DETECT_RESULT=urp
        _DETECT_RENDER_CONFIDENCE=medium
        return 0
    fi
    if [ "$has_hdrp" -eq 1 ]; then
        _DETECT_RESULT=hdrp
        _DETECT_RENDER_CONFIDENCE=medium
        return 0
    fi

    if [ -f "$graphics_path" ] && grep -Eq 'm_CustomRenderPipeline:[[:space:]]*\{fileID:[[:space:]]*0\}' "$graphics_path" 2>/dev/null; then
        _DETECT_RESULT=builtin
        _DETECT_RENDER_CONFIDENCE=high
    elif [ -f "$graphics_path" ]; then
        _DETECT_RESULT=unknown
        _DETECT_RENDER_CONFIDENCE=low
    else
        _DETECT_RESULT=unknown
        _DETECT_RENDER_CONFIDENCE=unknown
    fi

    return 0
}

# [기능]: 렌더 파이프라인 패키지와 GraphicsSettings 증거를 판정합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: URP/HDRP 동시 설치를 custom 충돌로 처리합니다.
detect_render_pipeline()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_render_pipeline에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_render_pipeline_apply "$1" || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_dependency_injection_apply()
{
    local project_root=$1
    local installed=""
    local has_vcontainer=0
    local has_zenject=0

    if _detect_manifest_matches "$project_root" '([[:alnum:]_-]+[.])*vcontainer'; then
        installed=VContainer
    fi
    if _detect_manifest_matches "$project_root" '([[:alnum:]_-]+[.])*(zenject|extenject)'; then
        if [ -n "$installed" ]; then
            installed="$installed, Zenject"
        else
            installed=Zenject
        fi
    fi
    if _detect_any_csharp_code_match "$project_root" '^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+(static[[:space:]]+)?VContainer([.]|[[:space:]]*;)|(^|[^[:alnum:]_])VContainer[.]|(^|[^[:alnum:]_])(LifetimeScope|IContainerBuilder|IObjectResolver)([^[:alnum:]_]|$)'; then
        has_vcontainer=1
    fi
    if _detect_any_csharp_code_match "$project_root" '^[[:space:]]*(global[[:space:]]+)?using[[:space:]]+(static[[:space:]]+)?(Zenject|Extenject)([.]|[[:space:]]*;)|(^|[^[:alnum:]_])(Zenject|Extenject)[.]|(^|[^[:alnum:]_])(DiContainer|MonoInstaller|PlaceholderFactory)([^[:alnum:]_]|$)'; then
        has_zenject=1
    fi

    if [ "$has_vcontainer" -eq 1 ] && [ "$has_zenject" -eq 1 ]; then
        _DETECT_RESULT=custom
        _DETECT_DI_CONFIDENCE=high
        _DETECT_DI_EVIDENCE="코드 사용 근거 확인: VContainer, Zenject"
    elif [ "$has_vcontainer" -eq 1 ]; then
        _DETECT_RESULT=vcontainer
        _DETECT_DI_CONFIDENCE=high
        _DETECT_DI_EVIDENCE="코드 사용 근거 확인: VContainer"
    elif [ "$has_zenject" -eq 1 ]; then
        _DETECT_RESULT=zenject
        _DETECT_DI_CONFIDENCE=high
        _DETECT_DI_EVIDENCE="코드 사용 근거 확인: Zenject"
    elif _detect_any_csharp_code_match "$project_root" '(^|[^[:alnum:]_])(DependencyInjector|ServiceContainer|InjectAttribute)([^[:alnum:]_]|$)'; then
        _DETECT_RESULT=custom
        _DETECT_DI_CONFIDENCE=medium
        _DETECT_DI_EVIDENCE="사용자 정의 DI 코드 근거 확인"
    elif [ -n "$installed" ]; then
        _DETECT_RESULT=unknown
        _DETECT_DI_CONFIDENCE=low
        _DETECT_DI_EVIDENCE="$installed 패키지 설치만 확인, 코드 사용 미확정"
    else
        _DETECT_RESULT=unknown
        _DETECT_DI_CONFIDENCE=unknown
        _DETECT_DI_EVIDENCE="확정할 코드 사용 근거 없음"
    fi

    return 0
}

# [기능]: manifest와 코드 증거로 의존성 주입 백엔드를 판정합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 주석·문자열·경로를 제외한 코드 사용 근거로 VContainer, Zenject, custom, unknown을 구분합니다.
detect_dependency_injection()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_dependency_injection에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_run_with_code_cache "$1" _detect_dependency_injection_apply || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_async_backend_apply()
{
    local project_root=$1
    local installed_unitask=0
    local has_unitask=0
    local has_coroutine=0
    local has_task=0
    local count=0

    if _detect_manifest_matches "$project_root" '([[:alnum:]_-]+[.])*unitask'; then
        installed_unitask=1
    fi
    if _detect_any_csharp_code_match "$project_root" 'Cysharp[.]Threading[.]Tasks|(^|[^[:alnum:]_])(UniTask|UniTaskVoid|UniTaskCompletionSource)([^[:alnum:]_]|$)'; then
        has_unitask=1
        count=$((count + 1))
    fi
    if _detect_any_csharp_code_match "$project_root" 'StartCoroutine[[:space:]]*[(]|yield[[:space:]]+return|(^|[^[:alnum:]_])IEnumerator([[:space:]<]|$)|(^|[^[:alnum:]_])Coroutine([[:space:]<]|$)'; then
        has_coroutine=1
        count=$((count + 1))
    fi
    if _detect_any_csharp_code_match "$project_root" 'System[.]Threading[.]Tasks|(^|[^[:alnum:]_])Task([<[:space:](]|$)|(^|[^[:alnum:]_])TaskCompletionSource([^[:alnum:]_]|$)'; then
        has_task=1
        count=$((count + 1))
    fi

    if [ "$count" -gt 1 ]; then
        _DETECT_RESULT=mixed
        _DETECT_ASYNC_CONFIDENCE=high
        _DETECT_ASYNC_EVIDENCE="복수 비동기 코드 사용 근거 확인"
    elif [ "$has_unitask" -eq 1 ]; then
        _DETECT_RESULT=unitask
        _DETECT_ASYNC_CONFIDENCE=high
        _DETECT_ASYNC_EVIDENCE="코드 사용 근거 확인: UniTask"
    elif [ "$has_coroutine" -eq 1 ]; then
        _DETECT_RESULT=coroutine
        _DETECT_ASYNC_CONFIDENCE=high
        _DETECT_ASYNC_EVIDENCE="코드 사용 근거 확인: Coroutine"
    elif [ "$has_task" -eq 1 ]; then
        _DETECT_RESULT=task
        _DETECT_ASYNC_CONFIDENCE=high
        _DETECT_ASYNC_EVIDENCE="코드 사용 근거 확인: Task"
    elif [ "$installed_unitask" -eq 1 ]; then
        _DETECT_RESULT=unknown
        _DETECT_ASYNC_CONFIDENCE=low
        _DETECT_ASYNC_EVIDENCE="UniTask 패키지 설치만 확인, 코드 사용 미확정"
    else
        _DETECT_RESULT=unknown
        _DETECT_ASYNC_CONFIDENCE=unknown
        _DETECT_ASYNC_EVIDENCE="판정할 코드 근거 없음"
    fi

    if [ "$installed_unitask" -eq 1 ] && [ "$has_unitask" -eq 0 ] && [ "$count" -gt 0 ]; then
        _DETECT_ASYNC_EVIDENCE="$_DETECT_ASYNC_EVIDENCE; UniTask 패키지 설치만 확인, 코드 사용 미확정"
    fi

    return 0
}

# [기능]: UniTask, Coroutine, Task 코드 증거로 비동기 백엔드를 판정합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 두 종류 이상의 증거를 mixed로 처리합니다.
detect_async_backend()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_async_backend에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_run_with_code_cache "$1" _detect_async_backend_apply || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_tween_backend_apply()
{
    local project_root=$1
    local installed=""
    local has_dotween=0
    local has_leantween=0

    if _detect_manifest_matches "$project_root" '([[:alnum:]_-]+[.])*dotween'; then
        installed=DOTween
    fi
    if _detect_manifest_matches "$project_root" '([[:alnum:]_-]+[.])*leantween'; then
        if [ -n "$installed" ]; then
            installed="$installed, LeanTween"
        else
            installed=LeanTween
        fi
    fi
    if _detect_any_csharp_code_match "$project_root" 'DG[.]Tweening|(^|[^[:alnum:]_])(DOTween|DOVirtual)[[:space:]]*[.]|[.]DO[A-Z][[:alnum:]_]*[[:space:]]*[(]'; then
        has_dotween=1
    fi
    if _detect_any_csharp_code_match "$project_root" '(^|[^[:alnum:]_])LeanTween[[:space:]]*[.]'; then
        has_leantween=1
    fi

    if [ "$has_dotween" -eq 1 ] && [ "$has_leantween" -eq 1 ]; then
        _DETECT_RESULT=custom
        _DETECT_TWEEN_CONFIDENCE=high
        _DETECT_TWEEN_EVIDENCE="코드 사용 근거 확인: DOTween, LeanTween"
    elif [ "$has_dotween" -eq 1 ]; then
        _DETECT_RESULT=dotween
        _DETECT_TWEEN_CONFIDENCE=high
        _DETECT_TWEEN_EVIDENCE="코드 사용 근거 확인: DOTween"
    elif [ "$has_leantween" -eq 1 ]; then
        _DETECT_RESULT=leantween
        _DETECT_TWEEN_CONFIDENCE=high
        _DETECT_TWEEN_EVIDENCE="코드 사용 근거 확인: LeanTween"
    elif _detect_any_csharp_code_match "$project_root" '(^|[^[:alnum:]_])(ITween|TweenService|TweenRunner)([^[:alnum:]_]|$)'; then
        _DETECT_RESULT=custom
        _DETECT_TWEEN_CONFIDENCE=medium
        _DETECT_TWEEN_EVIDENCE="사용자 정의 트윈 코드 근거 확인"
    elif [ -n "$installed" ]; then
        _DETECT_RESULT=unknown
        _DETECT_TWEEN_CONFIDENCE=low
        _DETECT_TWEEN_EVIDENCE="$installed 패키지 설치만 확인, 코드 사용 미확정"
    else
        _DETECT_RESULT=unknown
        _DETECT_TWEEN_CONFIDENCE=unknown
        _DETECT_TWEEN_EVIDENCE="확정할 코드 사용 근거 없음"
    fi

    return 0
}

# [기능]: DOTween, LeanTween, custom 트윈 증거를 판정합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 주석·문자열·경로를 제외한 코드 사용 근거로 트윈 백엔드를 판정합니다.
detect_tween_backend()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_tween_backend에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_run_with_code_cache "$1" _detect_tween_backend_apply || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_target_platforms_apply()
{
    _DETECT_RESULT=unknown
    return 0
}

# [기능]: 정적 파일만으로 확정할 수 없는 타겟 플랫폼을 unknown으로 반환합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 사용자 확인이 필요한 안전한 기본값을 제공합니다.
detect_target_platforms()
{
    if [ "$#" -ne 1 ]; then
        _detect_print_error "detect_target_platforms에는 프로젝트 루트가 필요합니다."
        return 2
    fi

    _detect_target_platforms_apply "$1" || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_architecture_apply()
{
    local project_root=$1
    local signatures_path=$2
    local line
    local profile
    local remainder
    local pattern
    local weight
    local mvvm_score=0
    local mvp_score=0
    local mvc_score=0
    local layered_clean_score=0
    local max_score=0
    local max_profile=custom
    local max_count=0
    local evidence=""
    local score

    while IFS= read -r line || [ -n "$line" ]; do
        if _detect_is_ignored_line "$line"; then
            continue
        fi

        profile=${line%%|*}
        remainder=${line#*|}
        pattern=${remainder%%|*}
        weight=${remainder#*|}

        case "$pattern" in
            */*)
                _detect_any_code_path_match "$project_root" "$pattern"
                ;;
            *)
                _detect_any_csharp_code_match "$project_root" "$pattern"
                ;;
        esac
        if [ "$?" -eq 0 ]; then
            case "$profile" in
                mvvm)
                    mvvm_score=$((mvvm_score + weight))
                    ;;
                mvp)
                    mvp_score=$((mvp_score + weight))
                    ;;
                mvc)
                    mvc_score=$((mvc_score + weight))
                    ;;
                layered_clean)
                    layered_clean_score=$((layered_clean_score + weight))
                    ;;
            esac

            if [ -z "$evidence" ]; then
                evidence="$profile:$pattern(+$weight)"
            else
                evidence="$evidence, $profile:$pattern(+$weight)"
            fi
        fi
    done < "$signatures_path"

    for profile in mvvm mvp mvc layered_clean
    do
        case "$profile" in
            mvvm) score=$mvvm_score ;;
            mvp) score=$mvp_score ;;
            mvc) score=$mvc_score ;;
            layered_clean) score=$layered_clean_score ;;
        esac

        if [ "$score" -gt "$max_score" ]; then
            max_score=$score
            max_profile=$profile
            max_count=1
        elif [ "$score" -eq "$max_score" ] && [ "$score" -gt 0 ]; then
            max_count=$((max_count + 1))
        fi
    done

    _DETECT_ARCHITECTURE_EVIDENCE="mvvm=$mvvm_score, mvp=$mvp_score, mvc=$mvc_score, layered_clean=$layered_clean_score; $evidence"
    _DETECT_ARCHITECTURE_CONFLICT=0
    if [ "$max_score" -ge 4 ] && [ "$max_count" -eq 1 ]; then
        _DETECT_RESULT=$max_profile
        _DETECT_ARCHITECTURE_CONFIDENCE=high
    else
        _DETECT_RESULT=custom
        if [ "$max_count" -gt 1 ] && [ "$max_score" -ge 4 ]; then
            _DETECT_ARCHITECTURE_CONFLICT=1
            _DETECT_ARCHITECTURE_CONFIDENCE=high
        elif [ "$max_score" -gt 0 ]; then
            _DETECT_ARCHITECTURE_CONFIDENCE=low
        else
            _DETECT_ARCHITECTURE_CONFIDENCE=unknown
        fi
    fi

    return 0
}

# [기능]: 공유 시그니처 점수로 아키텍처를 판정합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 유일한 최고 점수 4 이상만 확정하고 나머지는 custom으로 처리합니다.
detect_architecture()
{
    if [ "$#" -ne 2 ]; then
        _detect_print_error "detect_architecture에는 프로젝트 루트와 시그니처 경로가 필요합니다."
        return 2
    fi

    _detect_run_with_code_cache "$1" _detect_architecture_apply "$2" || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_optimization_states_apply()
{
    local unity_version=$1
    local render_pipeline=$2
    local version_major=${unity_version%%.*}
    local version_remainder=${unity_version#*.}
    local version_minor=${version_remainder%%.*}
    local is_unity_6=0
    local is_unity_62=0

    case "$version_major" in
        ''|*[!0-9]*)
            version_major=0
            ;;
    esac
    case "$version_minor" in
        ''|*[!0-9]*)
            version_minor=0
            ;;
    esac

    if [ "$version_major" -ge 6000 ]; then
        is_unity_6=1
    fi
    if [ "$version_major" -gt 6000 ] || { [ "$version_major" -eq 6000 ] && [ "$version_minor" -ge 2 ]; }; then
        is_unity_62=1
    fi

    case "$render_pipeline" in
        urp|hdrp)
            if [ "$is_unity_6" -eq 1 ]; then
                _DETECT_GPU_RESIDENT_DRAWER=applicable
                _DETECT_GPU_OCCLUSION_CULLING=unknown
            else
                _DETECT_GPU_RESIDENT_DRAWER=not_applicable
                _DETECT_GPU_OCCLUSION_CULLING=not_applicable
            fi
            ;;
        builtin)
            _DETECT_GPU_RESIDENT_DRAWER=not_applicable
            _DETECT_GPU_OCCLUSION_CULLING=not_applicable
            ;;
        *)
            _DETECT_GPU_RESIDENT_DRAWER=unknown
            _DETECT_GPU_OCCLUSION_CULLING=unknown
            ;;
    esac

    if [ "$render_pipeline" = "urp" ] && [ "$is_unity_6" -eq 1 ]; then
        _DETECT_STP=applicable
    elif [ "$render_pipeline" = "custom" ] || [ "$render_pipeline" = "unknown" ]; then
        _DETECT_STP=unknown
    else
        _DETECT_STP=not_applicable
    fi

    if [ "$is_unity_62" -eq 0 ] || [ "$render_pipeline" = "builtin" ]; then
        _DETECT_MESH_LOD=not_applicable
    else
        _DETECT_MESH_LOD=unknown
    fi

    _DETECT_RESULT="gpu_resident_drawer=$_DETECT_GPU_RESIDENT_DRAWER
gpu_occlusion_culling=$_DETECT_GPU_OCCLUSION_CULLING
stp=$_DETECT_STP
mesh_lod=$_DETECT_MESH_LOD"
    return 0
}

# [기능]: Unity 버전과 렌더 파이프라인 전제만으로 최적화 적용 가능성을 판정합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 씬, GPU, 활성 설정이 필요한 항목은 unknown으로 보존합니다.
detect_optimization_states()
{
    if [ "$#" -ne 2 ]; then
        _detect_print_error "detect_optimization_states에는 Unity 버전과 렌더 파이프라인이 필요합니다."
        return 2
    fi

    _detect_optimization_states_apply "$1" "$2" || return $?
    printf '%s\n' "$_DETECT_RESULT"
}

_detect_write_profile_seed()
{
    local output_path=$1
    local source_root
    local test_root
    local target_platform

    if ! printf '%s\n' \
        'profile_version=1' \
        'confirmation_status=pending' \
        "project_name=$_DETECT_PROJECT_NAME" \
        "unity_version=$_DETECT_UNITY_VERSION" \
        "render_pipeline=$_DETECT_RENDER_PIPELINE" \
        "architecture=$_DETECT_ARCHITECTURE" > "$output_path"; then
        _detect_print_error "프로필 임시 파일을 기록할 수 없습니다: $output_path"
        return 2
    fi

    while IFS= read -r source_root || [ -n "$source_root" ]; do
        if [ -n "$source_root" ]; then
            printf 'source_root=%s\n' "$source_root" >> "$output_path" || return 2
        fi
    done <<DETECT_SOURCE_ROOTS_EOF
$_DETECT_SOURCE_ROOTS
DETECT_SOURCE_ROOTS_EOF

    while IFS= read -r test_root || [ -n "$test_root" ]; do
        if [ -n "$test_root" ]; then
            printf 'test_root=%s\n' "$test_root" >> "$output_path" || return 2
        fi
    done <<DETECT_TEST_ROOTS_EOF
$_DETECT_TEST_ROOTS
DETECT_TEST_ROOTS_EOF

    if ! printf '%s\n' \
        "dependency_injection=$_DETECT_DEPENDENCY_INJECTION" \
        "async_backend=$_DETECT_ASYNC_BACKEND" \
        "tween_backend=$_DETECT_TWEEN_BACKEND" >> "$output_path"; then
        return 2
    fi

    while IFS= read -r target_platform || [ -n "$target_platform" ]; do
        if [ -n "$target_platform" ]; then
            printf 'target_platform=%s\n' "$target_platform" >> "$output_path" || return 2
        fi
    done <<DETECT_TARGET_PLATFORMS_EOF
$_DETECT_TARGET_PLATFORMS
DETECT_TARGET_PLATFORMS_EOF

    printf '%s\n' \
        'response_language=ko' \
        'log_language=ko' \
        'author_name=윤승종' \
        'private_field_prefix=m_' \
        'ui_callback_prefix=func_' \
        'region_policy=encouraged' \
        'xml_documentation_policy=all_methods' \
        "gpu_resident_drawer=$_DETECT_GPU_RESIDENT_DRAWER" \
        "gpu_occlusion_culling=$_DETECT_GPU_OCCLUSION_CULLING" \
        "stp=$_DETECT_STP" \
        "mesh_lod=$_DETECT_MESH_LOD" \
        'exclude_root=Library' \
        'exclude_root=Temp' \
        'exclude_root=Logs' \
        'exclude_root=obj' \
        'exclude_root=UserSettings' \
        'exclude_root=Packages' \
        'exclude_root=.git' \
        'exclude_root=.agents' \
        'exclude_root=.agents-backup' \
        'exclude_root=Assets/Plugins' \
        'exclude_root=Assets/ThirdParty' >> "$output_path"
}

_detect_prepare_profile()
{
    local profile_path=$1
    local schema_path=$2
    local directory
    local file_name
    local temporary_prefix
    local temporary_path
    local prepared_prefix
    local prepared_path
    local existing_mode=""
    local status

    directory=${profile_path%/*}
    file_name=${profile_path##*/}
    if [ "$directory" = "$profile_path" ]; then
        directory=.
    fi
    if [ ! -d "$directory" ]; then
        _detect_print_error "프로필 출력 디렉터리를 찾을 수 없습니다: $directory"
        return 2
    fi
    if [ -d "$profile_path" ]; then
        _detect_print_error "프로필 출력 경로로 디렉터리를 사용할 수 없습니다: $profile_path"
        return 2
    fi
    if [ -e "$profile_path" ] && [ ! -f "$profile_path" ] && [ ! -L "$profile_path" ]; then
        _detect_print_error "프로필 출력 경로가 일반 파일이 아닙니다: $profile_path"
        return 2
    fi
    if [ -e "$profile_path" ] && [ ! -L "$profile_path" ] && [ -f "$profile_path" ]; then
        existing_mode=$(_profile_read_file_mode "$profile_path")
        status=$?
        if [ "$status" -ne 0 ] || [ -z "$existing_mode" ]; then
            _detect_print_error "기존 프로필 권한을 읽을 수 없습니다: $profile_path"
            return 2
        fi
    fi

    temporary_prefix="$directory/.${file_name}.seed."
    _DETECT_ACTIVE_PROFILE_SEED_PREFIX=$temporary_prefix
    _DETECT_ACTIVE_PROFILE_SEED=$(mktemp "${temporary_prefix}XXXXXX" 2>/dev/null)
    status=$?
    temporary_path=$_DETECT_ACTIVE_PROFILE_SEED
    if [ "$status" -ne 0 ] || [ -z "$temporary_path" ] || [ ! -f "$temporary_path" ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _DETECT_ACTIVE_PROFILE_SEED=""
        _DETECT_ACTIVE_PROFILE_SEED_PREFIX=""
        _detect_print_error "프로필 임시 파일을 만들 수 없습니다: $directory"
        return 2
    fi

    _detect_write_profile_seed "$temporary_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _DETECT_ACTIVE_PROFILE_SEED=""
        _DETECT_ACTIVE_PROFILE_SEED_PREFIX=""
        return "$status"
    fi

    profile_load "$temporary_path" "$schema_path" >/dev/null 2>&1
    status=$?
    if [ "$status" -ne 0 ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _DETECT_ACTIVE_PROFILE_SEED=""
        _DETECT_ACTIVE_PROFILE_SEED_PREFIX=""
        _detect_print_error "감지 프로필이 스키마 검증에 실패했습니다."
        return "$status"
    fi

    prepared_prefix="$directory/.${file_name}.prepare."
    _DETECT_PREPARED_PROFILE_PREFIX=$prepared_prefix
    _DETECT_PREPARED_PROFILE=$(mktemp "${prepared_prefix}XXXXXX" 2>/dev/null)
    status=$?
    prepared_path=$_DETECT_PREPARED_PROFILE
    if [ "$status" -ne 0 ] || [ -z "$prepared_path" ] || [ ! -f "$prepared_path" ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _DETECT_ACTIVE_PROFILE_SEED=""
        _DETECT_ACTIVE_PROFILE_SEED_PREFIX=""
        _profile_cleanup_temporary_file "$prepared_path" "$prepared_prefix"
        _detect_print_error "프로필 준비 파일을 만들 수 없습니다: $directory"
        return 2
    fi

    _profile_render_to_file "$prepared_path" "$schema_path" >/dev/null 2>&1
    status=$?
    _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
    _DETECT_ACTIVE_PROFILE_SEED=""
    _DETECT_ACTIVE_PROFILE_SEED_PREFIX=""
    if [ "$status" -ne 0 ]; then
        _profile_cleanup_temporary_file "$prepared_path" "$prepared_prefix"
        _DETECT_PREPARED_PROFILE=""
        _DETECT_PREPARED_PROFILE_PREFIX=""
        _detect_print_error "감지 프로필을 준비할 수 없습니다: $profile_path"
        return "$status"
    fi

    if [ -n "$existing_mode" ] && ! chmod "$existing_mode" "$prepared_path" 2>/dev/null; then
        _profile_cleanup_temporary_file "$prepared_path" "$prepared_prefix"
        _DETECT_PREPARED_PROFILE=""
        _DETECT_PREPARED_PROFILE_PREFIX=""
        _detect_print_error "기존 프로필 권한을 적용할 수 없습니다: $profile_path"
        return 2
    fi

    return 0
}

_detect_render_profile_comparison()
{
    local existing_path=$1
    local candidate_path=$2
    local candidate_display_path=${3:-$candidate_path}
    local schema_path=$_PROFILE_SCHEMA_PATH
    local schema_line
    local key
    local before_value
    local candidate_value
    local difference_count=0

    printf '%s\n' '**기존 프로필 비교**' ''
    printf '%s\n' "- 기존 프로필: \`$existing_path\`"
    printf '%s\n' "- 재감지 후보: \`$candidate_display_path\`"
    printf '%s\n' '- 기존 확정 프로필은 변경하지 않았습니다.' ''

    if [ ! -f "$existing_path" ] || [ ! -f "$candidate_path" ] || [ ! -f "$schema_path" ]; then
        printf '%s\n' '- 비교할 프로필 파일을 읽을 수 없습니다.'
        return 0
    fi

    while IFS= read -r schema_line || [ -n "$schema_line" ]; do
        if _detect_is_ignored_line "$schema_line"; then
            continue
        fi
        key=${schema_line%%|*}
        before_value=$(grep "^${key}=" "$existing_path" 2>/dev/null | sed "s/^${key}=//")
        candidate_value=$(grep "^${key}=" "$candidate_path" 2>/dev/null | sed "s/^${key}=//")
        if [ "$before_value" != "$candidate_value" ]; then
            printf '%s\n' "- \`$key\`: 기존 \`$before_value\` → 후보 \`$candidate_value\`"
            difference_count=$((difference_count + 1))
        fi
    done < "$schema_path"

    if [ "$difference_count" -eq 0 ]; then
        printf '%s\n' '- 감지 값 차이가 없습니다.'
    fi
}

_detect_render_report()
{
    local output_path=$1
    local source_root
    local test_root

    {
        printf '%s\n' '# Unity 하네스 감지 보고서' ''
        printf '%s\n' '## 요약' ''
        printf '%s\n' "- 프로젝트: \`$_DETECT_PROJECT_NAME\` (신뢰도: high, 근거 파일: 프로젝트 루트 디렉터리명)"
        printf '%s\n' "- Unity: \`$_DETECT_UNITY_VERSION\` (신뢰도: high, 근거 파일: \`ProjectSettings/ProjectVersion.txt\`)"
        printf '%s\n' "- 렌더 파이프라인: \`$_DETECT_RENDER_PIPELINE\` (신뢰도: $_DETECT_RENDER_CONFIDENCE, 근거 파일: $_DETECT_PACKAGE_EVIDENCE, \`ProjectSettings/GraphicsSettings.asset\`)"
        printf '%s\n' "- 아키텍처: \`$_DETECT_ARCHITECTURE\` (신뢰도: $_DETECT_ARCHITECTURE_CONFIDENCE, 근거 파일: \`.agents/config/detection-signatures.conf\`, 제외 경계 밖 .cs)"
        printf '%s\n' "- 프로필 상태: \`pending\` (신뢰도: high, 근거 파일: 생성된 프로필 후보)" ''

        printf '%s\n' '## 감지 근거와 신뢰도' ''
        printf '%s\n' '| 항목 | 값 | 신뢰도 | 근거 파일 및 증거 |' '|---|---|---|---|'
        printf '%s\n' "| unity_version | \`$_DETECT_UNITY_VERSION\` | high | \`ProjectSettings/ProjectVersion.txt\`의 \`m_EditorVersion\` |"
        printf '%s\n' "| render_pipeline | \`$_DETECT_RENDER_PIPELINE\` | $_DETECT_RENDER_CONFIDENCE | 설치 증거: $_DETECT_PACKAGE_EVIDENCE; 활성화 증거: \`ProjectSettings/GraphicsSettings.asset\` |"
        printf '%s\n' "| architecture | \`$_DETECT_ARCHITECTURE\` | $_DETECT_ARCHITECTURE_CONFIDENCE | \`.agents/config/detection-signatures.conf\`와 제외 경계 밖 .cs 경로/namespace/class; $_DETECT_ARCHITECTURE_EVIDENCE |"
        printf '%s\n' "| dependency_injection | \`$_DETECT_DEPENDENCY_INJECTION\` | $_DETECT_DI_CONFIDENCE | $_DETECT_DI_EVIDENCE |"
        printf '%s\n' "| async_backend | \`$_DETECT_ASYNC_BACKEND\` | $_DETECT_ASYNC_CONFIDENCE | $_DETECT_ASYNC_EVIDENCE |"
        printf '%s\n' "| tween_backend | \`$_DETECT_TWEEN_BACKEND\` | $_DETECT_TWEEN_CONFIDENCE | $_DETECT_TWEEN_EVIDENCE |"
        printf '%s\n' "| target_platform | \`$_DETECT_TARGET_PLATFORMS\` | unknown | 정적 프로젝트 파일만으로 활성 빌드 타겟 확정 불가 |" ''

        printf '%s\n' '## 소스 및 테스트 루트' ''
        while IFS= read -r source_root || [ -n "$source_root" ]; do
            if [ -n "$source_root" ]; then
                printf '%s\n' "- source_root: \`$source_root\` (신뢰도: $_DETECT_SOURCE_CONFIDENCE, 근거: asmdef/Scripts/.cs)"
            fi
        done <<DETECT_SOURCE_ROOTS_EOF
$_DETECT_SOURCE_ROOTS
DETECT_SOURCE_ROOTS_EOF
        if [ -n "$_DETECT_TEST_ROOTS" ]; then
            while IFS= read -r test_root || [ -n "$test_root" ]; do
                if [ -n "$test_root" ]; then
                    printf '%s\n' "- test_root: \`$test_root\` (신뢰도: $_DETECT_TEST_CONFIDENCE, 근거: 테스트 명명 폴더와 실제 .cs)"
                fi
            done <<DETECT_TEST_ROOTS_EOF
$_DETECT_TEST_ROOTS
DETECT_TEST_ROOTS_EOF
        else
            printf '%s\n' '- test_root: 감지되지 않음 (신뢰도: unknown)'
        fi
        printf '\n'

        printf '%s\n' '## 조건부 최적화 적용 가능성' ''
        printf '%s\n' "- gpu_resident_drawer: \`$_DETECT_GPU_RESIDENT_DRAWER\` — Unity 버전과 렌더 파이프라인 전제만 판정"
        printf '%s\n' "- gpu_occlusion_culling: \`$_DETECT_GPU_OCCLUSION_CULLING\` — 씬 가림 구조와 GPU 프로파일링 확인 필요"
        printf '%s\n' "- stp: \`$_DETECT_STP\` — TAA, Render Scale, Motion Vector 활성 상태 확인 필요"
        printf '%s\n' "- mesh_lod: \`$_DETECT_MESH_LOD\` — 현재 Unity 버전의 기본 Mesh LOD 지원 확인 필요; 6000.3 cross-fade는 GPU Resident Drawer 활성화 필요, 다른 버전 미확인은 unknown" ''

        printf '%s\n' '## 충돌 및 미확정 항목' ''
        if [ "$_DETECT_ARCHITECTURE_CONFLICT" -eq 1 ]; then
            printf '%s\n' '- 아키텍처 강한 시그니처 점수가 충돌하여 custom으로 처리했습니다.'
        elif [ "$_DETECT_ARCHITECTURE" = "custom" ]; then
            printf '%s\n' '- 아키텍처 최고 점수가 유일하지 않거나 4 미만이므로 custom으로 처리했습니다.'
        fi
        if [ "$_DETECT_RENDER_PIPELINE" = "custom" ]; then
            printf '%s\n' '- URP와 HDRP 패키지 설치 증거가 충돌합니다.'
        fi
        if [ "$_DETECT_DEPENDENCY_INJECTION" = "custom" ]; then
            printf '%s\n' '- 복수 DI 또는 사용자 정의 DI 증거가 있어 custom으로 처리했습니다.'
        fi
        if [ "$_DETECT_TWEEN_BACKEND" = "custom" ]; then
            printf '%s\n' '- 복수 트윈 또는 사용자 정의 트윈 증거가 있어 custom으로 처리했습니다.'
        fi
        printf '%s\n' '- target_platform은 unknown이며 Unity Editor에서 사용자가 확인해야 합니다.'
        printf '%s\n' '- 패키지 설치 증거는 실제 씬/에셋 활성화와 동일하지 않습니다.' ''

        if [ -n "$_DETECT_COMPARISON_PROFILE" ]; then
            _detect_render_profile_comparison "$_DETECT_COMPARISON_PROFILE" "$_DETECT_PREPARED_PROFILE" "$_DETECT_PROFILE_OUTPUT"
            printf '\n'
        fi

        printf '%s\n' '## 사용자 확인 절차' ''
        printf '%s\n' '1. 감지 프로필과 위 근거 파일을 검토합니다.'
        printf '%s\n' '2. Unity Editor에서 활성 Render Pipeline Asset과 Build Target을 확인합니다.'
        printf '%s\n' '3. 조건부 최적화는 씬·GPU·플랫폼 프로파일링 후 적용합니다.'
        printf '%s\n' '4. 값이 올바르면 초기화 스크립트의 `--confirm`으로 상태만 confirmed로 전환합니다.'
    } > "$output_path"
}

# [기능]: 감지 근거와 사용자 확인 절차를 Markdown 보고서로 원자 교체합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 프로필 쓰기와 같은 임시 파일 및 교체 정책을 적용합니다.
_detect_prepare_report()
{
    local report_path
    local directory
    local file_name
    local temporary_prefix
    local temporary_path
    local existing_mode=""
    local status

    if [ "$#" -ne 1 ]; then
        _detect_print_error "write_detection_report에는 보고서 경로가 필요합니다."
        return 2
    fi

    report_path=$1
    directory=${report_path%/*}
    file_name=${report_path##*/}
    if [ "$directory" = "$report_path" ]; then
        directory=.
    fi
    if [ ! -d "$directory" ]; then
        _detect_print_error "보고서 출력 디렉터리를 찾을 수 없습니다: $directory"
        return 2
    fi
    if [ -d "$report_path" ]; then
        _detect_print_error "보고서 출력 경로로 디렉터리를 사용할 수 없습니다: $report_path"
        return 2
    fi
    if [ -e "$report_path" ] && [ ! -L "$report_path" ] && [ -f "$report_path" ]; then
        existing_mode=$(_profile_read_file_mode "$report_path")
        if [ "$?" -ne 0 ] || [ -z "$existing_mode" ]; then
            _detect_print_error "기존 보고서 권한을 읽을 수 없습니다: $report_path"
            return 2
        fi
    fi

    temporary_prefix="$directory/.${file_name}.prepare."
    _DETECT_PREPARED_REPORT_PREFIX=$temporary_prefix
    _DETECT_PREPARED_REPORT=$(mktemp "${temporary_prefix}XXXXXX" 2>/dev/null)
    status=$?
    temporary_path=$_DETECT_PREPARED_REPORT
    if [ "$status" -ne 0 ] || [ -z "$temporary_path" ] || [ ! -f "$temporary_path" ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _DETECT_PREPARED_REPORT=""
        _DETECT_PREPARED_REPORT_PREFIX=""
        _detect_print_error "보고서 임시 파일을 만들 수 없습니다: $directory"
        return 2
    fi

    _detect_render_report "$temporary_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _DETECT_PREPARED_REPORT=""
        _DETECT_PREPARED_REPORT_PREFIX=""
        _detect_print_error "감지 보고서를 기록할 수 없습니다: $report_path"
        return 2
    fi

    if [ -n "$existing_mode" ] && ! chmod "$existing_mode" "$temporary_path" 2>/dev/null; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _DETECT_PREPARED_REPORT=""
        _DETECT_PREPARED_REPORT_PREFIX=""
        _detect_print_error "기존 보고서 권한을 적용할 수 없습니다: $report_path"
        return 2
    fi

    return 0
}

write_detection_report()
{
    local report_path

    if [ "$#" -ne 1 ]; then
        _detect_print_error "write_detection_report에는 보고서 경로가 필요합니다."
        return 2
    fi

    report_path=$1
    _detect_prepare_report "$report_path" || return $?
    if ! mv -f "$_DETECT_PREPARED_REPORT" "$report_path" 2>/dev/null; then
        _profile_cleanup_temporary_file "$_DETECT_PREPARED_REPORT" "$_DETECT_PREPARED_REPORT_PREFIX"
        _DETECT_PREPARED_REPORT=""
        _DETECT_PREPARED_REPORT_PREFIX=""
        _detect_print_error "감지 보고서를 원자 교체할 수 없습니다: $report_path"
        return 2
    fi

    _DETECT_PREPARED_REPORT=""
    _DETECT_PREPARED_REPORT_PREFIX=""
    return 0
}

_detect_restore_profile_output()
{
    local restore_status=0

    if [ -n "$_DETECT_ACTIVE_PROFILE_TARGET" ]; then
        if [ "$_DETECT_ACTIVE_PROFILE_HAD_EXISTING" -eq 1 ]; then
            if [ "$_DETECT_ACTIVE_PROFILE_ORIGINAL_MOVED" -eq 1 ] || [ "$_DETECT_ACTIVE_PROFILE_COMMITTED" -eq 1 ]; then
                if [ -e "$_DETECT_ACTIVE_PROFILE_BACKUP" ] || [ -L "$_DETECT_ACTIVE_PROFILE_BACKUP" ]; then
                    if ! mv -f "$_DETECT_ACTIVE_PROFILE_BACKUP" "$_DETECT_ACTIVE_PROFILE_TARGET" 2>/dev/null; then
                        _detect_print_error "기존 프로필 자동 복구에 실패했습니다. 수동 복구 원본: $_DETECT_ACTIVE_PROFILE_BACKUP"
                        restore_status=4
                    fi
                else
                    _detect_print_error "기존 프로필 자동 복구에 실패했습니다. 수동 복구 원본을 찾을 수 없습니다: $_DETECT_ACTIVE_PROFILE_BACKUP"
                    restore_status=4
                fi
            fi
        elif [ "$_DETECT_ACTIVE_PROFILE_COMMITTED" -eq 1 ]; then
            rm -f "$_DETECT_ACTIVE_PROFILE_TARGET" 2>/dev/null
        fi
    fi

    if [ "$restore_status" -eq 0 ]; then
        _profile_cleanup_temporary_file "$_DETECT_ACTIVE_PROFILE_BACKUP" "$_DETECT_ACTIVE_PROFILE_BACKUP_PREFIX"
    fi
    _DETECT_ACTIVE_PROFILE_TARGET=""
    _DETECT_ACTIVE_PROFILE_BACKUP=""
    _DETECT_ACTIVE_PROFILE_BACKUP_PREFIX=""
    _DETECT_ACTIVE_PROFILE_HAD_EXISTING=0
    _DETECT_ACTIVE_PROFILE_ORIGINAL_MOVED=0
    _DETECT_ACTIVE_PROFILE_COMMITTED=0
    return "$restore_status"
}

detect_cleanup_active_outputs()
{
    local restore_status

    _detect_restore_profile_output
    restore_status=$?
    _profile_cleanup_temporary_file "$_DETECT_ACTIVE_PROFILE_SEED" "$_DETECT_ACTIVE_PROFILE_SEED_PREFIX"
    _profile_cleanup_temporary_file "$_DETECT_PREPARED_PROFILE" "$_DETECT_PREPARED_PROFILE_PREFIX"
    _profile_cleanup_temporary_file "$_DETECT_PREPARED_REPORT" "$_DETECT_PREPARED_REPORT_PREFIX"
    _detect_cleanup_code_cache
    _DETECT_ACTIVE_PROFILE_SEED=""
    _DETECT_ACTIVE_PROFILE_SEED_PREFIX=""
    _DETECT_PREPARED_PROFILE=""
    _DETECT_PREPARED_PROFILE_PREFIX=""
    _DETECT_PREPARED_REPORT=""
    _DETECT_PREPARED_REPORT_PREFIX=""
    return "$restore_status"
}

_detect_handle_signal()
{
    local signal_status=$1

    if [ "$_DETECT_DEFER_SIGNAL" -eq 1 ]; then
        if [ "$_DETECT_PENDING_SIGNAL_STATUS" -eq 0 ]; then
            _DETECT_PENDING_SIGNAL_STATUS=$signal_status
        fi
        return 0
    fi

    trap - HUP INT TERM
    detect_cleanup_active_outputs
    exit "$signal_status"
}

_detect_exit_if_signal_pending()
{
    local signal_status=$_DETECT_PENDING_SIGNAL_STATUS

    if [ "$signal_status" -eq 0 ]; then
        return 0
    fi

    _DETECT_PENDING_SIGNAL_STATUS=0
    _detect_handle_signal "$signal_status"
}

detect_install_signal_handlers()
{
    _DETECT_DEFER_SIGNAL=0
    _DETECT_PENDING_SIGNAL_STATUS=0
    trap '_detect_handle_signal 129' HUP
    trap '_detect_handle_signal 130' INT
    trap '_detect_handle_signal 143' TERM
}

_detect_commit_output_pair()
{
    local profile_path=$1
    local report_path=$2
    local directory
    local file_name
    local backup_path
    local backup_prefix
    local cleanup_status
    local move_status

    directory=${profile_path%/*}
    file_name=${profile_path##*/}
    if [ "$directory" = "$profile_path" ]; then
        directory=.
    fi

    _DETECT_ACTIVE_PROFILE_TARGET=$profile_path
    _DETECT_ACTIVE_PROFILE_HAD_EXISTING=0
    _DETECT_ACTIVE_PROFILE_ORIGINAL_MOVED=0
    _DETECT_ACTIVE_PROFILE_COMMITTED=0
    if [ -e "$profile_path" ] || [ -L "$profile_path" ]; then
        backup_prefix="$directory/.${file_name}.rollback."
        backup_path="${backup_prefix}${_DETECT_PREPARED_PROFILE##*.}"
        if [ -e "$backup_path" ] || [ -L "$backup_path" ]; then
            detect_cleanup_active_outputs
            _detect_print_error "프로필 롤백 경로가 이미 존재합니다: $backup_path"
            return 2
        fi
        _DETECT_ACTIVE_PROFILE_BACKUP=$backup_path
        _DETECT_ACTIVE_PROFILE_BACKUP_PREFIX=$backup_prefix
        _DETECT_ACTIVE_PROFILE_HAD_EXISTING=1

        _DETECT_DEFER_SIGNAL=1
        mv -f "$profile_path" "$backup_path" 2>/dev/null
        move_status=$?
        if [ "$move_status" -eq 0 ]; then
            _DETECT_ACTIVE_PROFILE_ORIGINAL_MOVED=1
        fi
        _DETECT_DEFER_SIGNAL=0
        _detect_exit_if_signal_pending
        if [ "$move_status" -ne 0 ]; then
            detect_cleanup_active_outputs
            _detect_print_error "기존 프로필을 롤백용으로 보존할 수 없습니다: $profile_path"
            return 2
        fi
    fi

    _DETECT_DEFER_SIGNAL=1
    mv -f "$_DETECT_PREPARED_PROFILE" "$profile_path" 2>/dev/null
    move_status=$?
    if [ "$move_status" -eq 0 ]; then
        _DETECT_ACTIVE_PROFILE_COMMITTED=1
        _DETECT_PREPARED_PROFILE=""
        _DETECT_PREPARED_PROFILE_PREFIX=""
    fi
    _DETECT_DEFER_SIGNAL=0
    _detect_exit_if_signal_pending
    if [ "$move_status" -ne 0 ]; then
        detect_cleanup_active_outputs
        cleanup_status=$?
        _detect_print_error "감지 프로필을 원자 교체할 수 없습니다: $profile_path"
        if [ "$cleanup_status" -ne 0 ]; then
            return "$cleanup_status"
        fi
        return 2
    fi

    _DETECT_DEFER_SIGNAL=1
    mv -f "$_DETECT_PREPARED_REPORT" "$report_path" 2>/dev/null
    move_status=$?
    if [ "$move_status" -eq 0 ]; then
        _DETECT_PREPARED_REPORT=""
        _DETECT_PREPARED_REPORT_PREFIX=""
        _profile_cleanup_temporary_file "$_DETECT_ACTIVE_PROFILE_BACKUP" "$_DETECT_ACTIVE_PROFILE_BACKUP_PREFIX"
        _DETECT_ACTIVE_PROFILE_TARGET=""
        _DETECT_ACTIVE_PROFILE_BACKUP=""
        _DETECT_ACTIVE_PROFILE_BACKUP_PREFIX=""
        _DETECT_ACTIVE_PROFILE_HAD_EXISTING=0
        _DETECT_ACTIVE_PROFILE_ORIGINAL_MOVED=0
        _DETECT_ACTIVE_PROFILE_COMMITTED=0
    fi
    _DETECT_DEFER_SIGNAL=0
    _detect_exit_if_signal_pending
    if [ "$move_status" -ne 0 ]; then
        detect_cleanup_active_outputs
        cleanup_status=$?
        _detect_print_error "감지 보고서를 원자 교체할 수 없습니다: $report_path"
        if [ "$cleanup_status" -ne 0 ]; then
            return "$cleanup_status"
        fi
        return 2
    fi

    return 0
}

_detect_analyze_project()
{
    local project_root=$1
    local signatures_path=$2

    _detect_unity_version_apply "$project_root" || return $?
    _DETECT_UNITY_VERSION=$_DETECT_RESULT
    _detect_source_roots_apply "$project_root" || return $?
    _DETECT_SOURCE_ROOTS=$_DETECT_RESULT
    _detect_test_roots_apply "$project_root" || return $?
    _DETECT_TEST_ROOTS=$_DETECT_RESULT
    _detect_render_pipeline_apply "$project_root" || return $?
    _DETECT_RENDER_PIPELINE=$_DETECT_RESULT
    _detect_dependency_injection_apply "$project_root" || return $?
    _DETECT_DEPENDENCY_INJECTION=$_DETECT_RESULT
    _detect_async_backend_apply "$project_root" || return $?
    _DETECT_ASYNC_BACKEND=$_DETECT_RESULT
    _detect_tween_backend_apply "$project_root" || return $?
    _DETECT_TWEEN_BACKEND=$_DETECT_RESULT
    _detect_target_platforms_apply "$project_root" || return $?
    _DETECT_TARGET_PLATFORMS=$_DETECT_RESULT
    _detect_architecture_apply "$project_root" "$signatures_path" || return $?
    _DETECT_ARCHITECTURE=$_DETECT_RESULT
    _detect_optimization_states_apply "$_DETECT_UNITY_VERSION" "$_DETECT_RENDER_PIPELINE" || return $?
    return 0
}

# [기능]: 전체 감지 API를 순서대로 실행하고 pending 프로필과 보고서를 생성합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 읽기 검증 후에만 출력하며 선택적으로 기존 프로필 비교를 포함합니다.
_detect_project_apply()
{
    local requested_root
    local profile_path
    local report_path
    local schema_path
    local signatures_path
    local project_root
    local status

    if [ "$#" -lt 5 ] || [ "$#" -gt 6 ]; then
        _detect_print_error "detect_project에는 프로젝트, 프로필, 보고서, 스키마, 시그니처 경로가 필요합니다."
        return 2
    fi

    requested_root=$1
    profile_path=$2
    report_path=$3
    schema_path=$4
    signatures_path=$5
    _DETECT_COMPARISON_PROFILE=${6:-}
    _DETECT_SANITIZER_INVOCATIONS=0
    _DETECT_CODE_LIST_COLLECTIONS=0

    project_root=$(find_unity_project_root "$requested_root")
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    _detect_validate_project_inputs "$project_root" "$schema_path" "$signatures_path" || return $?

    _DETECT_PROJECT_ROOT=$project_root
    _DETECT_PROJECT_NAME=${project_root##*/}

    _detect_prepare_code_cache "$project_root" || return $?
    _detect_analyze_project "$project_root" "$signatures_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        _detect_cleanup_code_cache
        return "$status"
    fi

    _DETECT_PROFILE_OUTPUT=$profile_path
    _PROFILE_SCHEMA_PATH=$schema_path
    _detect_prepare_profile "$profile_path" "$schema_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        _detect_cleanup_code_cache
        return "$status"
    fi
    _detect_prepare_report "$report_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        _profile_cleanup_temporary_file "$_DETECT_PREPARED_PROFILE" "$_DETECT_PREPARED_PROFILE_PREFIX"
        _DETECT_PREPARED_PROFILE=""
        _DETECT_PREPARED_PROFILE_PREFIX=""
        _detect_cleanup_code_cache
        return "$status"
    fi
    _detect_commit_output_pair "$profile_path" "$report_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi
    _detect_cleanup_code_cache

    printf '%s\n' "[감지] pending 프로필을 생성했습니다: $profile_path"
    printf '%s\n' "[감지] 감지 보고서를 생성했습니다: $report_path"
    return 0
}

detect_project()
{
    local status

    _DETECT_MANIFEST_ROOT=""
    _DETECT_MANIFEST_DEPENDENCY_KEYS=""
    _DETECT_PACKAGE_EVIDENCE=""
    _detect_project_apply "$@"
    status=$?
    _DETECT_MANIFEST_ROOT=""
    _DETECT_MANIFEST_DEPENDENCY_KEYS=""
    _DETECT_PACKAGE_EVIDENCE=""
    return "$status"
}

#!/bin/bash

# ==============================================================================
# [기능]: Unity 하네스 프로필에 따라 프로젝트 C# 코드를 읽기 전용으로 검사합니다.
# [작성자]: 윤승종
# ==============================================================================

_LINT_PROJECT_ROOT=""
_LINT_TEST_SOURCE_CACHED_PATH=""
_LINT_TEST_SOURCE_CACHED_RESULT=1
_LINT_CONFIRMATION_STATUS=""
_LINT_ARCHITECTURE=""
_LINT_DEPENDENCY_INJECTION=""
_LINT_ASYNC_BACKEND=""
_LINT_TWEEN_BACKEND=""
_LINT_PRIVATE_FIELD_PREFIX=""
_LINT_XML_DOCUMENTATION_POLICY=""
_LINT_SOURCE_ROOTS=""
_LINT_EXCLUDE_ROOTS=""
_LINT_FILES=""
_LINT_CANDIDATES=""
_LINT_DUMP_CODE=0
_LINT_ERROR_COUNT=0
_LINT_WARNING_COUNT=0
_LINT_CARRIAGE_RETURN=$(printf '\r')
_LINT_LINE_FEED='
'

_lint_list_contains()
{
    local list=$1
    local expected=$2
    local item

    while IFS= read -r item || [ -n "$item" ]; do
        if [ "$item" = "$expected" ]; then
            return 0
        fi
    done <<LINT_LIST_EOF
$list
LINT_LIST_EOF

    return 1
}

_lint_append_line()
{
    local list=$1
    local value=$2

    if [ -z "$list" ]; then
        _LINT_APPEND_RESULT=$value
    else
        _LINT_APPEND_RESULT="${list}
$value"
    fi
}

_lint_relative_path()
{
    local absolute_path=$1

    # Sets _LINT_RELATIVE_RESULT; called per file, so no command substitution (fork).
    case "$absolute_path" in
        "$_LINT_PROJECT_ROOT"/*)
            _LINT_RELATIVE_RESULT=${absolute_path#"$_LINT_PROJECT_ROOT"/}
            ;;
        "$_LINT_PROJECT_ROOT")
            _LINT_RELATIVE_RESULT='.'
            ;;
        *)
            _LINT_RELATIVE_RESULT=$absolute_path
            ;;
    esac
}

_lint_lexical_normalize_absolute()
{
    local remaining
    local component
    local normalized

    case "$1" in
        /*)
            remaining=${1#/}
            ;;
        *)
            return 1
            ;;
    esac
    normalized=""
    while :; do
        case "$remaining" in
            */*)
                component=${remaining%%/*}
                remaining=${remaining#*/}
                ;;
            *)
                component=$remaining
                remaining=""
                ;;
        esac

        case "$component" in
            ""|.)
                ;;
            ..)
                if [ -z "$normalized" ]; then
                    return 1
                fi
                case "$normalized" in
                    */*)
                        normalized=${normalized%/*}
                        ;;
                    *)
                        normalized=""
                        ;;
                esac
                ;;
            *)
                if [ -z "$normalized" ]; then
                    normalized=$component
                else
                    normalized="$normalized/$component"
                fi
                ;;
        esac

        if [ -z "$remaining" ]; then
            break
        fi
    done

    if [ -z "$normalized" ]; then
        _LINT_LEXICAL_ABSOLUTE=/
    else
        _LINT_LEXICAL_ABSOLUTE="/$normalized"
    fi
}

_lint_physicalize_absolute()
{
    local probe=$1
    local suffix=""
    local component
    local physical_path

    while [ ! -d "$probe" ]; do
        if [ "$probe" = "/" ]; then
            return 1
        fi
        component=${probe##*/}
        if [ -z "$suffix" ]; then
            suffix=$component
        else
            suffix="$component/$suffix"
        fi
        probe=${probe%/*}
        if [ -z "$probe" ]; then
            probe=/
        fi
    done

    physical_path=$(cd -P "$probe" 2>/dev/null && pwd -P)
    if [ -z "$physical_path" ]; then
        return 1
    fi
    if [ -n "$suffix" ]; then
        if [ "$physical_path" = "/" ]; then
            physical_path="/$suffix"
        else
            physical_path="$physical_path/$suffix"
        fi
    fi
    _LINT_PHYSICAL_ABSOLUTE=$physical_path
}

_lint_normalize_boundary()
{
    local boundary=$1
    local relative_boundary
    local remaining
    local component
    local normalized
    local target_path
    local physical_path

    case "$boundary" in
        /*)
            if ! _lint_lexical_normalize_absolute "$boundary"; then
                return 1
            fi
            target_path=$_LINT_LEXICAL_ABSOLUTE
            relative_boundary=""
            ;;
        *)
            relative_boundary=$boundary
            ;;
    esac

    if [ -n "$relative_boundary" ]; then
        remaining=$relative_boundary
        normalized=""
        while :; do
            case "$remaining" in
                */*)
                    component=${remaining%%/*}
                    remaining=${remaining#*/}
                    ;;
                *)
                    component=$remaining
                    remaining=""
                    ;;
            esac

            case "$component" in
                ""|.)
                    ;;
                ..)
                    if [ -z "$normalized" ]; then
                        return 1
                    fi
                    case "$normalized" in
                        */*)
                            normalized=${normalized%/*}
                            ;;
                        *)
                            normalized=""
                            ;;
                    esac
                    ;;
                *)
                    if [ -z "$normalized" ]; then
                        normalized=$component
                    else
                        normalized="$normalized/$component"
                    fi
                    ;;
            esac

            if [ -z "$remaining" ]; then
                break
            fi
        done

        if [ -z "$normalized" ]; then
            normalized=.
        fi
        target_path="$_LINT_PROJECT_ROOT/$normalized"
    fi

    if ! _lint_physicalize_absolute "$target_path"; then
        return 1
    fi
    physical_path=$_LINT_PHYSICAL_ABSOLUTE
    case "$physical_path" in
        "$_LINT_PROJECT_ROOT")
            normalized=.
            ;;
        "$_LINT_PROJECT_ROOT"/*)
            normalized=${physical_path#"$_LINT_PROJECT_ROOT"/}
            ;;
        *)
            return 1
            ;;
    esac

    _LINT_NORMALIZED_BOUNDARY=$normalized
}

_lint_prepare_excludes()
{
    local excludes=$_LINT_EXCLUDE_ROOTS
    local exclude_root
    local normalized_excludes=""

    while IFS= read -r exclude_root || [ -n "$exclude_root" ]; do
        if [ -z "$exclude_root" ]; then
            continue
        fi
        if ! _lint_normalize_boundary "$exclude_root"; then
            lint_emit "CONFIG001" "error" "$exclude_root" "0" "제외 루트가 프로젝트 경계 밖을 가리킵니다"
            return 1
        fi
        if _lint_list_contains "$normalized_excludes" "$_LINT_NORMALIZED_BOUNDARY"; then
            continue
        fi
        _lint_append_line "$normalized_excludes" "$_LINT_NORMALIZED_BOUNDARY"
        normalized_excludes=$_LINT_APPEND_RESULT
    done <<LINT_EXCLUDES_EOF
$excludes
LINT_EXCLUDES_EOF

    _LINT_EXCLUDE_ROOTS=$normalized_excludes
}

_lint_prepare_source_roots()
{
    local source_roots=$_LINT_SOURCE_ROOTS
    local source_root
    local normalized_roots=""

    while IFS= read -r source_root || [ -n "$source_root" ]; do
        if [ -z "$source_root" ]; then
            continue
        fi
        if ! _lint_normalize_boundary "$source_root"; then
            lint_emit "CONFIG001" "error" "$source_root" "0" "소스 루트가 Assets/_Game 경계 밖을 가리킵니다"
            return 1
        fi
        case "$_LINT_NORMALIZED_BOUNDARY" in
            Assets/_Game|Assets/_Game/*)
                ;;
            *)
                lint_emit "CONFIG001" "error" "$source_root" "0" "소스 루트는 Assets/_Game 또는 그 하위 경로여야 합니다"
                return 1
                ;;
        esac
        if _lint_list_contains "$normalized_roots" "$_LINT_NORMALIZED_BOUNDARY"; then
            continue
        fi
        _lint_append_line "$normalized_roots" "$_LINT_NORMALIZED_BOUNDARY"
        normalized_roots=$_LINT_APPEND_RESULT
    done <<LINT_SOURCE_ROOTS_EOF
$source_roots
LINT_SOURCE_ROOTS_EOF

    _LINT_SOURCE_ROOTS=$normalized_roots
}

_lint_is_excluded()
{
    local relative_path=$1
    local exclude_root

    while IFS= read -r exclude_root || [ -n "$exclude_root" ]; do
        if [ -z "$exclude_root" ]; then
            continue
        fi
        if [ "$exclude_root" = "." ]; then
            return 0
        fi
        case "$exclude_root" in
            ./*)
                exclude_root=${exclude_root#./}
                ;;
        esac
        exclude_root=${exclude_root%/}
        case "$relative_path" in
            "$exclude_root"|"$exclude_root"/*)
                return 0
                ;;
        esac
    done <<LINT_EXCLUDE_ROOTS_EOF
$_LINT_EXCLUDE_ROOTS
LINT_EXCLUDE_ROOTS_EOF

    return 1
}

_lint_collect_files()
{
    local file_pattern=${1:-'*.cs'}
    local source_root
    local source_path
    local source_physical
    local found_files
    local file_path
    local relative_path
    local status
    local files=()

    _LINT_FILES=""
    while IFS= read -r source_root || [ -n "$source_root" ]; do
        if [ -z "$source_root" ]; then
            continue
        fi
        case "$source_root" in
            /*)
                source_path=$source_root
                ;;
            *)
                source_path="$_LINT_PROJECT_ROOT/$source_root"
                ;;
        esac

        if [ ! -d "$source_path" ] || [ ! -r "$source_path" ]; then
            lint_emit "PATH001" "error" "$source_root" "0" "소스 루트를 찾거나 읽을 수 없습니다"
            continue
        fi

        source_physical=$(cd -P "$source_path" 2>/dev/null && pwd -P)
        case "$source_physical" in
            "$_LINT_PROJECT_ROOT"|"$_LINT_PROJECT_ROOT"/*)
                ;;
            *)
                lint_emit "PATH001" "error" "$source_root" "0" "소스 루트가 프로젝트 경계 밖을 가리킵니다"
                continue
                ;;
        esac

        found_files=$(find "$source_physical" -type f -name "$file_pattern" -print 2>/dev/null)
        status=$?
        if [ "$status" -ne 0 ]; then
            lint_emit "PATH001" "error" "$source_root" "0" "소스 파일 목록을 수집할 수 없습니다"
            return 4
        fi
        while IFS= read -r file_path || [ -n "$file_path" ]; do
            if [ -z "$file_path" ]; then
                continue
            fi
            _lint_relative_path "$file_path"
            relative_path=$_LINT_RELATIVE_RESULT
            if _lint_is_excluded "$relative_path"; then
                continue
            fi
            # Array append is O(1); growing a string through function arguments was O(n^2).
            files[${#files[@]}]=$file_path
        done <<LINT_FOUND_FILES_EOF
$found_files
LINT_FOUND_FILES_EOF
    done <<LINT_SOURCE_ROOTS_EOF
$_LINT_SOURCE_ROOTS
LINT_SOURCE_ROOTS_EOF
    if [ "${#files[@]}" -gt 0 ]; then
        local IFS='
'
        _LINT_FILES="${files[*]}"
    fi
}

lint_collect_scope_files()
{
    if [ "$#" -ne 1 ]; then
        lint_emit "CONFIG001" "error" "." "0" "lint_collect_scope_files에는 파일 패턴이 필요합니다"
        return 1
    fi
    case "$1" in
        '*.cs'|'*.asmdef')
            _lint_collect_files "$1"
            ;;
        *)
            lint_emit "CONFIG001" "error" "." "0" "허용되지 않은 파일 패턴입니다: $1"
            return 1
            ;;
    esac
}

_lint_scan_files()
{
    local project_root=$1

    shift

    LC_ALL=C awk \
        -v project_root="$project_root" \
        -v field_prefix="$_LINT_PRIVATE_FIELD_PREFIX" \
        -v documentation_policy="$_LINT_XML_DOCUMENTATION_POLICY" \
        -v dump_code="$_LINT_DUMP_CODE" '
        function emit(tag, line_number)
        {
            print tag "|" line_number "|" relative_path
        }

        function reset_file_state(    view_name)
        {
            in_block_comment = 0
            raw_quotes = 0
            in_verbatim_string = 0
            interpolated_string = 0
            interpolation_depth = 0
            interpolation_outer = 0
            in_string = 0
            in_character = 0
            serialized_attribute = 0
            for (view_name in serialized_views)
            {
                delete serialized_views[view_name]
            }
            is_view = relative_path ~ /(^|\/)Views?\// || relative_path ~ /View[.]cs$/
            is_domain = relative_path ~ /(^|\/)Domain\//
            brace_depth = 0
            in_update = 0
            waiting_update = 0
            pending_instance_line = 0
            pending_instance_readonly = 0
            in_static_property = 0
            static_property_line = 0
            static_property_depth = 0
            static_property_has_set = 0
            static_property_is_instance = 0
            xml_ready = 0
            in_register_instance = 0
            register_instance_line = 0
            register_instance_depth = 0
            register_instance_reported = 0
        }

        function quote_count(text, start,    count)
        {
            count = 0
            while (substr(text, start + count, 1) == "\"")
            {
                count++
            }
            return count
        }

        function sanitize(text,    output, position, character, next_character, count)
        {
            output = ""
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
                if (raw_quotes > 0)
                {
                    if (character == "\"")
                    {
                        count = quote_count(text, position)
                        if (count >= raw_quotes)
                        {
                            raw_quotes = 0
                        }
                        position += count
                    }
                    else
                    {
                        position++
                    }
                    continue
                }
                if (in_verbatim_string)
                {
                    if (interpolated_string && character == "{" && next_character != "{")
                    {
                        in_verbatim_string = 0
                        interpolation_depth = 1
                        interpolation_outer = 2
                        output = output " "
                        position++
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
                    if (interpolated_string && character == "{" && next_character != "{")
                    {
                        in_string = 0
                        interpolation_depth = 1
                        interpolation_outer = 1
                        output = output " "
                        position++
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
                if (interpolation_depth > 0 && character == "{")
                {
                    interpolation_depth++
                    output = output character
                    position++
                    continue
                }
                if (interpolation_depth > 0 && character == "}")
                {
                    interpolation_depth--
                    if (interpolation_depth == 0)
                    {
                        if (interpolation_outer == 2)
                        {
                            in_verbatim_string = 1
                        }
                        else
                        {
                            in_string = 1
                        }
                        interpolated_string = 1
                        interpolation_outer = 0
                        output = output " "
                    }
                    else
                    {
                        output = output character
                    }
                    position++
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
                if (character == "/" && next_character == "/")
                {
                    break
                }
                if (character == "/" && next_character == "*")
                {
                    output = output " "
                    in_block_comment = 1
                    position += 2
                    continue
                }
                if (character == "@" && next_character == "\"")
                {
                    output = output " "
                    in_verbatim_string = 1
                    position += 2
                    continue
                }
                if (character == "$" && next_character == "@" && substr(text, position + 2, 1) == "\"")
                {
                    output = output " "
                    in_verbatim_string = 1
                    interpolated_string = 1
                    position += 3
                    continue
                }
                if (character == "@" && next_character == "$" && substr(text, position + 2, 1) == "\"")
                {
                    output = output " "
                    in_verbatim_string = 1
                    interpolated_string = 1
                    position += 3
                    continue
                }
                if (character == "$" && next_character == "\"")
                {
                    count = quote_count(text, position + 1)
                    output = output " "
                    if (count >= 3)
                    {
                        raw_quotes = count
                    }
                    else
                    {
                        in_string = 1
                        interpolated_string = 1
                    }
                    position += count + 1
                    continue
                }
                if (character == "\"")
                {
                    count = quote_count(text, position)
                    output = output " "
                    if (count >= 3)
                    {
                        raw_quotes = count
                    }
                    else
                    {
                        in_string = 1
                        interpolated_string = 0
                    }
                    position += count
                    continue
                }
                if (character == "\047")
                {
                    output = output " "
                    in_character = 1
                    position++
                    continue
                }

                output = output character
                position++
            }
            return output
        }

        function character_count(text, expected,    position, count)
        {
            count = 0
            for (position = 1; position <= length(text); position++)
            {
                if (substr(text, position, 1) == expected)
                {
                    count++
                }
            }
            return count
        }

        function is_method_declaration(code)
        {
            if (code ~ /^[[:space:]]*(return|throw|await|yield|else|case|new)([^A-Za-z0-9_]|$)/ \
                && code !~ /^[[:space:]]*new[[:space:]]+((public|private|protected|internal|static|virtual|override|abstract|sealed|async|extern|unsafe|partial)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[(]/)
            {
                return 0
            }
            if (code ~ /\[[[:space:]]*new([^A-Za-z0-9_]|$)/)
            {
                return 0
            }
            return code ~ /^[[:space:]]*((public|private|protected|internal|static|virtual|override|abstract|sealed|async|extern|new|unsafe|partial)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*(<[A-Za-z0-9_<>,.\[\]?[:space:]]+>)?[[:space:]]*[(]/
        }

        function is_update_declaration(code)
        {
            return code ~ /^[[:space:]]*((public|private|protected|internal|static|virtual|override|abstract|sealed|async|extern|new|unsafe|partial)[[:space:]]+)*void[[:space:]]+(Update|LateUpdate|FixedUpdate)[[:space:]]*[(][^)]*[)]/
        }

        function has_bad_private_field(code,    text, token_count, tokens, index_value, name)
        {
            if (is_method_declaration(code))
            {
                return 0
            }
            text = code
            gsub(/[[][^]]*[]]/, " ", text)
            gsub(/[=;(){}]/, " & ", text)
            token_count = split(text, tokens, /[[:space:]]+/)
            for (index_value = 1; index_value <= token_count; index_value++)
            {
                if (tokens[index_value] == "private" || tokens[index_value] == "protected")
                {
                    index_value++
                    while (tokens[index_value] == "static" || tokens[index_value] == "readonly" || tokens[index_value] == "volatile" || tokens[index_value] == "new")
                    {
                        index_value++
                    }
                    if (tokens[index_value] == "const")
                    {
                        return 0
                    }
                    index_value++
                    name = tokens[index_value]
                    if (name !~ /^[A-Za-z_][A-Za-z0-9_]*$/)
                    {
                        return 0
                    }
                    if (code ~ (name "[[:space:]]*[(]"))
                    {
                        return 0
                    }
                    if (code ~ (name "[[:space:]]*([{]|=>)"))
                    {
                        return 0
                    }
                    if (code !~ (name "[[:space:]]*(=|;)"))
                    {
                        return 0
                    }
                    return field_prefix != "" && substr(name, 1, length(field_prefix)) != field_prefix
                }
            }
            return 0
        }

        function remember_serialized_view(code,    text, token_count, tokens, index_value, name)
        {
            if (code ~ /\[SerializeField\]/)
            {
                serialized_attribute = 1
            }
            if (!serialized_attribute || code !~ /View[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(=|;)/)
            {
                return
            }
            text = code
            sub(/=.*/, "", text)
            gsub(/;/, " ", text)
            token_count = split(text, tokens, /[[:space:]]+/)
            for (index_value = token_count; index_value >= 1; index_value--)
            {
                name = tokens[index_value]
                if (name ~ /^[A-Za-z_][A-Za-z0-9_]*$/)
                {
                    serialized_views[name] = 1
                    break
                }
            }
            serialized_attribute = 0
        }

        FNR == 1 {
            if (seen_files[FILENAME])
            {
                skip_file = 1
            }
            else
            {
                seen_files[FILENAME] = 1
                skip_file = 0
                relative_path = FILENAME
                if (index(relative_path, project_root "/") == 1)
                {
                    relative_path = substr(relative_path, length(project_root) + 2)
                }
                reset_file_state()
            }
        }

        skip_file {
            next
        }

        {
            raw = $0
            if (raw ~ /^[[:space:]]*\/\/\//)
            {
                xml_ready = 1
                next
            }

            code = sanitize(raw)
            if (code ~ /^[[:space:]]*$/)
            {
                next
            }
            if (dump_code)
            {
                print FNR "|" code
                next
            }

            opens = character_count(code, "{")
            closes = character_count(code, "}")
            method_declaration = is_method_declaration(code)
            if (documentation_policy != "disabled" && method_declaration)
            {
                requires_documentation = documentation_policy == "all_methods" || code ~ /^[[:space:]]*(public|protected)[[:space:]]/
                if (requires_documentation && !xml_ready)
                {
                    emit("DOC", FNR)
                }
            }

            if (in_static_property)
            {
                if (code ~ /(^|[^A-Za-z0-9_])set[[:space:]]*[;{=]/)
                {
                    static_property_has_set = 1
                }
                static_property_depth += opens - closes
                if (static_property_depth <= 0)
                {
                    if (static_property_has_set)
                    {
                        emit("SOLIDMUT", static_property_line)
                    }
                    else if (static_property_is_instance)
                    {
                        emit("SOLID", static_property_line)
                    }
                    in_static_property = 0
                    static_property_has_set = 0
                    static_property_is_instance = 0
                }
            }
            else
            {
                if (pending_instance_line > 0)
                {
                    if (code ~ /^[[:space:]]*[{]/)
                    {
                        in_static_property = 1
                        static_property_line = pending_instance_line
                        static_property_depth = opens - closes
                        static_property_is_instance = 1
                        static_property_has_set = code ~ /(^|[^A-Za-z0-9_])set[[:space:]]*[;{=]/
                        if (static_property_depth <= 0)
                        {
                            if (static_property_has_set)
                            {
                                emit("SOLIDMUT", static_property_line)
                            }
                            else
                            {
                                emit("SOLID", static_property_line)
                            }
                            in_static_property = 0
                            static_property_has_set = 0
                            static_property_is_instance = 0
                        }
                    }
                    else if (code ~ /^[[:space:]]*=>/)
                    {
                        emit("SOLID", pending_instance_line)
                    }
                    else if (code ~ /^[[:space:]]*=/)
                    {
                        if (pending_instance_readonly)
                        {
                            emit("SOLID", pending_instance_line)
                        }
                        else
                        {
                            emit("SOLIDMUT", pending_instance_line)
                        }
                    }
                    pending_instance_line = 0
                    pending_instance_readonly = 0
                }
                is_static_type_declaration = code ~ /(^|[^A-Za-z0-9_])public[[:space:]]+static[[:space:]]+(partial[[:space:]]+)?(class|struct|enum|interface)([^A-Za-z0-9_]|$)/
                if (code ~ /(^|[^A-Za-z0-9_])public[[:space:]]+static[[:space:]]+/)
                {
                    if (code !~ /(^|[^A-Za-z0-9_])(readonly|const|event|operator)([^A-Za-z0-9_]|$)/ \
                        && code ~ /(^|[^A-Za-z0-9_])public[[:space:]]+static[[:space:]]+((volatile|new)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*(;|=([^>]|$))/)
                    {
                        emit("SOLIDMUT", FNR)
                    }
                    else if (!is_static_type_declaration && code !~ /\(/ \
                        && code ~ /(^|[^A-Za-z0-9_])public[[:space:]]+static[[:space:]]+((readonly|volatile|new)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[{]/)
                    {
                        in_static_property = 1
                        static_property_line = FNR
                        static_property_depth = opens - closes
                        static_property_is_instance = code ~ /(^|[^A-Za-z0-9_])Instance[[:space:]]*[{]/
                        static_property_has_set = code ~ /(^|[^A-Za-z0-9_])set[[:space:]]*[;{=]/
                        if (static_property_depth <= 0)
                        {
                            if (static_property_has_set)
                            {
                                emit("SOLIDMUT", static_property_line)
                            }
                            else if (static_property_is_instance)
                            {
                                emit("SOLID", static_property_line)
                            }
                            in_static_property = 0
                            static_property_has_set = 0
                            static_property_is_instance = 0
                        }
                    }
                    else if (code ~ /(^|[^A-Za-z0-9_])public[[:space:]]+static[[:space:]]+((readonly|volatile|new)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*[[:space:]]+Instance[[:space:]]*(;|=>|=([^>]|$))/)
                    {
                        emit("SOLID", FNR)
                    }
                    else if (code ~ /(^|[^A-Za-z0-9_])public[[:space:]]+static[[:space:]]+((readonly|volatile|new)[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>,.\[\]?]*[[:space:]]+Instance[[:space:]]*$/)
                    {
                        pending_instance_line = FNR
                        pending_instance_readonly = code ~ /(^|[^A-Za-z0-9_])readonly([^A-Za-z0-9_]|$)/
                    }
                }
            }
            if (code ~ /(^|[^A-Za-z0-9_])(m_|button|text|image|slider|transform|gameObject)[A-Za-z0-9_]*[[:space:]]*[?][.?]/)
            {
                emit("UNITYNULL", FNR)
            }
            if (has_bad_private_field(code))
            {
                emit("STYLE", FNR)
            }

            active_update_line = in_update
            if (!in_update && !waiting_update && is_update_declaration(code))
            {
                update_base_depth = brace_depth
                if (code ~ /=>/)
                {
                    active_update_line = 1
                }
                else if (code !~ /;[[:space:]]*$/)
                {
                    waiting_update = 1
                }
            }
            if (waiting_update && opens > 0)
            {
                in_update = 1
                active_update_line = 1
                waiting_update = 0
            }
            if (active_update_line)
            {
                if (code ~ /[.](Where|Select|SelectMany|Distinct|OrderBy|OrderByDescending|ThenBy|GroupBy|ToList|ToArray|Any|All|First|FirstOrDefault|Single|SingleOrDefault|Count)[[:space:]]*[(]/ || code ~ /(^|[^A-Za-z0-9_])Enumerable[.]/)
                {
                    emit("PERF_LINQ", FNR)
                }
                if ((code ~ /(^|[^A-Za-z0-9_])new[[:space:]]+[A-Za-z_][A-Za-z0-9_.<>]*/ || code ~ /(^|[^A-Za-z0-9_])new[[:space:]]*[(]/) && code !~ /new[[:space:]]+(Vector2|Vector3|Vector4|Quaternion|Color|Color32|Rect|Bounds|Ray|Plane|Matrix4x4)[[:space:]]*[(]/)
                {
                    emit("PERF_NEW", FNR)
                }
                if (code ~ /(^|[^A-Za-z0-9_])(DOTween|DOVirtual)[[:space:]]*[.]|[.]DO[A-Z][A-Za-z0-9_]*[[:space:]]*[(]/)
                {
                    emit("DOTWEEN", FNR)
                }
            }

            if (is_view && (code ~ /^[[:space:]]*using[[:space:]]+[A-Za-z0-9_.]*Models[[:space:]]*;/ || (code ~ /(^|[^A-Za-z0-9_])[A-Za-z_][A-Za-z0-9_]*Model([^A-Za-z0-9_]|$)/ && code !~ /ViewModel/)))
            {
                emit("VIEW_MODEL", FNR)
            }
            lower_code = tolower(code)
            if (is_view && lower_code ~ /m_[a-z0-9_]*model[a-z0-9_]*[[:space:]]*[.][[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=/)
            {
                emit("MVC_MUTATION", FNR)
            }
            if (is_domain && code ~ /^[[:space:]]*using[[:space:]]+([A-Za-z0-9_.]+[.])?(UnityEngine|Presentation|Infrastructure|Views|ViewModels)([.;]|$)/)
            {
                emit("LAYER_DEP", FNR)
            }

            remember_serialized_view(code)
            register_segment = code
            if (!in_register_instance && match(code, /RegisterInstance[[:space:]]*[(]/))
            {
                in_register_instance = 1
                register_instance_line = FNR
                register_instance_depth = 0
                register_instance_reported = 0
                register_segment = substr(code, RSTART)
            }
            if (in_register_instance)
            {
                for (view_name in serialized_views)
                {
                    if (!register_instance_reported && register_segment ~ ("(^|[^A-Za-z0-9_])" view_name "([^A-Za-z0-9_]|$)"))
                    {
                        emit("VCONTAINER", register_instance_line)
                        register_instance_reported = 1
                    }
                }
                register_instance_depth += character_count(register_segment, "(") - character_count(register_segment, ")")
                if (register_instance_depth <= 0)
                {
                    in_register_instance = 0
                }
            }
            if (code ~ /(^|[^A-Za-z0-9_])(StartCoroutine|IEnumerator|Coroutine)([^A-Za-z0-9_]|$)|yield[[:space:]]+return/)
            {
                emit("COROUTINE", FNR)
            }

            brace_depth += opens - closes
            if (in_update && brace_depth <= update_base_depth)
            {
                in_update = 0
            }
            if (method_declaration || code !~ /^[[:space:]]*\[/)
            {
                xml_ready = 0
            }
        }
    ' "$@"
}

_lint_collect_candidates()
{
    local file_path
    local candidates
    local candidate
    local status
    local files=()

    _LINT_CANDIDATES=""
    while IFS= read -r file_path || [ -n "$file_path" ]; do
        if [ -z "$file_path" ]; then
            continue
        fi
        if [ ! -r "$file_path" ]; then
            _lint_relative_path "$file_path"
            lint_emit "PATH001" "error" "$_LINT_RELATIVE_RESULT" "0" "C# 파일을 읽을 수 없습니다"
            return 4
        fi
        files[${#files[@]}]=$file_path
    done <<LINT_FILES_EOF
$_LINT_FILES
LINT_FILES_EOF

    if [ "${#files[@]}" -eq 0 ]; then
        return 0
    fi
    candidates=$(_lint_scan_files "$_LINT_PROJECT_ROOT" "${files[@]}" 2>/dev/null)
    status=$?
    if [ "$status" -ne 0 ]; then
        lint_emit "CONFIG001" "error" "." "0" "C# 파일 분석기를 실행할 수 없습니다"
        return 4
    fi
    while IFS= read -r candidate || [ -n "$candidate" ]; do
        if [ -z "$candidate" ]; then
            continue
        fi
        _lint_append_line "$_LINT_CANDIDATES" "$candidate"
        _LINT_CANDIDATES=$_LINT_APPEND_RESULT
    done <<LINT_CANDIDATES_EOF
$candidates
LINT_CANDIDATES_EOF
}

# [기능]: 주석·문자열을 제거한 C# 코드 줄을 "줄번호|코드" 형식으로 출력합니다.
# 업무 규칙 등 추가 검사가 같은 sanitize 경로를 재사용하도록 제공합니다.
lint_sanitized_lines()
{
    local status

    _LINT_DUMP_CODE=1
    _lint_scan_files "$_LINT_PROJECT_ROOT" "$1"
    status=$?
    _LINT_DUMP_CODE=0
    return "$status"
}

_lint_candidate_parts()
{
    local record=$1
    local remainder

    _LINT_CANDIDATE_TAG=${record%%|*}
    remainder=${record#*|}
    _LINT_CANDIDATE_LINE=${remainder%%|*}
    _LINT_CANDIDATE_PATH=${remainder#*|}
}

# [기능]: Unity Test Framework가 IEnumerator를 강제하는 테스트 소스인지 판정합니다.
# 경로(Tests·Test 디렉터리) 또는 파일 내용의 테스트 마커로 판정하며, 결과를 파일 단위로 캐시합니다.
lint_is_test_source()
{
    local relative_path=$1
    local absolute_path

    case "$relative_path" in
        Tests/*|Test/*|*/Tests/*|*/Test/*)
            return 0
            ;;
    esac

    if [ "$relative_path" = "$_LINT_TEST_SOURCE_CACHED_PATH" ]; then
        return "$_LINT_TEST_SOURCE_CACHED_RESULT"
    fi
    _LINT_TEST_SOURCE_CACHED_PATH=$relative_path

    absolute_path="$_LINT_PROJECT_ROOT/$relative_path"
    if [ -r "$absolute_path" ] \
        && grep -Eq '\[UnityTest\]|using[[:space:]]+NUnit\.Framework|UNITY_INCLUDE_TESTS|UnityEngine\.TestRunner|UnityEditor\.TestRunner|nunit\.framework' "$absolute_path" 2>/dev/null; then
        _LINT_TEST_SOURCE_CACHED_RESULT=0
        return 0
    fi
    _LINT_TEST_SOURCE_CACHED_RESULT=1
    return 1
}

_lint_machine_escape()
{
    local value=$1

    value=${value//%/%25}
    value=${value//|/%7C}
    value=${value//"$_LINT_CARRIAGE_RETURN"/%0D}
    value=${value//"$_LINT_LINE_FEED"/%0A}
    _LINT_ESCAPED_VALUE=$value
}

# [기능]: 모든 린트 상태와 프로필 캐시를 초기화합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 범용 하네스 린트 상태 초기화를 구현합니다.
lint_reset()
{
    _LINT_PROJECT_ROOT=""
    _LINT_TEST_SOURCE_CACHED_PATH=""
    _LINT_TEST_SOURCE_CACHED_RESULT=1
    _LINT_CONFIRMATION_STATUS=""
    _LINT_ARCHITECTURE=""
    _LINT_DEPENDENCY_INJECTION=""
    _LINT_ASYNC_BACKEND=""
    _LINT_TWEEN_BACKEND=""
    _LINT_PRIVATE_FIELD_PREFIX=""
    _LINT_XML_DOCUMENTATION_POLICY=""
    _LINT_SOURCE_ROOTS=""
    _LINT_EXCLUDE_ROOTS=""
    _LINT_FILES=""
    _LINT_CANDIDATES=""
    _LINT_ERROR_COUNT=0
    _LINT_WARNING_COUNT=0
}

# [기능]: 정규화된 한 건의 린트 결과를 출력하고 심각도를 집계합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: pending 프로필 오류의 warning 하향을 적용합니다.
lint_emit()
{
    local rule_id=$1
    local severity=$2
    local relative_path=$3
    local line_number=$4
    local message=$5
    local rule_scope=${6:-core}
    local escaped_path
    local escaped_message

    if [ "$rule_scope" = "profile" ] && [ "$_LINT_CONFIRMATION_STATUS" = "pending" ] && [ "$severity" = "error" ]; then
        severity=warning
    fi

    _lint_machine_escape "$relative_path"
    escaped_path=$_LINT_ESCAPED_VALUE
    _lint_machine_escape "$message"
    escaped_message=$_LINT_ESCAPED_VALUE
    printf '%s|%s|%s|%s|%s\n' "$rule_id" "$severity" "$escaped_path" "$line_number" "$escaped_message"
    if [ "$severity" = "error" ]; then
        _LINT_ERROR_COUNT=$((_LINT_ERROR_COUNT + 1))
    else
        _LINT_WARNING_COUNT=$((_LINT_WARNING_COUNT + 1))
    fi
}

# [기능]: 프로필과 무관하게 적용되는 핵심, 성능, 안전성, 스타일 규칙을 실행합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: Core 규칙 라우팅을 구현합니다.
lint_core_rules()
{
    local record

    while IFS= read -r record || [ -n "$record" ]; do
        if [ -z "$record" ]; then
            continue
        fi
        _lint_candidate_parts "$record"
        case "$_LINT_CANDIDATE_TAG" in
            SOLID)
                lint_emit "SOLID001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "public static Instance 전역 접근이 의심됩니다. 불변 캐시 인스턴스면 무시할 수 있습니다"
                ;;
            SOLIDMUT)
                lint_emit "SOLID001" "error" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "변경 가능한 public static 전역 상태가 감지되었습니다"
                ;;
            PERF_LINQ)
                lint_emit "PERF001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "매 프레임 메서드에서 LINQ 사용이 감지되었습니다"
                ;;
            PERF_NEW)
                lint_emit "PERF002" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "매 프레임 메서드에서 참조 타입 할당이 의심됩니다"
                ;;
            UNITYNULL)
                lint_emit "UNITYNULL001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "Unity Object Fake Null 오용이 의심됩니다"
                ;;
            STYLE)
                lint_emit "STYLE001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "private 필드 접두사 규칙을 확인하십시오"
                ;;
            DOC)
                if ! lint_is_test_source "$_LINT_CANDIDATE_PATH"; then
                    lint_emit "DOC001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "프로필 XML 문서화 정책 위반이 의심됩니다"
                fi
                ;;
        esac
    done <<LINT_CORE_CANDIDATES_EOF
$_LINT_CANDIDATES
LINT_CORE_CANDIDATES_EOF
}

# [기능]: 확정된 아키텍처 프로필에 해당하는 규칙만 실행합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: MVVM, MVP, MVC, Layered Clean 라우팅을 구현합니다.
lint_architecture_rules()
{
    local record

    if [ "$_LINT_ARCHITECTURE" = "custom" ]; then
        return 0
    fi

    while IFS= read -r record || [ -n "$record" ]; do
        if [ -z "$record" ]; then
            continue
        fi
        _lint_candidate_parts "$record"
        case "$_LINT_ARCHITECTURE:$_LINT_CANDIDATE_TAG" in
            mvvm:VIEW_MODEL)
                lint_emit "MVVM001" "error" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "View에서 Model을 직접 참조하고 있습니다" "profile"
                ;;
            mvp:VIEW_MODEL)
                lint_emit "MVP001" "error" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "View에서 Model을 직접 참조하고 있습니다" "profile"
                ;;
            mvc:MVC_MUTATION)
                lint_emit "MVC001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "View에서 Model 상태를 직접 변경하는 코드가 의심됩니다" "profile"
                ;;
            layered_clean:LAYER_DEP)
                lint_emit "LAYER001" "error" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "Domain이 바깥 계층을 참조하고 있습니다" "profile"
                ;;
        esac
    done <<LINT_ARCHITECTURE_CANDIDATES_EOF
$_LINT_CANDIDATES
LINT_ARCHITECTURE_CANDIDATES_EOF
}

# [기능]: DI, 비동기, 트윈 프로필에 해당하는 기술 전용 규칙만 실행합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: unknown, none, custom 기술 프로필의 검사 생략을 구현합니다.
lint_technology_rules()
{
    local record

    while IFS= read -r record || [ -n "$record" ]; do
        if [ -z "$record" ]; then
            continue
        fi
        _lint_candidate_parts "$record"
        case "$_LINT_DEPENDENCY_INJECTION:$_LINT_CANDIDATE_TAG" in
            vcontainer:VCONTAINER)
                lint_emit "VCONTAINER001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "직렬화 View를 RegisterInstance로 등록한 코드가 의심됩니다" "profile"
                ;;
        esac
        case "$_LINT_ASYNC_BACKEND:$_LINT_CANDIDATE_TAG" in
            unitask:COROUTINE)
                if ! lint_is_test_source "$_LINT_CANDIDATE_PATH"; then
                    lint_emit "UNITASK001" "error" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "UniTask 프로젝트에서 Coroutine 사용이 감지되었습니다" "profile"
                fi
                ;;
        esac
        case "$_LINT_TWEEN_BACKEND:$_LINT_CANDIDATE_TAG" in
            dotween:DOTWEEN)
                lint_emit "DOTWEEN001" "warning" "$_LINT_CANDIDATE_PATH" "$_LINT_CANDIDATE_LINE" "Update 계열 메서드에서 Tween 생성이 감지되었습니다" "profile"
                ;;
        esac
    done <<LINT_TECHNOLOGY_CANDIDATES_EOF
$_LINT_CANDIDATES
LINT_TECHNOLOGY_CANDIDATES_EOF
}

# [기능]: 전체 프로필 검사를 실행하고 정규화된 결과를 출력합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: 프로필 검증, 소스 경계, 규칙 라우팅을 통합합니다.
lint_project()
{
    local requested_root
    local profile_path
    local schema_path
    local project_root
    local profile_excludes
    local default_excludes
    local status

    lint_reset
    if [ "$#" -ne 3 ]; then
        lint_emit "CONFIG001" "error" "." "0" "lint_project에는 프로젝트, 프로필, 스키마 경로가 필요합니다"
        return 1
    fi

    requested_root=$1
    profile_path=$2
    schema_path=$3
    if [ ! -d "$requested_root" ]; then
        lint_emit "PATH001" "error" "." "0" "프로젝트 루트를 찾을 수 없습니다"
        return 1
    fi
    project_root=$(cd -P "$requested_root" 2>/dev/null && pwd -P)
    if [ -z "$project_root" ]; then
        lint_emit "PATH001" "error" "." "0" "프로젝트 루트를 읽을 수 없습니다"
        return 1
    fi
    _LINT_PROJECT_ROOT=$project_root

    if ! profile_load "$profile_path" "$schema_path" >/dev/null 2>&1; then
        lint_emit "CONFIG001" "error" "$profile_path" "0" "프로필을 읽거나 검증할 수 없습니다"
        return 1
    fi

    _LINT_CONFIRMATION_STATUS=$(profile_get "confirmation_status")
    _LINT_ARCHITECTURE=$(profile_get "architecture")
    _LINT_DEPENDENCY_INJECTION=$(profile_get "dependency_injection")
    _LINT_ASYNC_BACKEND=$(profile_get "async_backend")
    _LINT_TWEEN_BACKEND=$(profile_get "tween_backend")
    _LINT_PRIVATE_FIELD_PREFIX=$(profile_get "private_field_prefix")
    _LINT_XML_DOCUMENTATION_POLICY=$(profile_get "xml_documentation_policy")
    _LINT_SOURCE_ROOTS=$(profile_get_all "source_root")
    profile_excludes=$(profile_get_all "exclude_root" 2>/dev/null || true)
    default_excludes=$(printf '%s\n' \
        'Library' \
        'Temp' \
        'Logs' \
        'obj' \
        'UserSettings' \
        'Packages' \
        '.git' \
        '.agents' \
        '.agents-backup' \
        'Assets/Plugins' \
        'Assets/ThirdParty')
    if [ -n "$profile_excludes" ]; then
        _LINT_EXCLUDE_ROOTS="${default_excludes}
$profile_excludes"
    else
        _LINT_EXCLUDE_ROOTS=$default_excludes
    fi

    if ! _lint_prepare_source_roots; then
        return 1
    fi
    if ! _lint_prepare_excludes; then
        return 1
    fi

    lint_collect_scope_files '*.cs'
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi
    _lint_collect_candidates
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi
    lint_core_rules
    lint_architecture_rules
    lint_technology_rules
    lint_exit_code
}

# [기능]: 누적된 error 유무를 프로세스 종료 코드로 변환합니다.
# [작성자]: 윤승종
# [수정 날짜]: 2026-07-16
# [마지막 수정 작성자]: 윤승종
# [수정 내용]: error가 하나라도 있으면 1을 반환합니다.
lint_exit_code()
{
    if [ "$_LINT_ERROR_COUNT" -gt 0 ]; then
        return 1
    fi
    return 0
}

lint_reset

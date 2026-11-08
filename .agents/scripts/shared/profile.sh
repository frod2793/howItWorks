#!/bin/bash

# ==============================================================================
# [기능]: Unity 하네스 프로젝트 프로필을 안전하게 읽고 검증하며 기록합니다.
# [작성자]: 윤승종
# ==============================================================================

_PROFILE_DATA=""
_PROFILE_SCHEMA_PATH=""
_PROFILE_UTF8_BOM=$(printf '\357\273\277')
_PROFILE_CARRIAGE_RETURN=$(printf '\r')

_PROFILE_SCHEMA_KEY=""
_PROFILE_SCHEMA_REQUIRED=""
_PROFILE_SCHEMA_CARDINALITY=""
_PROFILE_SCHEMA_TYPE=""
_PROFILE_SCHEMA_ALLOWED=""

_profile_print_error()
{
    printf '%s\n' "[프로필] $1" >&2
}

_profile_strip_line_ending()
{
    _PROFILE_LINE=$1

    case "$_PROFILE_LINE" in
        *"$_PROFILE_CARRIAGE_RETURN")
            _PROFILE_LINE=${_PROFILE_LINE%"$_PROFILE_CARRIAGE_RETURN"}
            ;;
    esac
}

_profile_is_ignored_line()
{
    local line=$1
    local trimmed=$1

    if [ -z "$line" ]; then
        return 0
    fi

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

    if [ -z "$trimmed" ]; then
        return 0
    fi

    case "$trimmed" in
        \#*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

_profile_list_contains()
{
    local list=$1
    local expected=$2
    local item

    while IFS= read -r item || [ -n "$item" ]; do
        if [ "$item" = "$expected" ]; then
            return 0
        fi
    done <<PROFILE_LIST_EOF
$list
PROFILE_LIST_EOF

    return 1
}

_profile_append_data()
{
    local key=$1
    local value=$2

    if [ -z "$_PROFILE_DATA" ]; then
        _PROFILE_DATA="$key=$value"
    else
        _PROFILE_DATA="${_PROFILE_DATA}
$key=$value"
    fi
}

_profile_restore_memory_state()
{
    _PROFILE_DATA=$1
    _PROFILE_SCHEMA_PATH=$2
    _PROFILE_SCHEMA_KEY=$3
    _PROFILE_SCHEMA_REQUIRED=$4
    _PROFILE_SCHEMA_CARDINALITY=$5
    _PROFILE_SCHEMA_TYPE=$6
    _PROFILE_SCHEMA_ALLOWED=$7
    if [ "$9" -eq 1 ]; then
        _PROFILE_LINE=$8
    else
        unset _PROFILE_LINE
    fi
}

_profile_run_transaction()
{
    local restore_on_success=$1
    local operation=$2
    local caller_data=$_PROFILE_DATA
    local caller_schema_path=$_PROFILE_SCHEMA_PATH
    local caller_schema_key=$_PROFILE_SCHEMA_KEY
    local caller_schema_required=$_PROFILE_SCHEMA_REQUIRED
    local caller_schema_cardinality=$_PROFILE_SCHEMA_CARDINALITY
    local caller_schema_type=$_PROFILE_SCHEMA_TYPE
    local caller_schema_allowed=$_PROFILE_SCHEMA_ALLOWED
    local caller_line=""
    local is_caller_line_set=0
    local status
    shift 2

    if [ "${_PROFILE_LINE+x}" = "x" ]; then
        caller_line=$_PROFILE_LINE
        is_caller_line_set=1
    fi

    "$operation" "$@"
    status=$?
    if [ "$status" -ne 0 ] || [ "$restore_on_success" -eq 1 ]; then
        _profile_restore_memory_state "$caller_data" "$caller_schema_path" "$caller_schema_key" "$caller_schema_required" "$caller_schema_cardinality" "$caller_schema_type" "$caller_schema_allowed" "$caller_line" "$is_caller_line_set"
    fi

    return "$status"
}

_profile_parse_schema_line()
{
    local remainder=$1

    case "$remainder" in
        *'|'*)
            _PROFILE_SCHEMA_KEY=${remainder%%|*}
            remainder=${remainder#*|}
            ;;
        *)
            return 3
            ;;
    esac

    case "$remainder" in
        *'|'*)
            _PROFILE_SCHEMA_REQUIRED=${remainder%%|*}
            remainder=${remainder#*|}
            ;;
        *)
            return 3
            ;;
    esac

    case "$remainder" in
        *'|'*)
            _PROFILE_SCHEMA_CARDINALITY=${remainder%%|*}
            remainder=${remainder#*|}
            ;;
        *)
            return 3
            ;;
    esac

    case "$remainder" in
        *'|'*)
            _PROFILE_SCHEMA_TYPE=${remainder%%|*}
            _PROFILE_SCHEMA_ALLOWED=${remainder#*|}
            ;;
        *)
            return 3
            ;;
    esac

    case "$_PROFILE_SCHEMA_ALLOWED" in
        *'|'*)
            return 3
            ;;
    esac

    return 0
}

_profile_enum_contains()
{
    local allowed=$1
    local actual=$2
    local candidate
    local is_last=0

    while :; do
        case "$allowed" in
            *,*)
                candidate=${allowed%%,*}
                allowed=${allowed#*,}
                ;;
            *)
                candidate=$allowed
                is_last=1
                ;;
        esac

        if [ "$candidate" = "$actual" ]; then
            return 0
        fi

        if [ "$is_last" -eq 1 ]; then
            return 1
        fi
    done
}

_profile_check_schema()
{
    local schema_path=$1
    local line
    local seen_keys=""
    local schema_key_count=0

    if [ ! -f "$schema_path" ] || [ ! -r "$schema_path" ]; then
        _profile_print_error "스키마 파일을 읽을 수 없습니다: $schema_path"
        return 2
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        _profile_strip_line_ending "$line"
        line=$_PROFILE_LINE

        if _profile_is_ignored_line "$line"; then
            continue
        fi

        if ! _profile_parse_schema_line "$line"; then
            _profile_print_error "스키마 행 형식이 올바르지 않습니다: $line"
            return 3
        fi

        schema_key_count=$((schema_key_count + 1))
        if [ "$schema_key_count" -eq 1 ]; then
            case "$_PROFILE_SCHEMA_KEY" in
                "$_PROFILE_UTF8_BOM"*)
                    _profile_print_error "스키마 첫 키에 UTF-8 BOM을 사용할 수 없습니다."
                    return 3
                    ;;
            esac
        fi

        if [ -z "$_PROFILE_SCHEMA_KEY" ]; then
            _profile_print_error "스키마 키가 비어 있습니다."
            return 3
        fi

        if _profile_list_contains "$seen_keys" "$_PROFILE_SCHEMA_KEY"; then
            _profile_print_error "스키마 키가 중복되었습니다: $_PROFILE_SCHEMA_KEY"
            return 3
        fi

        case "$_PROFILE_SCHEMA_REQUIRED" in
            required|optional)
                ;;
            *)
                _profile_print_error "스키마 필수 여부가 올바르지 않습니다: $_PROFILE_SCHEMA_KEY"
                return 3
                ;;
        esac

        case "$_PROFILE_SCHEMA_CARDINALITY" in
            single|multiple)
                ;;
            *)
                _profile_print_error "스키마 반복 규칙이 올바르지 않습니다: $_PROFILE_SCHEMA_KEY"
                return 3
                ;;
        esac

        case "$_PROFILE_SCHEMA_TYPE" in
            enum)
                if [ -z "$_PROFILE_SCHEMA_ALLOWED" ]; then
                    _profile_print_error "열거형 허용값이 비어 있습니다: $_PROFILE_SCHEMA_KEY"
                    return 3
                fi
                ;;
            text|path)
                ;;
            *)
                _profile_print_error "스키마 값 형식이 올바르지 않습니다: $_PROFILE_SCHEMA_KEY"
                return 3
                ;;
        esac

        if [ -z "$seen_keys" ]; then
            seen_keys=$_PROFILE_SCHEMA_KEY
        else
            seen_keys="${seen_keys}
$_PROFILE_SCHEMA_KEY"
        fi
    done < "$schema_path"

    if [ "$schema_key_count" -eq 0 ]; then
        _profile_print_error "스키마에 정의된 키가 없습니다."
        return 3
    fi

    return 0
}

_profile_find_schema_key()
{
    local expected_key=$1
    local schema_path=$2
    local line

    while IFS= read -r line || [ -n "$line" ]; do
        _profile_strip_line_ending "$line"
        line=$_PROFILE_LINE

        if _profile_is_ignored_line "$line"; then
            continue
        fi

        if ! _profile_parse_schema_line "$line"; then
            return 3
        fi

        if [ "$_PROFILE_SCHEMA_KEY" = "$expected_key" ]; then
            return 0
        fi
    done < "$schema_path"

    return 1
}

profile_reset()
{
    _PROFILE_DATA=""
    _PROFILE_SCHEMA_PATH=""
}

_profile_load_apply()
{
    local profile_path
    local schema_path
    local line
    local key
    local value
    local profile_key_count=0
    local status

    if [ "$#" -ne 2 ]; then
        _profile_print_error "profile_load에는 프로필 경로와 스키마 경로가 필요합니다."
        return 2
    fi

    profile_path=$1
    schema_path=$2
    profile_reset

    _profile_check_schema "$schema_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    if [ ! -f "$profile_path" ] || [ ! -r "$profile_path" ]; then
        _profile_print_error "프로필 파일을 읽을 수 없습니다: $profile_path"
        return 2
    fi

    while IFS= read -r line || [ -n "$line" ]; do
        _profile_strip_line_ending "$line"
        line=$_PROFILE_LINE

        if _profile_is_ignored_line "$line"; then
            continue
        fi

        case "$line" in
            *=*)
                key=${line%%=*}
                value=${line#*=}
                ;;
            *)
                _profile_print_error "프로필 행에 등호가 없습니다: $line"
                return 3
                ;;
        esac

        profile_key_count=$((profile_key_count + 1))
        if [ "$profile_key_count" -eq 1 ]; then
            case "$key" in
                "$_PROFILE_UTF8_BOM"*)
                    _profile_print_error "프로필 첫 키에 UTF-8 BOM을 사용할 수 없습니다."
                    return 3
                    ;;
            esac
        fi

        if [ -z "$key" ]; then
            _profile_print_error "프로필 키가 비어 있습니다."
            return 3
        fi

        _profile_append_data "$key" "$value"
    done < "$profile_path"

    profile_validate "$schema_path"
}

profile_load()
{
    _profile_run_transaction 0 _profile_load_apply "$@"
}

profile_validate()
{
    local schema_path
    local entry
    local key
    local value
    local seen_keys=""
    local seen_single_keys=""
    local line
    local status

    if [ "$#" -ne 1 ]; then
        _profile_print_error "profile_validate에는 스키마 경로가 필요합니다."
        return 2
    fi

    schema_path=$1
    _profile_check_schema "$schema_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    while IFS= read -r entry || [ -n "$entry" ]; do
        if [ -z "$entry" ]; then
            continue
        fi

        key=${entry%%=*}
        value=${entry#*=}

        _profile_find_schema_key "$key" "$schema_path"
        status=$?
        if [ "$status" -eq 1 ]; then
            _profile_print_error "스키마에 없는 키입니다: $key"
            return 3
        fi
        if [ "$status" -ne 0 ]; then
            _profile_print_error "스키마 키를 확인할 수 없습니다: $key"
            return "$status"
        fi

        if [ "$_PROFILE_SCHEMA_CARDINALITY" = "single" ]; then
            if _profile_list_contains "$seen_single_keys" "$key"; then
                _profile_print_error "한 번만 사용할 수 있는 키가 중복되었습니다: $key"
                return 3
            fi

            if [ -z "$seen_single_keys" ]; then
                seen_single_keys=$key
            else
                seen_single_keys="${seen_single_keys}
$key"
            fi
        fi

        if [ "$_PROFILE_SCHEMA_TYPE" = "enum" ]; then
            if ! _profile_enum_contains "$_PROFILE_SCHEMA_ALLOWED" "$value"; then
                _profile_print_error "허용되지 않은 값입니다: $key=$value"
                return 3
            fi
        fi

        if ! _profile_list_contains "$seen_keys" "$key"; then
            if [ -z "$seen_keys" ]; then
                seen_keys=$key
            else
                seen_keys="${seen_keys}
$key"
            fi
        fi
    done <<PROFILE_DATA_EOF
$_PROFILE_DATA
PROFILE_DATA_EOF

    while IFS= read -r line || [ -n "$line" ]; do
        _profile_strip_line_ending "$line"
        line=$_PROFILE_LINE

        if _profile_is_ignored_line "$line"; then
            continue
        fi

        if ! _profile_parse_schema_line "$line"; then
            _profile_print_error "스키마 행 형식이 올바르지 않습니다: $line"
            return 3
        fi

        if [ "$_PROFILE_SCHEMA_REQUIRED" = "required" ]; then
            if ! _profile_list_contains "$seen_keys" "$_PROFILE_SCHEMA_KEY"; then
                _profile_print_error "필수 키가 누락되었습니다: $_PROFILE_SCHEMA_KEY"
                return 3
            fi
        fi
    done < "$schema_path"

    _PROFILE_SCHEMA_PATH=$schema_path
    return 0
}

profile_get()
{
    local expected_key
    local entry
    local key

    if [ "$#" -ne 1 ]; then
        _profile_print_error "profile_get에는 조회할 키가 필요합니다."
        return 2
    fi

    expected_key=$1
    while IFS= read -r entry || [ -n "$entry" ]; do
        if [ -z "$entry" ]; then
            continue
        fi

        key=${entry%%=*}
        if [ "$key" = "$expected_key" ]; then
            printf '%s\n' "${entry#*=}"
            return 0
        fi
    done <<PROFILE_DATA_EOF
$_PROFILE_DATA
PROFILE_DATA_EOF

    return 1
}

profile_get_all()
{
    local expected_key
    local entry
    local key
    local found=0

    if [ "$#" -ne 1 ]; then
        _profile_print_error "profile_get_all에는 조회할 키가 필요합니다."
        return 2
    fi

    expected_key=$1
    while IFS= read -r entry || [ -n "$entry" ]; do
        if [ -z "$entry" ]; then
            continue
        fi

        key=${entry%%=*}
        if [ "$key" = "$expected_key" ]; then
            printf '%s\n' "${entry#*=}"
            found=1
        fi
    done <<PROFILE_DATA_EOF
$_PROFILE_DATA
PROFILE_DATA_EOF

    if [ "$found" -eq 0 ]; then
        return 1
    fi

    return 0
}

profile_set_single()
{
    local expected_key
    local replacement_value
    local old_data
    local entry
    local key
    local value
    local matching_count=0
    local status

    if [ "$#" -ne 2 ]; then
        _profile_print_error "profile_set_single에는 키와 값이 필요합니다."
        return 2
    fi

    expected_key=$1
    replacement_value=$2

    case "$replacement_value" in
        *"$_PROFILE_CARRIAGE_RETURN"*|*'
'*)
            _profile_print_error "프로필 값에는 줄바꿈을 사용할 수 없습니다: $expected_key"
            return 3
            ;;
    esac

    if [ -z "$_PROFILE_SCHEMA_PATH" ]; then
        _profile_print_error "먼저 프로필을 스키마로 검증해야 합니다."
        return 2
    fi

    _profile_check_schema "$_PROFILE_SCHEMA_PATH"
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    _profile_find_schema_key "$expected_key" "$_PROFILE_SCHEMA_PATH"
    status=$?
    if [ "$status" -eq 1 ]; then
        _profile_print_error "스키마에 없는 키는 교체할 수 없습니다: $expected_key"
        return 3
    fi
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    if [ "$_PROFILE_SCHEMA_CARDINALITY" != "single" ]; then
        _profile_print_error "반복 키는 profile_set_single로 교체할 수 없습니다: $expected_key"
        return 3
    fi

    if [ "$_PROFILE_SCHEMA_TYPE" = "enum" ]; then
        if ! _profile_enum_contains "$_PROFILE_SCHEMA_ALLOWED" "$replacement_value"; then
            _profile_print_error "허용되지 않은 값입니다: $expected_key=$replacement_value"
            return 3
        fi
    fi

    while IFS= read -r entry || [ -n "$entry" ]; do
        if [ -z "$entry" ]; then
            continue
        fi

        key=${entry%%=*}
        if [ "$key" = "$expected_key" ]; then
            matching_count=$((matching_count + 1))
        fi
    done <<PROFILE_DATA_EOF
$_PROFILE_DATA
PROFILE_DATA_EOF

    if [ "$matching_count" -ne 1 ]; then
        _profile_print_error "교체할 단일 키가 정확히 한 개 존재해야 합니다: $expected_key"
        return 3
    fi

    old_data=$_PROFILE_DATA
    _PROFILE_DATA=""
    while IFS= read -r entry || [ -n "$entry" ]; do
        if [ -z "$entry" ]; then
            continue
        fi

        key=${entry%%=*}
        value=${entry#*=}
        if [ "$key" = "$expected_key" ]; then
            _profile_append_data "$key" "$replacement_value"
        else
            _profile_append_data "$key" "$value"
        fi
    done <<PROFILE_DATA_EOF
$old_data
PROFILE_DATA_EOF

    profile_validate "$_PROFILE_SCHEMA_PATH"
    status=$?
    if [ "$status" -ne 0 ]; then
        _PROFILE_DATA=$old_data
        return "$status"
    fi

    return 0
}

_profile_cleanup_temporary_file()
{
    local temporary_path=$1
    local temporary_prefix=$2

    if [ -z "$temporary_path" ]; then
        return 0
    fi

    case "$temporary_path" in
        "$temporary_prefix"*)
            rm -f "$temporary_path" 2>/dev/null
            ;;
    esac

    return 0
}

_profile_read_file_mode()
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

_profile_render_to_file()
{
    local output_path=$1
    local schema_path=$2
    local schema_line
    local entry
    local key
    local value

    if ! : 2>/dev/null > "$output_path"; then
        _profile_print_error "프로필 출력 파일을 만들 수 없습니다: $output_path"
        return 2
    fi

    while IFS= read -r schema_line || [ -n "$schema_line" ]; do
        _profile_strip_line_ending "$schema_line"
        schema_line=$_PROFILE_LINE

        if _profile_is_ignored_line "$schema_line"; then
            continue
        fi

        if ! _profile_parse_schema_line "$schema_line"; then
            _profile_print_error "스키마 행 형식이 올바르지 않습니다: $schema_line"
            return 3
        fi

        while IFS= read -r entry || [ -n "$entry" ]; do
            if [ -z "$entry" ]; then
                continue
            fi

            key=${entry%%=*}
            value=${entry#*=}
            if [ "$key" = "$_PROFILE_SCHEMA_KEY" ]; then
                if ! printf '%s=%s\n' "$key" "$value" 2>/dev/null >> "$output_path"; then
                    _profile_print_error "프로필을 기록할 수 없습니다: $output_path"
                    return 2
                fi
            fi
        done <<PROFILE_DATA_EOF
$_PROFILE_DATA
PROFILE_DATA_EOF
    done < "$schema_path"

    return 0
}

_profile_write_apply()
{
    local output_path
    local schema_path
    local directory
    local file_name
    local target_path
    local temporary_template
    local temporary_prefix
    local temporary_path
    local existing_mode=""
    local status

    if [ "$#" -ne 1 ]; then
        _profile_print_error "profile_write에는 출력 경로가 필요합니다."
        return 2
    fi

    output_path=$1
    schema_path=$_PROFILE_SCHEMA_PATH
    if [ -z "$schema_path" ]; then
        _profile_print_error "먼저 프로필을 스키마로 검증해야 합니다."
        return 2
    fi

    if [ "$output_path" -ef "$schema_path" ]; then
        _profile_print_error "스키마 파일을 프로필 출력 대상으로 사용할 수 없습니다: $output_path"
        return 2
    fi

    profile_validate "$schema_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    case "$output_path" in
        */*)
            directory=${output_path%/*}
            file_name=${output_path##*/}
            if [ -z "$directory" ]; then
                directory="/"
            fi
            ;;
        *)
            directory="."
            file_name=$output_path
            ;;
    esac

    if [ ! -d "$directory" ]; then
        _profile_print_error "프로필 출력 디렉터리를 찾을 수 없습니다: $directory"
        return 2
    fi

    if [ "$directory" = "/" ]; then
        target_path="/$file_name"
        temporary_prefix="/.${file_name}.tmp."
    else
        target_path="$directory/$file_name"
        temporary_prefix="$directory/.${file_name}.tmp."
    fi
    temporary_template="${temporary_prefix}XXXXXX"

    if [ -d "$target_path" ]; then
        _profile_print_error "프로필 출력 경로로 디렉터리를 사용할 수 없습니다: $output_path"
        return 2
    fi

    if [ -e "$target_path" ] && [ ! -f "$target_path" ] && [ ! -L "$target_path" ]; then
        _profile_print_error "프로필 출력 경로가 일반 파일이 아닙니다: $output_path"
        return 2
    fi

    if [ -e "$target_path" ] && [ ! -L "$target_path" ] && [ -f "$target_path" ]; then
        existing_mode=$(_profile_read_file_mode "$target_path")
        status=$?
        if [ "$status" -ne 0 ] || [ -z "$existing_mode" ]; then
            _profile_print_error "기존 프로필 파일 권한을 읽을 수 없습니다: $output_path"
            return 2
        fi
    fi

    temporary_path=$(mktemp "$temporary_template" 2>/dev/null)
    status=$?
    if [ "$status" -ne 0 ] || [ -z "$temporary_path" ] || [ ! -f "$temporary_path" ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _profile_print_error "프로필 임시 파일을 만들 수 없습니다: $directory"
        return 2
    fi

    _profile_render_to_file "$temporary_path" "$schema_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        return "$status"
    fi

    if [ -n "$existing_mode" ]; then
        if ! chmod "$existing_mode" "$temporary_path" 2>/dev/null; then
            _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
            _profile_print_error "기존 프로필 파일 권한을 적용할 수 없습니다: $output_path"
            return 2
        fi
    fi

    if ! mv -f "$temporary_path" "$target_path" 2>/dev/null; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _profile_print_error "프로필 출력 파일을 원자 교체할 수 없습니다: $output_path"
        return 2
    fi

    return 0
}

profile_write()
{
    _profile_run_transaction 1 _profile_write_apply "$@"
}

_profile_confirm_apply()
{
    local profile_path
    local schema_path
    local directory
    local file_name
    local target_path
    local temporary_template
    local temporary_prefix
    local temporary_path
    local status

    if [ "$#" -ne 2 ]; then
        _profile_print_error "profile_confirm에는 프로필 경로와 스키마 경로가 필요합니다."
        return 2
    fi

    profile_path=$1
    schema_path=$2

    profile_load "$profile_path" "$schema_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    profile_set_single "confirmation_status" "confirmed"
    status=$?
    if [ "$status" -ne 0 ]; then
        return "$status"
    fi

    case "$profile_path" in
        */*)
            directory=${profile_path%/*}
            file_name=${profile_path##*/}
            if [ -z "$directory" ]; then
                directory="/"
            fi
            ;;
        *)
            directory="."
            file_name=$profile_path
            ;;
    esac

    if [ ! -d "$directory" ]; then
        _profile_print_error "프로필 디렉터리를 찾을 수 없습니다: $directory"
        return 2
    fi

    if [ "$directory" = "/" ]; then
        target_path="/$file_name"
        temporary_prefix="/.${file_name}.tmp."
    else
        target_path="$directory/$file_name"
        temporary_prefix="$directory/.${file_name}.tmp."
    fi
    temporary_template="${temporary_prefix}XXXXXX"

    temporary_path=$(mktemp "$temporary_template" 2>/dev/null)
    status=$?
    if [ "$status" -ne 0 ] || [ -z "$temporary_path" ] || [ ! -f "$temporary_path" ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _profile_print_error "프로필 임시 파일을 만들 수 없습니다: $directory"
        return 2
    fi

    if ! cp -p "$target_path" "$temporary_path" 2>/dev/null; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _profile_print_error "프로필을 임시 파일로 복제할 수 없습니다: $profile_path"
        return 2
    fi

    profile_write "$temporary_path"
    status=$?
    if [ "$status" -ne 0 ]; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        return "$status"
    fi

    if ! mv -f "$temporary_path" "$target_path" 2>/dev/null; then
        _profile_cleanup_temporary_file "$temporary_path" "$temporary_prefix"
        _profile_print_error "확정된 프로필로 원자 교체할 수 없습니다: $profile_path"
        return 2
    fi

    return 0
}

profile_confirm()
{
    _profile_run_transaction 0 _profile_confirm_apply "$@"
}

profile_reset

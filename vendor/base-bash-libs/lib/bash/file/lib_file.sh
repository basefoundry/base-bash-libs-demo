# shellcheck shell=bash
#
# lib_file.sh - Bash library of generic file manipulation functions.
#

[[ -n "${BASE_BASH_LIBS_FILE_LOADED:-}" ]] && return 0
if [[ "${BASE_BASH_LIBS_STDLIB_LOADED:-}" != "1" ]]; then
    printf '%s\n' "Error: lib_file.sh requires lib_std.sh to be sourced first." >&2
    return 1 2> /dev/null || exit 1
fi
readonly BASE_BASH_LIBS_FILE_LOADED=1

__base_bash_libs_file_literal_path__() {
    local result_name="$1" path="$2"

    if [[ "$path" == -* ]]; then
        path="./$path"
    fi
    printf -v "$result_name" '%s' "$path"
}

__base_bash_libs_file_resolve_target_path__() {
    local result_name="$1" path="$2"
    local link_target path_dir depth=0

    __base_bash_libs_file_literal_path__ path "$path"
    if [[ "$path" != /* ]]; then
        path="$(pwd -P)/$path" || return 1
    fi

    while [[ -L "$path" ]]; do
        ((depth += 1))
        if ((depth > 40)); then
            base_std_log_error -l base_bash_libs.file "Too many symlink levels while resolving '$2'."
            return 1
        fi

        link_target="$(readlink "$path")" || return 1
        if [[ "$link_target" == /* ]]; then
            path="$link_target"
        else
            path="$(dirname -- "$path")/$link_target"
        fi
        path_dir="$(cd -P -- "$(dirname -- "$path")" && pwd -P)" || return 1
        path="$path_dir/$(basename -- "$path")"
    done

    printf -v "$result_name" '%s' "$path"
}

__base_bash_libs_file_validate_markers__() {
    local beginning_marker="$1" end_marker="$2"

    if [[ -z "$beginning_marker" || -z "$end_marker" ||
        "$beginning_marker" == "$end_marker" ||
        "$beginning_marker" == *$'\n'* || "$beginning_marker" == *$'\r'* ||
        "$end_marker" == *$'\n'* || "$end_marker" == *$'\r'* ]]; then
        base_std_log_error -l base_bash_libs.file "Section markers must be non-empty, distinct, single-line values."
        return 2
    fi
    return 0
}

__base_bash_libs_file_mode__() {
    local file_path="$1" mode

    if mode=$(stat -c '%a' "$file_path" 2> /dev/null); then
        printf '%s\n' "$mode"
        return 0
    fi

    stat -f '%Lp' "$file_path"
}

__base_bash_libs_file_fingerprint__() {
    local result_name="$1" file_path="$2" fingerprint content_hash

    if fingerprint="$(stat -c '%d:%i:%s:%Y:%Z' -- "$file_path" 2> /dev/null)"; then
        :
    elif ! fingerprint="$(stat -f '%d:%i:%z:%m:%c' -- "$file_path" 2> /dev/null)"; then
        return 1
    fi

    # Filesystems differ in timestamp precision (notably macOS/BSD stat), so
    # metadata alone can miss a same-size rewrite in the same clock tick.
    # Include a content digest to make the optimistic commit check resistant to
    # that race while retaining the inexpensive stat identity fields above.
    if command -v sha256sum > /dev/null 2>&1; then
        content_hash="$(sha256sum -- "$file_path" | awk '{print $1}')" || return 1
    elif command -v shasum > /dev/null 2>&1; then
        content_hash="$(shasum -a 256 -- "$file_path" | awk '{print $1}')" || return 1
    else
        return 1
    fi
    [[ "$content_hash" =~ ^[[:xdigit:]]{64}$ ]] || return 1
    printf -v "$result_name" '%s:%s' "$fingerprint" "$content_hash"
}

__base_bash_libs_file_commit_temp__() {
    local temp_file="$1" target_file="$2" expected_fingerprint="$3" current_fingerprint

    if ! __base_bash_libs_file_fingerprint__ current_fingerprint "$target_file" ||
        [[ "$current_fingerprint" != "$expected_fingerprint" ]]; then
        return 6
    fi
    mv -f -- "$temp_file" "$target_file"
}

__base_bash_libs_file_preserve_file_mode__() {
    local source_file="$1" target_file="$2" source_mode

    if ! source_mode="$(__base_bash_libs_file_mode__ "$source_file")"; then
        return 1
    fi

    chmod "$source_mode" "$target_file"
}

__base_bash_libs_file_remove_temp_paths__() {
    local path

    for path; do
        if [[ -n "$path" ]]; then
            rm -f -- "$path"
            base_std_unregister_cleanup_path "$path"
        fi
    done
    return 0
}

__base_bash_libs_file_make_target_temp__() {
    local result_name="$1" target_file="$2"
    local target_dir target_base temp_dir temp_path

    target_dir="$(dirname -- "$target_file")"
    target_base="$(basename -- "$target_file")"
    temp_dir="$(cd -- "$target_dir" && pwd -P)" || return 1

    temp_path="$(mktemp "$temp_dir/$target_base.XXXXXX" 2> /dev/null)" || return 1
    if ! base_std_register_cleanup_path "$temp_path"; then
        rm -f -- "$temp_path"
        return 1
    fi

    printf -v "$result_name" '%s' "$temp_path"
}

__base_bash_libs_file_section_awk__() {
    local mode="$1" target_file="$2" beginning_marker="$3" end_marker="$4"
    local new_content_file="${5-}"

    BASE_BASH_LIBS_FILE_MODE="$mode" \
        BASE_BASH_LIBS_FILE_START_MARKER="$beginning_marker" \
        BASE_BASH_LIBS_FILE_END_MARKER="$end_marker" \
        BASE_BASH_LIBS_FILE_NEW_CONTENT_FILE="$new_content_file" \
        awk '
    BEGIN {
        MODE = ENVIRON["BASE_BASH_LIBS_FILE_MODE"]
        START_M = ENVIRON["BASE_BASH_LIBS_FILE_START_MARKER"]
        END_M = ENVIRON["BASE_BASH_LIBS_FILE_END_MARKER"]
        NEW_TEXT_FILE = ENVIRON["BASE_BASH_LIBS_FILE_NEW_CONTENT_FILE"]
        in_section = 0
        processed = 0
        result = 0
    }
    $0 == START_M {
        if (MODE == "ordered") {
            if (in_section == 1) {
                result = 1
                exit
            }
            in_section = 1
            next
        }
        if (processed == 0) {
            if (MODE == "replace") {
                print START_M
                while ((getline line < NEW_TEXT_FILE) > 0) {
                    print line
                }
                close(NEW_TEXT_FILE)
                in_section = 1
                processed = 1
                next
            }
            in_section = 1
            next
        }
    }
    $0 == END_M {
        if (in_section == 0) {
            if (MODE == "ordered" || processed == 0) {
                result = 1
                exit
            }
            print $0
            next
        }
        if (MODE == "extract") {
            in_section = 0
            processed = 1
            exit
        }
        if (MODE == "remove") {
            in_section = 0
            processed = 1
            next
        }
        if (MODE == "replace") {
            print END_M
            in_section = 0
            processed = 2
            next
        }
        in_section = 0
        next
    }
    {
        if (MODE == "ordered") {
            next
        }
        if (MODE == "extract" && in_section == 1) {
            print $0
        } else if (MODE == "remove" && in_section == 0) {
            print $0
        } else if (MODE == "replace" && processed != 1) {
            print $0
        }
    }
    END {
        if (in_section == 1 || (MODE == "extract" && processed == 0)) {
            result = 1
        }
        exit result
    }
    ' "$target_file"
}

__base_bash_libs_file_section_markers_ordered__() {
    local target_file="$1" beginning_marker="$2" end_marker="$3"

    __base_bash_libs_file_section_awk__ ordered "$target_file" "$beginning_marker" "$end_marker"
}

__base_bash_libs_file_section_marker_counts__() {
    local target_file="$1" beginning_marker="$2" end_marker="$3"
    local beginning_count_var="$4" end_count_var="$5"
    local section_beginning_marker_count section_end_marker_count

    __base_bash_libs_file_validate_markers__ "$beginning_marker" "$end_marker" || return $?

    section_beginning_marker_count=$(grep -cxF -- "$beginning_marker" "$target_file" || true)
    section_end_marker_count=$(grep -cxF -- "$end_marker" "$target_file" || true)

    printf -v "$beginning_count_var" '%s' "$section_beginning_marker_count"
    printf -v "$end_count_var" '%s' "$section_end_marker_count"

    if ((section_beginning_marker_count != section_end_marker_count)); then
        base_std_log_error -l base_bash_libs.file "Asymmetric markers in '$target_file': $section_beginning_marker_count start, $section_end_marker_count end. Manual repair needed."
        return 2
    fi
    if ((section_beginning_marker_count > 0)) && ! __base_bash_libs_file_section_markers_ordered__ "$target_file" "$beginning_marker" "$end_marker"; then
        base_std_log_error -l base_bash_libs.file "Misordered markers in '$target_file'. Manual repair needed."
        return 2
    fi

    return 0
}

#
# base_file_section_exists - Inspect whether a marker-delimited section is present.
#
# Returns:
#   0 when the target file contains at least one valid marker pair.
#   1 when the target file is missing or the marker pair is absent.
#   2 when marker pairs are asymmetric or misordered and need manual repair.
#
base_file_section_exists() {
    if [[ $# -ne 3 ]]; then
        base_std_log_error -l base_bash_libs.file "base_file_section_exists: expected <target_file> <beginning_marker> <end_marker>."
        return 2
    fi

    local target_file="$1" beginning_marker="$2" end_marker="$3"
    local beginning_marker_count _end_marker_count

    __base_bash_libs_file_literal_path__ target_file "$target_file"
    __base_bash_libs_file_validate_markers__ "$beginning_marker" "$end_marker" || return $?
    [[ -f "$target_file" ]] || return 1
    __base_bash_libs_file_section_marker_counts__ "$target_file" "$beginning_marker" "$end_marker" \
        beginning_marker_count _end_marker_count || return $?

    ((beginning_marker_count > 0))
}

#
# base_file_section_needs_update - Inspect whether add/update would change a section.
#
# Returns:
#   0 when adding or updating the section would change the target file.
#   1 when the first existing marker-delimited section already matches.
#   2 when marker pairs are asymmetric or misordered and need manual repair.
#
base_file_section_needs_update() {
    if [[ $# -lt 3 ]]; then
        base_std_log_error -l base_bash_libs.file "base_file_section_needs_update: expected <target_file> <beginning_marker> <end_marker> [content_lines...]."
        return 2
    fi

    local target_file="$1" beginning_marker="$2" end_marker="$3"
    local beginning_marker_count _end_marker_count
    local current_content_file="" new_content_file="" status=0
    shift 3

    __base_bash_libs_file_literal_path__ target_file "$target_file"
    __base_bash_libs_file_validate_markers__ "$beginning_marker" "$end_marker" || return $?
    [[ -f "$target_file" ]] || return 0
    __base_bash_libs_file_section_marker_counts__ "$target_file" "$beginning_marker" "$end_marker" \
        beginning_marker_count _end_marker_count || return $?
    ((beginning_marker_count > 0)) || return 0

    if ! base_std_make_temp_file new_content_file base-file-section-new; then
        base_std_log_error -l base_bash_libs.file "Failed to create temporary content file for '$target_file'."
        return 2
    fi
    if (($# > 0)); then
        if ! printf '%s\n' "$@" > "$new_content_file"; then
            base_std_log_error -l base_bash_libs.file "Failed to write replacement content for '$target_file'."
            __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
            return 2
        fi
    elif ! : > "$new_content_file"; then
        base_std_log_error -l base_bash_libs.file "Failed to write replacement content for '$target_file'."
        __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
        return 2
    fi

    if ! base_std_make_temp_file current_content_file base-file-section-current; then
        base_std_log_error -l base_bash_libs.file "Failed to create temporary current content file for '$target_file'."
        __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
        return 2
    fi

    if ! __base_bash_libs_file_section_awk__ extract "$target_file" "$beginning_marker" "$end_marker" > "$current_content_file"; then
        base_std_log_error -l base_bash_libs.file "Failed to read existing section in '$target_file'."
        __base_bash_libs_file_remove_temp_paths__ "$current_content_file" "$new_content_file"
        return 2
    fi

    if cmp -s "$current_content_file" "$new_content_file"; then
        status=1
    fi

    __base_bash_libs_file_remove_temp_paths__ "$current_content_file" "$new_content_file"
    return "$status"
}

#
# base_file_update_file_section - Idempotently manages a block of text within a file,
#                       demarcated by start and end markers.
#
# This function can add, update, or remove a section of text in a file.
# It is designed to be safe to run multiple times. If the section already
# exists, the first full-line marker pair will be replaced. If it doesn't
# exist, it will be appended. If the target file itself does not exist, this
# returns success without creating the file.
#
# Usage:
#   base_file_update_file_section [options] <target_file> <start_marker> <end_marker> [content_lines...]
#
# Options:
#   -r : Remove the section defined by the markers instead of adding/updating it.
#
# Arguments:
#   target_file:    The path to the file to be modified.
#   start_marker:   The exact string that marks the beginning of the section.
#   end_marker:     The exact string that marks the end of the section.
#   content_lines:  (Optional) One or more strings, each representing a line of
#                   content to be placed inside the section.
#
# Examples:
#
#   # Add/update a section in .bash_profile
#   local commands=("export FOO=bar" "alias myalias='echo hello'")
#   base_file_update_file_section ~/.bash_profile "# START" "# END" "${commands[@]}"
#
#   # Remove the same section
#   base_file_update_file_section -r ~/.bash_profile "# START" "# END"
#
base_file_update_file_section() {
    local remove_section=false
    local new_content_array=()

    if [[ "${1-}" == "-r" ]]; then
        remove_section=true
        shift # consume -r
    fi

    if [[ $# -lt 3 ]]; then
        base_std_log_error -l base_bash_libs.file "Insufficient arguments."
        if [[ "$remove_section" == true ]]; then
            base_std_log_info -l base_bash_libs.file "Usage: base_file_update_file_section -r <target_file> <beginning_marker> <end_marker>"
        else
            base_std_log_info -l base_bash_libs.file "Usage: base_file_update_file_section <target_file> <beginning_marker> <end_marker> [new_lines...]"
        fi
        return 2
    fi

    local target_file="$1" beginning_marker="$2" end_marker="$3"
    shift 3 # consume target_file, beginning_marker, end_marker
    if [[ "$remove_section" == true ]]; then
        if [[ $# -gt 0 ]]; then
            base_std_log_error -l base_bash_libs.file "When -r flag is used, no content arguments should be provided."
            base_std_log_info -l base_bash_libs.file "Usage: base_file_update_file_section -r <target_file> <beginning_marker> <end_marker>"
            return 2
        fi
    else
        new_content_array=("$@") # Capture remaining arguments as new_lines
    fi

    __base_bash_libs_file_literal_path__ target_file "$target_file"
    __base_bash_libs_file_validate_markers__ "$beginning_marker" "$end_marker" || return $?
    if [[ ! -f "$target_file" ]]; then
        base_std_log_debug -l base_bash_libs.file "Target file '$target_file' does not exist."
        return 0
    fi

    __base_bash_libs_file_resolve_target_path__ target_file "$target_file" || return 1
    local original_fingerprint=""
    if ! __base_bash_libs_file_fingerprint__ original_fingerprint "$target_file"; then
        base_std_log_error -l base_bash_libs.file \
            "Unable to fingerprint '$target_file' before editing."
        return 1
    fi

    local __base_bash_libs_file_update_beginning_marker_count __base_bash_libs_file_update_end_marker_count
    local commit_status
    if ! __base_bash_libs_file_section_marker_counts__ "$target_file" "$beginning_marker" "$end_marker" \
        __base_bash_libs_file_update_beginning_marker_count __base_bash_libs_file_update_end_marker_count; then
        return 1
    fi

    local section_exists=false
    if ((__base_bash_libs_file_update_beginning_marker_count > 0)); then
        section_exists=true
    fi

    local new_content_string=""
    if [[ "$remove_section" == false ]]; then
        if [[ -n "${new_content_array[0]+set}" ]]; then
            # Use printf to join array elements with newlines, adding a final newline.
            # This ensures proper multi-line insertion.
            printf -v new_content_string '%s\n' "${new_content_array[@]+"${new_content_array[@]}"}"
        fi
    fi

    if [[ "$section_exists" == false && "$remove_section" == true ]]; then
        base_std_log_debug -l base_bash_libs.file "Section not present in '$target_file'; nothing to remove."
        return 0
    fi

    local current_content_file="" new_content_file="" temp_file
    if [[ "$remove_section" == false ]]; then
        if ! base_std_make_temp_file new_content_file base-file-section-new; then
            base_std_log_error -l base_bash_libs.file "Failed to create temporary content file for '$target_file'."
            return 1
        fi

        if ! printf '%s' "$new_content_string" > "$new_content_file"; then
            base_std_log_error -l base_bash_libs.file "Failed to write replacement content for '$target_file'."
            __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
            return 1
        fi
    fi

    if [[ "$section_exists" == true && "$remove_section" == false ]]; then
        if ! base_std_make_temp_file current_content_file base-file-section-current; then
            base_std_log_error -l base_bash_libs.file "Failed to create temporary current content file for '$target_file'."
            __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
            return 1
        fi

        if ! __base_bash_libs_file_section_awk__ extract "$target_file" "$beginning_marker" "$end_marker" > "$current_content_file"; then
            base_std_log_error -l base_bash_libs.file "Failed to read existing section in '$target_file'."
            __base_bash_libs_file_remove_temp_paths__ "$current_content_file" "$new_content_file"
            return 1
        fi

        if cmp -s "$current_content_file" "$new_content_file"; then
            base_std_log_debug -l base_bash_libs.file "Section already up to date in '$target_file'."
            __base_bash_libs_file_remove_temp_paths__ "$current_content_file" "$new_content_file"
            return 0
        fi
        __base_bash_libs_file_remove_temp_paths__ "$current_content_file"
    fi

    if [[ "$section_exists" == true ]]; then
        base_std_log_info -l base_bash_libs.file "Updating '$target_file'"
    else
        base_std_log_info -l base_bash_libs.file "Adding section to '$target_file'"
    fi
    if ! __base_bash_libs_file_make_target_temp__ temp_file "$target_file"; then
        base_std_log_error -l base_bash_libs.file "Failed to create temporary file for '$target_file'."
        __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
        return 1
    fi
    if ! __base_bash_libs_file_preserve_file_mode__ "$target_file" "$temp_file"; then
        base_std_log_error -l base_bash_libs.file "Failed to preserve permissions for '$target_file'."
        __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
        return 1
    fi

    if [[ "$section_exists" == true ]]; then
        if [[ "$remove_section" == true ]]; then
            if __base_bash_libs_file_section_awk__ remove "$target_file" "$beginning_marker" "$end_marker" > "$temp_file"; then
                __base_bash_libs_file_commit_temp__ "$temp_file" "$target_file" "$original_fingerprint"
                commit_status=$?
                if ((commit_status == 0)); then
                    base_std_unregister_cleanup_path "$temp_file"
                    __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
                    return 0
                fi
                if ((commit_status == 6)); then
                    base_std_log_error -l base_bash_libs.file \
                        "Concurrent modification detected for '$target_file'; refusing to overwrite it."
                    __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
                    return 6
                fi
            fi
        else
            if __base_bash_libs_file_section_awk__ replace "$target_file" "$beginning_marker" "$end_marker" "$new_content_file" > "$temp_file"; then
                __base_bash_libs_file_commit_temp__ "$temp_file" "$target_file" "$original_fingerprint"
                commit_status=$?
                if ((commit_status == 0)); then
                    base_std_unregister_cleanup_path "$temp_file"
                    __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
                    return 0
                fi
                if ((commit_status == 6)); then
                    base_std_log_error -l base_bash_libs.file \
                        "Concurrent modification detected for '$target_file'; refusing to overwrite it."
                    __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
                    return 6
                fi
            fi
        fi

        base_std_log_error -l base_bash_libs.file "Failed to process sections in '$target_file'."
        __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
        return 1
    else
        # Markers not found in the file
        if ! cp "$target_file" "$temp_file"; then
            base_std_log_error -l base_bash_libs.file "Failed to copy '$target_file' to '$temp_file'."
            __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
            return 1
        fi

        if [[ -s "$temp_file" ]] && [[ $(tail -c 1 "$temp_file" 2> /dev/null | wc -l) -eq 0 ]]; then
            if ! printf '\n' >> "$temp_file"; then
                base_std_log_error -l base_bash_libs.file "Failed to add trailing newline to '$temp_file'."
                __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
                return 1
            fi
        fi

        if ! {
            printf '%s\n' "$beginning_marker"
            printf '%s' "$new_content_string"
            printf '%s\n' "$end_marker"
        } >> "$temp_file"; then
            base_std_log_error -l base_bash_libs.file "Failed to add new section to '$target_file'."
            __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
            return 1
        fi

        __base_bash_libs_file_commit_temp__ "$temp_file" "$target_file" "$original_fingerprint"
        commit_status=$?
        if ((commit_status != 0)); then
            if ((commit_status == 6)); then
                base_std_log_error -l base_bash_libs.file \
                    "Concurrent modification detected for '$target_file'; refusing to overwrite it."
                __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
                return 6
            fi
            base_std_log_error -l base_bash_libs.file "Failed to replace '$target_file' with '$temp_file'."
            __base_bash_libs_file_remove_temp_paths__ "$temp_file" "$new_content_file"
            return 1
        fi

        base_std_unregister_cleanup_path "$temp_file"
        __base_bash_libs_file_remove_temp_paths__ "$new_content_file"
        return 0
    fi
}

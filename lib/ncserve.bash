#!/bin/bash


handleRequest() {
    while read -r http_version; do
        [[ -z $http_version ]] && continue

        declare -A HEADERS=()
        
        info "$http_version" >&2

        read -ra version_arr <<<"$http_version"
        declare http_method="${version_arr[0]}"
        
        if [[ $http_method != @(GET) ]]; then
            respond -S 500 -C "Method $http_method is not supported yet."
            while read -r line; do
                [[ ${#line} -eq 1 ]] && break
            done

            continue
        fi

        while read -r line; do
            [[ ${#line} -eq 1 ]] && break
            debug "Header line: $line" >&2
            declare header_name="${line%%:*}"
            declare header_val="${line#*:}"
            debug 'Header name: '"$header_name" >&2
            debug 'Header val: '"$header_val" >&2
            HEADERS[$header_name]="$header_val"
        done

        debug '===== Handling:' >&2
        for header in "${!HEADERS[@]}"; do
            debug 'HEADER => '"$header"': '"${HEADERS[$header]}" >&2
        done
        
        declare route="${version_arr[1]}"
        debug "ROUTE => $route" >&2

        (route "$route" || respond -S 404 -C 'The requested resource was not found')
    done
}

respond() {
    declare arg="$1" content='' status=''
    declare -A headers=()
    while shift; do
        case "$arg" in
            -S | --status)
                status="$1"
                shift
                ;;
            -H | --header)
                headers[$1]="$2"
                shift 2
                ;;
            -C | --content)
                content="$1"
                shift
                ;;
            *)
                printf 'Unknown option: "%s"\n' "${arg}" >&2
                return 1
        esac
        arg="$1"
    done

    declare content_length="$(echo "$content" | wc -c)"

    headers['Content-Length']="$content_length"

    if [[ -z ${headers['Content-Type']} ]]; then
        headers['Content-Type']='text/plain'
    fi

    if [[ -z $status ]]; then
        status=200
    fi

    printf 'HTTP/1.1 %d\n' "$status"
    for header in "${!headers[@]}"; do
        printf '%s: %s\r\n' "$header" "${headers[$header]}"
    done
    printf '\r\n\n'

    echo "$content"
}

startServer() {
    declare -i INFO=1

    if ! declare -f route &>>/dev/null; then
        echo 'No route function defined, not starting server.' >&2

        return 1
    fi

    if ! which netcat &>>/dev/null; then
        echo "This script is dependent on netcat, can't start server" >&2

        return 1
    fi

    declare port="$1"

    mkfifo server_fifo
    trap 'rm server_fifo' EXIT

    info 'Starting server on port '"$port"

    # shellcheck disable=SC2094
    while true; do
        netcat -k -l -p "$port" < server_fifo \
            | handleRequest \
            | { if [[ $DEBUG -ge 1 ]]; then tee server_fifo; else cat > server_fifo; fi; }
    done
}

debug() {
    if [[ $DEBUG -ge 1 ]]; then
        echo "[DEBUG] => $1" >&2
    fi
}

# shellcheck disable=SC2059
debugf() {
    if [[ $DEBUG -ge 1 ]]; then
        declare format_string="$1"
        shift
        printf "[DEBUG] => $format_string" "$@" >&2
    fi
}

info() {
    if [[ $INFO -eq 1 ]]; then
        echo "[INFO] => $1" >&2
    fi
}

# shellcheck disable=SC2059
infof() {
    if [[ $INFO -eq 1 ]]; then
        declare format_string="$1"
        shift
        printf "[INFO] => $format_string" "$@" >&2
    fi
}

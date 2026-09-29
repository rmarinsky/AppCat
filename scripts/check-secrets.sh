#!/bin/bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

if [[ "$(ripsecrets --version)" != 'ripsecrets 0.1.11' || "$(gitleaks version)" != '8.30.1' ]]; then
    echo 'Secret scanner versions differ from mise.toml; run mise install.' >&2
    exit 1
fi

check_paths() {
    local path name
    while IFS= read -r -d '' path; do
        name="${path##*/}"
        case "$name" in
            .env.example|.env.template) ;; # Content still goes through both scanners.
            .env|.env.*|*.pem|*.key|*.p12|*.pfx|id_rsa|id_ed25519|credentials.json|secrets.json|*.sql.gz|*.dump)
                echo "Refusing credential/signing/dump path: $path" >&2
                return 1
                ;;
        esac
    done
}

case "${1:-tree}" in
    staged)
        check_paths < <(git diff --cached --name-only --diff-filter=ACMR -z)
        git diff --cached --no-ext-diff --no-color --binary | gitleaks stdin --redact --no-banner
        paths=()
        while IFS= read -r -d '' path; do paths+=("$path"); done < <(git diff --cached --name-only --diff-filter=ACMR -z)
        if [[ ${#paths[@]} -gt 0 ]]; then
            ripsecrets --strict-ignore "${paths[@]}" >/dev/null || {
                echo 'Staged-file secret scan failed; suspected values are not printed.' >&2
                exit 1
            }
        fi
        ;;
    range)
        scan_range() {
            gitleaks git --redact --no-banner --log-opts="$1"
        }

        if [[ "${2:-}" == --push-refs ]]; then
            saw_ref_update=false
            while IFS=' ' read -r local_ref local_oid remote_ref remote_oid extra; do
                [[ -z "$local_ref" ]] && continue
                saw_ref_update=true
                if [[ -n "${extra:-}" || -z "${local_oid:-}" || -z "${remote_ref:-}" || -z "${remote_oid:-}" ]]; then
                    echo 'Malformed pre-push ref update.' >&2
                    exit 2
                fi
                for oid in "$local_oid" "$remote_oid"; do
                    if [[ ! "$oid" =~ ^[0-9a-fA-F]+$ || ( ${#oid} != 40 && ${#oid} != 64 ) ]]; then
                        echo 'Malformed pre-push object ID.' >&2
                        exit 2
                    fi
                done

                [[ "$local_oid" =~ ^0+$ ]] && continue # Deleted remote ref.
                if [[ "$remote_oid" =~ ^0+$ ]]; then
                    scan_range "$local_oid" # A new ref makes its complete history newly reachable.
                else
                    scan_range "$remote_oid..$local_oid"
                fi
            done
            if [[ "$saw_ref_update" == false ]]; then
                echo 'Git supplied no ref updates to the pre-push secret scan.' >&2
                exit 2
            fi
        elif [[ -n "${2:-}" ]]; then
            scan_range "$2"
        else
            echo 'A commit range or --push-refs is required for range mode.' >&2
            exit 2
        fi
        ;;
    tree)
        check_paths < <(git ls-files -z)
        paths=()
        while IFS= read -r -d '' path; do paths+=("$path"); done < <(git ls-files -z)
        ripsecrets --strict-ignore "${paths[@]}" >/dev/null || {
            echo 'Tracked-tree secret scan failed; suspected values are not printed.' >&2
            exit 1
        }
        ;;
    *) echo 'Usage: check-secrets.sh staged|tree|range [base..head|--push-refs]' >&2; exit 2 ;;
esac

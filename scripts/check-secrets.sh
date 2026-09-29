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
        gitleaks git --redact --no-banner --log-opts="${2:-origin/main..HEAD}"
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
    *) echo 'Usage: check-secrets.sh staged|tree|range [base..head]' >&2; exit 2 ;;
esac

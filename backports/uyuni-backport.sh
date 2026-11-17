#!/usr/bin/env bash

set -Eeuo pipefail

usage() {
    cat <<'EOF'
Usage: git backport [TARGET_BRANCH] [options]

Backport or synchronize the current Uyuni PR to SUSE/spacewalk.
New Spacewalk PRs are drafts unless --ready is supplied.

Arguments:
  TARGET_BRANCH          Spacewalk base branch (configured value or Manager-5.2)

Options:
  --spacewalk PATH       Spacewalk checkout (configured value or ../spacewalk)
  --pr NUMBER            Uyuni source PR number; current branch supplies the backport name
  --allow-unapproved     Allow a PR whose current review decision is not APPROVED
  --ready                Open a ready-for-review PR instead of a draft PR
  --no-push              Rebuild the local Spacewalk branch without pushing it
  --no-pr                Push the branch without opening a Spacewalk PR
  -h, --help             Show this help

Environment:
  SPACEWALK_REPO                  Default path to the Spacewalk checkout
  UYUNI_BACKPORT_TARGET_BRANCH    Default target branch (fallback: Manager-5.2)

Configuration:
  The same variables can be set in a .env file next to this script.
  Shell environment values override .env; command-line arguments override both.

Examples:
  git backport
  git backport Manager-5.2
  git backport Manager-5.2 --ready
  git backport Manager-5.2 --pr 11192 --allow-unapproved
  git backport Manager-5.1 --no-pr
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_file="$script_dir/.env"

# Keep variables already supplied by the caller so the shell environment takes
# precedence over values loaded from the local configuration file.
spacewalk_repo_was_set="${SPACEWALK_REPO+x}"
spacewalk_repo_from_environment="${SPACEWALK_REPO-}"
target_branch_was_set="${UYUNI_BACKPORT_TARGET_BRANCH+x}"
target_branch_from_environment="${UYUNI_BACKPORT_TARGET_BRANCH-}"

if [[ -f "$config_file" ]]; then
    # The .env file is a trusted, user-owned Bash configuration file.
    # shellcheck disable=SC1090
    source "$config_file"
fi

if [[ -n "$spacewalk_repo_was_set" ]]; then
    SPACEWALK_REPO="$spacewalk_repo_from_environment"
fi
if [[ -n "$target_branch_was_set" ]]; then
    UYUNI_BACKPORT_TARGET_BRANCH="$target_branch_from_environment"
fi

target_branch="${UYUNI_BACKPORT_TARGET_BRANCH:-Manager-5.2}"
spacewalk_repo="${SPACEWALK_REPO:-}"
allow_unapproved=0
source_pr=""
push_branch=1
open_pr=1
draft_pr=1
target_was_set=0

while (($#)); do
    case "$1" in
        --spacewalk)
            (($# >= 2)) || die "--spacewalk requires a path"
            spacewalk_repo="$2"
            shift 2
            ;;
        --pr)
            (($# >= 2)) || die "--pr requires a pull request number"
            [[ "$2" =~ ^[1-9][0-9]*$ ]] || die "--pr requires a positive pull request number"
            source_pr="$2"
            shift 2
            ;;
        --allow-unapproved)
            allow_unapproved=1
            shift
            ;;
        --ready)
            draft_pr=0
            shift
            ;;
        --no-push)
            push_branch=0
            open_pr=0
            shift
            ;;
        --no-pr)
            open_pr=0
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        -*)
            die "unknown option: $1"
            ;;
        *)
            ((target_was_set == 0)) || die "only one target branch may be supplied"
            target_branch="$1"
            target_was_set=1
            shift
            ;;
    esac
done

if ((open_pr == 0 && draft_pr == 0)); then
    die "--ready cannot be combined with --no-pr or --no-push"
fi

command -v git >/dev/null || die "git is required"
command -v gh >/dev/null || die "GitHub CLI (gh) is required"
command -v jq >/dev/null || die "jq is required"
command -v sha1sum >/dev/null || die "sha1sum is required"

uyuni_repo="$(git rev-parse --show-toplevel 2>/dev/null)" ||
    die "run this command from inside your Uyuni checkout"
source_branch="$(git -C "$uyuni_repo" branch --show-current)"
[[ -n "$source_branch" ]] || die "the Uyuni checkout is in detached-HEAD state"
[[ "$source_branch" != "master" ]] || die "refusing to backport directly from master"

if [[ -n "$(git -C "$uyuni_repo" status --porcelain)" ]]; then
    die "the Uyuni checkout has uncommitted changes; commit or stash them first"
fi

if [[ -z "$spacewalk_repo" ]]; then
    spacewalk_repo="$(dirname "$uyuni_repo")/spacewalk"
fi
spacewalk_repo="$(cd "$spacewalk_repo" 2>/dev/null && pwd)" ||
    die "Spacewalk checkout not found; use --spacewalk PATH or SPACEWALK_REPO"
git -C "$spacewalk_repo" rev-parse --git-dir >/dev/null 2>&1 ||
    die "'$spacewalk_repo' is not a Git checkout"

spacewalk_origin="$(git -C "$spacewalk_repo" remote get-url origin 2>/dev/null || true)"
[[ "$spacewalk_origin" == *SUSE/spacewalk.git || "$spacewalk_origin" == *SUSE/spacewalk ]] ||
    die "Spacewalk origin does not point to SUSE/spacewalk: $spacewalk_origin"

gh auth status --hostname github.com >/dev/null 2>&1 ||
    die "GitHub CLI is not authenticated; run: gh auth login --hostname github.com"

pr_selector="${source_pr:-$source_branch}"
if [[ -n "$source_pr" ]]; then
    printf 'Reading Uyuni PR #%s for branch %s...\n' "$source_pr" "$source_branch"
else
    printf 'Reading Uyuni PR for branch %s...\n' "$source_branch"
fi
pr_json="$(
    gh pr view "$pr_selector" \
        --repo uyuni-project/uyuni \
        --json number,title,url,headRefOid,reviewDecision,commits
)" || die "no Uyuni PR was found for '$pr_selector'"

pr_number="$(jq -r '.number' <<<"$pr_json")"
pr_title="$(jq -r '.title' <<<"$pr_json")"
pr_url="$(jq -r '.url' <<<"$pr_json")"
pr_head="$(jq -r '.headRefOid' <<<"$pr_json")"
review_decision="$(jq -r '.reviewDecision // ""' <<<"$pr_json")"
local_head="$(git -C "$uyuni_repo" rev-parse HEAD)"

if [[ -z "$source_pr" ]]; then
    [[ "$local_head" == "$pr_head" ]] ||
        die "local HEAD is not the current PR HEAD; push the branch or check out the reviewed commit"
fi
if ((allow_unapproved == 0)) && [[ "$review_decision" != "APPROVED" ]]; then
    die "Uyuni PR #$pr_number review decision is '${review_decision:-none}', not APPROVED"
fi

mapfile -t commits < <(jq -r '.commits[].oid' <<<"$pr_json")
((${#commits[@]} > 0)) || die "Uyuni PR #$pr_number has no commits"

if [[ -n "$source_pr" ]]; then
    for commit in "${commits[@]}"; do
        git -C "$uyuni_repo" cat-file -e "$commit^{commit}" 2>/dev/null ||
            die "Uyuni PR #$pr_number commit '$commit' is not available locally; fetch the PR or update master first"
    done
fi

source_slug="$(printf '%s' "$source_branch" | tr -cs 'A-Za-z0-9._-' '-')"
target_slug="$(printf '%s' "$target_branch" | tr -cs 'A-Za-z0-9._-' '-')"
backport_branch="backport/uyuni-${pr_number}-${source_slug}-to-${target_slug}"
target_version="${target_branch#Manager-}"
backport_pr_title="$target_version - $pr_title"
pr_body_format="## What does this PR change?\n\nBackport of %s\n\nUyuni source HEAD: \`%s\`\nTarget product branch: \`%s\`\nSpacewalk target HEAD: \`%s\`\nSpacewalk backport HEAD: \`%s\`\n\n## Changelogs\n\nMake sure the changelogs entries you are adding are compliant with https://github.com/uyuni-project/uyuni/wiki/Contributing#changelogs and https://github.com/uyuni-project/uyuni/wiki/Contributing#uyuni-projectuyuni-repository\n\nIf you don't need a changelog check, please mark this checkbox:\n\n- [ ] No changelog needed\n\nIf you uncheck the checkbox after the PR is created, you will need to re-run \`changelog_test\` (see below)"

build_pr_body() {
    printf "$pr_body_format" "$pr_url" "$pr_head" "$target_branch" "$target_head" "$1"
}

printf 'Fetching Spacewalk %s...\n' "$target_branch"
git -C "$spacewalk_repo" fetch origin "$target_branch"
git -C "$spacewalk_repo" show-ref --verify --quiet "refs/remotes/origin/$target_branch" ||
    die "Spacewalk branch 'origin/$target_branch' does not exist"
target_head="$(git -C "$spacewalk_repo" rev-parse "refs/remotes/origin/$target_branch")"

if git -C "$spacewalk_repo" worktree list --porcelain |
    awk -v branch="refs/heads/$backport_branch" '$1 == "branch" && $2 == branch { found = 1 } END { exit !found }'; then
    die "Spacewalk branch '$backport_branch' is checked out; switch that worktree to another branch first"
fi

remote_head="$(
    git -C "$spacewalk_repo" ls-remote --heads origin "refs/heads/$backport_branch" |
        awk 'NR == 1 { print $1 }'
)"

spacewalk_pr_json="$(
    gh pr list \
        --repo SUSE/spacewalk \
        --state open \
        --base "$target_branch" \
        --head "$backport_branch" \
        --limit 1 \
        --json number,url,body,isDraft
)"
spacewalk_pr_number="$(jq -r '.[0].number // empty' <<<"$spacewalk_pr_json")"
spacewalk_pr_url="$(jq -r '.[0].url // empty' <<<"$spacewalk_pr_json")"
spacewalk_pr_body="$(jq -r '.[0].body // empty' <<<"$spacewalk_pr_json")"
spacewalk_pr_is_draft="$(jq -r '.[0].isDraft // false' <<<"$spacewalk_pr_json")"
source_marker="Uyuni source HEAD: \`$pr_head\`"
recorded_target_head="$(
    sed -n 's/^Spacewalk target HEAD: `\([0-9a-fA-F][0-9a-fA-F]*\)`$/\1/p' <<<"$spacewalk_pr_body"
)"
recorded_backport_head="$(
    sed -n 's/^Spacewalk backport HEAD: `\([0-9a-fA-F][0-9a-fA-F]*\)`$/\1/p' <<<"$spacewalk_pr_body"
)"

if ((push_branch == 1)) && \
    [[ -n "$remote_head" && -n "$spacewalk_pr_number" ]] && \
    [[ "$spacewalk_pr_body" == *"$source_marker"* ]] && \
    [[ -n "$recorded_target_head" && "$recorded_target_head" == "$target_head" ]] && \
    [[ -n "$recorded_backport_head" && "$recorded_backport_head" == "$remote_head" ]]; then
    if ((open_pr == 1)); then
        pr_body="$(build_pr_body "$remote_head")"
        gh pr edit "$spacewalk_pr_number" \
            --repo SUSE/spacewalk \
            --title "$backport_pr_title" \
            --body "$pr_body" >/dev/null
        if ((draft_pr == 0)) && [[ "$spacewalk_pr_is_draft" == "true" ]]; then
            gh pr ready "$spacewalk_pr_number" --repo SUSE/spacewalk >/dev/null
        fi
    fi
    printf '\nSpacewalk backport is already synchronized with Uyuni HEAD %s.\n%s\n' \
        "$pr_head" "$spacewalk_pr_url"
    exit 0
fi

# Import the reviewed commits directly from the local Uyuni checkout. This avoids
# adding a persistent Uyuni remote to the private Spacewalk clone. With an
# explicit PR number, import the reviewed PR head instead of the naming branch.
source_fetch_ref="$source_branch"
if [[ -n "$source_pr" ]]; then
    source_fetch_ref="$pr_head"
fi
git -C "$spacewalk_repo" fetch "$uyuni_repo" "$source_fetch_ref"
for commit in "${commits[@]}"; do
    git -C "$spacewalk_repo" cat-file -e "$commit^{commit}" ||
        die "PR commit '$commit' could not be imported from the Uyuni checkout"
done

temp_parent="$(mktemp -d -t uyuni-backport-XXXXXX)"
worktree="$temp_parent/worktree"
worktree_added=0
keep_worktree=0
license_hash_path="web/html/src/vendors/npm.licenses.hash.txt"
package_lock_path="web/package-lock.json"

resolve_generated_license_hash_conflict() {
    local -a conflicts=()
    local generated_hash

    mapfile -t conflicts < <(git -C "$worktree" diff --name-only --diff-filter=U)
    ((${#conflicts[@]} == 1)) || return 1
    [[ "${conflicts[0]}" == "$license_hash_path" ]] || return 1
    [[ -f "$worktree/$package_lock_path" ]] || return 1

    generated_hash="$(sha1sum "$worktree/$package_lock_path" | awk '{print $1}')"
    [[ "$generated_hash" =~ ^[0-9a-f]{40}$ ]] || return 1

    printf '%s' "$generated_hash" >"$worktree/$license_hash_path"
    git -C "$worktree" add -- "$license_hash_path"
    printf 'Resolved generated npm license hash conflict from %s: %s\n' \
        "$package_lock_path" "$generated_hash"
}

continue_after_generated_license_hash_conflicts() {
    while resolve_generated_license_hash_conflict; do
        if git -C "$worktree" -c core.editor=true cherry-pick --continue; then
            return 0
        fi
    done
    return 1
}

print_conflict_recovery() {
    printf '\nAutomatic cherry-pick stopped because of conflicts.\n' >&2
    printf 'Continue in this isolated Spacewalk worktree:\n  %s\n' "$worktree" >&2
    printf '\nOpen it in a shell or editor:\n' >&2
    printf '  cd %q\n' "$worktree" >&2
    if command -v code >/dev/null; then
        printf '  code %q\n' "$worktree" >&2
    fi

    printf '\nResolve and finish all queued commits there:\n' >&2
    printf '  git status\n' >&2
    printf '  git diff --name-only --diff-filter=U\n' >&2
    printf '  # Edit the listed files and remove all conflict markers.\n' >&2
    printf '  git add -A\n' >&2
    printf '  git cherry-pick --continue\n' >&2
    printf '  # Repeat status/add/continue if a later commit also conflicts.\n' >&2

    printf '\nAfter the cherry-pick has completely finished:\n' >&2
    printf '  git status\n' >&2
    printf '  git diff --check %q...HEAD\n' "origin/$target_branch" >&2
    printf '  git branch -f %q HEAD\n' "$backport_branch" >&2
    printf '  backport_head="$(git rev-parse HEAD)"\n' >&2
    printf '  pr_body="$(printf %q %q %q %q %q \"$backport_head\")"\n' \
        "$pr_body_format" "$pr_url" "$pr_head" "$target_branch" "$target_head" >&2

    if ((push_branch == 0)); then
        printf '\n--no-push was selected; stop after creating the local backport branch.\n' >&2
        return
    fi

    if [[ -n "$remote_head" ]]; then
        printf '\nReplace the remote branch with lease protection:\n' >&2
        printf '  git push --force-with-lease=%q:%q -u origin %q:%q\n' \
            "refs/heads/$backport_branch" "$remote_head" \
            "$backport_branch" "$backport_branch" >&2
    else
        printf '\nPush the new branch:\n' >&2
        printf '  git push -u origin %q\n' "$backport_branch" >&2
    fi

    if ((open_pr == 0)); then
        printf '\n--no-pr was selected; the workflow is complete after the push.\n' >&2
    elif [[ -n "$spacewalk_pr_number" ]]; then
        printf '\nUpdate the existing Spacewalk PR metadata:\n' >&2
        printf '  gh pr edit %q --repo SUSE/spacewalk --title %q --body "$pr_body"\n' \
            "$spacewalk_pr_number" "$backport_pr_title" >&2
        if ((draft_pr == 0)) && [[ "$spacewalk_pr_is_draft" == "true" ]]; then
            printf '  gh pr ready %q --repo SUSE/spacewalk\n' "$spacewalk_pr_number" >&2
        fi
    elif ((draft_pr == 1)); then
        printf '\nOpen the draft Spacewalk PR:\n' >&2
        printf '  gh pr create --repo SUSE/spacewalk --base %q --head %q --title %q --body "$pr_body" --draft\n' \
            "$target_branch" "$backport_branch" "$backport_pr_title" >&2
    else
        printf '\nOpen the Spacewalk PR:\n' >&2
        printf '  gh pr create --repo SUSE/spacewalk --base %q --head %q --title %q --body "$pr_body"\n' \
            "$target_branch" "$backport_branch" "$backport_pr_title" >&2
    fi
}

cleanup() {
    if ((worktree_added == 1)); then
        if ((keep_worktree == 1)); then
            printf '\nRetained isolated backport worktree:\n  %s\n' "$worktree" >&2
        else
            git -C "$spacewalk_repo" worktree remove --force "$worktree" >/dev/null 2>&1 || true
            rmdir "$temp_parent" >/dev/null 2>&1 || true
        fi
    else
        rmdir "$temp_parent" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

git -C "$spacewalk_repo" worktree add --detach "$worktree" "origin/$target_branch"
worktree_added=1

printf 'Cherry-picking %d commit(s) onto %s...\n' "${#commits[@]}" "$target_branch"
for commit in "${commits[@]}"; do
    read -r -a commit_line <<<"$(git -C "$worktree" rev-list --parents -n 1 "$commit")"
    if ((${#commit_line[@]} > 2)); then
        keep_worktree=1
        die "PR commit '$commit' is a merge commit and cannot be cherry-picked automatically"
    fi
done
if ! git -C "$worktree" cherry-pick "${commits[@]}"; then
    if ! continue_after_generated_license_hash_conflicts; then
        keep_worktree=1
        print_conflict_recovery
        exit 1
    fi
fi

new_backport_head="$(git -C "$worktree" rev-parse HEAD)"
pr_body="$(build_pr_body "$new_backport_head")"
git -C "$spacewalk_repo" branch -f "$backport_branch" "$new_backport_head"

if ((push_branch == 0)); then
    printf '\nRebuilt local Spacewalk branch: %s\n' "$backport_branch"
    if [[ -n "$remote_head" ]]; then
        printf 'Replace the remote branch later with:\n'
        printf '  git -C %q push --force-with-lease=%q:%q -u origin %q:%q\n' \
            "$spacewalk_repo" "refs/heads/$backport_branch" "$remote_head" \
            "$backport_branch" "$backport_branch"
    else
        printf 'Push it later with:\n  git -C %q push -u origin %q\n' \
            "$spacewalk_repo" "$backport_branch"
    fi
    exit 0
fi

if [[ -n "$remote_head" ]]; then
    printf 'Replacing existing Spacewalk branch from the current Uyuni PR history...\n'
    git -C "$spacewalk_repo" push \
        --force-with-lease="refs/heads/$backport_branch:$remote_head" \
        -u origin \
        "$backport_branch:$backport_branch"
else
    git -C "$spacewalk_repo" push -u origin "$backport_branch"
fi

if ((open_pr == 0)); then
    printf '\nPushed Spacewalk branch: %s\n' "$backport_branch"
    exit 0
fi

if [[ -n "$spacewalk_pr_number" ]]; then
    gh pr edit "$spacewalk_pr_number" \
        --repo SUSE/spacewalk \
        --title "$backport_pr_title" \
        --body "$pr_body" >/dev/null
    if ((draft_pr == 0)) && [[ "$spacewalk_pr_is_draft" == "true" ]]; then
        gh pr ready "$spacewalk_pr_number" --repo SUSE/spacewalk >/dev/null
    fi
    printf '\nUpdated Spacewalk PR #%s:\n%s\n' "$spacewalk_pr_number" "$spacewalk_pr_url"
else
    pr_create_args=(
        gh pr create
        --repo SUSE/spacewalk
        --base "$target_branch"
        --head "$backport_branch"
        --title "$backport_pr_title"
        --body "$pr_body"
    )
    if ((draft_pr == 1)); then
        pr_create_args+=(--draft)
    fi
    spacewalk_pr_url="$("${pr_create_args[@]}")"
    if ((draft_pr == 1)); then
        printf '\nCreated draft Spacewalk PR:\n%s\n' "$spacewalk_pr_url"
    else
        printf '\nCreated Spacewalk PR:\n%s\n' "$spacewalk_pr_url"
    fi
fi

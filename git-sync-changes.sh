#!/bin/bash
#
# Copyright 2017 Google Inc. All rights reserved.
# 
# Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except
# in compliance with the License. You may obtain a copy of the License at
# 
# http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software distributed under the License
# is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express
# or implied. See the License for the specific language governing permissions and limitations under
# the License.

current_branch() {
  git symbolic-ref HEAD
}

current_head() {
  git show-ref --heads $(current_branch) | cut -d ' ' -f 1
}

current_user() {
  user_email=$(git config --get user.email)
  echo "${user_email:-${USER}}"
}

check_remote() {
  git remote get-url origin 2>/dev/null >&2 && return 0
  echo "Remote ${remote} does not exist... nothing to sync" >&2 ; return 1
}

remote="${1:-origin}"
user="${2:-$(current_user)}"
branch="${3:-$(current_branch)}"

if [ -z "$(current_head)" ]; then
  echo "Empty repository; nothing to do" >&2
  exit 0
fi
check_remote "${remote}" || exit 0

local_sync_ref() {
  echo "refs/sync/${user}/${branch}"
}

remote_sync_ref() {
  echo "refs/sync_remotes/${remote}/${user}/$(current_branch)"
}

fetch_remote_changes() {
  local_ref="$(local_sync_ref)"
  remote_ref="$(remote_sync_ref)"

  git fetch "${remote}" "+${local_ref}:${remote_ref}" 2>/dev/null >&2 || return 0
  local_commit="$(git show-ref ${local_ref} | cut -d ' ' -f 1)"
  remote_commit="$(git show-ref ${remote_ref} | cut -d ' ' -f 1)"
  if [ "${local_commit}" == "${remote_commit}" ]; then
    # Everything is already in sync.
    return 1
  fi

  merge_base="$(git merge-base ${local_ref} ${remote_ref})"
  if [ "${remote_commit}" == "${merge_base}" ]; then
    # The remote changes have already been included in our local changes.
    # All that is left is for us to potentially push the local changes.
    return 0
  fi

  # Create a temporary directory in which to perform the merge
  maindir=$(pwd)
  tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'sync-changes')
  git worktree add "${tempdir}" 2>/dev/null >&2
  cd "${tempdir}"

  # Perform the merge, favoring our changes in the case of conflicts, and
  # update the local ref.
  git merge --ff "${local_ref}" 2>/dev/null >&2
  git merge -s recursive -X ours "${remote_ref}" 2>/dev/null >&2
  git commit -a -m "Merge remote changes" 2>/dev/null >&2
  tempbranch="$(current_branch)"
  git update-ref "${local_ref}" "${tempbranch}" 2>/dev/null >&2

  # Copy any remote changes to our working dir
  find -type d -and -not -path "./.git/*" -and -not -name '.git' -exec 'mkdir' '-p' "${maindir}/{}" ';'
  find -not -type d -and -not -path "./.git/*" -and -not -name '.git' -exec 'cp' '{}' "${maindir}/"'{}' ';'

  # Cleanup post merge
  cd "${maindir}"
  rm -rf "${tempdir}"
  git update-ref -d "${tempbranch}"
  git worktree prune
  return 0
}

push_local_changes() {
  local_ref="$(local_sync_ref)"
  remote_ref="$(remote_sync_ref)"
  remote_commit="$(git show-ref ${remote_ref} | cut -d ' ' -f 1)"

  if [ -z "$(git diff ${local_ref} ${branch})" ] && [ -z "$(git diff ${remote_commit} ${branch})" ]; then
    # We have no changes against the branch, either locally or remotely.
    #
    # Clean up by reseting the change history.
    git update-ref "${local_ref}" "${branch}"
  fi

  git push "${remote}" --force-with-lease="${local_ref}:${remote_commit}" "${local_ref}:${local_ref}" 2>/dev/null >&2 || return 0
}

# Create an undo-buffer-like commit of the local changes.
#
# This differs from `git stash` in that multiple changes can
# be chained together.
#
# The resulting commit is stored in refs/sync/${user}/${branch}
stash_changes() {
  local_ref="$(local_sync_ref)"
  local_commit="$(git show-ref ${local_ref} | cut -d ' ' -f 1)"
  local_diff="$(git diff ${branch})"
  if [ -z "${local_commit}" ] && [ -z "${local_diff}" ]; then
    # We have neither local modifications nor previously saved changes
    return 0
  fi
  if [ -z "${local_commit}" ]; then
    # We do not have previously saved changes, so just take a stash
    # and save it.
    changes_stash=$(git stash create "Save local changes")
    git update-ref "${local_ref}" "${changes_stash}" 2>/dev/null >&2
    return 0
  fi

  new_changes="$(git diff ${local_commit})"
  if [ -z "${new_changes}" ]; then
    # We have no changes since the last time we saved.
    return 0
  fi

  changes_stash=$(git stash create "Save local changes")
  changes_tree=$(git cat-file -p "${changes_stash}" | head -n 1 | cut -d ' ' -f 2)
  changes_commit=$(git commit-tree -p "$(current_head)" -p "${local_commit}" -m "Save local changes" "${changes_tree}")
  git update-ref "${local_ref}" "${changes_commit}" 2>/dev/null >&2
}

stash_changes
fetch_remote_changes || exit 0
push_local_changes

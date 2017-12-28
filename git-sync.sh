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
  git show-ref $(current_branch) | cut -d ' ' -f 1
}

current_user() {
  user_email=$(git config --get user.email)
  echo "${user_email:-${USER}}"
}

local_sync_ref() {
  user="${1:-$(current_user)}"
  branch="${2:-$(current_branch)}"
  echo "refs/sync/${user}/${branch}"
}

remote_sync_ref() {
  remote="${1:-origin}"
  user="${2:-$(current_user)}"
  branch="${3:-$(current_branch)}"
  echo "refs/sync_remotes/${remote}/${user}/$(current_branch)"
}

check_remote() {
  git remote get-url origin 2>/dev/null >&2 && return 0
  echo "Remote ${remote} does not exist... nothing to sync" >&2 ; return 1
}

fetch_remote_changes() {
  remote="${1:-origin}"
  user="${2:-$(current_user)}"
  branch="${3:-$(current_branch)}"
  local_ref="$(local_sync_ref ${user} ${branch})"
  remote_ref="$(remote_sync_ref ${remote} ${user} ${branch})"

  git fetch "${remote}" "+${local_ref}:${remote_ref}" 2>/dev/null >&2 || return 0

  local_commit="$(git show-ref ${local_ref} | cut -d ' ' -f 2)"
  merge_base="$(git merge-base ${local_ref} ${remote_ref})"
  if [ "${local_commit}" == "${merge_base}" ]; then
    # We have already merged in the remote ref, so there is nothing left to do
    return 1;
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

  # Copy an remote changes to our working dir
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
  remote="${1:-origin}"
  user="${2:-$(current_user)}"
  branch="${3:-$(current_branch)}"
  local_ref="$(local_sync_ref ${user} ${branch})"

  git push "${remote}" "${local_ref}:${local_ref}" 2>/dev/null >&2 || return 0
}

stash_changes() {
  user="${1:-$(current_user)}"
  branch="${2:-$(current_branch)}"
  local_ref="$(local_sync_ref ${user} ${branch})"

  # Create a temporary directory in which to create the changes commit
  maindir=$(pwd)
  tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'sync-changes')
  git worktree add "${tempdir}" 2>/dev/null >&2
  cd "${tempdir}"
  git merge -s recursive -X theirs "${local_ref}" 2>/dev/null >&2 || true

  # Copy the local changes to that temp directory
  cd "${maindir}"
  find -type d -and -not -path "./.git/*" -and -not -name '.git' -exec 'mkdir' '-p' "${tempdir}/{}" ';'
  find -not -type d -and -not -path "./.git/*" -and -not -name '.git' -exec 'cp' '{}' "${tempdir}/"'{}' ';'

  # Create the changes commit and update the corresponding ref
  cd "${tempdir}"
  git add ./ 2>/dev/null >&2
  git commit -a -m "Save local changes" 2>/dev/null >&2
  git update-ref "${local_ref}" "$(current_head)" 2>/dev/null >&2
  tempbranch="$(current_branch)"

  # Cleanup the temporary directory and branch that we used
  cd "${maindir}"
  rm -rf "${tempdir}"
  git update-ref -d "${tempbranch}"
  git worktree prune
}

remote="${1:-origin}"
user="${2:-$(current_user)}"
branch="${3:-$(current_branch)}"

if [ -z "$(current_head)" ]; then
  echo "Empty repository; nothing to do" >&2
  exit 0
fi
check_remote "${remote}" || return 0

stash_changes "${user}" "${branch}"
fetch_remote_changes "${remote}" "${user}" "${branch}" || return 0
push_local_changes "${remote}" "${user}" "${branch}"

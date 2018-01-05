#!/bin/bash
#
# Copyright 2018 Google Inc. All rights reserved.
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

# Set up our test directories and automatically cleanup on exit
maindir=$(pwd)
test_remote=$(mktemp -d 2>/dev/null || mktemp -d -t 'sync-changes')
test_client_1=$(mktemp -d 2>/dev/null || mktemp -d -t 'sync-changes')
test_client_2=$(mktemp -d 2>/dev/null || mktemp -d -t 'sync-changes')
trap "{ cd ${maindir}; rm -rf ${test_remote}; rm -rf ${test_client_1}; rm -rf ${test_client_2}; }" EXIT

sync_cmd="${maindir}/git-sync-changes"

setup_repo() {
  echo "Setting up remote repository..."
  cd "${test_remote}"
  git init 2>/dev/null >&2
  echo "# Example README" >> README.md
  git add ./ 2>/dev/null >&2
  git commit -a -m 'Initial commit with a README file' 2>/dev/null >&2

  echo "Setting up the first test client..."
  cd "${test_client_1}"
  git init 2>/dev/null >&2
  git remote add origin "${test_remote}" 2>/dev/null >&2
  git fetch origin 2>/dev/null >&2
  git checkout -t "origin/master" 2>/dev/null >&2

  echo "Setting up the second test client..."
  cd "${test_client_2}"
  git init 2>/dev/null >&2
  git remote add origin "${test_remote}" 2>/dev/null >&2
  git fetch origin 2>/dev/null >&2
  git checkout -t "origin/master" 2>/dev/null >&2
}

test_initial_sync() {
  echo "Testing syncing a new repository..."
  cd "${test_client_1}"
  if [ "$(git ls-remote origin | grep 'refs/synced_client')" != "" ]; then
    echo $'\tinitial sync test run against an already initialized remote'
    return 1
  fi
  ${sync_cmd} || return 1

  cd "${test_client_2}"
  if [ "$(git ls-remote origin | grep 'refs/synced_client')" == "" ]; then
    echo $'\tinitial sync test failed to initialize the remote'
    return 1
  fi
  ${sync_cmd} || return 1

  user_email="$(git config --get user.email)"
  if [ "$(git show-ref refs/synced_remote_client/origin/${user_email}/refs/heads/master)" == "" ]; then
    echo $'\tinitial sync test failed to sync the remote commit'
    return 1
  else
    echo $'\tinitial sync test passed'
  fi
}

test_modified_file() {
  echo "Testing syncing a file modification..."
  cd "${test_client_1}"
  readme_txt="Additional text added to the README"
  echo "${readme_txt}" >> README.md
  ${sync_cmd} || return 1

  cd "${test_client_2}"
  ${sync_cmd} || return 1
  if [ "$(tail -n 1 README.md)" != "${readme_txt}" ]; then
    return 1
  else
    echo $'\tfile modification sync test passed'
  fi
}

test_new_file() {
  echo "Testing syncing a new file..."
  cd "${test_client_1}"
  second_readme_txt="Additional README"
  echo "${second_readme_txt}" >> README_2.md
  ${sync_cmd} || return 1

  cd "${test_client_2}"
  ${sync_cmd} || return 1
  if [ "$(cat README_2.md)" != "${second_readme_txt}" ]; then
    return 1
  else
    echo $'\tnew file sync test passed'
  fi
}

test_rollback_changes() {
  echo "Testing syncing a client with reverted changes..."
  cd "${test_client_1}"
  git reset HEAD ./ 2>/dev/null >&2
  git checkout -- ./  2>/dev/null >&2
  for file in `git status --porcelain=1 | grep '??' | cut -d ' ' -f 2`; do
   rm "${file}"
  done
  ${sync_cmd} || return 1

  cd "${test_client_2}"
  ${sync_cmd} || return 1
  if [ -n "$(git status --porcelain=1)" ]; then
    git status
    ls -al
    return 1
  else
    echo $'\treverted changes sync test passed'
  fi
}

test_sync_then_commit() {
  echo "Testing syncing a file modification..."
  cd "${test_client_1}"
  readme_txt="Additional text added to the README"
  echo "${readme_txt}" >> README.md
  second_readme_txt="Additional README"
  echo "${second_readme_txt}" >> README_2.md
  ${sync_cmd} || return 1

  cd "${test_client_2}"
  ${sync_cmd} || return 1
  if [ "$(cat README_2.md)" != "${second_readme_txt}" ]; then
    return 1
  elif [ "$(tail -n 1 README.md)" != "${readme_txt}" ]; then
    return 1
  fi

  cd "${test_client_1}"
  git add ./
  git commit -a -m 'Second commit' 2>/dev/null >&2
  ${sync_cmd} || return 1
  log=`git log`
  status=`git status`

  cd "${test_client_2}"
  ${sync_cmd} || return 1

  if [ "$(git log)" != "${log}" ]; then
    echo $'\t'"Log mismatch: '$(git log)' vs '${log}'" >&2
    return 1
  elif [ "$(git status)" != "${status}" ]; then
    echo $'\t'"Status mismatch: '$(git status)' vs '${status}'" >&2
    return 1
  else
    echo $'\tfile sync and then commit test passed'
  fi
}

test_filename_with_space() {
  echo "Testing syncing a file with space in its name"
  cd "${test_client_1}"
  third_readme_txt="Additional README with space in its name"
  echo "${third_readme_txt}" >> README\ 3.md
  ${sync_cmd} || return 1

  cd "${test_client_2}"
  ${sync_cmd} || return 1
  if [ "$(cat README\ 3.md)" != "${third_readme_txt}" ]; then
    return 1
  fi

  cd "${test_client_1}"
  git add ./
  git commit -a -m 'Third commit' 2>/dev/null >&2
  ${sync_cmd} || return 1
  log=`git log`
  status=`git status`

  cd "${test_client_2}"
  ${sync_cmd} || return 1

  if [ "$(git log)" != "${log}" ]; then
    echo $'\t'"Log mismatch: '$(git log)' vs '${log}'" >&2
    return 1
  elif [ "$(git status)" != "${status}" ]; then
    echo $'\t'"Status mismatch: '$(git status)' vs '${status}'" >&2
    return 1
  else
    echo $'\tfilename with space sync test passed'
  fi
}

exit_with_message() {
  echo $'\t'"$1"
  exit 1
}

setup_repo
test_initial_sync || exit_with_message "testing the initial sync failed"
test_modified_file || exit_with_message "testing a modified file failed"
test_new_file || exit_with_message "testing a new file failed"
test_rollback_changes || exit_with_message "testing a rollback failed"
test_sync_then_commit || exit_with_message "testing a sync and commit failed"
test_filename_with_space || exit_with_message "testing a sync with a space in a file name failed"

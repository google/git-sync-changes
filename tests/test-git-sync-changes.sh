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

sync_cmd="${maindir}/git-sync-changes.sh"

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

test_modified_file() {
  echo "Testing syncing a file modification..."
  cd "${test_client_1}"
  readme_txt="Additional text added to the README"
  echo "${readme_txt}" >> README.md
  ${sync_cmd}

  cd "${test_client_2}"
  ${sync_cmd}
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
  ${sync_cmd}

  cd "${test_client_2}"
  ${sync_cmd}
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
  ${sync_cmd}

  cd "${test_client_2}"
  ${sync_cmd}
  if [ -n "$(git status --porcelain=1)" ]; then
    git status
    ls -al
    return 1
  else
    echo $'\treverted changes sync test passed'
  fi
}

setup_repo
test_modified_file || exit 1
test_new_file || exit 1
test_rollback_changes || exit 1

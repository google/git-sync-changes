# Collaborative editing for git repositories

This repository implements shared worktrees for git.

This is done by storing the worktree state in the repository itself.

The result is that anyone with push permissions on the repository
can sync their local worktree with that shared worktree, and then
view and edit pending changes prior to committing them.

## Usage

The shared worktree functionality is implemented with a new git
command called `git-sync-changes`. Running that command will sync
pending changes between your local worktree and the shared worktree,
leaving the two in the same state.

The command takes two optional parameters, the remote repository
storing the shared worktree, and the name of that tree.

For example:

```sh
git sync-changes origin shared-work
```

will sync your local worktree with the worktree named `shared-work`
in the remote named `origin`.

If the worktree name is not specified, the tool will default to
a worktree named after the current user and the current checked-out
branch.

If the remote is not specified, then it defaults to `origin`.

Each invocation of the command only performs a single sync, so to
keep your worktree continuously updated, run it periodically.

For instance, you could run the command in a loop with something
like:

```sh
( while [ 1 ]; do
    git sync-changes
	sleep 30
  done)
```

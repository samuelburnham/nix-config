# Dev VM isolation (handoff)

Goal: agents in the dev microVM can edit, commit and push freely, and a
malicious agent there cannot run code on the desktop host. This note records
the design Sam agreed, what is done, and what is left.

## Design

1. **No shared host directories.** `microvm.shares` is empty. The guest's
   base Nix store is an immutable EROFS image built on the host. All working
   repos live in the VM's own `~/repos`, on its persistent `home.img` volume.
   - VM filesystem writes stay in its disk images, so host tools do not see
     guest-written repository files. That closes the shared-directory
     injection class: `.git/config` keys (`core.fsmonitor`,
     `core.sshCommand`, filters), hooks, `.envrc`, devshell `shellHook`s,
     `build.rs` and lakefiles run by LSPs, and project agent config
     (`.claude/`, `.codex/`, `.mcp.json`).
2. **The authoritative nix-config checkout stays on the host,** in
   `~/repos/nix-config`, alongside any other trusted host repositories.
   Host agents edit it, and `rebuild` runs it as root.
   - The VM has no writable access to that checkout. The CLAUDE.md memory section in
     `home/modules/claude.nix` tells VM agents to hand nix-config edits to Sam.
   - Host repositories must not be writable by the VM. That keeps the
     host's existing trust of `~/repos` correct again: Ghostty's start
     directory, Codex `trustedRoots`, Claude `Read`/`Edit(~/repos/**)`, the
     restic scan.
3. **The VM pushes to GitHub itself.** `GH_TOKEN` (sops secret `gh-token`,
   forwarded per session by `ssh-dev-vm` and `ssh-bench` in
   `home/modules/gui.nix`) becomes a fine-grained PAT shared with bench boxes:
   - It is created by `samuelburnham`, with argumentcomputer as the resource
     owner and only the development repositories in scope, excluding nix-config.
   - It has Contents write and only other necessary permissions, but **no
     Administration**, so it cannot lift rulesets.
   - Git pushes over HTTPS through the `gh` credential helper and the
     `insteadOf` rewrite in `home/profiles/dev-vm.nix`.
   - Sam opens PRs by hand.
4. **`main` is protected on GitHub.** Add a ruleset on the argumentcomputer
   repos: require a PR, block force-pushes and deletions, **no bypass
   actors**. Requiring a PR alone does not enforce human approval: a
   Contents-write token can also call the merge API. Enforce required reviews
   with an identity unavailable to the VM if human approval is required.

5. **Use a private guest store.** `microvm.storeOnDisk = true` builds
   a read-only EROFS image containing the guest system closure: NixOS, its
   home-manager generation, nvim, tmux config and their dependencies. The
   runner attaches that image as a read-only block device. No virtiofsd is
   needed, and unrelated host store paths are unavailable to the guest.
   - `rebuild` updates the host and guest configurations.
     `restartIfChanged = false` keeps the running VM on its booted image.
     Save work, then run `sudo systemctl restart microvm@dev` to use the
     new generation.
   - Packages absent from the image are fetched or built into the guest's
     writable store overlay. They cannot be read from the host store.
   - `home.img`, the writable store overlay and the persistent Nix DB remain
     separate volumes. Existing overlay whiteouts and stale DB entries still
     need handling when the base changes.

   Network, clipboard and credential restrictions remain separate controls.

### Accepted risk

Malicious code can reach GitHub, and CI secrets can be exposed to
agent-written code. Sam does not review diffs before opening PRs, so a host
push gate would add no review. Withholding Workflows or Actions permissions
would not help: code run by existing workflows reaches the same secrets. For
example, ix `nix.yml` runs `lake build` after `cachix-action` has received
its token. A PR requirement guards direct updates to `main`; human approval
requires the additional review policy described above.

### Rejected alternatives

- **Sharing `~/repos` with a host git wrapper:** a per-call shadow `GIT_DIR`
  with an allowlisted config. It was about 380 lines, every new git config
  key that runs a command would be a bypass, and it did nothing about the
  non-git vectors. Deleted.
- **Sharing `~/repos` with nix-config masked** through `InaccessiblePaths`
  on `microvm-virtiofsd@dev`. Every other host tool that touches `~/repos`
  stayed exposed (Starship's `git status`, Codex trust, wlogout icons).
- **Pushing from a host-owned mirror** that fetches from the VM over ssh
  (`vm-push`), or from personal forks. Both add a review step or a secret
  boundary that the accepted risk above makes moot.
- **UID mapping** so git's `safe.directory` refuses VM repos. Moot without a
  share.

## Status (uncommitted in the working tree)

Done:

- `hosts/desktop/microvm.nix`: no host directories are shared; `storeOnDisk`
  provides the guest store as an EROFS image.
  The guest creates `/home/sam/repos` through tmpfiles.
- Deleted `home/modules/git-shared-repos.nix` and
  `scripts/git-shared-repos.sh`.
- `home/profiles/dev-vm.nix`: comments describe the push-capable token, and
  the auto-allow `Bash(gh api:*)` is removed (it was safe only for a
  read-only token).
- `common/host.nix`: the `gh-token` comment no longer says read-only.
- `home/modules/claude.nix`: one line saying nix-config is host-only.
- `docs/backup.md`: VM repos are in `home.img`, so they are not backed up.
- The full desktop system (`nixosConfigurations.nixos`) evaluates. Nothing
  has been built or switched on the desktop.

Other uncommitted changes in the tree are unrelated (nvf LaTeX setup in
`nvim.nix`, zathura in `gui.nix`, `.envrc`, Claude permission rules, and
Sam's own profile edits). Do not fold them into this change.

## Remaining work

Needs a decision or a fix before migrating:

- **wlogout icons.** `home/modules/hyprland.nix` loads them from
  `~/repos/clones/hyprland/catppuccin/wlogout/...`. Either keep that clone
  on the host or move the icons into the Nix store (a flake input or
  package). Moving them is cleaner.
- **Backup of VM work.** `home.img` is not in restic, so unpushed commits,
  stashes and uncommitted work are lost if the image is. Options:
  - Rely on pushing branches, which is now possible from the VM.
  - Have the host back up `home.img` while the VM is stopped, or from a
    filesystem snapshot.
  - Run restic inside the VM against a separate repository. This must not be
    a writable host path, or it reopens a host-writable surface.
- **`home.img` size.** It is a 128 GiB sparse ceiling. Check host free space
  with `df -h /var/lib/microvms/dev` and guest home free space with
  `ssh dev-vm 'df -h /home'`. Account for the selected repositories without
  recursively scanning the entire research-clone tree or Nix store. Growing
  an existing image needs a manual `truncate` plus `resize2fs` with the VM stopped.

Hardening that remains independent of the share:

- **Clipboard.** `clipboard-read = "allow"` in `home/modules/ghostty.nix`
  lets the VM read the host clipboard silently over OSC 52, including copied
  passwords. `ask` or `deny` fixes it. The existing comment says `ask` fails
  silently when the dialog is dismissed, so this is Sam's call.
- **Optional:** firewall the VM off the LAN. Today it NATs out with full LAN
  reach.
- **Optional simplification:** the restic git-ignore scanner in
  `hosts/desktop/restic.nix` was isolated because `~/repos` was VM-writable.
  It now only sees host repos, so the isolation is belt-and-braces. Leave it.

Workflow changes to expect:

- Host tools cannot see VM files. To view a PDF built in the VM with host
  zathura, `scp dev-vm:repos/ix-paper/result/paper.pdf .`.
- Research clones needed by VM tools live in the VM. Independently maintained,
  trusted clones may remain on the host, including the wlogout icon source.

Sam does these on GitHub:

- Create the fine-grained PAT, then store it with `sops secrets/secrets.yaml`
  (`gh-token`). The same secret renders `NIX_CONFIG` access-tokens, so
  private flake inputs owned outside argumentcomputer would stop fetching in
  the VM.
- Add the `main` rulesets.

## Migration

On the desktop, in order:

1. Choose the repositories to migrate and the trusted repositories to retain
   on the host. Check host and guest free space as described above. Stop writes
   to migrating repositories for the final copy, including linked worktrees.
2. `rebuild` builds and installs the guest image. Save VM work, then run
   `sudo systemctl restart microvm@dev`. The VM does not restart on a host
   rebuild (`restartIfChanged = false`). Its virtiofsd service stops with the
   old VM and has no daemon to start for the new configuration. After the
   restart the VM's `~/repos` is the directory on `home.img`; preserve anything
   already there. Removing the share does not copy the previously shared files.
3. Copy the selected repositories into the VM's `~/repos`, checking for
   destination collisions first. Preserve Git metadata, uncommitted files,
   stashes, and linked worktrees. For an individual repository:

   ```sh
   tar -C ~/repos -cf - REPOSITORY | ssh dev-vm 'tar -C ~/repos -xpf -'
   ```

4. Verify the copies, uncommitted state, stashes and linked-worktree paths in
   the VM, and confirm backup coverage. Only then remove the migrated copies
   from the **host**. Retain host `nix-config` and other trusted repositories,
   including `clones/hyprland` while wlogout depends on it. Keep the VM's
   `~/repos` and its repositories intact.

## Verify

Inside the VM:

```sh
findmnt -t virtiofs                # no mounts
findmnt /nix/.ro-store             # read-only EROFS block device
findmnt /home                      # persistent guest home volume
git -C ~/repos/REPOSITORY status   # migrated work is intact
```

Inspect GitHub rulesets and token permissions before using the write-capable
token. Branch protection and human approval requirements are independent of
the VM's filesystem isolation.

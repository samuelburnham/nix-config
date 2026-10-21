# Dev VM isolation (handoff)

Goal: agents in the dev microVM can edit, commit and push freely, and a
malicious agent there cannot run code on the desktop host. This note records
the design Sam agreed, what is done, and what is left.

## Design

1. **No shared repositories.** The only host directory the VM sees is
   `/nix/store`, read-only over virtiofs (`hosts/desktop/microvm.nix`). All
   working repos live in the VM's own `~/repos`, on its persistent `home.img`
   volume.
   - Nothing the VM writes lands on a host path. That rules out the whole
     injection class: `.git/config` keys (`core.fsmonitor`,
     `core.sshCommand`, filters), hooks, `.envrc`, devshell `shellHook`s,
     `build.rs` and lakefiles run by LSPs, and project agent config
     (`.claude/`, `.codex/`, `.mcp.json`).
2. **nix-config lives only on the host,** in `~/repos/nix-config`, and is
   edited by host agents. `rebuild` runs it as root.
   - The VM has no copy. The CLAUDE.md memory section in
     `home/modules/claude.nix` tells VM agents to hand nix-config edits to Sam.
   - The host's `~/repos` holds nothing else the VM wrote. That makes the
     host's existing trust of `~/repos` correct again: Ghostty's start
     directory, Codex `trustedRoots`, Claude `Read`/`Edit(~/repos/**)`, the
     restic scan.
3. **The VM pushes to GitHub itself.** `GH_TOKEN` (sops secret `gh-token`,
   forwarded per session by `ssh-dev-vm` in `home/modules/gui.nix`) becomes a
   fine-grained PAT:
   - It is owned by `samuelburnham` and scoped to the argumentcomputer repos
     in use.
   - It has Contents write and whatever else is convenient, but **no
     Administration**, so it cannot lift rulesets.
   - Git pushes over HTTPS through the `gh` credential helper and the
     `insteadOf` rewrite in `home/profiles/dev-vm.nix`.
   - Sam opens PRs by hand.
4. **`main` is protected on GitHub.** Add a ruleset on the argumentcomputer
   repos: require a PR, block force-pushes and deletions, **no bypass
   actors**. Whether an admin bypass carries over to a PAT is unverified,
   hence no bypass.

5. **Keep the read-only store share.** The host builds the guest's whole
   closure: NixOS, its home-manager generation, nvim, tmux config, Ghostty
   terminfo. The guest needs those paths, and the shared store also serves
   as the lower layer for devshell builds in the VM, so toolchains already on
   the host are not fetched again.
   - Integrity: virtiofsd runs as root, and guest root can remount the guest
     side read-write. So the share sets `readOnly = true`, which passes
     virtiofsd `--readonly`, on top of NixOS's read-only `/nix/store` bind
     mount.
   - Confidentiality: the VM can read every host store path. Store paths are
     world-readable on the host anyway, so keep secrets out of the store
     (sops already renders them under `/run`).
   - The alternative is `microvm.storeOnDisk = true`: an erofs image of
     exactly the guest closure, attached as a block device. It removes
     virtiofsd entirely and hides host-only paths. The costs:
     - an image rebuild on every guest closure change;
     - the image in the Cachix CI build;
     - devshell inputs fetched again into the overlay, instead of being read
       from the host store.

     Worth it only if virtiofsd itself, or reading the host store, is in the
     threat model.

### Accepted risk

Malicious code can reach GitHub, and CI secrets can be exposed to
agent-written code. Sam does not review diffs before opening PRs, so a host
push gate would add no review. Withholding Workflows or Actions permissions
would not help: code run by existing workflows reaches the same secrets. For
example, ix `nix.yml` runs `lake build` after `cachix-action` has received
its token. What stays guarded is `main`: code reaches it only through a PR
Sam merges.

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

- `hosts/desktop/microvm.nix`: the `repos` share is removed, leaving only
  `ro-store`, now with `readOnly = true`. Comments are updated. The guest already creates
  `/home/sam/repos` through tmpfiles.
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
- **`home.img` size.** It is a 128 GiB sparse ceiling. Check
  `du -sh ~/repos` on the desktop first. Growing an existing image needs a
  manual `truncate` plus `resize2fs` with the VM stopped.

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
- Research clones (`~/repos/clones`) move into the VM, so host agents will
  not find them.

Sam does these on GitHub:

- Create the fine-grained PAT, then store it with `sops secrets/secrets.yaml`
  (`gh-token`). The same secret renders `NIX_CONFIG` access-tokens, so
  private flake inputs owned outside argumentcomputer would stop fetching in
  the VM.
- Add the `main` rulesets.

## Migration

On the desktop, in order:

1. Check that the repos fit: `du -sh ~/repos` (excluding nix-config) against
   the free space in `/var/lib/microvms/dev` and the `home.img` ceiling.
2. `rebuild`, then
   `sudo systemctl restart microvm-virtiofsd@dev microvm@dev`. The VM does
   not restart on a host rebuild (`restartIfChanged = false`). After the
   restart the VM's `~/repos` is the empty directory on `home.img`.
3. Copy the repos in. Add `--exclude` flags for build output (`target`,
   `.lake/build`, `result`) if space is tight.

   ```sh
   tar -C ~/repos --exclude=./nix-config -cf - . | ssh dev-vm 'tar -C ~/repos -xpf -'
   ```

4. Verify in the VM (`git -C ~/repos/ix status`, a build), then delete
   everything except `nix-config` from the host's `~/repos`. Keep
   `clones/hyprland` until the wlogout icons are moved.

## Verify

Inside the VM:

```sh
mount | grep virtiofs              # only /nix/.ro-store
sudo mount -o remount,rw /nix/.ro-store; sudo touch /nix/.ro-store/x   # touch fails
ls ~/repos/nix-config              # does not exist
git push origin HEAD:main          # rejected by the ruleset
git push origin HEAD:some-branch   # succeeds
```

{
  config,
  lib,
  pkgs,
  username,
  ...
}:
let
  home = "/home/${username}";
  repositories = "${home}/repos";
  repository = "/mnt/onetouch/NixOS-restic";
  scanner = "restic-gitignore-onetouch";
  manifestDirectory = "/run/${scanner}";
  manifest = "${manifestDirectory}/paths";
  excludes = "/run/restic-backups-onetouch/gitignore-excludes";
  helper = "${pkgs.python3}/bin/python3 -I ${../../scripts/restic-gitignore.py}";

  # A private root exposes only explicit bind mounts. Blocking socket syscalls
  # also prevents access to host AF_UNIX sockets through read-only source mounts.
  sandbox = {
    TemporaryFileSystem = "/:ro";
    # ProtectSystem=strict installs a competing mount at / that hides the tmpfs.
    ProtectSystem = false;
    BindReadOnlyPaths = [
      "/nix/store"
      "/etc/passwd"
      "/etc/group"
      "/etc/localtime"
    ];
    PrivateTmp = true;
    PrivateDevices = true;
    PrivateNetwork = true;
    PrivatePIDs = true;
    ProtectProc = "invisible";
    ProcSubset = "pid";
    NoNewPrivileges = true;
    RestrictNamespaces = true;
    RestrictSUIDSGID = true;
    LockPersonality = true;
    SystemCallArchitectures = "native";
    SystemCallFilter = [
      "@system-service"
      "~@network-io @mount @privileged"
    ];
    SystemCallErrorNumber = "EPERM";
    UMask = "0077";
    WorkingDirectory = "/";
  };
in
{
  users.users.restic = {
    isSystemUser = true;
    uid = config.ids.uids.restic;
    group = "restic";
  };
  users.groups.restic.gid = config.ids.gids.restic;

  # exFAT ownership is mount-wide: Sam owns the drive, and the backup group can
  # write it. The service namespace exposes only the Restic repository writable.
  fileSystems."/mnt/onetouch" = {
    device = "/dev/disk/by-uuid/5EAC-B331";
    fsType = "exfat";
    options = [
      "nofail"
      "x-systemd.automount"
      "x-systemd.idle-timeout=600"
      "x-gvfs-show"
      "uid=1000"
      "gid=${toString config.ids.gids.restic}"
      "dmask=0007"
      "fmask=0117"
      "nosuid"
      "nodev"
      "noexec"
    ];
  };

  sops.secrets.restic-password = {
    mode = "0400";
    owner = username;
  };

  # Interactive restores use the source secret and the caller's default cache;
  # the service's credential copy exists only while its unit is running.
  environment.systemPackages = [
    (pkgs.writeShellScriptBin "restic-onetouch" ''
      export RESTIC_REPOSITORY=${lib.escapeShellArg repository}
      export RESTIC_PASSWORD_FILE=${lib.escapeShellArg config.sops.secrets.restic-password.path}
      exec ${lib.getExe config.services.restic.backups.onetouch.package} "$@"
    '')
  ];

  # systemd opens stdout before dropping privileges. The scanner gets a write
  # descriptor, but cannot replace the manifest or access its parent directory.
  systemd.tmpfiles.rules = [ "d ${manifestDirectory} 0750 root restic -" ];
  systemd.services.${scanner} = {
    description = "Collect Git-ignored backup paths in an isolated filesystem";
    unitConfig.RequiresMountsFor = "/mnt/onetouch";
    serviceConfig = sandbox // {
      Type = "oneshot";
      User = username;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      BindReadOnlyPaths = sandbox.BindReadOnlyPaths ++ [ repositories ];
      ExecStart = "${helper} scan ${repositories} ${pkgs.git}/bin/git";
      StandardOutput = "truncate:${manifest}";
      StandardError = "journal";
      TimeoutStartSec = "15min";
      MemoryMax = "512M";
      TasksMax = 64;
      LimitFSIZE = "64M";
    };
  };

  services.restic.backups.onetouch = {
    inherit repository;
    user = "restic";
    createWrapper = false;
    passwordFile = "/run/credentials/restic-backups-onetouch.service/password";
    paths = [ home ];
    exclude = [
      "${home}/.cache"
      # Includes local saves; saves without a Steam Cloud copy are not backed up.
      "${home}/.local/share/Steam"
      "${home}/.local/share/containers"
    ];
    backupPrepareCommand = "${helper} encode ${repositories} ${manifest} ${excludes}";
    extraBackupArgs = [ "--exclude-file=${excludes}" ];
    timerConfig = {
      OnCalendar = "*-*-* 12:00:00";
      # Catch up when the timer starts after downtime. A disconnected drive
      # fails the run; reconnecting it does not itself trigger another attempt.
      Persistent = true;
    };
    pruneOpts = [
      "--keep-daily 7"
      "--keep-weekly 4"
      "--keep-monthly 6"
    ];
    runCheck = true;
  };

  systemd.services.restic-backups-onetouch = {
    requires = [ "${scanner}.service" ];
    after = [ "${scanner}.service" ];
    unitConfig.RequiresMountsFor = "/mnt/onetouch";
    serviceConfig = sandbox // {
      Group = "restic";
      # https://restic.readthedocs.io/en/stable/080_examples.html#using-ambient-capabilities-with-systemd
      AmbientCapabilities = [ "CAP_DAC_READ_SEARCH" ];
      CapabilityBoundingSet = [ "CAP_DAC_READ_SEARCH" ];
      LoadCredential = "password:${config.sops.secrets.restic-password.path}";
      BindReadOnlyPaths = sandbox.BindReadOnlyPaths ++ [
        home
        manifestDirectory
      ];
      BindPaths = [ repository ];
      ReadWritePaths = [ repository ];
      RuntimeDirectoryMode = "0700";
    };
  };
}

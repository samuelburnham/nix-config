# Hyprland workstation overlay — imported by hosts that run Hyprland
# instead of GNOME (see home/profiles/desktop.nix). Sister file to ./gnome.nix.
# The two share GUI applications, Ghostty, MIME defaults, and Podman via
# ./gui.nix; this file holds only the Hyprland-specific bits.
{
  pkgs,
  pkgs-unstable,
  config,
  inputs,
  lib,
  ...
}:
let
  # Re-run the config in every live instance after home-manager switches a
  # Lua file. The HM module's own onChange hook is disabled when
  # `package = null`, so it's wired manually on the xdg.configFile entries
  # below. `reload config-only` re-executes the Lua config in place; after
  # first migrating off hyprland.conf, run `hyprctl reload full-reset` once
  # (or relog) — a plain reload doesn't switch config formats.
  hyprReload = ''
    (
      XDG_RUNTIME_DIR="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
      if [[ -d "$XDG_RUNTIME_DIR/hypr" ]]; then
        for i in $(${pkgs.hyprland}/bin/hyprctl instances -j | ${pkgs.jq}/bin/jq -r '.[].instance'); do
          ${pkgs.hyprland}/bin/hyprctl -i "$i" reload config-only || true
        done
      fi
    )
  '';

  # Workspace-overview plugin (loaded via wayland.windowManager.hyprland
  # .plugins below). The nixpkgs package builds upstream KZDKM master,
  # which predates the 0.55 V2 plugin API and has no Lua dispatcher
  # wrappers, so it fails against the system Hyprland 0.55.4. Built from
  # the migrate-v2 branch (KZDKM/Hyprspace#238) instead until it merges;
  # binds live in nix/binds.lua, styling under settings.config.plugin.
  # Pinned to 0c0fe4f, the last commit on that branch compatible with
  # 0.55.4 — the later "Updating deprecated functions + render changes"
  # commits track Hyprland master's header layout (managers/animation/ →
  # animation/, new desktop/state/GlobalWindowController.hpp) and no
  # longer compile against 0.55.4 headers.
  hyprspace = pkgs.hyprlandPlugins.hyprspace.overrideAttrs {
    version = "0-unstable-2026-07-07";
    src = pkgs.fetchFromGitHub {
      owner = "ImanolBarba";
      repo = "Hyprspace";
      rev = "0c0fe4fc9cc9eac42d6891b840c349263ce42dba";
      hash = "sha256-0Z/wCBBbWdcmROnwfg52xFbJW1uH8PD/hwa5GrOHSzw=";
    };
  };

  swayncLog = pkgs.writeShellScript "swaync-log" ''
    mkdir -p "$HOME/.local/share/swaync"
    printf '%s [%s] %s: %s\n' \
      "$(date -Iseconds)" \
      "$SWAYNC_APP_NAME" \
      "$SWAYNC_SUMMARY" \
      "$SWAYNC_BODY" \
      >> "$HOME/.local/share/swaync/notifications.log"
  '';

  # Screenshot wrapper around hyprshot. Saves under $XDG_SCREENSHOTS_DIR
  # with a GNOME-style filename (hyprshot itself ignores
  # XDG_SCREENSHOTS_DIR and hardcodes a `_hyprshot` suffix), then claims
  # the clipboard with a file:// URI on text/uri-list — the MIME that
  # Firefox / Zulip / Telegram / image editors / file managers all
  # accept and render as the image on paste. Both the wl-copy and the
  # notify-send run in transient user-service units so they survive
  # Hyprland's exec dispatcher (and Waybar's on-click) tearing down
  # children. The notification needs this specifically because its "Open
  # folder" action makes notify-send block on the swaync client
  # connection until dismissed; if that child is reaped, swaync withdraws
  # the notification and nothing is shown. The action selects the file in
  # Nautilus.
  hyprshotCmd = pkgs.writeShellScript "hyprshot-cmd" ''
    dir=''${XDG_SCREENSHOTS_DIR:-$HOME/Pictures/Screenshots}
    filename="Screenshot From $(date +'%Y-%m-%d %H-%M-%S').png"
    fullpath="$dir/$filename"

    ${pkgs.hyprshot}/bin/hyprshot --silent -o "$dir" -f "$filename" "$@"
    [ -f "$fullpath" ] || exit 0

    ${pkgs.systemd}/bin/systemd-run --user --collect --quiet --no-block \
      --setenv=WAYLAND_DISPLAY --setenv=XDG_RUNTIME_DIR \
      ${pkgs.bash}/bin/bash -c \
      'printf "file://%s\r\n" "$1" | ${pkgs.wl-clipboard}/bin/wl-copy --foreground --type text/uri-list' \
      wl-copy "$fullpath"

    ${pkgs.systemd}/bin/systemd-run --user --collect --quiet --no-block \
      --setenv=WAYLAND_DISPLAY --setenv=XDG_RUNTIME_DIR --setenv=DBUS_SESSION_BUS_ADDRESS \
      ${pkgs.bash}/bin/bash -c '
        action=$(${pkgs.libnotify}/bin/notify-send \
          -a Hyprshot -i "$1" \
          -A open="Open folder" \
          "Screenshot saved" "$1" 2>/dev/null)
        [ "$action" = open ] && exec ${pkgs.nautilus}/bin/nautilus --select "$1"
      ' notify-send "$fullpath"
  '';

  # Convert a file:// URI clipboard (GTK4 apps — Loupe, Nautilus — put
  # text/uri-list on Hyprland instead of raw image bytes) to raw image/png
  # so terminal apps that only speak image/* MIME types can paste it.
  # Runs on the host so it has full filesystem access regardless of sandbox
  # boundaries. magick handles any format ImageMagick supports.
  clipboardToImage = pkgs.writeShellScript "clipboard-to-image" ''
    uri=$(${pkgs.wl-clipboard}/bin/wl-paste --type text/uri-list 2>/dev/null \
      | head -1 | tr -d '\r\n') || exit 0
    case "$uri" in file://*) ;; *) exit 0 ;; esac
    path=$(${pkgs.python3}/bin/python3 -c \
      "import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1][7:]))" \
      "$uri" 2>/dev/null) || exit 0
    [ -f "$path" ] || exit 0
    if ${pkgs.imagemagick}/bin/magick "$path" png:- \
        | ${pkgs.wl-clipboard}/bin/wl-copy --type image/png; then
      ${pkgs.libnotify}/bin/notify-send -t 2000 "Clipboard" "Image ready to paste"
    else
      ${pkgs.libnotify}/bin/notify-send -t 2000 "Clipboard" "Not a supported image format"
    fi
  '';

  # The Waybar bar runs in the host Hyprland session, so its built-in
  # cpu/memory/disk modules read the host's /proc and host `/` — useless
  # for "how loaded is the guest" since the VM's footprint shows up as
  # opaque cloud-hypervisor RSS on the host (held at a floor by the
  # balloon) and the VM's own writable volumes live inside disk images.
  # These scripts feed a separate VM pill group (plus a VM-aware host RAM
  # pill) by sshing the guest over VSOCK (the `dev-vm` alias from
  # home/profiles/desktop.nix). The fetch caches raw meminfo+df so the
  # pills share one round-trip per refresh; when the VM is down ssh fails
  # and the guest-facing pills render `--`.
  vmStatsFetch = pkgs.writeShellScript "waybar-vm-stats-fetch" ''
    set -u
    cache="''${XDG_RUNTIME_DIR:-/tmp}/waybar-vm-stats"
    now=$(${pkgs.coreutils}/bin/date +%s)
    mtime=$(${pkgs.coreutils}/bin/stat -c %Y "$cache" 2>/dev/null || echo 0)
    if [ ! -s "$cache" ] || [ $(( now - mtime )) -ge 4 ]; then
      if out=$(${pkgs.openssh}/bin/ssh \
          -o BatchMode=yes -o ConnectTimeout=2 \
          -o StrictHostKeyChecking=accept-new \
          dev-vm \
          'grep -E "^(MemTotal|MemAvailable):" /proc/meminfo; echo @@DF@@; df -B1 --output=used,size,target /nix/.rw-store /home' \
          2>/dev/null); then
        printf '%s\n' "$out" > "$cache.$$" && mv -f "$cache.$$" "$cache"
      else
        printf 'OFF\n' > "$cache.$$" && mv -f "$cache.$$" "$cache"
      fi
    fi
    ${pkgs.coreutils}/bin/cat "$cache"
  '';

  vmMemPill = pkgs.writeShellScript "waybar-vm-mem" ''
    set -u
    raw=$(${vmStatsFetch})
    mem=$'\uF0C9' # nf-fa-memory
    if [ "$raw" = OFF ]; then
      printf '{"text":"VM -- %s","class":"off","tooltip":"dev VM is off"}\n' "$mem"
      exit 0
    fi
    total=$(printf '%s\n' "$raw" | ${pkgs.gawk}/bin/awk '/^MemTotal:/{print $2}')
    avail=$(printf '%s\n' "$raw" | ${pkgs.gawk}/bin/awk '/^MemAvailable:/{print $2}')
    used=$(( total - avail ))
    set -- $(${pkgs.gawk}/bin/awk -v u="$used" -v t="$total" -v a="$avail" \
      'BEGIN{printf "%.1f %.0f %.1f %.0f", u/1048576, t/1048576, a/1048576, 100*u/t}')
    usedg=$1; totalg=$2; availg=$3; pct=$4
    if [ "$pct" -ge 90 ]; then cls=critical
    elif [ "$pct" -ge 75 ]; then cls=warning
    else cls=normal; fi
    printf '{"text":"VM %s%% %s","class":"%s","tooltip":"VM RAM: %s%% used\\n%s / %s GiB used · %s GiB available"}\n' \
      "$pct" "$mem" "$cls" "$pct" "$usedg" "$totalg" "$availg"
  '';

  # The VM's two writable volumes (the nix-store overlay and /home) are
  # separate disk images with independent ceilings, so each gets its own
  # pill — either can fill without the other noticing. One pill per mount,
  # showing that volume's used%; the tooltip carries the GiB breakdown.
  mkVmDiskPill =
    {
      key,
      target,
      glyph,
      label,
    }:
    pkgs.writeShellScript "waybar-vm-disk-${key}" ''
      set -u
      raw=$(${vmStatsFetch})
      icon=$'${glyph}'
      if [ "$raw" = OFF ]; then
        printf '{"text":"-- %s","class":"off","tooltip":"dev VM is off"}\n' "$icon"
        exit 0
      fi
      out=$(printf '%s\n' "$raw" | ${pkgs.gawk}/bin/awk -v want='${target}' '
        /@@DF@@/ { seen = 1; next }
        seen && $3 == want {
          used = $1; size = $2
          pct = (size > 0) ? 100 * used / size : 0
          printf "%.0f\t%.1f / %.0f GiB used (%.0f%%)", \
            pct, used / 1073741824, size / 1073741824, pct
        }')
      pct=$(printf '%s' "$out" | ${pkgs.coreutils}/bin/cut -f1)
      detail=$(printf '%s' "$out" | ${pkgs.coreutils}/bin/cut -f2)
      if [ -z "$pct" ]; then
        printf '{"text":"-- %s","class":"off","tooltip":"${label}: unavailable"}\n' "$icon"
        exit 0
      fi
      if [ "$pct" -ge 90 ]; then cls=critical
      elif [ "$pct" -ge 80 ]; then cls=warning
      else cls=normal; fi
      printf '{"text":"%s%% %s","class":"%s","tooltip":"${label}: %s"}\n' \
        "$pct" "$icon" "$cls" "$detail"
    '';

  vmDiskNixPill = mkVmDiskPill {
    key = "nix";
    target = "/nix/.rw-store";
    glyph = "\\uF313"; # nf-linux-nixos
    label = "Nix store overlay";
  };
  vmDiskHomePill = mkVmDiskPill {
    key = "home";
    target = "/home";
    glyph = "\\U000F02DC"; # nf-md-home
    label = "VM /home";
  };

  # Host RAM, but with the dev VM's *reclaimable* memory discounted so the
  # pill reflects real hardware pressure instead of sitting pinned at the
  # VM's resident-footprint floor. The guest's footprint on the host (the
  # microvm@dev.service cgroup) is mostly returnable — guest page cache
  # plus balloon-deflatable pages — so counting it as "used" is
  # misleading. Instead we add back whatever the guest itself reports as
  # MemAvailable (capped at its host footprint, since it can't return more
  # than it holds): effective_avail = host_avail + min(guest_avail, vm).
  # The number stays low while the VM merely caches and climbs only as the
  # guest genuinely commits RAM — i.e. as the machine actually nears OOM.
  # Falls back to the plain host figure when the VM is down or the cgroup
  # has no memory accounting.
  hostMemPill = pkgs.writeShellScript "waybar-host-mem" ''
    set -u
    mem=$'\uF0C9' # nf-fa-memory
    set -- $(${pkgs.gawk}/bin/awk '
      /^MemTotal:/{t=$2} /^MemAvailable:/{a=$2}
      /^SwapTotal:/{st=$2} /^SwapFree:/{sf=$2}
      END{printf "%d %d %d %d", t, a, st, sf}' /proc/meminfo)
    htotal=$1; havail=$2; swapt=$3; swapf=$4
    vmbytes=$(${pkgs.systemd}/bin/systemctl show -p MemoryCurrent --value microvm@dev.service 2>/dev/null)
    case "$vmbytes" in ""|*[!0-9]*) vmkb=0 ;; *) vmkb=$(( vmbytes / 1024 )) ;; esac
    # A bogus/unset cgroup reading (e.g. uint64 max) can't exceed RAM.
    [ "$vmkb" -gt "$htotal" ] && vmkb=0
    raw=$(${vmStatsFetch})
    if [ "$raw" = OFF ]; then
      gavail=0; vmkb=0
    else
      gavail=$(printf '%s\n' "$raw" | ${pkgs.gawk}/bin/awk '/^MemAvailable:/{print $2}')
    fi
    disc=$gavail
    [ "$disc" -gt "$vmkb" ] && disc=$vmkb
    effavail=$(( havail + disc ))
    [ "$effavail" -gt "$htotal" ] && effavail=$htotal
    set -- $(${pkgs.gawk}/bin/awk -v t="$htotal" -v ea="$effavail" -v ha="$havail" \
      -v st="$swapt" -v sf="$swapf" 'BEGIN{
        effpct = (t>0) ? 100*(t-ea)/t : 0
        rawpct = (t>0) ? 100*(t-ha)/t : 0
        printf "%.0f %.0f %.1f %.1f %.1f", \
          effpct, rawpct, ea/1048576, (st-sf)/1048576, st/1048576
      }')
    effpct=$1; rawpct=$2; effavailg=$3; swapused=$4; swaptot=$5
    if [ "$effpct" -ge 90 ]; then cls=critical
    elif [ "$effpct" -ge 75 ]; then cls=warning
    else cls=normal; fi
    printf '{"text":"%s%% %s","class":"%s","tooltip":"Host RAM: %s%% effective (VM-discounted)\\n%s%% raw · %s GiB effective free\\nswap %s / %s GiB"}\n' \
      "$effpct" "$mem" "$cls" "$effpct" "$rawpct" "$effavailg" "$swapused" "$swaptot"
  '';

  # Idle auto-suspend with a runtime opt-out. hypridle's final listener runs
  # `suspendUnlessInhibited`, which suspends only when the flag file is
  # absent; the Waybar pill flips that flag via `toggleSuspendInhibit`.
  # Deliberately narrower than the wayland
  # idle-inhibitor (the Waybar eye), which pauses *every* hypridle timer and
  # so keeps the screen lit and the session unlocked: here dim, DPMS-off and
  # lock still fire, only the suspend step is skipped — so a remote-control
  # session keeps the machine awake while the display is off and locked.
  # before_sleep_cmd locks on the way down, so a suspend always resumes
  # locked. The flag lives in XDG_RUNTIME_DIR, so it clears on logout and
  # auto-suspend is re-armed by default each session.
  suspendUnlessInhibited = pkgs.writeShellScript "hypridle-suspend-unless-inhibited" ''
    [ -e "''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suspend-inhibited" ] && exit 0
    exec ${pkgs.systemd}/bin/systemctl suspend
  '';
  toggleSuspendInhibit = pkgs.writeShellScript "hypridle-toggle-suspend" ''
    flag="''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suspend-inhibited"
    if [ -e "$flag" ]; then
      rm -f "$flag"
      ${pkgs.libnotify}/bin/notify-send -a hypridle -t 2000 \
        "Auto-suspend on" "Suspends after 30 min idle"
    else
      : > "$flag"
      ${pkgs.libnotify}/bin/notify-send -a hypridle -t 2000 \
        "Auto-suspend off" "Stays awake when idle — display still locks and powers off"
    fi
    ${pkgs.procps}/bin/pkill -RTMIN+9 waybar 2>/dev/null || true
  '';
  suspendInhibitPill = pkgs.writeShellScript "waybar-suspend-inhibit" ''
    bolt=$'' # nf-fa-bolt — staying awake
    bed=$''  # nf-fa-bed — will suspend
    if [ -e "''${XDG_RUNTIME_DIR:-/tmp}/hypridle-suspend-inhibited" ]; then
      printf '{"text":"%s","class":"active","tooltip":"Auto-suspend OFF — machine stays awake when idle (display still locks + powers off).\\nClick to re-arm suspend."}\n' "$bolt"
    else
      printf '{"text":"%s","class":"normal","tooltip":"Auto-suspend ON — suspends after 30 min idle.\\nClick to keep awake for a remote session."}\n' "$bed"
    fi
  '';

  # Per-monitor wallpapers, single source of truth shared by hyprpaper (live
  # desktop) and the hyprlock background pre-blur below. Kept under ~/Pictures
  # (not the store) so they can be swapped in place without a rebuild.
  wallpaperDP2 = "${config.home.homeDirectory}/Pictures/wallhaven-1.jpg";
  wallpaperHDMI = "${config.home.homeDirectory}/Pictures/wallhaven-2.jpg";

  # Pre-blurred lock backgrounds. hyprlock's `screenshot` background is
  # captured and blurred lazily on first paint; because the display is
  # already DPMS-off by the time hypridle locks, that work is deferred to
  # wake, stalling the lock UI for seconds. Instead, blur each wallpaper once
  # per login (the hyprlock-bg service) into the cache and point hyprlock at
  # the ready PNGs with blur_passes = 0 — locking and waking then do zero
  # image work. A wallpaper swapped in place is picked up next login;
  # `systemctl --user restart hyprlock-bg` regenerates on demand.
  lockBgDP2 = "${config.xdg.cacheHome}/hyprlock/dp-2.png";
  lockBgHDMI = "${config.xdg.cacheHome}/hyprlock/hdmi-a-1.png";
  blurWallpapers = pkgs.writeShellScript "hyprlock-blur-wallpapers" ''
    set -eu
    blur() {
      src=$1
      dst=$2
      [ -f "$src" ] || return 0
      ${pkgs.coreutils}/bin/mkdir -p "$(${pkgs.coreutils}/bin/dirname "$dst")"
      # Downscale (a blurred background needs no detail) then a strong
      # Gaussian blur, producing a display-ready PNG. -strip drops metadata.
      ${pkgs.imagemagick}/bin/magick "$src" -resize '2000x>' -blur 0x12 -strip "$dst"
    }
    blur ${wallpaperDP2} ${lockBgDP2}
    blur ${wallpaperHDMI} ${lockBgHDMI}
  '';

in
{
  imports = [
    ./gui.nix
  ];

  # Point ssh at gcr-ssh-agent's socket. gnome-keyring 48+ no longer ships
  # an SSH agent (upstream disabled it at build time); the agent is gcr's,
  # run via systemd socket units that NixOS enables alongside
  # services.gnome.gnome-keyring (common/hyprland-wm.nix). gnome-session
  # exports the variable for GNOME sessions; under Hyprland nothing does,
  # so ssh would otherwise fall back to no agent and re-prompt for the key
  # passphrase every invocation. This only covers interactive shells — the
  # uwsm/env file below exports the same socket into the systemd
  # activation environment for uwsm apps and user services (waybar,
  # ghostty binds).
  home.sessionVariables.SSH_AUTH_SOCK = "$XDG_RUNTIME_DIR/gcr/ssh";

  home.packages = with pkgs; [
    # File manager + GNOME Settings panel. Both work standalone outside a
    # GNOME session; control-center panels backed by session-agnostic
    # daemons (NetworkManager, PipeWire, CUPS) keep working, panels that
    # need GNOME Shell (Online Accounts, Background) become no-ops.
    nautilus
    # gnome-control-center refuses to start unless XDG_CURRENT_DESKTOP
    # contains GNOME or Unity; wrap the binary so both terminal invocations
    # and fuzzel launches (via the .desktop file's `Exec=gnome-control-center`)
    # get the override transparently.
    (symlinkJoin {
      name = "gnome-control-center";
      paths = [ gnome-control-center ];
      nativeBuildInputs = [ makeWrapper ];
      postBuild = ''
        wrapProgram $out/bin/gnome-control-center \
          --set XDG_CURRENT_DESKTOP GNOME
      '';
    })

    # Wayland Qt support — wiki "Must-have" page recommends installing
    # qt5-wayland and qt6-wayland so Qt apps and the xdg-desktop-portal
    # share-picker render natively.
    qt5.qtwayland
    qt6.qtwayland

    # cliphist's home-manager service pulls in cliphist + wl-clipboard for
    # its own watchers. Tmux yank (base.nix) also pipes through wl-copy
    # outside that service chain, but wl-clipboard is shared via gui.nix.

    # Screenshots — hyprshot wraps grim+slurp with Hyprland IPC awareness
    # (current monitor / focused window selection). Clipboard + notification
    # are handled by the `hyprshotCmd` wrapper in the let block above; grim
    # and slurp stay listed because hyprshot shells out to them, and
    # grimblast is kept as a wlroots-generic fallback.
    grim
    slurp
    grimblast
    hyprshot

    libnotify

    # hypridle + hyprlock + hyprpaper + hyprsunset are configured as
    # services below; their home-manager modules pull in the binaries.

    # Wayland-native colour picker — invoke with the bind below or directly.
    # `-a` auto-copies the picked colour to the clipboard via wl-clipboard
    # (provided by gui.nix); `-f hex` formats as #RRGGBB.
    hyprpicker

    # Media + brightness keys referenced by the example XF86 binds
    brightnessctl
    playerctl
    pavucontrol

    # Escape-hatch terminal, bound to Super+Shift+Q below without the
    # `uwsm app --` wrapper the other launch binds use — a raw spawn that
    # still works if the uwsm app-launch machinery is ever broken.
    kitty

    # Graphical power menu — Lock / Logout / Suspend / Hibernate / Reboot /
    # Shutdown buttons. Invoked from the Waybar custom/power pill below.
    wlogout

    # Quickshell — QML-based Wayland shell framework. Renders the
    # volume OSD popup; see xdg.configFile."quickshell/osd/shell.qml"
    # below. Started via `exec-once = qs -c osd` in the Hyprland
    # settings.
    pkgs-unstable.quickshell
  ];

  # Volume OSD as a Quickshell config. Subscribes to PipeWire sink +
  # source state so the popup shows on every volume/mute change —
  # keypress, waybar scroll, AVRCP headphone button, pavucontrol, any
  # app's slider — not just on actions we explicitly bind. Started by
  # its own `qs -c osd` exec-once below.
  xdg.configFile."quickshell/osd/shell.qml".text = ''
    //@ pragma UseQApplication

    import QtQuick
    import QtQuick.Layouts
    import Quickshell
    import Quickshell.Wayland
    import Quickshell.Hyprland
    import Quickshell.Services.Pipewire

    ShellRoot {
        id: root

        property bool osdVisible: false
        property real progress: 0
        property bool muted: false
        property bool isMicChange: false
        // Suppress the spurious volumeChanged signal Pipewire fires
        // when the daemon first connects and reads initial state.
        property bool ready: false

        // Keep the audio sub-objects alive so their property change
        // signals actually reach the Connections below.
        PwObjectTracker {
            objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
        }

        Connections {
            target: Pipewire.defaultAudioSink?.audio ?? null
            function refresh() {
                if (!root.ready) return;
                root.isMicChange = false;
                root.muted = Pipewire.defaultAudioSink?.audio?.muted ?? false;
                root.progress = Pipewire.defaultAudioSink?.audio?.volume ?? 0;
                root.osdVisible = true;
                hideTimer.restart();
            }
            function onVolumeChanged() { refresh(); }
            function onMutedChanged() { refresh(); }
        }

        Connections {
            target: Pipewire.defaultAudioSource?.audio ?? null
            function refresh() {
                if (!root.ready) return;
                root.isMicChange = true;
                root.muted = Pipewire.defaultAudioSource?.audio?.muted ?? false;
                root.progress = Pipewire.defaultAudioSource?.audio?.volume ?? 0;
                root.osdVisible = true;
                hideTimer.restart();
            }
            function onVolumeChanged() { refresh(); }
            function onMutedChanged() { refresh(); }
        }

        Timer {
            id: readyTimer
            interval: 1000
            running: true
            onTriggered: root.ready = true
        }

        Timer {
            id: hideTimer
            interval: 1500
            onTriggered: root.osdVisible = false
        }

        LazyLoader {
            active: root.osdVisible

            PanelWindow {
                screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.exclusionMode: ExclusionMode.Ignore
                WlrLayershell.namespace: "quickshell:osd"

                color: "transparent"
                implicitWidth: 360
                implicitHeight: 64
                margins.top: 80
                anchors.top: true

                // Catppuccin Mocha — base bg, surface0 track, blue
                // accent, overlay0 for the muted state. Matches the
                // waybar pulseaudio pill's palette in style.css above.
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 8
                    color: "#1e1e2e"
                    radius: 12
                    border.width: 1
                    border.color: "#45475a"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 14

                        Text {
                            Layout.preferredWidth: 22
                            Layout.alignment: Qt.AlignVCenter
                            text: root.muted ? ""
                                : root.isMicChange ? ""
                                : root.progress < 0.34 ? ""
                                : ""
                            font.family: "FiraCode Nerd Font Mono"
                            font.pixelSize: 18
                            color: root.muted ? "#6c7086" : "#cdd6f4"
                            horizontalAlignment: Text.AlignHCenter
                        }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 6
                            Layout.alignment: Qt.AlignVCenter
                            radius: 3
                            color: "#313244"

                            Rectangle {
                                width: parent.width * Math.min(1, Math.max(0, root.progress))
                                height: parent.height
                                radius: parent.radius
                                color: root.muted ? "#6c7086" : "#89b4fa"
                                Behavior on width {
                                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                                }
                            }
                        }

                        Text {
                            Layout.preferredWidth: 44
                            Layout.alignment: Qt.AlignVCenter
                            text: Math.round(root.progress * 100) + "%"
                            font.family: "FiraCode Nerd Font Mono"
                            font.pixelSize: 13
                            color: root.muted ? "#6c7086" : "#cdd6f4"
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }
            }
        }
    }
  '';

  # Hyprland-specific addition over gui.nix's image MIME defaults — under
  # GNOME, Nautilus is already the default file manager; spelling it out
  # here ensures `xdg-open .` lands on Nautilus under Hyprland too.
  xdg.mimeApps.defaultApplications."inode/directory" = [ "org.gnome.Nautilus.desktop" ];

  home.pointerCursor = {
    gtk.enable = true;
    x11.enable = true;
    package = pkgs.bibata-cursors;
    name = "Bibata-Modern-Classic";
    size = 24;
  };

  ###########################################################################
  # Hyprland compositor, configured via the 0.55+ Lua config. Table-shaped
  # config in `settings` renders straight to hl.monitor / hl.workspace_rule /
  # hl.config calls; binds, window rules, and runtime helpers are plain Lua
  # in the xdg.configFile."hypr/nix/*.lua" blocks below the compositor
  # block, pulled in by the require() lines in extraConfig. The keybinds
  # started as a translation of the upstream example config, extended with
  # Vim-style hjkl focus and per-monitor workspace conventions; see the
  # comment block above the workspace binds (nix/binds.lua) for the
  # modifier convention.
  ###########################################################################
  wayland.windowManager.hyprland = {
    enable = true;
    xwayland.enable = true;
    # NixOS module owns the Hyprland and XDPH packages; setting these to null
    # tells home-manager to use the system ones so versions can't diverge.
    # (https://wiki.hypr.land/Nix/Hyprland-on-Home-Manager/#using-the-home-manager-module-with-nixos)
    package = null;
    portalPackage = null;
    # Off (despite defaulting to true) because the session is launched via
    # UWSM (programs.hyprland.withUWSM in common/hyprland-wm.nix), which
    # owns both jobs this integration would otherwise do — exporting the
    # compositor's environment into the systemd user manager and starting
    # graphical-session.target. Leaving it on would race uwsm's session
    # units with the exec-once stop/start of hyprland-session.target.
    systemd.enable = false;
    # Generate ~/.config/hypr/hyprland.lua instead of legacy hyprland.conf —
    # hyprlang is deprecated since Hyprland 0.55 and the wiki documents Lua
    # only. stateVersion < 26.05 would otherwise default to "hyprlang".
    configType = "lua";

    # hyprspace is loaded (and its panel styling applied) from the start
    # hook in extraConfig below, NOT via the `plugins` option: a plugin's
    # `plugin:overview:*` config keys don't exist until it loads, so setting
    # them here in the eagerly-parsed hl.config() block errors as unknown.

    settings = {
      monitor = [
        # 34" ultrawide (Viewteck GNV34DBE) anchors the layout at the origin.
        {
          output = "DP-2";
          mode = "3440x1440@144";
          position = "0x0";
          scale = 1;
        }
        # HP VH240a centered horizontally above the ultrawide:
        # x = (3440 - 1920) / 2. Y is negative because Hyprland uses
        # inverse-Y (negative = up).
        {
          output = "HDMI-A-1";
          mode = "1920x1080@60";
          position = "760x-1080";
          scale = 1;
        }
      ];

      # Workspaces pinned per monitor so the Super+N synced pair-switch
      # binds (nix/binds.lua) are deterministic. 1-5 = DP-2 (lower), 6-10 =
      # HDMI-A-1 (upper). `persistent` keeps them around even when empty;
      # `default` is the workspace each monitor opens on at session start.
      workspace_rule =
        map (
          i:
          {
            workspace = toString i;
            monitor = "DP-2";
            persistent = true;
          }
          // lib.optionalAttrs (i == 1) { default = true; }
        ) (lib.range 1 5)
        ++ map (
          i:
          {
            workspace = toString i;
            monitor = "HDMI-A-1";
            persistent = true;
          }
          // lib.optionalAttrs (i == 6) { default = true; }
        ) (lib.range 6 10);

      # Session environment lives in ~/.config/uwsm/env* (see the
      # xdg.configFile."uwsm/env" blocks below), not in hl.env() calls here:
      # uwsm exports those files into the systemd activation environment at
      # session start, so user services and uwsm-launched apps see them too,
      # whereas hl.env() would only reach the compositor's own children
      # (wiki: Configuring/Environment-variables, uwsm note).

      # Only customisations vs upstream defaults are set here. Anything
      # not listed inherits Hyprland's built-in default
      # (src/config/values/ConfigValues.cpp).
      config = {
        general = {
          border_size = 2; # default: 1
          # Default 20 wastes real estate; 5 matches gaps_in (default 5) so
          # every seam is the same scale. The top edge reads slightly wider
          # anyway — waybar's floating pills carry 5px internal margin inside
          # the bar's exclusive zone.
          gaps_out = 5; # default: 20
          col = {
            # blue → mauve
            active_border = {
              colors = [
                "rgba(89b4faee)"
                "rgba(cba6f7ee)"
              ];
              angle = 45;
            };
            inactive_border = "rgba(313244aa)"; # surface0
          };
        };

        decoration = {
          rounding = 10; # default: 0
          blur.size = 3; # default: 8
          # Slight dim on unfocused windows so the focused one reads first
          # at a glance — important on the ultrawide where 3+ tiles are
          # visible at once. Fullscreen always renders at full opacity.
          active_opacity = 1.0; # default: 1.0
          inactive_opacity = 0.85; # default: 1.0
          fullscreen_opacity = 1.0; # default: 1.0
        };

        dwindle = {
          preserve_split = true; # default: false
        };

        misc = {
          # Apps raise their window on notification click via the EWMH
          # _NET_ACTIVE_WINDOW request; Hyprland ignores those by default.
          focus_on_activate = true;
        };

      };

    };

    extraConfig = ''
      -- All session daemons (cliphist, nm-applet, blueman-applet, swaync,
      -- hyprpolkitagent) are managed by home-manager systemd user services,
      -- bound to graphical-session.target (started by uwsm). Quickshell is
      -- the exception: not wired as a systemd user service, so start the
      -- volume OSD here. Its QML lives in
      -- xdg.configFile."quickshell/osd/shell.qml".
      hl.on("hyprland.start", function()
        hl.exec_cmd("uwsm app -- ${pkgs-unstable.quickshell}/bin/qs -c osd")
      end)

      -- Loud warning when the session is NOT uwsm-managed (e.g. the plain
      -- "Hyprland" GDM entry was picked by accident): every `uwsm app`
      -- bind is dead there and no user services start, so the session
      -- looks broken with no obvious cause. Under uwsm the compositor
      -- runs inside wayland-wm@Hyprland.service; a plain GDM launch runs
      -- in the login session scope instead, so the cgroup is the
      -- discriminator.
      hl.on("hyprland.start", function()
        local f = io.open("/proc/self/cgroup", "r")
        if f == nil then
          return
        end
        local cgroup = f:read("a") or ""
        f:close()
        if not cgroup:find("wayland-wm@", 1, true) then
          hl.notification.create({
            text = "Session is NOT uwsm-managed - app binds and user "
              .. "services (waybar, ghostty, fuzzel) will not work. "
              .. "Log out and pick the \"Hyprland (uwsm)\" entry in GDM.",
            timeout = 60000,
            icon = "warning",
          })
        end
      end)

      -- Load Hyprspace and apply its panel styling. The plugin's
      -- plugin:overview:* keys only exist once it's loaded, which can't
      -- happen inside the eagerly-parsed hl.config() above — so they're set
      -- here, after the load. `hyprctl keyword` is rejected under the Lua
      -- config parser ("use eval"), so the values go through `hyprctl eval`
      -- running hl.config(), which merges and leaves the rest of the config
      -- intact. hl.exec_cmd spawns via `/bin/sh -c` without waiting, so the
      -- load and eval are chained in one command: hyprctl blocks on each IPC
      -- reply, so `&&` runs the eval only after the plugin has registered its
      -- keys.
      hl.on("hyprland.start", function()
        hl.exec_cmd(
          [[hyprctl plugin load ${hyprspace}/lib/libhyprspace.so && ]]
          .. [[hyprctl eval 'hl.config({ ["plugin"] = { ["overview"] = { ]]
          .. [[["panelColor"] = "rgba(11111bee)", ]]
          .. [[["panelBorderColor"] = "rgba(89b4faee)", ]]
          .. [[["workspaceActiveBorder"] = "rgba(89b4faee)", ]]
          .. [[["workspaceInactiveBorder"] = "rgba(313244aa)", ]]
          -- Hide the trailing "new workspace" tile: with 1-5 and 6-10 bound
          -- to the two monitors, it only ever creates an orphan ws 11.
          .. [[["showNewWorkspace"] = 0 } } })']]
        )
      end)

      require("nix/binds")
      require("nix/rules")
    '';
  };

  # Keybinds and runtime helpers as a real Lua module — kept out of
  # `settings`, whose Lua renderer would force an _args/mkLuaInline wrapper
  # around every bind. Store paths are interpolated by Nix at build time.
  # Bind reference: https://wiki.hypr.land/Configuring/Basics/Binds/
  xdg.configFile."hypr/nix/binds.lua" = {
    onChange = hyprReload;
    text = ''
      local mod = "SUPER"

      -- GUI apps launch via `uwsm app --` so each runs in its own systemd
      -- scope under app-graphical.slice instead of as a child inside the
      -- compositor's unit (wiki: Useful-Utilities/Systemd-start, "Launching
      -- applications inside session"). Short-lived utilities (hyprpicker,
      -- screenshot/clipboard scripts) stay direct children — they exit
      -- before unit placement matters.
      --
      -- Super+T opens ghostty ssh'd into the dev microvm and attached to
      -- tmux (via the ssh-dev-vm wrapper, which forwards
      -- GH_TOKEN/NIX_CONFIG). Super+Shift+T (below) opens a plain host
      -- ghostty.
      local terminal    = "uwsm app -- ghostty -e ssh-dev-vm"
      local fileManager = "uwsm app -- nautilus"
      local menu        = "uwsm app -- fuzzel"

      -- Send the focused window to "workspace N on the current monitor".
      -- Workspace move targets are absolute, so look up the active
      -- workspace ID (1-5 = DP-2 by our pinning rules; 6-10 = HDMI-A-1)
      -- and add 5 to N when the cursor is on the upper monitor.
      local function move_to_ws_relative(n)
        return function()
          local ws = hl.get_active_workspace()
          local target = (ws ~= nil and ws.id >= 6) and (n + 5) or n
          hl.dispatch(hl.dsp.window.move({ workspace = target }))
        end
      end

      -- Focus the leftmost ("l") or rightmost ("r") mapped window on the
      -- active workspace. Used by the Super+Shift+H/L binds — sister to
      -- the Super+Shift+J/K monitor jumps. Workspaces are pinned per
      -- monitor, so filtering by workspace implicitly filters by monitor.
      local function focus_edge_window(dir)
        return function()
          local ws = hl.get_active_workspace()
          if ws == nil then
            return
          end
          local best = nil
          for _, w in ipairs(ws:get_windows()) do
            if w.mapped and (best == nil
                or (dir == "l" and w.at.x < best.at.x)
                or (dir == "r" and w.at.x > best.at.x)) then
              best = w
            end
          end
          if best ~= nil then
            hl.dispatch(hl.dsp.focus({ window = best }))
          end
        end
      end

      -- Toggle the focused window in/out of the `magic` special workspace,
      -- following it either way. In a normal workspace → move into the
      -- scratchpad and show it. Already in the scratchpad → eject to the
      -- normal workspace on the focused monitor.
      local function scratch_toggle()
        local w = hl.get_active_window()
        if w == nil then
          return
        end
        if w.workspace ~= nil and w.workspace.special then
          for _, m in ipairs(hl.get_monitors()) do
            if m.focused then
              hl.dispatch(hl.dsp.window.move({ workspace = m.active_workspace }))
              return
            end
          end
        else
          hl.dispatch(hl.dsp.window.move({ workspace = "special:magic" }))
        end
      end

      -- Lock and blank the display in one go (walk-away / remote-session
      -- action). Lock first, brief pause so hyprlock has grabbed before the
      -- output powers down, then DPMS off; any input wakes the display back
      -- to the lock screen. Unlike hypridle's DPMS-off step this doesn't
      -- stop Waybar — a one-shot bind has no on-resume hook to restart it,
      -- and the surface-leak bug it guards against only shows over repeated
      -- idle cycles.
      hl.bind(mod .. " + ALT + Q", hl.dsp.exec_cmd(
        "loginctl lock-session && sleep 0.5 && ${pkgs.hyprland}/bin/hyprctl dispatch dpms off"))
      hl.bind(mod .. " + Escape", hl.dsp.exec_cmd(
        "pidof wlogout || uwsm app -- ${pkgs.wlogout}/bin/wlogout -L 1200 -R 1200 -T 350 -B 350"))
      hl.bind(mod .. " + X", hl.dsp.window.close())
      hl.bind(mod .. " + E", hl.dsp.exec_cmd(fileManager))
      hl.bind(mod .. " + V", hl.dsp.window.float({ action = "toggle" }))
      hl.bind(mod .. " + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
      hl.bind(mod .. " + BackSpace", hl.dsp.exec_cmd(menu))
      -- Pseudo moved off P to free it for the screenshot scheme below.
      hl.bind(mod .. " + I", hl.dsp.window.pseudo())
      -- Colour picker — C for "colour"; moved off P for the same reason.
      hl.bind(mod .. " + C", hl.dsp.exec_cmd("hyprpicker -a -f hex"))
      hl.bind(mod .. " + SHIFT + D", hl.dsp.exec_cmd("darkman toggle"))
      hl.bind(mod .. " + T", hl.dsp.exec_cmd(terminal))
      -- Plain host ghostty — the push terminal: the write-capable SSH key
      -- lives only on the host, so git push always happens here rather than
      -- in the dev VM.
      hl.bind(mod .. " + SHIFT + T", hl.dsp.exec_cmd("uwsm app -- ghostty"))

      -- Escape-hatch terminal, deliberately NOT uwsm-wrapped: if `uwsm app`
      -- is ever broken every wrapped bind above is dead, and this raw
      -- spawn (a plain child of the compositor unit) is the one guaranteed
      -- way to get a shell.
      hl.bind(mod .. " + SHIFT + Q", hl.dsp.exec_cmd("kitty"))

      -- Screenshots via hyprshot — every mode saves to
      -- ~/Pictures/Screenshots AND copies the image to the clipboard;
      -- swaync surfaces a thumbnail preview. Super+P: region drag-
      -- select. +Shift: focused window. +Alt: whole focused monitor.
      hl.bind(mod .. " + P", hl.dsp.exec_cmd("${hyprshotCmd} -m region"))
      hl.bind(mod .. " + SHIFT + P", hl.dsp.exec_cmd("${hyprshotCmd} -m window"))
      hl.bind(mod .. " + ALT + P", hl.dsp.exec_cmd("${hyprshotCmd} -m output"))

      -- Convert a file:// URI clipboard to raw image/png. GTK4 apps
      -- (Loupe, Nautilus) copy images as text/uri-list on Hyprland;
      -- press this after copying from an image viewer, then paste
      -- normally in Claude Code or any app that needs raw image bytes.
      hl.bind(mod .. " + CTRL + P", hl.dsp.exec_cmd("${clipboardToImage}"))

      hl.bind(mod .. " + H", hl.dsp.focus({ direction = "left" }))
      hl.bind(mod .. " + J", hl.dsp.focus({ direction = "down" }))
      hl.bind(mod .. " + K", hl.dsp.focus({ direction = "up" }))
      hl.bind(mod .. " + L", hl.dsp.focus({ direction = "right" }))

      -- Move the focused window in a direction (swap within the layout).
      hl.bind(mod .. " + ALT + H", hl.dsp.window.move({ direction = "left" }))
      hl.bind(mod .. " + ALT + J", hl.dsp.window.move({ direction = "down" }))
      hl.bind(mod .. " + ALT + K", hl.dsp.window.move({ direction = "up" }))
      hl.bind(mod .. " + ALT + L", hl.dsp.window.move({ direction = "right" }))

      -- Force the focused window onto the monitor below/above, regardless
      -- of its position. The plain direction move above picks the target
      -- monitor from a focal point at the window's *horizontal centre*, so
      -- a window parked on the left/right of the ultrawide — outside
      -- HDMI-A-1's narrower, centred x-span — never finds the monitor above
      -- and no-ops. The monitor form (getMonitorInDirection) has no such
      -- blind spot and works for tiled, floating, and fullscreen windows.
      hl.bind(mod .. " + ALT + SHIFT + J", hl.dsp.window.move({ monitor = "d" }))
      hl.bind(mod .. " + ALT + SHIFT + K", hl.dsp.window.move({ monitor = "u" }))

      -- Toggle the dwindle split orientation (horizontal/vertical) of the
      -- focused container.
      hl.bind(mod .. " + ALT + T", hl.dsp.layout("togglesplit"))

      -- Jump to a screen edge.
      -- J/K cross the vertical monitor boundary (K → HDMI-A-1, J → DP-2).
      -- H/L focus the left/rightmost window on the *current* monitor via
      -- the helper above — workspace filtering picks the right monitor's
      -- clients automatically.
      hl.bind(mod .. " + SHIFT + H", focus_edge_window("l"))
      hl.bind(mod .. " + SHIFT + J", hl.dsp.focus({ monitor = "d" }))
      hl.bind(mod .. " + SHIFT + K", hl.dsp.focus({ monitor = "u" }))
      hl.bind(mod .. " + SHIFT + L", focus_edge_window("r"))

      -- Modifier convention:
      --   ALT = move focused window (instead of switching workspace)
      -- Numbers are absolute: 1-5 = DP-2 (bottom monitor) workspaces 1-5,
      -- 6-0 = HDMI-A-1 (top monitor) workspaces 6-10. Arrows are
      -- direction-based so they always act on the *current* monitor
      -- (m+1/m-1 wraps within the active monitor's workspace range).

      -- --- Switch workspace ---
      hl.bind(mod .. " + left", hl.dsp.focus({ workspace = "m-1" }))
      hl.bind(mod .. " + right", hl.dsp.focus({ workspace = "m+1" }))

      for i = 1, 10 do
        hl.bind(mod .. " + " .. (i % 10), hl.dsp.focus({ workspace = i }))
      end

      -- --- Move focused window to workspace (Alt prefix) ---
      hl.bind(mod .. " + ALT + left", hl.dsp.window.move({ workspace = "m-1" }))
      hl.bind(mod .. " + ALT + right", hl.dsp.window.move({ workspace = "m+1" }))

      -- Move focused window to ws N on the *current* monitor (helper
      -- adjusts the target by +5 when the cursor is on HDMI-A-1); 6-0
      -- target the upper monitor's workspaces absolutely.
      for i = 1, 5 do
        hl.bind(mod .. " + ALT + " .. i, move_to_ws_relative(i))
      end
      for i = 6, 10 do
        hl.bind(mod .. " + ALT + " .. (i % 10), hl.dsp.window.move({ workspace = i }))
      end

      -- Hyprspace workspace overview. The hl.plugin.overview.* wrappers
      -- are registered when the plugin loads in the start hook — after
      -- this file is parsed — so the calls must sit inside closures that
      -- defer the lookup to keypress time. Plain TAB = current monitor,
      -- SHIFT = both monitors at once.
      hl.bind(mod .. " + TAB", function()
        hl.plugin.overview.toggle()
      end)
      hl.bind(mod .. " + SHIFT + TAB", function()
        hl.plugin.overview.toggle("all")
      end)

      hl.bind(mod .. " + S", hl.dsp.workspace.toggle_special("magic"))
      -- Toggle the focused window in/out of the magic scratchpad,
      -- following it to the destination workspace either way.
      hl.bind(mod .. " + ALT + S", scratch_toggle)

      hl.bind(mod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
      hl.bind(mod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

      -- Mouse drag move/resize (upstream example)
      hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(), { mouse = true })
      hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

      -- Keyboard resize, repeating while held (legacy binde).
      hl.bind(mod .. " + CTRL + h", hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true })
      hl.bind(mod .. " + CTRL + j", hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true })
      hl.bind(mod .. " + CTRL + k", hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true })
      hl.bind(mod .. " + CTRL + l", hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true })

      -- Volume goes through wpctl directly so the resulting PipeWire
      -- state change is the OSD trigger — the Quickshell `osd` config
      -- subscribes to PipeWire and shows the popup on every change
      -- (waybar scroll, AVRCP headphone buttons, pavucontrol, any app's
      -- slider) rather than only on these keypresses. Brightness still
      -- routes through swayosd-client because there's no
      -- PipeWire-equivalent event source for backlight changes.
      -- repeating+locked = legacy bindel: repeats while held, works on
      -- the lock screen.
      hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+"), { repeating = true, locked = true })
      hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { repeating = true, locked = true })
      hl.bind("XF86AudioMute", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { repeating = true, locked = true })
      hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { repeating = true, locked = true })
      hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("swayosd-client --brightness raise"), { repeating = true, locked = true })
      hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("swayosd-client --brightness lower"), { repeating = true, locked = true })

      -- Media keys (legacy bindl: work on the lock screen).
      hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
      hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
      hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
    '';
  };

  # Window rules. Unlike legacy one-effect-per-line windowrule keywords, a
  # Lua rule carries all its effects in one table.
  # Reference: https://wiki.hypr.land/Configuring/Basics/Window-Rules/
  xdg.configFile."hypr/nix/rules.lua" = {
    onChange = hyprReload;
    text = ''
      -- Ignore maximize requests from apps — Hyprland's tiler handles layout.
      hl.window_rule({ match = { class = ".*" }, suppress_event = "maximize" })

      -- Fix some dragging issues with XWayland
      hl.window_rule({
        match = {
          class = "^$",
          title = "^$",
          xwayland = true,
          float = true,
          fullscreen = false,
          pin = false,
        },
        no_focus = true,
      })

      -- Open utility/dialog-style apps floating instead of tiled. Rules
      -- are evaluated once against the class at open time. `center`
      -- places the floater mid-monitor rather than at the cursor.
      hl.window_rule({ match = { class = [[^(org\.gnome\.Nautilus)$]] }, float = true, center = true })
      hl.window_rule({ match = { class = [[^(org\.gnome\.Calculator)$]] }, float = true, center = true })

      -- Bitwarden's extension popup is a separate Firefox window, but at
      -- open time it's indistinguishable from a normal browser window:
      -- same class (firefox) and title (Mozilla Firefox). Firefox only
      -- writes the "Extension: (Bitwarden Password Manager)" title after
      -- the page loads — too late for a window rule — so float it from
      -- the title-change event instead (the wiki-recommended pattern for
      -- late title changes). The "Extension:" prefix is Firefox chrome,
      -- never a webpage title, so this can't float the whole browser;
      -- the floating guard keeps later title changes from re-centering a
      -- popup that's been moved. title:find with plain=true is a literal
      -- prefix match, not a Lua pattern.
      hl.on("window.title", function(w)
        if w ~= nil and not w.floating and w.class == "firefox"
            and w.title:find("Extension: (Bitwarden Password Manager)", 1, true) == 1 then
          hl.dispatch(hl.dsp.window.float({ action = "set", window = w }))
          hl.dispatch(hl.dsp.window.center({ window = w }))
        end
      end)
    '';
  };

  # Reload running instances when the HM-generated hyprland.lua itself
  # changes (the module skips its own onChange hook when package = null).
  xdg.configFile."hypr/hyprland.lua".onChange = hyprReload;

  # lua-language-server workspace config so editors autocomplete the hl.*
  # API from the stubs shipped with the hyprland package. The HM module
  # writes this only when it owns the package; with package = null it must
  # be provided manually (pkgs.hyprland == the system package — same
  # nixpkgs).
  xdg.configFile."hypr/.luarc.json".text = builtins.toJSON {
    workspace.library = [ "${pkgs.hyprland}/share/hypr/stubs" ];
    diagnostics.globals = [ "hl" ];
  };

  # Session-wide environment, sourced by uwsm at session start and exported
  # into the systemd activation environment — reaches user services,
  # uwsm-launched apps, and the compositor alike (Hyprland-config `env`
  # lines would only reach the compositor's own children). Shell syntax,
  # one `export KEY=VAL` per line.
  xdg.configFile."uwsm/env".text = ''
    export XCURSOR_THEME=Bibata-Modern-Classic
    export XCURSOR_SIZE=24
    # gcr-ssh-agent's socket (see the home.sessionVariables.SSH_AUTH_SOCK
    # comment). home.sessionVariables only reaches interactive shells via
    # hm-session-vars.sh; anything launched without a shell in between —
    # `ghostty -e ssh-dev-vm` binds, waybar's VM-pill ssh — sees only the
    # systemd activation environment, so the socket must be exported here
    # too or every such ssh falls back to per-invocation passphrase prompts.
    export SSH_AUTH_SOCK=$XDG_RUNTIME_DIR/gcr/ssh
    # Canonical screenshots dir — grimblast and most XDG-aware tools honour it.
    export XDG_SCREENSHOTS_DIR=${config.home.homeDirectory}/Pictures/Screenshots
    # Without the librsvg loader cache, GTK apps render SVG assets (e.g.
    # wlogout's button icons) as broken-image placeholders.
    export GDK_PIXBUF_MODULE_FILE=${pkgs.librsvg}/lib/gdk-pixbuf-2.0/2.10.0/loaders.cache
  '';
  # HYPR*/AQ_* variables belong in env-hyprland, which uwsm exports only to
  # the compositor unit rather than the whole session.
  xdg.configFile."uwsm/env-hyprland".text = ''
    export HYPRCURSOR_SIZE=24
  '';

  # Two Waybar instances, each pinned to one output (omitting `output`
  # spawns on every monitor and races across rebuilds). `primaryBar` on
  # the ultrawide covers the GNOME top-right popup equivalent (workspaces,
  # tray, idle inhibitor, audio, network, clock); nm-applet +
  # blueman-applet surface in `tray`. `secondaryBar` on HDMI-A-1 is
  # minimal — just workspaces + focused window title — so the upper
  # monitor's active workspace is visible at a glance.
  programs.waybar = {
    enable = true;
    systemd.enable = true;
    # Catppuccin Mocha palette + styling adapted from rubyowo's reference
    # dotfiles (linked from the catppuccin/waybar README as the preview
    # image source — github.com/rubyowo/dotfiles, commit f925cf8).
    # Aesthetic: transparent bar with floating @surface0 pill modules,
    # rounded outer corners on the leftmost (cpu) and rightmost (clock)
    # of the right group, per-module accent colours, 15pt FiraCode.
    style = ''
      @define-color rosewater #f5e0dc;
      @define-color flamingo  #f2cdcd;
      @define-color pink      #f5c2e7;
      @define-color mauve     #cba6f7;
      @define-color red       #f38ba8;
      @define-color maroon    #eba0ac;
      @define-color peach     #fab387;
      @define-color yellow    #f9e2af;
      @define-color green     #a6e3a1;
      @define-color teal      #94e2d5;
      @define-color sky       #89dceb;
      @define-color sapphire  #74c7ec;
      @define-color blue      #89b4fa;
      @define-color lavender  #b4befe;
      @define-color text      #cdd6f4;
      @define-color subtext1  #bac2de;
      @define-color subtext0  #a6adc8;
      @define-color overlay2  #9399b2;
      @define-color overlay1  #7f849c;
      @define-color overlay0  #6c7086;
      @define-color surface2  #585b70;
      @define-color surface1  #45475a;
      @define-color surface0  #313244;
      @define-color base      #1e1e2e;
      @define-color mantle    #181825;
      @define-color crust     #11111b;

      * {
        font-family: "FiraCode Nerd Font", sans-serif;
        font-size: 15px;
        font-weight: bold;
        min-height: 0;
      }

      window#waybar {
        background: transparent;
        color: @text;
        margin: 5px 5px;
      }

      /* Left: workspaces pill */
      #workspaces {
        border-radius: 1rem;
        margin: 5px;
        background-color: @surface0;
        margin-left: 1rem;
      }
      #workspaces button {
        color: @lavender;
        border-radius: 1rem;
        padding: 0.2rem 0.5rem;
      }
      #workspaces button.active {
        background-color: @sky;
        color: @base;
        border-radius: 1rem;
        font-weight: bold;
      }
      #workspaces button.urgent {
        color: @red;
      }
      #workspaces button:hover {
        color: @sapphire;
        border-radius: 1rem;
      }

      /* Center: focused window title, matching @surface0 pill so the
         text stays legible over light wallpapers. */
      #window {
        color: @text;
        background-color: @surface0;
        border-radius: 1rem;
        padding: 0.3rem 0.75rem;
        margin: 5px 0;
      }

      /* Center: submap indicator. Hidden by Waybar when no submap is
         active; flips to a filled peach pill the moment one is entered
         (e.g. resize mode via Super+R). Dark text + bright background so
         it's impossible to miss against the transparent bar. */
      #submap {
        background-color: @peach;
        color: @base;
        border-radius: 1rem;
        padding: 0.3rem 0.75rem;
        margin: 5px 0.5rem;
      }

      /* Right side: four independent pills.
         Group 1 (system metrics): cpu - memory - temperature - disk - power-profiles-daemon
         Group 2 (tray): standalone
         Group 3 (connectivity/controls): idle_inhibitor - pulseaudio - network - custom-notification
         Group 4 (clock): standalone */
      #cpu,
      #custom-host-memory,
      #temperature,
      #temperature.gpu,
      #disk,
      #power-profiles-daemon,
      #custom-vm-memory,
      #custom-vm-disk-nix,
      #custom-vm-disk-home,
      #tray,
      #custom-darkman,
      #custom-screenshot,
      #custom-suspend-inhibit,
      #idle_inhibitor,
      #pulseaudio,
      #network,
      #custom-notification,
      #clock,
      #custom-power {
        background-color: @surface0;
        padding: 0.5rem 0.75rem;
        margin: 5px 0;
      }

      /* Group 1: system metrics */
      #cpu {
        color: @peach;
        border-radius: 1rem 0 0 1rem;
        margin-left: 1rem;
      }
      /* Host RAM (custom/host-memory, replacing Waybar's native memory
         module so it can subtract the VM's reclaimable footprint).
         Escalates peach → red as effective machine pressure climbs. */
      #custom-host-memory {
        color: @yellow;
      }
      #custom-host-memory.warning {
        color: @peach;
      }
      #custom-host-memory.critical {
        background-color: @red;
        color: @base;
      }
      #temperature {
        color: @maroon;
      }
      /* GPU temp pill — sapphire to distinguish from the maroon CPU pill
         sitting just to its left. */
      #temperature.gpu {
        color: @sapphire;
      }
      /* Above critical-threshold: pill flips to a filled red background
         with dark text so it's hard to miss. Applies to both CPU and
         GPU pills via the shared #temperature ID. */
      #temperature.critical {
        background-color: @red;
        color: @base;
      }
      #disk {
        color: @teal;
      }
      #power-profiles-daemon {
        color: @mauve;
        border-radius: 0 1rem 1rem 0;
        /* Tighter left padding so the icon sits closer to temperature;
           extra right padding so content doesn't crowd the rounded edge. */
        padding-left: 0.25rem;
        padding-right: 1rem;
        margin-right: 0.5rem;
      }
      /* VM metrics: their own pill group (sky), set off from the host
         system-metrics group to its left. Order is RAM, nix-store disk,
         /home disk; the first rounds the left edge and the last the right,
         the middle pill stays square so the group reads as one unit.
         `.warning`/`.critical` escalate as the guest fills RAM or a
         volume; `.off` dims the group when the VM is down. */
      #custom-vm-memory {
        color: @sky;
        border-radius: 1rem 0 0 1rem;
        margin-left: 0.5rem;
      }
      #custom-vm-disk-nix {
        color: @sky;
      }
      #custom-vm-disk-home {
        color: @sky;
        border-radius: 0 1rem 1rem 0;
        margin-right: 0.5rem;
      }
      #custom-vm-memory.warning,
      #custom-vm-disk-nix.warning,
      #custom-vm-disk-home.warning {
        color: @peach;
      }
      #custom-vm-memory.critical,
      #custom-vm-disk-nix.critical,
      #custom-vm-disk-home.critical {
        background-color: @red;
        color: @base;
      }
      #custom-vm-memory.off,
      #custom-vm-disk-nix.off,
      #custom-vm-disk-home.off {
        color: @overlay0;
      }
      #power-profiles-daemon.performance {
        color: @red;
      }
      #power-profiles-daemon.power-saver {
        color: @green;
      }

      /* Group 2: tray (standalone pill) */
      #tray {
        color: @text;
        border-radius: 1rem;
        margin-right: 0.5rem;
      }

      /* darkman toggle (standalone pill between tray and connectivity).
         Glyph colour follows mode via the `class` field on the JSON
         output — sun-yellow when light, lavender when dark. */
      #custom-darkman {
        border-radius: 1rem;
        margin-right: 0.5rem;
      }
      #custom-darkman.light {
        color: @yellow;
      }
      #custom-darkman.dark {
        color: @lavender;
      }

      /* Screenshot trigger (standalone pill, sapphire-blue camera).
         Padding asymmetric to compensate for the U+F030 camera glyph's
         internal whitespace within its character cell — same trick as
         #custom-power below. Shared rule is 0.75rem horizontal; nudge
         by 0.125rem so the glyph sits visually centered. */
      #custom-screenshot {
        color: @sapphire;
        border-radius: 1rem;
        padding-left: 0.625rem;
        padding-right: 0.875rem;
        margin-right: 0.5rem;
      }

      /* Idle auto-suspend toggle (standalone pill). Calm lavender bed glyph
         when suspend is armed; flips to a yellow bolt when suspend is
         inhibited (machine staying awake), matching #idle_inhibitor.activated. */
      #custom-suspend-inhibit {
        color: @lavender;
        border-radius: 1rem;
        margin-right: 0.5rem;
      }
      #custom-suspend-inhibit.active {
        color: @yellow;
      }

      /* Group 3: connectivity / controls */
      #idle_inhibitor {
        color: @lavender;
        border-radius: 1rem 0 0 1rem;
      }
      #idle_inhibitor.activated {
        color: @yellow;
      }
      #pulseaudio {
        color: @maroon;
      }
      #pulseaudio.muted {
        color: @overlay0;
      }
      #network {
        color: @teal;
      }
      #network.disconnected {
        color: @overlay0;
      }
      #custom-notification {
        color: @pink;
        border-radius: 0 1rem 1rem 0;
        /* Extra right-padding so the bell glyph doesn't crowd the rounded edge. */
        padding-right: 1rem;
        margin-right: 0.5rem;
      }

      /* Group 4: clock (standalone pill) */
      #clock {
        color: @text;
        border-radius: 1rem;
      }

      /* Group 5: power button (standalone pill) — click opens wlogout.
         Padding is slightly asymmetric to compensate for the U+F011 power
         glyph's own internal whitespace within its character cell.
         Shared rule is 0.75rem horizontal; we nudge by 0.125rem. */
      #custom-power {
        color: @red;
        border-radius: 1rem;
        padding-left: 0.625rem;
        padding-right: 0.875rem;
        margin-left: 0.5rem;
        margin-right: 1rem;
      }

      tooltip {
        background: @surface0;
        color: @text;
        border: 1px solid @overlay0;
      }
    '';
    settings.primaryBar = {
      output = [ "DP-2" ];
      layer = "top";
      position = "top";
      # 0 removes the default 4px inter-module gap so each pill group
      # joins seamlessly; the gaps *between* groups come from the
      # margin-right values on the last module of each group in style.css.
      spacing = 0;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [
        "hyprland/submap"
        "hyprland/window"
      ];
      modules-right = [
        "cpu"
        "custom/host-memory"
        "temperature"
        "temperature#gpu"
        "disk"
        "power-profiles-daemon"
        "custom/vm-memory"
        "custom/vm-disk-nix"
        "custom/vm-disk-home"
        "tray"
        "custom/darkman"
        "custom/screenshot"
        "custom/suspend-inhibit"
        "idle_inhibitor"
        "pulseaudio"
        "network"
        "custom/notification"
        "clock"
        "custom/power"
      ];
      "hyprland/submap" = {
        # Hyprland emits an IPC `submap` event on enter/exit; Waybar's
        # module hides itself when the submap is empty (default state) and
        # shows this format string while one is active. Adds a CSS class
        # matching the submap name (e.g. `#submap.resize`) for per-mode
        # styling if ever needed.
        format = "󰩨 {}"; # nf-md-resize
        tooltip = false;
      };
      "hyprland/window" = {
        # Prefix the title with the app class so visually-identical
        # terminals (ghostty + kitty share a theme) are distinguishable.
        # `rewrite` keys are full-match regexes; the `(.*)` tail recaptures
        # the title. Ghostty's Wayland class is the reverse-DNS app_id.
        separate-outputs = true;
        format = "{class}  {title}";
        rewrite = {
          "com.mitchellh.ghostty  (.*)" = "  ghostty  $1"; # nf-fa-terminal
          "kitty  (.*)" = "  kitty  $1";
        };
      };
      clock = {
        # Pango span (typecraft-style) colours just the calendar glyph
        # @pink — the time itself inherits the module's @text colour.
        format = "<span foreground='#f5c2e7'></span>  {:%a %b %d  %I:%M %p}";
        tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
      };
      # Glyphs below are Nerd Font codepoints from Waybar's upstream
      # config.jsonc. They render blank in plain editors but resolve to
      # icons via the FiraCode Nerd Font installed in gui.nix.
      cpu.format = "{usage}% "; # nf-fa-microchip
      cpu.interval = 1;
      disk = {
        format = "{percentage_used}% 󰋊"; # nf-md-harddisk
        tooltip-format = "{used} used / {total} total on {path}";
      };
      # Guest-truthful RAM/disk for the dev microvm (scripts in the let
      # block). 5s interval keeps the VSOCK ssh light; both VM pills share
      # one fetch via the cache, and render `--` when the VM is down. The
      # host-memory pill replaces Waybar's native `memory` module so it can
      # discount the VM's reclaimable footprint.
      "custom/host-memory" = {
        return-type = "json";
        format = "{}";
        exec = "${hostMemPill}";
        interval = 2;
      };
      "custom/vm-memory" = {
        return-type = "json";
        format = "{}";
        exec = "${vmMemPill}";
        interval = 5;
      };
      "custom/vm-disk-nix" = {
        return-type = "json";
        format = "{}";
        exec = "${vmDiskNixPill}";
        interval = 5;
      };
      "custom/vm-disk-home" = {
        return-type = "json";
        format = "{}";
        exec = "${vmDiskHomePill}";
        interval = 5;
      };
      tray.spacing = 10;
      power-profiles-daemon = {
        format = "{icon}";
        tooltip-format = "Power profile: {profile}\nDriver: {driver}";
        format-icons = {
          default = ""; # nf-fa-bolt
          performance = ""; # nf-fa-bolt
          balanced = ""; # nf-fa-balance-scale
          power-saver = ""; # nf-fa-leaf
        };
      };
      pulseaudio = {
        format = "{volume}% {icon}";
        format-muted = "";
        format-icons.default = [
          ""
          ""
          ""
        ];
        format-bluetooth = "{volume}% {icon}"; # nf-fa-bluetooth
        format-bluetooth-muted = "{icon}";
        # Scroll/click adjust PipeWire directly via wpctl — the
        # Quickshell `osd` config picks up the resulting state change
        # and renders the popup, the same way the XF86Audio binds and
        # external sources (BT headphones, pavucontrol) flow through.
        # Right-click still opens pavucontrol for routing.
        on-scroll-up = "${pkgs.wireplumber}/bin/wpctl set-volume -l 1.5 @DEFAULT_AUDIO_SINK@ 5%+";
        on-scroll-down = "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-";
        on-click = "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
        on-click-right = "pavucontrol";
      };
      temperature = {
        # Pin to k10temp's Tctl on the AMD CPU. Without this, waybar's
        # auto-pick lands on the acpitz chassis sensor which sits at room
        # temperature (~17°C) regardless of CPU load. The PCI path is the
        # stable host bridge for k10temp on Ryzen platforms (function 18.3
        # under the root domain); hwmonN inside it can be renumbered, but
        # there's only one hwmon entry under this directory so waybar
        # picks it unambiguously.
        hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:18.3/hwmon";
        input-filename = "temp1_input";
        interval = 5;
        critical-threshold = 80;
        format = "{temperatureC}°C 󰔏"; # nf-md-thermometer
      };
      # dGPU edge temp from amdgpu. The PCI path is for the discrete card
      # (multiple bridges deep); the iGPU's amdgpu sibling sits closer to
      # the root and is ignored here. critical bumped to 90°C because AMD
      # dGPUs sustain higher idle/load temps than the CPU.
      "temperature#gpu" = {
        hwmon-path-abs = "/sys/devices/pci0000:00/0000:00:01.1/0000:01:00.0/0000:02:00.0/0000:03:00.0/hwmon";
        input-filename = "temp1_input";
        interval = 5;
        critical-threshold = 90;
        format = "{temperatureC}°C 󰢮"; # nf-md-vga
      };
      network = {
        interval = 5;
        # Right-pad each value so the pill width is constant — without
        # padding, the whole right side of the bar shifts left/right
        # every second as digits roll over (e.g. 9KB → 10KB → 100KB).
        # Waybar auto-bumps the unit at 1000, so bandwidth maxes at
        # "999XB" (5 chars) at any magnitude; signal is 0–100 (3 chars).
        format-wifi = " {bandwidthDownBytes:>5}  {bandwidthUpBytes:>5}   {signalStrength:>3}% "; # nf-fa-arrow-down, nf-fa-arrow-up, nf-fa-wifi
        format-ethernet = " {bandwidthDownBytes:>5}  {bandwidthUpBytes:>5}  󰌗 "; # nf-fa-arrow-down, nf-fa-arrow-up, nf-md-lan
        format-disconnected = "Disconnected  "; # nf-fa-times
        tooltip-format = "{ifname}: {ipaddr}";
      };
      "custom/notification" = {
        tooltip = false;
        format = "{icon}";
        format-icons = {
          notification = "󰂚"; # nf-md-bell_badge
          none = "󰂜"; # nf-md-bell_off
          dnd-notification = "󰂛"; # nf-md-bell_cancel
          dnd-none = "󰂛";
        };
        return-type = "json";
        exec-if = "which swaync-client";
        exec = "swaync-client -swb";
        on-click = "swaync-client -t -sw";
        on-click-right = "swaync-client -d -sw";
        escape = true;
      };
      # darkman state pill — `class` is set to "light"/"dark" so the CSS
      # below can colour the glyph differently per mode. `signal = 8` makes
      # Waybar re-run `exec` on SIGRTMIN+8, which darkman's light/dark
      # mode-scripts (services.darkman below) raise immediately on
      # transition — instant icon update without a busy poll. `interval`
      # is a 60s fallback in case the signal is dropped.
      "custom/darkman" = {
        return-type = "json";
        format = "{}";
        exec = "${pkgs.writeShellScript "waybar-darkman" ''
          # darkman 2.x prints `LIGHT` / `DARK` (uppercase) followed by a
          # newline; normalise both case and whitespace so the case match
          # is stable across versions.
          state=$(${pkgs.darkman}/bin/darkman get 2>/dev/null \
            | tr '[:upper:]' '[:lower:]' \
            | tr -d '[:space:]')
          # Glyphs declared via $'\uXXXX' (bash ANSI-C quoting) instead
          # of literal UTF-8 bytes — keeps the Nix source ASCII-safe and
          # immune to editor-roundtrip stripping of non-ASCII characters.
          # F185 = nf-fa-sun_o, F186 = nf-fa-moon_o.
          case "$state" in
            light) icon=$'' ;;
            dark)  icon=$'' ;;
            *)     state="unknown"; icon="?" ;;
          esac
          # Use a heredoc-free printf with the long-form em-dash escape
          # for the same reason.
          printf '{"text":"%s","class":"%s","alt":"%s","tooltip":"%s mode — click to toggle"}\n' \
            "$icon" "$state" "$state" "$state"
        ''}";
        on-click = "${pkgs.darkman}/bin/darkman toggle";
        signal = 8;
        interval = 60;
      };
      "custom/power" = {
        tooltip = false;
        format = ""; # nf-fa-power_off (U+F011) — injected as a literal byte below
        # wlogout default stretches buttons to fill the screen — passing per-side
        # margins shrinks the active area. On a 3440px ultrawide, 1200px L/R +
        # 350px T/B centres the 2x3 grid at \~340x370 buttons.
        # uwsm app: launched from waybar's unit, wlogout would otherwise die
        # if waybar restarts; a scope of its own also matches the Super+Esc
        # bind's placement.
        on-click = "uwsm app -- ${pkgs.wlogout}/bin/wlogout -L 1200 -R 1200 -T 350 -B 350";
      };
      # Screenshot pill — mirrors the Print/Shift+Print/Ctrl+Print binds.
      # Click: drag-select region. Right-click: focused window.
      # Middle-click: whole focused monitor. All three save to
      # ~/Pictures/Screenshots and copy the image to the clipboard.
      "custom/screenshot" = {
        tooltip = true;
        tooltip-format = "Click: region\nRight-click: window\nMiddle-click: monitor";
        format = ""; # nf-fa-camera (U+F030)
        on-click = "${hyprshotCmd} -m region";
        on-click-right = "${hyprshotCmd} -m window";
        on-click-middle = "${hyprshotCmd} -m output";
      };
      idle_inhibitor = {
        format = "{icon}";
        format-icons = {
          activated = "";
          deactivated = "";
        };
        tooltip-format-activated = "Idle inhibited (presentation mode)";
        tooltip-format-deactivated = "Click to inhibit idle";
      };
      # Idle auto-suspend toggle. Signal-driven (no polling): runs once at
      # startup and again whenever toggleSuspendInhibit sends SIGRTMIN+9.
      "custom/suspend-inhibit" = {
        return-type = "json";
        format = "{}";
        exec = "${suspendInhibitPill}";
        on-click = "${toggleSuspendInhibit}";
        signal = 9;
      };
    };
    settings.secondaryBar = {
      output = [ "HDMI-A-1" ];
      layer = "top";
      position = "top";
      spacing = 0;
      modules-left = [ "hyprland/workspaces" ];
      modules-center = [
        "hyprland/submap"
        "hyprland/window"
      ];
      modules-right = [ ];
      "hyprland/window" = {
        separate-outputs = true;
        format = "{class}  {title}";
        rewrite = {
          "com.mitchellh.ghostty  (.*)" = "  ghostty  $1"; # nf-fa-terminal
          "kitty  (.*)" = "  kitty  $1";
        };
      };
    };
  };

  # hyprpaper — wallpaper daemon. Per-monitor wallpapers sourced from
  # ~/Pictures (not the Nix store) so they're easy to swap without a
  # rebuild. `splash = false` suppresses the boot splash overlay.
  #
  # hyprpaper 0.8 (the hyprtoolkit rewrite) dropped the old flat syntax
  # (`preload = PATH` + `wallpaper = MONITOR,PATH`) in favour of anonymous
  # `wallpaper { }` blocks that carry the monitor and path together; there
  # is no separate preload step. The old keys are parsed but ignored, so a
  # stale config leaves every monitor on the default. One block per monitor;
  # an empty `monitor` would make that block the fallback for any unlisted
  # output.
  services.hyprpaper = {
    enable = true;
    settings = {
      splash = false;
      wallpaper = [
        {
          monitor = "DP-2";
          path = wallpaperDP2;
          fit_mode = "cover";
        }
        {
          monitor = "HDMI-A-1";
          path = wallpaperHDMI;
          fit_mode = "cover";
        }
      ];
    };
  };

  # Generate the pre-blurred hyprlock backgrounds once per graphical login
  # (see blurWallpapers). oneshot + RemainAfterExit so it runs once and stays
  # "active"; hyprlock reads the cached PNGs on demand, so this need only
  # finish before the first lock, not block the session.
  systemd.user.services.hyprlock-bg = {
    Unit = {
      Description = "Pre-blur wallpapers for the hyprlock background";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${blurWallpapers}";
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # hypridle — dim → DPMS off (power save) → lock (security threshold).
  # Black screen and lock are deliberately separate: walking away for a
  # minute should not require re-authing. hyprsunset's gamma filter
  # handles the dim step (works on externals without backlight). Waybar's
  # idle_inhibitor module ties into the same wayland-inhibit protocol
  # hypridle honours, so clicking the eye pauses every timer
  # (Caffeine-style presentation mode).
  services.hypridle = {
    enable = true;
    settings = {
      general = {
        after_sleep_cmd = "hyprctl dispatch dpms on";
        before_sleep_cmd = "loginctl lock-session";
        lock_cmd = "pidof hyprlock || hyprlock";
        # Hold the logind sleep inhibitor until hyprlock has actually locked
        # the session, so an idle-suspend can never resume to a briefly
        # unlocked desktop. `3` waits on the wayland session-lock app
        # specifically (vs the default `2`/auto), which matters now that the
        # listener below can trigger a real suspend.
        inhibit_sleep = 3;
      };
      listener = [
        {
          timeout = 295;
          on-timeout = "hyprctl hyprsunset gamma 50";
          on-resume = "hyprctl hyprsunset gamma 100";
        }
        {
          timeout = 300;
          # Per-output Waybar bars leak surfaces across a wl_output
          # destroy/create cycle, leaving N stacked copies on a monitor
          # after a few DPMS idle/wake rounds. Stopping Waybar before
          # the output is destroyed avoids the bug condition.
          on-timeout = "systemctl --user stop waybar.service && hyprctl dispatch dpms off";
          on-resume = "hyprctl dispatch dpms on && systemctl --user start waybar.service";
        }
        {
          timeout = 600;
          on-timeout = "loginctl lock-session";
        }
        {
          # Final step: suspend after 30 min idle, unless the Waybar suspend
          # pill has armed the inhibit flag — see suspendUnlessInhibited.
          # before_sleep_cmd locks first, so it always resumes to a lock
          # screen.
          timeout = 1800;
          on-timeout = "${suspendUnlessInhibited}";
        }
      ];
    };
  };

  # hyprlock — upstream example config (share/hypr/hyprlock.conf at the
  # version pinned by nixpkgs), minus the en/ru layout-switcher label.
  programs.hyprlock = {
    enable = true;
    settings = {
      general = {
        hide_cursor = false;
        # Draw widgets (clock, input field) immediately rather than waiting on
        # the background resource, and render the pre-blurred PNGs below with
        # no runtime blur — so lock/wake never stalls on image work.
        immediate_render = true;
      };
      animations = {
        enabled = true;
        bezier = "linear, 1, 1, 0, 0";
        animation = [
          "fadeIn, 1, 5, linear"
          "fadeOut, 1, 5, linear"
          "inputFieldDots, 1, 2, linear"
        ];
      };
      background = [
        {
          monitor = "DP-2";
          path = lockBgDP2;
          blur_passes = 0;
        }
        {
          monitor = "HDMI-A-1";
          path = lockBgHDMI;
          blur_passes = 0;
        }
      ];
      input-field = [
        {
          monitor = "DP-2";
          size = "20%, 5%";
          outline_thickness = 3;
          inner_color = "rgba(0, 0, 0, 0.0)";
          outer_color = "rgba(89b4faee) rgba(cba6f7ee) 45deg"; # blue → mauve
          check_color = "rgba(a6e3a1ee) rgba(94e2d5ee) 120deg"; # green → teal
          fail_color = "rgba(f38ba8ee) rgba(eba0acee) 40deg"; # red → maroon
          font_color = "rgb(205, 214, 244)"; # text
          fade_on_empty = false;
          rounding = 15;
          font_family = "Monospace";
          placeholder_text = "Input password...";
          fail_text = "$PAMFAIL";
          dots_spacing = 0.3;
          position = "0, -20";
          halign = "center";
          valign = "center";
        }
      ];
      label = [
        {
          monitor = "DP-2";
          text = "$TIME";
          font_size = 90;
          font_family = "Monospace";
          position = "-30, 0";
          halign = "right";
          valign = "top";
        }
        {
          monitor = "DP-2";
          text = ''cmd[update:60000] date +"%A, %d %B %Y"'';
          font_size = 25;
          font_family = "Monospace";
          position = "-30, -150";
          halign = "right";
          valign = "top";
        }
      ];
    };
  };

  # hyprsunset — Night Light equivalent (replaces gnome-control-center's
  # toggle, which is inert under Hyprland). 3500K sits at the warm end of
  # the "warm but not orange" range (GNOME's night-light default is 4000K);
  # gamma 0.9 dims the ramp slightly at night. Note the unit split: profile
  # gamma is a 0.0–1.0 fraction (0.9 = 90%), but the runtime `hyprctl
  # hyprsunset gamma` IPC takes a percent (0–100). The daemon also handles
  # hypridle's `gamma` IPC calls for the dim-before-DPMS-off step — the
  # active profile's gamma is overridden until the next profile boundary, so
  # the two uses don't fight.
  services.hyprsunset = {
    enable = true;
    settings.profile = [
      {
        time = "06:30";
        identity = true;
      }
      {
        time = "20:00";
        temperature = 3500;
        gamma = 0.9;
      }
    ];
  };

  # Time-of-day backlight for the DisplayPort primary (Viewteck GNV34DBE).
  # hyprsunset only shifts colour temperature/gamma; the panel's actual
  # brightness is driven over DDC/CI with ddcutil (VCP 0x10), enabled at the
  # system level in hosts/desktop/default.nix. `--model GNV34DBE` scopes the
  # write to the primary so the secondary HP panel is left alone. The script
  # picks the level from the current time rather than using two independent
  # day/night timers, so a mid-day boot or login lands on the right value
  # with no firing-order ambiguity. Boundaries match the hyprsunset schedule.
  # (ddcutil retries the I2C transaction itself, so no shell retry is needed.)
  systemd.user.services.monitor-brightness = {
    Unit = {
      Description = "Set DP primary monitor brightness by time of day";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "monitor-brightness" ''
        # 10# forces base-10 so HHMM like 0820 isn't parsed as invalid octal.
        hhmm=$((10#$(${pkgs.coreutils}/bin/date +%H%M)))
        if [ "$hhmm" -ge 630 ] && [ "$hhmm" -lt 2000 ]; then
          level=50
        else
          level=25
        fi
        ${pkgs.ddcutil}/bin/ddcutil --model GNV34DBE setvcp 10 "$level"
      '';
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
  systemd.user.timers.monitor-brightness = {
    Unit.Description = "Apply time-of-day monitor brightness at the day/night boundaries";
    Timer = {
      OnCalendar = [
        "*-*-* 06:30:00"
        "*-*-* 20:00:00"
      ];
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # darkman — light/dark mode switch. A toggle writes
  # `org.gnome.desktop.interface color-scheme` to dconf; xdg-desktop-portal-gtk
  # reads that key and re-broadcasts via the freedesktop `Settings` portal —
  # Ghostty's `dark:.../light:...` theme split, auto-dark-mode.nvim
  # (apps/nvim.nix), and Firefox's prefers-color-scheme all subscribe to that
  # portal, so the whole stack flips in unison. No automatic schedule: darkman
  # switches on sunrise/sunset for a configured location, and with none set
  # (and geoclue off, its default) it makes no transitions — it just restores
  # the last mode from its cache, seeded to dark below. `Super+Shift+D`
  # toggles manually.
  services.darkman = {
    enable = true;
    # darkman 2.2.0 aborts at startup if no config file exists, so emit one
    # even though every value here is already darkman's default. usegeoclue
    # false (no geolocation) keeps the no-automatic-schedule behaviour
    # described above; mode is driven entirely by the manual toggle.
    settings.usegeoclue = false;
    darkModeScripts = {
      gtk-theme = ''
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-dark'"
      '';
      # Refresh the custom/darkman Waybar pill instantly — matches the
      # `signal = 8` on the module so it re-runs `darkman get` and swaps
      # the sun/moon glyph + class without waiting for the 60s poll.
      waybar-refresh = ''
        ${pkgs.procps}/bin/pkill -RTMIN+8 waybar || true
      '';
      # Notify running nvim instances on the host instantly via RPC so the
      # colorscheme switches without waiting for auto-dark-mode's 3-second
      # poll. Default nvim socket layout is $XDG_RUNTIME_DIR/nvim.<pid>.0.
      # <Cmd> fires the Ex command regardless of current mode. VM-side
      # nvim instances aren't reachable from here (separate runtime dir).
      nvim-dark = ''
        for sock in "''${XDG_RUNTIME_DIR:-/run/user/$UID}"/nvim.*.0; do
          [ -S "$sock" ] && ${pkgs.neovim}/bin/nvim --server "$sock" \
            --remote-send '<Cmd>DarkMode<CR>' 2>/dev/null &
        done
        true
      '';
    };
    lightModeScripts = {
      gtk-theme = ''
        ${pkgs.dconf}/bin/dconf write /org/gnome/desktop/interface/color-scheme "'prefer-light'"
      '';
      waybar-refresh = ''
        ${pkgs.procps}/bin/pkill -RTMIN+8 waybar || true
      '';
      nvim-light = ''
        for sock in "''${XDG_RUNTIME_DIR:-/run/user/$UID}"/nvim.*.0; do
          [ -S "$sock" ] && ${pkgs.neovim}/bin/nvim --server "$sock" \
            --remote-send '<Cmd>LightMode<CR>' 2>/dev/null &
        done
        true
      '';
    };
  };

  # darkman applies its cached mode on startup and runs no transitions without
  # a location, so seed the cache to dark for a dark-by-default first boot.
  # Written with no trailing newline — darkman matches the file's exact bytes
  # against "dark"/"light". A `Super+Shift+D` toggle overwrites this and
  # persists across reboots; the seed only fills a missing cache (fresh machine
  # or cleared ~/.cache).
  home.activation.darkmanDefaultDark = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    cacheDir="''${XDG_CACHE_HOME:-$HOME/.cache}/darkman"
    if [ ! -e "$cacheDir/mode.txt" ]; then
      mkdir -p "$cacheDir"
      printf 'dark' > "$cacheDir/mode.txt"
    fi
  '';

  # swayosd — centered OSD popup for brightness and caps-lock changes.
  # Volume OSD lives in the Quickshell `osd` config above, which is
  # event-driven on PipeWire state and so catches volume changes from
  # any source rather than only the keypresses we wire to it.
  services.swayosd.enable = true;

  programs.wlogout = {
    enable = true;
    layout = [
      {
        label = "lock";
        action = "loginctl lock-session";
        text = "Lock";
        keybind = "l";
      }
      {
        label = "logout";
        # Not `hyprctl dispatch exit` — that kills the compositor out from
        # under uwsm's session units; `uwsm stop` tears the session down in
        # order.
        action = "uwsm stop";
        text = "Logout";
        keybind = "e";
      }
      {
        label = "suspend";
        action = "systemctl suspend";
        text = "Suspend";
        keybind = "u";
      }
      {
        label = "hibernate";
        action = "systemctl hibernate";
        text = "Hibernate";
        keybind = "h";
      }
      {
        label = "reboot";
        action = "systemctl reboot";
        text = "Reboot";
        keybind = "r";
      }
      {
        label = "shutdown";
        action = "systemctl poweroff";
        text = "Shutdown";
        keybind = "s";
      }
    ];
    style =
      let
        icons = "${config.home.homeDirectory}/repos/clones/hyprland/catppuccin/wlogout/icons/wleave/mocha/blue";
      in
      ''
        * {
          background-image: none;
          box-shadow: none;
        }
        window {
          background-color: rgba(30, 30, 46, 0.90);
        }
        button {
          border-radius: 0;
          border-color: #89b4fa;
          text-decoration-color: #cdd6f4;
          color: #cdd6f4;
          background-color: #181825;
          border-style: solid;
          border-width: 1px;
          background-repeat: no-repeat;
          background-position: center;
          background-size: 25%;
        }
        button:focus, button:active, button:hover {
          background-color: rgb(48, 50, 66);
          outline-style: none;
        }
        #lock      { background-image: image(url("${icons}/lock.svg")); }
        #logout    { background-image: image(url("${icons}/logout.svg")); }
        #suspend   { background-image: image(url("${icons}/suspend.svg")); }
        #hibernate { background-image: image(url("${icons}/hibernate.svg")); }
        #reboot    { background-image: image(url("${icons}/reboot.svg")); }
        #shutdown  { background-image: image(url("${icons}/shutdown.svg")); }
      '';
  };

  programs.fuzzel = {
    enable = true;
    settings = {
      main = {
        font = "FiraCode Nerd Font Mono:size=14";
        prompt = "❯  ";
        lines = 10;
        width = 35;
        layer = "overlay";
        # Desktop entries launched from the menu get their own systemd scope
        # instead of living (and dying) inside fuzzel's parent unit — same
        # placement as the `uwsm app --` prefixes on the Hyprland binds.
        launch-prefix = "uwsm app --";
      };
      colors = {
        # Catppuccin Mocha, blue accent (github.com/catppuccin/fuzzel)
        background = "1e1e2edd";
        text = "cdd6f4ff";
        prompt = "bac2deff";
        placeholder = "7f849cff";
        input = "cdd6f4ff";
        match = "89b4faff";
        selection = "585b70ff";
        selection-text = "cdd6f4ff";
        selection-match = "89b4faff";
        counter = "7f849cff";
        border = "89b4faff";
      };
      border = {
        width = 2;
        radius = 12;
      };
    };
  };

  services.swaync = {
    enable = true;
    settings = {
      # mpris first so playback controls sit at the top of the panel.
      # Spotify song-change popups arrive via D-Bus notifications and need
      # no extra config — the mpris widget reads the MPRIS2 interface
      # directly for transport controls (prev/play/next/scrub).
      widgets = [
        "mpris"
        "dnd"
        "title"
        "notifications"
      ];
      widget-config.mpris.autohide = true;

      # Append every incoming notification to a plain-text log so content
      # can be retrieved after a popup is dismissed. No match conditions =
      # catches all notifications. Env vars injected by swaync per
      # configModel.vala: SWAYNC_APP_NAME, SWAYNC_SUMMARY, SWAYNC_BODY.
      scripts.log-all.exec = "${swayncLog}";
    };
    # Catppuccin Mocha — expanded from github.com/catppuccin/swaync _theme.scss
    # with mocha palette variables substituted to plain hex values.
    style = ''
      * {
        all: unset;
        font-size: 14px;
        font-family: "FiraCode Nerd Font Mono";
        transition: 200ms;
      }
      trough highlight { background: #cdd6f4; }
      scale { margin: 0 7px; }
      scale trough { margin: 0rem 1rem; min-height: 8px; min-width: 70px; border-radius: 12.6px; }
      trough slider {
        margin: -10px;
        border-radius: 12.6px;
        box-shadow: 0 0 2px rgba(0,0,0,0.8);
        transition: all 0.2s ease;
        background-color: #89b4fa;
      }
      trough slider:hover { box-shadow: 0 0 2px rgba(0,0,0,0.8), 0 0 8px #89b4fa; }
      trough { background-color: #313244; }

      .notification-background {
        box-shadow: 0 0 8px 0 rgba(0,0,0,0.8), inset 0 0 0 1px #45475a;
        border-radius: 12.6px;
        margin: 18px;
        background: #181825;
        color: #cdd6f4;
        padding: 0;
      }
      .notification-background .notification { padding: 7px; border-radius: 12.6px; }
      .notification-background .notification.critical { box-shadow: inset 0 0 7px 0 #f38ba8; }
      .notification .notification-content { margin: 7px; }
      .notification .notification-content overlay { margin: 4px; }
      /* Restore swaync's built-in icon sizes — the leading `all: unset`
         wipes them and catppuccin's upstream _theme.scss doesn't reinstate
         them, so without these rules notification icons render tiny. */
      .notification .notification-content .image { -gtk-icon-size: 64px; }
      .notification .notification-content .app-icon { -gtk-icon-size: 24px; }
      .notification-group-icon { -gtk-icon-size: 32px; }
      .notification-content .summary { color: #cdd6f4; }
      .notification-content .time { color: #a6adc8; }
      .notification-content .body { color: #bac2de; }
      .notification > *:last-child > * { min-height: 3.4em; }
      .notification-background .close-button {
        margin: 7px; padding: 2px; border-radius: 6.3px;
        color: #1e1e2e; background-color: #f38ba8;
      }
      .notification-background .close-button:hover { background-color: #eba0ac; }
      .notification-background .close-button:active { background-color: #f5c2e7; }
      .notification .notification-action {
        border-radius: 7px; color: #cdd6f4;
        box-shadow: inset 0 0 0 1px #45475a;
        margin: 4px; padding: 8px;
        background-color: #313244;
      }
      .notification .notification-action:hover { background-color: #45475a; }
      .notification .notification-action:active { background-color: #585b70; }
      .notification.critical progress { background-color: #f38ba8; }
      .notification.low progress, .notification.normal progress { background-color: #89b4fa; }
      .notification progress, .notification trough, .notification progressbar {
        border-radius: 12.6px; padding: 3px 0;
      }

      .control-center {
        box-shadow: 0 0 8px 0 rgba(0,0,0,0.8), inset 0 0 0 1px #313244;
        border-radius: 12.6px;
        background-color: #1e1e2e;
        color: #cdd6f4;
        padding: 14px;
      }
      .control-center .notification-background {
        border-radius: 7px; box-shadow: inset 0 0 0 1px #45475a; margin: 4px 10px;
      }
      .control-center .notification-background .notification { border-radius: 7px; }
      .control-center .notification-background .notification.low { opacity: 0.8; }
      .control-center .widget-title > label { color: #cdd6f4; font-size: 1.3em; }
      .control-center .widget-title button {
        border-radius: 7px; color: #cdd6f4;
        background-color: #313244; box-shadow: inset 0 0 0 1px #45475a; padding: 8px;
      }
      .control-center .widget-title button:hover { background-color: #45475a; }
      .control-center .widget-title button:active { background-color: #585b70; }
      .control-center .notification-group { margin-top: 10px; }
      .control-center .notification-group:focus .notification-background { background-color: #313244; }
      scrollbar slider { margin: -3px; opacity: 0.8; }
      scrollbar trough { margin: 2px 0; }

      .widget-dnd { margin-top: 5px; border-radius: 8px; font-size: 1.1rem; }
      .widget-dnd > switch { font-size: initial; border-radius: 8px; background: #313244; box-shadow: none; }
      .widget-dnd > switch:checked { background: #89b4fa; }
      .widget-dnd > switch slider { background: #45475a; border-radius: 8px; }

      .widget-mpris-player { background: #313244; border-radius: 12.6px; color: #cdd6f4; }
      .mpris-overlay { background-color: #313244; opacity: 0.9; padding: 15px 10px; }
      .widget-mpris-album-art { -gtk-icon-size: 100px; border-radius: 12.6px; margin: 0 10px; }
      .widget-mpris-title { font-size: 1.2rem; color: #cdd6f4; }
      .widget-mpris-subtitle { font-size: 1rem; color: #bac2de; }
      .widget-mpris button { border-radius: 12.6px; color: #cdd6f4; margin: 0 5px; padding: 2px; }
      .widget-mpris button image { -gtk-icon-size: 1.8rem; }
      .widget-mpris button:hover { background-color: #313244; }
      .widget-mpris button:active { background-color: #45475a; }
      .widget-mpris button:disabled { opacity: 0.5; }
    '';
  };

  # hyprpolkitagent works out of the box (no config needed) — it just listens
  # on the polkit D-Bus and pops up a password prompt when an app asks for
  # elevated privileges (sudo GUI prompts, NetworkManager VPN auth, etc.).
  services.hyprpolkitagent.enable = true;

  # Deliberately no gnome-keyring user unit here: pam_gnome_keyring.so
  # (wired system-wide by services.gnome.gnome-keyring in
  # common/hyprland-wm.nix, on both the GDM and tty login PAM stacks)
  # starts the daemon at login and unlocks it with the login password — a
  # separate systemd unit would only duplicate the PAM-started daemon.
  # The SSH agent is likewise not gnome-keyring's job anymore:
  # gnome-keyring 48+ is built without it, and gcr-ssh-agent's socket
  # units cover it (see the SSH_AUTH_SOCK comment near the top).

  # Tray applets shown in Waybar's tray module. The home-manager service
  # modules pull in the right package and wire systemd user units bound to
  # the wayland session — cleaner than spawning them from exec-once.
  services.network-manager-applet.enable = true;
  services.blueman-applet.enable = true;

  # cliphist — clipboard history daemon. Module default is 500 entries;
  # capped lower here for shorter retention.
  services.cliphist = {
    enable = true;
    extraOptions = [
      "-max-dedupe-search"
      "10"
      "-max-items"
      "50"
    ];
  };
}

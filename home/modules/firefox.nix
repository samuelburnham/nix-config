# Largely inspired by https://github.com/Misterio77/nix-config/blob/36f76f9a4e6dd45c692755858a248c26883184f5/home/gabriel/features/desktop/common/firefox.nix
# TODO: Look into the new profile UI: https://support.mozilla.org/en-US/kb/profile-management
# Could be nice to separate work and personal accounts, bookmarks & history more cleanly than multi-account containers, or use both
{
  pkgs,
  lib,
  ...
}:
{
  programs.firefox = {
    enable = true;
    # 26.05 moved the default profile location to $XDG_CONFIG_HOME/mozilla/firefox.
    # Pin the pre-26.05 path so the existing ~/.mozilla/firefox profile keeps
    # working in place rather than being abandoned for a fresh XDG one.
    configPath = ".mozilla/firefox";
    policies = {
      DisplayBookmarksToolbar = "always";
      # Pre-answer Firefox's external-protocol confirmation dialog
      # ("Allow https://… to open the X link with Y?"). `ask = false`
      # skips the prompt; the scheme list comes from each app's
      # MimeType= entry in its .desktop file.
      Handlers.schemes = {
        tg = {
          action = "useHelperApp";
          ask = false;
          handlers = [
            {
              name = "Telegram";
              path = "${pkgs.telegram-desktop}/bin/telegram-desktop";
            }
          ];
        };
        tonsite = {
          action = "useHelperApp";
          ask = false;
          handlers = [
            {
              name = "Telegram";
              path = "${pkgs.telegram-desktop}/bin/telegram-desktop";
            }
          ];
        };
        slack = {
          action = "useHelperApp";
          ask = false;
          handlers = [
            {
              name = "Slack";
              path = "${pkgs.slack}/bin/slack";
            }
          ];
        };
      };
    };

    profiles.sam = {
      search = {
        force = true;
        default = "ddg";
        order = [
          "ddg"
          "google"
        ];
      };
      # about:config settings
      settings = {
        # Remember each site's zoom setting
        # On desktop ultrawide, text-heavy sites need at least 120% zoom
        # I don't know how to scale just the page to 120% by default,
        # but at least this way I only have to zoom in once per page and FF remembers it
        "browser.zoom.siteSpecific" = true;
        "browser.startup.homepage" = "about:home";

        # Disable irritating first-run stuff
        "browser.disableResetPrompt" = true;
        "browser.download.panel.shown" = true;
        "browser.feeds.showFirstRunUI" = false;
        "browser.messaging-system.whatsNewPanel.enabled" = false;
        "browser.rights.3.shown" = true;
        "browser.shell.checkDefaultBrowser" = false;
        "browser.shell.defaultBrowserCheckCount" = 1;
        "browser.startup.homepage_override.mstone" = "ignore";
        "browser.uitour.enabled" = false;
        "startup.homepage_override_url" = "";
        "trailhead.firstrun.didSeeAboutWelcome" = true;
        "browser.bookmarks.restore_default_bookmarks" = false;
        # TODO: Prevent the "Import bookmarks" button from showing up in the toolbar
        "browser.bookmarks.addedImportButton" = true;

        # Disable about:config warning
        "browser.aboutConfig.showWarning" = false;
        # Always open bookmarks in new tab
        "browser.tabs.loadBookmarksInTabs" = true;
        # Disable save passwords, autofill, and the breach-alert popup
        # that Firefox throws at form fields whenever it thinks one of the
        # site's fields matches a leaked-credential database.
        "signon.rememberSignons" = false;
        "signon.autofillForms" = false;
        "extensions.formautofill.addresses.enabled" = false;
        "extensions.formautofill.creditCards.enabled" = false;
        # Form history dropdown (the "annoying" autocomplete that surfaces
        # everything you've ever typed into a search/login field).
        "browser.formfill.enable" = false;

        # Don't ask for download dir
        "browser.download.useDownloadDir" = false; # Doesn't seem to stick after login

        # Disable crappy home activity stream page, including the
        # sponsored Pocket "stories" row and the sponsored top-site tiles.
        "browser.newtabpage.activity-stream.feeds.section.topstories" = false;
        "browser.newtabpage.activity-stream.feeds.topsites" = false;
        "browser.newtabpage.activity-stream.showSponsored" = false;
        "browser.newtabpage.activity-stream.showSponsoredTopSites" = false;
        "browser.newtabpage.activity-stream.section.highlights.includePocket" = false;
        "browser.newtabpage.activity-stream.improvesearch.topSiteSearchShortcuts" = false;
        # Pocket integration entirely — removes the save-to-Pocket button
        # and the sponsored-content sources Pocket feeds into the new tab.
        "extensions.pocket.enabled" = false;
        "browser.newtabpage.blocked" = lib.genAttrs [
          # Youtube
          "26UbzFJ7qT9/4DhodHKA1Q=="
          # Facebook
          "4gPpjkxgZzXPVtuEoAL9Ig=="
          # Wikipedia
          "eV8/WsSLxHadrTL1gAxhug=="
          # Reddit
          "gLv0ja2RYVgxKdp0I5qwvA=="
          # Amazon
          "K00ILysCaEq8+bEqV/3nuw=="
          # Twitter
          "T9nJot5PurhJSy8n038xGA=="
        ] (_: 1);

        # URL bar — kill Firefox Suggest entirely (sponsored + non-sponsored)
        # plus the side panels (trending, weather, addons, MDN, Pocket, Yelp)
        # that Mozilla keeps adding behind feature flags.
        "browser.urlbar.quicksuggest.enabled" = false;
        "browser.urlbar.quicksuggest.dataCollection.enabled" = false;
        "browser.urlbar.suggest.quicksuggest.sponsored" = false;
        "browser.urlbar.suggest.quicksuggest.nonsponsored" = false;
        "browser.urlbar.suggest.trending" = false;
        "browser.urlbar.suggest.weather" = false;
        "browser.urlbar.suggest.bestmatch" = false;
        "browser.urlbar.suggest.addons" = false;
        "browser.urlbar.suggest.mdn" = false;
        "browser.urlbar.suggest.pocket" = false;
        "browser.urlbar.suggest.yelp" = false;
        # Hide the "Firefox Suggest" / "Sponsored" group labels in the
        # dropdown so any stray result that slips through is unlabeled
        # rather than carrying ad-style chrome.
        "browser.urlbar.groupLabels.enabled" = false;

        # Harden
        # These don't seem to stick after login
        "privacy.trackingprotection.enabled" = true;
        "dom.security.https_only_mode" = true;

        # Vertical tabs and sidebar
        "sidebar.verticalTabs" = true;
        "sidebar.revamp" = true;
        "sidebar.main.tools" = "syncedtabs,history,bookmarks";

        # Always show downloads button in toolbar
        "browser.download.autohideButton" = false;
        # Toolbar layout
        "browser.uiCustomization.state" = builtins.toJSON {
          placements = {
            widget-overflow-fixed-list = [ ];
            # "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action" = Bitwarden
            nav-bar = [
              "sidebar-button"
              "back-button"
              "forward-button"
              "stop-reload-button"
              "vertical-spacer"
              "customizableui-special-spring1"
              "urlbar-container"
              "customizableui-special-spring2"
              "open-file-button"
              "downloads-button"
              "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
              "addon_darkreader_org-browser-action"
              "ublock0_raymondhill_net-browser-action"
              "unified-extensions-button"
              "reset-pbm-toolbar-button"
              "firefox-view-button"
              "alltabs-button"
            ];
            toolbar-menubar = [ "menubar-items" ];
            TabsToolbar = [ ];
            vertical-tabs = [ "tabbrowser-tabs" ];
            PersonalToolbar = [ "personal-bookmarks" ];
          };
          seen = [
            "save-to-pocket-button"
            "developer-button"
            "_446900e4-71c2-419f-a6a7-df9c091e268b_-browser-action"
            "addon_darkreader_org-browser-action"
            "ublock0_raymondhill_net-browser-action"
            "nordvpnproxy_nordvpn_com-browser-action"
            "screenshot-button"
          ];
          dirtyAreaCache = [
            "unified-extensions-area"
            "nav-bar"
            "PersonalToolbar"
            "toolbar-menubar"
            "TabsToolbar"
            "vertical-tabs"
          ];
          currentVersion = 23;
          newElementCount = 2;
        };
      };
    };
  };

  xdg.mimeApps.defaultApplications = {
    "text/html" = [ "firefox.desktop" ];
    "text/xml" = [ "firefox.desktop" ];
    "x-scheme-handler/http" = [ "firefox.desktop" ];
    "x-scheme-handler/https" = [ "firefox.desktop" ];
    "application/pdf" = [ "firefox.desktop" ];
  };
}

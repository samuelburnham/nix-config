# TODO:
# Make PgUp/Down map to C-u/C-d as the latter is a more useful scroll amount
# Set up projects for each Neovim instance like VSCode or tmux, where each neovim is its own project with saved state
# Test lean.nvim with goto-def, infoview, and hover, `,` local leader key maybe should be unified with `<leader>l`
# Test `blink-cmp`
# Add some functionality borrowed from tmux like session persistence, SSH, and running a Neovim systemd server on startup. See https://kraust.github.io/posts/neovim-is-a-multiplexer/
# Complete leader keybindings for common tasks
# Keep an eye on Ghostty integration with Neovim, such as https://github.com/neovim/neovim/issues/33155 which would fix multiline copy-paste from `:terminal`
# and probably other bugs like squashed text on window resize
# awesome-nvf configurations:
# https://github.com/jack-thesparrow/schrovimger
# https://github.com/e-v-o-l-v-e/nix-config/blob/main/home/nvf.nix
#
# Look into:
# folke/trouble.nvim
# nvim-lua/plenary.nvim
# https://github.com/smoka7/multicursors.nvim
# https://github.com/NeogitOrg/neogit
#
# Cheat sheet
# Terminal copy-paste uses system clipboard, `y`/`p` should work
# The latter works in insert mode as well in both regular and terminal buffer
#
# <C-Right>/<C-Left> to cycle open tabs, so that you don't open already closed buffers
# To reach several tabs away, do <leader>bc to pick tab by letter, or <leader>fb to open buffers list
#
# To go forward/backward in cursor history (where was I last), use <C-i>/<C-o>
# This will jump between buffers as well. It's nice for going back after go to def or jumping around a file
#
# Visual mode
# Follow which-key for key sequences, it's amazing. But increase menu popup time so it only shows after a second or two
# gU/gu to uppercase or lowercase selection, g~ to toggle case
# gc to toggle comment, gcc for the current line
# gv to select last visual selection
# Core Neovim configuration that can be used both standalone and with home-manager
{
  pkgs,
  pkgs-unstable,
  lib,
  inputs,
  flakeInputs,
  ...
}:
let
  markdownMappings = ''
    function(bufnr)
      local function in_vault()
        return vim.b[bufnr].obsidian_buffer == true
          and require("obsidian.api").find_workspace(vim.api.nvim_buf_get_name(bufnr)) ~= nil
      end

      -- Return commands so edits run after expression evaluation releases textlock.
      vim.keymap.set("n", "<CR>", function()
        local utils = require("mkdnflow.utils")
        local row = vim.api.nvim_win_get_cursor(0)[1]
        if utils.cursorInCodeBlock(row) then return "<CR>" end

        local vault = in_vault()
        if vault then
          if require("obsidian.api").cursor_link() then
            return "<Cmd>Obsidian follow_link<CR>"
          end
          if require("obsidian.api").cursor_tag() then return "<Cmd>Obsidian tags<CR>" end
        elseif require("mkdnflow.links").getLinkUnderCursor() then
          return "<Cmd>MkdnFollowLink<CR>"
        end

        local list_type = require("mkdnflow.lists").hasListType()
        if list_type == "ultd" or list_type == "oltd" then
          return "<Cmd>MkdnToggleToDo<CR>"
        end
        if vim.fn.foldclosed(row) ~= -1 or utils.getHeadingLevel(vim.api.nvim_get_current_line()) < 99 then
          return "<Cmd>MkdnEnter<CR>"
        end
        if vault then return "<CR>" end
        return "<Cmd>MkdnEnter<CR>"
      end, { buffer = bufnr, expr = true, desc = "Follow link, toggle task, or fold heading" })

      vim.keymap.set("x", "<CR>", function()
        return in_vault() and ":Obsidian link<CR>" or ":MkdnEnter<CR>"
      end, { buffer = bufnr, expr = true, desc = "Create link from selection" })

      vim.keymap.set("n", "<F2>", function()
        return in_vault() and "<Cmd>Obsidian rename<CR>" or "<Cmd>MkdnMoveSource<CR>"
      end, { buffer = bufnr, expr = true, desc = "Rename note or link target" })

      return in_vault
    end
  '';
in
{
  vim = {
    options.guicursor = "n-v-c-sm:block,i-ci-ve:ver25,r-cr-o:hor20,t:ver25-blinkon500-blinkoff500-TermCursor";
    vimAlias = true;

    # Catppuccin theme, follows OS light/dark preference via auto-dark-mode.nvim
    theme = {
      enable = true;
      name = "catppuccin";
      style = "mocha";
    };
    # Modeline
    statusline.lualine = {
      enable = true;
      # catppuccin.nvim registers the theme as catppuccin-nvim, not catppuccin;
      # use setupOpts to bypass nvf's enum (which only lists "catppuccin").
      setupOpts.options.theme = "catppuccin-nvim";
    };
    visuals.rainbow-delimiters.enable = true;
    # TODO: Test this out e.g. with gitsigns and consider nvim-hlslens for search
    visuals.nvim-scrollbar.enable = true;

    utility.diffview-nvim = {
      enable = true;
      # Asymmetric red/green per side (matches the README preview): DiffAdd
      # on the old buffer is win-remapped to a copy of DiffDelete.
      setupOpts.enhanced_diff_hl = true;
    };

    # Passive visualization only — hunk staging, reset, and diffs go
    # through Neogit/diffview. Flattened into the <leader>g namespace
    # alongside the Neogit popups (gs/gw/gc/gl/gp).
    git.gitsigns = {
      enable = true;
      mappings = {
        stageHunk = null;
        undoStageHunk = null;
        resetHunk = null;
        stageBuffer = null;
        resetBuffer = null;
        diffThis = null;
        diffProject = null;
        toggleDeleted = null;

        # ]c/[c defaults retained — they fall through to vim's native
        # next-change inside diff mode, and jump gitsigns hunks elsewhere.
        previewHunk = "<leader>gh";
        blameLine = "<leader>gb";
        toggleBlame = "<leader>gB";
      };
    };

    # TODO: Image renders but overlaps with text
    # See https://github.com/3rd/image.nvim/issues/287, likely fixed upstream
    # Or switch to https://github.com/folke/snacks.nvim/blob/main/docs/image.md
    #utility.images.image-nvim = {
    #  enable = true;
    #  setupOpts.backend = "kitty";
    #};

    utility.snacks-nvim = {
      enable = true;
      setupOpts = {
        dashboard = {
          enabled = true;
          #{ section = "projects", gap = 1, padding = 1 },
          #{ section = "recent_files", gap = 1, padding = 1 },
          sections = lib.generators.mkLuaInline ''
            {
              { section = "header" },
              { section = "keys", gap = 1, padding = 1 },
              { icon = " ", title = "Projects", section = "projects", indent = 2, padding = 1 },
              { title = "Sessions", section = "session", indent = 2, padding = 1 },
            }
          '';
        };
        picker.enabled = true;
        bigfile.enabled = true;
        quickfile.enabled = true;
        indent.enabled = true;
        words.enabled = true;
        # keys = [
        #   {
        #     key = "<leader><space>";
        #     mode = ["n"];
        #     lua = true;
        #     action = ''
        #       function() Snacks.picker.smart() end
        #     '';
        #     desc = "Smart Find Files";
        #   }
        # ];
      };
    };

    extraPackages = with pkgs; [
      ripgrep
      kitty
      tex-fmt
      pkgs-unstable.obsidian-headless
    ];

    # TODO: Unify cmdline and file-based keybindings
    autocomplete.blink-cmp = {
      enable = true;
      mappings.confirm = "<C-CR>";
      setupOpts = {
        signature.enabled = true;
        cmdline.enabled = true;
        completion.list.selection.auto_insert = false;

        # Completion trigger on Alt-Space; Ctrl-Space is reserved for tmux prefix
        keymap = {
          preset = "default";
          "<CR>" = [ "fallback" ];
          # Tables and lists claim Tab; other text keeps completion bindings.
          "<Tab>" = lib.mkBefore [
            (lib.generators.mkLuaInline ''
              function(cmp)
                if vim.api.nvim_get_mode().mode == "i"
                  and (vim.bo.filetype == "markdown" or vim.bo.filetype == "rmd")
                then
                  if require("mkdnflow.tables").MarkdownTable:read().valid then
                    cmp.hide()
                    return vim.keycode("<Cmd>MkdnTableNextCell<CR>")
                  elseif require("mkdnflow.lists").hasListType()
                    and not require("mkdnflow.utils").cursorInCodeBlock(vim.api.nvim_win_get_cursor(0)[1])
                  then
                    cmp.hide()
                    return vim.keycode("<Cmd>MkdnIndentListItem<CR>")
                  end
                end
              end
            '')
          ];
          "<S-Tab>" = lib.mkBefore [
            (lib.generators.mkLuaInline ''
              function(cmp)
                if vim.api.nvim_get_mode().mode == "i"
                  and (vim.bo.filetype == "markdown" or vim.bo.filetype == "rmd")
                then
                  if require("mkdnflow.tables").MarkdownTable:read().valid then
                    cmp.hide()
                    return vim.keycode("<Cmd>MkdnTablePrevCell<CR>")
                  elseif require("mkdnflow.lists").hasListType()
                    and not require("mkdnflow.utils").cursorInCodeBlock(vim.api.nvim_win_get_cursor(0)[1])
                  then
                    cmp.hide()
                    return vim.keycode("<Cmd>MkdnDedentListItem<CR>")
                  end
                end
              end
            '')
          ];
          "<C-space>" = [ "fallback" ];
          "<M-space>" = [
            "show"
            "show_documentation"
            "hide_documentation"
          ];
        };

        # Select and accept with `<M-space>`, close with `<C-e>`
        cmdline.keymap = {
          preset = "default";
          # TODO: Tab select_and_accept doesn't work, not sure why
          "<Tab>" = [
            "show"
            "accept"
          ];
          "<M-space>" = [
            "select_and_accept"
            "fallback"
          ];
        };
        cmdline.completion.list.selection.auto_insert = false;
        cmdline.completion.list.selection.preselect = true;
        # If `menu.auto_show` is annoying, can set to false and set Tab to show menu and also accept
        # `"<Tab>" = ["show_and_insert_or_accept_single" "select_and_accept"];`
        # But have to wait for blink 1.7, above doesn't work atm
        cmdline.completion.menu.auto_show = lib.generators.mkLuaInline ''
          function(ctx)
            return vim.fn.getcmdtype() == ':'
          end
        '';
      };
    };

    # TODO: Add https://github.com/nvim-telescope/telescope-fzf-native.nvim if better perf needed
    # https://github.com/NotAShelf/nvf/blob/9df9d51fd9fc8f9a8fc377f984ea3b7ae796172d/modules/plugins/utility/telescope/telescope.nix#L232-L243
    telescope = {
      enable = true;
      setupOpts = {
        pickers = {
          buffers = {
            sort_mru = true;
            sort_lastused = true;
          };
        };
      };
      # nvf calls `telescope.load_extension('<name>')` in telescope's own
      # after-hook, so no VimEnter autocmd needed. `packages` is empty because
      # persisted-nvim is already in runtimepath via extraPlugins.
      extensions = [
        {
          name = "persisted";
        }
      ];
    };
    # TODO:
    # Fix auto-refresh after running git commands from `:terminal`
    # Improve icons for git, yellow circle and square is weird
    filetree.neo-tree = {
      enable = true;
      setupOpts = {
        # `traditional` makes Git walk ignored build trees on every refresh.
        # Repositories are mounted over virtiofs in the dev VM, where those
        # metadata-heavy walks are expensive. `matching` still identifies
        # paths explicitly covered by ignore patterns so hide_gitignored keeps
        # working, without traversing their contents.
        event_handlers = [
          {
            event = "before_git_status";
            handler = lib.generators.mkLuaInline ''
              function(args)
                for i, value in ipairs(args.status_args) do
                  if value == "--ignored=traditional" then
                    args.status_args[i] = "--ignored=matching"
                  end
                end
              end
            '';
          }
        ];
        # Ignored nodes remain hidden by default and have no Git decoration
        # when filtered items are revealed.
        default_component_configs.git_status.symbols.ignored = "";
        window = {
          mappings = {
            "<space>" = "none";
            "q" = "close_window";
          };
        };
      };
    };
    ui.noice = {
      enable = true;
      setupOpts = {
        presets = {
          command_palette = false;
        };
        # Workaround enabling `:!` shell command output: https://github.com/folke/noice.nvim/issues/1097
        routes = [
          {
            filter = {
              event = "msg_show";
              kind = [
                "shell_out"
                "shell_err"
                "shell_ret"
              ];
            };
            view = "popup";
            opts = {
              level = "info";
              skip = false;
              replace = false;
            };
          }
        ];
      };
    };

    notify.nvim-notify = {
      enable = true;
    };

    # Use `direnv.nvim` instead for now to fix loading files from other directorie
    utility.direnv.enable = false;

    # TODO: Contribute manually build Vim plugins to nixpkgs for auto-updates
    extraPlugins = {
      # Preserve proportional window sizes when the outer terminal (Ghostty)
      # resizes, so :terminal splits don't get squashed while regular buffers
      # take up all the reclaimed space.
      # Default register triggers (WinEnter/BufWinEnter). Avoid WinResized —
      # it also fires during the outer Ghostty resize, so bufresize ends up
      # registering the transient squashed layout and pins terminals at
      # whatever width the mid-tile redistribution produced.
      bufresize = {
        package = pkgs.vimPlugins.bufresize-nvim;
        setup = ''
          require('bufresize').setup()
        '';
      };

      auto-dark-mode = {
        package = pkgs.vimUtils.buildVimPlugin {
          pname = "auto-dark-mode.nvim";
          version = flakeInputs.auto-dark-mode.shortRev;
          src = flakeInputs.auto-dark-mode;
        };
        setup = ''
          local function apply(flavour)
            require('catppuccin').setup({ flavour = flavour })
            vim.cmd.colorscheme('catppuccin')
          end
          require('auto-dark-mode').setup({
            set_dark_mode  = function() apply('mocha') end,
            set_light_mode = function() apply('latte') end,
          })
          -- User commands let darkman's mode scripts trigger an instant switch
          -- via `nvim --server <sock> --remote-send '<Cmd>DarkMode<CR>'`
          -- without waiting for auto-dark-mode's 3-second poll interval.
          vim.api.nvim_create_user_command('DarkMode',  function() apply('mocha') end, {})
          vim.api.nvim_create_user_command('LightMode', function() apply('latte') end, {})
          -- A headless VM has no desktop portal for auto-dark-mode's D-Bus
          -- probe, so inside tmux seed the initial flavour from tmux's
          -- #{client_theme}, which tmux derives from the terminal's OSC 2031
          -- light/dark reports (Ghostty emits them; they survive the ssh hop).
          -- Live changes arrive via the client-{dark,light}-theme tmux hooks
          -- (dev-vm.nix) driving the DarkMode/LightMode commands above.
          vim.api.nvim_create_autocmd('VimEnter', {
            once = true,
            callback = function()
              if not vim.env.TMUX then return end
              local t = vim.trim(vim.fn.system({ 'tmux', 'display-message', '-p', '#{client_theme}' }))
              if t == 'light' then apply('latte') elseif t == 'dark' then apply('mocha') end
            end,
          })
        '';
      };
      # Enables loading rust-analyzer after direnv completes for Rust files in another directory
      # Otherwise rust-analyzer can't find the binary because direnv hasn't yet loaded it from the Nix flake
      # Lean doesn't have this issue, likely due to starting via autocmd rather than `vim.lsp.enable()`
      direnv = {
        package = pkgs.vimUtils.buildVimPlugin {
          pname = "direnv.nvim";
          version = flakeInputs.direnv-nvim.shortRev;
          src = flakeInputs.direnv-nvim;
        };
        setup = ''
          -- direnv.nvim shells out to the `direnv` binary on BufEnter, so only
          -- set it up where direnv is installed: the dev VM auto-loads the
          -- devshell, while the workstations (direnv intentionally absent) skip
          -- it instead of throwing ENOENT on every buffer.
          if vim.fn.executable('direnv') == 1 then
            require('direnv-nvim').setup({
              async = true,
              on_direnv_finished = function ()
                bufnr = vim.api.nvim_get_current_buf()
                if vim.bo[bufnr].filetype == "rust" then
                  vim.lsp.start({
                    name = 'rust-analyzer',
                    cmd = {'rust-analyzer'},
                    root_dir = vim.fs.root(0, {'Cargo.toml'}),
                  })
                end
              end
            })
          end
        '';
      };
      # Could use smooth scroll with mouse wheel, see https://github.com/karb94/neoscroll.nvim/issues/50#issuecomment-1160094214
      neoscroll = {
        package = pkgs.vimPlugins.neoscroll-nvim;
        setup = ''
          neoscroll = require('neoscroll')
          neoscroll.setup({
            stop_eof = true,
            cursor_scrolls_alone = false,
          })
          local keymap = {
            ["<C-S-Up>"] = function() neoscroll.ctrl_u({ duration = 250 }) end;
            ["<C-S-Down>"] = function() neoscroll.ctrl_d({ duration = 250 }) end;
            ["<PageUp>"] = function() neoscroll.ctrl_b({ duration = 450 }) end;
            ["<PageDown>"] = function() neoscroll.ctrl_f({ duration = 450 }) end;
            ["<C-Up>"] = function() neoscroll.scroll(-0.1, { move_cursor=false; duration = 100 }) end;
            ["<C-Down>"] = function() neoscroll.scroll(0.1, { move_cursor=false; duration = 100 }) end;
          }
          local modes = { 'n', 'v', 'x' }
          for key, func in pairs(keymap) do
            vim.keymap.set(modes, key, func)
          end
        '';
      };
      # Persistent sessions per cwd, auto-restored on nvim startup
      # Pairs with tmux-resurrect: resurrect preserves the pane's cwd,
      # nvim relaunches there, persisted autoloads the matching session
      persisted-nvim = {
        package = pkgs-unstable.vimPlugins.persisted-nvim;
        setup = ''
          require("persisted").setup({
            save_dir = vim.fn.stdpath("data") .. "/sessions/",
            autoload = true,
            autostart = true,
            use_git_branch = false,
          })
        '';
      };
      # Vim launched from `:terminal` opens a buffer instead of vimception
      flatten = {
        package = pkgs-unstable.vimPlugins.flatten-nvim;
        setup = ''
          require('flatten').setup({
            window = {
              open = "current",
              focus = "last",
            },
          })
        '';
      };
      # lean.nvim dep, enables line comments with `gc`
      tcomment = {
        package = pkgs.vimPlugins.tcomment_vim;
      };
      # lean.nvim dep, enables enhanced `%` motion
      matchup = {
        package = pkgs.vimPlugins.vim-matchup;
      };
      # lean.nvim dep, enables switching text variants with `gs`
      switch = {
        package = pkgs.vimPlugins.switch-vim;
      };
      # Start continuous compilation with ,ll; saves rebuild the PDF and
      # Zathura refreshes it. ,lv jumps from the source to the PDF. The plain
      # `zathura` method focuses windows with xdotool, which is X11-only;
      # `zathura_simple` keeps SyncTeX forward and inverse search on Wayland.
      vimtex = {
        package = pkgs.vimPlugins.vimtex;
        setup = ''
          vim.g.vimtex_compiler_method = "latexmk"
          vim.g.vimtex_compiler_latexmk = { continuous = 1 }
          vim.g.vimtex_view_method = "zathura_simple"
          vim.g.vimtex_view_automatic = 1
        '';
      };
    };
    # TODO: Look into optional lean.nvim enhancements
    # https://github.com/lewis6991/satellite.nvim
    # https://github.com/kosayoda/nvim-lightbulb
    # https://github.com/rmagatti/goto-preview
    # Bug: When adding a dependency and running `lake update`, if I do `import <dep>` in a Lean file then Lean.nvim runs `lake setup-file` which will clone and attempt to build the dependency. However, this fails with:
    # ```
    # info: stderr:
    # /nix/store/qla374n3avx7nzaw2kvq6wj9y4agiw1l-clang-19.1.7/bin/clang: symbol lookup error: /nix/store/qla374n3avx7nzaw2kvq6wj9y4agiw1l-clang-19.1.7/bin/clang: undefined symbol: _ZNK4llvm3opt3Arg11getAsStringB5cxx11ERKNS0_7ArgListE, version LLVM_19.1
    # ```
    # which means Lean.nvim is using the wrong clang or doesn't have the right libraries loaded from `/nix/store/<hash>-lean/bin/clang`. Furthermore after this error the whole Neovim UI is unresponsive half the time and the terminal buffer stops working. Idk the fix but a workaround is to close the infoview window (`,i` to toggle) so Neovim works again, then run `lake build` which will succeed, then reopen the infoview and restart the Lean server for that file.
    lazy.plugins = {
      # TODO: Support promoting/demoting entire Markdown subtrees while preserving relative heading levels.
      "mkdnflow.nvim" = {
        # mkdnflow 2.22.3 passes clipboard newlines to nvim_buf_set_text.
        package = pkgs-unstable.vimPlugins.mkdnflow-nvim.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (pkgs.writeText "mkdnflow-clipboard.patch" ''
              --- a/lua/mkdnflow/links/init.lua
              +++ b/lua/mkdnflow/links/init.lua
              @@ -671,6 +671,17 @@
                   local range = args.range or false
                   local style = args.style or links.style
                   local transform_scope = args.transform_scope or links.transform_scope
              +    local clipboard_source
              +    if from_clipboard then
              +        clipboard_source = vim.trim(vim.fn.getreg('+'))
              +        if #clipboard_source == 0 or clipboard_source:find('[\r\n]') then
              +            vim.notify(
              +                'Clipboard must contain a single non-empty link destination',
              +                vim.log.levels.WARN
              +            )
              +            return
              +        end
              +    end
                   -- Get mode from vim
                   local mode = vim.api.nvim_get_mode()['mode']
                   -- Get the cursor position
              @@ -713,8 +724,7 @@
                           -- Make a markdown link out of the date and cursor
                           local replacement
                           if from_clipboard then
              -                replacement =
              -                    M.formatLink(cursor_word, vim.fn.getreg('+'), nil, style, transform_scope)
              +                replacement = M.formatLink(cursor_word, clipboard_source, nil, style, transform_scope)
                           else
                               replacement = M.formatLink(cursor_word, nil, nil, style, transform_scope)
                           end
              @@ -820,7 +830,7 @@
                               replacement = M.formatLink(text, cite_path, nil, style, transform_scope)
                           else
                               replacement = from_clipboard
              -                        and M.formatLink(text, vim.fn.getreg('+'), nil, style, transform_scope)
              +                        and M.formatLink(text, clipboard_source, nil, style, transform_scope)
                                   or M.formatLink(text, nil, nil, style, transform_scope)
                           end
                           -- If no replacement, end here
            '')
            # Unchanged table writes move render-markdown's extmarks on every cell jump.
            (pkgs.writeText "mkdnflow-table-format-noop.patch" ''
              --- a/lua/mkdnflow/tables/core.lua
              +++ b/lua/mkdnflow/tables/core.lua
              @@ -734,3 +734,10 @@
              +    local current_lines = vim.api.nvim_buf_get_lines(
              +        0, self.line_range.start - 1, self.line_range.finish, true
              +    )
              +    if vim.deep_equal(current_lines, formatted_lines) then
              +        return
              +    end
              +
                   -- Write back to buffer
                   vim.api.nvim_buf_set_lines(
                       0,
            '')
          ];
        });
        setupModule = "mkdnflow";
        ft = [
          "markdown"
          "rmd"
        ];
        setupOpts = {
          modules.backlinks = false;
          on_attach = lib.generators.mkLuaInline ''
            function(bufnr)
              local in_vault = (${markdownMappings})(bufnr)
              local numbering_tick = vim.api.nvim_buf_get_changedtick(bufnr)
              local numbering_seq = vim.fn.undotree().seq_last
              local list_query = vim.treesitter.query.parse("markdown", "(list) @list")
              vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave", "BufWritePre" }, {
                group = vim.api.nvim_create_augroup("MarkdownNumbering" .. bufnr, { clear = true }),
                buffer = bufnr,
                desc = "Keep ordered Markdown lists numbered sequentially",
                callback = function(event)
                  if not vim.bo[bufnr].modifiable
                    or (vim.bo[bufnr].filetype ~= "markdown" and vim.bo[bufnr].filetype ~= "rmd")
                  then
                    return
                  end
                  vim.api.nvim_buf_call(bufnr, function()
                    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
                    if tick == numbering_tick and event.event ~= "BufWritePre" then return end
                    numbering_tick = tick
                    local seq = vim.fn.undotree().seq_last
                    local new_edit = seq > numbering_seq
                    numbering_seq = seq
                    -- Undo and redo must restore their saved text without another edit.
                    if not new_edit and event.event ~= "BufWritePre" then return end

                    local tree = vim.treesitter.get_parser(bufnr, "markdown"):parse()[1]
                    local edits = {}
                    for _, list in list_query:iter_captures(tree:root(), bufnr) do
                      local number = 0
                      for item in list:iter_children() do
                        local marker = item:type() == "list_item" and item:named_child(0)
                        if marker and (marker:type() == "list_marker_dot" or marker:type() == "list_marker_parenthesis") then
                          number = number + 1
                          local digits = vim.treesitter.get_node_text(marker, bufnr):match("^%d+")
                          if digits and digits ~= tostring(number) then
                            local row, col = marker:start()
                            edits[#edits + 1] = { row = row, col = col, length = #digits, text = tostring(number) }
                            local width_change = #tostring(number) - #digits
                            if width_change ~= 0 then
                              local _, content_col = marker:end_()
                              local last_row, last_col = item:end_()
                              -- Continuation indentation is relative to the marker's width.
                              for next_row = row + 1, last_row do
                                if next_row < last_row or last_col > content_col then
                                  local line = vim.api.nvim_buf_get_lines(bufnr, next_row, next_row + 1, false)[1]
                                  if line and line:sub(col + 1, content_col):match("^ +$") and #line > content_col then
                                    edits[#edits + 1] = {
                                      row = next_row,
                                      col = col,
                                      length = math.max(0, -width_change),
                                      text = string.rep(" ", math.max(0, width_change)),
                                    }
                                  end
                                end
                              end
                            end
                          end
                        end
                      end
                    end
                    -- Apply later markers first so their byte offsets stay valid.
                    table.sort(edits, function(a, b)
                      if a.row == b.row then return a.col > b.col end
                      return a.row > b.row
                    end)
                    for _, edit in ipairs(edits) do
                      if new_edit then vim.cmd.undojoin() end
                      vim.api.nvim_buf_set_text(bufnr, edit.row, edit.col, edit.row, edit.col + edit.length, { edit.text })
                      new_edit = true
                    end
                    numbering_tick = vim.api.nvim_buf_get_changedtick(bufnr)
                    numbering_seq = vim.fn.undotree().seq_last
                  end)
                end,
              })

              local table_tick = vim.api.nvim_buf_get_changedtick(bufnr)
              local table_seq = vim.fn.undotree().seq_last
              vim.api.nvim_create_autocmd("InsertLeave", {
                group = vim.api.nvim_create_augroup("MarkdownTableFormat" .. bufnr, { clear = true }),
                buffer = bufnr,
                desc = "Format Markdown tables after insert-mode edits",
                callback = function()
                  if not vim.bo[bufnr].modifiable
                    or (vim.bo[bufnr].filetype ~= "markdown" and vim.bo[bufnr].filetype ~= "rmd")
                  then
                    return
                  end
                  vim.api.nvim_buf_call(bufnr, function()
                    local tick = vim.api.nvim_buf_get_changedtick(bufnr)
                    local seq = vim.fn.undotree().seq_last
                    local new_edit = tick ~= table_tick and seq > table_seq
                    table_tick, table_seq = tick, seq
                    -- Undo and redo must retain their saved formatting.
                    if not new_edit then return end
                    local cursor = vim.api.nvim_win_get_cursor(0)
                    local tree = vim.treesitter.get_parser(bufnr, "markdown"):parse()[1]
                    local node = tree:root():named_descendant_for_range(cursor[1] - 1, cursor[2], cursor[1] - 1, cursor[2])
                    while node and node:type() ~= "pipe_table" do node = node:parent() end
                    if not node then return end
                    local tables = require("mkdnflow.tables")
                    local tbl = tables.MarkdownTable:read()
                    if not tbl.valid then return end
                    local view = vim.fn.winsaveview()
                    local row = tbl:get_row(view.lnum)
                    local cell = row and row:which_cell(view.col)
                    local offset = cell and view.col - row:locate_cell(cell) + 1
                    -- Automatic alignment belongs to the edit's undo step.
                    pcall(vim.cmd.undojoin)
                    tbl:format()
                    if cell then
                      local line = vim.api.nvim_buf_get_lines(bufnr, view.lnum - 1, view.lnum, false)[1]
                      local formatted = tables.TableRow:from_string(line, view.lnum)
                      local first, last = formatted:locate_cell(cell)
                      view.col = math.max(first - 1, math.min(first - 1 + offset, last - 1))
                    end
                    vim.fn.winrestview(view)
                    table_tick = vim.api.nvim_buf_get_changedtick(bufnr)
                    table_seq = vim.fn.undotree().seq_last
                  end)
                end,
              })

              local function move_cell_or_link(direction)
                local tables = require("mkdnflow.tables")
                if tables.MarkdownTable:read().valid then
                  tables.moveToCell(0, direction)
                elseif in_vault() then
                  require("obsidian.api").nav_link(direction > 0 and "next" or "prev")
                else
                  vim.cmd(direction > 0 and "MkdnNextLink" or "MkdnPrevLink")
                end
              end

              vim.keymap.set("n", "<Tab>", function() move_cell_or_link(1) end, {
                buffer = bufnr,
                desc = "Next table cell or link",
              })
              vim.keymap.set("n", "<S-Tab>", function() move_cell_or_link(-1) end, {
                buffer = bufnr,
                desc = "Previous table cell or link",
              })

              local function open_line(above)
                local tables = require("mkdnflow.tables")
                local tbl = tables.MarkdownTable:read()
                if not tbl.valid then
                  vim.cmd(above and "MkdnNewListItemAboveInsert" or "MkdnNewListItemBelowInsert")
                  return
                end

                local cursor = vim.api.nvim_win_get_cursor(0)
                if tbl.table_type == "pipe" and cursor[1] <= tbl.metadata.separator_row_idx then
                  -- Keep the table header and separator adjacent.
                  local cell = tbl:get_row(cursor[1]):which_cell(cursor[2])
                  local separator = tbl:get_row(tbl.metadata.separator_row_idx)
                  local col = separator:locate_cell(cell)
                  vim.api.nvim_win_set_cursor(0, { separator.line_nr, col - 1 })
                  above = false
                end
                tbl:add_row(above and -1 or 0)
                tables.moveToCell(above and -1 or 1, 0)
                vim.cmd.startinsert()
              end

              vim.keymap.set("n", "o", function() open_line(false) end, {
                buffer = bufnr,
                desc = "Open table row or list item below",
              })
              vim.keymap.set("n", "O", function() open_line(true) end, {
                buffer = bufnr,
                desc = "Open table row or list item above",
              })

              local function move_block(direction)
                if not vim.bo[bufnr].modifiable then return end
                local cursor = vim.api.nvim_win_get_cursor(0)
                local line = vim.api.nvim_buf_get_lines(bufnr, cursor[1] - 1, cursor[1], false)[1]
                local first_content = line:find("[^%s>]")
                if not first_content then return end
                -- Leading indentation and quote prefixes can belong to the preceding node.
                local col = math.min(math.max(cursor[2], first_content - 1), #line - 1)
                local tree = vim.treesitter.get_parser(bufnr, "markdown"):parse()[1]
                local node = tree:root():named_descendant_for_range(cursor[1] - 1, col, cursor[1] - 1, col)
                while node and node:type() ~= "list_item" and node:type() ~= "pipe_table_row" do
                  -- A table header inside a list must not move the containing item.
                  if node:type() == "pipe_table" then return end
                  if node:type() == "section" then
                    local heading = node:named_child(0)
                    if not heading or heading:type() ~= "atx_heading" or heading:start() ~= cursor[1] - 1 then
                      return
                    end
                    break
                  end
                  node = node:parent()
                end
                if not node then return end

                local neighbor
                if direction < 0 then
                  neighbor = node:prev_named_sibling()
                else
                  neighbor = node:next_named_sibling()
                end
                if not neighbor or neighbor:type() ~= node:type() then return end
                if node:type() == "section" then
                  local heading = neighbor:named_child(0)
                  if not heading or heading:type() ~= "atx_heading"
                    or heading:named_child(0):type() ~= node:named_child(0):named_child(0):type()
                  then
                    return
                  end
                end

                local function bounds(item)
                  local first, _, last, last_col = item:range()
                  if last_col > 0 then last = last + 1 end
                  -- A block can include the following block's indentation or quote prefix.
                  local boundary = item
                  while boundary and not boundary:next_named_sibling() do
                    boundary = boundary:parent()
                  end
                  if boundary then
                    local next_start = boundary:next_named_sibling():start()
                    last = math.min(last, next_start)
                  end
                  -- Block nodes include following blank lines; keep separators in place.
                  while last > first + 1 do
                    local tail = vim.api.nvim_buf_get_lines(bufnr, last - 1, last, false)[1]
                    if not tail:match("^%s*$") then break end
                    last = last - 1
                  end
                  return first, last
                end

                local first, last = bounds(node)
                local offset = math.min(cursor[1] - 1 - first, last - first - 1)
                local upper_start, upper_end, lower_start, lower_end = first, last, bounds(neighbor)
                if direction < 0 then
                  upper_start, upper_end, lower_start, lower_end = lower_start, lower_end, first, last
                end
                if upper_start >= upper_end or upper_end > lower_start or lower_start >= lower_end then return end
                local replacement = vim.api.nvim_buf_get_lines(bufnr, lower_start, lower_end, false)
                vim.list_extend(replacement, vim.api.nvim_buf_get_lines(bufnr, upper_end, lower_start, false))
                vim.list_extend(replacement, vim.api.nvim_buf_get_lines(bufnr, upper_start, upper_end, false))
                vim.api.nvim_buf_set_lines(bufnr, upper_start, lower_end, true, replacement)
                local moved_start = direction > 0 and upper_start + lower_end - upper_end or upper_start
                vim.api.nvim_win_set_cursor(0, { moved_start + offset + 1, cursor[2] })
              end

              vim.keymap.set({ "n", "i" }, "<M-J>", function() move_block(1) end, {
                buffer = bufnr,
                desc = "Move Markdown row, item, or section down",
              })
              vim.keymap.set({ "n", "i" }, "<M-K>", function() move_block(-1) end, {
                buffer = bufnr,
                desc = "Move Markdown row, item, or section up",
              })
              require("which-key").add({
                { "<localleader>i", group = "Insert", buffer = bufnr },
                { "<localleader>d", group = "Delete", buffer = bufnr },
                { "<localleader>a", group = "Align", buffer = bufnr },
                { "<localleader>t", group = "Tables", buffer = bufnr },
              })
            end
          '';
          mappings = {
            MkdnEnter = false;
            MkdnMoveSource = false;
            MkdnToggleToDo = [
              [
                "n"
                "v"
              ]
              "<localleader>c"
            ];
            MkdnNextLink = false;
            MkdnPrevLink = false;
            MkdnNewListItemBelowInsert = false;
            MkdnNewListItemAboveInsert = false;
            MkdnUpdateNumbering = [
              "n"
              "<localleader>nn"
            ];
            MkdnTableNewRowBelow = [
              "n"
              "<localleader>ir"
            ];
            MkdnTableNewRowAbove = [
              "n"
              "<localleader>iR"
            ];
            MkdnTableNewColAfter = [
              "n"
              "<localleader>ic"
            ];
            MkdnTableNewColBefore = [
              "n"
              "<localleader>iC"
            ];
            MkdnTableDeleteRow = [
              "n"
              "<localleader>dr"
            ];
            MkdnTableDeleteCol = [
              "n"
              "<localleader>dc"
            ];
            MkdnTableFormat = [
              "n"
              "<localleader>tr"
            ];
            MkdnTableAlignLeft = [
              "n"
              "<localleader>al"
            ];
            MkdnTableAlignRight = [
              "n"
              "<localleader>ar"
            ];
            MkdnTableAlignCenter = [
              "n"
              "<localleader>ac"
            ];
            MkdnTableAlignDefault = [
              "n"
              "<localleader>ax"
            ];
            MkdnFoldSection = [
              "n"
              "<localleader>f"
            ];
            MkdnUnfoldSection = [
              "n"
              "<localleader>F"
            ];
            MkdnCreateLinkFromClipboard = [
              [
                "n"
                "v"
              ]
              "<localleader>p"
            ];
          };
        };
        keys = [
          {
            key = "<localleader>tn";
            mode = "n";
            ft = [
              "markdown"
              "rmd"
            ];
            action = "<cmd>MkdnTable 2 1<CR>";
            desc = "New two-column table";
          }
        ];
      };
      "lean.nvim" = {
        package = pkgs-unstable.vimPlugins.lean-nvim;
        setupModule = "lean";
        setupOpts = {
          mappings = true;
          # Narrower than upstream's 1/3 default — still comfortable for
          # goal state / hypotheses while leaving more room for code.
          # Pairs with the `leaninfo` FileType autocmd below, which calls
          # bufresize.resize_open() so the remaining width is redistributed
          # proportionally across existing splits instead of smushing the
          # rightmost one.
          infoview.width = 0.25;
          # Don't auto-open: lean.nvim is lazy-loaded by BufReadPre *.lean,
          # so on session restore the infoview opens mid-layout — before
          # the session script's `vert Nresize` commands finish — and
          # `Infoview.__width` gets frozen against an interim
          # `vim.o.columns`, leaving it stuck at ~minimum width. Toggle
          # manually with <localleader>i.
          infoview.autoopen = false;
        };
        event = [
          "BufReadPre *.lean"
          "BufNewFile *.lean"
        ];
        keys = [
          # Restart Lean LSP in case it gets in a bad build state after `lake build` in the terminal
          {
            key = "<localleader>R";
            mode = [ "n" ];
            ft = [ "lean" ];
            lua = true;
            action = ''
              function()
                for _, client in ipairs(vim.lsp.get_clients()) do
                  if client.name == "lean" then
                    client.stop()
                  end
                end
                vim.cmd("edit")
              end
            '';
            desc = "Restart Lean LSP completely";
          }
        ];
      };
      # Magit-like git UI: status, commit/rebase/merge popups, worktree popup.
      # Routes diffs through diffview.nvim (already enabled above) for proper
      # side-by-side review.
      neogit = {
        package = pkgs-unstable.vimPlugins.neogit;
        setupModule = "neogit";
        setupOpts = {
          integrations = {
            diffview = true;
            telescope = true;
            snacks = true;
          };
          # Open status as a vertical split to the left so it composes with
          # existing layouts instead of taking the whole window
          kind = "vsplit";
          disable_commit_confirmation = false;
        };
        cmd = [
          "Neogit"
          "NeogitCommit"
          "NeogitLogCurrent"
          "NeogitResetState"
        ];
        keys = [
          {
            key = "<leader>gs";
            mode = [ "n" ];
            action = "<cmd>Neogit<cr>";
            desc = "Neogit status";
          }
          {
            key = "<leader>gw";
            mode = [ "n" ];
            action = "<cmd>Neogit worktree<cr>";
            desc = "Neogit worktree popup";
          }
          {
            key = "<leader>gc";
            mode = [ "n" ];
            action = "<cmd>Neogit commit<cr>";
            desc = "Neogit commit popup";
          }
          {
            key = "<leader>gl";
            mode = [ "n" ];
            action = "<cmd>Neogit log<cr>";
            desc = "Neogit log popup";
          }
          {
            key = "<leader>gp";
            mode = [ "n" ];
            action = "<cmd>Neogit push<cr>";
            desc = "Neogit push popup";
          }
        ];
      };
    };
    clipboard = {
      enable = true;
      registers = "unnamedplus";
    };
    undoFile.enable = true;
    # TODO: Replace with https://github.com/gbprod/yanky.nvim
    utility.undotree = {
      enable = true;
    };

    # Preserve swapfiles in case Neovim crashes
    preventJunkFiles = false;
    # `stdpath` is at `~/.local/share/nvf/`
    options.directory = lib.generators.mkLuaInline "vim.fn.stdpath('data') .. '/swap'";
    options.backupdir = lib.generators.mkLuaInline "vim.fn.stdpath('data') .. '/backup'";

    # Using persistence.nvim for now
    session.nvim-session-manager = {
      enable = false;
    };

    # Lower case chars will match on upper-case as well
    searchCase = "smart";

    # Move cursor between buffers with Ctrl+hjkl
    # Resize with Alt+hjkl
    # Swap buffers with <leader>ws+hjkl
    utility.smart-splits = {
      enable = true;
      setupOpts = {
        multiplexer_integration = "tmux";
        # No-wrap: hitting C-l in the rightmost split (etc.) is a no-op
        # rather than wrapping back to the leftmost. Matches the tmux-side
        # no-wrap guards so the whole nav chain stops at outer edges.
        at_edge = "stop";
      };
      keymaps = {
        move_cursor_left = "<C-h>";
        move_cursor_down = "<C-j>";
        move_cursor_up = "<C-k>";
        move_cursor_right = "<C-l>";
        swap_buf_left = "<leader>wsh";
        swap_buf_down = "<leader>wsj";
        swap_buf_up = "<leader>wsk";
        swap_buf_right = "<leader>wsl";
      };
    };

    # Tab line gives a quick overview of open tabs and whether they are saved
    # Also helps with navigating open buffers, so I don't have to cycle by memory
    # or open the buffers list, which is a power tool and usually overkill
    tabline.nvimBufferline = {
      enable = true;
      setupOpts.options = {
        sort_by = "insert_at_end";
        hover = {
          enabled = true;
          delay = 100;
        };
      };
      mappings = {
        cycleNext = "<C-Right>";
        cyclePrevious = "<C-Left>";
        moveNext = "<A-Right>";
        movePrevious = "<A-Left>";
      };
    };
    # Needed for bufferline's hover on tab event showing the close icon
    options.mousemoveevent = true;

    # External-write handling for agentic Claude workflows.
    # autoread: reload buffers whose files change externally without prompting.
    # updatetime: default 4000ms is too slow for CursorHold-based reload
    # detection; 250ms also makes LSP hovers/diagnostics feel snappier.
    options.autoread = true;
    options.updatetime = 250;

    # Show dots for trailing whitespace and non-breaking spaces
    options.list = true;
    options.listchars = "trail:·,nbsp:·,tab:  ";

    mini.bufremove = {
      enable = true;
    };

    # Leader key
    globals.mapleader = " ";
    keymaps = [
      {
        key = "<leader>lf";
        mode = [ "n" ];
        lua = true;
        action = ''
          function() require("conform").format({ async = true }) end
        '';
        desc = "Format buffer";
      }
      {
        key = "x";
        mode = [ "n" ];
        action = "\"_x";
        desc = "Delete character without copying";
      }
      {
        key = "k";
        mode = [
          "n"
          "v"
          "x"
        ];
        action = "gk";
        # Executes command without displaying it on the command line
        silent = true;
        desc = "Scroll up a visual line";
      }
      {
        key = "j";
        mode = [
          "n"
          "v"
          "x"
        ];
        action = "gj";
        silent = true;
        desc = "Scroll down a visual line";
      }
      {
        key = "<leader><Tab>";
        mode = [
          "n"
          "v"
        ];
        action = ":b#<CR>";
        silent = true;
        # Description is shown by which-key on the leader popup
        desc = "Switch to most recent buffer";
      }
      {
        key = "<leader>b/";
        mode = [
          "n"
          "v"
        ];
        action = ":vnew<CR>";
        silent = true;
        desc = "New buffer split right";
      }
      {
        key = "<leader>b-";
        mode = [
          "n"
          "v"
        ];
        action = ":new<CR>";
        silent = true;
        desc = "New buffer split below";
      }
      # C-hjkl is reserved for smart-splits pane navigation (normal mode
      # only). In insert and terminal modes these keys would forward to
      # tmux via send-keys and cause display corruption in :terminal
      # buffers (e.g. Claude). Swallow them so the user has to leave
      # insert/terminal mode first before navigating.
      {
        key = "<C-h>";
        mode = [
          "i"
          "t"
        ];
        action = "<Nop>";
        silent = true;
        desc = "Disable pane-nav key in insert/terminal mode";
      }
      {
        key = "<C-j>";
        mode = [
          "i"
          "t"
        ];
        action = "<Nop>";
        silent = true;
        desc = "Disable pane-nav key in insert/terminal mode";
      }
      {
        key = "<C-k>";
        mode = [
          "i"
          "t"
        ];
        action = "<Nop>";
        silent = true;
        desc = "Disable pane-nav key in insert/terminal mode";
      }
      {
        key = "<C-l>";
        mode = [
          "i"
          "t"
        ];
        action = "<Nop>";
        silent = true;
        desc = "Disable pane-nav key in insert/terminal mode";
      }
      {
        # Deletes the buffer, prompting to save if changed
        # Based on https://github.com/folke/snacks.nvim/blob/main/lua/snacks/bufdelete.lua
        key = "<leader>bd";
        mode = [
          "n"
          "v"
        ];
        lua = true;
        action = ''
          function()
            local bd = require("mini.bufremove").delete
            if vim.bo.modified then
              local choice = vim.fn.confirm(("Save changes to %q?"):format(vim.fn.bufname()), "&Yes\n&No\n&Cancel")
              if choice == 1 then -- Yes
                local ok, out = pcall(vim.api.nvim_command_output, "write")
                bd(0)
                if ok and out ~= "" then
                  vim.schedule(function()
                    vim.api.nvim_echo({{out, "Normal"}}, false, {})
                  end)
                end
              elseif choice == 2 then -- No
                bd(0, true)
              end
            else
              bd(0)
            end
          end
        '';
        silent = false;
        desc = "Delete buffer";
      }
      {
        key = "<leader>bD";
        mode = [
          "n"
          "v"
        ];
        lua = true;
        action = ''
          function()
            local bd = require("mini.bufremove").delete(0, true)
          end
        '';
        silent = false;
        desc = "Delete buffer (force)";
      }
      {
        key = "<leader>bt";
        mode = [
          "n"
          "v"
        ];
        action = "<cmd>vsp | terminal<CR>";
        silent = true;
        desc = "Open terminal to the right";
      }
      {
        key = "<Esc>";
        mode = [ "t" ];
        action = "<C-\\><C-n>";
        silent = true;
        desc = "Exit terminal mode";
      }
      {
        key = "<leader>w/";
        mode = [
          "n"
          "v"
        ];
        action = ":vsp<CR>";
        silent = true;
        desc = "New window split right";
      }
      {
        key = "<leader>w-";
        mode = [
          "n"
          "v"
        ];
        action = ":sp<CR>";
        silent = true;
        desc = "New window split below";
      }
      {
        key = "<leader>wd";
        mode = [
          "n"
          "v"
        ];
        action = ":close<CR>";
        silent = true;
        desc = "Close window";
      }
      {
        key = "<Esc>";
        mode = [ "n" ];
        action = "<cmd>nohlsearch<CR>";
        silent = true;
        desc = "Turn off search highlighting";
      }
      {
        key = "<leader>t";
        mode = [
          "n"
          "v"
        ];
        action = ":Neotree<CR>";
        silent = true;
        desc = "Open filetree";
      }
      {
        key = "<leader>ut";
        mode = [ "n" ];
        action = ":UndotreeToggle<CR>";
        silent = true;
        desc = "Toggle Undo Tree";
      }
      {
        key = "<leader>sl";
        mode = [ "n" ];
        action = ":Persisted load<CR>";
        silent = true;
        desc = "Load session for the current directory";
      }
      {
        key = "<leader>sL";
        mode = [ "n" ];
        action = ":Persisted load_last<CR>";
        silent = true;
        desc = "Load most recent session (global)";
      }
      {
        key = "<leader>ss";
        mode = [ "n" ];
        action = ":Persisted select<CR>";
        silent = true;
        desc = "Select session to load";
      }
      {
        key = "<leader>sS";
        mode = [ "n" ];
        action = ":Persisted save<CR>";
        silent = true;
        desc = "Save current session now";
      }
      {
        key = "<leader>st";
        mode = [ "n" ];
        action = ":Persisted toggle<CR>";
        silent = true;
        desc = "Toggle session (load/start/stop)";
      }
      {
        key = "<leader>sq";
        mode = [ "n" ];
        action = ":Persisted stop<CR>";
        silent = true;
        desc = "Disable autosave for this session";
      }
      {
        key = "<leader>se";
        mode = [ "n" ];
        action = ":Persisted start<CR>";
        silent = true;
        desc = "Enable autosave for this session";
      }
      {
        key = "<leader>sD";
        mode = [ "n" ];
        action = ":Persisted delete_current<CR>";
        silent = true;
        desc = "Delete current session";
      }
      {
        key = "<leader>sd";
        mode = [ "n" ];
        action = ":Persisted delete<CR>";
        silent = true;
        desc = "Delete a session from a list";
      }
      # TODO: Snacks picker or telescope?
      {
        key = "<leader><space>";
        mode = [ "n" ];
        lua = true;
        action = ''
          function()
            Snacks.picker.smart()
          end
        '';
        silent = true;
        desc = "Smart Find Files";
      }
      {
        key = "<leader>FB";
        mode = [ "n" ];
        lua = true;
        action = ''
          function() Snacks.picker.buffers() end
        '';
        desc = "Buffers";
      }
      {
        key = "<leader>FF";
        mode = [ "n" ];
        lua = true;
        action = ''
          function() Snacks.picker.files() end
        '';
        desc = "Find Files";
      }
      {
        key = "<leader>FP";
        mode = [ "n" ];
        lua = true;
        action = ''
          function() Snacks.picker.projects() end
        '';
        desc = "Projects";
      }
    ];

    binds.whichKey = {
      enable = true;
      register = {
        "<leader>b" = "+Buffers";
        "<leader>g" = "+Git";
        "<leader>s" = "+Sessions";
        "<leader>u" = "+Undo Tree";
        "<leader>l" = "+LSP";
        "<leader>n" = "+Notes";
        "<leader>w" = "+Windows";
        "<leader>ws" = "+Swap windows";
      };
    };

    binds.hardtime-nvim = {
      enable = false;
      #enable = true;
    };

    lsp = {
      enable = true;
      formatOnSave = true;
      # Conform handles the format key so it selects the same formatter as save.
      mappings.format = null;
      inlayHints.enable = true;
      lightbulb.enable = false;
      #lspSignature.enable = true;
      lspkind.enable = true;
      # nil (the Nix LSP, started by languages.nix.lsp) prompts on every
      # .nix buffer whose flake inputs aren't in the store yet — "… not
      # available. Fetch them now?". autoArchive runs `nix flake archive`
      # to fetch them automatically instead of asking each time. The nested
      # key is servers.<lsp>.settings.<lsp-config-section>.…, so `nil.nil`
      # is the server name followed by nil's own config section.
      servers.nil.settings.nil.nix.flake.autoArchive = true;
      #mappings = {
      #
      #};
    };
    languages.nix = {
      enable = true;
      # Breaks indentation of comments and new lines
      # Disabling along with the tabstop autcmd below means tabbing on newline won't auto-indent to previous line's indent
      treesitter.enable = false;
      # Canonical output (same AST → same format) for minimal, stable diffs.
      # Alejandra 4.0 preserves input line breaks, so multi-line lists stay
      # multi-line even if they'd fit on one — Claude edits and hand-written
      # expansions both lock in. nixfmt (RFC 166) is pure: always expands
      # multi-item lists, no input-layout memory.
      format = {
        enable = true;
        type = [ "nixfmt" ];
      };
      lsp = {
        enable = true;
      };
    };

    autocmds = [
      {
        enable = true;
        desc = "Tabs into 2 spaces for Nix";
        event = [ "FileType" ];
        pattern = [ "nix" ];
        callback = lib.generators.mkLuaInline ''
          function()
            vim.opt_local.shiftwidth =  2
            vim.opt_local.tabstop =  2
            vim.opt_local.softtabstop =  2
          end
        '';
      }
      {
        enable = true;
        # lean.nvim opens the infoview with `botright Xvsplit`, which steals
        # width from the adjacent window only. With 3+ columns this squashes
        # the rightmost one while the others stay put. bufresize's
        # resize_open() re-reads the registered pre-split layout and applies
        # proportional widths to every existing split, leaving the new
        # infoview at its configured width. vim.schedule defers the call
        # until after lean finishes its layout operations.
        desc = "Proportionally rebalance splits when Lean infoview opens (instead of squashing the rightmost)";
        event = [ "FileType" ];
        pattern = [ "leaninfo" ];
        callback = lib.generators.mkLuaInline ''
          function()
            vim.schedule(function()
              pcall(require('bufresize').resize_open)
            end)
          end
        '';
      }
      {
        enable = true;
        desc = "Trigger :checktime so buffers reload after external writes (Claude auto-accept, git pull, etc.)";
        event = [
          "BufEnter"
          "FocusGained"
          "CursorHold"
          "CursorHoldI"
        ];
        pattern = [ "*" ];
        command = "if mode() !~ '[cC]' | checktime | endif";
      }
      {
        enable = true;
        desc = "Enter insert mode when starting terminal";
        event = [ "TermOpen" ];
        callback = lib.generators.mkLuaInline ''
          function()
            vim.cmd("startinsert")
          end
        '';
      }
      {
        enable = true;
        desc = "Enter insert mode and restore guicursor in terminal after Git buffer";
        event = [ "BufLeave" ];
        pattern = [
          "*COMMIT_EDITMSG"
          "*git-rebase-todo"
        ];
        callback = lib.generators.mkLuaInline ''
          function()
            vim.schedule(function()
              if vim.bo.buftype == 'terminal' then
                vim.cmd("set guicursor& | set guicursor=" .. vim.o.guicursor)
                vim.cmd("startinsert")
              end
            end)
          end
        '';
      }
      # Workaround due to Noice mangling swapfile messages in the UI on session restore
      # When opening a file otherwise, the swap message takes priority and prints correctly
      # {
      #   enable = true;
      #   desc = "Disable Noice before loading session";
      #   event = ["User"];
      #   pattern = ["PersistedLoadPre"];
      #   callback = lib.generators.mkLuaInline ''
      #     function()
      #       vim.cmd("Noice disable")
      #     end
      #   '';
      # }
      # {
      #   enable = true;
      #   desc = "Enable Noice after loading session";
      #   event = ["User"];
      #   pattern = ["PersistedLoadPost"];
      #   callback = lib.generators.mkLuaInline ''
      #     function()
      #       vim.cmd("Noice enable")
      #     end
      #   '';
      # }
      # Sidebar-style buffers (neo-tree, undotree, Neogit*, Diffview*) don't
      # round-trip through :mksession — the session would restore them as
      # broken empty buffers. Pattern from persisted.nvim's README §Events.
      # Neogit* covers NeogitStatus, NeogitPopup, NeogitLogView, NeogitDiffView,
      # NeogitCommitView, NeogitStashView, NeogitRefsView, NeogitConsole,
      # NeogitReflogView, NeogitCommitSelectView, NeogitGitCommandHistory.
      # Diffview* covers DiffviewFiles (file panel) and DiffviewFileHistory.
      #
      # Also strips non-file buffers other than :terminal: snacks dashboard,
      # snacks scratch, quickfix, help, prompt. These carry no recoverable
      # state — on reload they'd reappear as empty windows and hide the
      # files we actually care about. :terminal buffers are kept; nvim's
      # sessionoptions include "terminal" by default, so the saved session
      # reopens them as fresh shells in the original window layout.
      {
        enable = true;
        desc = "Strip sidebar + non-file buffers (keep :terminal) before persisted save";
        event = [ "User" ];
        pattern = [ "PersistedSavePre" ];
        callback = lib.generators.mkLuaInline ''
          function()
            local strip = { "neo-tree", "undotree", "diff", "leaninfo" }
            for _, buf in ipairs(vim.api.nvim_list_bufs()) do
              local ft = vim.bo[buf].filetype
              local bt = vim.bo[buf].buftype
              if (bt ~= "" and bt ~= "terminal")
                or vim.tbl_contains(strip, ft)
                or ft:match("^Neogit")
                or ft:match("^Diffview")
              then
                vim.api.nvim_buf_delete(buf, { force = true })
              end
            end
          end
        '';
      }
    ];

    languages.rust = {
      enable = true;
      treesitter.enable = true;
      #format.enable = true;
      #crates.enable = true;
      lsp = {
        # Enabling makes the LSP start automatically via the global `vim.lsp.enable('rust-analyzer')` setting
        # This breaks when opening files from another directory because direnv hasn't finished loading rust-analyzer yet.
        # The solution is the direnv.nvim autocmd in `extraPlugins`
        enable = false;
      };
    };

    # texlab for completion and diagnostics. VimTeX (in extraPlugins) owns
    # highlighting, since tree-sitter highlighting replaces the syntax groups
    # its motions and conceal depend on.
    languages.tex = {
      enable = true;
      treesitter.enable = false;
      format = {
        enable = true;
        type = [ "tex-fmt" ];
      };
      lsp.enable = true;
    };

    formatter.conform-nvim.setupOpts = {
      formatters_by_ft.bib = [ "tex-fmt" ];
      formatters.tex-fmt = {
        # Resolve through PATH so a dev shell overrides the bundled fallback.
        command = lib.mkForce "tex-fmt";
        # Let tex-fmt.toml control indentation instead of buffer settings.
        args = [ "--stdin" ];
      };
    };

    notes.obsidian = {
      enable = true;
      setupOpts = {
        legacy_commands = false;
        workspaces = [
          {
            name = "vault";
            path = "~/Documents/vault";
          }
        ];
        completion = {
          blink = true;
          nvim_cmp = false;
        };
        note_id_func = lib.generators.mkLuaInline ''require("obsidian.builtin").title_id'';
        frontmatter.enabled = false;
        sync.enabled = true;
        daily_notes.folder = "daily";
        checkbox.enabled = false;
        # Obsidian reinstalls its Enter mapping on every vault note entry.
        callbacks.enter_note = lib.generators.mkLuaInline ''
          function()
            if vim.bo.filetype == "markdown" then
              (${markdownMappings})(vim.api.nvim_get_current_buf())
            end
          end
        '';
      };
    };

    # Separate data rows visually without adding separator rows to Markdown files.
    pluginOverrides.render-markdown-nvim = pkgs.applyPatches {
      name = "render-markdown-nvim";
      src =
        (inputs.mnw.lib.npinsToPluginsAttrs pkgs "${inputs.self}/npins/sources.json").render-markdown-nvim;
      patches = [
        (pkgs.writeText "render-markdown-table-grid.patch" ''
          --- a/lua/render-markdown/render/markdown/table.lua
          +++ b/lua/render-markdown/render/markdown/table.lua
          @@ -422,4 +422,9 @@
               table_border(first.node, true, { border[1], border[2], border[3] })
               if #rows > 1 then
          +        for _, row in ipairs(rows) do
          +            if row ~= last and row.node.type == 'pipe_table_row' then
          +                table_border(row.node, false, { border[4], border[5], border[6] })
          +            end
          +        end
                   table_border(last.node, false, { border[7], border[8], border[9] })
               end
        '')
        (pkgs.writeText "render-markdown-before-ui-flush.patch" ''
          --- a/lua/render-markdown/core/manager.lua
          +++ b/lua/render-markdown/core/manager.lua
          @@ -98,3 +98,4 @@
                   'ModeChanged',
          +        'SafeState',
                   'TextChanged',
                   'WinScrolled',
          --- a/lua/render-markdown/core/ui.lua
          +++ b/lua/render-markdown/core/ui.lua
          @@ -42,3 +42,3 @@
               log.buf('info', 'Update', buf, event, ('force %s'):format(force))
          -    M.updater.new(buf, win, force):start()
          +    M.updater.new(buf, win, force):start(event)
           end
          @@ -70,6 +70,14 @@
          -function Updater:start()
          +---@param event string
          +function Updater:start(event)
               if not env.valid(self.buf, self.win) then
                   return
               end
          +    -- SafeState follows text-changing autocmds and precedes the UI flush.
          +    if event == 'SafeState' then
          +        if self.config.debounce == 0 and self:changed() then
          +            self:run()
          +        end
          +        return
          +    end
               self.decorator:schedule(
                   self:changed() and not env.buf.empty(self.buf),
        '')
      ];
    };

    # Anchor the footer at EOF, after virtual borders on the last text line.
    pluginOverrides.obsidian-nvim = pkgs.vimUtils.buildVimPlugin {
      name = "obsidian.nvim";
      src = (inputs.mnw.lib.npinsToPluginsAttrs pkgs "${inputs.self}/npins/sources.json").obsidian-nvim;
      patches = [
        (pkgs.writeText "obsidian-footer-position.patch" ''
          --- a/lua/obsidian/footer/init.lua
          +++ b/lua/obsidian/footer/init.lua
          @@ -42,7 +42,7 @@
               local footer_format = Obsidian.opts.footer.format
               ---@cast footer_format -nil
               local display_text = note_status(buf, footer_format, update_backlinks)
          -    local row0 = #vim.api.nvim_buf_get_lines(buf, 0, -2, false)
          +    local row0 = vim.api.nvim_buf_line_count(buf)
               local col0 = 0
               local separator = Obsidian.opts.footer.separator
               local hl_group = Obsidian.opts.footer.hl_group
          @@ -55,5 +55,5 @@
                 footer_chunks = { footer_contents }
               end
          -    local opts = { virt_lines = footer_chunks }
          +    local opts = { virt_lines = footer_chunks, virt_lines_above = true }
               vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
               vim.api.nvim_buf_set_extmark(buf, ns_id, row0, col0, opts)
        '')
      ];
      nvimSkipModules = [
        "minimal"
        "obsidian.picker._telescope"
        "obsidian.picker._snacks"
        "obsidian.picker._fzf"
        "obsidian.picker._mini"
      ];
    };

    lazy.plugins.obsidian-nvim = {
      # The shared editor package also runs on machines without the vault.
      enabled = lib.generators.mkLuaInline ''
        function()
          return vim.fn.isdirectory(vim.fn.expand("~/Documents/vault")) == 1
        end
      '';
      keys = [
        {
          key = "<leader>nf";
          mode = "n";
          action = "<cmd>Obsidian quick_switch<CR>";
          desc = "Find note";
        }
        {
          key = "<leader>ns";
          mode = "n";
          action = "<cmd>Obsidian search<CR>";
          desc = "Search notes";
        }
        {
          key = "<leader>nn";
          mode = "n";
          action = "<cmd>Obsidian new<CR>";
          desc = "New note";
        }
        {
          key = "<leader>nd";
          mode = "n";
          action = "<cmd>Obsidian today<CR>";
          desc = "Today's daily note";
        }
        {
          key = "<leader>nb";
          mode = "n";
          action = "<cmd>Obsidian backlinks<CR>";
          desc = "Note backlinks";
        }
        {
          key = "<leader>nl";
          mode = "n";
          action = "<cmd>Obsidian follow_link<CR>";
          desc = "Follow note link";
        }
      ];
    };

    globals = {
      # Mkdnflow manages folds; render-markdown controls note styling.
      vim_markdown_folding_disabled = 1;
      vim_markdown_conceal = 0;
      vim_markdown_conceal_code_blocks = 0;
    };

    languages.markdown = {
      enable = true;
      # Empty cells are valid data, but cannot start a table's delimiter row.
      # https://github.com/tree-sitter-grammars/tree-sitter-markdown/issues/242
      treesitter.mdPackage = pkgs.vimPlugins.nvim-treesitter.grammarToPlugin (
        pkgs.vimPlugins.nvim-treesitter.builtGrammars.markdown.overrideAttrs (old: {
          patches = (old.patches or [ ]) ++ [
            (pkgs.writeText "markdown-empty-table-rows.patch" ''
              --- a/tree-sitter-markdown/src/scanner.c
              +++ b/tree-sitter-markdown/src/scanner.c
              @@ -1262,9 +1262,7 @@
                           advance(s, lexer);
                       }
                       if (lexer->lookahead == '|') {
              -            delimiter_cell_count++;
              -            advance(s, lexer);
              -            continue;
              +            return false;
                       }
                       if (lexer->lookahead == ':') {
                           advance(s, lexer);
            '')
          ];
        })
      );
      format = {
        enable = true;
      };
      lsp = {
        enable = true;
      };
      extensions = {
        render-markdown-nvim =
          let
            navigationModes = [
              "n"
              "no"
              "nov"
              "noV"
              (lib.generators.mkLuaInline ''"no\22"'')
            ];
          in
          {
            enable = true;
            setupOpts = {
              checkbox.checked.icon = "✓ ";
              # Refresh moved decorations after each edit, including rapid undo/redo.
              debounce = 0;
              # Keep the preview visible while an operator waits for its motion.
              render_modes = navigationModes ++ [
                "c"
                "t"
              ];
              win_options.concealcursor.rendered = "nc";
              anti_conceal = {
                disabled_modes = navigationModes;
                ignore = {
                  check_icon = true;
                  code_inline = true;
                };
              };
              # Multiple `==` on the same line even within code blocks
              # cause the whole line to highlight and conceal the `==` signs
              # Switch to removing all highlights if desired
              # inline_highlight = {
              #   enabled = false;
              # };
            };
          };
      };
    };
    # TODO: Modeline icons and general nerd font support (already installed in home.nix and supported by Ghostty)
    #utility.icon-picker.enable = true;

    # Route :terminal-launched editor invocations (git commit, fzf, etc.)
    # back through flatten.nvim. Forcing EDITOR=nvim, scoped to this nvim
    # via vim.env, makes a child editor connect to the parent's NVIM socket
    # (flatten is nvim-only) instead of opening a nested full TUI in the
    # terminal pane. Scoping it here keeps the routing intact regardless of
    # what the surrounding environment resolved EDITOR to.
    #
    # The serverstart fallback covers the rare case where the auto-server
    # didn't come up at boot (e.g. the wrapper's $NVIM_LISTEN_ADDRESS
    # collided with a stale socket). Without v:servername, :terminal
    # can't export $NVIM and flatten opens nested nvim on git commit.
    luaConfigRC.editor-env = ''
      vim.env.EDITOR = "nvim"
      if vim.v.servername == "" then
        pcall(vim.fn.serverstart)
      end
    '';

    # With no local display — e.g. nvim running over ssh in the dev
    # microvm — wl-copy/xclip have no clipboard to reach, so y/p can't use
    # the system clipboard. Use OSC 52 instead: nvim emits an escape
    # sequence that the host terminal (ghostty) turns into a clipboard
    # write/read. On the host (WAYLAND_DISPLAY set) the default wl-copy
    # provider is left in place, since it's more robust than OSC 52.
    luaConfigRC.clipboard-osc52 = ''
      if vim.env.WAYLAND_DISPLAY == nil and vim.env.DISPLAY == nil then
        local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
        if ok then
          vim.g.clipboard = {
            name = "OSC 52",
            copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
            paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
          }
        end
      end
    '';

  };
}

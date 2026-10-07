;; TODO
;; Figure out how keymaps work
;; Disable the evil-repeat keybinding as . or rebind it to something more sane
;; Figure out how general works and integrate the above into it
;; Set a keybinding for LSP go-to definition in Rust
;; Get LSP to start automatically in Rust
;; Enable straight.el
(defvar bootstrap-version)
(let ((bootstrap-file
       (expand-file-name "straight/repos/straight.el/bootstrap.el" user-emacs-directory))
      (bootstrap-version 5))
  (unless (file-exists-p bootstrap-file)
    (with-current-buffer
        (url-retrieve-synchronously
         "https://raw.githubusercontent.com/raxod502/straight.el/develop/install.el"
         'silent 'inhibit-cookies)
      (goto-char (point-max))
      (eval-print-last-sexp)))
  (load bootstrap-file nil 'nomessage))

(straight-use-package 'use-package)
(setq straight-use-package-by-default t)

;; UI Configs
(setq inhibit-startup-message t)
(setq initial-scratch-message ";; Happy Hacking")

(scroll-bar-mode -1)        ; Disable visible scrollbar
(tool-bar-mode -1)          ; Disable the toolbar
(tooltip-mode -1)           ; Disable tooltips
(menu-bar-mode -1)          ; Disable the menu bar
;;(set-fringe-mode nil)      ; Give some breathing room on the edges

;; Set up the visible bell
(setq visible-bell t)

;; Add columns and line numbers
(column-number-mode)
(global-display-line-numbers-mode t)
(setq display-line-numbers-type 'relative)
;; Not sure what the below does, failed attempt to decrease fringe next to line numbers
;;(setq-default fringes-outside-margins t)
;;(global-display-line-numbers-mode t)
;;(global-whitespace-mode -1)
;;(setq display-line-numbers 'relative)

;; Split popups vertically by default
(setq split-height-threshold nil)
(setq split-width-threshold 0)

;; Disable line numbers for some modes
;;(dolist (mode '(org-mode-hook
;;                term-mode-hook
;;                shell-mode-hook
;;                eshell-mode-hook))
;;  (add-hook mode (lambda () (display-line-numbers-mode 0))))

;; TODO: customize based on monitor size
;;(add-to-list 'default-frame-alist '(height . 80))
;;(add-to-list 'default-frame-alist '(width . 200))

(use-package smooth-scrolling
  :config
  (smooth-scrolling-mode 1))

(use-package doom-themes
  :config
  ;; Disables italic line numbers
  (setq doom-themes-enable-italic nil)
  (load-theme 'doom-solarized-dark-high-contrast t)
  (doom-themes-org-config))

;; Make ESC quit prompts
(global-set-key (kbd "<escape>") 'keyboard-escape-quit)

;; TODO: figure out best way to autosave
;; Other configs
(setq make-backup-files t
      auto-save-default t
      backup-directory-alist
      `(("." . "~/.emacs-auto-saves"))
      delete-old-versions t
      kept-new-versions 2
      kept-old-versions 2
      version-control t)

(desktop-save-mode t)
(savehist-mode t)
(add-to-list 'savehist-additional-variables 'kill-ring)

;; Auto reload buffer when changed on disk
(global-auto-revert-mode t)

;; Custom keybindings
;; NOTE: Pressing "C-u" before SPC will modify some of these to have special behavior
;; E.g. C-u SPC r b allows for custom arguments
;; TODO: Figure out how to make "M-SPC" emulate "C-u" instead of non-normal-prefix,
;; which I never use
(use-package general
  :config
  (general-evil-setup t)
  (general-define-key
   :states '(motion normal visual insert emacs)
  :keymaps 'override
  :prefix "SPC"
  :non-normal-prefix "M-SPC"
  "TAB"   '(switch-to-previous-buffer :which-key "previous buffer")
  "SPC"   '(execute-extended-command :which-key "M-x")
  "y"     '(browse-kill-ring :which-key "show kill ring")
  ;; Find file
  "f"     '(find-file :which-key "find file")
  ;; Buffers
  "b"     '(:which-key "buffers")
  "bb"     '(switch-to-buffer :which-key "buffer list")
  "bx"     '(kill-current-buffer :which-key "kill current buffer")
  ;; Dired
  "d"     '(dired-jump :which-key "dired")
  ;; Add new element
  "a"     '(:which-key "add")
  "at"    '(eshell :which-key "shell")
  "af"    '(make-frame :which-key "frame")
  ;; Evaluate Elisp
  "e"     '(:which-key "eval Elisp")
  "er"    '(eval-region :which-key "eval highlighted region")
  "eb"    '(eval-buffer :which-key "eval buffer")
  ;; Command log mode
  "c"     '(:which-key "command log")
  "cb"    '(clm/toggle-command-log-buffer :which-key "toggle clm buffer")
  ;; Window
  "w"     '(:which-key "window")
  "wl"    '(windmove-right :which-key "move right")
  "wh"    '(windmove-left :which-key "move left")
  "wk"    '(windmove-up :which-key "move up")
  "wj"    '(windmove-down :which-key "move bottom")
  "w/"    '(split-window-right :which-key "split right")
  "w-"    '(split-window-below :which-key "split bottom")
  "wa"    '(ace-window :which-key "select window")
  "ws"    '(ace-swap-window :which-key "swap windows")
  "wx"    '(delete-window :which-key "delete window")
  "q"     '(:which-key "quit")
  "qz"    '(delete-frame :which-key "delete frame")
  ;; Popups
  "p"     '(:which-key "popups")
  "pt"    '(popper-toggle-type :which-key "toggle type")
  "pc"    '(popper-cycle :which-key "cycle")
  "p TAB"  '(popper-toggle-latest :which-key "toggle latest")
  ;; This kills the Emacs server as well, which I rarely want
  ;; Maybe re-enable once I get autosave working
  ;;"qq"    '(kill-emacs :which-key "quit")
  ;; Magit
  "g"    '(magit-status :which-key "magit status")
  ;; LSP
  "l"     '(:which-key "LSP")
  ;; TODO: Get LSP to start automatically when entering a Rust buffer
  "ls"  '(lsp :which-key "Start LSP")
  "la"  '(lsp-execute-code-action :which-key "execute")
  "lr"  '(lsp-rename :which-key "rename")
  "lq"  '(lsp-restart :which-key "restart")
  "lQ"  '(lsp-workspace-restart :which-key "restart all")
  "ll"  '(flycheck-list-errors :which-key "flycheck")
  "lf"  '(xref-find-references :which-key "list references")
  "ld"  '(xref-find-definitions :which-key "go to def")
  "lb"  '(xref-go-back :which-key "go back")
  ;; Rust
  ;; C-c C-k to kill compilation, change to something more ergonomic
  "r"     '(:which-key "Rust")
  "ra"    '(rustic-run-shell-command :which-key "any command")
  "r TAB" '(rustic-recompile :which-key "recompile")
  "rs"  '(lsp-rust-analyzer-status :which-key "status")
  "rk"  '(rustic-cargo-check :which-key "check")
  "rb"  '(rustic-cargo-build :which-key "build")
  "rr"  '(rustic-cargo-run :which-key "run")
  "rt"  '(rustic-cargo-test :which-key "test")
  "rT"  '(rustic-cargo-current-test :which-key "this test")
  "rf"  '(rustic-cargo-fmt :which-key "format")
  "rc"  '(rustic-cargo-clippy :which-key "clippy")
  ;; Org
  ;; Projectile
  ;; "pf"  '(helm-projectile-find-file :which-key "find files")
  ;; "pp"  '(helm-projectile-switch-project :which-key "switch project")
  ;; "pb"  '(helm-projectile-switch-to-buffer :which-key "switch buffer")
  ;;  "/"   '(helm-projectile-rg :which-key "ripgrep")
))
;;

;; Switch to most recent buffer
(defun switch-to-previous-buffer ()
  (interactive)
  (switch-to-buffer (other-buffer)))

;; Vim Evil mode
;; TODO: disable q as macro definer
;; https://github.com/noctuid/evil-guide
(use-package evil
  :init
  (setq evil-want-integration t)
  (setq evil-want-keybinding nil)
  (setq evil-want-C-i-jump nil)
  :config
  (evil-mode 1))

(use-package evil-collection
  :after evil
  ;; Not sure if needed
  :custom (evil-collection-setup-minibuffer t)
  :config (evil-collection-init))

;; TODO: make the completion window browsable with evil keys
;; https://www.masteringemacs.org/article/understanding-minibuffer-completion
(fido-vertical-mode t)
(setq completions-detailed t)
(setq completion-cycle-threshold 5)

;; TODO: Disable "qq" setting kbd macro
;; Manage popup windows
(use-package popper
  :init
  (setq popper-reference-buffers
        '("\\*Messages\\*"
          "Output\\*$"
	  "\\*Warnings\\*"
          "\\*Async Shell Command\\*"
          help-mode
	  "^\\*eshell.*\\*$" eshell-mode
          compilation-mode ; currently not working for rustic-compilation, so it's set separately
	  rustic-compilation-mode))
  (popper-mode t)
  (popper-echo-mode t) ; For echo area hints
  :config (setq popper-display-control nil)) 

;;(setq popper-group-function #'popper-group-by-project) ; project.el projects
;;(setq popper-group-function #'popper-group-by-perspective) ; group by perspective
;; Does above works with perspective-el package or some builtin one?
(use-package shackle
  :init (setq shackle-mode t))
  ;;:config
  ;;(setq shackle-rules '("\\`\\*rustic.*?\\*\\'" :regexp t :align 'below)))
;; Shackle rules not working
;; Edit magit

;; Dired
(use-package dired
  :straight (:type built-in)
  :hook (dired-mode . dired-hide-details-mode)
  :commands (dired dired-jump)
  :bind
;;  (
;;   :map evil-motion-state-map
;;	 ;;evil-forward-sentence-begin
;;	 (")" nil))
  :config
  (put 'dired-find-alternate-file 'disabled nil)
  (evil-collection-define-key 'normal 'dired-mode-map
    "h" 'dired-up-directory
    "l" 'dired-find-file))

(use-package dired-single
  :commands (dired dired-jump))

(use-package all-the-icons-dired
  :hook (dired-mode . all-the-icons-dired-mode)
  :config (setq all-the-icons-dired-monochrome nil))

(use-package dired-git-info
  :config
  (setq dgi-auto-hide-details-p nil)
  :bind (:map dired-mode-map
              (")" . dired-git-info-mode)))
  
;;TODO: diredfl?
;;TODO: Disable the C-z key, which switches from evil state to normal emacs (e.g. no insert/normal mode)
;;(evil-global-set-key 'normal "" `evil-emacs-state)
;;;; Delete without register, "DD" deletes line
;;;;(evil-define-operator evil-delete-without-register (beg end type yank-handler)
;;;;  (interactive "<R><y>")
;;;;  (evil-delete beg end type ?_ yank-handler))
;;;;(define-key evil-normal-state-map (kbd "D") 'evil-delete-without-register)
;;;;(define-key evil-visual-state-map (kbd "D") 'evil-delete-without-register)
;;
;;;; Do something similar with 'evil-change "C-w" or "x" change without register/kill ring
;;;;(define-key evil-visual-state-map (kbd "c") 'evil-delete-without-register)
;;
;; Use visual line motions, allowing scroll within wrapped lines
(evil-global-set-key 'motion "j" 'evil-next-visual-line)
(evil-global-set-key 'motion "k" 'evil-previous-visual-line)

;; Keep cursor in place when scrolling
(setq scroll-preserve-screen-position 1)
;;
;;;; Below scroll commands are backwards, e.g. "scrol-down" actually scrolls up
(defun scroll-half-page-up ()
  "scroll up half the page"
  (interactive)
  ;; "scroll-down" actually scrolls up
  (scroll-down (/ (window-body-height) 2)))

(defun scroll-half-page-down ()
  "scroll down half the page"
  (interactive)
  ;; "scroll-up" actually scrolls down
  (scroll-up (/ (window-body-height) 2)))

;; Page up/down
;; Only works in normal mode
(global-set-key (kbd "C-k") 'scroll-half-page-up)
(global-set-key (kbd "C-j") 'scroll-half-page-down)

;; Single-line scroll up/down
;; Only works in normal mode
(global-set-key (kbd "M-k") 'evil-scroll-line-up)
(global-set-key (kbd "M-j") 'evil-scroll-line-down)

(global-set-key (kbd "C-h M-k") 'describe-keymap)
;; Restore C-y as paste keybinding for insert mode, minibuffer, etc
;; Why does '(normal insert) give errors?
(evil-global-set-key 'normal (kbd "C-y") 'yank)
(evil-global-set-key 'insert (kbd "C-y") 'yank)

;; TODO set C-e as another prefix command or nil
;;(global-unset-key (kbd "C-e"))
;;(define-prefix-command 'extra)
;;(evil-global-set-key '(normal insert) (kbd "C-e") 'extra)

;; TODO: Disable

(use-package ace-window)

(use-package browse-kill-ring)

;; TODO: see useful commands and keybinds from System Crafters
(use-package command-log-mode
  :config
  (global-command-log-mode t))

;; TODO
;; Fix which-key not showing all options, maybe by changing height or below cmd
;;(advice-remove #'fit-window-to-buffer #'doom-modeline-redisplay)
;; which-key-setup-minibuffer
;; Which Key
;;(use-package which-key)
  ;;:init
  ;;(setq which-key-separator " ")
  ;;(setq which-key-prefix-prefix "+")
;;  :diminish which-key-mode
  ;;:config
  ;;(which-key-mode)
  ;;(setq which-key-idle-delay 0.5))
;;
(use-package which-key
  :init 
  (setq which-key-separator " ")
  (setq which-key-prefix-prefix "+")
  :diminish which-key-mode
  :config
  (which-key-mode)
  (setq which-key-idle-delay 0.3))

;; All The Icons
;; Requires fonts: `M-x all-the-icons-install-fonts`
(use-package all-the-icons
  :if (display-graphic-p))

(use-package doom-modeline
  :init (doom-modeline-mode 1)
  :custom ((doom-modeline-height 15)))

(use-package rainbow-delimiters
  :hook (prog-mode . rainbow-delimiters-mode))


;; Shell configs
(defun efs/configure-eshell ()
  ;; Save command history when commands are entered
  (add-hook 'eshell-pre-command-hook 'eshell-save-some-history)

  ;; Truncate buffer for performance
  (add-to-list 'eshell-output-filter-functions 'eshell-truncate-buffer)

  ;; Bind some useful keys for evil-mode
  (evil-define-key '(normal insert visual) eshell-mode-map (kbd "C-r") 'counsel-esh-history)
  (evil-define-key '(normal insert visual) eshell-mode-map (kbd "<home>") 'eshell-bol)
  (evil-normalize-keymaps)

  (setq eshell-history-size         10000
        eshell-buffer-maximum-lines 10000
        eshell-hist-ignoredups t
        eshell-scroll-to-bottom-on-input t))

(use-package eshell-git-prompt)

(use-package eshell
  :hook (eshell-first-time-mode . efs/configure-eshell)
  :config

  (with-eval-after-load 'esh-opt
    (setq eshell-destroy-buffer-when-process-dies t)
    (setq eshell-visual-commands '("htop" "zsh" "vim")))

  (eshell-git-prompt-use-theme 'powerline))

;;(use-package vterm)

;;(use-package envrc
;;  :config
;;  (envrc-global-mode))
;;
;;(with-eval-after-load 'envrc
;;  (define-key envrc-mode-map (kbd "C-c e") 'envrc-command-map))

(use-package sudo-edit)

;;;; Programming Configs

;;;; Global tabs into two spaces unless otherwise specified
;;(setq indent-tabs-mode nil)
;;(setq tab-width 2)
;;;;

;; TODO: Experiment with the below packages, see
;; https://robert.kra.hn/posts/rust-emacs-setup/
(use-package lsp-mode
  :commands lsp
  :custom
  (lsp-rust-analyzer-cargo-watch-command "clippy")
  (lsp-eldoc-render-all t)
  (lsp-idle-delay 0.6)
  ;; enable / disable the hints as you prefer:
  ;; TODO: Get rid of the annoying hints on the side of the window
  (lsp-rust-analyzer-server-display-inlay-hints t)
  (lsp-rust-analyzer-display-lifetime-elision-hints-enable "skip_trivial")
  (lsp-rust-analyzer-display-chaining-hints t)
  (lsp-rust-analyzer-display-lifetime-elision-hints-use-parameter-names t)
  (lsp-rust-analyzer-display-closure-return-type-hints t)
  (lsp-rust-analyzer-display-parameter-hints t)
  (lsp-rust-analyzer-display-reborrow-hints t)
  :config
  (add-hook 'lsp-mode-hook 'lsp-ui-mode))
  ;;(add-hook 'rustic-mode-hook #'lsp)
  (add-hook 'rust-mode-hook #'lsp)
  ;; Attempt to fix lsp-mode not auto-starting for Rust files
  ;;:hook
  ;;(rustic-mode . lsp))

(use-package lsp-ui
  :commands lsp-ui-mode
  :custom
  (lsp-ui-peek-always-show t)
  (lsp-ui-sideline-show-hover t)
  (lsp-ui-doc-enable t))

(use-package company
  :bind
  (:map company-active-map
	("C-n". company-select-next)
	("C-p". company-select-previous)
	("M-<". company-select-first)
	("M->". company-select-last)
	("<tab>". tab-indent-or-complete)
	("TAB". tab-indent-or-complete)))

(use-package yasnippet
  :config
  (yas-reload-all)
  (add-hook 'prog-mode-hook 'yas-minor-mode)
  (add-hook 'text-mode-hook 'yas-minor-mode))

(defun company-yasnippet-or-completion ()
  (interactive)
  (or (do-yas-expand)
      (company-complete-common)))

(defun check-expansion ()
  (save-excursion
    (if (looking-at "\\_>") t
      (backward-char 1)
      (if (looking-at "\\.") t
        (backward-char 1)
        (if (looking-at "::") t nil)))))

(defun do-yas-expand ()
  (let ((yas/fallback-behavior 'return-nil))
    (yas/expand)))

(defun tab-indent-or-complete ()
  (interactive)
  (if (minibufferp)
      (minibuffer-complete)
    (if (or (not yas/minor-mode)
            (null (do-yas-expand)))
        (if (check-expansion)
            (company-complete-common)
          (indent-for-tab-command)))))

;; TODO: Make flycheck use clippy, ideally from rustic config
;; If I get straight.el errors, see this:
;; https://github.com/radian-software/straight.el#integration-with-flycheck
(use-package flycheck)

(use-package exec-path-from-shell
  :init (exec-path-from-shell-initialize))

(use-package rustic
  :config
  (setq rustic-indent-offset 2)
  (setq rustic-format-on-save nil)

  ;; Edit default arguments
  ;;(setq rustic-default-test-arguments "--release --workspace -- --include-ignored --nocapture")
  (setq rustic-default-test-arguments "--release --workspace")
  (setq rustic-cargo-check-arguments "--benches --tests")
  (setq rustic-cargo-clippy-arguments "--all -- -D warnings")
  ;; These get stored dynamically from the output of prior C-u commands
  ;; TODO: Disable the above
  ;;(setq rustic-cargo-build-arguments "")
  ;; Or, set them on the fly with "C-u" prefix (see general)

  ;; Customize rustic-compilation colors for solarized-dark theme
  ;;(setq rustic-ansi-faces ["black" "red3" "green3" "yellow3" "cyan4" "magenta3" "cyan3" "white"])

  (add-hook 'rustic-mode-hook rustic-mode-hook))

(defun rustic-mode-hook ()
  (when buffer-file-name
    (setq-local buffer-save-without-query t))
  (add-hook 'before-save-hook 'lsp-format-buffer nil t))

;;(use-package haskell-mode
;;  :config
;;  (setq haskell-indent-mode t)
;;  (setq haskell-indent-offset 2))
;;
(use-package markdown-mode
  :mode ("README\\.md\\'" . gfm-mode))

(use-package yaml-mode)

(use-package nix-mode
  :mode "\\.nix\\'")

;;(setq js-indent-level 2)
;;(setq js-format-on-save t)
;;

;;Keybindings for lambda and forall
(global-set-key (kbd "M-l") "λ")
(global-set-key (kbd "M-;") "∀")
;;
(use-package magit)
;;
;;
(use-package lean4-mode
  :straight (lean4-mode :type git :host github :repo "leanprover/lean4-mode")
  ;; to defer loading the package until required
  :commands (lean4-mode))
;;
;;(global-set-key (kbd "S-SPC") #'company-complete)
;;;;(evil-define-key 'normal org-mode-map (kbd "<tab>") #'org-cycle)
;;
;;;; Org mode -------------------------------------------------
(defun org-mode-setup ()
  (visual-line-mode)
  (org-indent-mode)
  (font-lock-add-keywords 'org-mode
                          '(("^ *\\([-]\\) "
                             (0 (prog1 () (compose-region (match-beginning 1) (match-end 1) "•")))))))
  
(use-package org
  :hook (org-mode . org-mode-setup)
  :config
  (setq org-ellipsis " ⬎"))
;;
(use-package org-bullets
  :after org
  :hook (org-mode . org-bullets-mode)
  :custom
  (org-bullets-bullet-list '("◉" "○" "●" "○" "●" "○" "●")))

;; Set faces for heading levels
;;(dolist (face '((org-level-1 . 1.2)
;;                (org-level-2 . 1.1)
;;                (org-level-3 . 1.05)
;;                (org-level-4 . 1.0)
;;                (org-level-5 . 1.1)
;;                (org-level-6 . 1.1)
;;                (org-level-7 . 1.1)
;;                (org-level-8 . 1.1)))
;;  (set-face-attribute (car face) nil :font "Cantarell" :weight 'regular :height (cdr face)))

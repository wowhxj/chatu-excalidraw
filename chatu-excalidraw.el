;;; chatu-excalidraw.el --- Chatu backend for Excalidraw  -*- lexical-binding: t -*-

;; Copyright (c) 2024-2026 Randolph Huang

;; Author: Randolph Huang <xiaojianghuang@yahoo.com>
;; URL: https://github.com/kimim/chatu
;; Keywords: multimedia convenience
;; Version: 0.1.0
;; Package-Requires: ((emacs "29.1") (chatu "0"))

;; This file is NOT part of GNU Emacs.

;;; License:

;; This program is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Excalidraw backend for `chatu' (https://github.com/kimim/chatu).
;;
;; Requirements:
;; 1. Install `excalidraw_export' via npm to convert .excalidraw
;;    files to SVG (used by `chatu-add').
;; 2. Either rely on the "open" command (macOS) or install Excalidraw
;;    as a browser PWA / point `chatu-excalidraw-server-url' at a
;;    self-hosted instance to edit diagrams (used by `chatu-open').
;;
;; This package also replaces `chatu-new' with a version based on
;; `completing-read', so the diagram type (drawio/plantuml/excalidraw/...)
;; can be picked from a list instead of typed by hand.  Customize
;; `chatu-excalidraw-new-type-options' and `chatu-excalidraw-new-default-type'
;; to change the choices.

;;; Code:

(require 'chatu)
(require 'chatu-common)

(defgroup chatu-excalidraw nil
  "Chatu backend for Excalidraw."
  :group 'chatu
  :prefix "chatu-excalidraw-")

(defcustom chatu-excalidraw-server-url "https://excalidraw.com/"
  "The URL for the Excalidraw server.
Default is the official server. Set this to your self-hosted instance if needed.

Only used on non-macOS systems. On macOS, `chatu-excalidraw-open' opens
the local .excalidraw file directly via the \"open\" command instead,
relying on an installed Excalidraw PWA being registered as the default
handler for .excalidraw files (which is what makes Cmd-S in the app
save changes straight back to that file). See `chatu-excalidraw-open'."
  :group 'chatu-excalidraw
  :type 'string)

(defcustom chatu-excalidraw-executable-func #'chatu-excalidraw--find-executable
  "The function to find the browser executable for opening Excalidraw."
  :group 'chatu-excalidraw
  :type 'function)

(defcustom chatu-excalidraw-new-type-options '("drawio" "plantuml" "excalidraw")
  "Diagram types offered by `chatu-excalidraw-new'."
  :group 'chatu-excalidraw
  :type '(repeat string))

(defcustom chatu-excalidraw-new-default-type "drawio"
  "Default diagram type preselected by `chatu-excalidraw-new'."
  :group 'chatu-excalidraw
  :type 'string)

(defcustom chatu-excalidraw-new-default-width 800
  "Default image display width (in pixels) offered by `chatu-excalidraw-new'.

This becomes the :width value on the inserted chatu line, and is used
by `chatu-excalidraw-add' to set the #+ATTR_ORG/#+ATTR_HTML width when
rendering, in `org-mode' buffers."
  :group 'chatu-excalidraw
  :type 'integer)

(defcustom chatu-excalidraw-attr-latex-width "0.5\\linewidth"
  "Width used in the #+ATTR_LATEX line inserted by `chatu-excalidraw-add'.

Unlike the pixel :width used for #+ATTR_ORG/#+ATTR_HTML, LaTeX widths
are conventionally expressed as a fraction of \\linewidth."
  :group 'chatu-excalidraw
  :type 'string)

(defconst chatu-excalidraw-font-names '("Virgil" "Cascadia" "Segoe UI Emoji")
  "Font-family names `excalidraw_export' hardcodes in its SVG output.
\"Virgil\" is the hand-drawn text font, \"Cascadia\" the code font,
and \"Segoe UI Emoji\" a fallback used for CJK/emoji text — all three
are declared or assumed available in ways that don't work for
non-browser SVG renderers. See `chatu-excalidraw-handwritten-font'.")

(defcustom chatu-excalidraw-handwritten-font nil
  "Local font family substituted for `chatu-excalidraw-font-names'.

`excalidraw_export' emits SVGs referencing \"Virgil\" and \"Cascadia\"
via @font-face rules that point at remote font URLs (e.g.
https://excalidraw.com/Virgil.woff2\\=), and \"Segoe UI Emoji\" (used
for CJK/emoji text) with no @font-face at all, just assumed to be
installed. Non-browser SVG renderers — including the one Emacs uses
to display inline images — don't fetch remote fonts and are unlikely
to have \"Segoe UI Emoji\" installed either, so text falls back to a
generic font instead of matching what the Excalidraw editor shows.

Set this to the family name of a font you have installed locally
(check with `M-x list-faces-display' or the system font book/registry
— NOT the file name; e.g. a file named XiaolaiMono-Regular.ttf may
register its family as \"Xiaolai Mono\") to have
`chatu-excalidraw-script' rewrite all of `chatu-excalidraw-font-names'
in the exported SVG to it. Leave nil to use `excalidraw_export's
output unmodified."
  :group 'chatu-excalidraw
  :type '(choice (const :tag "Use excalidraw_export's fonts as-is" nil)
                 (string :tag "Local font family name")))

(defcustom chatu-excalidraw-export-bin-dir nil
  "Directory prepended to PATH when running `excalidraw_export'.

`excalidraw_export' depends on the native \"canvas\" npm module, whose
prebuilt binaries lag behind the newest Node.js releases; on a system
Node too new for the installed \"canvas\" version, it fails with an
ERR_DLOPEN_FAILED / NODE_MODULE_VERSION mismatch. If that happens,
install `excalidraw_export' under an older Node via nvm (e.g. `nvm
exec 22 npm install -g excalidraw_export'), then point this at that
Node's bin directory, e.g. \"~/.nvm/versions/node/vX.Y.Z/bin\" — its
shebang (`#!/usr/bin/env node') will then resolve to that Node
instead of whatever is first on your regular PATH. Leave nil to use
`excalidraw_export' as found on PATH unmodified."
  :group 'chatu-excalidraw
  :type '(choice (const :tag "Use PATH as-is" nil)
                 (directory :tag "Node bin directory")))

(defun chatu-excalidraw--find-executable ()
  "Find the browser executable on PATH, with macOS compatibility.
For macOS, tries to use the \"open\" command for handling URLs."
  (cond
   ((eq system-type 'darwin)
    (or (executable-find "open")
        (error "Cannot find 'open' command on macOS")))
   (t
    (condition-case nil
        (file-truename (or (executable-find "google-chrome")
                           (executable-find "chromium")
                           (executable-find "firefox")
                           (error "Cannot find a suitable browser executable")))
      (wrong-type-argument
       (message "Cannot find a suitable browser on the PATH."))))))

(defun chatu-excalidraw--ensure-baseline (input-path)
  "Add the legacy \"baseline\" field to text elements in INPUT-PATH.
Current Excalidraw (and AI-generated files) use the newer schema where
\"baseline\" was replaced by \"lineHeight\", but the renderer bundled
in `excalidraw_export' still computes text y-positions from
\"baseline\" — without it every line lands at y=\"NaN\", stacking all
lines of a label on top of each other in the exported SVG."
  (when (file-exists-p input-path)
    (let* ((json (with-temp-buffer
                   (insert-file-contents input-path)
                   (json-parse-buffer)))
           (elements (gethash "elements" json))
           (modified nil))
      (when elements
        (seq-doseq (elem elements)
          (when (and (equal (gethash "type" elem) "text")
                     (not (gethash "baseline" elem)))
            ;; ponytail: 0.36*fontSize descent approximation, matches
            ;; the baseline values old Excalidraw wrote closely enough
            ;; for hand-drawn style; refine per-font if it drifts.
            (puthash "baseline"
                     (round (- (gethash "height" elem)
                               (* 0.36 (gethash "fontSize" elem))))
                     elem)
            (setq modified t)))
        (when modified
          (let ((coding-system-for-write 'utf-8))
            (with-temp-file input-path
              (insert (json-serialize json)))))))))

(defun chatu-excalidraw-script (keyword-plist)
  "Get conversion script.
KEYWORD-PLIST contains parameters from the chatu line."
  (let* ((input-path
          (chatu-common-with-extension
           (plist-get keyword-plist :input-path) "excalidraw"))
         (_ (chatu-excalidraw--ensure-baseline input-path))
         (output-path (plist-get keyword-plist :output-path))
         (output-dir (file-name-directory output-path))
         ;; excalidraw_export names the generated SVG after the source file
         (generated-svg (concat input-path ".svg"))
         (move-command (if (string= generated-svg output-path)
                          "echo 'File already in place'"
                          (format "mv %s %s"
                                  (shell-quote-argument generated-svg)
                                  (shell-quote-argument output-path))))
         (path-prefix (if chatu-excalidraw-export-bin-dir
                          (format "PATH=%s:$PATH "
                                  (shell-quote-argument
                                   (expand-file-name chatu-excalidraw-export-bin-dir)))
                        ""))
         (font-command (if chatu-excalidraw-handwritten-font
                           (format " && sed -i.bak %s %s && rm -f %s.bak"
                                   (mapconcat
                                    (lambda (name)
                                      (format "-e %s"
                                              (shell-quote-argument
                                               (format "s|%s|%s|g" name
                                                       chatu-excalidraw-handwritten-font))))
                                    chatu-excalidraw-font-names " ")
                                   (shell-quote-argument output-path)
                                   (shell-quote-argument output-path))
                         "")))
    (format "mkdir -p %s && %sexcalidraw_export %s && %s%s"
            (shell-quote-argument output-dir)
            path-prefix
            (shell-quote-argument input-path)
            move-command
            font-command)))

(defcustom chatu-excalidraw-claude-program "claude"
  "Claude Code executable used by `chatu-excalidraw-open' for AI generation."
  :group 'chatu-excalidraw
  :type 'string)

(defcustom chatu-excalidraw-claude-args '("--permission-mode" "acceptEdits")
  "Extra arguments passed to `chatu-excalidraw-claude-program'.
The default allows Claude Code to write the generated .excalidraw
file without an interactive permission prompt, which would otherwise
hang the headless process."
  :group 'chatu-excalidraw
  :type '(repeat string))

(defconst chatu-excalidraw-empty
  "{\"type\":\"excalidraw\",\"version\":2,\"source\":\"https://excalidraw.com\",\"elements\":[],\"appState\":{\"gridSize\":null,\"viewBackgroundColor\":\"#ffffff\"}}"
  "Content of empty Excalidraw file.")

(defun chatu-excalidraw-open (keyword-plist)
  "Open .excalidraw file for editing.
KEYWORD-PLIST contains parameters from the chatu line.

On macOS, the file is opened directly via the \"open\" command, so
that if an Excalidraw PWA (e.g. `chatu-excalidraw-server-url'
installed as a Chrome app and set as the default handler for
.excalidraw files) is registered, it gets a real file handle and can
save changes straight back to this same path.

On other systems, no such file-handler mechanism exists, so the
diagram content is instead passed to `chatu-excalidraw-server-url' via
a URL, and edits must be exported/saved back manually.

When the .excalidraw file does not exist yet, prompt for an optional
AI description; if non-empty, generate the diagram asynchronously via
`chatu-excalidraw-claude-program' (using the excalidraw-diagram-generator
skill) before opening it. An empty description creates an empty
diagram, as before."
  (interactive)
  (let* ((input-path (plist-get keyword-plist :input-path))
         (input-path (file-truename (chatu-common-with-extension input-path "excalidraw"))))
    (if (file-exists-p input-path)
        (chatu-excalidraw--open-file input-path)
      (make-directory (file-name-directory input-path) t)
      (let ((prompt (string-trim
                     (read-string "AI diagram description (empty to draw yourself): "))))
        (if (string-empty-p prompt)
            (progn
              (with-temp-file input-path
                (insert chatu-excalidraw-empty))
              (chatu-excalidraw--open-file input-path))
          (chatu-excalidraw--generate input-path prompt))))))

(defun chatu-excalidraw--open-file (input-path)
  "Open existing INPUT-PATH in the Excalidraw PWA or browser."
  (if (eq system-type 'darwin)
      (start-process "excalidraw" nil "open" input-path)
    (let* ((browser-path (funcall chatu-excalidraw-executable-func))
           (url (concat chatu-excalidraw-server-url "?#json="
                        (url-hexify-string
                         (with-temp-buffer
                           (insert-file-contents input-path)
                           (buffer-string))))))
      (start-process "excalidraw" nil browser-path url))))

(defun chatu-excalidraw--generate (input-path prompt)
  "Generate INPUT-PATH from PROMPT via Claude Code, then open it.
Runs asynchronously; falls back to an empty diagram if generation
fails or produces something that is not an Excalidraw JSON file."
  (message "chatu-excalidraw: generating diagram with AI, will open when ready...")
  (let ((process
         (apply #'start-process "chatu-excalidraw-ai" nil
                chatu-excalidraw-claude-program
                "-p"
                (format (concat "使用 excalidraw-diagram-generator 技能，"
                                "根据以下描述生成 Excalidraw 图表，"
                                "并将结果保存到文件 %s ：%s")
                        input-path prompt)
                chatu-excalidraw-claude-args)))
    (set-process-sentinel
     process
     (lambda (_process event)
       (unless (and (string-match-p "finished" event)
                    (file-exists-p input-path)
                    (with-temp-buffer
                      (insert-file-contents input-path)
                      (string-prefix-p "{" (string-trim (buffer-string)))))
         (message "chatu-excalidraw: AI generation failed (%s), opening empty diagram"
                  (string-trim event))
         (with-temp-file input-path
           (insert chatu-excalidraw-empty)))
       (chatu-excalidraw--open-file input-path)))))

(defun chatu-excalidraw-save-from-url (url output-path)
  "Save Excalidraw content from URL to OUTPUT-PATH."
  (let ((json-data (url-unhex-string (substring url (string-match "json=\\(.+\\)" url) 5))))
    (with-temp-file output-path
      (insert json-data))))

(defun chatu-excalidraw-get-width (line)
  "Get :width value from chatu LINE, as inserted by `chatu-excalidraw-new'."
  (when (string-match ":width +\\([0-9]+\\)" line)
    (list :width (substring-no-properties (match-string 1 line)))))

;;;###autoload
(add-to-list 'chatu-keyword-value-functions #'chatu-excalidraw-get-width t)

(defun chatu-excalidraw--new-input-name (type)
  "Generate an input file name: \"chatu_<timestamp>\" with TYPE's extension.
When `chatu-input-dir' is set (possibly buffer-locally), prepend it,
so the chatu line spells out the full relative path instead of
relying on the implicit directory; chatu ignores `chatu-input-dir'
for input names that already contain a directory, so both forms
resolve identically."
  (concat (when chatu-input-dir (file-name-as-directory chatu-input-dir))
          (format-time-string "chatu_%Y%m%d_%H%M%S")
          "." (if (string= type "plantuml") "puml" type)))

;;;###autoload
(defun chatu-excalidraw-new ()
  "Insert a chatu text line, picking the diagram type via `completing-read'.
Also prompts for a display width, stored as :width on the line and
used by `chatu-excalidraw-add' to size the rendered image. The input
file name is generated automatically as \"chatu_<timestamp>\" rather
than prompted for."
  (interactive)
  (let* ((selected-type (completing-read "Select type: "
                                          chatu-excalidraw-new-type-options
                                          nil t nil nil
                                          chatu-excalidraw-new-default-type))
         (prefix (cond ((derived-mode-p 'markdown-mode)
                        "<!-- #+chatu: :")
                       ((derived-mode-p 'org-mode)
                        "#+chatu: :")))
         (suffix (if (derived-mode-p 'markdown-mode)
                     " -->"
                   "\n#+RESULTS:"))
         (input-name (chatu-excalidraw--new-input-name selected-type))
         (width (read-number "Image width: " chatu-excalidraw-new-default-width)))
    (insert prefix selected-type " \"" input-name "\" :width "
            (number-to-string width) suffix)
    (when (derived-mode-p 'org-mode)
      (forward-line -1))))

;;;###autoload
(advice-add 'chatu-new :override #'chatu-excalidraw-new)

(defun chatu-excalidraw--results-line-p (line)
  "Non-nil if LINE looks like an org #+RESULTS: marker."
  (string-prefix-p "#+results:" (downcase line)))

(defun chatu-excalidraw--owned-line-p (line)
  "Non-nil if LINE is one `chatu-excalidraw-add' regenerates on every render.
This excludes the #+RESULTS: marker itself, which is preserved rather
than regenerated — see `chatu-excalidraw--results-line-p'."
  (or (string-prefix-p "#+CAPTION:" line)
      (string-prefix-p "#+ATTR_ORG:" line)
      (string-prefix-p "#+ATTR_LATEX:" line)
      (string-prefix-p "#+ATTR_HTML:" line)
      (string-prefix-p (chatu-img-pre) line)))

;;;###autoload
(defun chatu-excalidraw-add ()
  "Like `chatu-add', but also insert #+ATTR_* width lines in `org-mode'.
Uses the chatu line's :width, as set via `chatu-excalidraw-new'."
  (interactive)
  (save-excursion
    (let* ((keyword-plist (chatu-keyword-plist))
           (width (plist-get keyword-plist :width))
           (type (downcase (plist-get keyword-plist :type)))
           (script (progn
                     (require (intern (concat "chatu-" type)))
                     (funcall (intern (concat "chatu-" type "-script"))
                              keyword-plist)))
           (script (string-replace "\\~" "~" script))
           (result (plist-get keyword-plist :output-path))
           (result-dir (file-name-directory result))
           (space-count (string-search
                         (cond ((derived-mode-p 'markdown-mode) "<")
                               ((derived-mode-p 'org-mode) "#"))
                         (buffer-substring (line-beginning-position)
                                            (line-end-position)))))
      (when (not (file-exists-p result-dir))
        (make-directory result-dir t))
      (forward-line)
      ;; Preserve (or insert, for lines written before this existed)
      ;; the #+RESULTS: marker, org-babel style, ahead of the actual
      ;; output; only the content below it gets regenerated.
      (when (derived-mode-p 'org-mode)
        (if (chatu-excalidraw--results-line-p
             (string-trim (buffer-substring (line-beginning-position)
                                             (line-end-position))))
            (forward-line)
          (insert "#+RESULTS:\n")))
      ;; Regenerate everything else this command owns from scratch:
      ;; any previously-inserted #+ATTR_* block, and any
      ;; previously-inserted image link.
      (while (and (not (eobp))
                  (chatu-excalidraw--owned-line-p
                   (string-trim (buffer-substring (line-beginning-position)
                                                   (line-end-position)))))
        ;; `kill-whole-line' with arg 0 leaves the newline (and an
        ;; empty residual line) behind, which would stop this loop
        ;; after one iteration; delete the line and its newline
        ;; outright so consecutive owned lines are all consumed.
        (delete-region (line-beginning-position)
                        (progn (forward-line 1) (point))))
      (let ((process (start-process-shell-command "chatu-buffer" nil script)))
        (set-process-sentinel
         process (lambda (_process _event) (chatu-refresh-image))))
      (beginning-of-line)
      (open-line 1)
      (let ((indent (make-string space-count ?\s)))
        (when (and width (derived-mode-p 'org-mode))
          (insert indent "#+CAPTION:\n"
                  indent (format "#+ATTR_ORG: :width %s\n" width)
                  indent (format "#+ATTR_LATEX: :width %s :float nil\n"
                                 chatu-excalidraw-attr-latex-width)
                  indent (format "#+ATTR_HTML: :width %s :class zoomImage :border 1\n" width)))
        (insert indent)
        (chatu-insert-image result)))))

;;;###autoload
(advice-add 'chatu-add :override #'chatu-excalidraw-add)

(provide 'chatu-excalidraw)

;;; chatu-excalidraw.el ends here

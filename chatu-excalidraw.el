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

(defun chatu-excalidraw-script (keyword-plist)
  "Get conversion script.
KEYWORD-PLIST contains parameters from the chatu line."
  (let* ((input-path
          (chatu-common-with-extension
           (plist-get keyword-plist :input-path) "excalidraw"))
         (output-path (plist-get keyword-plist :output-path))
         (output-dir (file-name-directory output-path))
         ;; excalidraw_export names the generated SVG after the source file
         (generated-svg (concat input-path ".svg"))
         (move-command (if (string= generated-svg output-path)
                          "echo 'File already in place'"
                          (format "mv %s %s"
                                  (shell-quote-argument generated-svg)
                                  (shell-quote-argument output-path)))))
    (format "mkdir -p %s && excalidraw_export %s && %s"
            (shell-quote-argument output-dir)
            (shell-quote-argument input-path)
            move-command)))

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
a URL, and edits must be exported/saved back manually."
  (interactive)
  (let* ((input-path (plist-get keyword-plist :input-path))
         (input-path (file-truename (chatu-common-with-extension input-path "excalidraw")))
         (file-exists (file-exists-p input-path)))
    (unless file-exists
      (with-temp-file input-path
        (insert chatu-excalidraw-empty)))
    (if (eq system-type 'darwin)
        (start-process "excalidraw" nil "open" input-path)
      (let* ((browser-path (funcall chatu-excalidraw-executable-func))
             (url (concat chatu-excalidraw-server-url "?#json="
                         (url-hexify-string
                          (with-temp-buffer
                            (insert-file-contents input-path)
                            (buffer-string))))))
        (start-process "excalidraw" nil browser-path url)))))

(defun chatu-excalidraw-save-from-url (url output-path)
  "Save Excalidraw content from URL to OUTPUT-PATH."
  (let ((json-data (url-unhex-string (substring url (string-match "json=\\(.+\\)" url) 5))))
    (with-temp-file output-path
      (insert json-data))))

;;;###autoload
(defun chatu-excalidraw-new ()
  "Insert a chatu text line, picking the diagram type via `completing-read'."
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
                   "\n#+results:"))
         (input-name (read-string "Input name: " "")))
    (insert prefix selected-type " \"" input-name "\"" suffix)
    (when (derived-mode-p 'org-mode)
      (forward-line -1))))

;;;###autoload
(advice-add 'chatu-new :override #'chatu-excalidraw-new)

(provide 'chatu-excalidraw)

;;; chatu-excalidraw.el ends here

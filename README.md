# chatu-excalidraw

An [Excalidraw](https://excalidraw.com/) backend for
[chatu](https://github.com/kimim/chatu), the Emacs package that lets
you author diagrams alongside `org-mode` / `markdown-mode` text and
render them to inline SVG images.

`chatu` dispatches diagram types to `chatu-<type>-script` /
`chatu-<type>-open` functions provided by separate packages; this
package supplies the `excalidraw` type.

It also replaces `chatu-new` with a `completing-read`-based version,
so you pick the diagram type from a list instead of typing it.

## Requirements

- [chatu](https://github.com/kimim/chatu)
- [`excalidraw_export`](https://www.npmjs.com/package/excalidraw_export)
  (npm) — used by `chatu-add` to render `.excalidraw` files to SVG.
- A way to edit `.excalidraw` files, used by `chatu-open`:
  - macOS: an app registered as the default handler for `.excalidraw`
    files (see [macOS setup](#macos-setup-round-trip-saving) below for
    the round-trip-saving reason this matters).
  - Other systems: a browser on `PATH` (`google-chrome`, `chromium`,
    or `firefox`), pointed at an Excalidraw instance — either
    `https://excalidraw.com/` (default) or your own self-hosted
    deployment.

## Installation

With `use-package` + `straight.el`:

```elisp
(use-package chatu
  :custom ((chatu-input-dir "./draws")
           (chatu-output-dir "./images"))
  :hook ((org-mode markdown-mode) . chatu-mode))

(use-package chatu-excalidraw
  :straight (chatu-excalidraw :type git :host github :repo "your-user/chatu-excalidraw")
  :after chatu)
```

Or manually, if the file is on your `load-path`:

```elisp
(require 'chatu-excalidraw)
```

## Customization

| Variable | Default | Purpose |
|---|---|---|
| `chatu-excalidraw-server-url` | `"https://excalidraw.com/"` | Excalidraw instance used when opening diagrams **on non-macOS systems only** (see below). Point it at a self-hosted instance if you run one. |
| `chatu-excalidraw-executable-func` | `chatu-excalidraw--find-executable` | Function used to locate a browser executable on non-macOS systems. |
| `chatu-excalidraw-new-type-options` | `("drawio" "plantuml" "excalidraw")` | Candidates offered by `chatu-excalidraw-new`'s type prompt. |
| `chatu-excalidraw-new-default-type` | `"drawio"` | Type preselected in that prompt. |

Example — pointing at a self-hosted Excalidraw server:

```elisp
(setq chatu-excalidraw-server-url "https://your-excalidraw-host.example.com")
```

## Usage

Enable `chatu-mode` in the buffer (via the `:hook` above, or
`M-x chatu-mode`). It binds `C-c C-c` to render a diagram and `C-c
C-o` to open one for editing.

**1. Insert a chatu line — `M-x chatu-new`**

This package overrides `chatu-new` with `chatu-excalidraw-new`:
it prompts for a type (`completing-read` over
`chatu-excalidraw-new-type-options`, defaulting to
`chatu-excalidraw-new-default-type`), then for an input file name.
Choosing `excalidraw` with name `arch` inserts, in `org-mode`:

```org
#+chatu: :excalidraw "arch"
#+results:
```

(in `markdown-mode`, a single HTML comment line instead).

**2. Edit the diagram — cursor on the chatu line, `C-c C-o`**

Runs `chatu-excalidraw-open`. If `./draws/arch.excalidraw` (per
`chatu-input-dir`) doesn't exist yet, it's created with an empty
Excalidraw document, then opened:

- **macOS**: via `open` on the local file path directly. Whichever
  app is registered as the default handler for `.excalidraw` receives
  the real file and can save back to it. See
  [macOS setup](#macos-setup-round-trip-saving).
- **Other systems**: no such file-handler mechanism exists, so the
  content is instead passed to `chatu-excalidraw-server-url` as a URL
  (`?#json=...`) and opened in a browser. There is no live file
  handle in this case — the page can't save back to the original
  path, so exported/downloaded edits must be moved into place by
  hand.

**3. Render and insert the image — `C-c C-c`**

Runs `chatu-excalidraw-script`, which shells out to
`excalidraw_export` to produce an SVG under `chatu-output-dir`, then
inserts (or replaces) an image link below the chatu line and
refreshes inline image display. Re-run `C-c C-c` any time after
editing the diagram to update the rendered image.

## macOS setup: round-trip saving

Browsers can only save silently back to a specific local file if
they were handed a real file handle for it (via Chrome's File System
Access API). Opening a page by URL — even with the diagram's JSON
embedded in the hash — does **not** provide such a handle, so pressing
Cmd-S there falls back to a plain download into `~/Downloads/`.

To get proper round-trip saving into your `chatu`-managed path (e.g.
`./draws/arch.excalidraw`), install your Excalidraw instance as a
Chrome PWA and register it as the default handler for `.excalidraw`
files:

1. In Chrome, visit your Excalidraw instance (`https://excalidraw.com/`
   or your self-hosted URL).
2. Install it as an app (address bar install icon, or the Chrome menu
   → *Cast, Save, and Share* → *Install \<name\>...*).
3. In Finder, select any `.excalidraw` file → `Cmd-I` (Get Info) →
   *Open with* → choose the installed app → *Change All...*.

Once this is set up, `chatu-excalidraw-open` opens the local file
directly, the installed app gets a real file handle, and Cmd-S in the
editor writes straight back to that same path —
`chatu-excalidraw-server-url` is not consulted on macOS at all.

## License

GPL-3.0-or-later, matching `chatu`.

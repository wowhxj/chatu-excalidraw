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
  - macOS: the built-in `open` command (works out of the box if you
    have an app associated with `.excalidraw`, e.g. the Excalidraw
    desktop app or a browser PWA).
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
| `chatu-excalidraw-server-url` | `"https://excalidraw.com/"` | Excalidraw instance used when opening diagrams on non-macOS systems. Point it at a self-hosted instance if you run one. |
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
Excalidraw document, then opened — via `open` on macOS, or a browser
URL (`chatu-excalidraw-server-url` + the file's JSON) elsewhere. Draw,
save, close.

**3. Render and insert the image — `C-c C-c`**

Runs `chatu-excalidraw-script`, which shells out to
`excalidraw_export` to produce an SVG under `chatu-output-dir`, then
inserts (or replaces) an image link below the chatu line and
refreshes inline image display. Re-run `C-c C-c` any time after
editing the diagram to update the rendered image.

## License

GPL-3.0-or-later, matching `chatu`.

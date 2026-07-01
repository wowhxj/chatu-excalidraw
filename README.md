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
  (npm) — used by `chatu-add` to render `.excalidraw` files to SVG. If
  it fails with `ERR_DLOPEN_FAILED` / a `NODE_MODULE_VERSION`
  mismatch, see [Node/canvas version issues](#nodecanvas-version-issues)
  below.
- A way to edit `.excalidraw` files, used by `chatu-open`:
  - macOS: an app registered as the default handler for `.excalidraw`
    files (see [macOS setup](#macos-setup-round-trip-saving) below for
    the round-trip-saving reason this matters).
  - Other systems: a browser on `PATH` (`google-chrome`, `chromium`,
    or `firefox`), pointed at an Excalidraw instance — either
    `https://excalidraw.com/` (default) or your own self-hosted
    deployment.

## Installation

With `use-package` and Emacs 29+'s built-in `package-vc.el` (via the
`:vc` keyword):

```elisp
(use-package chatu
  :custom ((chatu-input-dir "./draws")
           (chatu-output-dir "./images"))
  :hook ((org-mode markdown-mode) . chatu-mode))

(use-package chatu-excalidraw
  :vc (:url "https://github.com/wowhxj/chatu-excalidraw" :rev newest)
  :after chatu
  :config
  ;; Only needed if you self-host Excalidraw instead of using
  ;; https://excalidraw.com/ — see chatu-excalidraw-server-url below.
  (setq chatu-excalidraw-server-url "https://your-excalidraw-host.example.com")
  ;; Only needed if excalidraw_export needs pinning to a specific Node
  ;; version — see "Node/canvas version issues" below.
  (setq chatu-excalidraw-export-bin-dir "~/.nvm/versions/node/vX.Y.Z/bin")
  ;; Only needed to fix font rendering — see "Font rendering" below.
  (setq chatu-excalidraw-handwritten-font "Xiaolai Mono"))
```

To upgrade later: `M-x package-vc-upgrade RET chatu-excalidraw RET`.

With `straight.el` instead:

```elisp
(use-package chatu-excalidraw
  :straight (chatu-excalidraw :type git :host github :repo "wowhxj/chatu-excalidraw")
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
| `chatu-excalidraw-export-bin-dir` | `nil` | Directory prepended to `PATH` when running `excalidraw_export`. Set this if you had to install `excalidraw_export` under a specific Node version — see [Node/canvas version issues](#nodecanvas-version-issues). |
| `chatu-excalidraw-handwritten-font` | `nil` | Local font family substituted into the exported SVG in place of `excalidraw_export`'s built-in fonts. See [Font rendering](#font-rendering). |
| `chatu-excalidraw-new-default-width` | `800` | Default image width (px) offered by `chatu-excalidraw-new`'s width prompt. |
| `chatu-excalidraw-attr-latex-width` | `"0.5\\linewidth"` | Width used in the `#+ATTR_LATEX` line `chatu-excalidraw-add` inserts (LaTeX widths are conventionally a fraction of `\linewidth`, not pixels). |

See the `:config` block in [Installation](#installation) above for a
full example combining several of these.

## Usage

Enable `chatu-mode` in the buffer (via the `:hook` above, or
`M-x chatu-mode`). It binds `C-c C-c` to render a diagram and `C-c
C-o` to open one for editing.

**1. Insert a chatu line — `M-x chatu-new`**

This package overrides `chatu-new` with `chatu-excalidraw-new`:
it prompts for a type (`completing-read` over
`chatu-excalidraw-new-type-options`, defaulting to
`chatu-excalidraw-new-default-type`) and a display width (defaulting
to `chatu-excalidraw-new-default-width`) — there is no file name
prompt; the input file is named `chatu_<timestamp>` automatically
(e.g. `chatu_20260701_022806.excalidraw`), one less thing to type.
Choosing `excalidraw`, width `400` inserts, in `org-mode`:

```org
#+chatu: :excalidraw "chatu_20260701_022806" :width 400
#+RESULTS:
```

(in `markdown-mode`, a single HTML comment line instead, with no
`#+RESULTS:` — that marker is an org-mode convention). The `:width`
value is consumed by `chatu-excalidraw-add` in step 3 below; it has no
effect otherwise, so it's harmless to edit or remove by hand.

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

This package also overrides `chatu-add` with `chatu-excalidraw-add`.
It runs `chatu-excalidraw-script`, which shells out to
`excalidraw_export` to produce an SVG under `chatu-output-dir`, then
(re)inserts an image link below the chatu line and refreshes inline
image display — same as stock `chatu-add`. In `org-mode`, it also
keeps the `#+RESULTS:` marker (inserting one if missing, e.g. for
chatu lines written before this existed) directly below the chatu
line, and, if the line has a `:width` (as inserted by
`chatu-excalidraw-new`), (re)inserts a
`#+CAPTION:`/`#+ATTR_ORG:`/`#+ATTR_LATEX:`/`#+ATTR_HTML:` block below
that, ahead of the image link, e.g.:

```org
#+chatu: :excalidraw "chatu_20260701_022806" :width 400
#+RESULTS:
#+CAPTION:
#+ATTR_ORG: :width 400
#+ATTR_LATEX: :width 0.5\linewidth :float nil
#+ATTR_HTML: :width 400 :class zoomImage :border 1
[[file:./draws/chatu_20260701_022806.svg]]
```

Re-run `C-c C-c` any time after editing the diagram; it fully
regenerates everything below `#+RESULTS:` (any previous `#+ATTR_*`
block and the image link) rather than appending, so repeated renders
don't accumulate stale content. `#+RESULTS:` itself is left alone once
present.

Note: the export runs asynchronously, and the image link is inserted
immediately regardless of whether it succeeds — if the rendered image
looks broken, check whether the output `.svg` file actually exists
before assuming the Lisp side is at fault (see
[Node/canvas version issues](#nodecanvas-version-issues) for a common
cause).

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

## Node/canvas version issues

`excalidraw_export` depends on the native `canvas` npm module, which
ships prebuilt binaries pinned to specific Node ABI versions. If your
system Node is newer than what `canvas` has a prebuilt binary for,
`chatu-excalidraw-add` silently fails (it runs the export
asynchronously and inserts the image link regardless of success —
check for a missing output file if the rendered image looks broken)
with something like:

```
Error: The module '.../canvas/build/Release/canvas.node'
was compiled against a different Node.js version using
NODE_MODULE_VERSION 131. This version of Node.js requires
NODE_MODULE_VERSION 147.
```

`npm rebuild canvas` does **not** fix this if your Node is new enough
that `canvas`'s C++ source itself has stopped compiling against the
current V8 headers (e.g. `no member named 'GetIsolate' in
'v8::Context'`) — that means the installed `canvas` major version
doesn't support your Node at all, prebuilt or from source.

The fix is to install `excalidraw_export` under an older Node version
via [nvm](https://github.com/nvm-sh/nvm), and point
`chatu-excalidraw-export-bin-dir` at it:

```bash
nvm install 22
nvm exec 22 npm install -g excalidraw_export
```

```elisp
(setq chatu-excalidraw-export-bin-dir "~/.nvm/versions/node/vX.Y.Z/bin")
```

`excalidraw_export`'s shebang is `#!/usr/bin/env node`, so prepending
that directory to `PATH` for the export command (which is what this
variable does) makes it resolve to the matching Node instead of
whatever else is first on your regular `PATH`.

## Font rendering

The SVG `excalidraw_export` produces hardcodes three font-family
names (`chatu-excalidraw-font-names`):

- `"Virgil"` — hand-drawn Latin text — declared via `@font-face {
  src: url("https://excalidraw.com/Virgil.woff2") }`, a **remote**
  font URL.
- `"Cascadia"` — code text — same remote-URL pattern.
- `"Segoe UI Emoji"` — used for CJK/emoji text — referenced directly
  with no `@font-face` at all, just assumed to already be installed.

Browsers fetch the remote fonts fine and likely have Segoe UI Emoji
available too; the renderer Emacs uses for inline SVGs (librsvg, via
`image-mode`/`org-redisplay-inline-images`) does neither, so text
silently falls back to a generic font — for *any* script, not just
Latin — instead of matching what you see in the PWA editor.

Set `chatu-excalidraw-handwritten-font` to the family name of a font
you have installed locally, and `chatu-excalidraw-script` will rewrite
all three of the above to it in the exported SVG (a `sed`
post-processing step). Use the font's registered **family** name, not
its file name — e.g. a file named `XiaolaiMono-Regular.ttf` may
register its family as `"Xiaolai Mono"`; check with `fc-list` or
Font Book:

```elisp
(setq chatu-excalidraw-handwritten-font "Xiaolai Mono")
```

This only has a visible effect if the font is actually installed
locally under that exact family name; if not, `librsvg` just falls
back to a generic font again, same as before.

## License

GPL-3.0-or-later, matching `chatu`.

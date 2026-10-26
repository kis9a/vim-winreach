# winreach

Reach every window without going there.

`:tabdo windo` has to visit each tab page and window: the walk moves the
cursor, changes the current tab page, discards the previous-window and
alternate-buffer marks, and fires window and buffer autocommands at every
stop. `winreach` reaches windows in other tab pages through `win_execute()`
instead, so the traversal itself has no side effects. Only the command being
applied does what it does.

```vim
:Winlist                    " every window in every tab page
:Winpeek build.log          " what a window elsewhere is showing right now
:Winmap setlocal nonumber   " apply to every window, without moving
:Winheight 30%              " resize without crushing one neighbour
:Winundo                    " put back the layout :only just destroyed
```

## Commands

### `:Winlist`

Every window in every tab page, read without going to any of them:

```
tab 1
    1001   40x22  autoload/winref.vim
    1000   39x22  test/winref.vim
tab 2
    1003  100x13  [Scratch]             [nofile fixh]
  > 1002   100x2  README.md
    1005  100x10  [quickfix]            [fixh]
tab 3
    1004  100x28  Makefile              [+]
```

`>` marks the window you are in.

| Key | |
| --- | --- |
| `<CR>` | jump to the window under the cursor |
| `p` | peek at it (see `:Winpeek`) |
| `q` `<Esc>` | close the list |

The listing is a snapshot of the moment it was asked for. Running `:Winlist`
again from inside the list refreshes it in place. Building it moves nothing
and fires no autocommand; the list window is opened afterwards and is not
part of its own listing.

### `:Winpeek`

```vim
:Winpeek                  " the only other window, or the row under the cursor in :Winlist
:Winpeek build.log        " part of a buffer name
:Winpeek 1003             " a window id
```

Draws what another window is showing *right now*, where you are:

```
win 1003  tab 2  build.log  482-503/503
------------------------------------------
 482 ok  15 passed
 483 ok  16 passed
>484 FAIL 17 expected 3, got 4
 485
```

Buffer line numbers down the left, `>` on the line that window's cursor is
on. The peek is a popup on Vim and a floating window on Neovim, so nothing
is split or resized, and `:Winlist` stays open underneath if that is where
you came from. The keys scroll the *peeked* window from where you are:

| Key | |
| --- | --- |
| `j` `k` `<C-e>` `<C-y>` | line at a time |
| `<C-d>` `<C-u>` `<C-f>` `<C-b>` | half a screen, a screen |
| `g` `G` | top, bottom |
| `r` | read it again |
| `<CR>` | go there |
| `q` `<Esc>` | close the peek |

With `'wrap'` or closed folds the peek may show a few more lines than the
window itself does.

### `:Winsave` / `:Winrestore`

```vim
:Winsave    [name]
:Winrestore [name]
```

Save the current tab page's layout and put it back later. The layout tree,
the buffer in each window, window sizes and each window's view are restored.
Saved layouts live for the session, keyed by name (`default` when none is
given). `:Winrestore <Tab>` completes the names.

`:Winrestore` is a replacement, not a merge. It runs `:only` first, so
windows opened since the save are closed. An ordinary buffer modified in one
of them keeps its changes and is hidden rather than unloaded (`'hidden'` is
restored afterwards); a buffer whose `'bufhidden'` is `unload`, `delete` or
`wipe` is the exception. If the screen has been resized since the save, the
shape comes back but the sizes are not replayed, and it says so.

### `:Winundo`

```vim
:Winundo
```

Put back the layout this tab page had just before a window was closed.
`WinClosed` fires while the window being closed is still there, so the layout
is remembered without asking. A burst of closes from one `:only` is recorded
as a single entry. Asking again reaches further back; the entry used is
consumed.

Set `g:winreach_remember = 0` before the plugin loads to keep `winreach` out
of autocommands entirely. Lazy-loading the plugin on its commands also
disables this, since the autocommand lives in `plugin/`. Loading it eagerly
costs well under a millisecond and leaves `autoload/` untouched until a
command runs.

### `:Winheight` / `:Winwidth`

```vim
:Winheight 10     :Winwidth 40
:Winheight 30%    :Winwidth 50%
:Winheight +4     :Winwidth -8
```

`:resize` takes what it needs from whichever window happens to be adjacent.
These take it from every window sharing that axis, in proportion to what
each had:

```
        :resize 10          :Winheight 10
[4,6,10] -> [10, 1, 9]      [4,6,10] -> [10, 4, 6]
```

The layout is remembered before the change, so `:Winundo` takes it back.

### `:Winmap`

| Command | Behaviour |
| --- | --- |
| `:Winmap {cmd}` | Apply `{cmd}` to every window in every tab page. Stop at the first window where it fails, and report which one. |
| `:Winmap! {cmd}` | Visit the remaining windows anyway, and report a summary of the failures at the end. |

The current tab page, current window, `<C-w>p` and the alternate buffer are
unchanged by the walk, and the walk fires no `WinEnter`/`WinLeave`/
`BufEnter`/`BufLeave`/`TabEnter`/`TabLeave`. `CTRL-C` stops the walk in both
forms.

Popups (Vim) and floating windows (Neovim) are never visited. The window list
is snapshotted before the walk: windows opened by `{cmd}` are not swept, and
a window that is gone by its turn is skipped.

Things the walk cannot protect you from:

- **`{cmd}` still has its own effects.** `:Winmap edit foo` enters buffers
  and fires `BufEnter` for that reason.
- **`:close` in the last window of another tab page closes that tab page**,
  silently. `:tabdo windo close` would have raised `E444` there. This is how
  `win_execute()` behaves; think twice before `:Winmap` with a command that
  closes windows.
- **A command that splits or changes the buffer in another tab page** still
  clears the current tab page's `<C-w>p`, because that is what the split
  does. The alternate buffer and the jumplist are not affected.
- **An abort is not a rollback.** Whatever ran before the failing window has
  already happened.

## Function

```vim
let result = winreach#map({cmd} [, {opts}])
```

`opts.keep_going` (default `v:false`) is what the bang sets.

| Result key | |
| --- | --- |
| `visited` | Windows the command actually ran in |
| `skipped` | Windows that were gone by their turn, or that the command could not be run in |
| `remaining` | Windows an early stop never reached. `0` after a complete walk |
| `failed` | `[{'winid', 'tabnr', 'error', 'throwpoint'}]` |

`visited + skipped + len(failed) + remaining` equals the number of windows
that were there when the walk started. `tabnr` is resolved when the failure
is recorded, so it names the right tab page even after `{cmd}` has added or
removed one.

## Examples

```vim
" Settings that should hold everywhere, without losing your place
:Winmap setlocal nonumber norelativenumber

" Dim every window you are not in
:Winmap setlocal winhighlight=Normal:NormalNC

" Look, don't touch
:Winmap echo win_getid() bufname()

" Best effort across a layout where some windows will refuse
:Winmap! setlocal spell

" Only some windows: the command decides
:Winmap if &filetype ==# 'markdown' | setlocal spell | endif
```

## Requirements

Vim 8.1+ (`win_execute()`) or Neovim. There is no version gate: `winreach`
checks for the builtins it needs and reports rather than failing halfway.
`:Winpeek` additionally needs popup windows (Vim 8.2+) or `nvim_open_win()`.

`autoload/winreach/winref.vim` is vendored from
[kis9a/vim-winref](https://github.com/kis9a/vim-winref) under this plugin's
own namespace. Do not edit it here; regenerate it with `make vendor` in the
`vim-winref` checkout.

## Development

```sh
make init        # clone pinned vim-themis / vim-vimlint / vim-vimlparser
make test        # themis, Vim
make test-nvim   # themis, Neovim
make lint        # vimlint
```

## LICENSE

MIT. See [LICENSE](LICENSE).

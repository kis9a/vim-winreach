" winreach#winref - VENDORED from kis9a/vim-winref; do not edit here.
" Regenerate with 'make vendor' in the vim-winref checkout.
" winref-vendor: src=e5e0ba453d384294756536a2ffbd6bcf78631c86b9175164224a4376912b92a1 body=29fd7b89b6a624374e2d78cf94dabcb377fabbf7dd5f75e9560f2c1b10db0511
"
" win_id2win(), bufwinid(), getwinvar() and setwinvar() all resolve only
" windows of the *current* tab page, which makes existence checks silently
" false-negative and option writes silently no-op once the user switches
" tabs.  getwininfo() and win_execute() span tab pages; every query and every
" cross-window access here is built on those two.  winrestcmd() is used by
" without_equalize() alone, and Neovim additionally needs
" nvim_win_get_config() to recognise floating windows.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:seq = 0

" eval()'s temporary lives in the global namespace, but every vendored copy
" of this file has its own s:seq -- two copies would both reach for
" g:Winref_tmp_1 and the inner call would clobber and then unlet the outer
" one's value.  The directory this script sits in is the vendoring
" namespace, so it makes the key copy-unique.
let s:uniq = substitute(
      \ expand('<sfile>:p:h:t') . '_' . expand('<sfile>:p:t:r'),
      \ '[^A-Za-z0-9_]', '_', 'g')

" ---------------------------------------------------------------------------
" Capability
" ---------------------------------------------------------------------------

" Builtins each feature needs.  Versions are deliberately not checked: the
" plan verified behaviour on Vim 9.2 and Neovim 0.12.4 only, so a version
" number would be a guess.  'core' additionally needs a way to recognise
" floating windows on Neovim -- excluding them is part of the contract, not
" an optional extra.
let s:required = {
      \ 'core':             ['getwininfo'],
      \ 'execute':          ['getwininfo', 'win_execute'],
      \ 'eval':             ['getwininfo', 'win_execute'],
      \ 'try_close':        ['getwininfo', 'win_execute'],
      \ 'without_equalize': ['winrestcmd'],
      \ }

" g:winreach#winref#test_missing lets the test suite pretend a builtin is absent;
" a builtin cannot actually be removed at runtime.
function! s:has_fn(name) abort
  if index(get(g:, 'winreach#winref#test_missing', []), a:name) >= 0
    return 0
  endif
  return exists('*' . a:name)
endfunction

function! s:has(feature) abort
  if !has_key(s:required, a:feature)
    return 0
  endif
  for l:fn in s:required[a:feature]
    if !s:has_fn(l:fn)
      return 0
    endif
  endfor
  if a:feature !=# 'without_equalize' && has('nvim')
        \ && !s:has_fn('nvim_win_get_config')
    return 0
  endif
  return 1
endfunction

" available()          -> can the identity core be used?
" available('execute') -> can that feature be used?
function! winreach#winref#available(...) abort
  return s:has(a:0 > 0 ? a:1 : 'core') ? v:true : v:false
endfunction

" ---------------------------------------------------------------------------
" Internal
" ---------------------------------------------------------------------------

" A popup (Vim) or floating window (Neovim) is outside the managed domain.
"
" Vim: getwininfo() with no argument never lists popups, but getwininfo(id)
" does -- such an entry carries winnr 0.
" Neovim: floats *are* listed, and are recognised by a non-empty 'relative'.
"
" Never write win_gettype(win_id2win(id)): win_id2win() returns 0 for popups
" and for windows of other tab pages, so that reports the type of the
" *current* window instead.
function! s:is_unmanaged(info) abort
  if has('nvim')
    return get(nvim_win_get_config(a:info.winid), 'relative', '') !=# ''
  endif
  return get(a:info, 'winnr', 0) <= 0
endfunction

function! s:normalize(info) abort
  return {
        \ 'winid':  a:info.winid,
        \ 'tabnr':  a:info.tabnr,
        \ 'bufnr':  a:info.bufnr,
        \ 'width':  a:info.width,
        \ 'height': a:info.height,
        \ }
endfunction

" ---------------------------------------------------------------------------
" Query
" ---------------------------------------------------------------------------

" Info Dict for winid, or {} when it does not exist or is a popup/float.
" Spans tab pages, unlike win_id2win() and bufwinid().
function! winreach#winref#get(winid) abort
  if !s:has('core') || type(a:winid) != type(0) || a:winid <= 0
    return {}
  endif
  let l:infos = getwininfo(a:winid)
  if empty(l:infos) || s:is_unmanaged(l:infos[0])
    return {}
  endif
  return s:normalize(l:infos[0])
endfunction

" Is this a spec key with a value of the type that key accepts?
" 'winid' and 'bufnr' take a Number; 'tabnr' takes a Number or 'current'.
" A wrong-typed value must be rejected here rather than compared below:
" Vim refuses to compare a Number with a List or a Dict (E691 / E735), so
" find({'winid': []}) would raise out of a function documented to always
" return a List.
function! s:spec_pair_ok(key, val) abort
  if a:key ==# 'winid' || a:key ==# 'bufnr'
    return type(a:val) == type(0)
  endif
  if a:key ==# 'tabnr'
    return type(a:val) == type(0)
          \ || (type(a:val) == type('') && a:val ==# 'current')
  endif
  return 0
endfunction

" List (possibly empty) of info Dicts matching spec.
" spec keys: 'winid', 'bufnr', 'tabnr' ('current' allowed).  An empty spec
" deliberately matches every managed window in every tab page.
"
" Anything else -- a non-Dict, a key that is not one of the three, or a
" value of the wrong type -- returns [] rather than falling back to "match
" everything": a caller that mistypes 'bufnr' must not be handed an
" arbitrary window that it then treats as the one it asked for.
function! winreach#winref#find(spec) abort
  if !s:has('core') || type(a:spec) != type({})
    return []
  endif
  for l:key in keys(a:spec)
    if !s:spec_pair_ok(l:key, a:spec[l:key])
      return []
    endif
  endfor
  let l:spec = a:spec
  let l:out = []
  for l:info in getwininfo()
    if s:is_unmanaged(l:info)
      continue
    endif
    if has_key(l:spec, 'winid') && l:info.winid != l:spec.winid
      continue
    endif
    if has_key(l:spec, 'bufnr') && l:info.bufnr != l:spec.bufnr
      continue
    endif
    if has_key(l:spec, 'tabnr')
      let l:want = type(l:spec.tabnr) == type('') && l:spec.tabnr ==# 'current'
            \ ? tabpagenr() : l:spec.tabnr
      if l:info.tabnr != l:want
        continue
      endif
    endif
    call add(l:out, s:normalize(l:info))
  endfor
  return l:out
endfunction

" ---------------------------------------------------------------------------
" Cross-window access
" ---------------------------------------------------------------------------

" Run an Ex command in another window without moving the current window or
" tab page.  Returns v:false when the window is gone or unmanaged.
"
" This is the only way to set a window-local option in another tab page:
" setwinvar() is tab-local and fails silently.
function! winreach#winref#execute(winid, command) abort
  if !s:has('execute') || empty(winreach#winref#get(a:winid))
    return v:false
  endif
  call win_execute(a:winid, a:command)
  return v:true
endfunction

" Evaluate expr in another window and return its value.
" opts: {'default': value, 'silent': 0|1}
"
" A missing/unmanaged window yields opts.default (or {}).  An expression that
" fails in a window that *does* exist propagates its error, so a typo is not
" mistaken for a closed window -- pass {'silent': 1} for best-effort.
function! winreach#winref#eval(winid, expr, ...) abort
  let l:opts = a:0 > 0 && type(a:1) == type({}) ? a:1 : {}
  let l:default = get(l:opts, 'default', {})
  if !s:has('eval') || empty(winreach#winref#get(a:winid))
    return l:default
  endif
  let s:seq += 1
  " The capital is not a style choice: a Funcref cannot be assigned to a
  " global whose name does not start with an uppercase letter (E704), and
  " a leading underscore does not count.  With a lowercase or underscored
  " name, `winreach#winref#eval(id, 'function("F")')` -- or reading a w: variable
  " that holds one -- raises, and under {'silent': 1} it quietly returns
  " the default instead, which is the "the window is gone" answer this
  " function exists to keep separate from an expression that failed.
  let l:key = 'g:Winref_tmp_' . s:uniq . '_' . s:seq
  let l:cmd = (get(l:opts, 'silent', 0) ? 'silent! ' : '')
        \ . 'let ' . l:key . ' = ' . a:expr
  try
    call win_execute(a:winid, l:cmd)
    return exists(l:key) ? eval(l:key) : l:default
  finally
    execute 'unlet!' l:key
  endtry
endfunction

" ---------------------------------------------------------------------------
" Mutation
" ---------------------------------------------------------------------------

" Close a window, or report that it cannot be closed.
"
" Returns v:false, without raising, when the window does not exist, is a
" popup/float, or is the only managed window of its tab page -- closing the
" last window of the *current* tab raises E444, and win_execute()ing 'close'
" on the last window of *another* tab silently destroys that tab page, which
" is not what a caller asking to close one window wants.
" Any other error (E37 and friends, autocmd failures) propagates.
function! winreach#winref#try_close(winid) abort
  if !s:has('try_close')
    return v:false
  endif
  let l:info = winreach#winref#get(a:winid)
  if empty(l:info)
    return v:false
  endif
  if len(winreach#winref#find({'tabnr': l:info.tabnr})) <= 1
    return v:false
  endif
  call win_execute(a:winid, 'close')
  return v:true
endfunction

" Run Fn with 'equalalways' off, then restore it.
"
" 'equalalways' is on by default and re-equalises *every* window on any split
" or close, discarding the user's manual sizes.
"
" Switching the option back on re-equalises immediately -- that is true of
" :set, :setglobal, :let &g: and :noautocmd alike, so there is no quiet way
" to restore it.  The sizes are therefore captured after Fn and replayed
" once the option is back on.  This is winrestcmd()'s documented, valid case
" ("only works properly when no windows are opened or closed"): nothing
" happens between the capture and the replay.  The replay runs twice for the
" same reason Vim's own winrestcmd() emits every :resize twice -- see
" patch 8.2.2631, "Commands from winrestcmd() do not always work properly".
"
" Neovim's winrestcmd() also lists floating windows, which are otherwise
" outside this module's domain.  That is harmless here and deliberately not
" filtered: the capture happens after Fn, so a float's recorded size is the
" size it already has and replaying it is a no-op (verified on 0.12.4,
" including a float Fn itself resized).
"
" The replay only reaches sizes Vim is willing to produce.  A tab page whose
" windows do not fill the rows available to it -- Vim leaves one behind after
" the tabline appears or disappears, and 'winfixheight' can block the row
" that has to move -- is normalised the moment 'equalalways' comes back on,
" so on such a tab page even a Fn that does nothing can change a height.
" Nothing here can prevent that; any redraw-forcing command does it too.
"
" When 'equalalways' is already off there is nothing to protect against and
" nothing to restore, so Fn simply runs.  A plain local save/restore nests
" correctly: an inner call sees the 0 the outer one set and does nothing.
function! winreach#winref#without_equalize(Fn) abort
  if !s:has('without_equalize') || !&equalalways
    return call(a:Fn, [])
  endif
  try
    set noequalalways
    return call(a:Fn, [])
  finally
    let l:sizes = winrestcmd()
    set equalalways
    silent! execute l:sizes
    silent! execute l:sizes
  endtry
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

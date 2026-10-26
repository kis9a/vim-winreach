" winreach#tree - capture a tab page's window layout, and put it back
"
" winrestcmd() resizes windows that are still there; it has nothing to say
" once a window is gone.  Nothing built in restores a layout after :only.
"
" A flat listing cannot stand in for the tree either.  These two layouts
" occupy exactly the same rectangles at exactly the same positions --
"
"   col(row(a,b), row(c,d))     row(col(a,c), col(b,d))
"
" -- so every size-and-position record of them is identical, yet closing the
" top-left window widens the top-right one in the first and heightens the
" bottom-left one in the second.  Only winlayout() tells them apart.
"
" Rebuilding rather than patching is what makes this survive a window count
" that has changed since the capture.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:store = {}

" Layouts remembered automatically, oldest first.  WinClosed fires while the
" window being closed is still there, so what lands here is the layout as it
" was just before something took it apart -- which is the only moment worth
" recording, and the one nobody thinks to :Winsave at.
let s:ring = []
let s:RING_MAX = 8
let s:applying = 0

function! s:notify(level, msg) abort
  if a:level ==# 'error'
    echohl ErrorMsg
  elseif a:level ==# 'warn'
    echohl WarningMsg
  endif
  try
    echomsg 'winreach: ' . a:msg
  finally
    echohl None
  endtry
endfunction

" winlayout()'s nested Lists, with what each leaf needs to come back:
" {'type': 'leaf', 'bufnr': n, 'view': {}} | {'type': 'col'|'row', 'children': []}
function! s:annotate(node) abort
  if a:node[0] ==# 'leaf'
    let l:winid = a:node[1]
    return {
          \ 'type':  'leaf',
          \ 'bufnr': winbufnr(l:winid),
          \ 'view':  winreach#winref#eval(l:winid, 'winsaveview()', {'default': {}}),
          \ }
  endif
  return {
        \ 'type': a:node[0],
        \ 'children': map(copy(a:node[1]), {_, v -> s:annotate(v)}),
        \ }
endfunction

" A snapshot of the current tab page.  Reading it moves nothing: the views
" are read through win_execute(), not by visiting each window.
function! winreach#tree#capture() abort
  if !winreach#winref#available('eval') || !exists('*winlayout')
    return {}
  endif
  return {
        \ 'tree':    s:annotate(winlayout()),
        \ 'sizes':   s:sizes(),
        \ 'columns': &columns,
        \ 'lines':   &lines,
        \ }
endfunction

" winrestcmd() cannot be used here.  It numbers windows by winnr, and on
" Neovim a floating window occupies a winnr while winlayout() -- and so the
" tree this rebuilds -- leaves it out.  Replaying such a string against the
" rebuilt layout puts every size after the float on the wrong window.
" Numbering only the managed windows keeps the two in step.
function! s:sizes() abort
  let l:cmd = ''
  let l:nr = 1
  for l:info in winreach#winref#find({'tabnr': tabpagenr()})
    let l:cmd .= printf('%dresize %d|vert %dresize %d|',
          \ l:nr, l:info.height, l:nr, l:info.width)
    let l:nr += 1
  endfor
  return l:cmd
endfunction

function! s:leaves(node) abort
  if a:node.type ==# 'leaf'
    return [a:node]
  endif
  let l:out = []
  for l:child in a:node.children
    call extend(l:out, s:leaves(l:child))
  endfor
  return l:out
endfunction

function! winreach#tree#size(snap) abort
  return empty(a:snap) ? 0 : len(s:leaves(a:snap.tree))
endfunction

" Split n-1 times for n children, then recurse into each -- the shape comes
" back exactly, whatever the sizes end up being; those are replayed after.
function! s:build(node) abort
  if a:node.type ==# 'leaf'
    if bufexists(a:node.bufnr)
      execute 'buffer' a:node.bufnr
      if !empty(a:node.view)
        call winrestview(a:node.view)
      endif
    endif
    return
  endif
  let l:cmd = a:node.type ==# 'col' ? 'rightbelow split' : 'rightbelow vsplit'
  let l:wins = [win_getid()]
  for l:i in range(1, len(a:node.children) - 1)
    execute 'noautocmd ' . l:cmd
    call add(l:wins, win_getid())
  endfor
  for l:i in range(len(l:wins))
    call win_gotoid(l:wins[l:i])
    call s:build(a:node.children[l:i])
  endfor
endfunction

" Replaces the current tab page's layout.  Returns v:false when there was
" nothing to put back.
function! winreach#tree#apply(snap) abort
  if empty(a:snap) || !has_key(a:snap, 'tree')
    return v:false
  endif
  let l:missing = len(filter(copy(s:leaves(a:snap.tree)),
        \ '!bufexists(v:val.bufnr)'))
  if l:missing > 0
    call s:notify('warn', printf('%d of %d buffer%s no longer exist',
          \ l:missing, winreach#tree#size(a:snap), l:missing == 1 ? '' : 's'))
  endif

  " :only refuses to close a window holding unsaved changes unless the
  " buffer can be hidden, and a partial :only would leave the tab page in a
  " state that is neither the old layout nor the new one.  With 'hidden' an
  " ordinary buffer keeps its unsaved changes and is merely hidden rather
  " than unloaded -- Vim calls that abandoning it, but nothing is written
  " and nothing is lost.  A buffer whose 'bufhidden' is unload, delete or
  " wipe is the exception, and that option wins over 'hidden'.
  let l:save_hidden = &hidden
  let s:applying = 1
  try
    set hidden
    only
    call s:build(a:snap.tree)
  finally
    let &hidden = l:save_hidden
    let s:applying = 0
  endtry

  " The sizes are numbered over managed windows only (see s:sizes), and the
  " rebuild walks the tree in that same order, so the numbering lines up.
  " Twice, for the reason Vim's own winrestcmd() emits everything twice.
  if a:snap.columns == &columns && a:snap.lines == &lines
    silent! execute a:snap.sizes
    silent! execute a:snap.sizes
  else
    call s:notify('warn', printf('screen is %dx%d now, was %dx%d; sizes not replayed',
          \ &columns, &lines, a:snap.columns, a:snap.lines))
  endif
  return v:true
endfunction

" ---------------------------------------------------------------------------
" Remembered layouts
" ---------------------------------------------------------------------------

function! winreach#tree#remember(...) abort
  let l:force = a:0 > 0 && type(a:1) == type({}) && get(a:1, 'force', v:false)
  if s:applying || !get(g:, 'winreach_remember', 1)
    return
  endif
  " One window is not a layout worth coming back to
  let l:n = len(winreach#winref#find({'tabnr': tabpagenr()}))
  if l:n < 2
    return
  endif

  " :only closes windows one at a time, so WinClosed arrives as a burst --
  " 4 windows, then 3, then 2.  Only the first of those is the layout
  " anyone wants back, so a burst is coalesced by time rather than by a
  " high-water mark, which would go stale the moment you work smaller.
  if !l:force && !empty(s:ring)
    let l:last = s:ring[-1]
    if l:last.tabnr == tabpagenr()
          \ && reltimefloat(reltime(l:last.at)) < 0.2
          \ && winreach#tree#size(l:last.snap) >= l:n
      return
    endif
  endif

  let l:snap = winreach#tree#capture()
  if empty(l:snap)
    return
  endif
  call add(s:ring, {'tabnr': tabpagenr(), 'snap': l:snap, 'at': reltime()})
  if len(s:ring) > s:RING_MAX
    call remove(s:ring, 0)
  endif
endfunction

" Put back the most recent remembered layout of this tab page that had more
" windows than it has now.  The entry is consumed, so asking again reaches
" further back rather than doing nothing.
" A remembered layout is worth going back to when it is not what is on
" screen -- either a different set of windows, or the same ones sized
" differently, which is what a resize leaves behind.
function! s:differs(snap) abort
  if winreach#tree#size(a:snap) != len(winreach#winref#find({'tabnr': tabpagenr()}))
    return 1
  endif
  return a:snap.sizes !=# s:sizes()
endfunction

function! winreach#tree#undo() abort
  for l:i in reverse(range(len(s:ring)))
    let l:e = s:ring[l:i]
    if l:e.tabnr == tabpagenr() && s:differs(l:e.snap)
      call remove(s:ring, l:i)
      return winreach#tree#apply(l:e.snap)
    endif
  endfor
  call s:notify('warn', 'no different layout remembered for this tab page')
  return v:false
endfunction

" Drop everything remembered so far.  Used by the tests, which run inside a
" session where the WinClosed autocommand is live.
function! winreach#tree#forget() abort
  let s:ring = []
endfunction

function! winreach#tree#remembered() abort
  return map(copy(s:ring), {_, v -> {'tabnr': v.tabnr,
        \ 'windows': winreach#tree#size(v.snap)}})
endfunction

" ---------------------------------------------------------------------------
" Named store
" ---------------------------------------------------------------------------

function! s:key(name) abort
  return empty(a:name) ? 'default' : a:name
endfunction

function! winreach#tree#save(name) abort
  let l:snap = winreach#tree#capture()
  if empty(l:snap)
    call s:notify('error', 'this build cannot read the window layout')
    return v:false
  endif
  let s:store[s:key(a:name)] = l:snap
  call s:notify('info', printf('saved %s (%d window%s)',
        \ s:key(a:name), winreach#tree#size(l:snap),
        \ winreach#tree#size(l:snap) == 1 ? '' : 's'))
  return v:true
endfunction

function! winreach#tree#restore(name) abort
  let l:key = s:key(a:name)
  if !has_key(s:store, l:key)
    call s:notify('error', printf('no layout saved as %s', l:key))
    return v:false
  endif
  return winreach#tree#apply(s:store[l:key])
endfunction

function! winreach#tree#names() abort
  return sort(keys(s:store))
endfunction

function! winreach#tree#complete(lead, ...) abort
  return filter(winreach#tree#names(), 'stridx(v:val, a:lead) == 0')
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

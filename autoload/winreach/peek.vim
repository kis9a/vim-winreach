" winreach#peek - read a window you cannot see, without going there
"
" getbufline() is not enough: the buffer's text is not what a window is
" *showing*.  Three windows on one buffer are three different views, and
" which lines are on screen, where the cursor sits and how far it has
" scrolled are all window state.  win_execute() is the only way to read that
" for a window of another tab page, which is what this is built on.
"
" line("w$") is deliberately not used.  For a window that is not being
" displayed it returns w0 - 1 -- an empty range -- on Vim, while Neovim
" answers correctly.  line("w0") and winheight() are
" right in both, so the range is derived from those instead.  With 'wrap' or
" closed folds that over-reaches by however many screen lines the wrapping
" costs; harmless here, because the text is redrawn in a window with its own
" height rather than replayed into the original one.

let s:save_cpo = &cpoptions
set cpoptions&vim

" Every key is handled in one place; the two front ends differ only in how
" they deliver it.  A Vim popup takes a filter and receives the raw
" character, a Neovim float takes buffer-local mappings and needs the key
" notation, so both spellings are kept side by side.
let s:KEYS = [
      \ ['j',      'down'],
      \ ['<Down>', 'down'],
      \ ['<C-e>',  'down'],
      \ ['k',      'up'],
      \ ['<Up>',   'up'],
      \ ['<C-y>',  'up'],
      \ ['<C-d>',  'halfdown'],
      \ ['<C-u>',  'halfup'],
      \ ['<C-f>',  'pagedown'],
      \ ['<C-b>',  'pageup'],
      \ ['g',      'top'],
      \ ['G',      'bottom'],
      \ ['r',      'refresh'],
      \ ['<CR>',   'enter'],
      \ ['q',      'close'],
      \ ['<Esc>',  'close'],
      \ ]

" What each action sends to the window being watched.  Nothing here moves
" the current window: win_execute() runs them where they belong.
let s:MOTION = {
      \ 'down':     "normal! \<C-e>",
      \ 'up':       "normal! \<C-y>",
      \ 'halfdown': "normal! \<C-d>",
      \ 'halfup':   "normal! \<C-u>",
      \ 'pagedown': "normal! \<C-f>",
      \ 'pageup':   "normal! \<C-b>",
      \ 'top':      'normal! gg',
      \ 'bottom':   'normal! G',
      \ }

let s:peek = {}

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

function! s:label(bufnr) abort
  let l:name = bufname(a:bufnr)
  if !empty(l:name)
    return fnamemodify(l:name, ':~:.')
  endif
  let l:bt = getbufvar(a:bufnr, '&buftype')
  return empty(l:bt) ? '[No Name]' : '[' . l:bt . ']'
endfunction

" ---------------------------------------------------------------------------
" Reading
" ---------------------------------------------------------------------------

" What winid is showing right now, or {} when it is gone or unmanaged.
" Two round trips through win_execute(): the measurements, then the text.
function! winreach#peek#read(winid) abort
  let l:info = winreach#winref#get(a:winid)
  if empty(l:info) || !winreach#winref#available('eval')
    return {}
  endif
  let l:m = winreach#winref#eval(a:winid,
        \ '[line("w0"), winheight(0), line("$"), line("."), '
        \ . '&modified, &buftype, &tabstop]', {'default': []})
  if type(l:m) != type([]) || len(l:m) < 7
    return {}
  endif
  let [l:top, l:height, l:total, l:cursor, l:mod, l:bt, l:ts] = l:m
  let l:last = min([l:top + l:height - 1, l:total])
  let l:lines = l:top > l:total ? []
        \ : winreach#winref#eval(a:winid,
        \     printf('getline(%d, %d)', l:top, l:last), {'default': []})
  return {
        \ 'winid':    a:winid,
        \ 'tabnr':    l:info.tabnr,
        \ 'bufnr':    l:info.bufnr,
        \ 'label':    s:label(l:info.bufnr),
        \ 'top':      l:top,
        \ 'last':     l:last,
        \ 'total':    l:total,
        \ 'cursor':   l:cursor,
        \ 'height':   l:height,
        \ 'modified': l:mod,
        \ 'buftype':  l:bt,
        \ 'tabstop':  l:ts,
        \ 'lines':    type(l:lines) == type([]) ? l:lines : [],
        \ }
endfunction

function! s:clip(text, width) abort
  if a:width <= 0
    return ''
  endif
  " strcharpart first so a very long line is not trimmed one character at a
  " time; display width is never below character count, so this cannot cut
  " too little.
  let l:out = strchars(a:text) > a:width
        \ ? strcharpart(a:text, 0, a:width) : a:text
  while strdisplaywidth(l:out) > a:width && !empty(l:out)
    let l:out = strcharpart(l:out, 0, strchars(l:out) - 1)
  endwhile
  return l:out
endfunction

" The view as text.  Real buffer line numbers down the left, '>' on the line
" the far window's cursor is sitting on -- the two things that say "this is
" somewhere else, and this is where they are" without any highlighting.
"
" height caps how tall the result may be (0 for no cap).  A window taller
" than the peek can be does not simply lose its bottom: the line the far
" cursor is on is the one you opened this to see, so that is the line the
" visible slice is chosen to keep.  The header reports the range actually
" shown, not the one that would not fit.
function! winreach#peek#render(data, width, ...) abort
  if empty(a:data)
    return []
  endif
  let l:width = max([a:width, 20])
  let l:height = a:0 > 0 ? a:1 : 0
  let l:body = a:data.lines
  let l:top = a:data.top

  if l:height > 0 && len(l:body) > l:height - 2
    let l:avail = max([l:height - 2, 1])
    let l:at = a:data.cursor - a:data.top
    let l:start = l:at >= l:avail
          \ ? min([l:at - l:avail + 1, len(l:body) - l:avail]) : 0
    let l:body = l:body[l:start : l:start + l:avail - 1]
    let l:top += l:start
  endif

  let l:last = empty(l:body) ? a:data.last : l:top + len(l:body) - 1
  let l:head = s:clip(printf('win %d  tab %d  %s%s  %d-%d/%d',
        \ a:data.winid, a:data.tabnr, a:data.label,
        \ a:data.modified ? ' [+]' : '',
        \ l:top, l:last, a:data.total), l:width)

  let l:text_rows = []
  if empty(l:body)
    call add(l:text_rows, '  (nothing on screen)')
  else
    let l:nw = len(string(l:last))
    let l:pad = repeat(' ', a:data.tabstop > 0 ? a:data.tabstop : 8)
    let l:n = l:top
    for l:line in l:body
      let l:text = substitute(l:line, '\t', l:pad, 'g')
      let l:num = repeat(' ', l:nw - len(string(l:n))) . l:n
      call add(l:text_rows, s:clip(printf('%s%s %s',
            \ l:n == a:data.cursor ? '>' : ' ', l:num, l:text), l:width))
      let l:n += 1
    endfor
  endif

  " The rule is drawn last and only as wide as what is above and below it.
  " Drawn at the full width instead it would decide the width, and a peek
  " at a narrow file would open as wide as the screen.
  let l:rule = 0
  for l:r in [l:head] + l:text_rows
    let l:rule = max([l:rule, strdisplaywidth(l:r)])
  endfor
  return [l:head, repeat('-', l:rule)] + l:text_rows
endfunction

" ---------------------------------------------------------------------------
" Driving the far window
" ---------------------------------------------------------------------------

" Peeking does not have to be read-only.  The window is right there behind
" win_execute(); scrolling it from here is no harder than reading it, and it
" turns a glance into "read the rest of it without going".
function! winreach#peek#scroll(winid, action) abort
  if !has_key(s:MOTION, a:action)
    return v:false
  endif
  return winreach#winref#execute(a:winid, s:MOTION[a:action])
endfunction

" ---------------------------------------------------------------------------
" Choosing a window
" ---------------------------------------------------------------------------

function! s:candidates() abort
  let l:current = win_getid()
  return filter(sort(winreach#winref#find({}),
        \ {a, b -> a.tabnr - b.tabnr}), {_, v -> v.winid != l:current})
endfunction

" '' -> the row under the cursor in :Winlist, or the only other window.
" digits -> a window id.  Anything else -> a substring of the label.
function! winreach#peek#resolve(arg) abort
  let l:arg = trim(a:arg)
  if empty(l:arg)
    if exists('b:winreach_list_winids')
      let l:id = get(b:winreach_list_winids, line('.') - 1, 0)
      if l:id > 0
        return l:id
      endif
    endif
    let l:others = s:candidates()
    if len(l:others) == 1
      return l:others[0].winid
    endif
    call s:notify('warn', empty(l:others)
          \ ? 'no other window to peek at'
          \ : 'which window? give an id or part of a name, or use :Winlist')
    return 0
  endif
  if l:arg =~# '^\d\+$'
    let l:id = str2nr(l:arg)
    if empty(winreach#winref#get(l:id))
      call s:notify('warn', printf('window %d is gone', l:id))
      return 0
    endif
    return l:id
  endif
  let l:hits = []
  for l:info in s:candidates()
    if s:label(l:info.bufnr) =~? '\V' . escape(l:arg, '\')
      call add(l:hits, l:info)
    endif
  endfor
  if empty(l:hits)
    call s:notify('warn', printf('no window matching %s', string(l:arg)))
    return 0
  endif
  if len(l:hits) > 1
    call s:notify('warn', printf('%s matches %d windows: %s', string(l:arg),
          \ len(l:hits), join(map(copy(l:hits),
          \ {_, v -> v.winid . ' ' . s:label(v.bufnr)}), ', ')))
    return 0
  endif
  return l:hits[0].winid
endfunction

function! winreach#peek#complete(lead, ...) abort
  let l:out = []
  for l:info in s:candidates()
    call add(l:out, s:label(l:info.bufnr))
    call add(l:out, string(l:info.winid))
  endfor
  return sort(filter(l:out, {_, v -> stridx(v, a:lead) == 0}))
endfunction

" ---------------------------------------------------------------------------
" The peek window
" ---------------------------------------------------------------------------

function! s:supported() abort
  return winreach#winref#available('eval')
        \ && (has('nvim') ? exists('*nvim_open_win') : has('popupwin'))
endfunction

function! s:raw(notation) abort
  return a:notation[0] ==# '<' ? eval('"\' . a:notation . '"') : a:notation
endfunction

function! s:geometry(rows) abort
  let l:w = 20
  for l:r in a:rows
    let l:w = max([l:w, strdisplaywidth(l:r)])
  endfor
  let l:w = min([l:w, max([&columns - 8, 20])])
  let l:h = min([max([len(a:rows), 1]), max([&lines - 6, 3])])
  return [l:w, l:h]
endfunction

function! s:filter(id, key) abort
  for [l:notation, l:action] in s:KEYS
    if a:key ==# s:raw(l:notation)
      call winreach#peek#key(l:action)
      return 1
    endif
  endfor
  return 1
endfunction

function! s:on_popup_closed(...) abort
  let s:peek = {}
endfunction

function! s:show(winid, data) abort
  let l:rows = winreach#peek#render(
        \ a:data, max([&columns - 8, 20]), max([&lines - 6, 3]))
  let [l:w, l:h] = s:geometry(l:rows)
  if has('nvim')
    if empty(s:peek)
      let l:buf = nvim_create_buf(v:false, v:true)
      call nvim_buf_set_option(l:buf, 'bufhidden', 'wipe')
      let l:id = nvim_open_win(l:buf, v:true, {
            \ 'relative': 'editor', 'style': 'minimal', 'border': 'single',
            \ 'row': max([(&lines - l:h) / 2 - 1, 0]),
            \ 'col': max([(&columns - l:w) / 2, 0]),
            \ 'width': l:w, 'height': l:h,
            \ })
      let s:peek = {'kind': 'float', 'id': l:id, 'buf': l:buf, 'winid': a:winid}
      for [l:notation, l:action] in s:KEYS
        execute printf(
              \ 'nnoremap <buffer><silent><nowait> %s :call winreach#peek#key(%s)<CR>',
              \ l:notation, string(l:action))
      endfor
      augroup winreach_peek
        autocmd!
        autocmd WinLeave <buffer> call winreach#peek#close()
      augroup END
    else
      let s:peek.winid = a:winid
      call nvim_win_set_config(s:peek.id, {
            \ 'relative': 'editor',
            \ 'row': max([(&lines - l:h) / 2 - 1, 0]),
            \ 'col': max([(&columns - l:w) / 2, 0]),
            \ 'width': l:w, 'height': l:h,
            \ })
    endif
    call nvim_buf_set_option(s:peek.buf, 'modifiable', v:true)
    call nvim_buf_set_lines(s:peek.buf, 0, -1, v:false, l:rows)
    call nvim_buf_set_option(s:peek.buf, 'modifiable', v:false)
  else
    if empty(s:peek)
      " 'mapping' off sends every key to the filter instead of running the
      " user's own mappings inside the peek.
      let l:id = popup_create(l:rows, {
            \ 'line': max([(&lines - l:h) / 2 - 1, 1]),
            \ 'col': max([(&columns - l:w) / 2, 1]),
            \ 'minwidth': l:w, 'maxwidth': l:w,
            \ 'minheight': l:h, 'maxheight': l:h,
            \ 'border': [], 'padding': [0, 1, 0, 1],
            \ 'zindex': 200, 'mapping': 0,
            \ 'filter': function('s:filter'),
            \ 'callback': function('s:on_popup_closed'),
            \ })
      let s:peek = {'kind': 'popup', 'id': l:id, 'winid': a:winid}
    else
      let s:peek.winid = a:winid
      call popup_setoptions(s:peek.id, {
            \ 'minwidth': l:w, 'maxwidth': l:w,
            \ 'minheight': l:h, 'maxheight': l:h,
            \ })
    endif
    call popup_settext(s:peek.id, l:rows)
  endif
endfunction

function! winreach#peek#close() abort
  if empty(s:peek)
    return
  endif
  " Cleared first: closing a float fires WinLeave, which lands back here.
  let l:p = s:peek
  let s:peek = {}
  if l:p.kind ==# 'float'
    silent! autocmd! winreach_peek
    if nvim_win_is_valid(l:p.id)
      call nvim_win_close(l:p.id, v:true)
    endif
  else
    call popup_close(l:p.id)
  endif
endfunction

function! winreach#peek#winid() abort
  return get(s:peek, 'winid', 0)
endfunction

" The peek's own window: a popup id on Vim, a float's window id on Neovim.
" 0 when nothing is open.
function! winreach#peek#window() abort
  return get(s:peek, 'id', 0)
endfunction

function! winreach#peek#key(action) abort
  if empty(s:peek)
    return
  endif
  let l:winid = s:peek.winid
  if a:action ==# 'close'
    call winreach#peek#close()
    return
  endif
  if a:action ==# 'enter'
    call winreach#peek#close()
    call win_gotoid(l:winid)
    return
  endif
  if a:action !=# 'refresh'
    call winreach#peek#scroll(l:winid, a:action)
  endif
  let l:data = winreach#peek#read(l:winid)
  if empty(l:data)
    call winreach#peek#close()
    call s:notify('warn', printf('window %d is gone', l:winid))
    return
  endif
  call s:show(l:winid, l:data)
  if has('nvim') && s:peek.kind ==# 'float'
    redraw
  endif
endfunction

function! winreach#peek#open(...) abort
  if !s:supported()
    call s:notify('error', 'this build is missing a builtin winreach needs')
    return
  endif
  let l:winid = a:0 > 0 && type(a:1) == type(0)
        \ ? a:1 : winreach#peek#resolve(a:0 > 0 ? a:1 : '')
  if l:winid <= 0
    return
  endif
  let l:data = winreach#peek#read(l:winid)
  if empty(l:data)
    call s:notify('warn', printf('window %d is gone', l:winid))
    return
  endif
  call winreach#peek#close()
  call s:show(l:winid, l:data)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

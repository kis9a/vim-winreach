" winreach#list - see every window in every tab page, without going there
"
" Building the list reads the whole layout through winref, so nothing moves
" and no autocommand fires for the sake of looking.  The list window itself
" is opened afterwards and is deliberately not in its own listing: what you
" see is the layout as it was when you asked.

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:NAME = '[winreach]'

function! s:label(info) abort
  let l:name = bufname(a:info.bufnr)
  if !empty(l:name)
    return fnamemodify(l:name, ':~:.')
  endif
  let l:bt = getbufvar(a:info.bufnr, '&buftype')
  return empty(l:bt) ? '[No Name]' : '[' . l:bt . ']'
endfunction

" Short markers for the things that explain a window's behaviour at a glance.
" The buftype is skipped when the label is already showing it -- an unnamed
" quickfix window would otherwise read "[quickfix]  [quickfix]".
function! s:flags(info, current, label) abort
  let l:out = []
  let l:bt = getbufvar(a:info.bufnr, '&buftype')
  if !empty(l:bt) && a:label !=# '[' . l:bt . ']'
    call add(l:out, l:bt)
  endif
  if getbufvar(a:info.bufnr, '&modified')
    call add(l:out, '+')
  endif
  for [l:opt, l:mark] in [['&diff', 'diff'], ['&previewwindow', 'preview'],
        \ ['&winfixheight', 'fixh'], ['&winfixwidth', 'fixw']]
    if winreach#winref#eval(a:info.winid, l:opt, {'default': 0})
      call add(l:out, l:mark)
    endif
  endfor
  return join(l:out, ' ')
endfunction

" [{'text': String, 'winid': Number}] -- winid 0 for a tab-page heading.
function! winreach#list#rows() abort
  if !winreach#winref#available('eval')
    return []
  endif
  let l:current = win_getid()
  let l:wins = sort(winreach#winref#find({}), {a, b -> a.tabnr - b.tabnr})
  if empty(l:wins)
    return []
  endif

  " Widths are computed from the data so the columns line up whatever the
  " window ids and sizes happen to be.
  " Width and height are padded separately so the 'x' sits in one column;
  " right-aligning the whole 'WxH' string would only line up when both
  " halves happen to have the same number of digits.
  let l:cells = []
  let l:w_id = 0
  let l:w_w = 0
  let l:w_h = 0
  for l:info in l:wins
    let l:label = s:label(l:info)
    let l:cell = {
          \ 'tabnr': l:info.tabnr,
          \ 'winid': l:info.winid,
          \ 'id':    string(l:info.winid),
          \ 'w':     string(l:info.width),
          \ 'h':     string(l:info.height),
          \ 'label': l:label,
          \ 'flags': s:flags(l:info, l:current, l:label),
          \ }
    let l:w_id = max([l:w_id, len(l:cell.id)])
    let l:w_w = max([l:w_w, len(l:cell.w)])
    let l:w_h = max([l:w_h, len(l:cell.h)])
    call add(l:cells, l:cell)
  endfor

  let l:rows = []
  let l:tab = -1
  for l:c in l:cells
    if l:c.tabnr != l:tab
      let l:tab = l:c.tabnr
      call add(l:rows, {'text': printf('tab %d', l:tab), 'winid': 0})
    endif
    let l:text = printf('  %s %s  %sx%s  %s',
          \ l:c.winid == l:current ? '>' : ' ',
          \ repeat(' ', l:w_id - len(l:c.id)) . l:c.id,
          \ repeat(' ', l:w_w - len(l:c.w)) . l:c.w,
          \ l:c.h . repeat(' ', l:w_h - len(l:c.h)),
          \ l:c.label)
    if !empty(l:c.flags)
      let l:text .= '  [' . l:c.flags . ']'
    endif
    call add(l:rows, {'text': l:text, 'winid': l:c.winid})
  endfor
  return l:rows
endfunction

" Replace the contents of the list window we are already in.  The listing is
" a snapshot of the moment it was asked for, so being able to ask again
" without stacking a second list on top is the useful thing to do here.
function! s:refresh(rows) abort
  setlocal modifiable
  silent! keepjumps %delete _
  call setline(1, map(copy(a:rows), {_, v -> v.text}))
  setlocal nomodifiable nomodified
  let b:winreach_list_winids = map(copy(a:rows), {_, v -> v.winid})
  call cursor(len(a:rows) > 1 ? 2 : 1, 1)
endfunction

function! s:open(rows) abort
  " The height is always explicit.  That is not only about fitting the
  " content: a count suppresses 'equalalways', so opening the list leaves
  " every other window's height alone.  A bare :botright new would
  " re-equalise the whole tab page.
  let l:height = min([max([len(a:rows), 1]), max([&lines - 6, 3])])
  execute 'botright ' . l:height . 'new'
  silent! execute 'file ' . fnameescape(s:NAME)
  setlocal buftype=nofile bufhidden=wipe noswapfile nobuflisted
  setlocal nonumber norelativenumber nowrap cursorline winfixheight
  setlocal filetype=winreachlist
  call setline(1, map(copy(a:rows), {_, v -> v.text}))
  setlocal nomodifiable nomodified
  let b:winreach_list_winids = map(copy(a:rows), {_, v -> v.winid})

  nnoremap <buffer> <silent> <CR> :call winreach#list#enter()<CR>
  nnoremap <buffer> <silent> p    :call winreach#list#peek()<CR>
  nnoremap <buffer> <silent> q    :call winreach#list#close()<CR>
  nnoremap <buffer> <silent> <Esc> :call winreach#list#close()<CR>

  " Start on the first real window row
  call cursor(len(a:rows) > 1 ? 2 : 1, 1)
endfunction

function! winreach#list#open() abort
  if !winreach#winref#available('eval')
    echohl ErrorMsg
    echomsg 'winreach: this build is missing a builtin winreach needs'
    echohl None
    return
  endif
  " Asking again from inside the list means "show me the current state",
  " not "give me a second list"
  let l:in_list = exists('b:winreach_list_winids')
  let l:rows = winreach#list#rows()
  if empty(l:rows)
    echohl WarningMsg | echomsg 'winreach: no windows to list' | echohl None
    return
  endif
  if l:in_list
    call s:refresh(l:rows)
  else
    call s:open(l:rows)
  endif
endfunction

function! winreach#list#close() abort
  if !exists('b:winreach_list_winids')
    return
  endif
  if !winreach#winref#try_close(win_getid())
    " Sole window of this tab page: leave the buffer instead
    silent! enew
  endif
endfunction

" The listing says what is open; this says what it is showing.  Peeking
" leaves the list where it is, so the two read as one browser: move down a
" row, press p again.
function! winreach#list#peek() abort
  if !exists('b:winreach_list_winids')
    return
  endif
  let l:winid = get(b:winreach_list_winids, line('.') - 1, 0)
  if l:winid == 0
    return
  endif
  call winreach#peek#open(l:winid)
endfunction

function! winreach#list#enter() abort
  if !exists('b:winreach_list_winids')
    return
  endif
  let l:winid = get(b:winreach_list_winids, line('.') - 1, 0)
  if l:winid == 0
    return
  endif
  if empty(winreach#winref#get(l:winid))
    echohl WarningMsg
    echomsg printf('winreach: window %d is gone', l:winid)
    echohl None
    return
  endif
  call winreach#list#close()
  call win_gotoid(l:winid)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

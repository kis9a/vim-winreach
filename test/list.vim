" test/list.vim: tests for autoload/winreach/list.vim (:Winlist)

scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:suite = themis#suite('winreach#list')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  silent! tabonly!
  silent! only!
  silent! enew!
  let g:winreach_test_hits = 0
endfunction

function! s:suite.after_each() abort
  silent! augroup winreach_list_test
  silent! autocmd!
  silent! augroup END
  silent! tabonly!
  silent! only!
  " The list window sets 'winfixheight', and :only! keeps that window --
  " the option would survive into the next test and block its :resize.
  " Exactly the leftover-window-state problem winref exists for.
  setlocal nowinfixheight nowinfixwidth
endfunction

" Three tab pages, five windows.
function! s:world() abort
  only!
  vsplit
  tabnew
  split
  tabnew
  tabnext 2
endfunction

function! s:winid_rows() abort
  return filter(winreach#list#rows(), 'v:val.winid != 0')
endfunction

function! s:open_unmanaged() abort
  if has('nvim')
    let l:b = nvim_create_buf(v:false, v:true)
    return nvim_open_win(l:b, v:false,
          \ {'relative': 'editor', 'row': 1, 'col': 1, 'width': 10, 'height': 3})
  endif
  return popup_create('x', {'line': 2, 'col': 2})
endfunction

function! s:close_unmanaged(id) abort
  if has('nvim')
    silent! call nvim_win_close(a:id, v:true)
  else
    silent! call popup_close(a:id)
  endif
endfunction

" ===========================================================================
" rows()
" ===========================================================================

function! s:suite.rows_cover_every_window_in_every_tab() abort
  call s:world()
  call s:assert.equals(
        \ map(s:winid_rows(), {_, v -> v.winid}),
        \ map(winreach#winref#find({}), {_, v -> v.winid}))
endfunction

function! s:suite.rows_carry_a_heading_per_tab_page() abort
  call s:world()
  let l:headings = filter(map(winreach#list#rows(),
        \ {_, v -> v.winid == 0 ? v.text : ''}), '!empty(v:val)')
  call s:assert.equals(l:headings, ['tab 1', 'tab 2', 'tab 3'])
endfunction

function! s:suite.rows_mark_the_current_window() abort
  call s:world()
  let l:cur = win_getid()
  for l:row in s:winid_rows()
    call s:assert.equals(l:row.text =~# '^  >', l:row.winid == l:cur)
  endfor
endfunction

" Looking is free: reading the layout must not move or fire anything.
function! s:suite.building_the_rows_has_no_side_effects() abort
  call s:world()
  let l:tab = tabpagenr()
  let l:win = win_getid()
  augroup winreach_list_test
    autocmd!
    autocmd WinEnter,WinLeave,BufEnter,BufLeave *
          \ let g:winreach_test_hits += 1
  augroup END

  call winreach#list#rows()

  call s:assert.equals(g:winreach_test_hits, 0)
  call s:assert.equals(tabpagenr(), l:tab)
  call s:assert.equals(win_getid(), l:win)
endfunction

function! s:suite.a_popup_or_float_is_never_listed() abort
  call s:world()
  let l:id = s:open_unmanaged()
  try
    call s:assert.equals(
          \ index(map(s:winid_rows(), {_, v -> v.winid}), l:id), -1)
  finally
    call s:close_unmanaged(l:id)
  endtry
endfunction

" Columns are computed from the data, so they line up whatever the ids and
" sizes are.
function! s:suite.rows_are_column_aligned() abort
  let l:save = &columns
  try
    " Sizes must differ in width for this to mean anything: at 120 columns a
    " full-width window is '120x22' (6) and a third of one is '40x22' (5).
    set columns=120
    only!
    vsplit
    vsplit
    tabnew

    let l:sizes = map(s:winid_rows(), {_, v -> matchstr(v.text, '\d\+x\d\+')})
    call s:assert.true(len(uniq(sort(map(copy(l:sizes), 'len(v:val)')))) > 1,
          \ 'probe is useless unless the size widths differ: ' . string(l:sizes))

    let l:at = map(s:winid_rows(), {_, v -> stridx(v.text, 'x')})
    call s:assert.equals(uniq(sort(copy(l:at))), [l:at[0]])
  finally
    let &columns = l:save
  endtry
endfunction

" ===========================================================================
" :Winlist
" ===========================================================================

function! s:suite.the_command_opens_a_scratch_list() abort
  call s:world()
  let l:want = map(winreach#list#rows(), {_, v -> v.text})

  Winlist

  call s:assert.equals(&filetype, 'winreachlist')
  call s:assert.equals(&buftype, 'nofile')
  call s:assert.false(&modifiable)
  call s:assert.equals(getline(1, '$'), l:want)
endfunction

" What you see is the layout as it was when you asked; the list window is
" not in its own listing.
function! s:suite.the_list_window_is_not_in_its_own_listing() abort
  call s:world()
  Winlist
  let l:me = win_getid()
  call s:assert.equals(
        \ index(get(b:, 'winreach_list_winids', []), l:me), -1)
endfunction

" Opening a window is a mutation; 'equalalways' must not turn it into a
" resize of everything else.
" :Winlist opens a full-width window at the bottom, which splits the tab
" page vertically -- so heights are what 'equalalways' would re-equalise.
function! s:suite.opening_the_list_keeps_manual_heights() abort
  set equalalways
  try
    only!
    split
    split
    1wincmd w
    resize 4
    2wincmd w
    resize 6
    let l:before = map(getwininfo(), {_, v -> v.height})
    call s:assert.true(len(uniq(sort(copy(l:before)))) > 1,
          \ 'probe is useless unless the heights differ: ' . string(l:before))

    Winlist

    let l:after = map(winreach#winref#find({'tabnr': 'current'}),
          \ {_, v -> v.height})
    call s:assert.equals(l:after[0], l:before[0])
    call s:assert.equals(l:after[1], l:before[1])
  finally
    set noequalalways
  endtry
endfunction

function! s:suite.enter_jumps_to_the_window_and_closes_the_list() abort
  call s:world()
  let l:target = winreach#winref#find({'tabnr': 1})[0].winid
  Winlist
  let l:line = 0
  for l:i in range(len(b:winreach_list_winids))
    if b:winreach_list_winids[l:i] == l:target
      let l:line = l:i + 1
    endif
  endfor
  call s:assert.true(l:line > 0)

  call cursor(l:line, 1)
  call winreach#list#enter()

  call s:assert.equals(win_getid(), l:target)
  call s:assert.equals(tabpagenr(), 1)
  call s:assert.equals(bufname('%') =~# 'winreach', 0)
endfunction

function! s:suite.enter_on_a_tab_heading_does_nothing() abort
  call s:world()
  Winlist
  let l:me = win_getid()
  call cursor(1, 1)

  call winreach#list#enter()

  call s:assert.equals(win_getid(), l:me)
endfunction

function! s:suite.enter_on_a_window_that_is_gone_warns_and_stays() abort
  call s:world()
  let l:doomed = winreach#winref#find({'tabnr': 1})[0].winid
  Winlist
  let l:line = index(b:winreach_list_winids, l:doomed) + 1
  call s:assert.true(l:line > 0)
  call winreach#winref#try_close(l:doomed)
  let l:me = win_getid()

  call cursor(l:line, 1)
  let l:out = execute('call winreach#list#enter()', 'silent!')

  call s:assert.match(l:out, 'is gone')
  call s:assert.equals(win_getid(), l:me)
endfunction

" The listing is a snapshot, so asking again from inside it should show the
" current state rather than stack a second list on top of the first.
function! s:suite.asking_again_from_inside_refreshes_in_place() abort
  call s:world()
  Winlist
  let l:me = win_getid()
  let l:windows = len(winreach#winref#find({'tabnr': 'current'}))
  let l:before = getline(1, '$')

  " Something changes out there while the list is open
  call winreach#winref#try_close(winreach#winref#find({'tabnr': 1})[0].winid)
  Winlist

  call s:assert.equals(win_getid(), l:me)
  call s:assert.equals(len(winreach#winref#find({'tabnr': 'current'})), l:windows)
  call s:assert.not_equals(getline(1, '$'), l:before)
  call s:assert.equals(&filetype, 'winreachlist')
  call s:assert.false(&modifiable)
endfunction

function! s:suite.close_removes_the_list_window() abort
  call s:world()
  let l:before = len(winreach#winref#find({'tabnr': 'current'}))
  Winlist
  call s:assert.equals(
        \ len(winreach#winref#find({'tabnr': 'current'})), l:before + 1)

  call winreach#list#close()

  call s:assert.equals(
        \ len(winreach#winref#find({'tabnr': 'current'})), l:before)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

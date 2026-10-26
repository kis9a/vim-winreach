" test/winreach.vim: tests for autoload/winreach.vim

scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:suite = themis#suite('winreach')
let s:assert = themis#helper('assert')

" Global helpers: they run inside win_execute(), where script-local
" functions of this file are not reachable.
function! WinreachCount() abort
  let g:winreach_test_calls += 1
endfunction

function! WinreachCountThenFail() abort
  let g:winreach_test_calls += 1
  call WinreachNoSuchFunction()
endfunction

function! s:suite.before_each() abort
  silent! tabonly!
  silent! only!
  silent! enew!
  let g:winreach_test_hits = 0
  let g:winreach_test_calls = 0
endfunction

function! s:suite.after_each() abort
  silent! augroup winreach_test
  silent! autocmd!
  silent! augroup END
  silent! tabonly!
  silent! only!
  unlet! g:winreach_test_hits g:winreach_test_calls g:winreach_test_victim
endfunction

" Three tab pages, five windows in total.
function! s:world() abort
  only!
  vsplit
  tabnew
  split
  tabnew
  tabnext 2
endfunction

function! s:all_winids() abort
  return sort(map(copy(getwininfo()), {_, v -> v.winid}))
endfunction

function! s:watch_traversal_autocmds() abort
  augroup winreach_test
    autocmd!
    autocmd WinEnter,WinLeave,BufEnter,BufLeave *
          \ let g:winreach_test_hits += 1
  augroup END
endfunction

" ===========================================================================
" Applies everywhere
" ===========================================================================

function! s:suite.applies_to_every_window_in_every_tab() abort
  call s:world()
  call winreach#map('setlocal nonumber')

  call winreach#map('setlocal number')

  for l:info in winreach#winref#find({})
    call s:assert.equals(winreach#winref#eval(l:info.winid, '&number'), 1)
  endfor
endfunction

function! s:suite.reports_what_it_visited() abort
  call s:world()
  let l:got = winreach#map('setlocal number')
  call s:assert.equals(l:got.visited, len(winreach#winref#find({})))
  call s:assert.equals(l:got.skipped, 0)
  call s:assert.equals(l:got.failed, [])
endfunction

function! s:suite.visits_in_tab_order() abort
  call s:world()
  let g:winreach_test_order = []
  call winreach#map('call add(g:winreach_test_order, tabpagenr())')
  call s:assert.equals(g:winreach_test_order, sort(copy(g:winreach_test_order)))
  unlet g:winreach_test_order
endfunction

" Contract 6's second half: within a tab, getwininfo() order.
function! s:suite.visits_in_getwininfo_order_within_a_tab() abort
  call s:world()
  let g:winreach_test_order = []
  call winreach#map('call add(g:winreach_test_order, win_getid())')
  call s:assert.equals(g:winreach_test_order,
        \ map(winreach#winref#find({}), {_, v -> v.winid}))
  unlet g:winreach_test_order
endfunction

" ===========================================================================
" The traversal itself has no side effects
" ===========================================================================

function! s:suite.traversal_keeps_the_current_tab_and_window() abort
  call s:world()
  let l:tab = tabpagenr()
  let l:win = win_getid()

  call winreach#map('setlocal number')

  call s:assert.equals(tabpagenr(), l:tab)
  call s:assert.equals(win_getid(), l:win)
endfunction

function! s:suite.traversal_keeps_the_previous_window_mark() abort
  call s:world()
  wincmd j
  wincmd k
  let l:prev = win_getid(winnr('#'))
  call s:assert.true(l:prev > 0)

  call winreach#map('setlocal number')

  call s:assert.equals(win_getid(winnr('#')), l:prev)
endfunction

function! s:suite.traversal_keeps_the_alternate_buffer() abort
  call s:world()
  enew
  file winreach_alt_a
  enew
  file winreach_alt_b
  let l:alt = bufnr('#')
  call s:assert.true(l:alt > 0)

  call winreach#map('setlocal number')

  call s:assert.equals(bufnr('#'), l:alt)
endfunction

" The claim is narrow on purpose: walking the windows fires nothing.  A
" command that itself enters buffers still does whatever it does.
function! s:suite.traversal_fires_no_window_or_buffer_autocmds() abort
  call s:world()
  call s:watch_traversal_autocmds()

  call winreach#map('setlocal number')

  call s:assert.equals(g:winreach_test_hits, 0)
endfunction

function! s:suite.tabdo_windo_is_the_thing_this_avoids() abort
  call s:world()
  let l:tab = tabpagenr()
  let l:win = win_getid()
  call s:watch_traversal_autocmds()

  silent! tabdo windo setlocal number

  " Recorded as the baseline this plugin exists to beat
  call s:assert.true(g:winreach_test_hits > 0)
  call s:assert.true(tabpagenr() != l:tab || win_getid() != l:win)
endfunction

" ===========================================================================
" Snapshot semantics
" ===========================================================================

function! s:suite.windows_opened_by_the_command_are_not_swept() abort
  call s:world()
  let l:before = len(winreach#winref#find({}))

  let l:got = winreach#map('split')

  call s:assert.equals(l:got.visited, l:before)
  call s:assert.equals(len(winreach#winref#find({})), l:before * 2)
endfunction

function! s:suite.windows_closed_by_the_command_are_skipped() abort
  call s:world()
  " Close a window of tab 2 while visiting tab 1: the walk is tab-ordered, so
  " the victim is gone by the time its own turn comes.  It must not be the
  " sole window of its tab -- try_close() refuses those on purpose.
  let g:winreach_test_victim = winreach#winref#find({'tabnr': 2})[-1].winid
  function! WinreachTestCloseVictim() abort
    let g:winreach_test_calls += 1
    if g:winreach_test_calls == 1
      call winreach#winref#try_close(g:winreach_test_victim)
    endif
  endfunction

  let l:got = winreach#map('call WinreachTestCloseVictim()')

  call s:assert.equals(l:got.skipped, 1)
  call s:assert.equals(winreach#winref#get(g:winreach_test_victim), {})
  delfunction WinreachTestCloseVictim
endfunction

function! s:suite.a_popup_or_float_is_never_visited() abort
  call s:world()
  if has('nvim')
    let l:b = nvim_create_buf(v:false, v:true)
    let l:id = nvim_open_win(l:b, v:false,
          \ {'relative': 'editor', 'row': 1, 'col': 1, 'width': 10, 'height': 3})
  else
    let l:id = popup_create('x', {'line': 2, 'col': 2})
  endif
  try
    let l:got = winreach#map('let w:winreach_seen = 1')
    call s:assert.equals(l:got.visited, len(winreach#winref#find({})))
    call s:assert.equals(getwinvar(l:id, 'winreach_seen', 'absent'), 'absent')
  finally
    if has('nvim')
      silent! call nvim_win_close(l:id, v:true)
    else
      silent! call popup_close(l:id)
    endif
  endtry
endfunction


" ===========================================================================
" :Winmap / :Winmap!  (the command layer, not just winreach#map)
" ===========================================================================

function! s:suite.the_command_applies_everywhere() abort
  call s:world()
  Winmap setlocal nonumber
  Winmap setlocal number
  for l:info in winreach#winref#find({})
    call s:assert.equals(winreach#winref#eval(l:info.winid, '&number'), 1)
  endfor
endfunction

function! s:suite.the_command_keeps_the_current_tab_and_window() abort
  call s:world()
  let l:tab = tabpagenr()
  let l:win = win_getid()
  Winmap setlocal number
  call s:assert.equals(tabpagenr(), l:tab)
  call s:assert.equals(win_getid(), l:win)
endfunction

" The bang is what selects keep_going, so the two forms must differ in how
" many windows they report as failing.
function! s:suite.the_bang_selects_keep_going() abort
  call s:world()
  let l:n = len(winreach#winref#find({}))
  let g:winreach_test_calls = 0
  silent! Winmap call WinreachCountThenFail()
  let l:without = g:winreach_test_calls
  let g:winreach_test_calls = 0
  silent! Winmap! call WinreachCountThenFail()
  let l:with = g:winreach_test_calls
  call s:assert.equals(l:without, 1)
  call s:assert.equals(l:with, l:n)
endfunction

" A bar in the command belongs to the command, not to :Winmap.
function! s:suite.the_command_passes_a_bar_through() abort
  call s:world()
  let l:n = len(winreach#winref#find({}))
  let g:winreach_test_calls = 0
  Winmap let g:winreach_test_calls += 1 | let g:winreach_test_calls += 10
  call s:assert.equals(g:winreach_test_calls, l:n * 11)
endfunction

" ===========================================================================
" Reporting
" ===========================================================================

" The snapshot's tabnr goes stale as soon as the command adds a tab page.
function! s:suite.a_failure_reports_where_the_window_is_now() abort
  call s:world()
  let g:winreach_test_calls = 0
  function! WinreachShiftThenFail() abort
    let g:winreach_test_calls += 1
    if g:winreach_test_calls == 1
      0tabnew
    endif
    call WinreachNoSuchFunction()
  endfunction

  let l:got = winreach#map('call WinreachShiftThenFail()', {'keep_going': v:true})

  call s:assert.true(len(l:got.failed) > 0)
  for l:f in l:got.failed
    let l:info = winreach#winref#get(l:f.winid)
    if !empty(l:info)
      call s:assert.equals(l:f.tabnr, l:info.tabnr)
    endif
  endfor
  delfunction WinreachShiftThenFail
endfunction

function! s:suite.a_failure_records_a_throwpoint() abort
  call s:world()
  let l:got = winreach#map('call WinreachNoSuchFunction()')
  call s:assert.equals(sort(keys(l:got.failed[0])),
        \ ['error', 'tabnr', 'throwpoint', 'winid'])
  call s:assert.true(!empty(l:got.failed[0].throwpoint))
endfunction

" Stopping early leaves windows untouched; say how many.
function! s:suite.an_early_stop_reports_what_it_did_not_reach() abort
  call s:world()
  let l:n = len(winreach#winref#find({}))
  let g:winreach_test_calls = 0

  let l:got = winreach#map('call WinreachCountThenFail()')

  call s:assert.equals(l:got.visited + l:got.skipped
        \ + len(l:got.failed) + l:got.remaining, l:n)
  call s:assert.equals(l:got.remaining, l:n - 1)
endfunction

function! s:suite.a_completed_walk_leaves_nothing_remaining() abort
  call s:world()
  let l:got = winreach#map('setlocal number')
  call s:assert.equals(l:got.remaining, 0)
endfunction

" execute() returns v:false when it did nothing; that is not a visit.
function! s:suite.a_window_the_command_never_ran_in_is_not_counted_as_visited() abort
  call s:world()
  let l:n = len(winreach#winref#find({}))
  let g:winreach_test_calls = 0

  " Disable winref from inside the walk: every later window does nothing
  silent let l:got = winreach#map(
        \ "call WinreachCount() | let g:winreach#winref#test_missing = ['win_execute']")

  let g:winreach#winref#test_missing = []
  call s:assert.equals(l:got.visited, g:winreach_test_calls)
  call s:assert.true(l:got.visited < l:n)
endfunction

" A String keep_going already falls back to false on its own (!'yes' is 1 in
" legacy Vim script), so the behaviour alone cannot tell a validated build
" from an unvalidated one -- assert that the caller is actually told.
function! s:suite.keep_going_of_the_wrong_type_is_reported() abort
  call s:world()
  let l:n = len(winreach#winref#find({}))
  let g:winreach_test_calls = 0

  let l:out = execute("call winreach#map('call WinreachCountThenFail()',"
        \ . " {'keep_going': 'yes'})", 'silent!')

  call s:assert.match(l:out, 'keep_going must be a Number or Boolean')
  call s:assert.equals(g:winreach_test_calls, 1)
endfunction

" ===========================================================================
" Failure handling
" ===========================================================================

function! s:suite.aborts_at_the_first_failing_window() abort
  call s:world()
  let l:got = winreach#map('call WinreachNoSuchFunction()')

  call s:assert.equals(l:got.visited, 0)
  call s:assert.equals(len(l:got.failed), 1)
  call s:assert.match(l:got.failed[0].error, 'E117')
  call s:assert.true(l:got.failed[0].winid > 0)
endfunction

function! s:suite.bang_visits_the_rest_and_reports_them_all() abort
  call s:world()
  let l:n = len(winreach#winref#find({}))

  let l:got = winreach#map('call WinreachNoSuchFunction()', {'keep_going': v:true})

  call s:assert.equals(len(l:got.failed), l:n)
  call s:assert.equals(l:got.visited, 0)
endfunction

" Ctrl-C must end the walk, not become one more per-window failure that
" keep_going carries on from -- otherwise :Winmap! is uninterruptible and is
" strictly worse than the :tabdo windo it replaces, which stops at the first.
function! s:suite.an_interrupt_stops_the_walk_even_with_keep_going() abort
  call s:world()
  let l:n = len(winreach#winref#find({}))
  let g:winreach_test_calls = 0
  function! WinreachCountThenInterrupt() abort
    let g:winreach_test_calls += 1
    call interrupt()
  endfunction

  silent! let l:got = winreach#map('call WinreachCountThenInterrupt()',
        \ {'keep_going': v:true})

  call s:assert.equals(g:winreach_test_calls, 1)
  call s:assert.equals(l:got.remaining, l:n - 1)
  call s:assert.equals(l:got.failed, [])
  delfunction WinreachCountThenInterrupt
endfunction

function! s:suite.a_failure_does_not_move_the_cursor() abort
  call s:world()
  let l:tab = tabpagenr()
  let l:win = win_getid()

  call winreach#map('call WinreachNoSuchFunction()')

  call s:assert.equals(tabpagenr(), l:tab)
  call s:assert.equals(win_getid(), l:win)
endfunction

" ===========================================================================
" Guards
" ===========================================================================

function! s:suite.an_empty_command_is_refused() abort
  call s:world()
  for l:cmd in ['', '   ', 0, []]
    let l:got = winreach#map(l:cmd)
    call s:assert.equals(l:got.visited, 0)
    call s:assert.equals(l:got.failed, [])
  endfor
endfunction

function! s:suite.disabled_cleanly_without_win_execute() abort
  call s:world()
  let g:winreach#winref#test_missing = ['win_execute']
  try
    silent let l:got = winreach#map("setlocal number")
    call s:assert.equals(l:got.visited, 0)
  finally
    let g:winreach#winref#test_missing = []
  endtry
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

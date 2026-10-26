" test/tree.vim: tests for autoload/winreach/tree.vim (:Winsave / :Winrestore)

scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:suite = themis#suite('winreach#tree')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  silent! tabonly!
  silent! only!
  silent! enew!
  setlocal nowinfixheight nowinfixwidth
  let g:winreach_test_hits = 0
  let g:winreach_remember = 1
  call winreach#tree#forget()
endfunction

function! s:suite.after_each() abort
  silent! augroup winreach_tree_test
  silent! autocmd!
  silent! augroup END
  silent! tabonly!
  silent! only!
  setlocal nowinfixheight nowinfixwidth
  let g:winreach_remember = 1
  call winreach#tree#forget()
endfunction

" The shape alone, with the window ids thrown away.
function! s:shape(...) abort
  let l:node = a:0 > 0 ? a:1 : winlayout()
  if l:node[0] ==# 'leaf'
    return 'leaf'
  endif
  return l:node[0] . '(' . join(map(copy(l:node[1]),
        \ {_, v -> s:shape(v)}), ',') . ')'
endfunction

" Everything a flat listing could possibly record: size and position.
function! s:flat() abort
  return sort(map(copy(getwininfo()),
        \ {_, v -> printf('%dx%d@%d,%d', v.width, v.height, v.winrow, v.wincol)}))
endfunction

function! s:bufnames() abort
  return map(copy(getwininfo()), {_, v -> fnamemodify(bufname(v.bufnr), ':t')})
endfunction

" source | test stacked on the left, log | term stacked on the right.
function! s:nested() abort
  only!
  for l:f in ['source', 'test', 'log', 'term']
    call writefile(map(range(1, 200), 'l:f . " " . v:val'), '/tmp/wr_' . l:f . '.txt')
  endfor
  edit /tmp/wr_source.txt
  split /tmp/wr_test.txt
  wincmd l
  vsplit /tmp/wr_log.txt
  split /tmp/wr_term.txt
  wincmd t
endfunction

" ===========================================================================
" Why the tree, and not a flat listing
" ===========================================================================

" These two layouts fill exactly the same rectangles at exactly the same
" positions, so every size-and-position record of them is identical -- yet
" they behave differently.  This is the whole reason capture() keeps the
" tree instead of the numbers :Winlist shows.
function! s:suite.two_layouts_can_share_a_flat_listing_and_differ() abort
  only! | split | wincmd t | vsplit | wincmd j | wincmd j | vsplit
  let l:shape_a = s:shape()
  let l:flat_a = s:flat()

  only! | vsplit | wincmd t | split | wincmd l | split
  let l:shape_b = s:shape()

  call s:assert.equals(l:flat_a, s:flat())
  call s:assert.not_equals(l:shape_a, l:shape_b)
  call s:assert.equals(l:shape_a, 'col(row(leaf,leaf),row(leaf,leaf))')
  call s:assert.equals(l:shape_b, 'row(col(leaf,leaf),col(leaf,leaf))')
endfunction

function! s:suite.and_closing_the_same_window_does_different_things() abort
  only! | split | wincmd t | vsplit | wincmd j | wincmd j | vsplit | wincmd t
  close
  let l:after_a = s:flat()

  only! | vsplit | wincmd t | split | wincmd l | split | wincmd t
  close

  call s:assert.not_equals(l:after_a, s:flat())
endfunction

" ===========================================================================
" capture()
" ===========================================================================

function! s:suite.capture_records_the_shape_and_the_buffers() abort
  call s:nested()
  let l:snap = winreach#tree#capture()

  call s:assert.equals(winreach#tree#size(l:snap), 4)
  call s:assert.equals(l:snap.tree.type, 'col')
  call s:assert.equals(l:snap.columns, &columns)
  call s:assert.equals(l:snap.lines, &lines)
endfunction

" Looking is free here too: the views are read through win_execute().
function! s:suite.capture_has_no_side_effects() abort
  call s:nested()
  let l:tab = tabpagenr()
  let l:win = win_getid()
  augroup winreach_tree_test
    autocmd!
    autocmd WinEnter,WinLeave,BufEnter,BufLeave *
          \ let g:winreach_test_hits += 1
  augroup END

  call winreach#tree#capture()

  call s:assert.equals(g:winreach_test_hits, 0)
  call s:assert.equals(tabpagenr(), l:tab)
  call s:assert.equals(win_getid(), l:win)
endfunction

" ===========================================================================
" apply()
" ===========================================================================

function! s:suite.apply_puts_the_layout_back_after_only() abort
  call s:nested()
  let l:shape = s:shape()
  let l:flat = s:flat()
  let l:names = s:bufnames()
  let l:snap = winreach#tree#capture()

  only
  call s:assert.equals(winnr('$'), 1)

  call s:assert.equals(winreach#tree#apply(l:snap), v:true)

  call s:assert.equals(s:shape(), l:shape)
  call s:assert.equals(s:flat(), l:flat)
  call s:assert.equals(s:bufnames(), l:names)
endfunction

" capture() reads each leaf's view through win_execute(), so this covers the
" recording side of winrestview() -- which the restoring side cannot be
" covered here: themis runs in Ex mode, where there is no screen, so a
" scroll command has no effect even in the window it is run in (`zt` and
" `zb` both leave line('w0') equal to the cursor line).  The scroll position
" coming back is therefore correct-by-construction and unasserted.
function! s:suite.capture_records_each_leafs_view() abort
  call s:nested()
  let l:line = 20
  for l:info in getwininfo()
    call winreach#winref#execute(l:info.winid, 'call cursor(' . l:line . ', 1)')
    let l:line += 30
  endfor

  let l:snap = winreach#tree#capture()

  let l:views = []
  function! s:collect(node) abort closure
    if a:node.type ==# 'leaf'
      call add(l:views, a:node.view)
    else
      for l:c in a:node.children
        call s:collect(l:c)
      endfor
    endif
  endfunction
  call s:collect(l:snap.tree)

  call s:assert.equals(len(l:views), 4)
  call s:assert.equals(sort(map(copy(l:views), 'v:val.lnum'), 'n'), [20, 50, 80, 110])
endfunction

function! s:suite.apply_puts_the_cursor_back() abort
  call s:nested()
  let l:line = 20
  for l:info in getwininfo()
    call winreach#winref#execute(l:info.winid, 'call cursor(' . l:line . ', 1)')
    let l:line += 30
  endfor
  let l:want = map(copy(getwininfo()),
        \ {_, v -> winreach#winref#eval(v.winid, 'line(".")')})
  let l:snap = winreach#tree#capture()

  only
  call winreach#tree#apply(l:snap)

  call s:assert.equals(map(copy(getwininfo()),
        \ {_, v -> winreach#winref#eval(v.winid, 'line(".")')}), l:want)
endfunction

" A partial :only would leave the tab page neither as it was nor as asked.
function! s:suite.apply_gets_past_an_unsaved_buffer() abort
  call s:nested()
  let l:snap = winreach#tree#capture()
  let l:hidden = &hidden
  try
    set nohidden
    " The unsaved buffer must be in a window :only would have to close --
    " :only keeps the current one, so modifying that proves nothing.
    wincmd b
    call setline(1, 'edited but not written')
    wincmd t

    call s:assert.equals(winreach#tree#apply(l:snap), v:true)

    call s:assert.equals(winreach#tree#size(l:snap), len(getwininfo()))
    call s:assert.equals(&hidden, 0, "'hidden' must be put back as it was")
  finally
    silent! call winreach#map('silent! edit!')
    let &hidden = l:hidden
  endtry
endfunction

" On Neovim a floating window takes a winnr, but winlayout() -- and so the
" rebuilt layout -- leaves it out.  Sizes numbered by winnr would land on
" the wrong windows; sizes numbered over managed windows do not.
function! s:suite.a_float_open_at_capture_does_not_shift_the_sizes() abort
  if !has('nvim')
    return
  endif
  only!
  split
  split
  1wincmd w
  resize 4
  2wincmd w
  resize 6
  let l:want = map(copy(winreach#winref#find({'tabnr': 'current'})),
        \ {_, v -> v.height})
  call s:assert.true(len(uniq(sort(copy(l:want)))) > 1,
        \ 'probe is useless unless the heights differ: ' . string(l:want))

  let l:b = nvim_create_buf(v:false, v:true)
  let l:float = nvim_open_win(l:b, v:false,
        \ {'relative': 'editor', 'row': 1, 'col': 1, 'width': 20, 'height': 5})
  try
    call s:assert.equals(len(getwininfo()), len(l:want) + 1)
    let l:snap = winreach#tree#capture()
    call s:assert.equals(winreach#tree#size(l:snap), len(l:want))
  finally
    silent! call nvim_win_close(l:float, v:true)
  endtry

  only
  call winreach#tree#apply(l:snap)

  call s:assert.equals(map(copy(winreach#winref#find({'tabnr': 'current'})),
        \ {_, v -> v.height}), l:want)
endfunction

function! s:suite.apply_is_false_for_nothing_to_restore() abort
  call s:assert.equals(winreach#tree#apply({}), v:false)
  call s:assert.equals(winreach#tree#apply({'sizes': ''}), v:false)
endfunction

function! s:suite.apply_reports_a_buffer_that_is_gone() abort
  call s:nested()
  let l:snap = winreach#tree#capture()
  let l:doomed = bufnr('/tmp/wr_log.txt')
  only
  execute 'silent! bwipeout! ' . l:doomed

  let l:out = execute('call winreach#tree#apply(l:snap)', 'silent!')

  call s:assert.match(l:out, 'no longer exist')
  " The shape still comes back; only that leaf is empty
  call s:assert.equals(len(getwininfo()), winreach#tree#size(l:snap))
endfunction

" Replaying winnr-based sizes onto a screen of a different size would put
" them in the wrong place; say so instead.
function! s:suite.apply_skips_sizes_when_the_screen_changed() abort
  call s:nested()
  let l:snap = winreach#tree#capture()
  let l:snap.lines = l:snap.lines - 5

  only
  let l:out = execute('call winreach#tree#apply(l:snap)', 'silent!')

  call s:assert.match(l:out, 'sizes not replayed')
  call s:assert.equals(s:shape(), 'col(row(col(leaf,leaf),leaf),leaf)')
endfunction

" ===========================================================================
" :Winsave / :Winrestore
" ===========================================================================

function! s:suite.the_commands_round_trip_a_named_layout() abort
  call s:nested()
  let l:shape = s:shape()
  let l:flat = s:flat()

  Winsave work
  only
  Winrestore work

  call s:assert.equals(s:shape(), l:shape)
  call s:assert.equals(s:flat(), l:flat)
endfunction

function! s:suite.an_unnamed_save_is_called_default() abort
  call s:nested()
  silent Winsave
  call s:assert.true(index(winreach#tree#names(), 'default') >= 0)
endfunction

function! s:suite.restoring_a_name_that_was_never_saved_is_refused() abort
  call s:nested()
  let l:before = s:shape()

  let l:out = execute('call winreach#tree#restore("no_such_layout")', 'silent!')

  call s:assert.match(l:out, 'no layout saved')
  call s:assert.equals(s:shape(), l:before)
endfunction

" ===========================================================================
" Remembered layouts / :Winundo
" ===========================================================================

" The whole point: nobody runs :Winsave before the accident.
function! s:suite.a_layout_lost_to_only_comes_back_without_having_saved_it() abort
  call s:nested()
  let l:shape = s:shape()
  let l:flat = s:flat()
  let l:names = s:bufnames()
  " Note there is no :Winsave anywhere above -- that is the point

  only
  call s:assert.equals(winnr('$'), 1)

  call s:assert.equals(winreach#tree#undo(), v:true)

  call s:assert.equals(s:shape(), l:shape)
  call s:assert.equals(s:flat(), l:flat)
  call s:assert.equals(s:bufnames(), l:names)
endfunction

" :only closes one window at a time, so WinClosed arrives as a descending
" burst.  Remembering each step would make :Winundo restore the smallest.
function! s:suite.a_burst_of_closes_is_remembered_once() abort
  call s:nested()
  let l:n = len(winreach#winref#find({'tabnr': 'current'}))
  call s:assert.true(l:n > 2)

  only

  call s:assert.equals(winreach#tree#remembered(),
        \ [{'tabnr': 1, 'windows': l:n}])
endfunction

" Asking again reaches further back rather than doing nothing.
function! s:suite.undo_consumes_what_it_used() abort
  call s:nested()
  only
  call winreach#tree#undo()

  call s:assert.equals(winreach#tree#remembered(), [])
  let l:n = len(winreach#winref#find({'tabnr': 'current'}))
  let l:out = execute('call winreach#tree#undo()', 'silent!')
  call s:assert.match(l:out, 'no different layout remembered')
  call s:assert.equals(len(winreach#winref#find({'tabnr': 'current'})), l:n)
endfunction

function! s:suite.one_window_is_not_worth_remembering() abort
  only!
  split
  close
  call s:assert.equals(winreach#tree#remembered(), [{'tabnr': 1, 'windows': 2}])
  call winreach#tree#forget()
  only!
  " Closing the sole window of a tab page: nothing worth coming back to
  tabnew
  tabclose
  call s:assert.equals(winreach#tree#remembered(), [])
endfunction

function! s:suite.another_tabs_layout_is_not_offered_here() abort
  only!
  split
  tabnew
  split
  split
  only
  call s:assert.equals(map(winreach#tree#remembered(), {_, v -> v.tabnr}), [2])

  tabnext 1
  let l:out = execute('call winreach#tree#undo()', 'silent!')

  call s:assert.match(l:out, 'no different layout remembered')
  call s:assert.equals(len(winreach#winref#find({'tabnr': 'current'})), 2)
endfunction

function! s:suite.remembering_can_be_turned_off() abort
  let g:winreach_remember = 0
  try
    call s:nested()
    only
    call s:assert.equals(winreach#tree#remembered(), [])
  finally
    let g:winreach_remember = 1
  endtry
endfunction

" apply() runs :only itself; remembering that would bury the entry being
" restored under the layout it is replacing.
function! s:suite.restoring_does_not_remember_what_it_replaces() abort
  call s:nested()
  let l:snap = winreach#tree#capture()

  " Something else is on screen now -- apply()'s own :only will have real
  " windows to close, which is the case the guard exists for
  only!
  split
  split
  call s:assert.true(len(winreach#winref#find({'tabnr': 'current'})) > 1)
  call winreach#tree#forget()

  call winreach#tree#apply(l:snap)

  call s:assert.equals(winreach#tree#remembered(), [])
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

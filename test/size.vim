" test/size.vim: tests for autoload/winreach/size.vim (:Winheight / :Winwidth)

scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:suite = themis#suite('winreach#size')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  silent! tabonly!
  silent! only!
  silent! enew!
  setlocal nowinfixheight nowinfixwidth
  let g:winreach_remember = 1
  call winreach#tree#forget()
endfunction

function! s:suite.after_each() abort
  silent! tabonly!
  silent! only!
  setlocal nowinfixheight nowinfixwidth
  call winreach#tree#forget()
endfunction

function! s:heights() abort
  return map(copy(getwininfo()), {_, v -> v.height})
endfunction

function! s:widths() abort
  return map(copy(getwininfo()), {_, v -> v.width})
endfunction

function! s:sum(list) abort
  let l:n = 0
  for l:v in a:list
    let l:n += l:v
  endfor
  return l:n
endfunction

" Three stacked windows of deliberately unequal height, cursor in the first.
function! s:stack() abort
  only!
  split
  split
  1wincmd w
  resize 4
  2wincmd w
  resize 6
  1wincmd w
endfunction

" ===========================================================================
" What :resize does badly
" ===========================================================================

" :resize takes what it needs from whoever is next to it, so growing the
" first window by six lines leaves the second at one.  The point of this
" command is that everyone sharing the axis gives up a share instead.
function! s:suite.growing_a_window_does_not_crush_one_neighbour() abort
  call s:stack()
  let l:before = s:heights()
  resize 10
  let l:naive = s:heights()

  call s:stack()
  call winreach#size#set('height', '10')
  let l:shared = s:heights()

  call s:assert.equals(l:naive[0], 10)
  call s:assert.equals(l:shared[0], 10)
  call s:assert.equals(min(l:naive), 1, 'probe is useless unless :resize crushes one')
  call s:assert.true(min(l:shared) > 1)
  call s:assert.equals(s:sum(l:shared), s:sum(l:before))
endfunction

function! s:suite.shrinking_gives_the_room_back_in_proportion() abort
  call s:stack()
  let l:before = s:heights()
  wincmd b

  call winreach#size#set('height', '4')

  let l:after = s:heights()
  call s:assert.equals(l:after[2], 4)
  call s:assert.equals(s:sum(l:after), s:sum(l:before))
  " Both of the others grew, rather than one taking it all
  call s:assert.true(l:after[0] > l:before[0])
  call s:assert.true(l:after[1] > l:before[1])
endfunction

" ===========================================================================
" Ways of saying how big
" ===========================================================================

function! s:suite.a_percentage_is_of_what_the_axis_holds() abort
  call s:stack()
  let l:total = s:sum(s:heights())

  call winreach#size#set('height', '50%')

  call s:assert.equals(s:heights()[0], float2nr(round(l:total * 0.5)))
endfunction

function! s:suite.a_signed_number_is_relative() abort
  call s:stack()
  let l:was = s:heights()[0]

  call winreach#size#set('height', '+4')

  call s:assert.equals(s:heights()[0], l:was + 4)
endfunction

function! s:suite.anything_else_is_refused() abort
  call s:stack()
  let l:before = s:heights()
  for l:spec in ['', 'wide', '10x', '-', '%']
    let l:out = execute("call winreach#size#set('height', '" . l:spec . "')", 'silent!')
    call s:assert.match(l:out, 'want a number')
  endfor
  call s:assert.equals(s:heights(), l:before)
endfunction

" ===========================================================================
" Which windows share the axis
" ===========================================================================

" In col(row(a,b), c), a's width is shared with b only -- c is on the other
" side of a horizontal split and has nothing to do with it.  Getting this
" right is why the layout tree is needed and a flat list of windows is not.
function! s:suite.width_is_shared_with_the_row_only() abort
  only!
  split
  wincmd t
  vsplit
  1wincmd w
  let l:before = s:widths()
  call s:assert.equals(l:before[2], &columns, 'c should span the full width')

  call winreach#size#set('width', '20')

  let l:after = s:widths()
  call s:assert.equals(l:after[0], 20)
  call s:assert.equals(l:after[1], l:before[0] + l:before[1] - 20)
  call s:assert.equals(l:after[2], l:before[2], 'c must not have been touched')
endfunction

" The other direction, and the one that needs the walk upwards: in
" col(row(a,b), c) the leaf's parent is the row, which is not the axis a
" height change travels along.  a and b share their height by construction,
" so the room has to come from c -- taking it from b would be asking the
" row to shrink and grow at once.
function! s:suite.height_comes_from_above_the_row() abort
  only!
  split
  wincmd t
  vsplit
  1wincmd w
  let l:before = s:heights()
  call s:assert.equals(l:before[0], l:before[1], 'a and b share a height')

  call winreach#size#set('height', '15')

  let l:after = s:heights()
  call s:assert.equals(l:after[0], 15)
  call s:assert.equals(l:after[1], 15, 'b follows a, it does not pay for it')
  " a and b share one height, so what the column has to divide is
  " a's height plus c's, not the sum over every window
  call s:assert.equals(l:after[2], l:before[0] + l:before[2] - 15,
        \ 'c is the one that gives up the room')
  call s:assert.true(l:after[2] < l:before[2])
endfunction

function! s:suite.a_sole_window_has_nobody_to_share_with() abort
  only!
  let l:was = winheight(0)

  let l:out = execute("call winreach#size#set('height', '10')", 'silent!')

  call s:assert.match(l:out, 'nothing to share')
  call s:assert.equals(winheight(0), l:was)
endfunction

" ===========================================================================
" Reversibility
" ===========================================================================

" No mode to enter and no cancel key: the layout is remembered first, so the
" ordinary undo command takes it back.
function! s:suite.a_resize_can_be_undone() abort
  call s:stack()
  let l:before = s:heights()

  call winreach#size#set('height', '12')
  call s:assert.not_equals(s:heights(), l:before)

  call winreach#tree#undo()

  call s:assert.equals(s:heights(), l:before)
endfunction

function! s:suite.a_refused_resize_remembers_nothing() abort
  call s:stack()
  call winreach#tree#forget()

  silent! call winreach#size#set('height', 'nonsense')

  call s:assert.equals(winreach#tree#remembered(), [])
endfunction

" ===========================================================================
" :Winheight / :Winwidth
" ===========================================================================

function! s:suite.the_commands_reach_the_same_places() abort
  call s:stack()
  Winheight 10
  call s:assert.equals(s:heights()[0], 10)

  only!
  split
  wincmd t
  vsplit
  1wincmd w
  Winwidth 20
  call s:assert.equals(s:widths()[0], 20)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

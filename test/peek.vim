" test/peek.vim: tests for autoload/winreach/peek.vim (:Winpeek)

scriptencoding utf-8

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:suite = themis#suite('winreach#peek')
let s:assert = themis#helper('assert')

function! s:suite.before_each() abort
  call winreach#peek#close()
  silent! tabonly!
  silent! only!
  silent! enew!
endfunction

function! s:suite.after_each() abort
  call winreach#peek#close()
  silent! tabonly!
  silent! only!
  setlocal nowinfixheight nowinfixwidth
  " :file refuses a name another buffer already holds (E95), and silent!
  " leaves that buffer unnamed instead -- a test would then quietly be
  " looking for a window that is not called what it thinks.
  for l:b in filter(range(1, bufnr('$')),
        \ 'bufexists(v:val) && bufname(v:val) =~# "winreach-peek-"')
    silent! execute 'bwipeout!' l:b
  endfor
endfunction

" A window in another tab page showing a long buffer.
"
" It is deliberately not scrolled to a chosen line: in the batch harness Vim
" keeps topline pinned to the cursor line, and neither winrestview() nor zt
" moves it (Neovim does honour zt).  Nothing here needs a
" particular topline, only that what is read back is the window's own.
function! s:far(...) abort
  let l:total = a:0 > 0 ? a:1 : 500
  let l:cursor = a:0 > 1 ? a:2 : 1
  tabnew
  call setline(1, map(range(1, l:total), '"log line " . v:val'))
  setlocal buftype=nofile noswapfile nowrap
  let l:id = win_getid()
  call cursor(l:cursor, 1)
  tabprevious
  return l:id
endfunction

" What the far window says about itself, measured without going through
" peek, so the two can be compared.
function! s:truth(winid) abort
  return winreach#winref#eval(a:winid,
        \ '[line("w0"), winheight(0), line("."), line("$")]', {'default': []})
endfunction

" ---------------------------------------------------------------------------
" read
" ---------------------------------------------------------------------------

function! s:suite.read_returns_the_visible_range_of_a_window_in_another_tab() abort
  let l:id = s:far(500, 4)
  let l:d = winreach#peek#read(l:id)
  call s:assert.not_empty(l:d)
  let [l:w0, l:height, l:cursor, l:total] = s:truth(l:id)
  call s:assert.equals(l:d.top, l:w0)
  call s:assert.equals(l:d.height, l:height)
  call s:assert.equals(l:d.cursor, l:cursor)
  call s:assert.equals(l:d.total, l:total)
  call s:assert.equals(l:d.tabnr, 2)
  call s:assert.equals(l:d.last, min([l:w0 + l:height - 1, l:total]))
  call s:assert.equals(len(l:d.lines), l:d.last - l:d.top + 1)
  call s:assert.equals(l:d.lines[0], 'log line ' . l:d.top)
  call s:assert.equals(l:d.lines[-1], 'log line ' . l:d.last)
endfunction

" The whole point of not using line("w$"): for a window that is not being
" displayed Vim answers w0 - 1, and a range built from it holds nothing.
function! s:suite.read_fills_the_window_rather_than_trusting_w_dollar() abort
  let l:id = s:far(500, 1)
  let [l:w0, l:height, l:_, l:total] = s:truth(l:id)
  call s:assert.compare(l:height, '>', 1)
  let l:w_dollar = winreach#winref#eval(l:id, 'line("w$")', {'default': -1})
  let l:d = winreach#peek#read(l:id)
  call s:assert.compare(len(l:d.lines), '>', 1)
  call s:assert.equals(len(l:d.lines), min([l:height, l:total]))
  if l:w_dollar < l:w0
    " Vim: w$ would have produced an empty range here.
    call s:assert.compare(l:d.last, '>', l:w_dollar)
  endif
endfunction

function! s:suite.read_does_not_change_the_current_tab_page_or_window() abort
  let l:id = s:far()
  let l:tab = tabpagenr()
  let l:win = win_getid()
  call winreach#peek#read(l:id)
  call s:assert.equals(tabpagenr(), l:tab)
  call s:assert.equals(win_getid(), l:win)
endfunction

function! s:suite.read_clamps_the_last_line_to_the_end_of_the_buffer() abort
  " Fewer lines than the window is tall: w0 + height - 1 runs past the end.
  let l:id = s:far(3, 1)
  let l:d = winreach#peek#read(l:id)
  call s:assert.equals(l:d.total, 3)
  call s:assert.equals(l:d.last, 3)
  call s:assert.equals(len(l:d.lines), 3)
endfunction

function! s:suite.read_returns_empty_for_a_window_that_does_not_exist() abort
  call s:assert.equals(winreach#peek#read(99999), {})
endfunction

function! s:suite.read_returns_empty_for_a_popup_or_float() abort
  if has('nvim')
    let l:b = nvim_create_buf(v:false, v:true)
    let l:id = nvim_open_win(l:b, v:false,
          \ {'relative': 'editor', 'row': 1, 'col': 1, 'width': 10, 'height': 3})
  else
    let l:id = popup_create('x', {'line': 2, 'col': 2})
  endif
  try
    call s:assert.equals(winreach#peek#read(l:id), {})
  finally
    if has('nvim') | silent! call nvim_win_close(l:id, v:true)
    else | silent! call popup_close(l:id) | endif
  endtry
endfunction

function! s:suite.read_reports_the_far_buffers_state_not_this_ones() abort
  setlocal buftype=nofile
  let l:id = s:far()
  call win_execute(l:id, 'setlocal modifiable | setlocal tabstop=3')
  let l:d = winreach#peek#read(l:id)
  call s:assert.equals(l:d.tabstop, 3)
  call s:assert.equals(l:d.buftype, 'nofile')
  call s:assert.not_equals(l:d.bufnr, bufnr('%'))
endfunction

" ---------------------------------------------------------------------------
" render
" ---------------------------------------------------------------------------

function! s:data(...) abort
  return extend({
        \ 'winid': 1001, 'tabnr': 2, 'bufnr': 7, 'label': 'log.txt',
        \ 'top': 300, 'last': 302, 'total': 500, 'cursor': 301,
        \ 'height': 3, 'modified': 0, 'buftype': '', 'tabstop': 4,
        \ 'lines': ['aaa', 'bbb', 'ccc'],
        \ }, a:0 > 0 ? a:1 : {})
endfunction

function! s:suite.render_heads_the_view_with_where_it_came_from() abort
  let l:head = winreach#peek#render(s:data(), 80)[0]
  call s:assert.match(l:head, 'win 1001')
  call s:assert.match(l:head, 'tab 2')
  call s:assert.match(l:head, 'log\.txt')
  call s:assert.match(l:head, '300-302/500')
endfunction

function! s:suite.render_marks_a_modified_buffer() abort
  call s:assert.not_match(winreach#peek#render(s:data(), 80)[0], '\[+\]')
  call s:assert.match(
        \ winreach#peek#render(s:data({'modified': 1}), 80)[0], '\[+\]')
endfunction

function! s:suite.render_numbers_the_lines_as_the_far_buffer_numbers_them() abort
  let l:rows = winreach#peek#render(s:data(), 80)
  call s:assert.equals(l:rows[2], ' 300 aaa')
  call s:assert.equals(l:rows[4], ' 302 ccc')
endfunction

function! s:suite.render_marks_the_line_the_far_cursor_is_on() abort
  let l:rows = winreach#peek#render(s:data(), 80)
  call s:assert.equals(l:rows[3], '>301 bbb')
  " and it moves with the cursor, rather than always being the second line
  let l:moved = winreach#peek#render(s:data({'cursor': 302}), 80)
  call s:assert.equals(l:moved[3], ' 301 bbb')
  call s:assert.equals(l:moved[4], '>302 ccc')
endfunction

function! s:suite.render_pads_line_numbers_to_the_widest_one() abort
  let l:rows = winreach#peek#render(
        \ s:data({'top': 99, 'last': 101, 'cursor': 99,
        \         'lines': ['a', 'b', 'c']}), 80)
  call s:assert.equals(l:rows[2], '> 99 a')
  call s:assert.equals(l:rows[3], ' 100 b')
endfunction

function! s:suite.render_expands_tabs_using_the_far_windows_tabstop() abort
  let l:rows = winreach#peek#render(
        \ s:data({'lines': ["\tx", 'b', 'c'], 'tabstop': 4}), 80)
  call s:assert.equals(l:rows[2], ' 300     x')
  let l:wide = winreach#peek#render(
        \ s:data({'lines': ["\tx", 'b', 'c'], 'tabstop': 8}), 80)
  call s:assert.equals(l:wide[2], ' 300         x')
endfunction

function! s:suite.render_keeps_every_row_inside_the_given_width() abort
  let l:rows = winreach#peek#render(
        \ s:data({'lines': [repeat('x', 300), 'b', 'c']}), 30)
  for l:r in l:rows
    call s:assert.compare(strdisplaywidth(l:r), '<=', 30)
  endfor
  call s:assert.equals(strdisplaywidth(l:rows[2]), 30)
endfunction

function! s:suite.render_counts_display_width_not_characters() abort
  " Each of these is one character and two columns wide.
  let l:rows = winreach#peek#render(
        \ s:data({'lines': [repeat('あ', 40), 'b', 'c']}), 24)
  call s:assert.compare(strdisplaywidth(l:rows[2]), '<=', 24)
  call s:assert.compare(strchars(l:rows[2]), '<', 24)
endfunction

function! s:suite.render_keeps_the_far_cursor_when_the_view_does_not_fit() abort
  let l:d = s:data({'top': 100, 'last': 109, 'cursor': 108, 'total': 500,
        \ 'lines': map(range(100, 109), '"line " . v:val')})
  " 6 rows: a header, a rule, and four lines of text
  let l:rows = winreach#peek#render(l:d, 80, 6)
  call s:assert.equals(len(l:rows), 6)
  call s:assert.equals(l:rows[2], ' 105 line 105')
  call s:assert.equals(l:rows[-2], ' 107 line 107')
  call s:assert.equals(l:rows[-1], '>108 line 108')
  call s:assert.match(l:rows[0], '105-108/500')
  " the lines past the cursor are the ones dropped, not the ones kept
  call s:assert.equals(len(filter(copy(l:rows), 'v:val =~# "line 109"')), 0)
endfunction

function! s:suite.render_marks_the_far_cursor_after_it_has_been_windowed() abort
  let l:d = s:data({'top': 100, 'last': 109, 'cursor': 106, 'total': 500,
        \ 'lines': map(range(100, 109), '"line " . v:val')})
  let l:rows = winreach#peek#render(l:d, 80, 6)
  call s:assert.equals(l:rows[2], ' 103 line 103')
  call s:assert.equals(l:rows[5], '>106 line 106')
endfunction

function! s:suite.render_does_not_slide_when_the_far_cursor_is_near_the_top() abort
  let l:d = s:data({'top': 100, 'last': 109, 'cursor': 101, 'total': 500,
        \ 'lines': map(range(100, 109), '"line " . v:val')})
  let l:rows = winreach#peek#render(l:d, 80, 6)
  call s:assert.equals(l:rows[2], ' 100 line 100')
  call s:assert.equals(l:rows[3], '>101 line 101')
  call s:assert.match(l:rows[0], '100-103/500')
endfunction

function! s:suite.render_shows_everything_when_no_height_is_given() abort
  let l:d = s:data({'top': 100, 'last': 109, 'cursor': 108, 'total': 500,
        \ 'lines': map(range(100, 109), '"line " . v:val')})
  call s:assert.equals(len(winreach#peek#render(l:d, 80)), 12)
  call s:assert.equals(len(winreach#peek#render(l:d, 80, 0)), 12)
  call s:assert.equals(len(winreach#peek#render(l:d, 80, 99)), 12)
endfunction

function! s:suite.render_is_only_as_wide_as_what_it_has_to_show() abort
  let l:rows = winreach#peek#render(
        \ s:data({'lines': ['ab', 'cd', 'ef']}), 200)
  let l:w = max(map(copy(l:rows), 'strdisplaywidth(v:val)'))
  call s:assert.compare(l:w, '<', 60)
  " the rule is exactly as wide as the widest thing around it, never wider
  call s:assert.equals(len(l:rows[1]), l:w)
  call s:assert.equals(l:rows[1], repeat('-', l:w))
endfunction

function! s:suite.render_says_so_when_there_is_nothing_on_screen() abort
  let l:rows = winreach#peek#render(
        \ s:data({'lines': [], 'top': 501, 'last': 500}), 80)
  call s:assert.equals(len(l:rows), 3)
  call s:assert.match(l:rows[2], 'nothing on screen')
endfunction

function! s:suite.render_returns_nothing_for_no_data() abort
  call s:assert.equals(winreach#peek#render({}, 80), [])
endfunction

" ---------------------------------------------------------------------------
" scroll
" ---------------------------------------------------------------------------

function! s:suite.scroll_moves_the_far_window_without_going_there() abort
  let l:id = s:far(500, 1)
  let l:tab = tabpagenr()
  let l:win = win_getid()
  call s:assert.equals(winreach#peek#read(l:id).top, 1)
  call s:assert.true(winreach#peek#scroll(l:id, 'bottom'))
  call s:assert.equals(tabpagenr(), l:tab)
  call s:assert.equals(win_getid(), l:win)
  let l:d = winreach#peek#read(l:id)
  call s:assert.equals(l:d.cursor, 500)
  call s:assert.compare(l:d.top, '>', 1)
  call s:assert.equals(l:d.lines[0], 'log line ' . l:d.top)
  call s:assert.true(winreach#peek#scroll(l:id, 'top'))
  let l:back = winreach#peek#read(l:id)
  call s:assert.equals(l:back.top, 1)
  call s:assert.equals(l:back.cursor, 1)
endfunction

function! s:suite.scroll_rejects_an_action_it_does_not_know() abort
  let l:id = s:far(500, 60)
  let l:before = s:truth(l:id)
  call s:assert.false(winreach#peek#scroll(l:id, 'sideways'))
  call s:assert.equals(s:truth(l:id), l:before)
endfunction

function! s:suite.scroll_reports_a_window_that_is_gone() abort
  call s:assert.false(winreach#peek#scroll(99999, 'bottom'))
endfunction

" ---------------------------------------------------------------------------
" resolve
" ---------------------------------------------------------------------------

function! s:suite.resolve_takes_a_window_id() abort
  let l:id = s:far()
  call s:assert.equals(winreach#peek#resolve(string(l:id)), l:id)
endfunction

function! s:suite.resolve_refuses_a_window_id_that_is_gone() abort
  call s:assert.equals(winreach#peek#resolve('99999'), 0)
endfunction

function! s:suite.resolve_takes_part_of_a_name() abort
  tabnew
  silent! file /tmp/winreach-peek-alpha.txt
  let l:alpha = win_getid()
  tabprevious
  call s:assert.equals(winreach#peek#resolve('peek-alpha'), l:alpha)
endfunction

function! s:suite.resolve_refuses_a_name_that_matches_more_than_one() abort
  tabnew
  silent! file /tmp/winreach-peek-beta.txt
  tabnew
  silent! file /tmp/winreach-peek-beta2.txt
  tabfirst
  call s:assert.equals(winreach#peek#resolve('peek-beta'), 0)
endfunction

function! s:suite.resolve_refuses_a_name_that_matches_nothing() abort
  call s:far()
  call s:assert.equals(winreach#peek#resolve('no-such-window'), 0)
endfunction

function! s:suite.resolve_picks_the_only_other_window_when_asked_for_nothing() abort
  let l:id = s:far()
  call s:assert.equals(winreach#peek#resolve(''), l:id)
endfunction

function! s:suite.resolve_will_not_guess_between_several_windows() abort
  call s:far()
  call s:far()
  call s:assert.equals(winreach#peek#resolve(''), 0)
endfunction

function! s:suite.resolve_never_offers_the_window_you_are_standing_in() abort
  silent! file /tmp/winreach-peek-here.txt
  call s:assert.equals(winreach#peek#resolve('peek-here'), 0)
  call s:assert.equals(len(filter(winreach#peek#complete(''),
        \ 'v:val =~# "peek-here"')), 0)
endfunction

function! s:suite.complete_offers_names_and_ids_of_the_other_windows() abort
  tabnew
  silent! file /tmp/winreach-peek-gamma.txt
  let l:id = win_getid()
  tabprevious
  let l:c = winreach#peek#complete('')
  call s:assert.not_equals(index(l:c, string(l:id)), -1)
  call s:assert.equals(len(filter(copy(l:c), 'v:val =~# "peek-gamma"')), 1)
  call s:assert.equals(winreach#peek#complete('zzz'), [])
endfunction

" ---------------------------------------------------------------------------
" the peek window
" ---------------------------------------------------------------------------

function! s:suite.open_shows_a_window_and_close_takes_it_away() abort
  let l:id = s:far()
  let l:before = len(winreach#winref#find({}))
  call winreach#peek#open(l:id)
  call s:assert.equals(winreach#peek#winid(), l:id)
  " The peek is a popup or a float: outside the managed set, so it does not
  " show up as another window and nothing was resized to make room for it.
  call s:assert.equals(len(winreach#winref#find({})), l:before)
  call winreach#peek#close()
  call s:assert.equals(winreach#peek#winid(), 0)
endfunction

function! s:suite.open_refuses_a_window_that_is_gone() abort
  call winreach#peek#open(99999)
  call s:assert.equals(winreach#peek#winid(), 0)
endfunction

function! s:suite.opening_a_second_peek_replaces_the_first() abort
  let l:a = s:far()
  let l:b = s:far()
  call winreach#peek#open(l:a)
  call winreach#peek#open(l:b)
  call s:assert.equals(winreach#peek#winid(), l:b)
  call winreach#peek#close()
  call s:assert.equals(winreach#peek#winid(), 0)
endfunction

function! s:suite.close_is_safe_when_nothing_is_open() abort
  call winreach#peek#close()
  call winreach#peek#close()
  call s:assert.equals(winreach#peek#winid(), 0)
endfunction

function! s:suite.a_key_scrolls_the_far_window_and_the_peek_stays_open() abort
  let l:id = s:far(500, 1)
  call winreach#peek#open(l:id)
  call winreach#peek#key('bottom')
  call s:assert.equals(winreach#peek#winid(), l:id)
  call s:assert.equals(winreach#peek#read(l:id).cursor, 500)
endfunction

function! s:suite.a_key_closes_the_peek_when_the_far_window_has_gone() abort
  let l:id = s:far()
  call winreach#peek#open(l:id)
  call win_execute(l:id, 'tabclose')
  call winreach#peek#key('refresh')
  call s:assert.equals(winreach#peek#winid(), 0)
endfunction

function! s:suite.q_closes_the_peek_and_leaves_the_far_window_alone() abort
  let l:id = s:far(500, 60)
  call winreach#peek#open(l:id)
  let l:before = s:truth(l:id)
  call winreach#peek#key('close')
  call s:assert.equals(winreach#peek#winid(), 0)
  call s:assert.equals(s:truth(l:id), l:before)
endfunction

function! s:suite.enter_closes_the_peek_and_goes_there() abort
  let l:id = s:far()
  call winreach#peek#open(l:id)
  call winreach#peek#key('enter')
  call s:assert.equals(winreach#peek#winid(), 0)
  call s:assert.equals(win_getid(), l:id)
  call s:assert.equals(tabpagenr(), 2)
endfunction

function! s:suite.keys_do_nothing_when_no_peek_is_open() abort
  let l:id = s:far(500, 60)
  let l:before = s:truth(l:id)
  call winreach#peek#key('bottom')
  call s:assert.equals(s:truth(l:id), l:before)
endfunction

" The peek window's actual contents, whichever kind of window it is.
function! s:shown() abort
  let l:id = winreach#peek#window()
  return l:id == 0 ? [] : getbufline(winbufnr(l:id), 1, '$')
endfunction

function! s:suite.the_peek_window_shows_what_render_produced() abort
  let l:id = s:far(500, 1)
  call winreach#peek#open(l:id)
  let l:shown = s:shown()
  call s:assert.compare(len(l:shown), '>', 2)
  let l:d = winreach#peek#read(l:id)
  call s:assert.equals(l:shown,
        \ winreach#peek#render(l:d, len(l:shown[1]), len(l:shown)))
  call s:assert.match(l:shown[0], 'win ' . l:id . '  tab 2')
  " the far window's cursor is on line 1, so line 1 is the marked one
  call s:assert.match(l:shown[2], '^>\s*1 log line 1$')
endfunction

function! s:suite.the_peek_window_follows_the_far_window_when_it_scrolls() abort
  let l:id = s:far(500, 1)
  call winreach#peek#open(l:id)
  call s:assert.match(s:shown()[2], '^>\s*1 log line 1$')
  call winreach#peek#key('bottom')
  call s:assert.compare(winreach#peek#read(l:id).top, '>', 1)
  " The last line is the one the far cursor is on, and it is still there
  " whether or not the whole view fitted.
  call s:assert.equals(s:shown()[-1], '>500 log line 500')
  " Every row is consecutive and the header names the range being shown.
  let l:shown = s:shown()
  let l:first = str2nr(matchstr(l:shown[2], '\d\+'))
  call s:assert.compare(l:first, '>', 1)
  call s:assert.match(l:shown[0], printf('%d-500/500', l:first))
  " Vim's batch harness pins topline to the cursor line, so there is only
  " one line to show there; where there is more, it runs consecutively.
  if len(l:shown) > 3
    call s:assert.equals(l:shown[3], printf(' %d log line %d',
          \ l:first + 1, l:first + 1))
  endif
endfunction

function! s:suite.the_peek_window_is_not_one_of_the_windows_it_can_show() abort
  let l:id = s:far()
  call winreach#peek#open(l:id)
  call s:assert.not_equals(winreach#peek#window(), 0)
  call s:assert.equals(winreach#winref#get(winreach#peek#window()), {})
  call winreach#peek#close()
  call s:assert.equals(winreach#peek#window(), 0)
endfunction

" ---------------------------------------------------------------------------
" keys
" ---------------------------------------------------------------------------
"
" A Vim popup receives the raw character through a filter; a Neovim float
" gets buffer-local mappings and needs the key notation.  Both spellings
" come from one table, so the table is what is worth checking.

let s:scope = themis#helper('scope')
let s:sfuncs = s:scope.funcs('autoload/winreach/peek.vim')
let s:svars = s:scope.vars('autoload/winreach/peek.vim')

function! s:suite.every_key_in_the_table_names_an_action_that_exists() abort
  let l:known = keys(s:svars.MOTION) + ['refresh', 'enter', 'close']
  call s:assert.compare(len(s:svars.KEYS), '>', 10)
  for [l:notation, l:action] in s:svars.KEYS
    call s:assert.not_equals(index(l:known, l:action), -1,
          \ printf('%s is mapped to unknown action %s', l:notation, l:action))
  endfor
endfunction

function! s:suite.notation_becomes_the_character_a_popup_filter_receives() abort
  let l:Raw = s:sfuncs.raw
  call s:assert.equals(l:Raw('j'), 'j')
  call s:assert.equals(l:Raw('G'), 'G')
  call s:assert.equals(l:Raw('<C-e>'), "\<C-e>")
  call s:assert.equals(l:Raw('<CR>'), "\<CR>")
  call s:assert.equals(l:Raw('<Esc>'), "\<Esc>")
  " and every notation in the table survives the trip
  for [l:notation, l:_] in s:svars.KEYS
    call s:assert.not_equals(l:Raw(l:notation), '')
  endfor
endfunction

function! s:suite.a_key_arriving_at_the_filter_drives_the_far_window() abort
  let l:id = s:far(500, 1)
  call winreach#peek#open(l:id)
  call s:assert.equals(s:sfuncs.filter(winreach#peek#window(), 'G'), 1)
  call s:assert.equals(winreach#peek#read(l:id).cursor, 500)
  call s:assert.equals(s:sfuncs.filter(winreach#peek#window(), 'g'), 1)
  call s:assert.equals(winreach#peek#read(l:id).cursor, 1)
  call s:assert.equals(s:sfuncs.filter(winreach#peek#window(), 'q'), 1)
  call s:assert.equals(winreach#peek#winid(), 0)
endfunction

function! s:suite.the_filter_swallows_a_key_it_has_no_use_for() abort
  let l:id = s:far(500, 60)
  call winreach#peek#open(l:id)
  let l:before = s:truth(l:id)
  " not passed through to whatever is underneath: the peek is on top of it
  call s:assert.equals(s:sfuncs.filter(winreach#peek#window(), 'Z'), 1)
  call s:assert.not_equals(winreach#peek#winid(), 0)
  call s:assert.equals(s:truth(l:id), l:before)
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

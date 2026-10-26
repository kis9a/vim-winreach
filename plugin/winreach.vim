" winreach - reach every window without going there

if exists('g:loaded_winreach')
  finish
endif
let g:loaded_winreach = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

" :Winmap {cmd}   apply {cmd} to every window in every tab page, aborting at
"                 the first window where it fails
" :Winmap! {cmd}  visit the remaining windows anyway and report a summary
command! -bang -nargs=+ -complete=command Winmap
      \ call winreach#command#map('<bang>', <q-args>)

" :Winlist  every window in every tab page, read without going there.
"           <CR> jumps to a window, p peeks into it, q closes the list.
command! -bar Winlist call winreach#list#open()

" :Winpeek [{id} | {name}]
"   draw what another window is showing right now -- its lines, its scroll
"   position, its cursor -- in a popup, without going there, and scroll it
"   from here.  <CR> goes there, q closes the peek.
command! -bar -nargs=? -complete=customlist,winreach#peek#complete Winpeek
      \ call winreach#peek#open(<q-args>)

" :Winsave [name] / :Winrestore [name]
"   save the current tab page's layout (tree, buffers, sizes, views) and put
"   it back.  :Winrestore replaces the current tab page's layout.
command! -bar -nargs=? -complete=customlist,winreach#tree#complete Winsave
      \ call winreach#tree#save(<q-args>)
command! -bar -nargs=? -complete=customlist,winreach#tree#complete Winrestore
      \ call winreach#tree#restore(<q-args>)

" :Winundo  put back the layout remembered just before the last window was
"           closed (WinClosed fires while the window is still there).
"           Set g:winreach_remember = 0 to keep winreach out of autocmds.
command! -bar Winundo call winreach#tree#undo()

" :Winheight / :Winwidth {N | N% | +N | -N}
"   :resize takes what it needs from whichever window is adjacent.  These
"   take it from everyone sharing that axis, in proportion to what they had,
"   and remember the layout first so :Winundo takes it back.
command! -bar -nargs=1 Winheight call winreach#size#set('height', <q-args>)
command! -bar -nargs=1 Winwidth  call winreach#size#set('width', <q-args>)

if get(g:, 'winreach_remember', 1) && exists('##WinClosed')
  augroup winreach_remember
    autocmd!
    autocmd WinClosed * call winreach#tree#remember()
  augroup END
endif

let &cpoptions = s:save_cpo
unlet s:save_cpo

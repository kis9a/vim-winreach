" winreach#command - :Winmap entry point

let s:save_cpo = &cpoptions
set cpoptions&vim

" :Winmap[!] {cmd}
function! winreach#command#map(bang, cmd) abort
  return winreach#map(a:cmd, {'keep_going': a:bang ==# '!' ? v:true : v:false})
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

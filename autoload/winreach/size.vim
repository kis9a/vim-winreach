" winreach#size - resize a window without crushing one neighbour
"
" :resize takes what it needs from whichever window is adjacent, so growing
" one window by six lines can leave the next one at one line while a third
" barely moves.  What Vim decides correctly is *which* windows are affected:
" along a given axis that is the set of children of the nearest ancestor
" whose type matches the axis, which is why this needs the layout tree and
" not just a list of windows.  What it decides badly is how much each of
" them gives up.  Here they give up in proportion to what they had.

let s:save_cpo = &cpoptions
set cpoptions&vim

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

" winlayout() with a parent link on every node, so a leaf can walk upwards.
function! s:tree(...) abort
  let l:node = a:0 > 0 ? a:1 : winlayout()
  let l:out = l:node[0] ==# 'leaf'
        \ ? {'type': 'leaf', 'winid': l:node[1]}
        \ : {'type': l:node[0],
        \    'children': map(copy(l:node[1]), {_, v -> s:tree(v)})}
  for l:child in get(l:out, 'children', [])
    let l:child.parent = l:out
  endfor
  return l:out
endfunction

function! s:find_leaf(node, winid) abort
  if a:node.type ==# 'leaf'
    return a:node.winid == a:winid ? a:node : {}
  endif
  for l:child in a:node.children
    let l:hit = s:find_leaf(l:child, a:winid)
    if !empty(l:hit)
      return l:hit
    endif
  endfor
  return {}
endfunction

" Any leaf below this node; every leaf of a subtree shares the subtree's
" extent along the axis its parent splits, so one is enough to measure and
" to resize by.
function! s:a_leaf(node) abort
  let l:cur = a:node
  while l:cur.type !=# 'leaf'
    let l:cur = l:cur.children[0]
  endwhile
  return l:cur.winid
endfunction

" The children of the nearest ancestor that splits along this axis, plus
" which of them contains winid.  {} when nothing above splits that way --
" a single window, or asking for height in a layout that only splits
" left to right.
function! s:pool(winid, axis) abort
  let l:leaf = s:find_leaf(s:tree(), a:winid)
  if empty(l:leaf)
    return {}
  endif
  let l:node = l:leaf
  while has_key(l:node, 'parent')
    let l:parent = l:node.parent
    if l:parent.type ==# a:axis
      return {'siblings': l:parent.children,
            \ 'index': index(l:parent.children, l:node)}
    endif
    let l:node = l:parent
  endwhile
  return {}
endfunction

function! s:measure(node, dim) abort
  let l:winid = s:a_leaf(a:node)
  return a:dim ==# 'height' ? winheight(win_id2win(l:winid))
        \ : winwidth(win_id2win(l:winid))
endfunction

" want may be a number, a percentage of what the pool holds, or a signed
" delta -- the three ways people actually say it.
function! s:target(spec, current, total) abort
  let l:s = trim(a:spec)
  if l:s =~# '^[+-]\d\+$'
    return a:current + str2nr(l:s)
  endif
  if l:s =~# '^\d\+%$'
    return float2nr(round(a:total * str2nr(l:s) / 100.0))
  endif
  if l:s =~# '^\d\+$'
    return str2nr(l:s)
  endif
  return -1
endfunction

" dim: 'height' | 'width'
function! winreach#size#set(dim, spec) abort
  if !winreach#winref#available() || !exists('*winlayout')
    call s:notify('error', 'this build cannot read the window layout')
    return v:false
  endif
  let l:axis = a:dim ==# 'height' ? 'col' : 'row'
  let l:pool = s:pool(win_getid(), l:axis)
  if empty(l:pool) || len(l:pool.siblings) < 2
    call s:notify('warn', printf('nothing to share %s with here', a:dim))
    return v:false
  endif

  let l:sizes = map(copy(l:pool.siblings), {_, v -> s:measure(v, a:dim)})
  let l:total = 0
  for l:s in l:sizes
    let l:total += l:s
  endfor
  let l:want = s:target(a:spec, l:sizes[l:pool.index], l:total)
  if l:want < 1
    call s:notify('error', 'want a number, a percentage, or +N / -N, not '
          \ . string(a:spec))
    return v:false
  endif

  " Everyone else needs at least one line or column left
  let l:others = filter(range(len(l:sizes)), 'v:val != l:pool.index')
  let l:want = min([l:want, l:total - len(l:others)])
  if l:want == l:sizes[l:pool.index]
    return v:true
  endif

  " Remembered before the change, so :Winundo takes it back
  call winreach#tree#remember({'force': v:true})

  let l:left = l:total - l:want
  let l:pool_before = l:total - l:sizes[l:pool.index]
  let l:new = copy(l:sizes)
  let l:new[l:pool.index] = l:want
  let l:acc = 0
  for l:k in range(len(l:others))
    let l:j = l:others[l:k]
    if l:k == len(l:others) - 1
      let l:new[l:j] = l:left - l:acc
    else
      let l:new[l:j] = max([1,
            \ float2nr(round(l:sizes[l:j] * 1.0 * l:left / l:pool_before))])
      let l:acc += l:new[l:j]
    endif
  endfor

  " Twice: an early resize can be clamped by what has not been shrunk yet
  let l:cmd = a:dim ==# 'height' ? 'resize ' : 'vertical resize '
  for l:pass in [1, 2]
    for l:j in range(len(l:pool.siblings))
      call winreach#winref#execute(s:a_leaf(l:pool.siblings[l:j]),
            \ l:cmd . l:new[l:j])
    endfor
  endfor
  return v:true
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" winreach - reach every window without going there
"
" :tabdo windo has to actually visit each tab page and window, so the walk
" itself moves the cursor, changes the current tab page, discards the
" previous-window and alternate-buffer marks, and fires the window and buffer
" autocommands of every stop along the way.  win_execute() spans tab pages
" without any of that, so the traversal here has no side effects of its own
" -- only the command being applied does.

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

" Windows to visit, in a stable order: by tab page, then by the order
" getwininfo() reports within the tab.  Popups and floating windows are
" outside winref's managed domain and are never visited.
function! s:targets() abort
  return sort(winreach#winref#find({}), {a, b -> a.tabnr - b.tabnr})
endfunction

" Where a window is *now*, for reporting.  The snapshot's tabnr goes stale the
" moment the command adds or removes a tab page, so a failure would otherwise
" name a tab that has since moved or ceased to exist.
function! s:locate(winid, fallback_tabnr) abort
  let l:info = winreach#winref#get(a:winid)
  return empty(l:info) ? a:fallback_tabnr : l:info.tabnr
endfunction

function! s:describe(entry) abort
  return printf('tab %d winid %d: %s',
        \ a:entry.tabnr, a:entry.winid, a:entry.error)
endfunction

" Apply an Ex command to every managed window in every tab page.
"
" The window list is snapshotted first, so a command that opens windows does
" not have them swept too, and one that closes windows does not make the walk
" stumble over the gaps -- a window that is gone by its turn is skipped.
"
" opts.keep_going: v:false (default) stops at the first failing window and
" reports where; v:true visits the rest and reports a summary.
"
" Returns {'visited', 'skipped', 'remaining', 'failed': [{'winid', 'tabnr',
" 'error', 'throwpoint'}]}.  'remaining' is what an early stop did not reach.
function! winreach#map(cmd, ...) abort
  let l:result = {'visited': 0, 'skipped': 0, 'remaining': 0, 'failed': []}

  let l:opts = a:0 > 0 && type(a:1) == type({}) ? a:1 : {}
  let l:keep_going = get(l:opts, 'keep_going', v:false)
  if type(l:keep_going) != type(0) && type(l:keep_going) != type(v:true)
    call s:notify('warn', "opts.keep_going must be a Number or Boolean; ignoring "
          \ . string(l:keep_going))
    let l:keep_going = v:false
  endif

  if !winreach#winref#available('execute')
    call s:notify('error', 'this build is missing a builtin winreach needs'
          \ . ' (getwininfo/win_execute)')
    return l:result
  endif
  if type(a:cmd) != type('') || empty(trim(a:cmd))
    call s:notify('error', 'no command given')
    return l:result
  endif

  let l:targets = s:targets()
  let l:total = len(l:targets)
  let l:i = 0

  for l:info in l:targets
    let l:i += 1
    " The command may have closed this window since the snapshot
    if empty(winreach#winref#get(l:info.winid))
      let l:result.skipped += 1
      continue
    endif
    try
      " execute() reports v:false when it did nothing after all
      if winreach#winref#execute(l:info.winid, a:cmd)
        let l:result.visited += 1
      else
        let l:result.skipped += 1
      endif
    catch /^Vim:Interrupt$/
      " Ctrl-C must stop the walk, not become one more per-window failure.
      " Vim refuses to rethrow a 'Vim' -prefixed exception (E608), so the
      " loop ends here instead and says so.
      let l:result.remaining = l:total - l:i
      call s:notify('warn', printf('interrupted; %d window%s not reached',
            \ l:result.remaining, l:result.remaining == 1 ? '' : 's'))
      return l:result
    catch
      let l:entry = {
            \ 'winid': l:info.winid,
            \ 'tabnr': s:locate(l:info.winid, l:info.tabnr),
            \ 'error': v:exception,
            \ 'throwpoint': v:throwpoint,
            \ }
      call add(l:result.failed, l:entry)
      if !l:keep_going
        let l:result.remaining = l:total - l:i
        call s:notify('error', s:describe(l:entry))
        return l:result
      endif
    endtry
  endfor

  if !empty(l:result.failed)
    call s:notify('warn', printf('%d of %d window%s failed',
          \ len(l:result.failed), l:total, l:total == 1 ? '' : 's'))
  endif
  return l:result
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo

" Guard for the vendored copy of winref.
"
" VENDORED from kis9a/vim-winref; do not edit here.
" Regenerate with 'make vendor' in the vim-winref checkout.
"
" Host-agnostic on purpose: the copy is found by globbing
" autoload/*/winref.vim, and the namespace is read off the directory name,
" so the same file works unchanged in every consumer.
"
" Two independent checks, because the two failure modes have different
" preconditions:
"
"   integrity  -- the copy still hashes to what generation recorded in its
"                 own header.  Needs nothing but the copy, so it NEVER
"                 skips: a hand edit fails everywhere, including in a CI
"                 job that has no vim-winref checkout.
"
"   freshness  -- the src digest in the header matches the canonical file.
"                 Needs the canonical checkout, so it skips cleanly when
"                 the consumer is used standalone.  `make vendor-check` in
"                 vim-winref is the no-skip counterpart of this one.

let s:suite = themis#suite('vendored winref')
let s:assert = themis#helper('assert')

let s:root = expand('<sfile>:p:h:h')

" ---------------------------------------------------------------------------

function! s:copy_path() abort
  let l:hits = glob(s:root . '/autoload/*/winref.vim', 1, 1)
  return empty(l:hits) ? '' : l:hits[0]
endfunction

function! s:namespace(path) abort
  return fnamemodify(a:path, ':p:h:t')
endfunction

" sha256 of the bytes readfile() would have read: lines joined with NL and a
" trailing NL, which is what a POSIX text file holds.
function! s:sha_lines(lines) abort
  return sha256(join(a:lines, "\n") . "\n")
endfunction

function! s:header(lines) abort
  let l:m = matchlist(get(a:lines, 2, ''),
        \ '^" winref-vendor: src=\(\x\{64}\) body=\(\x\{64}\)$')
  return empty(l:m) ? {} : {'src': l:m[1], 'body': l:m[2]}
endfunction

" First readable canonical autoload/winref.vim, or '' when none is on disk.
" $WINREF_SRC, when set, is authoritative in both directions: it points the
" check at a checkout in a non-standard place, and setting it to a path that
" does not exist forces the skip branch (used by the guard's own tests).
function! s:canonical() abort
  if !empty($WINREF_SRC)
    return filereadable($WINREF_SRC) ? $WINREF_SRC : ''
  endif
  let l:cands = [fnamemodify(s:root, ':h') . '/vim-winref/autoload/winref.vim']
  call extend(l:cands, split(globpath(&runtimepath, 'autoload/winref.vim'), "\n"))
  for l:c in l:cands
    if filereadable(l:c)
      return l:c
    endif
  endfor
  return ''
endfunction

let s:REGEN = "  regenerate: cd <vim-winref checkout> && make vendor"

" ---------------------------------------------------------------------------

function! s:suite.the_copy_exists() abort
  call s:assert.not_equals(s:copy_path(), '',
        \ 'no autoload/*/winref.vim under ' . s:root)
endfunction

" Never skips.
function! s:suite.is_generated_not_hand_edited() abort
  let l:path = s:copy_path()
  call s:assert.not_equals(l:path, '')
  call s:assert.true(exists('*sha256'), 'sha256() is unavailable')

  let l:lines = readfile(l:path)
  let l:h = s:header(l:lines)
  call s:assert.false(empty(l:h),
        \ join([l:path . ' has no "winref-vendor:" header line.',
        \ '  It predates the vendor guard, or the header was edited.',
        \ s:REGEN], "\n"))

  let l:got = s:sha_lines(l:lines[3:])
  call s:assert.equals(l:got, l:h.body,
        \ join([l:path . ' was edited in place after it was generated.',
        \ '  header body=' . l:h.body,
        \ '  actual body=' . l:got,
        \ '  Edit autoload/winref.vim in vim-winref instead, then',
        \ s:REGEN], "\n"))
endfunction

" Never skips: proves the sed transform left no un-namespaced call behind,
" which would resolve to whichever plugin won autoload/winref.vim on 'rtp'.
function! s:suite.has_no_unnamespaced_calls() abort
  let l:path = s:copy_path()
  let l:ns = s:namespace(l:path)
  let l:lines = readfile(l:path)
  let l:bad = []
  for l:i in range(3, len(l:lines) - 1)
    if stridx(substitute(l:lines[l:i], l:ns . '#winref#', '', 'g'), 'winref#') >= 0
      call add(l:bad, (l:i + 1) . ': ' . l:lines[l:i])
    endif
  endfor
  call s:assert.equals(l:bad, [],
        \ join(['un-namespaced winref# in ' . l:path] + l:bad, "\n"))
endfunction

" Skips when the canonical checkout is not on disk.
function! s:suite.matches_the_canonical_source() abort
  let l:canon = s:canonical()
  if empty(l:canon)
    call s:assert.skip('vim-winref checkout not on disk; '
          \ . 'set $WINREF_SRC or run `make vendor-check` in vim-winref')
  endif

  let l:path = s:copy_path()
  let l:h = s:header(readfile(l:path))
  call s:assert.false(empty(l:h), l:path . ' has no "winref-vendor:" header line')

  let l:want = s:sha_lines(readfile(l:canon))
  call s:assert.equals(l:h.src, l:want,
        \ join([l:path . ' is STALE with respect to ' . l:canon . '.',
        \ '  copy was cut from src=' . l:h.src,
        \ '  canonical is now  src=' . l:want,
        \ s:REGEN], "\n"))
endfunction

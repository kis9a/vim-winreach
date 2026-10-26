" Syntax for the :Winlist buffer

if exists('b:current_syntax')
  finish
endif

syntax match winreachListTab     '^tab \d\+$'
syntax match winreachListCurrent '^  >.*$'
syntax match winreachListWinid   '\%(^  [ >] \)\@<=\d\+'
syntax match winreachListSize    '\%(^  [ >] \d\+ \+\)\@<=\d\+x\d\+'
syntax match winreachListFlags   '\[[^]]*\]$'

highlight default link winreachListTab     Title
highlight default link winreachListCurrent CursorLineNr
highlight default link winreachListWinid   Number
highlight default link winreachListSize    Comment
highlight default link winreachListFlags   Special

let b:current_syntax = 'winreachlist'

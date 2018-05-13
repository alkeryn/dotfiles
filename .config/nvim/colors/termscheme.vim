" File: termscheme.vim
" Version: 1.0
" Author: hickop <hickop@gmail.com>
" Description: vim terminal colorscheme based on user .Xresources colors.

hi clear

if exists("syntax_on")
    syntax reset
endif

let g:colors_name="termscheme"

hi Normal       ctermfg=15      ctermbg=NONE

hi SpecialKey   ctermfg=4
hi NonText      ctermfg=7                       cterm=NONE
hi Directory    ctermfg=4
hi ErrorMsg     ctermfg=0       ctermbg=1
hi IncSearch    ctermfg=0       ctermbg=fg      cterm=NONE
hi Search       ctermfg=0       ctermbg=3
hi MoreMsg      ctermfg=fg                      cterm=NONE
hi LineNr       ctermfg=7       ctermbg=8
hi CursorLineNr ctermfg=fg      ctermbg=8
hi Question     ctermfg=fg                      cterm=NONE
hi StatusLine   ctermfg=fg      ctermbg=8       cterm=NONE
hi StatusLineNC ctermfg=7       ctermbg=8       cterm=NONE
hi VertSplit    ctermfg=236     ctermbg=236     cterm=NONE
hi Title        ctermfg=fg                      cterm=NONE
hi Visual       ctermfg=0       ctermbg=fg
hi WarningMsg   ctermfg=fg                      cterm=NONE
hi WildMenu     ctermfg=0       ctermbg=3
hi Folded       ctermfg=fg      ctermbg=8
hi FoldColumn   ctermfg=fg      ctermbg=8
hi DiffAdd      ctermfg=fg      ctermbg=6
hi DiffChange   ctermfg=fg      ctermbg=4
hi DiffDelete   ctermfg=0       ctermbg=1       cterm=NONE
hi DiffText     ctermfg=fg      ctermbg=6       cterm=NONE
hi SignColumn   ctermfg=fg      ctermbg=NONE
hi Pmenu        ctermfg=fg      ctermbg=236
hi PmenuSel     ctermfg=fg      ctermbg=6
hi PmenuSbar                    ctermbg=236
hi PmenuThumb                   ctermbg=fg
hi TabLine      ctermfg=7       ctermbg=8       cterm=NONE
hi TabLineSel   ctermfg=fg      ctermbg=NONE    cterm=NONE
hi TabLineFill  ctermfg=0       ctermbg=8       cterm=NONE
hi Cursor                       ctermbg=4
hi CursorLine                   ctermbg=236     cterm=NONE
hi ColorColumn                  ctermbg=236     cterm=NONE

hi MatchParen   ctermfg=0       ctermbg=3
hi Comment      ctermfg=240
hi Constant     ctermfg=6
hi Error        ctermfg=0       ctermbg=3
hi Identifier   ctermfg=6                       cterm=NONE
hi PreProc      ctermfg=4                       cterm=NONE
hi Special      ctermfg=3
hi Statement    ctermfg=3                       cterm=NONE
hi Todo         ctermfg=5       ctermbg=NONE
hi Type         ctermfg=2                       cterm=NONE

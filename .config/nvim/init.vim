"Colors
set t_Co=256
set background=dark
set termguicolors

set number relativenumber
set numberwidth=1

set hlsearch "highlight search
set ignorecase "not case sensitive
set smartcase "case smart

"set foldmethod=syntax
"set clipboard=unnamedplus
set mouse=ni

"Indent settings

set autoindent                " always set autoindenting on
set copyindent                " copy Indentation

"File settings

set nobackup		" do not keep a backup file, use versions instead
set autoread
set encoding=utf-8
set fileencoding=utf-8 "write
set fileencodings=utf-8 "read
set bomb "unicode header
set binary "warning disable expandtab if set after

"Tabs settings

set shiftwidth=4 "tab indent size
" set tabstop=4 "tab display
set softtabstop=4 "insert tab
" set expandtab "tabs are space

call plug#begin('~/.vim/plugged')
"Auto complete

Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'zchee/deoplete-clang'
Plug 'carlitux/deoplete-ternjs', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'zchee/deoplete-jedi'
Plug 'zchee/deoplete-zsh'


Plug 'Shougo/neoinclude.vim' "also check completion in includes

Plug 'ternjs/tern_for_vim', { 'for': ['javascript', 'javascript.jsx'] , 'do' : 'npm install' }
Plug 'othree/jspc.vim', { 'for': ['javascript', 'javascript.jsx'] }

"Behavior
Plug 'Townk/vim-autoclose' "autclose brackets
Plug 'tpope/vim-surround' "Sourounding
Plug 'honza/vim-snippets' "snippets engine
Plug 'SirVer/ultisnips' "sippets

"Tools
Plug 'ervandew/supertab'
Plug 'scrooloose/nerdtree'
Plug 'junegunn/fzf.vim'
Plug 'ntpeters/vim-better-whitespace' "show when there is gross trailing whitespace
Plug 'tpope/vim-repeat' "repeat last command from plugin
Plug 'tpope/vim-commentary' "Comment shortcut
Plug 'KabbAmine/vCoolor.vim' " color picker

" Plug 'iago-lito/vim-visualMarks' "breaks '<<' indent
" Plug 'terryma/vim-multiple-cursors' " Multiple Cursors

"Looks
Plug 'luochen1990/rainbow' "rainbow highlight brackets
Plug 'lilydjwg/colorizer' " Colorize hexa or rgb
Plug 'neomake/neomake' "do full syntax checking for most languages
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'miyakogi/seiya.vim' "background transparent again
Plug 'kovetskiy/sxhkd-vim'

"Themes
Plug 'chriskempson/base16-vim'
Plug 'kaicataldo/material.vim'
Plug 'phanviet/vim-monokai-pro'

"Fancy
" Plug 'aurieh/discord.nvim', { 'do': ':UpdateRemotePlugins'}
" Plug 'anned20/vimsence' "discord
Plug 'mhinz/vim-startify' "A nice start menu
Plug 'vim-scripts/Color-Scheme-Explorer'

"Plug 'ryanoasis/vim-devicons' "Icons should always be last plugin
call plug#end()

syntax enable
colorscheme monokai_pro

tnoremap <Esc> <C-\><C-n>

"Variables
let mapleader = " "

let g:deoplete#enable_at_startup = 1
let g:AutoClosePumvisible = {"ENTER": "<C-Y>", "ESC": "<ESC>"} "fix autoclose breaking escape exit autocompletion
let g:NERDTreeDirArrowExpandable = '▸'
let g:NERDTreeDirArrowCollapsible = '▾'

let g:seiya_auto_enable=1
" Default value: ['ctermbg']
let g:seiya_target_groups = has('nvim') ? ['guibg'] : ['ctermbg']


let g:multi_cursor_use_default_mapping=0

" Default mapping
" let g:multi_cursor_start_word_key      = '<C-b>'
" let g:multi_cursor_select_all_word_key = '<A-n>'
" let g:multi_cursor_start_key           = 'g<C-n>'
" let g:multi_cursor_select_all_key      = 'g<A-n>'
" let g:multi_cursor_next_key            = '<C-b>'
" let g:multi_cursor_prev_key            = '<C-p>'
" let g:multi_cursor_skip_key            = '<C-x>'
" let g:multi_cursor_quit_key            = '<Esc>'

"Shortcuts
noremap <C-n> :NERDTreeToggle<CR>
nnoremap <C-_> :noh<CR>
nnoremap <C-ç> :set hlsearch!<CR>
nnoremap Q <nop> "Disable annoying EX mode
let g:SuperTabDefaultCompletionType = "<c-n>"

"tab nav with shift
nnoremap <C-j> gT
nnoremap <C-k> gt
nnoremap <C-h> :tabm -1<CR>
nnoremap <C-l> :tabm +1<CR>
nnoremap tn :tabnew<CR>
nnoremap tq :tabclose<CR>
"splits
nnoremap <A-h> <C-w>h
nnoremap <A-j> <C-w>j
nnoremap <A-k> <C-w>k
nnoremap <A-l> <C-w>l

"Quick edit init.vim
nnoremap <leader>ev :vsplit $MYVIMRC<cr>
nnoremap <leader>sv :source $MYVIMRC<cr>

"Augroup
augroup AutoGroup
    au!
    " autocmd FileType javascript let g:SuperTabDefaultCompletionType = "<c-x><c-o>"
augroup END

augroup Binary
    au!
    au BufReadPre  *.bin let &bin=1
    au BufReadPost *.bin if &bin | %!xxd
    au BufReadPost *.bin set ft=xxd | endif
    au BufWritePre *.bin if &bin | %!xxd -r
    au BufWritePre *.bin endif
    au BufWritePost *.bin if &bin | %!xxd
    au BufWritePost *.bin set nomod | endif
augroup END

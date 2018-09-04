set t_Co=256

set background=dark
set termguicolors

set nobackup		" do not keep a backup file, use versions instead
set number relativenumber
set numberwidth=1
set hlsearch
set ignorecase
set smartcase

"set foldmethod=syntax
"set clipboard=unnamedplus
set mouse=ni

set autoindent                " always set autoindenting on
set copyindent                " copy Indentation
set autoread
nnoremap Q <nop> "Disable annoying EX mode

set encoding=utf-8
set fileencoding=utf-8
set fileencodings=utf-8
set bomb
set binary
set expandtab

syntax enable
call plug#begin('~/.vim/plugged')
"Auto complete

Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'zchee/deoplete-clang'
Plug 'carlitux/deoplete-ternjs', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'zchee/deoplete-jedi'

Plug 'zchee/deoplete-zsh'
Plug 'kovetskiy/sxhkd-vim'

Plug 'Shougo/neoinclude.vim' "also check completion in includes
"Plug 'Valloric/YouCompleteMe'


Plug 'ternjs/tern_for_vim', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'othree/jspc.vim', { 'for': ['javascript', 'javascript.jsx'] }
"Behavior
Plug 'Townk/vim-autoclose' "autclose brackets

"Tools
Plug 'ervandew/supertab'
Plug 'scrooloose/nerdtree'
Plug 'junegunn/fzf.vim'
Plug 'lilydjwg/colorizer' " Colorize hexa or rgb
Plug 'ntpeters/vim-better-whitespace' "show when there is gross trailing whitespace

Plug 'tpope/vim-surround' "Sourounding
Plug 'tpope/vim-repeat' "repat last command from plugin
Plug 'tpope/vim-commentary' "Comment shortcut

Plug 'iago-lito/vim-visualMarks'
" Plug 'terryma/vim-multiple-cursors' "Comment shortcut

Plug 'KabbAmine/vCoolor.vim' " color picker

Plug 'honza/vim-snippets' "snippets engine
Plug 'SirVer/ultisnips' "sippets

"Looks
Plug 'luochen1990/rainbow' "rainbow highlight brackets
Plug 'neomake/neomake' "do full syntax checking for most languages
Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'miyakogi/seiya.vim' "background transparent again

"Themes
Plug 'chriskempson/base16-vim'
Plug 'kaicataldo/material.vim'
Plug 'phanviet/vim-monokai-pro'

"Fancy
"Plug 'aurieh/discord.nvim', { 'do': ':UpdateRemotePlugins'}
Plug 'anned20/vimsence' "discord
Plug 'mhinz/vim-startify' "A nice start menu
Plug 'vim-scripts/Color-Scheme-Explorer'

"Plug 'ryanoasis/vim-devicons' "Icons should always be last plugin
call plug#end()

colorscheme monokai_pro

tnoremap <Esc> <C-\><C-n>

"Variables
let mapleader = "-"

autocmd FileType javascript let g:SuperTabDefaultCompletionType = "<c-x><c-o>"
let g:deoplete#enable_at_startup = 1

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

"tab nav with shift
nnoremap <C-J> gT
nnoremap <C-K> gt
nnoremap tn :tabnew<CR>
nnoremap tq :tabclose<CR>

nnoremap <leader>ev :vsplit $MYVIMRC<cr>
nnoremap <leader>sv :source $MYVIMRC<cr>

augroup Binary
  au!
  au BufReadPre  *.bin let &bin=1
  au BufReadPost *.bin if &bin | %!xxd
  au BufReadPost *.bin set ft=xxd | endif
  au BufWritePre *.bin if &bin | %!xxd -r
  au BufWritePre *.bin endif
  au BufWritePost *.bin if &bin | %!xxd
  au BufWritePost *.bin set nomod | endif
augroup END<Paste>

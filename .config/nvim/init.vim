set t_Co=256

set background=dark
set termguicolors

set nobackup		" do not keep a backup file, use versions instead
set number relativenumber
set numberwidth=1
set hlsearch
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
colorscheme elflord 
call plug#begin('~/.vim/plugged')
Plug 'scrooloose/nerdtree'
Plug 'vim-airline/vim-airline'

Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'zchee/deoplete-clang'
Plug 'Shougo/neoinclude.vim' "also check completion in includes

Plug 'carlitux/deoplete-ternjs', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'zchee/deoplete-zsh'

Plug 'ternjs/tern_for_vim', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'othree/jspc.vim', { 'for': ['javascript', 'javascript.jsx'] }

Plug 'ervandew/supertab'
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
Plug 'kovetskiy/sxhkd-vim'
Plug 'vim-airline/vim-airline-themes'
Plug 'aurieh/discord.nvim', { 'do': ':UpdateRemotePlugins'}
"Looks
Plug 'luochen1990/rainbow' "rainbow highlight brackets
Plug 'neomake/neomake' "do full syntax checking for most languages
"Tools
Plug 'KabbAmine/vCoolor.vim'
Plug 'lilydjwg/colorizer'
Plug 'ntpeters/vim-better-whitespace' "show when there is gross trailing whitespace
Plug 'mhinz/vim-startify' "A nice start menu
Plug 'tpope/vim-surround' 
Plug 'tpope/vim-repeat'

"Themes
Plug 'chriskempson/base16-vim'
Plug 'kaicataldo/material.vim'

Plug 'ryanoasis/vim-devicons' "Icons should always be last plugin
call plug#end()
map <C-n> :NERDTreeToggle<CR>
tnoremap <Esc> <C-\><C-n>

autocmd FileType javascript let g:SuperTabDefaultCompletionType = "<c-x><c-o>"
let g:deoplete#enable_at_startup = 1

let g:NERDTreeDirArrowExpandable = '▸'
let g:NERDTreeDirArrowCollapsible = '▾'

nmap <C-_> :noh<CR>
nmap <C-ç> :set hlsearch!<CR>

"tab nav with shift
nnoremap <C-J> gT
nnoremap <C-K> gt
nnoremap tn :tabnew<CR>
nnoremap tq :tabclose<CR>


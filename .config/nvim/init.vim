set t_Co=256
"set termguicolors

set nobackup		" do not keep a backup file, use versions instead
set number relativenumber
set numberwidth=1
set hlsearch
set smartcase
"set foldmethod=syntax
"set clipboard=unnamedplus
set mouse=a
set autoindent                " always set autoindenting on
syntax enable
colorscheme elflord 
call plug#begin('~/.vim/plugged')
Plug 'scrooloose/nerdtree'
Plug 'vim-airline/vim-airline'
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'zchee/deoplete-clang'
Plug 'carlitux/deoplete-ternjs', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'ternjs/tern_for_vim', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'othree/jspc.vim', { 'for': ['javascript', 'javascript.jsx'] }
Plug 'ervandew/supertab'
Plug 'SirVer/ultisnips'
Plug 'honza/vim-snippets'
Plug 'kovetskiy/sxhkd-vim'
Plug 'vim-airline/vim-airline-themes'
Plug 'aurieh/discord.nvim', { 'do': ':UpdateRemotePlugins'}
call plug#end()
map <C-n> :NERDTreeToggle<CR>
tnoremap <Esc> <C-\><C-n>

autocmd FileType javascript let g:SuperTabDefaultCompletionType = "<c-x><c-o>"
let g:deoplete#enable_at_startup = 1

let g:NERDTreeDirArrowExpandable = '▸'
let g:NERDTreeDirArrowCollapsible = '▾'

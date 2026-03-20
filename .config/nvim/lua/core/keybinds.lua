local fzf = require("fzf-lua")

local fzf_newtab = setmetatable({}, {
  __index = function(_, key)
    return function()
      fzf[key]({
        jump1_action = fzf.actions.file_tabedit,
        actions = {
          ["enter"] = fzf.actions.file_tabedit,
        }
      })
    end
  end
})

local k = vim.keymap
k.set('t', '<Esc>', '<C-\\><C-n>') -- terminal stuff
-- Shortcuts
k.set('n', '<C-n>', ':NERDTreeToggle<CR>')
k.set('n', '<C-_>', ':noh<CR>')
k.set('n', '<C-ç>', ':set hlsearch!<CR>')
k.set('n', 'Q', '<nop>') -- Disable annoying EX mode

-- Tab navigation with shift
k.set('n', '<C-j>', 'gT')
k.set('n', '<C-k>', 'gt')
k.set('n', '<C-h>', ':tabm -1<CR>')
k.set('n', '<C-l>', ':tabm +1<CR>')
k.set('n', 'tn', ':tabnew<CR>')
k.set('n', 'tq', ':tabclose<CR>')

-- Splits
k.set('n', '<A-h>', '<C-w>h')
k.set('n', '<A-j>', '<C-w>j')
k.set('n', '<A-k>', '<C-w>k')
k.set('n', '<A-l>', '<C-w>l')

-- Quick edit init.vim
k.set('n', '<leader>ev', ':vsplit $MYVIMRC<cr>')
k.set('n', '<leader>sv', ':source $MYVIMRC<cr>')
k.set('n', '<leader>w', ':w<cr>')
k.set('n', '<leader>q', ':q<cr>')
k.set('n', '<leader>Q', ':q!<cr>')
k.set('n', '<leader>j', fzf.files)
k.set('n', '<leader>J', fzf_newtab.files)
k.set('n', '<leader>t', fzf.tabs)
k.set('n', '<leader>b', fzf.builtin)
k.set('n', '<leader>n', fzf.live_grep_native)
k.set('n', '<leader>c', require("codecompanion").toggle)

-- Up down wrap line
k.set('n', 'k', 'gk', { silent = true })
k.set('n', 'j', 'gj', { silent = true })

vim.api.nvim_create_autocmd('LspAttach', {
    callback = function(args)
      local nmap = function(keys, func, desc)
        if desc then
          desc = 'LSP: ' .. desc
        end
        vim.keymap.set('n', keys, func, { buffer = args.buf, desc = desc })
      end

      nmap('<leader>d', fzf.lsp_declarations, 'Go to Declaration')
      nmap('<leader>f', fzf.lsp_definitions, 'Go to Definition')
      nmap('<leader>F', fzf_newtab.lsp_definitions, 'Go to definition, newtab')
      nmap('<leader>D', fzf.lsp_typedefs, 'Type Definition')
      nmap('K', vim.lsp.buf.hover, 'Hover Documentation')
      nmap('gi', fzf.lsp_implementations, 'Go to Implementation')
      nmap('<leader>x', fzf.lsp_references, 'Go to References')
      nmap('<leader>k', vim.lsp.buf.signature_help, 'Signature Help')
      nmap('<leader>wa', vim.lsp.buf.add_workspace_folder, 'Add Workspace Folder')
      nmap('<leader>wr', vim.lsp.buf.remove_workspace_folder, 'Remove Workspace Folder')
      nmap('<leader>wl', function() print(vim.inspect(vim.lsp.buf.list_workspace_folders())) end, 'List Workspace Folders')
      nmap('<leader>rn', vim.lsp.buf.rename, 'Rename')
      nmap('<leader>a', vim.lsp.buf.code_action, 'Code Action')
      nmap('<leader>=', function() vim.lsp.buf.format { async = true } end, 'Format')
    end,
  })


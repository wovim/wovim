-- Default user-commands, autocmds, mappings, menus.

local nvim_on = require('vim._core.util').nvim_on

--- Default user commands
do
  vim.api.nvim_create_user_command('Inspect', function(cmd)
    if cmd.bang then
      vim.print(vim.inspect_pos())
    else
      vim.show_pos()
    end
  end, { desc = 'Inspect highlights and extmarks at the cursor', bang = true })

  vim.api.nvim_create_user_command('InspectTree', function(cmd)
    local opts = { lang = cmd.fargs[1] }

    if cmd.mods ~= '' or cmd.count ~= 0 then
      local count = cmd.count ~= 0 and cmd.count or ''
      local new = cmd.mods ~= '' and 'new' or 'vnew'

      opts.command = ('%s %s%s'):format(cmd.mods, count, new)
    end

    vim.treesitter.inspect_tree(opts)
  end, { desc = 'Inspect treesitter language tree for buffer', count = true, nargs = '?' })

  vim.api.nvim_create_user_command('EditQuery', function(cmd)
    vim.treesitter.query.edit(cmd.fargs[1])
  end, {
    desc = 'Edit treesitter query',
    nargs = '?',
    complete = function()
      return vim.treesitter.language._complete()
    end,
  })

  vim.api.nvim_create_user_command('Open', function(cmd)
    if #cmd.fargs == 0 then
      local current_file = vim.fn.expand('%')
      if current_file ~= '' then
        vim.ui.open(current_file)
      end
    else
      vim.ui.open(cmd.fargs[1])
    end
  end, {
    desc = 'Open file with system default handler. See :help vim.ui.open()',
    nargs = '?',
    complete = 'file',
  })
end

--- Default mappings
do
  --- Default maps for * and # in visual mode.
  ---
  --- See |v_star-default| and |v_#-default|
  do
    local function _visual_search(forward)
      assert(forward == 0 or forward == 1)
      local pos = vim.fn.getpos('.')
      local vpos = vim.fn.getpos('v')
      local mode = vim.fn.mode()
      local chunks = vim.fn.getregion(pos, vpos, { type = mode })
      local esc_chunks = vim
        .iter(chunks)
        :map(function(v)
          return vim.fn.escape(v, [[\]])
        end)
        :totable()
      local esc_pat = table.concat(esc_chunks, [[\n]])
      if #esc_pat == 0 then
        vim.api.nvim_echo({ { 'E348: No string under cursor' } }, true, { err = true })
        return '<Esc>'
      end
      local search = [[\V]] .. esc_pat

      vim.fn.setreg('/', search)
      vim.fn.histadd('/', search)
      vim.v.searchforward = forward

      -- The count has to be adjusted when searching backwards and the cursor
      -- isn't positioned at the beginning of the selection
      local count = vim.v.count1
      if forward == 0 then
        local _, line, col, _ = unpack(pos)
        local _, vline, vcol, _ = unpack(vpos)
        if
          line > vline
          or mode == 'v' and line == vline and col > vcol
          or mode == 'V' and col ~= 1
          or mode == '\22' and col > vcol
        then
          count = count + 1
        end
      end
      return '<Esc>' .. count .. 'n'
    end

    vim.keymap.set('x', '*', function()
      return _visual_search(1)
    end, { desc = ':help v_star-default', expr = true })
    vim.keymap.set('x', '#', function()
      return _visual_search(0)
    end, { desc = ':help v_#-default', expr = true })
  end

  --- Map Y to y$. This mimics the behavior of D and C. See |Y-default|
  vim.keymap.set('n', 'Y', 'y$', { desc = ':help Y-default' })

  --- Use normal! <C-L> to prevent inserting raw <C-L> when using i_<C-O>. #17473
  ---
  --- See |CTRL-L-default|
  vim.keymap.set('n', '<C-L>', '<Cmd>nohlsearch<Bar>diffupdate<Bar>normal! <C-L><CR>', {
    desc = ':help CTRL-L-default',
  })

  --- Set undo points when deleting text in insert mode.
  ---
  --- See |i_CTRL-U-default| and |i_CTRL-W-default|
  vim.keymap.set('i', '<C-U>', '<C-G>u<C-U>', { desc = ':help i_CTRL-U-default' })
  vim.keymap.set('i', '<C-W>', '<C-G>u<C-W>', { desc = ':help i_CTRL-W-default' })

  --- Use the same flags as the previous substitution with &.
  ---
  --- Use : instead of <Cmd> so that ranges are supported. #19365
  ---
  --- See |&-default|
  vim.keymap.set('n', '&', ':&&<CR>', { desc = ':help &-default' })

  --- Use Q in Visual mode to execute a macro on each line of the selection. #21422
  --- This only make sense in linewise Visual mode. #28287
  ---
  --- Applies to @x and includes @@ too.
  vim.keymap.set(
    'x',
    'Q',
    "mode() ==# 'V' ? ':normal! @<C-R>=reg_recorded()<CR><CR>' : 'Q'",
    { silent = true, expr = true, desc = ':help v_Q-default' }
  )
  vim.keymap.set(
    'x',
    '@',
    "mode() ==# 'V' ? ':normal! @'.getcharstr().'<CR>' : '@'",
    { silent = true, expr = true, desc = ':help v_@-default' }
  )

  --- Map |gx| to call |vim.ui.open| on the `textDocument/documentLink` or <cfile> at cursor.
  do
    local function do_open(uri)
      local cmd, err = vim.ui.open(uri)
      local rv = cmd and cmd:wait(1000) or nil
      if cmd and rv and rv.code ~= 0 then
        err = ('vim.ui.open: command %s (%d): %s'):format(
          (rv.code == 124 and 'timeout' or 'failed'),
          rv.code,
          vim.inspect(cmd.cmd)
        )
      end
      return err
    end

    local gx_desc =
      'Opens filepath or URI under cursor with the system handler (file explorer, web browser, …)'
    vim.keymap.set({ 'n' }, 'gx', function()
      for _, url in ipairs(require('vim.ui')._get_urls()) do
        local err = do_open(url)
        if err then
          vim.notify(err, vim.log.levels.ERROR)
        end
      end
    end, { desc = gx_desc })
    vim.keymap.set({ 'x' }, 'gx', function()
      local lines =
        vim.fn.getregion(vim.fn.getpos('.'), vim.fn.getpos('v'), { type = vim.fn.mode() })
      -- Trim whitespace on each line and concatenate.
      local err = do_open(table.concat(vim.iter(lines):map(vim.trim):totable()))
      if err then
        vim.notify(err, vim.log.levels.ERROR)
      end
    end, { desc = gx_desc })
  end

  --- Default maps for built-in commenting.
  ---
  --- See |gc-default| and |gcc-default|.
  do
    local operator_rhs = function()
      return require('vim._comment').operator()
    end
    vim.keymap.set({ 'n', 'x' }, 'gc', operator_rhs, { expr = true, desc = 'Toggle comment' })

    local line_rhs = function()
      return require('vim._comment').operator() .. '_'
    end
    vim.keymap.set('n', 'gcc', line_rhs, { expr = true, desc = 'Toggle comment line' })

    local textobject_rhs = function()
      require('vim._comment').textobject()
    end
    vim.keymap.set({ 'o' }, 'gc', textobject_rhs, { desc = 'Comment textobject' })
  end

  --- Default maps for LSP functions.
  ---
  --- These are mapped unconditionally to avoid different behavior depending on whether an LSP
  --- client is attached. If no client is attached, or if a server does not support a capability, an
  --- error message is displayed rather than exhibiting different behavior.
  ---
  --- See |grr|, |grn|, |gra|, |gri|, |grt| |gO|, |i_CTRL-S|.
  do
    vim.keymap.set('n', 'grn', function()
      vim.lsp.buf.rename()
    end, { desc = 'vim.lsp.buf.rename()' })

    vim.keymap.set({ 'n', 'x' }, 'gra', function()
      vim.lsp.buf.code_action()
    end, { desc = 'vim.lsp.buf.code_action()' })

    vim.keymap.set('n', 'grx', function()
      vim.lsp.codelens.run()
    end, { desc = 'vim.lsp.codelens.run()' })

    vim.keymap.set('n', 'grr', function()
      vim.lsp.buf.references()
    end, { desc = 'vim.lsp.buf.references()' })

    vim.keymap.set('n', 'gri', function()
      vim.lsp.buf.implementation()
    end, { desc = 'vim.lsp.buf.implementation()' })

    vim.keymap.set('n', 'grt', function()
      vim.lsp.buf.type_definition()
    end, { desc = 'vim.lsp.buf.type_definition()' })

    vim.keymap.set('n', 'gO', function()
      vim.lsp.buf.document_symbol()
    end, { desc = 'vim.lsp.buf.document_symbol()' })

    vim.keymap.set({ 'i', 's' }, '<C-S>', function()
      vim.lsp.buf.signature_help()
    end, { desc = 'vim.lsp.buf.signature_help()' })
  end

  do
    ---@param direction vim.snippet.Direction
    ---@param key string
    local function set_snippet_jump(direction, key)
      vim.keymap.set({ 'i', 's' }, key, function()
        if vim.snippet.active({ direction = direction }) then
          return string.format('<Cmd>lua vim.snippet.jump(%d)<CR>', direction)
        else
          return key
        end
      end, {
        desc = 'vim.snippet.jump if active, otherwise ' .. key,
        expr = true,
        silent = true,
      })
    end

    set_snippet_jump(1, '<Tab>')
    set_snippet_jump(-1, '<S-Tab>')
  end

  --- Map [d and ]d to move to the previous/next diagnostic. Map <C-W>d to open a floating window
  --- for the diagnostic under the cursor.
  ---
  --- See |[d-default|, |]d-default|, and |CTRL-W_d-default|.
  do
    vim.keymap.set('n', ']d', function()
      vim.diagnostic.jump({ count = vim.v.count1 })
    end, { desc = 'Jump to the next diagnostic in the current buffer' })

    vim.keymap.set('n', '[d', function()
      vim.diagnostic.jump({ count = -vim.v.count1 })
    end, { desc = 'Jump to the previous diagnostic in the current buffer' })

    vim.keymap.set('n', ']D', function()
      vim.diagnostic.jump({ count = vim._maxint, wrap = false })
    end, { desc = 'Jump to the last diagnostic in the current buffer' })

    vim.keymap.set('n', '[D', function()
      vim.diagnostic.jump({ count = -vim._maxint, wrap = false })
    end, { desc = 'Jump to the first diagnostic in the current buffer' })

    vim.keymap.set('n', '<C-W>d', function()
      vim.diagnostic.open_float()
    end, { desc = 'Show diagnostics under the cursor' })

    vim.keymap.set(
      'n',
      '<C-W><C-D>',
      '<C-W>d',
      { remap = true, desc = 'Show diagnostics under the cursor' }
    )
  end

  --- Execute a command and print errors without a stacktrace.
  --- @param opts vim.api.keyset.cmd Arguments to |nvim_cmd()|
  local function cmd(opts)
    local ok, err = pcall(vim.api.nvim_cmd, opts, {})
    if not ok then
      vim.api.nvim_echo({ { require('vim._core.util').cmd_errmsg(err) } }, true, { err = true })
    end
  end

  --- vim-unimpaired style mappings. See: https://github.com/tpope/vim-unimpaired
  do
    -- Quickfix mappings
    vim.keymap.set('n', '[q', function()
      cmd({ cmd = 'cprevious', count = vim.v.count1 })
    end, { desc = ':cprevious' })

    vim.keymap.set('n', ']q', function()
      cmd({ cmd = 'cnext', count = vim.v.count1 })
    end, { desc = ':cnext' })

    vim.keymap.set('n', '[Q', function()
      cmd({ cmd = 'crewind', count = vim.v.count ~= 0 and vim.v.count or nil })
    end, { desc = ':crewind' })

    vim.keymap.set('n', ']Q', function()
      cmd({ cmd = 'clast', count = vim.v.count ~= 0 and vim.v.count or nil })
    end, { desc = ':clast' })

    vim.keymap.set('n', '[<C-Q>', function()
      cmd({ cmd = 'cpfile', count = vim.v.count1 })
    end, { desc = ':cpfile' })

    vim.keymap.set('n', ']<C-Q>', function()
      cmd({ cmd = 'cnfile', count = vim.v.count1 })
    end, { desc = ':cnfile' })

    -- Location list mappings
    vim.keymap.set('n', '[l', function()
      cmd({ cmd = 'lprevious', count = vim.v.count1 })
    end, { desc = ':lprevious' })

    vim.keymap.set('n', ']l', function()
      cmd({ cmd = 'lnext', count = vim.v.count1 })
    end, { desc = ':lnext' })

    vim.keymap.set('n', '[L', function()
      cmd({ cmd = 'lrewind', count = vim.v.count ~= 0 and vim.v.count or nil })
    end, { desc = ':lrewind' })

    vim.keymap.set('n', ']L', function()
      cmd({ cmd = 'llast', count = vim.v.count ~= 0 and vim.v.count or nil })
    end, { desc = ':llast' })

    vim.keymap.set('n', '[<C-L>', function()
      cmd({ cmd = 'lpfile', count = vim.v.count1 })
    end, { desc = ':lpfile' })

    vim.keymap.set('n', ']<C-L>', function()
      cmd({ cmd = 'lnfile', count = vim.v.count1 })
    end, { desc = ':lnfile' })

    -- Argument list
    vim.keymap.set('n', '[a', function()
      cmd({ cmd = 'previous', count = vim.v.count1 })
    end, { desc = ':previous' })

    vim.keymap.set('n', ']a', function()
      -- count doesn't work with :next, must use range. See #30641.
      cmd({ cmd = 'next', range = { vim.v.count1 } })
    end, { desc = ':next' })

    vim.keymap.set('n', '[A', function()
      if vim.v.count ~= 0 then
        cmd({ cmd = 'argument', count = vim.v.count })
      else
        cmd({ cmd = 'rewind' })
      end
    end, { desc = ':rewind' })

    vim.keymap.set('n', ']A', function()
      if vim.v.count ~= 0 then
        cmd({ cmd = 'argument', count = vim.v.count })
      else
        cmd({ cmd = 'last' })
      end
    end, { desc = ':last' })

    -- Tags
    vim.keymap.set('n', '[t', function()
      -- count doesn't work with :tprevious, must use range. See #30641.
      cmd({ cmd = 'tprevious', range = { vim.v.count1 } })
    end, { desc = ':tprevious' })

    vim.keymap.set('n', ']t', function()
      -- count doesn't work with :tnext, must use range. See #30641.
      cmd({ cmd = 'tnext', range = { vim.v.count1 } })
    end, { desc = ':tnext' })

    vim.keymap.set('n', '[T', function()
      -- count doesn't work with :trewind, must use range. See #30641.
      cmd({ cmd = 'trewind', range = vim.v.count ~= 0 and { vim.v.count } or nil })
    end, { desc = ':trewind' })

    vim.keymap.set('n', ']T', function()
      -- :tlast does not accept a count, so use :trewind if count given
      if vim.v.count ~= 0 then
        cmd({ cmd = 'trewind', range = { vim.v.count } })
      else
        cmd({ cmd = 'tlast' })
      end
    end, { desc = ':tlast' })

    vim.keymap.set('n', '[<C-T>', function()
      -- count doesn't work with :ptprevious, must use range. See #30641.
      cmd({ cmd = 'ptprevious', range = { vim.v.count1 } })
    end, { desc = ':ptprevious' })

    vim.keymap.set('n', ']<C-T>', function()
      -- count doesn't work with :ptnext, must use range. See #30641.
      cmd({ cmd = 'ptnext', range = { vim.v.count1 } })
    end, { desc = ':ptnext' })

    -- Buffers
    vim.keymap.set('n', '[b', function()
      cmd({ cmd = 'bprevious', count = vim.v.count1 })
    end, { desc = ':bprevious' })

    vim.keymap.set('n', ']b', function()
      cmd({ cmd = 'bnext', count = vim.v.count1 })
    end, { desc = ':bnext' })

    vim.keymap.set('n', '[B', function()
      if vim.v.count ~= 0 then
        cmd({ cmd = 'buffer', count = vim.v.count })
      else
        cmd({ cmd = 'brewind' })
      end
    end, { desc = ':brewind' })

    vim.keymap.set('n', ']B', function()
      if vim.v.count ~= 0 then
        cmd({ cmd = 'buffer', count = vim.v.count })
      else
        cmd({ cmd = 'blast' })
      end
    end, { desc = ':blast' })

    -- Add empty lines
    vim.keymap.set('n', '[<Space>', function()
      vim.go.operatorfunc = require('vim._core.util').space_above
      return 'g@l'
    end, { expr = true, desc = 'Add empty line above cursor' })

    vim.keymap.set('n', ']<Space>', function()
      vim.go.operatorfunc = require('vim._core.util').space_below
      return 'g@l'
    end, { expr = true, desc = 'Add empty line below cursor' })
  end

  --- "Incremental selection" mappings (treesitter + LSP fallback).
  do
    vim.keymap.set({ 'x' }, '[n', function()
      vim.treesitter.select('prev', vim.v.count1)
    end, { desc = 'Select previous node' })

    vim.keymap.set({ 'x' }, ']n', function()
      vim.treesitter.select('next', vim.v.count1)
    end, { desc = 'Select next node' })

    vim.keymap.set({ 'x' }, '[N', function()
      vim.treesitter.select('extend_prev', vim.v.count1)
    end, { desc = 'Select previous sibling node' })

    vim.keymap.set({ 'x' }, ']N', function()
      vim.treesitter.select('extend_next', vim.v.count1)
    end, { desc = 'Select next sibling node' })

    vim.keymap.set({ 'x', 'o' }, 'an', function()
      if vim.treesitter.get_parser(nil, nil, { error = false }) then
        vim.treesitter.select('parent', vim.v.count1)
      else
        vim.lsp.buf.selection_range(vim.v.count1)
      end
    end, { desc = 'Select parent (outer) node' })

    vim.keymap.set({ 'x', 'o' }, 'in', function()
      if vim.treesitter.get_parser(nil, nil, { error = false }) then
        vim.treesitter.select('child', vim.v.count1)
      else
        vim.lsp.buf.selection_range(-vim.v.count1)
      end
    end, { desc = 'Select child (inner) node' })
  end
end

--- Default menus
do
  --- Right click popup menu
  vim.cmd([[
    amenu     PopUp.Open\ in\ web\ browser  gx
    anoremenu PopUp.Inspect                 <Cmd>Inspect<CR>
    anoremenu PopUp.Go\ to\ definition      <Cmd>lua vim.lsp.buf.definition()<CR>
    anoremenu PopUp.Show\ Diagnostics       <Cmd>lua vim.diagnostic.open_float()<CR>
    anoremenu PopUp.Show\ All\ Diagnostics  <Cmd>lua vim.diagnostic.setqflist()<CR>
    anoremenu PopUp.Configure\ Diagnostics  <Cmd>help vim.diagnostic.config()<CR>
    anoremenu PopUp.-1-                     <Nop>
    vnoremenu PopUp.Cut                     "+x
    vnoremenu PopUp.Copy                    "+y
    anoremenu PopUp.Paste                   "+gP
    vnoremenu PopUp.Paste                   "+P
    vnoremenu PopUp.Delete                  "_x
    nnoremenu PopUp.Select\ All             ggVG
    vnoremenu PopUp.Select\ All             gg0oG$
    inoremenu PopUp.Select\ All             <C-Home><C-O>VG
    anoremenu PopUp.-2-                     <Nop>
    anoremenu PopUp.How-to\ disable\ mouse  <Cmd>help disable-mouse<CR>
  ]])

  local function enable_ctx_menu()
    vim.cmd([[
      amenu disable PopUp.Go\ to\ definition
      amenu disable PopUp.Open\ in\ web\ browser
      amenu disable PopUp.Show\ Diagnostics
      amenu disable PopUp.Show\ All\ Diagnostics
      amenu disable PopUp.Configure\ Diagnostics
    ]])

    local url = require('vim.ui')._get_urls()[1]
    if url and vim.startswith(url, 'http') then
      vim.cmd([[amenu enable PopUp.Open\ in\ web\ browser]])
    elseif vim.lsp.get_clients({ bufnr = 0 })[1] then
      vim.cmd([[anoremenu enable PopUp.Go\ to\ definition]])
    end

    local lnum = vim.fn.getcurpos()[2] - 1 ---@type integer
    local diagnostic = false
    if next(vim.diagnostic.get(0, { lnum = lnum })) ~= nil then
      diagnostic = true
      vim.cmd([[anoremenu enable PopUp.Show\ Diagnostics]])
    end

    if diagnostic or next(vim.diagnostic.count(0)) ~= nil then
      vim.cmd([[
        anoremenu enable PopUp.Show\ All\ Diagnostics
        anoremenu enable PopUp.Configure\ Diagnostics
      ]])
    end
  end

  local nvim_popupmenu_augroup = vim.api.nvim_create_augroup('nvim.popupmenu')
  nvim_on('MenuPopup', nvim_popupmenu_augroup, {
    pattern = '*',
    desc = 'Mouse popup menu',
    -- nested = true,
  }, function()
    enable_ctx_menu()
  end)
end

--- Default autocommands. See |default-autocmds|
do
  -- Warn if $NVIM_LOG_FILE or $XDG_STATE_HOME are inaccessible. #38039
  if vim.v.vim_did_enter then
    require('vim._core.log').check_log_file()
  else
    nvim_on('VimEnter', nil, { once = true }, function()
      require('vim._core.log').check_log_file()
    end)
  end

  local nvim_terminal_augroup = vim.api.nvim_create_augroup('nvim.terminal')
  vim.api.nvim_create_autocmd('BufReadCmd', {
    pattern = 'term://*',
    group = nvim_terminal_augroup,
    desc = 'Treat term:// buffers as terminal buffers',
    nested = true,
    command = "if !exists('b:term_title')|call jobstart(matchstr(expand(\"<amatch>\"), '\\c\\mterm://\\%(.\\{-}//\\%(\\d\\+:\\)\\?\\)\\?\\zs.*'), {'term': v:true, 'cwd': expand(get(matchlist(expand(\"<amatch>\"), '\\c\\mterm://\\(.\\{-}\\)//'), 1, ''))})",
  })

  nvim_on({ 'TermClose' }, nvim_terminal_augroup, {
    nested = true,
    desc = 'Automatically close terminal buffers when started with no arguments and exiting without an error',
  }, function(ev)
    if vim.v.event.status ~= 0 then
      return
    end
    local info = vim.api.nvim_get_chan_info(vim.bo[ev.buf].channel)
    local argv = info.argv or {}
    if table.concat(argv, ' ') == vim.o.shell then
      vim.api.nvim_buf_delete(ev.buf, { force = true })
    end
  end)

  local nvim_terminal_exitmsg_ns = vim.api.nvim_create_namespace('nvim.terminal.exitmsg')

  --- @param buf integer
  --- @param msg string
  --- @param pos integer
  local function set_terminal_exitmsg(buf, msg, pos)
    vim.api.nvim_buf_set_extmark(buf, nvim_terminal_exitmsg_ns, pos, 0, {
      virt_text = { { msg, nil } },
      virt_text_pos = 'overlay',
    })
  end

  nvim_on('TermClose', nvim_terminal_augroup, {
    nested = true,
    desc = 'Displays the "[Process exited]" virtual text',
  }, function(ev)
    if not vim.api.nvim_buf_is_valid(ev.buf) then
      return
    end

    local buf = vim.bo[ev.buf]
    local pos = ev.data.pos ---@type integer
    local buf_has_exitmsg = #(
        vim.api.nvim_buf_get_extmarks(ev.buf, nvim_terminal_exitmsg_ns, 0, -1)
      ) > 0

    -- `nvim_open_term` buffers do not have an attached 'channel'.
    local msg = buf.channel == 0 and '[Terminal closed]'
      or ('[Process exited %d]'):format(vim.v.event.status)

    if buf.buftype ~= 'terminal' or buf_has_exitmsg then
      -- TermClose may be queued before TermOpen if process exits before `terminal_open` is called.
      -- Don't display the msg now, let TermOpen display it.
      nvim_on('TermOpen', nil, {
        buf = ev.buf,
        once = true,
      }, function()
        set_terminal_exitmsg(ev.buf, msg, pos)
      end)
      return
    end
    set_terminal_exitmsg(ev.buf, msg, pos)
  end)

  nvim_on('TermRequest', nvim_terminal_augroup, {
    desc = 'Handles OSC foreground/background color requests',
  }, function(ev)
    --- @type integer
    local channel = vim.bo[ev.buf].channel
    if channel == 0 then
      return
    end
    local fg_request = ev.data.sequence == '\027]10;?'
    local bg_request = ev.data.sequence == '\027]11;?'
    if fg_request or bg_request then
      -- WARN: This does not return the actual foreground/background color,
      -- but rather returns:
      --   - fg=white/bg=black when Nvim option 'background' is 'dark'
      --   - fg=black/bg=white when Nvim option 'background' is 'light'
      local red, green, blue = 0, 0, 0
      local bg_option_dark = vim.o.background == 'dark'
      if (fg_request and bg_option_dark) or (bg_request and not bg_option_dark) then
        red, green, blue = 65535, 65535, 65535
      end
      local command = fg_request and 10 or 11
      local data =
        string.format('\027]%d;rgb:%04x/%04x/%04x%s', command, red, green, blue, ev.data.terminator)
      vim.api.nvim_chan_send(channel, data)
    end
  end)

  local nvim_terminal_prompt_ns = vim.api.nvim_create_namespace('nvim.terminal.prompt')
  nvim_on('TermRequest', nvim_terminal_augroup, {
    desc = 'Mark shell prompts indicated by OSC 133 sequences for navigation',
  }, function(ev)
    if string.match(ev.data.sequence, '^\027]133;A') then
      local lnum = ev.data.cursor[1] ---@type integer
      if lnum >= 1 then
        vim.api.nvim_buf_set_extmark(
          ev.buf,
          nvim_terminal_prompt_ns,
          lnum - 1,
          0,
          { right_gravity = false }
        )
      end
    end
  end)

  ---@param ns integer
  ---@param buf integer
  ---@param count integer
  local function jump_to_prompt(ns, win, buf, count)
    local row, col = unpack(vim.api.nvim_win_get_cursor(win))
    local start = -1
    local end_ ---@type 0|-1
    if count > 0 then
      start = row
      end_ = -1
    elseif count < 0 then
      -- Subtract 2 because row is 1-based, but extmarks are 0-based
      start = row - 2
      end_ = 0
    end

    if start < 0 then
      return
    end

    local extmarks = vim.api.nvim_buf_get_extmarks(
      buf,
      ns,
      { start, col },
      end_,
      { limit = math.abs(count) }
    )
    if #extmarks > 0 then
      local extmark = assert(extmarks[math.min(#extmarks, math.abs(count))])
      vim.api.nvim_win_set_cursor(win, { extmark[2] + 1, extmark[3] })
    end
  end

  nvim_on('TermOpen', nvim_terminal_augroup, {
    desc = 'Default settings for :terminal buffers',
  }, function(ev)
    vim.bo[ev.buf].modifiable = false
    vim.bo[ev.buf].undolevels = -1
    vim.bo[ev.buf].scrollback = vim.o.scrollback < 0 and 10000 or math.max(1, vim.o.scrollback)
    vim.bo[ev.buf].textwidth = 0
    vim.wo[0][0].wrap = false
    vim.wo[0][0].list = false
    vim.wo[0][0].number = false
    vim.wo[0][0].relativenumber = false
    vim.wo[0][0].signcolumn = 'no'
    vim.wo[0][0].foldcolumn = '0'

    -- This is gross. Proper list options support when?
    local winhl = vim.o.winhighlight
    if winhl ~= '' then
      winhl = winhl .. ','
    end
    vim.wo[0][0].winhighlight = winhl .. 'StatusLine:StatusLineTerm,StatusLineNC:StatusLineTermNC'

    vim.keymap.set({ 'n', 'x', 'o' }, '[[', function()
      jump_to_prompt(nvim_terminal_prompt_ns, 0, ev.buf, -vim.v.count1)
    end, { buf = ev.buf, desc = 'Jump [count] shell prompts backward' })
    vim.keymap.set({ 'n', 'x', 'o' }, ']]', function()
      jump_to_prompt(nvim_terminal_prompt_ns, 0, ev.buf, vim.v.count1)
    end, { buf = ev.buf, desc = 'Jump [count] shell prompts forward' })

    -- If the terminal buffer is being reused, clear the previous exit msg
    vim.api.nvim_buf_clear_namespace(ev.buf, nvim_terminal_exitmsg_ns, 0, -1)
  end)

  vim.api.nvim_create_autocmd('CmdwinEnter', {
    pattern = '[:>]',
    desc = 'Limit syntax sync to maxlines=1 in the command window',
    group = vim.api.nvim_create_augroup('nvim.cmdwin'),
    command = 'syntax sync minlines=1 maxlines=1',
  })

  nvim_on('SwapExists', vim.api.nvim_create_augroup('nvim.swapfile'), {
    pattern = '*',
    desc = 'Skip the swapfile prompt when the swapfile is owned by a running Nvim process',
  }, function()
    local info = vim.fn.swapinfo(vim.v.swapname)
    local user = vim.uv.os_get_passwd().username
    local iswin = 1 == vim.fn.has('win32')
    if info.error or info.pid <= 0 or (not iswin and info.user ~= user) then
      vim.v.swapchoice = '' -- Show the prompt.
      return
    end
    vim.v.swapchoice = 'e' -- Choose "(E)dit".
    vim.notify(
      ('W325: Ignoring swapfile from Nvim process %d'):format(info.pid),
      vim.log.levels.WARN,
      { _truncate = true }
    )
  end)

  -- Jump to the last-known cursor position when reopening a file, per the
  -- worked example at |restore-cursor|: skip an invalid mark, a commit or
  -- rebase message (it's a new one, not last time's), xxd(1)-filtered binary
  -- (see |using-xxd|), diff mode, or a cursor an earlier autocmd (a
  -- ftplugin, a user's own BufReadPost/FileType handler) already moved off
  -- line one. 'filetype' is already set by the time this runs -- it's
  -- BufWinEnter, which fires strictly after every BufReadPost handler,
  -- ftdetect's own BufReadPost autocmd (group "filetypedetect", what
  -- actually fires FileType) included, regardless of registration order.
  -- A later startup argument (+cmd,
  -- -c, -t, -q, -S) that moves the cursor is unaffected too, but by
  -- ordering, not by any check here: main.c runs all of those (exe_commands,
  -- handle_tag, qf_jump) *after* every window's own BufWinEnter, so a jump
  -- made here always executes first and is free to be overridden after.
  --
  -- BufWinEnter also fires for a plain switch to a buffer that's already
  -- loaded -- CTRL-^, CTRL-O/CTRL-I, :bprevious/:bnext, a 'hidden' buffer
  -- coming back into view -- none of which are "reopening a file" in the
  -- sense |restore-cursor| means. Those already have their own, more
  -- authoritative position/view restoration (native per-window cursor
  -- memory, |'jumpoptions'| "view"), and competing with it is worse than
  -- doing nothing: the cursor line can coincidentally end up right while
  -- the scroll position doesn't, since a plain g`" jump doesn't know what
  -- view was saved for a jumplist-style return. So this only fires right
  -- after a genuine read -- BufReadPost sets a per-buffer flag, BufWinEnter
  -- consumes and clears it, and a plain buffer-switch (no matching
  -- BufReadPost just before it) leaves the flag unset and does nothing.
  -- (:split on the same buffer never even fires BufWinEnter, so there's
  -- nothing to skip there either.) The flag is also cleared shortly after
  -- BufReadPost itself, in case that read has no BufWinEnter to consume it
  -- at all -- :checktime / 'autoread' reloads a changed buffer by calling
  -- readfile() directly (buf_reload() in fileio.c) in the buffer's own
  -- existing window (confirmed by direct trace: BufReadPost fires there
  -- with a real, non-synthetic window already current), not no window --
  -- but BufWinEnter still doesn't follow, since the window was already
  -- showing this buffer and nothing about *that* pairing changed. A flag
  -- left set from the reload would mislead the next unrelated BufWinEnter
  -- for the same buffer. (The clear is scheduled, not
  -- immediate, so it still loses to a switch made in the exact same tick as
  -- the reload -- not reachable through normal interactive use, since a
  -- reload's own trigger, e.g. CursorHold, is never in the same tick as
  -- whatever switches buffers next.)
  --
  -- Two of Nvim's own startup-sequencing quirks additionally race a
  -- restore made straight from BufWinEnter, and both are worked around
  -- rather than deferred -- deferring the decision to VimEnter was tried
  -- and reverted: every startup argument above also runs *before* VimEnter,
  -- so a VimEnter-time jump would just as happily override one of *those*,
  -- exactly the failure this design avoids by running first instead.
  --
  -- - Opening the same file in two windows at once ("nvim -o f f") reuses
  --   one buffer, and Nvim unloads+rereads it for the second window --
  --   which writes the |'"| mark from that window's own (still line-1)
  --   cursor, clobbering the mark before its BufWinEnter can read it. Worked
  --   around by caching the mark on BufReadPost, before anything can
  --   clobber it, and preferring that cache over the live mark -- but only
  --   for a read that's actually part of *this* startup's own file argument
  --   list, not merely "still starting up": Nvim's unload+reread writes the
  --   buffer's own cursor into the mark as part of leaving it, and a later,
  --   unrelated reread of the same buffer (a startup -c command that
  --   explicitly rereads a file already named on the argument list, even in
  --   a brand new window, say) does the exact same thing to the mark --
  --   indistinguishable from the race by its mark, cursor, or window alone.
  --   What *does* distinguish them: |argv()|, at the moment this file loads
  --   (before a single window exists), already lists every file the
  --   argument list is *going* to open, duplicates and all -- so each entry
  --   can be claimed off, once, by the read it actually belongs to
  --   (`nvim_lastplace_arg_pending` below), and only that read trusts the
  --   cache. Nothing later can ever claim one, since the list itself never
  --   grows.
  --   A *third* (or later) occurrence of a name earlier in the list doesn't
  --   always get its own fresh read at all -- e.g. "nvim -o g f f" never
  --   fires BufReadPost for window 3. Every extra window opens onto
  --   firstwin's own starting buffer (main.c), and do_ecmd() only rereads
  --   when that starting buffer *is* the target -- true for "-o f f"
  --   (firstwin already showed f) and true again for every window of
  --   "-o f f f" (firstwin's own name is the one repeating), false once an
  --   unrelated file comes first (confirmed by direct trace: "-o g f f"'s
  --   window 3 and "-o g f g f"'s second "f" both get only a BufWinEnter,
  --   no BufReadPost -- while that same run's second "g" gets a real reread,
  --   since firstwin's own name is what it matches). BufWinEnter still
  --   fires unconditionally either way, so BufWinEnter itself falls back to
  --   the same claim-and-cache handling BufReadPost normally does, for any
  --   window still unclaimed once startup gets there (see below).
  -- - "nvim -d a b" only turns 'diff' on for every window *after* every
  --   file is already open (see diff_win_options() in diff.c), so 'diff'
  --   reads as off for every window but the first at its own BufWinEnter.
  --   Worked around because 'diff' is a startup exception to that: it's
  --   set on the *first* window immediately, before any window is even
  --   created (main.c: "so that it can be checked for in a vimrc file") --
  --   so checking the first window's 'diff', not just the current one,
  --   catches "-d was requested" even before the current window's own bit
  --   is flipped.
  local nvim_lastplace_augroup = vim.api.nvim_create_augroup('nvim.lastplace')
  local nvim_lastplace_marks = {} --- @type table<integer, [integer, integer]>
  local nvim_lastplace_fresh_read = {} --- @type table<integer, true>
  local nvim_lastplace_arg_read = {} --- @type table<integer, true>

  --- How many more times each file the argument list names is expected to
  --- be read fresh as part of *this* startup's own window creation --
  --- keyed by resolved path since that's all argv() gives before any buffer
  --- (and so any buffer number) exists yet. A duplicate entry (e.g. "nvim -o
  --- f f") claims two; everything else claims one; a file named zero times
  --- (opened only via -c/+cmd) never claims any -- see the block comment
  --- above.
  ---
  --- Capped at 1 per path unless -o/-O/-p (with an optional window-count
  --- digit, e.g. "-O3") was actually given: without one of those,
  --- create_windows() never opens more than a single window (window_count
  --- stays 1 regardless of how many times a name repeats in the argument
  --- list -- e.g. "nvim f f" just opens the first "f" once, leaving "f f"
  --- navigable via |:next| in that one window, not two), so at most one
  --- read of any given path could ever be part of *this* startup's own
  --- window creation. Leaving the cap off let a plain "nvim f f" permanently
  --- leave one claim unclaimed, which a later, unrelated startup switch to
  --- that same buffer (e.g. a -c command, still before VimEnter) could then
  --- wrongly consume via the BufWinEnter fallback below, applying a stashed
  --- mark that's likely stale by then to a window that should never have
  --- been touched at all -- confirmed by direct trace.
  local nvim_lastplace_multi_window = false
  for _, arg in ipairs(vim.v.argv) do
    if arg:match('^%-[oOp]%d*$') then
      nvim_lastplace_multi_window = true
      break
    end
  end
  local nvim_lastplace_arg_pending = {} --- @type table<string, integer>
  for _, arg in ipairs(vim.fn.argv() --[[@as string[] ]]) do
    local path = vim.fn.fnamemodify(arg, ':p')
    local pending = (nvim_lastplace_arg_pending[path] or 0) + 1
    if nvim_lastplace_multi_window or pending <= 1 then
      nvim_lastplace_arg_pending[path] = pending
    end
  end

  --- Whether "nvim -d ..." was requested, even before the *current* window's
  --- own 'diff' has been turned on yet (see the block comment above). Only a
  --- valid proxy during startup itself: post-startup, the first window in a
  --- tab being in diff mode says nothing about a later, unrelated window
  --- added to that same tab (a plain :split while an earlier :diffthis
  --- session is still open, say), so this is only ever consulted then.
  local function nvim_lastplace_diff_startup_pending()
    local first_win = vim.api.nvim_tabpage_list_wins(0)[1]
    return vim.api.nvim_win_is_valid(first_win) and vim.wo[first_win].diff
  end

  --- Restore the current window's cursor to `buf`'s last-known position, if
  --- there's a real one worth jumping to. `buf` is a parameter (rather than
  --- read off the current window) for symmetry with the rest of this file's
  --- nvim_on() callbacks. `is_arg_read` is true only for the read that just
  --- claimed an entry off `nvim_lastplace_arg_pending` (see the block
  --- comment above and BufReadPost below) -- i.e. only ever during startup,
  --- and only for a read Nvim's own unload/reread race could actually have
  --- clobbered.
  local function nvim_lastplace_restore(buf, is_arg_read)
    if
      vim.bo[buf].buftype ~= ''
      or vim.wo[0].diff
      or (is_arg_read and nvim_lastplace_diff_startup_pending())
      or vim.fn.line('.') > 1
    then
      return
    end
    local ft = vim.bo[buf].filetype
    if ft == 'gitrebase' or ft == 'xxd' or ft:find('commit', 1, true) then
      return
    end
    local mark = vim.api.nvim_buf_get_mark(buf, '"')
    if is_arg_read and nvim_lastplace_marks[buf] then
      mark = nvim_lastplace_marks[buf]
    end
    local lnum = mark[1]
    if lnum <= 0 or lnum > vim.api.nvim_buf_line_count(buf) then
      return
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    if lnum == cursor[1] and mark[2] == cursor[2] then
      -- Nothing to restore -- e.g. a buffer that was never explicitly
      -- closed defaults its '"' mark to (1, 0) (see clrallmarks() in
      -- mark.c), the same place a fresh window's cursor already sits.
      -- Just an optimization: skip a no-op jump, nothing more.
      return
    end
    -- g`" reads the live '"' mark, not `mark` above -- write the cached
    -- value back first in case Nvim's own startup sequencing (see above)
    -- clobbered it. A genuine no-op outside of that startup race.
    vim.api.nvim_buf_set_mark(buf, '"', lnum, mark[2], {})
    vim.cmd('normal! g`"')
    vim.cmd('normal! zv') -- open a fold left closed around the target line
  end

  nvim_on('BufReadPost', nvim_lastplace_augroup, {
    desc = 'Track a genuine file read for |restore-cursor|.',
  }, function(ev)
    nvim_lastplace_fresh_read[ev.buf] = true
    if vim.v.vim_did_enter == 1 then
      -- A same-command BufWinEnter (the common case) already consumes and
      -- clears this flag itself, synchronously, before a scheduled callback
      -- can run -- so this is a no-op then. It only matters for a read with
      -- no BufWinEnter to follow it at all; see the block comment above.
      -- Skipped during startup itself: BufWinEnter's own restore call below
      -- already reads this flag synchronously, before startup can proceed
      -- any further, so nothing here would ever run ahead of it anyway.
      vim.schedule(function()
        nvim_lastplace_fresh_read[ev.buf] = nil
      end)
    end
    -- Claim this read against the argument list, if it's on it; see the
    -- block comment above. A buffer can be read fresh more than once with
    -- the same name still pending (the "-o f f" race this exists for) --
    -- always the same buffer number both times, so nvim_lastplace_arg_read
    -- is keyed by that, even though the claim itself is by path.
    local path = vim.api.nvim_buf_get_name(ev.buf)
    local pending = nvim_lastplace_arg_pending[path]
    if pending and pending > 0 then
      nvim_lastplace_arg_pending[path] = pending - 1
      nvim_lastplace_arg_read[ev.buf] = true
      -- Startup-only cache; see the block comment above. Only ever written
      -- for a read that just claimed an argument-list entry, so it can
      -- never grow past the length of the argument list, and never again
      -- once every entry is claimed.
      if nvim_lastplace_marks[ev.buf] == nil then
        nvim_lastplace_marks[ev.buf] = vim.api.nvim_buf_get_mark(ev.buf, '"')
      end
    else
      nvim_lastplace_arg_read[ev.buf] = nil
    end
  end)

  nvim_on({ 'BufDelete', 'BufWipeout' }, nvim_lastplace_augroup, {
    desc = 'Forget a deleted buffer for |restore-cursor|.',
  }, function(ev)
    nvim_lastplace_marks[ev.buf] = nil
    nvim_lastplace_fresh_read[ev.buf] = nil
    nvim_lastplace_arg_read[ev.buf] = nil
  end)

  -- nvim_lastplace_restore itself skips anything but a real file buffer
  -- (buftype ""), so this never actually restores for the quickfix list, a
  -- terminal, or a scratch buffer -- even though it's not filtered by
  -- pattern here.
  nvim_on('BufWinEnter', nvim_lastplace_augroup, {
    desc = 'Restore cursor to the last-known position. See |restore-cursor|.',
  }, function(ev)
    if nvim_lastplace_fresh_read[ev.buf] then
      nvim_lastplace_fresh_read[ev.buf] = nil
      local is_arg_read = nvim_lastplace_arg_read[ev.buf]
      nvim_lastplace_arg_read[ev.buf] = nil
      nvim_lastplace_restore(ev.buf, is_arg_read)
      return
    end
    -- No BufReadPost preceded this window's own BufWinEnter -- e.g. a
    -- repeated startup argument whose window just got pointed at a buffer
    -- another window already loaded, with no read of its own to claim (see
    -- the block comment above). BufWinEnter still fires unconditionally
    -- for it, so fall back to the same claim-and-cache handling BufReadPost
    -- does, keyed off the same argument-list pending count. Safe even for a
    -- switch that happens well before VimEnter (a -c command, say, not just
    -- edit_buffers()'s own window creation): nvim_lastplace_arg_pending
    -- itself is only ever seeded above 1 per path when -o/-O/-p was
    -- actually given, so a *plain* "nvim f f" (no window flag, one real
    -- window) never leaves a phantom claim behind for something later and
    -- unrelated to consume.
    if vim.v.vim_did_enter == 1 or nvim_lastplace_marks[ev.buf] == nil then
      return
    end
    local path = vim.api.nvim_buf_get_name(ev.buf)
    local pending = nvim_lastplace_arg_pending[path]
    if pending and pending > 0 then
      nvim_lastplace_arg_pending[path] = pending - 1
      nvim_lastplace_restore(ev.buf, true)
    end
  end)

  -- Startup-only cache and claim table; done with both once every window
  -- that's going to exist at startup has had its own BufWinEnter -- the
  -- argument list this is keyed against never grows, so nothing is ever
  -- consulted again either way, but there's no reason to keep holding them.
  nvim_on('VimEnter', nvim_lastplace_augroup, {
    desc = 'Drop the startup-only cache and claim table. See |restore-cursor|.',
    once = true,
  }, function()
    nvim_lastplace_marks = {}
    nvim_lastplace_arg_pending = {}
  end)

  -- Check if a TTY is attached
  local tty = nil
  for _, ui in ipairs(vim.api.nvim_list_uis()) do
    if ui.stdout_tty then
      tty = ui
      break
    end
  end

  -- Shared TTY option detection used by two paths: the startup path (a TTY is
  -- present when Nvim starts) and the UIEnter path (a TTY attaches to a
  -- previously |--headless| server, e.g. behind |--remote-ui|). The helpers are
  -- hoisted here so both paths share one implementation instead of duplicating
  -- it.
  --
  -- Precedence: never override an explicit user setting. For 'background',
  -- bg_user_set() treats only our own sets (SID_LUA, -8) as re-applicable; a
  -- user set (real script SID, ":set", or API client) is preserved.
  -- 'termguicolors' is guarded by `was_set` and is only ever enabled here.
  --
  -- Limitation: 'background' is global, the OSC 11 query is broadcast to every
  -- attached terminal, and a |TermResponse| is not attributable to a UI, so the
  -- value reflects whichever terminal answers last (decided by response speed),
  -- not necessarily the most recently attached one.
  local group = vim.api.nvim_create_augroup('nvim.tty')

  --- Set an option after startup (so that OptionSet is fired), but only if not
  --- already set by the user.
  ---
  --- @param option string Option name
  --- @param value any Option value
  --- @param force boolean? Always set the value, even if already set
  local function setoption(option, value, force)
    if not force and vim.api.nvim_get_option_info2(option).was_set then
      -- Don't do anything if option is already set
      return
    end

    -- Wait until Nvim is finished starting to set the option to ensure the
    -- OptionSet event fires.
    if vim.v.vim_did_enter == 1 then
      --- @diagnostic disable-next-line:no-unknown
      vim.o[option] = value
    else
      nvim_on('VimEnter', group, {
        once = true,
        nested = true,
      }, function()
        setoption(option, value, force)
      end)
    end
  end

  --- Script ID (SID) used for our own automatic 'background' sets. Lets
  --- bg_user_set() distinguish a user set from our detection.
  local sid_lua = -8

  --- True if 'background' was set by the user, not by our detection (sid_lua).
  local function bg_user_set()
    local info = vim.api.nvim_get_option_info2('background')
    return info.was_set and info.last_set_sid ~= sid_lua
  end

  --- Parse a string of hex characters as a color.
  ---
  --- The string can contain 1 to 4 hex characters. The returned value is
  --- between 0.0 and 1.0 (inclusive) representing the intensity of the color.
  ---
  --- For instance, if only a single hex char "a" is used, then this function
  --- returns 0.625 (10 / 16), while a value of "aa" would return 0.664 (170 /
  --- 256).
  ---
  --- @param c string Color as a string of hex chars
  --- @return number? Intensity of the color
  local function parsecolor(c)
    if #c == 0 or #c > 4 then
      return nil
    end

    local val = vim._tointeger(c, 16)
    if not val then
      return nil
    end

    local max = vim._assert_integer(string.rep('f', #c), 16)
    return val / max
  end

  --- Parse an OSC 11 response
  ---
  --- Either of the two formats below are accepted:
  ---
  ---   OSC 11 ; rgb:<red>/<green>/<blue>
  ---
  --- or
  ---
  ---   OSC 11 ; rgba:<red>/<green>/<blue>/<alpha>
  ---
  --- where
  ---
  ---   <red>, <green>, <blue>, <alpha> := h | hh | hhh | hhhh
  ---
  --- The alpha component is ignored, if present.
  ---
  --- @param resp string OSC 11 response
  --- @return string? Red component
  --- @return string? Green component
  --- @return string? Blue component
  local function parseosc11(resp)
    local r, g, b
    r, g, b = resp:match('^\027%]11;rgb:(%x+)/(%x+)/(%x+)$')
    if not r and not g and not b then
      local a
      r, g, b, a = resp:match('^\027%]11;rgba:(%x+)/(%x+)/(%x+)/(%x+)$')
      if not a or #a > 4 then
        return nil, nil, nil
      end
    end

    if r and g and b and #r <= 4 and #g <= 4 and #b <= 4 then
      return r, g, b
    end

    return nil, nil, nil
  end

  --- Guess value of 'background' based on terminal color.
  ---
  --- We write Operating System Command (OSC) 11 to the terminal to request the
  --- terminal's background color. We then wait for a response. If the response
  --- matches `rgba:RRRR/GGGG/BBBB/AAAA` where R, G, B, and A are hex digits, then
  --- compute the luminance[1] of the RGB color and classify it as light/dark
  --- accordingly. Note that the color components may have anywhere from one to
  --- four hex digits, and require scaling accordingly as values out of 4, 8, 12,
  --- or 16 bits. Also note the A(lpha) component is optional, and is parsed but
  --- ignored in the calculations.
  ---
  --- [1] https://en.wikipedia.org/wiki/Luma_%28video%29
  ---
  --- In slow environments (e.g. SSH with high latency), this will increase
  --- startup time and produce a warning, so users may want to disable it.
  ---
  --- The OSC 11 handler is PERSISTENT (timeout=0) so it also reacts to runtime
  --- theme changes (a terminal in mode 2031 re-queries and forwards a fresh
  --- |TermResponse|). Its augroup is cleared on each call so only the
  --- most-recently-attached TUI's handler remains.
  ---
  --- @param sync boolean When true (a TTY is present at startup), also send a
  --- DSR probe and synchronously wait so 'background' is set before user config,
  --- warning (E1568) if the terminal never answers the DSR.
  local function detect_background(sync, chan)
    -- Re-create (clear) the handler's augroup on each call so only the
    -- most-recently-attached TUI's handler remains.
    local bg_group = vim.api.nvim_create_augroup('nvim.tty.background')

    -- Send OSC 11 query. In the startup (sync) path also send a DSR probe: if
    -- the DSR response comes first, the terminal most likely doesn't support the
    -- bg color query, and we don't have to keep waiting for a bg response. #32109
    local osc11 = '\027]11;?\007'
    local dsr = '\027[5n'

    -- This handler updates 'background' anytime we receive an OSC 11 response
    -- from the terminal emulator. It is persistent (no built-in timeout) so it
    -- also reacts to runtime theme changes; the per-response bg_user_set() guard
    -- stops it once the user pins 'background'.
    local did_dsr_response = false
    vim.tty.request(
      osc11 .. (sync and dsr or ''),
      { group = bg_group, timeout = 0, chan = chan },
      function(resp)
        -- DSR response that should come after the OSC 11 response if the terminal
        -- supports it.
        if sync and string.match(resp, '^\027%[0n$') then
          did_dsr_response = true
          -- Don't stop listening: the bg response may come after the DSR response
          -- if the terminal handles requests out of sequence. In that case, the bg
          -- will simply be set later in the startup sequence.
          return
        end

        -- Never override an explicit user value: stop once the user pins it.
        if bg_user_set() then
          return true
        end

        local r, g, b = parseosc11(resp)
        if r and g and b then
          local rr = parsecolor(r)
          local gg = parsecolor(g)
          local bb = parsecolor(b)

          if rr and gg and bb then
            local luminance = (0.299 * rr) + (0.587 * gg) + (0.114 * bb)
            local bg = luminance < 0.5 and 'dark' or 'light'
            vim.o.background = bg
          end
        end
      end
    )

    if not sync then
      return
    end

    -- Wait until detection of OSC 11 capabilities is complete to ensure
    -- background is automatically set before user config.
    if
      not vim.wait(100, function()
        return did_dsr_response
      end, 1)
      -- Don't show the warning when running tests to avoid flakiness.
      and os.getenv('NVIM_TEST') == nil
    then
      vim.notify(
        "E1568: Terminal did not respond to DSR request for 'background' color. Startup may be slower. :help 'ttyfast'",
        vim.log.levels.WARN,
        { _truncate = true }
      )
    end
  end

  --- If the TUI (term_has_truecolor) was able to determine that the host
  --- terminal supports truecolor, enable 'termguicolors'. Otherwise, query the
  --- terminal (using both XTGETTCAP and SGR + DECRQSS). If the terminal's
  --- response indicates that it does support truecolor enable 'termguicolors',
  --- but only if the user has not already disabled it.
  ---
  --- @param ui table<string,any> The attached TTY UI (see |nvim_list_uis()|).
  local function detect_termguicolors(ui)
    local colorterm = os.getenv('COLORTERM')
    if ui.rgb or colorterm == 'truecolor' or colorterm == '24bit' then
      -- The TUI was able to determine truecolor support or $COLORTERM explicitly indicates
      -- truecolor support
      setoption('termguicolors', true)
    elseif (colorterm == nil or colorterm == '') and vim.o.ttyfast then
      -- Neither the TUI nor $COLORTERM indicate that truecolor is supported, so query the
      -- terminal
      local caps = {} ---@type table<string, boolean>
      vim.tty.query(
        { 'Tc', 'RGB', 'setrgbf', 'setrgbb' },
        { group = group, chan = ui.chan },
        function(cap, found)
          if not found then
            return
          end

          caps[cap] = true
          if caps.Tc or caps.RGB or (caps.setrgbf and caps.setrgbb) then
            setoption('termguicolors', true)
          end
        end
      )

      -- Arbitrary colors to set in the SGR sequence
      local r = 1
      local g = 2
      local b = 3

      -- Write SGR followed by DECRQSS. This sets the background color then
      -- immediately asks the terminal what the background color is. If the
      -- terminal responds to the DECRQSS with the same SGR sequence that we
      -- sent then the terminal supports truecolor.
      --
      -- Reset attributes first, as other code may have set attributes.
      local payload = ('\027[0m\027[48;2;%d;%d;%dm%s'):format(r, g, b, '\027P$qm\027\\')

      vim.tty.request(payload, { group = group, chan = ui.chan }, function(resp)
        local decrqss = resp:match('^\027P1%$r([%d;:]+)m$')
        if not decrqss then
          return
        end

        -- The DECRQSS SGR response first contains attributes separated by semicolons, followed by
        -- the SGR itself with parameters separated by colons. Some terminals include "0" in the
        -- attribute list unconditionally; others do not. Our SGR sequence did not set any
        -- attributes, so there should be no attributes in the list.
        local attrs = vim.split(decrqss, ';')
        if #attrs ~= 1 and (#attrs ~= 2 or attrs[1] ~= '0') then
          return
        end

        -- The returned SGR sequence should begin with 48:2
        local sgr = assert(attrs[#attrs]):match('^48:2:([%d:]+)$')
        if not sgr then
          return
        end

        -- The remaining elements of the SGR sequence should be the 3 colors we set. Some
        -- terminals also include an additional parameter (which can even be empty!), so handle
        -- those cases as well
        local params = vim.split(sgr, ':')
        if #params ~= 3 and (#params ~= 4 or (params[1] ~= '' and params[1] ~= '1')) then
          return true
        end

        if
          vim._tointeger(params[#params - 2]) == r
          and vim._tointeger(params[#params - 1]) == g
          and vim._tointeger(params[#params]) == b
        then
          setoption('termguicolors', true)
        end

        return true
      end)
    end
  end

  if tty then
    -- A TTY is present at startup. Detect synchronously so 'background' is set
    -- before user config runs, and detect 'termguicolors'. This path owns the
    -- startup TTY (including runtime reactivity), so the UIEnter path below is
    -- not registered for it (avoids double-detection).
    if vim.o.ttyfast then
      detect_background(true, tty.chan)
    end

    detect_termguicolors(tty)

    -- Show progress bars in supporting terminals
    nvim_on('Progress', vim.api.nvim_create_augroup('nvim.progress'), {
      desc = 'Display native progress bars',
    }, function(ev)
      if ev.data.status == 'running' then
        if ev.data.percent ~= nil then
          vim.api.nvim_ui_send(string.format('\027]9;4;1;%d\027\\', ev.data.percent))
        else
          -- "Indeterminate" progress (unknown percent).
          vim.api.nvim_ui_send(string.format('\027]9;4;3\027\\'))
        end
      else
        vim.api.nvim_ui_send('\027]9;4;0;0\027\\')
      end
    end)
  end

  -- Re-detect terminal options when a UI attaches, not only at startup: a
  -- |--headless| server (e.g. behind |--remote-ui|) has no UI when the block
  -- above runs, and swapping a TUI between servers should pick up the current
  -- terminal. Only handle TTYs that attach AFTER startup: if a TTY was present
  -- at startup the block above already owns detection (incl. runtime
  -- reactivity), so registering here too would double-detect.
  if not tty then
    --- The terminal UI that just attached (per |v:event| `chan`), or nil.
    local function attaching_tty()
      local chan = (vim.v.event or {}).chan
      for _, ui in ipairs(vim.api.nvim_list_uis()) do
        if ui.chan == chan then
          return ui.stdout_tty and ui or nil
        end
      end
      return nil
    end

    nvim_on('UIEnter', vim.api.nvim_create_augroup('nvim.tty.attach'), {}, function()
      local ui = attaching_tty()
      if not ui then
        return
      end

      -- 'termguicolors': enable when the attaching UI reports truecolor (or the
      -- terminal query confirms it), unless the user set it. Never disabled here.
      detect_termguicolors(ui)

      -- 'background': (re)query OSC 11. The persistent handler also reacts to
      -- runtime theme changes (mode 2031 -> TUI re-queries -> |TermResponse|);
      -- the per-response bg_user_set() guard preserves an explicit user value.
      if vim.o.ttyfast then
        detect_background(false, ui.chan)
      end
    end)
  end
end

--- Default options
do
  --- Default 'grepprg' to ripgrep if available.
  if vim.fn.executable('rg') == 1 then
    -- Use -uu to make ripgrep not check ignore files/skip dot-files
    vim.o.grepprg = 'rg --vimgrep -uu '
    vim.o.grepformat = '%f:%l:%c:%m'
  end
end

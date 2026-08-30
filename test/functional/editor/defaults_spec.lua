--
-- Tests for default autocmds, mappings, commands, and menus.
--
-- See options/defaults_spec.lua for default options and environment decisions.
--

local t = require('test.testutil')
local n = require('test.functional.testnvim')()
local Screen = require('test.functional.ui.screen')
local t_shada = require('test.functional.shada.testutil')

local describe, it, before_each, after_each = t.describe, t.it, t.before_each, t.after_each
describe('default', function()
  describe('autocommands', function()
    it('nvim.terminal.TermClose closes terminal with default shell on success', function()
      n.clear()
      n.api.nvim_set_option_value('shell', n.testprg('shell-test'), {})
      n.command('set shellcmdflag=EXIT shellredir= shellpipe= shellquote= shellxquote=')

      -- Should not block other events
      n.command('let g:n=0')
      n.command('au BufEnter * let g:n = g:n + 1')

      t.eq(1, n.exec_lua('vim.cmd.terminal(); return vim.g.n'))

      t.retry(nil, 1000, function()
        t.neq('terminal', n.api.nvim_get_option_value('buftype', { buf = 0 }))
        t.eq(2, n.eval('g:n'))
      end)
    end)

    describe('nvim.lastplace', function()
      local reset, shada_clear = t_shada.reset, t_shada.clear
      local testfile = 'Xtestfile-lastplace'

      local function fixture_lines(count)
        local out = {} --- @type string[]
        for i = 1, count do
          out[i] = ('line %d'):format(i)
        end
        return table.concat(out, '\n') .. '\n'
      end

      local function cursor(win)
        return n.api.nvim_win_get_cursor(win or 0)[1]
      end

      -- The '"' mark is only committed on a real buffer close (see
      -- src/nvim/mark.c set_last_cursor()), not by a mid-session :wshada, so
      -- seed it via a genuine quit-and-respawn against the same shada file.
      local function seed_mark_and_quit(line, args)
        reset(args)
        n.command('edit ' .. testfile)
        n.command(tostring(line))
        n.expect_exit(n.command, 'qall')
      end

      before_each(function()
        t.write_file(testfile, fixture_lines(30), true)
      end)

      after_each(function()
        shada_clear()
        os.remove(testfile)
        os.remove('COMMIT_EDITMSG')
      end)

      it('restores the cursor to the last-known position', function()
        seed_mark_and_quit(10)
        reset()
        n.command('edit ' .. testfile)
        t.eq(10, cursor())
      end)

      it('restores in every window when the same file is opened twice at startup (#16339)', function()
        seed_mark_and_quit(10)
        reset({ args = { '-o', testfile, testfile } })
        local wins = n.api.nvim_list_wins()
        t.eq(2, #wins)
        for _, win in ipairs(wins) do
          t.eq(10, cursor(win))
        end
      end)

      it('restores every occurrence of a repeated name, not just the first (#16339)', function()
        -- do_ecmd()'s own reread-in-place shortcut (see the block comment
        -- above) only ever matches a window still showing firstwin's own
        -- unreplaced starting buffer -- true for "-o f f" above and for
        -- every window of "-o f f f" (firstwin's own name is what
        -- repeats), false the moment an unrelated file comes first. Both
        -- "g f f"'s second "f" and "g f g f"'s second "f" (confirmed by
        -- direct trace) skip past that shortcut, firing only BufWinEnter
        -- with no BufReadPost to claim -- exactly what the BufWinEnter-side
        -- fallback below exists for. "g f g f"'s second "g" still takes the
        -- shortcut normally (its own name is firstwin's), so it's included
        -- too, as a check that the fallback doesn't fire for -- or somehow
        -- interfere with -- a window that didn't need it.
        seed_mark_and_quit(10)
        local other = 'Xtestfile-lastplace-other'
        t.write_file(other, fixture_lines(5), true)
        reset()
        n.command('edit ' .. other)
        n.command('3')
        n.expect_exit(n.command, 'qall')
        reset({ args = { '-o', other, testfile, other, testfile } })
        local wins = n.api.nvim_list_wins()
        t.eq(4, #wins)
        for _, win in ipairs(wins) do
          -- Exact basename match -- `other` has `testfile` as a literal
          -- prefix of its own name, so a substring check would misclassify
          -- every one of its windows as `testfile` too.
          local base = n.fn.fnamemodify(n.api.nvim_buf_get_name(n.api.nvim_win_get_buf(win)), ':t')
          t.eq(true, base == testfile or base == other, base)
          t.eq(base == testfile and 10 or 3, cursor(win))
        end
        os.remove(other)
      end)

      it('a repeated name with no -o/-O/-p does not leave a phantom claim behind (#16339)', function()
        -- "nvim f f" (no window flag) opens exactly one window -- the
        -- duplicate is just a second |:args| entry, navigable via |:next|,
        -- not a second window -- so at most one real read of it can ever
        -- happen. Without the cap on nvim_lastplace_arg_pending (see the
        -- block comment above), the second, un-consumed claim survived
        -- until *something* -- any startup-time switch to that buffer in a
        -- new window, still before VimEnter -- came along to claim it, at
        -- which point the BufWinEnter fallback misapplied the startup-time
        -- cache to a window that should never have been touched at all.
        seed_mark_and_quit(10)
        reset({
          args = {
            -- Move the live mark well away from the cached startup value,
            -- so a wrong restore (the stale cache) is distinguishable from
            -- the correct outcome (no restore at all).
            '-c',
            'call nvim_buf_set_mark(bufnr(""), "\\"", 20, 0, {})',
            '-c',
            'wincmd n',
            '-c',
            'buffer ' .. testfile,
            testfile,
            testfile,
          },
        })
        t.eq(1, cursor())
      end)

      it('a later startup read does not fall back to a stale window-race cache (#16339)', function()
        -- The mark cache exists only to survive Nvim's own unload+reread
        -- for a *repeated* startup file argument (see the block comment on
        -- nvim.lastplace in defaults.lua) -- it must not also catch a
        -- later, unrelated genuine read of the same buffer, still before
        -- VimEnter, that legitimately changed the mark itself: deleting it
        -- and moving the cursor to line one here, right before an :edit!
        -- forces a real reread. A stale cache read back here would silently
        -- override both.
        seed_mark_and_quit(10)
        reset({
          args = {
            '-c',
            'call nvim_buf_del_mark(bufnr(""), "\\"")',
            '-c',
            'normal! 1G',
            '-c',
            'edit!',
            testfile,
          },
        })
        t.eq(1, cursor())
      end)

      it('does not swallow typeahead queued right after a real restore', function()
        seed_mark_and_quit(10)
        reset()
        n.command('let g:order = ""')
        n.command('autocmd BufWinEnter * let g:order ..= "B"')
        -- A real restore executes `normal! g`"` + `normal! zv`, not
        -- feedkeys(..., 'x', ...) -- the latter drains all pending
        -- typeahead when called reentrantly (see |feedkeys()|), which used
        -- to let this queued command run inside the BufWinEnter autocmd
        -- instead of after it.
        n.feed(':edit ' .. testfile .. '<CR>:let g:order ..= "T"<CR>')
        t.eq(10, cursor())
        t.eq('BT', n.eval('g:order'))
      end)

      it('opens a fold that would otherwise hide the restored line', function()
        -- The fold has to exist by BufWinEnter, so it's built from a
        -- BufReadPost autocmd (registered early via --cmd, so it's in place
        -- before the file is even read) rather than a -c command: -c/+cmd
        -- run *after* every window's own BufWinEnter (see the block comment
        -- on nvim.lastplace in defaults.lua), same as any other startup
        -- argument, so a fold created that way would still be closed by the
        -- time this restore's own zv already ran.
        seed_mark_and_quit(12)
        reset({
          args = {
            '--cmd',
            'set foldmethod=manual',
            '--cmd',
            'autocmd BufReadPost * 5,20fold',
            testfile,
          },
        })
        t.eq(12, cursor())
        t.eq(-1, n.fn.foldclosed('.'))
      end)

      it('a position given on the command line wins', function()
        seed_mark_and_quit(10)
        reset({ args = { '+5', testfile } })
        t.eq(5, cursor())
      end)

      it('a startup command landing on line one is not clobbered (#16339)', function()
        -- The tricky case: exe_commands() (+cmd/-c/-S), handle_tag() (-t),
        -- and qf_jump() (-q) all run *after* this window's own BufWinEnter,
        -- so a mark-restore made straight from BufWinEnter always loses to
        -- them by ordering -- but only if the restore doesn't independently
        -- try again once they're done. Landing on line one specifically
        -- used to be indistinguishable from "nothing touched it yet".
        seed_mark_and_quit(20)
        reset({ args = { '-c', 'normal! 1G', testfile } })
        t.eq(1, cursor())
      end)

      it('is skipped for every window in "nvim -d" diff mode', function()
        -- 'diff' is only turned on for every window *after* every file is
        -- already open (diff_win_options() in diff.c), so a plain BufWinEnter
        -- check of the *current* window's own 'diff' sees it off for every
        -- window but the first at its own BufWinEnter.
        seed_mark_and_quit(10)
        local other = 'Xtestfile-lastplace-diff'
        t.write_file(other, fixture_lines(30), true)
        -- Seed `other` with a *different* mark too: with no mark there at
        -- all, a correctly-skipped window 2 and a broken proxy that wrongly
        -- restores it anyway both land on line 1 -- indistinguishable. A
        -- real, different mark makes "wrongly restored" observable.
        reset()
        n.command('edit ' .. other)
        n.command('15')
        n.expect_exit(n.command, 'qall')
        reset({ args = { '-d', testfile, other } })
        local wins = n.api.nvim_list_wins()
        t.eq(2, #wins)
        for _, win in ipairs(wins) do
          t.eq(1, cursor(win))
          t.eq(true, n.api.nvim_get_option_value('diff', { win = win }))
        end
        os.remove(other)
      end)

      it('does not skip restore for an unrelated window in a diffthis-only tab, post-startup (#16339)', function()
        -- nvim_lastplace_diff_startup_pending() (see its doc comment in
        -- defaults.lua) can't even be reached here -- it's gated on the same
        -- argument-list claim as the mark cache (`is_arg_read`), which is
        -- never true for a read this long after startup; the argument list
        -- it's checked against is fixed at startup and never grows. This is
        -- instead about the *other*, unconditional 'diff' check: confirms an
        -- interactive :diffthis session already running in window 1 doesn't
        -- also disable restore for a later, unrelated window in the same
        -- tab -- `belowright` so the new window isn't accidentally window 1
        -- itself, though nothing here actually consults window order.
        seed_mark_and_quit(10)
        reset()
        local diff_buf = 'Xtestfile-lastplace-diffthis'
        t.write_file(diff_buf, fixture_lines(30), true)
        n.command('edit ' .. diff_buf)
        n.command('diffthis')
        n.command('belowright split ' .. testfile)
        t.eq(10, cursor())
        t.eq(false, n.api.nvim_get_option_value('diff', { win = 0 }))
        os.remove(diff_buf)
      end)

      it('does not leave a stale restore visible after :diffsplit', function()
        -- The new window's own 'diff' actually reads *false* at its
        -- BufWinEnter (confirmed by direct trace): ex_diffsplit() sets
        -- w_p_diff=true before do_exedit() (diff.c:1485-1486), but
        -- do_exedit's own buffer-load path resets it, and it's only set
        -- back to true *after* do_exedit returns, at diff.c:1493. So the
        -- restore isn't actually skipped here -- it runs and jumps to the
        -- mark like normal. What makes the end state correct anyway is
        -- ex_diffsplit()'s own diff_get_corresponding_line() call right
        -- after (diff.c:1499-1500), which unconditionally overwrites the
        -- cursor to the diff-aligned position, making whatever the restore
        -- did moot. This asserts that guaranteed-correct end state, not
        -- that a guard fired.
        seed_mark_and_quit(10)
        reset()
        local diff_buf = 'Xtestfile-lastplace-diffsplit'
        t.write_file(diff_buf, fixture_lines(30), true)
        n.command('edit ' .. diff_buf)
        n.command('diffsplit ' .. testfile)
        t.eq(1, cursor())
        t.eq(true, n.api.nvim_get_option_value('diff', { win = 0 }))
        os.remove(diff_buf)
      end)

      it('does not restore on a plain switch after a reload with no BufWinEnter', function()
        -- :checktime / 'autoread' reload a changed buffer via readfile()
        -- directly (buf_reload() in fileio.c), with no window involved, so
        -- no BufWinEnter follows to consume the fresh-read flag. Simulated
        -- here with nvim_exec_autocmds rather than a real file-change +
        -- :checktime, which is timing-sensitive; the mark is also
        -- deliberately desynced from where native per-window memory would
        -- return, since otherwise the two are indistinguishable by cursor
        -- position alone (leaving a buffer always resets its own '"' mark
        -- to match the leaving cursor).
        seed_mark_and_quit(10)
        reset()
        n.command('edit ' .. testfile)
        n.command('normal! 15G')
        n.command('enew')
        local buf = n.fn.bufnr(testfile)
        n.api.nvim_buf_set_mark(buf, '"', 27, 0, {})
        n.api.nvim_exec_autocmds('BufReadPost', { buffer = buf })
        n.command('buffer ' .. testfile)
        t.eq(15, cursor())
      end)

      it('can be disabled by the user', function()
        seed_mark_and_quit(10)
        reset({ args = { '--cmd', 'autocmd! nvim.lastplace', testfile } })
        t.eq(1, cursor())
      end)

      it('skips a commit message', function()
        t.write_file('COMMIT_EDITMSG', 'subject\n\n# comment\n', true)
        reset({ args = { '--cmd', 'filetype on' } })
        n.command('edit COMMIT_EDITMSG')
        n.command('3')
        n.expect_exit(n.command, 'qall')
        reset({ args = { '--cmd', 'filetype on' } })
        n.command('edit COMMIT_EDITMSG')
        t.eq('gitcommit', n.api.nvim_get_option_value('filetype', { buf = 0 }))
        t.eq(1, cursor())
      end)

      it('skips xxd and gitrebase filetypes', function()
        seed_mark_and_quit(10)
        for _, ft in ipairs({ 'xxd', 'gitrebase' }) do
          -- BufReadPre, not FileType/BufReadPost -- has to be in place
          -- before the guard in nvim_lastplace_restore actually runs.
          reset({ args = { '--cmd', 'autocmd BufReadPre * set filetype=' .. ft, testfile } })
          t.eq(1, cursor())
        end
      end)

      it('skips a mark past the end of a shrunk file', function()
        seed_mark_and_quit(10)
        t.write_file(testfile, 'line 1\nline 2\n', true)
        reset()
        n.command('edit ' .. testfile)
        t.eq(1, cursor())
      end)
    end)
  end)

  describe('popupmenu', function()
    it('can be disabled by user', function()
      n.clear {
        args = { '+autocmd! nvim.popupmenu', '+aunmenu PopUp' },
      }
      local screen = Screen.new(40, 8)
      n.insert([[
        1 line 1
        2 https://example.com
        3 line 3
        4 line 4]])

      n.api.nvim_input_mouse('right', 'press', '', 0, 1, 4)
      screen:expect({
        grid = [[
          1 line 1                                |
          2 ht^tps://example.com                   |
          3 line 3                                |
          4 line 4                                |
          {1:~                                       }|*3
                                                  |
        ]],
      })
    end)

    it('right-click on URL shows "Open in web browser"', function()
      n.clear()
      local screen = Screen.new(40, 8)
      n.insert([[
        1 line 1
        2 https://example.com
        3 line 3
        4 line 4]])

      n.api.nvim_input_mouse('right', 'press', '', 0, 3, 4)
      screen:expect({
        grid = [[
          1 line 1                                |
          2 https://example.com                   |
          3 line 3                                |
          4 li^ne 4                                |
          {1:~  }{4: Inspect              }{1:               }|
          {1:~  }{4:                      }{1:               }|
          {1:~  }{4: Paste                }{1:               }|
             {4: Select All           }               |
        ]],
      })

      n.api.nvim_input_mouse('right', 'press', '', 0, 1, 4)
      screen:expect({
        grid = [[
          1 line 1                                |
          2 ht^tps://example.com                   |
          3 l{4: Open in web browser  }               |
          4 l{4: Inspect              }               |
          {1:~  }{4:                      }{1:               }|
          {1:~  }{4: Paste                }{1:               }|
          {1:~  }{4: Select All           }{1:               }|
             {4:                      }               |
        ]],
      })
    end)
  end)

  describe('key mappings', function()
    describe('Visual mode search mappings', function()
      it('handle various chars properly', function()
        n.clear({ args_rm = { '--cmd' } })
        local screen = Screen.new(60, 8)
        screen:set_default_attr_ids({
          [1] = { foreground = Screen.colors.NvimDarkGray4 },
          [2] = {
            foreground = Screen.colors.NvimLightGray2,
            background = Screen.colors.NvimDarkGray4,
          },
          [3] = {
            foreground = Screen.colors.NvimLightGrey1,
            background = Screen.colors.NvimDarkYellow,
          },
          [4] = {
            foreground = Screen.colors.NvimDarkGrey1,
            background = Screen.colors.NvimLightYellow,
          },
        })
        n.api.nvim_buf_set_lines(0, 0, -1, true, {
          [[testing <CR> /?\!1]],
          [[testing <CR> /?\!2]],
          [[testing <CR> /?\!3]],
          [[testing <CR> /?\!4]],
        })
        n.feed('gg0vf!')
        n.poke_eventloop()
        n.feed('*')
        screen:expect([[
          {3:testing <CR> /?\!}1                                          |
          {4:^testing <CR> /?\!}2                                          |
          {3:testing <CR> /?\!}3                                          |
          {3:testing <CR> /?\!}4                                          |
          {1:~                                                           }|*2
          {2:[No Name] [+]                             2,1            All}|
          /\Vtesting <CR> /?\\!                     [2/4]             |
        ]])
        n.feed('n')
        screen:expect([[
          {3:testing <CR> /?\!}1                                          |
          {3:testing <CR> /?\!}2                                          |
          {4:^testing <CR> /?\!}3                                          |
          {3:testing <CR> /?\!}4                                          |
          {1:~                                                           }|*2
          {2:[No Name] [+]                             3,1            All}|
          /\Vtesting <CR> /?\\!                     [3/4]             |
        ]])
        n.feed('G0vf!')
        n.poke_eventloop()
        n.feed('#')
        screen:expect([[
          {3:testing <CR> /?\!}1                                          |
          {3:testing <CR> /?\!}2                                          |
          {4:^testing <CR> /?\!}3                                          |
          {3:testing <CR> /?\!}4                                          |
          {1:~                                                           }|*2
          {2:[No Name] [+]                             3,1            All}|
          ?\Vtesting <CR> /?\\!                     [3/4]             |
        ]])
        n.feed('n')
        screen:expect([[
          {3:testing <CR> /?\!}1                                          |
          {4:^testing <CR> /?\!}2                                          |
          {3:testing <CR> /?\!}3                                          |
          {3:testing <CR> /?\!}4                                          |
          {1:~                                                           }|*2
          {2:[No Name] [+]                             2,1            All}|
          ?\Vtesting <CR> /?\\!                     [2/4]             |
        ]])
      end)
    end)

    describe('unimpaired-style mappings', function()
      it('show the command output when successful', function()
        n.clear({ args_rm = { '--cmd' } })
        local screen = Screen.new(40, 8)
        n.fn.setqflist({
          { filename = 'file1', text = 'item1' },
          { filename = 'file2', text = 'item2' },
        })

        n.feed(']q')

        screen:set_default_attr_ids({
          [1] = { foreground = Screen.colors.NvimDarkGrey4 },
          [2] = {
            background = Screen.colors.NvimDarkGrey4,
            foreground = Screen.colors.NvimLightGray2,
          },
        })
        screen:expect({
          grid = [[
            ^                                        |
            {1:~                                       }|*5
            {2:file2                 0,0-1          All}|
            (2 of 2): item2                         |
          ]],
        })
      end)

      it('do not show a full stack trace when unsuccessful #30625', function()
        n.clear({ args_rm = { '--cmd' } })
        local screen = Screen.new(40, 8)
        screen:set_default_attr_ids({
          [1] = { foreground = Screen.colors.NvimDarkGray4 },
          [2] = {
            background = Screen.colors.NvimDarkGray4,
            foreground = Screen.colors.NvimLightGrey2,
          },
          [3] = { foreground = Screen.colors.NvimLightRed },
          [4] = { foreground = Screen.colors.NvimLightCyan },
        })

        n.feed('[a')
        screen:expect({
          grid = [[
                                                    |
            {1:~                                       }|*4
            {2:                                        }|
            {3:E163: There is only one file to edit}    |
            {4:Press ENTER or type command to continue}^ |
          ]],
        })

        n.feed('[q')
        screen:expect({
          grid = [[
            ^                                        |
            {1:~                                       }|*5
            {2:[No Name]             0,0-1          All}|
            {3:E42: No Errors}                          |
          ]],
        })

        n.feed('[l')
        screen:expect({
          grid = [[
            ^                                        |
            {1:~                                       }|*5
            {2:[No Name]             0,0-1          All}|
            {3:E776: No location list}                  |
          ]],
        })

        n.feed('[t')
        screen:expect({
          grid = [[
            ^                                        |
            {1:~                                       }|*5
            {2:[No Name]             0,0-1          All}|
            {3:E73: Tag stack empty}                    |
          ]],
        })
      end)

      describe('[<Space>', function()
        it('adds an empty line above the current line', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed('[<Space>')
          n.expect([[

          first line]])
        end)

        it('works with a count', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed('5[<Space>')
          n.expect([[





          first line]])
        end)

        it('supports dot repetition', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed('[<Space>')
          n.feed('.')
          n.expect([[


          first line]])
        end)

        it('supports dot repetition and a count', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed('[<Space>')
          n.feed('3.')
          n.expect([[




          first line]])
        end)
      end)

      describe(']<Space>', function()
        it('adds an empty line below the current line', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed(']<Space>')
          n.expect([[
          first line
          ]])
        end)

        it('works with a count', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed('5]<Space>')
          n.expect([[
          first line




          ]])
        end)

        it('supports dot repetition', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed(']<Space>')
          n.feed('.')
          n.expect([[
          first line

          ]])
        end)

        it('supports dot repetition and a count', function()
          n.clear({ args_rm = { '--cmd' } })
          n.insert([[first line]])
          n.feed(']<Space>')
          n.feed('2.')
          n.expect([[
          first line


          ]])
        end)
      end)
    end)
  end)
end)

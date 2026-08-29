local t = require('test.testutil')
local n = require('test.functional.testnvim')()

local it, before_each, finally = t.it, t.before_each, t.finally
local assert_alive = n.assert_alive
local clear = n.clear
local command = n.command
local eq = t.eq
local eval = n.eval
local exec = n.exec
local feed = n.feed
local pcall_err = t.pcall_err
local write_file = t.write_file

before_each(clear)

it('no crash when ending Visual mode while editing buffer closes window', function()
  command('new')
  command('autocmd ModeChanged v:n ++once close')
  feed('v')
  command('enew')
  assert_alive()
end)

it('no crash when ending Visual mode close the window to switch to', function()
  command('new')
  command('autocmd ModeChanged v:n ++once only')
  feed('v')
  command('wincmd p')
  assert_alive()
end)

it('no crash when truncating overlong message', function()
  pcall(command, 'source test/old/testdir/crash/vim_msg_trunc_poc')
  assert_alive()
end)

it('no crash with very long option error message', function()
  pcall(command, 'source test/old/testdir/crash/poc_did_set_langmap')
  assert_alive()
end)

it('no crash when closing window with tag in loclist', function()
  exec([[
    new
    lexpr ['foo']
    lopen
    let g:qf_bufnr = bufnr()
    lclose
    call settagstack(1, #{items: [#{tagname: 'foo', from: [g:qf_bufnr, 1, 1, 0]}]})
  ]])
  eq(1, eval('bufexists(g:qf_bufnr)'))
  command('1close')
  eq(0, eval('bufexists(g:qf_bufnr)'))
  assert_alive()
end)

it('no crash when writing "Untitled" file fails', function()
  t.mkdir('Untitled')
  finally(function()
    vim.uv.fs_rmdir('Untitled')
  end)
  feed('ifoobar')
  command('set bufhidden=unload')
  eq('Vim(enew):E502: "Untitled" is a directory', pcall_err(command, 'confirm enew'))
  assert_alive()
end)

-- oldtest: Test_crash_bufwrite()
it('no crash when converting buffer with incomplete multibyte chars', function()
  command('edit ++bin test/old/testdir/samples/buffer-test.txt')
  finally(function()
    os.remove('Xoutput')
  end)
  command('w! ++enc=ucs4 Xoutput')
  assert_alive()
end)

-- A 'comments' part whose flags are longer than COM_MAX_LEN is truncated so
-- that no ':' survives into the parse buffer.
local long_com = ':#,' .. string.rep('0', 60) .. ':X'

it('no crash when joining with an overlong flags part in "comments"', function()
  command('set formatoptions+=j')
  command('set comments=' .. long_com)
  command([[call setline(1, ['# foo', '# bar'])]])
  command('normal! J')
  eq('# foo bar', eval('getline(1)'))
  assert_alive()
end)

it('no crash when an overlong "comments" part comes from a modeline', function()
  finally(function()
    os.remove('Xcrash_comments')
  end)
  write_file(
    'Xcrash_comments',
    table.concat({
      '# foo',
      '# bar',
      '# vim: set fo+=j com=' .. long_com:gsub(':', '\\:') .. ' :',
      '',
    }, '\n')
  )
  command('set modeline modelines=5')
  command('edit Xcrash_comments')
  eq(long_com, eval('&comments'))
  command('normal! J')
  eq('# foo bar', eval('getline(1)'))
  assert_alive()
end)

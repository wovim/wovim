-- Tests for walking undo history into an undofile written in an older format.
--
-- wovim writes UF_VERSION 3.  Version 2 is Vim's original layout, inherited at
-- the fork and written by every Neovim before extmark undo info was added.
-- Rather than delete such a file to take its name, wovim leaves it alone, walks
-- into it lazily when "u" runs off the bottom of the session's own history, and
-- persists its own history to a ".un3~" sibling instead.

local t = require('test.testutil')
local n = require('test.functional.testnvim')()

local describe, it, before_each, after_each = t.describe, t.it, t.before_each, t.after_each
local clear = n.clear
local command = n.command
local feed = n.feed
local expect = n.expect
local eq = t.eq
local neq = t.neq
local fn = n.fn
local pcall_err = t.pcall_err

local fname = 'Xundo_continuity'
local undofile = '.' .. fname .. '.un~'
local sibling = '.' .. fname .. '.un3~'

-- UF_START_MAGIC is "Vim\237UnDo\345" in C octal, i.e. these nine bytes.
local START_MAGIC = 'Vim\159UnDo\229'
local HEADER_MAGIC = '\95\208' -- UF_HEADER_MAGIC 0x5fd0
local ENTRY_END = '\53\129' -- UF_ENTRY_END_MAGIC 0x3581

local function slurp(path)
  local f = io.open(path, 'rb')
  if not f then
    return nil
  end
  local data = f:read('a')
  f:close()
  return data
end

local function spew(path, data)
  local f = assert(io.open(path, 'wb'))
  f:write(data)
  f:close()
end

--- Rewrites a real version-3 undofile in place as a genuine version-2 one.
---
--- Two things separate the formats, both introduced by the 2->3 bump (commit
--- f42e932df4, "Extmarks: Save extmark undo information to undofile"):
---
---   * the 2-byte version field at offset 9;
---   * serialize_uhp() closes each header with UF_ENTRY_END_MAGIC twice in v3
---     -- once after the entry list, once after the extmark list -- where v2
---     wrote it only once, with no extmark section in between.
---
--- Patching the version bytes alone is NOT enough, and the extmark section is
--- not empty even for plain text edits: every buffer change records an
--- ExtmarkSplice, so a real v3 header carries one such record.  So the whole
--- span from the entry-list terminator to the extmark-list terminator is cut.
---
--- Locating those terminators by byte search is safe only because the fixture
--- content is short ASCII, where 0x81 cannot occur in text or in the small
--- big-endian counts around it.  The assertion below is what keeps that honest:
--- if the marker count ever stops matching two per header, this fails loudly
--- rather than quietly producing a file that tests nothing.
local function to_version_2(path)
  local b = assert(slurp(path), path .. ' does not exist')

  local function offsets(needle)
    local out, i = {}, 1
    while true do
      local s = b:find(needle, i, true)
      if not s then
        break
      end
      out[#out + 1] = s
      i = s + 1
    end
    return out
  end

  local heads = offsets(HEADER_MAGIC)
  local ends = offsets(ENTRY_END)
  assert(#heads > 0, 'fixture has no undo headers')
  assert(
    #ends == 2 * #heads,
    ('fixture: expected %d ENTRY_END markers for %d headers, found %d'):format(
      2 * #heads,
      #heads,
      #ends
    )
  )

  local parts, prev = {}, 1
  for i = 1, #ends, 2 do
    local entry_end, extmark_end = ends[i], ends[i + 1]
    assert(extmark_end > entry_end, 'fixture: ENTRY_END markers out of order')
    parts[#parts + 1] = b:sub(prev, entry_end + 1)
    prev = extmark_end + 2
  end
  parts[#parts + 1] = b:sub(prev)

  local out = table.concat(parts)
  out = out:sub(1, 9) .. '\0\2' .. out:sub(12)
  spew(path, out)
  return out
end

--- Builds "one" -> "ttwo" -> "three" in a throwaway session, persists it, and
--- rewrites the result as a version-2 file.  Leaves the text file holding
--- "three", which is the state the version-2 file's hash matches.
local function build_legacy_history()
  spew(fname, 'one\n')
  clear()
  command('set undodir=. undofile ul=100')
  command('edit ' .. fname)
  feed('ccttwo<esc>')
  command('set ul=100')
  feed('ccthree<esc>')
  command('set ul=100')
  command('write')
  local v3 = assert(slurp(undofile), 'no undofile was written')
  eq(3, v3:byte(11)) -- sanity: wovim really did write version 3
  to_version_2(undofile)
  eq(2, assert(slurp(undofile)):byte(11))
end

--- Opens the file fresh with 'undofile' on, so u_read_undo() finds and stashes
--- the version-2 file instead of loading or deleting it.
local function open_with_legacy()
  clear()
  command('set undodir=. undofile ul=100')
  command('edit ' .. fname)
  expect('three')
end

local function messages()
  return fn.execute('messages')
end

local function count_crossings()
  local count = 0
  for _ in messages():gmatch('older format') do
    count = count + 1
  end
  return count
end

describe('undo continuity across undofile formats', function()
  before_each(function()
    for _, f in ipairs({ fname, undofile, sibling, 'Xother.un~' }) do
      os.remove(f)
    end
  end)

  after_each(function()
    for _, f in ipairs({ fname, undofile, sibling, 'Xother.un~' }) do
      os.remove(f)
    end
  end)

  it('walks "u" past this session\'s history into an older-format undofile', function()
    build_legacy_history()
    open_with_legacy()

    feed('ccfour<esc>')
    expect('four')

    feed('u') -- this session's only change
    expect('three')

    feed('u') -- crosses the format boundary
    expect('ttwo')

    feed('u') -- keeps walking inside the older history
    expect('one')

    feed('u') -- and really is the oldest change there is
    expect('one')
    t.matches('Already at oldest change', messages())
  end)

  it('mentions crossing the boundary exactly once', function()
    build_legacy_history()
    open_with_legacy()

    feed('ccfour<esc>')
    feed('uu') -- reach the boundary and cross it
    expect('ttwo')
    eq(1, count_crossings())

    feed('uu') -- deeper, then bump into the true oldest change
    expect('one')
    eq(1, count_crossings())
  end)

  it('crosses on "g-" too, but ":undo N" stays in this session\'s history', function()
    build_legacy_history()
    open_with_legacy()

    feed('ccfour<esc>')
    feed('g-')
    expect('three')

    feed('g-') -- crosses, exactly as "u" does
    expect('ttwo')

    feed('g-')
    expect('one')

    feed('g+') -- and back out again
    expect('ttwo')
  end)

  it('refuses ":undo N" for a sequence number that only exists in the older file', function()
    build_legacy_history()
    open_with_legacy()

    feed('ccfour<esc>')
    -- This session has exactly one change, so #2 exists only in the older
    -- file.  There is no shared sequence-number space across the boundary, so
    -- it must behave like any other unknown number rather than crossing.
    t.matches('E830: Undo number 2 not found', pcall_err(command, 'undo 2'))
    expect('four')
  end)

  it("redoes back out of the older history into this session's", function()
    build_legacy_history()
    open_with_legacy()

    feed('ccfour<esc>')
    feed('uuu') -- four -> three -> ttwo -> one
    expect('one')

    feed('<C-r>')
    expect('ttwo')

    feed('<C-r>') -- last redo inside the older history
    expect('three')

    feed('<C-r>') -- crosses back out, redoing this session's own change
    expect('four')

    feed('<C-r>')
    expect('four')
    t.matches('Already at newest change', messages())
  end)

  it('never writes to the older file, using a versioned sibling instead', function()
    build_legacy_history()
    local before = assert(slurp(undofile))

    open_with_legacy()
    feed('ccfour<esc>')
    feed('uu') -- cross the boundary first
    expect('ttwo')

    command('write')

    eq(before, slurp(undofile))
    neq(nil, slurp(sibling))
    -- The sibling is wovim's own format.
    eq(3, assert(slurp(sibling)):byte(11))
  end)

  it('leaves a file with an unrecognized version alone and writes a sibling', function()
    -- The security-relevant case: not merely the one older version wovim can
    -- read, but any version it does not write.  A hardcoded exception for
    -- version 2 would still delete this one.
    spew(fname, 'one\n')
    local bogus = START_MAGIC .. '\0\99' .. string.rep('\0', 64)
    spew(undofile, bogus)

    clear()
    command('set undodir=. undofile ul=100')
    -- Refusing to *read* an unrecognized version is unchanged, and still an
    -- error.  What must not happen is the file being deleted when we write.
    t.matches('E824: Incompatible undo file', pcall_err(command, 'edit ' .. fname))
    expect('one')

    feed('cctwo<esc>')
    command('write')

    eq(bogus, slurp(undofile))
    neq(nil, slurp(sibling))
  end)

  it('finds its own sibling history back on reopen', function()
    spew(fname, 'one\n')
    spew(undofile, START_MAGIC .. '\0\99' .. string.rep('\0', 64))

    clear()
    command('set undodir=. undofile ul=100')
    t.matches('E824: Incompatible undo file', pcall_err(command, 'edit ' .. fname))
    feed('cctwo<esc>')
    command('write')
    neq(nil, slurp(sibling))

    -- Reopening must locate the sibling, not stop at the occupied bare name.
    -- The bare name still holds the unreadable file, so finding history at all
    -- proves the sibling was preferred within this 'undodir' entry.
    clear()
    command('set undodir=. undofile ul=100')
    command('edit ' .. fname)
    expect('two')
    feed('u')
    expect('one')
  end)

  it('adopts the older file outright when ":rundo" names it', function()
    build_legacy_history()
    open_with_legacy()

    -- An explicit path is an explicit request: this loads into the live tree
    -- rather than being stashed for lazy reading, so "u" needs no detour past
    -- a session history that is not there.
    command('rundo ' .. undofile)
    feed('u')
    expect('ttwo')
    feed('u')
    expect('one')

    -- And the adopted history is ordinary live history now: writable, in
    -- wovim's own format.
    command('wundo Xother.un~')
    eq(3, assert(slurp('Xother.un~')):byte(11))
  end)

  it('does not leak into an "inccommand" preview rollback', function()
    -- 'inccommand' detaches the undo tree, builds a disposable one for the
    -- preview, then unwinds it. That unwind drives the same loop "u" does, so
    -- it must not be able to walk out of the speculative tree and into the
    -- user's real older history.
    build_legacy_history()
    open_with_legacy()

    command('set inccommand=nosplit')
    feed('ccalpha bravo<esc>')
    feed(':%s/bravo/charlie') -- previewing, not yet submitted
    feed('<esc>') -- abandon it: the preview tree is rolled back
    expect('alpha bravo')

    -- Undo still behaves exactly as it would have without the preview.
    feed('u')
    expect('three')
    feed('u')
    expect('ttwo')
  end)

  it('resumes where it left off when a change is made mid-walk', function()
    build_legacy_history()
    open_with_legacy()

    feed('ccfour<esc>')
    feed('uu') -- cross into the older history
    expect('ttwo')

    feed('ccfive<esc>') -- edit from inside it
    expect('five')

    feed('u') -- undoes the edit, not an older-history change
    expect('ttwo')

    -- Resumes *below* where the walk left off.  Restarting at the newest
    -- older-history change instead would produce "three" here.
    feed('u')
    expect('one')
  end)
end)

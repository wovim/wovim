local t = require('test.testutil')
local n = require('test.functional.testnvim')()

local describe, it, before_each, after_each = t.describe, t.it, t.before_each, t.after_each
local eq = t.eq
local pcall_err = t.pcall_err
local clear = n.clear
local api = n.api
local fn = n.fn
local rmdir = n.rmdir
local write_file = t.write_file
local mkdir = t.mkdir

local testdir = 'Xtest-functional-spell-spellfile.d'

describe('spellfile', function()
  before_each(function()
    clear({ env = { XDG_DATA_HOME = testdir .. '/xdg_data' } })
    rmdir(testdir)
    mkdir(testdir)
    mkdir(testdir .. '/spell')
  end)
  after_each(function()
    rmdir(testdir)
  end)
  --                   ┌ Magic string (#VIMSPELLMAGIC)
  --                   │       ┌ Spell file version (#VIMSPELLVERSION)
  local spellheader = 'VIMspell\050'
  it('errors out when prefcond section is truncated', function()
    api.nvim_set_option_value('runtimepath', testdir, {})
    -- stylua: ignore
    write_file(testdir .. '/spell/en.ascii.spl',
    --                         ┌ Section identifier (#SN_PREFCOND)
    --                         │   ┌ Section flags (#SNF_REQUIRED or zero)
    --                         │   │   ┌ Section length (4 bytes, MSB first)
               spellheader .. '\003\001\000\000\000\003'
    --             ┌ Number of regexes in section (2 bytes, MSB first)
    --             │       ┌ Condition length (1 byte)
    --             │       │   ┌ Condition regex (missing!)
               .. '\000\001\001')
    api.nvim_set_option_value('spelllang', 'en', {})
    t.matches('Vim%(set%):E758: Truncated spell file', pcall_err(n.command, 'set spell'))
  end)
  it('errors out when prefcond regexp contains NUL byte', function()
    api.nvim_set_option_value('runtimepath', testdir, {})
    -- stylua: ignore
    write_file(testdir .. '/spell/en.ascii.spl',
    --                         ┌ Section identifier (#SN_PREFCOND)
    --                         │   ┌ Section flags (#SNF_REQUIRED or zero)
    --                         │   │   ┌ Section length (4 bytes, MSB first)
               spellheader .. '\003\001\000\000\000\008'
    --             ┌ Number of regexes in section (2 bytes, MSB first)
    --             │       ┌ Condition length (1 byte)
    --             │       │   ┌ Condition regex
    --             │       │   │       ┌ End of sections marker
               .. '\000\001\005ab\000cd\255'
    --             ┌ LWORDTREE tree length (4 bytes)
    --             │               ┌ KWORDTREE tree length (4 bytes)
    --             │               │               ┌ PREFIXTREE tree length
               .. '\000\000\000\000\000\000\000\000\000\000\000\000')
    api.nvim_set_option_value('spelllang', 'en', {})
    t.matches('Vim%(set%):E759: Format error in spell file', pcall_err(n.command, 'set spell'))
  end)
  it('errors out when region contains NUL byte', function()
    api.nvim_set_option_value('runtimepath', testdir, {})
    -- stylua: ignore
    write_file(testdir .. '/spell/en.ascii.spl',
    --                         ┌ Section identifier (#SN_REGION)
    --                         │   ┌ Section flags (#SNF_REQUIRED or zero)
    --                         │   │   ┌ Section length (4 bytes, MSB first)
               spellheader .. '\000\001\000\000\000\008'
    --             ┌ Regions  ┌ End of sections marker
               .. '01234\00067\255'
    --             ┌ LWORDTREE tree length (4 bytes)
    --             │               ┌ KWORDTREE tree length (4 bytes)
    --             │               │               ┌ PREFIXTREE tree length
               .. '\000\000\000\000\000\000\000\000\000\000\000\000')
    api.nvim_set_option_value('spelllang', 'en', {})
    t.matches('Vim%(set%):E759: Format error in spell file', pcall_err(n.command, 'set spell'))
  end)
  it('errors out when SAL section contains NUL byte', function()
    api.nvim_set_option_value('runtimepath', testdir, {})
    -- stylua: ignore
    write_file(testdir .. '/spell/en.ascii.spl',
    --                         ┌ Section identifier (#SN_SAL)
    --                         │   ┌ Section flags (#SNF_REQUIRED or zero)
    --                         │   │   ┌ Section length (4 bytes, MSB first)
               spellheader .. '\005\001\000\000\000\008'
    --             ┌ salflags
    --             │   ┌ salcount (2 bytes, MSB first)
    --             │   │       ┌ salfromlen (1 byte)
    --             │   │       │   ┌ Special character
    --             │   │       │   │┌ salfrom (should not contain NUL)
    --             │   │       │   ││   ┌ saltolen
    --             │   │       │   ││   │   ┌ salto
    --             │   │       │   ││   │   │┌ End of sections marker
               .. '\000\000\001\0024\000\0017\255'
    --             ┌ LWORDTREE tree length (4 bytes)
    --             │               ┌ KWORDTREE tree length (4 bytes)
    --             │               │               ┌ PREFIXTREE tree length
               .. '\000\000\000\000\000\000\000\000\000\000\000\000')
    api.nvim_set_option_value('spelllang', 'en', {})
    t.matches('Vim%(set%):E759: Format error in spell file', pcall_err(n.command, 'set spell'))
  end)
  it('errors out when spell header contains NUL bytes', function()
    api.nvim_set_option_value('runtimepath', testdir, {})
    write_file(testdir .. '/spell/en.ascii.spl', spellheader:sub(1, -3) .. '\000\000')
    api.nvim_set_option_value('spelllang', 'en', {})
    t.matches(
      'Vim%(set%):E757: This does not look like a spell file',
      pcall_err(n.command, 'set spell')
    )
  end)

  it('can be set to a relative path', function()
    local fname = testdir .. '/spell/spell.add'
    api.nvim_set_option_value('spellfile', fname, {})
  end)

  it('can be set to an absolute path', function()
    local fname = fn.fnamemodify(testdir .. '/spell/spell.add', ':p')
    api.nvim_set_option_value('spellfile', fname, {})
  end)

  describe('default location', function()
    it("is stdpath('data')/site/spell/en.utf-8.add", function()
      n.command('set spell')
      n.insert('abc')
      n.feed('zg')
      eq(
        ('%s/site/spell/en.utf-8.add'):format(fn.stdpath('data')),
        api.nvim_get_option_value('spellfile', {})
      )
    end)

    it("is not set if stdpath('data') is not writable", function()
      n.command('set spell')
      fn.writefile({ '' }, testdir .. '/xdg_data')
      n.insert('abc')
      eq("Vim(normal):E764: Option 'spellfile' is not set", pcall_err(n.command, 'normal! zg'))
    end)

    it("is not set if 'spelllang' is not set", function()
      n.command('set spell spelllang=')
      n.insert('abc')
      eq("Vim(normal):E764: Option 'spellfile' is not set", pcall_err(n.command, 'normal! zg'))
    end)

    it('accepts overwrites on midword and syllable section, errors on memory leak', function()
      api.nvim_set_option_value('runtimepath', testdir, {})
      -- stylua: ignore

      -- Set SN_MIDWORD and SN_SYLLABLE twice so the loader overwrites lp->sl_midword. Should
      -- not leak memory.
      write_file(testdir .. '/spell/en.ascii.spl',
                 spellheader
    --            ┌ Section identifier (#SN_MIDWORD)
    --            │   ┌ Section flags (#SNF_REQUIRED or zero)
    --            │   │   ┌ Section length (4 bytes, MSB first)
              .. '\002\001\000\000\000\003abc'  -- SN_MIDWORD (midword = "abc")
              .. '\002\001\000\000\000\003def'  -- Overwrites SN_MIDWORD (midword = "def")
    --            ┌ Section identifier (#SN_SYLLABLE)
    --            │   ┌ Section flags (#SNF_REQUIRED or zero)
    --            │   │   ┌ Section length (4 bytes, MSB first)
              .. '\009\001\000\000\000\003ghi'  -- SN_SYLLABLE (syllable = "ghi")
              .. '\009\001\000\000\000\003jib'  -- Overwrites SN_SYLLABLE (syllable = "jib")
              .. '\255'                         -- End of sections marker
              .. '\000\000\000\000'             -- LWORDTREE len
              .. '\000\000\000\000'             -- KWORDTREE len
              .. '\000\000\000\000'             -- PREFIXTREE len
      )

      api.nvim_set_option_value('spelllang', 'en', {})
      n.command('set spell') -- Should not error
      eq(true, api.nvim_get_option_value('spell', {}))
    end)
  end)
end)

describe("'spellsuggest' file:", function()
  local sugfile = 'Xtest-functional-spellsuggest.sug'

  before_each(function()
    clear()
  end)
  after_each(function()
    os.remove(sugfile)
  end)

  -- A "file:" wordlist is arbitrary user data, so its good word may be longer
  -- than MAXWLEN (254).  make_case_word() used to strcpy() it into the MAXWLEN
  -- stack buffer that spell_suggest_file() passes in, overflowing it.
  it('truncates a good word longer than MAXWLEN', function()
    -- spell_suggest_file() reads at most MAXWLEN * 2 bytes per line, so 497
    -- bytes is about the longest good word it can hand to make_case_word().
    -- Whole words separated by spaces, so the suggestion survives the
    -- "is this suggestion itself misspelled?" filter and reaches spellsuggest().
    local goodword = ('hello '):rep(83):sub(1, -2)
    eq(497, #goodword)
    write_file(sugfile, 'helloi/' .. goodword .. '\n')

    n.command('set spell spelllang=en')
    n.command('set spellsuggest=file:' .. sugfile)

    local suggestions = fn.spellsuggest('helloi', 5)
    n.assert_alive()
    eq(1, #suggestions)
    -- MAXWLEN - 1 bytes, the most that fits alongside the NUL.
    eq(253, #suggestions[1])
    eq(goodword:sub(1, 253), suggestions[1])
  end)

  it('leaves a good word shorter than MAXWLEN alone', function()
    local goodword = ('hello '):rep(20):sub(1, -2)
    eq(119, #goodword)
    write_file(sugfile, 'helloi/' .. goodword .. '\n')

    n.command('set spell spelllang=en')
    n.command('set spellsuggest=file:' .. sugfile)

    eq({ goodword }, fn.spellsuggest('helloi', 5))
  end)

  -- check_suggestions() copies the suggestion into a MAXWLEN + 1 stack buffer
  -- and then appends the not-replaced tail of the bad word after it.  It used
  -- to append at st_wordlen, the length of the suggestion *before* that
  -- truncating copy.  A good word longer than MAXWLEN therefore put the
  -- destination past the end of the buffer, and made the remaining-size
  -- argument underflow to a huge size_t, so the append was unbounded too.
  it('appends the bad word tail at the truncated length', function()
    -- Capitalised, so spell_suggest_file() leaves it to captype() instead of
    -- make_case_word(), and the full 497 bytes reach add_suggestion().
    local goodword = 'Hello' .. (' hello'):rep(82)
    eq(497, #goodword)
    write_file(sugfile, 'helloi/' .. goodword .. '\n')

    n.command('set spell spelllang=en')
    n.command('set spellsuggest=file:' .. sugfile)

    -- Text after the bad word, so the out-of-bounds append copies a long run of
    -- bytes rather than a single stray NUL.
    local tail = ' ' .. ('x'):rep(250)
    local suggestions = fn.spellsuggest('helloi' .. tail, 5)
    n.assert_alive()
    eq(1, #suggestions)
    -- The suggestion itself is not truncated, only the scratch copy used to
    -- check whether the suggestion is misspelled.
    eq(goodword .. tail, suggestions[1])
  end)

  it('leaves a capitalised good word shorter than MAXWLEN alone', function()
    local goodword = 'Hello' .. (' hello'):rep(19)
    eq(119, #goodword)
    write_file(sugfile, 'helloi/' .. goodword .. '\n')

    n.command('set spell spelllang=en')
    n.command('set spellsuggest=file:' .. sugfile)

    local tail = ' ' .. ('x'):rep(250)
    eq({ goodword .. tail }, fn.spellsuggest('helloi' .. tail, 5))
  end)
end)

describe("'spellsuggest' expr:", function()
  before_each(function()
    clear()
  end)

  -- The same check_suggestions() overflow through the other door.  An "expr:"
  -- suggestion is arbitrary user data as well, and unlike a "file:" wordlist
  -- entry it is not even bounded by a MAXWLEN * 2 line buffer.
  it('appends the bad word tail at the truncated length', function()
    -- Nearly twice MAXWLEN, and longer than a "file:" line could ever be.
    local goodword = 'Hello' .. (' hello'):rep(165)
    eq(995, #goodword)
    api.nvim_set_var('goodword', goodword)

    n.command('set spell spelllang=en')
    n.exec([==[
      func XSuggest()
        return [[g:goodword, 0]]
      endfunc
      set spellsuggest=expr:XSuggest()
    ]==])

    local tail = ' ' .. ('x'):rep(250)
    local suggestions = fn.spellsuggest('helloi' .. tail, 5)
    n.assert_alive()
    eq(1, #suggestions)
    eq(goodword .. tail, suggestions[1])
  end)
end)

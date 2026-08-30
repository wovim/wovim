# Undo Continuity

**Status:** implemented (`src/nvim/undo.c`, commit `805589c643`)

Persistent undo silently loses history across a format change. The fix is
a value already proven in this same codebase, for a different file.

## Contents

1. [The failure mode](#1-the-failure-mode)
2. [The north star](#2-the-north-star)
3. [Precedent already in this codebase](#3-precedent-already-in-this-codebase)
4. [The mechanism](#4-the-mechanism)
5. [Scope check](#5-scope-check)
6. [What this deliberately does not do](#6-what-this-deliberately-does-not-do)
7. [How the open questions were settled](#7-how-the-open-questions-were-settled)
8. [References](#8-references)

## 1. The failure mode

Security researcher David Chisnall described trying Neovim years ago and
finding his persistent undo history simply gone. Not corrupted — deleted.
Neovim had recognized the file as a Vim undo file, in a format it no longer
wrote, and replaced it. He raised it upstream and was told the format was
unstable and not to rely on it. His verdict, quoted by Marcin Wichary: the
maintainers had "no concept of a duty of care to their users."

This fork's own code confirms that story directly. `u_write_undo()`
checks whether a file already sits at the
undo-file path; if it does, it reads only the four-byte magic prefix, and
if that matches, it deletes the file unconditionally before writing a fresh
one — without ever inspecting the version field.

> **`src/nvim/undo.c:1206–1245`**
> Recognizes any file whose magic bytes match — any generation, any writer
> — then calls `os_remove(file_name)` unconditionally. The version check
> exists only on the *read* path (`E824: Incompatible undo file`), which
> has no say over what the write path is about to do.

The read-side rejection is fine, arguably correct — Chisnall himself called
that forgivable as a bug. What isn't forgivable, in his framing and in
ours, is deleting data nobody asked to have deleted.

## 2. The north star

Not-destroying his history is only the floor. The actual thing to
build toward is the moment itself: he opens a file with years of Vim undo
history sitting next to it, and either he notices what wovim did for him
and is delighted, or — better — he never notices anything happened at all,
because `u` and `g-` just keep working, straight through the exact
transition that used to erase them.

His own words describe the workflow this has to survive intact: undo back
until he finds what he's looking for, copy it, paste it into the current
version. That has to keep working the day he switches editors, not stop at
whatever moment wovim's own history begins.

Everything below is one question: what's the smallest, most honest
mechanism that produces *that* moment, rather than a moment where his data
merely survived somewhere he'd have to go looking for it?

## 3. Precedent already in this codebase

This isn't a value we'd be importing. Neovim already holds it, just
unevenly — stated outright for the plugin API, and fully implemented for a
sibling persistent file.

### Stated as a design goal

> **`runtime/doc/dev.txt` — `design-goals`**
> "Backwards compatibility is a feature. The RPC API in particular should
> never break."

The RPC API gets this guarantee by name. The one persistent file holding a
user's actual editing history does not.

### Fully implemented, for ShaDa

ShaDa (marks, registers, command history — Neovim's successor to
`viminfo`) already does most of what this proposal needs, for a different
file:

> **`runtime/doc/starting.txt:1042–1074` — `shada-compatibility`**
> "ShaDa files are forward and backward compatible." Unknown entries are
> ignored on read and copied through, untouched, on write — no
> version-locked rejection.

> **`runtime/doc/starting.txt:1115–1125` — `shada-error-handling`**
> Writes go to a temp file, then rename over the target — never
> remove-then-create. And: "non-ShaDa files are not overwritten for safety
> reasons, to avoid accidentally destroying an unrelated file."

Safe atomic write and refuse-to-touch-what-you're-not-sure-about are both
already implemented, tested, and shipping, one subsystem over. What ShaDa
doesn't need, and undo does, is the last piece: something that reaches
*into* the incompatible file, not just around it.

### And for files it isn't sure about

Neovim already has a third pattern for exactly this class of problem: a
swap file it doesn't recognize or doesn't own is never silently deleted.
It raises the ATTENTION dialog and makes the user choose.

> **`src/nvim/fileio.c:597`** (context)
> The ATTENTION flow exists precisely so an uncertain, possibly-someone's
> file never gets acted on without a decision.

Undo files don't need the dialog itself — prompting on every save would
violate the second half of Raskin's rules on its own (don't waste the
user's time) — but the underlying instinct, *don't act on a file you
haven't earned the right to touch*, is exactly right, and carries straight
over.

## 4. The mechanism

**Never write the old file. Read it lazily, on the exact keystroke that
needs it.**

Today, `u`/`g-` walking backward stops the moment the in-session undo tree
bottoms out. This file already has a message ready for exactly that point:

> **`src/nvim/undo.c:2177`**
> `msg(_("Already at oldest change"), 0);`

That is the seam. If an older-format file sits at the buffer's undo path
when this line would fire, don't fire it — read that file instead (once,
lazily, read-only) and keep walking into it as more tree. The user's `u`
key doesn't change meaning. It just keeps working.

**Never touch what's already there, ever, in either direction.** The old
file is never rewritten, because wovim never becomes its writer. New undo
state goes into wovim's own file. If the canonical undo path is occupied
by a version wovim doesn't write, wovim writes its own live history to a
version-tagged sibling instead of taking that name for itself — so the old
file keeps living exactly where a real Vim, or an older wovim, already
expects to find it. That's not just safety; it's what makes "use both Vim
and Neovim on the same files without losing history," the thing a user
actually asked for in the GitHub thread on this exact break, genuinely
possible rather than merely non-destructive.

**One quiet acknowledgment, the first time it happens.** Not a dialog.
Reuse the message idiom already sitting a few lines from the seam itself —
the same family as "Already at oldest change" — for exactly one line, the
first time a walk crosses into legacy history: something like "(now in
Vim history, before 2021)". Enough that he can tell, if he looks, that the
software knew what it was doing. Not enough to interrupt him for it.

**One piece of machinery, two doors.** The read-only legacy-format parser
this needs is the same code an explicit "make this permanent" command
would need anyway, for anyone who'd rather consolidate the two files into
one and stop carrying the old one forward. Building the lazy path first
turns that command into a promotion of already-working code, sparing it a
second implementation of the same parser.

## 5. Scope check

The obvious worry with "read an old format" is open-ended maintenance. It
isn't, here — the format has moved exactly once since the fork, and the
mechanism above needs no redesign at the next move either.

| When | Commit | What |
|---|---|---|
| 2014-01-31 | `72cf89bce` | Neovim imports Vim's `undo.c` wholesale. `UF_VERSION` already at 2; this is Vim's own original format, inherited, not authored. |
| 2021-02-19 | `f42e932df` | "Extmarks: Save extmark undo information to undofile." `UF_VERSION` 2 → 3 — the *only* bump in the file's tracked history, and it's this exact break that produced the two GitHub issues below, not casual churn. A real feature (extmarks don't exist in Vim). |
| today | — | Still version 3. Exactly one legacy reader (format 2) covers the entire history of this file, in both directions, at every point since the fork. |

And because the rule is "whatever version I find but don't currently
write, read it lazily if I still can" rather than a hardcoded list, the
*next* format bump doesn't need this document revisited — it just adds
one more sibling the live version might someday walk into, the same way
version 3 would walk into version 2 today.

## 6. What this deliberately does not do

**It does not rewrite old bytes, ever.** No legacy writer exists or needs
to. The only code that ever has to understand a historical format is a
reader, invoked lazily or by explicit request — irrelevant to whether an
ordinary save is correct.

**It does not merge trees.** The live tree and the legacy tree stay two
distinct trees on disk, connected only by the walk. Nothing about this
design tries to splice sequence numbers or reconcile timestamps across the
boundary — the boundary is real; it stays invisible in normal use because
crossing it is an ordinary tree-walk.

**It does not need to solve the general N-format problem.** It only ever
needs to answer "what's the one file immediately behind the one I'm
writing," which per §5 has had exactly one answer for over a decade.

## 7. How the open questions were settled

**The acknowledgment line.** A one-shot `msg()` (not `echomsg`, not an
error) the first time a walk crosses the boundary, gated behind
`'shortmess'`'s `u` flag like the existing undo messages: `Now in undo
history from an older format`. `:messages`-visible, not repeated on
subsequent crossings for the same buffer — matches the "discoverable if
you look, invisible if you don't" constraint without inventing a new
message convention for it.

**The promotion command's shape.** No new command. `:rundo {file}` was
already the door for loading an explicit path; naming the old file that
way now takes the same full-install path as any other `:rundo`, rather
than the lazy stash a plain `u`/`g-` walk uses. Explicit path in, explicit
adoption out.

**Sibling-file naming.** `.un3~` — the bare `.un~` suffix with
`UF_VERSION` spliced in, derived at compile time so a future version bump
renames it automatically. Distinguishable at a glance, and not a name any
real Vim or an unpatched wovim would produce on its own.

## 8. References

- **Primary.** David Chisnall, Mastodon post, 2026-08-28 —
  <https://infosec.exchange/@david_chisnall/117171776562702259>
- **Secondary.** Marcin Wichary, "They had no concept of a duty of care to
  their users," *Unsung*, 2026-08-28 —
  <https://unsung.aresluna.org/they-had-no-concept-of-a-duty-of-care-to-their-users/>.
  Also the source for Raskin's First Law, cited there from *The Humane
  Interface* (2000).
- **Issue.** [neovim/neovim#17301](https://github.com/neovim/neovim/issues/17301),
  "nvim can't read vim's undo files" — closed `wontfix`, 2022. Includes the
  "I want to switch vim to nvim or even use both w/o having to lose years
  of my edit history" comment this design is built to satisfy.
- **Issue.** [neovim/neovim#14978](https://github.com/neovim/neovim/issues/14978),
  request for a 0.4→0.5 undofile converter — closed as "never materialized,"
  2021–2022. The community-attempted script is linked from the thread.
- **Source.** `src/nvim/undo.c`: `u_write_undo()` at 1168, the
  unconditional delete at 1206–1245; `u_read_undo()` at 1409, the version
  check at 1473–1477; the "Already at oldest/newest change" seam at
  2177/2179 (and its sibling at 1936/1949).
- **Source.** `runtime/doc/dev.txt` (design-goals), `runtime/doc/starting.txt`
  (shada-compatibility, shada-error-handling) — shipped in this repo,
  quoted above.

---

*wovim — local fork, improved for its own sake. Not filed upstream.*

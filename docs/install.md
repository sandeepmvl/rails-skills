# Installing rails-skills in your AI coding tool

`rails-skills` follows the [Anthropic Skills open standard](https://docs.claude.com): every skill is a directory under `skills/` containing a `SKILL.md` (YAML frontmatter + markdown body). Any tool that can read a directory of skill/rule/context files can use them.

The universal mechanism is the same everywhere:

1. **Clone the pack** somewhere your tool can read it.
2. **Point your tool at it** — either by cloning directly into the tool's skills/rules directory, or by referencing the cloned path from the tool's context file.

The orchestrator skill (`00-rails-project-discovery`) is the entry point — once the pack is visible to your agent, ask it to "use rails-project-discovery" (or just start a Rails task) and it routes to the right downstream skills.

---

## Two install modes — pick one

You don't have to clone this into every project. Choose based on how you work:

| Mode | Install location | Best for |
|---|---|---|
| **Global (recommended for most devs)** | one shared directory (e.g. `~/.claude/skills/`) | you work across many projects — Rails and non-Rails — and want the pack available everywhere without re-cloning |
| **Per-project** | inside one repo (e.g. `.claude/skills/`) | you want the pack pinned/versioned with a single app, or committed alongside a specific project |

### Why global is safe even on non-Rails projects

Skills are **description-gated** — each one only activates when the task matches its trigger description. On a React, Go, or Python project, the Rails skills stay **dormant**: they cost nothing and never interfere. They wake up only when you actually work on Rails (or when you explicitly invoke `rails-project-discovery`). So a single global install gives you Rails expertise on demand, everywhere, with zero noise elsewhere.

### Activate on demand

Even with a global install, you can force the pack on for a given task:

```
use the rails-project-discovery skill
```

or just start a Rails task ("add a model", "fix this N+1", "write a migration") and the orchestrator triggers itself.

### Global install locations by tool

Clone once into the tool's user-level directory, then it's available in every project:

| Tool | Global location | Command |
|---|---|---|
| Claude Code | `~/.claude/skills/` | `git clone https://github.com/sandeepmvl/rails-skills ~/.claude/skills/rails-skills` |
| Cursor | `~/.cursor/skills/` | `git clone https://github.com/sandeepmvl/rails-skills ~/.cursor/skills/rails-skills` |
| OpenAI Codex | `~/.codex/` (referenced from global `~/.codex/AGENTS.md`) | `git clone https://github.com/sandeepmvl/rails-skills ~/.codex/rails-skills` |
| Gemini CLI | `~/.gemini/` (referenced from `~/.gemini/GEMINI.md`) | `git clone https://github.com/sandeepmvl/rails-skills ~/.gemini/rails-skills` |
| Windsurf | `~/.codeium/windsurf/` global rules | `git clone https://github.com/sandeepmvl/rails-skills ~/.codeium/windsurf/rails-skills` |

> Paths are tool- and version-specific and evolving. If your tool doesn't auto-discover a global skills directory, reference the cloned path from that tool's **global** context/rules file (the user-level `CLAUDE.md` / `AGENTS.md` / `GEMINI.md` / rules) the same way the per-project sections below show — just point at the home-directory path instead of the in-repo one.

**Update everywhere at once:** with a single global clone, `git -C <global-path>/rails-skills pull` updates the pack for all your projects.

---

> **Note on portability:** the Skills open standard is young (released December 2025). Native skill discovery is first-class in Claude Code and Claude.ai. Other tools consume the same `SKILL.md` files through their existing rules/context mechanism. Where a tool's path differs by version, adapt the directory below to match your install.

---

## Claude Code

```bash
cd <your-rails-app>
git clone https://github.com/sandeepmvl/rails-skills .claude/skills
```

Start Claude Code in the project. Skills are auto-discovered from `.claude/skills/`. The orchestrator interviews you and loads the relevant skills.

**Global install** (available in every project):

```bash
git clone https://github.com/sandeepmvl/rails-skills ~/.claude/skills/rails-skills
```

---

## Claude.ai / Claude API

Upload the individual skill folders, or reference them via the API's skills mechanism. Each `skills/<name>/` directory is a self-contained skill — package the ones you need.

---

## Cursor

```bash
cd <your-rails-app>
git clone https://github.com/sandeepmvl/rails-skills .cursor/skills
```

Cursor reads project rules/skills from `.cursor/`. Reference the orchestrator from your `.cursorrules` or project rules if Cursor does not auto-load the directory in your version:

```
When working on Rails code, consult the skills in .cursor/skills/,
starting with 00-rails-project-discovery.
```

---

## OpenAI Codex

Codex reads project guidance from `AGENTS.md`. Clone the pack and point `AGENTS.md` at it:

```bash
cd <your-rails-app>
git clone https://github.com/sandeepmvl/rails-skills .agent/rails-skills
```

Add to `AGENTS.md`:

```markdown
## Rails conventions
This project uses the rails-skills pack in `.agent/rails-skills/skills/`.
Before writing or reviewing Rails code, read the relevant SKILL.md —
start with `00-rails-project-discovery/SKILL.md` to pick the right skills.
```

---

## Gemini CLI

Gemini CLI reads project context from `GEMINI.md` (and supports extensions). Clone the pack and reference it:

```bash
cd <your-rails-app>
git clone https://github.com/sandeepmvl/rails-skills .gemini/rails-skills
```

Add to `GEMINI.md`:

```markdown
Rails work in this repo follows the skills in `.gemini/rails-skills/skills/`.
Consult `00-rails-project-discovery/SKILL.md` first, then the relevant skill.
```

---

## Antigravity

Clone the pack into your workspace and reference the skills directory from your Antigravity project rules/context, pointing the agent at `skills/00-rails-project-discovery/SKILL.md` as the entry point:

```bash
cd <your-rails-app>
git clone https://github.com/sandeepmvl/rails-skills .antigravity/rails-skills
```

---

## Windsurf

Windsurf reads rules from `.windsurf/rules/`. Clone the pack and reference it from a rules file:

```bash
cd <your-rails-app>
git clone https://github.com/sandeepmvl/rails-skills .windsurf/rails-skills
```

Add a `.windsurf/rules/rails-skills.md`:

```markdown
For Rails code, use the skills in .windsurf/rails-skills/skills/.
Start with 00-rails-project-discovery to route to the right skill.
```

---

## Keeping the pack updated

Whichever tool you use, pull the latest skills with:

```bash
cd <path-to-cloned-rails-skills>
git pull origin main
```

Pin to a release tag for reproducibility:

```bash
git fetch --tags
git checkout v0.1.0
```

---

## Adding to `.gitignore`

If you clone the pack *inside* your Rails app, ignore it so it doesn't get committed into your app's repo:

```
# .gitignore in your Rails app
.claude/skills/
.cursor/skills/
```

(Adjust to whichever directory your tool uses.)

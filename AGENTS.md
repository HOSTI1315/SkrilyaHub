# AGENTS.md

## Cursor Cloud specific instructions

This repository contains **Roblox Lua (Luau) game automation scripts** for the "SkrilyaHub" project. There is no traditional build system, package manager, CI pipeline, or test framework. The scripts are designed to execute inside the Roblox game client via third-party script executors and cannot be run end-to-end locally.

### Available tooling

| Tool | Purpose | Command |
|------|---------|---------|
| **selene** | Roblox-aware Lua linter (preferred) | `selene <file>` |
| **luacheck** | Standard Lua linter | `luacheck <file>` |
| **StyLua** | Lua code formatter | `stylua --check <file>` or `stylua <file>` |
| **lua5.4** | Lua interpreter (syntax verification) | `lua5.4 -e "..."` |

### Linting

- **Selene** (`selene.toml` configured with `std = "roblox"`) is the primary linter — it understands Roblox/Luau globals and APIs natively. Run `selene .` to lint all files.
- **Luacheck** (`.luacheckrc`) is also configured but may report false positives for Luau-specific features like `continue`, `table.find`, and `math.clamp` since it uses the Lua 5.1 standard.
- **StyLua** (`stylua.toml`) handles formatting checks. Run `stylua --check .` to verify formatting.

### File naming

Some script files have unusual names (spaces, special characters, emoji, no `.lua` extension). Always quote filenames in shell commands.

### Key caveats

- These scripts use Roblox executor-specific APIs (`getgenv`, `syn.request`, `queue_on_teleport`, `loadstring(game:HttpGet(...))`, etc.) that do not exist in standard Lua. They cannot be executed locally.
- UI libraries (FluentPlus, Kairo) are loaded at runtime via HTTP from GitHub. There are no local dependencies to install.
- The `Code.txt` file contains redeemable game codes for Re:Rangers X.
- Comments in the scripts are primarily in Russian.

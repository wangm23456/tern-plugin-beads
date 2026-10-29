# Tern Beads Plugin

[Beads (bd)](https://github.com/gastownhall/beads) issue tracker board for [Tern](https://stencil.so/tern).

Provides a rich visual task management dashboard in Tern terminal:

- Filter issues by status: Ready (`bd ready`), In Progress, Blocked, Done, or All.
- Interactive keyboard shortcuts (`c` claim, `x` close, `u` reopen, `p` priority rotation, `n` new issue).
- Mouse click support for status tabs, priority buttons, and project switching.
- Multi-project workspace switcher.

## Prerequisites

- [Tern Terminal](https://stencil.so/tern)
- [Beads CLI (`bd`)](https://github.com/gastownhall/beads) installed in `PATH` (e.g. `~/.local/bin/bd` or `/opt/homebrew/bin/bd`).

## Installation

```bash
mkdir -p ~/.config/tern/plugins
git clone https://github.com/wangm23456/tern-plugin-beads.git ~/.config/tern/plugins/beads
```

## Usage

In Tern command palette (`Cmd+P` or `Ctrl+P`):

- `开启当前焦点项目的 Beads 看板`: opens the board beside your active terminal pane.
- `Beads: 选择项目打开任务看板`: select from known project directories.

# ⚜️Lspmark.nvim

A Sane[^1] Project-wise[^2] Bookmarks Plugin with Persistent[^3] Storage Based on LSP[^4] for Neovim.

There is a bunch of bookmark plugins but none of them suit my demand, if you also finding a bookmark plugin that can:

1. Organize the bookmarks in project-wise since in most of my time I open Neovim in a project (cwd) and jump here and there,
2. Persistent the bookmarks across different Neovim launches.
3. Try to lay the bookmarks in the right place even after a format.
4. Can be deleted and pasted to other place, even not current file.
5. Use telescope to browse, jump or delete all the bookmarks.
6. …

Then not only the bookmarks, but also you, are in the right place. Let me show you the features one by one:

## Features

<details>
  <summary>Persistent bookmarks</summary>
  
  ![persistent](https://github.com/tristone13th/lspmark.nvim/assets/17382962/b23b3c5a-b489-45c5-b5a3-afbc57590c47)
</details>

<details>
  <summary>Persist bookmarks after format</summary>
  
  ![format](https://github.com/tristone13th/lspmark.nvim/assets/17382962/cdf24f0f-e2c5-49b3-82c2-94295c51d64c)
</details>

<details>
  <summary>Delete and paste bookmarks in 1 buffer</summary>
  
  ![buffer](https://github.com/tristone13th/lspmark.nvim/assets/17382962/6639c3c6-7900-40b8-b681-c3f48255a016)
</details>

<details>
  <summary>Delete and paste across buffers</summary>
  
  ![buffers](https://github.com/tristone13th/lspmark.nvim/assets/17382962/6447be15-860e-405e-ad4d-f1cd997dd94a)
</details>

<details>
  <summary>Telescope integration</summary>
  
  ![telescope](https://github.com/tristone13th/lspmark.nvim/assets/17382962/9944a07c-6d29-4a4c-a473-9d088f9902c3)
</details>

## Setup & Usage

All you need to do is installing it using your favorite plugin manager and run the following code after installation:

```lua
require("lspmark").setup()
require("telescope").load_extension("lspmark")
```

and bind the following functions to your preferred keys:

- Your key to paste text (`p`): `require('lspmark.bookmarks').paste_text()`;
- Your key to toggle the mark: `require('lspmark.bookmarks').toggle_bookmark()`;
- Your key to delete text in visual mode (`d`): `require('lspmark.bookmarks').delete_visual_selection()`;
- Your key to delete one line (`dd`): `lua require('lspmark.bookmarks').delete_line()`.

To open the telescope window, you can run `Telescope lspmark`, to delete current selection in the telescope picker, you can press `d`.

## FAQ

### What's the rationale behind the feature "delete and paste"?

This plugin does not just aim for code navigating, it is also for code refactoring/writing, during which we will move the code snippets around frequently, so developers won't want to lose their bookmarks in a code snippet just because it is moved from a place to another.

### Why bookmarking with the help of LSP information?

The symbols in LSP could be considered as the basic logical element for coding. For example, when we format, a line of text could be added, deleted, or even moved to another place, but the LSP symbols in the document won't change a lot. With the help of the information on each LSP symbol, we only need to save each bookmark's offset in that symbol so most of the bookmarks will be kept in their original place, given the fact that most of the developers prefer incremental format rather than format a file entirely. So only the bookmarks in the formatted symbols will be affected and may be placed in another place. This plugin aims to try to keep each bookmark in the place it should be. If you have any ideas to mitigate this, don't hesitate to submit an issue or PR!

[^1]: "Sane" means it will try best to respect your intuition.
[^2]: "Project-wise" means the bookmarks are organized according to the cwd (project).
[^3]: "Persistent" means the bookmarks will be saved to file so they won't be lost when nvim is opened next time.
[^4]: "LSP" means we store each bookmark's information associated with their LSP symbol.


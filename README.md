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

### Persistent bookmarks

![persistent](https://github.com/tristone13th/lspmark.nvim/assets/17382962/b23b3c5a-b489-45c5-b5a3-afbc57590c47)

### Persist bookmarks after format

![format](https://github.com/tristone13th/lspmark.nvim/assets/17382962/cdf24f0f-e2c5-49b3-82c2-94295c51d64c)

### Delete and paste bookmarks in 1 buffer

![buffer](https://github.com/tristone13th/lspmark.nvim/assets/17382962/6639c3c6-7900-40b8-b681-c3f48255a016)

### Delete and paste across buffers

![buffers](https://github.com/tristone13th/lspmark.nvim/assets/17382962/6447be15-860e-405e-ad4d-f1cd997dd94a)

### Telescope integration

![telescope](https://github.com/tristone13th/lspmark.nvim/assets/17382962/9944a07c-6d29-4a4c-a473-9d088f9902c3)

## Setup & Usage

All you need to do is install it using your favorite plugin manager and run the following code after installation:

```lua
require("lspmark").setup()
require("telescope").load_extension("lspmark")
```

and bind the following functions to your preferred keys:

- You key to paste text (`p`): `require('lspmark.bookmarks').paste_text()`;
- You key to toggle the mark: `require('lspmark.bookmarks').toggle_bookmark()`;
- You key to delete text in visual mode (`d`): `require('lspmark.bookmarks').delete_visual_selection()`;
- You key to delete one line (`dd`): `lua require('lspmark.bookmarks').delete_line()`.

To open the telescope window, you can run `Telescope lspmark`, to delete current selection in the telescope picker, you can press `d`.

[^1]: "Sane" means it will try best to respect your intuition.
[^2]: "Project-wise" means the bookmarks are organized according to the cwd (project).
[^3]: "Persistent" means the bookmarks will be saved to file so they won't be lost when nvim is opened next time.
[^4]: "LSP" means we store each bookmark's information associated with their LSP symbol.


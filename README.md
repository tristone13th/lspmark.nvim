# ⚜️Lspmark.nvim

A Sane[^1] Project-wise[^2] Bookmarks Plugin with Persistent[^3] Storage Based on LSP[^4] for Neovim.

Notice:

1. If you find any error log reported please try to remove the folder containing persistent files first (on Linux it is `~/.local/share/nvim/lspmark/`) since during the development the internal representation of bookmarks may changed. :-)
2. Bookmark operations (toggle, modify comment, open telescope, etc.) on modified buffer will be slower, so saving the buffer before performing such operations is a good habit.
3. Breaking changes will be documented in CHANGELOG.md, check this document if you encounter any issues after updating.

There is a bunch of bookmark plugins but none of them suit my demand, if you also finding a bookmark plugin that can:

1. Organize the bookmarks in project-wise since in most of my time I open Neovim in a project (cwd) and jump here and there,
2. Persistent the bookmarks across different Neovim launches.
3. Try to lay the bookmarks in the right place even after a format.
4. Can be deleted and pasted to other place, even not current file.
5. Use telescope to browse, jump or delete all the bookmarks.
6. Add comments to bookmarks for better searching.
7. Organize the bookmarks per git branch automatically.
8. …

Then not only the bookmarks, but also you, are in the right place. Let me show you the features one by one:

## Features

<details>
  <summary>Persistent bookmarks</summary>
  <br>
  
  ![persistent](https://github.com/tristone13th/lspmark.nvim/assets/17382962/b23b3c5a-b489-45c5-b5a3-afbc57590c47)
</details>

<details>
  <summary>Persist bookmarks after format</summary>
  <br>
  
  ![format](https://github.com/tristone13th/lspmark.nvim/assets/17382962/cdf24f0f-e2c5-49b3-82c2-94295c51d64c)
</details>

<details>
  <summary>Delete and paste bookmarks in 1 buffer</summary>
  <br>
  
  ![buffer](https://github.com/tristone13th/lspmark.nvim/assets/17382962/6639c3c6-7900-40b8-b681-c3f48255a016)
</details>

<details>
  <summary>Delete and paste across buffers</summary>
  <br>
  
  ![buffers](https://github.com/tristone13th/lspmark.nvim/assets/17382962/6447be15-860e-405e-ad4d-f1cd997dd94a)
</details>

<details>
  <summary>Telescope integration</summary>
  <br>
  
  ![telescope](https://github.com/tristone13th/lspmark.nvim/assets/17382962/9944a07c-6d29-4a4c-a473-9d088f9902c3)
</details>

<details>
  <summary>Bookmark with a comment</summary>
  <br>

  ![comment](https://github.com/tristone13th/lspmark.nvim/assets/17382962/98a5e84b-6b95-47bd-a3aa-c1c834880d39)
</details>

## Setup & Usage

**First**, install it using your favorite plugin manager and run the following code after installation:

```lua
require("lspmark").setup()
require("telescope").load_extension("lspmark")
```

Note: To open the telescope window, you can run `Telescope lspmark`, to delete current selection in the telescope picker, you can press `d`.

**Second**, you need to bind your keys (or assiociate some commands) to the following APIs to enable partial or all the features:

### `require('lspmark.bookmarks').paste_text()`

This function is used for pasting texts deleted with bookmarks, you can bind the key to paste text (`p`) to it.

### `require('lspmark.bookmarks').toggle_bookmark({with_comment=false})`

This function is used for toggling the bookmark at current line, you can bind the key to toggle the mark.

You can change `with_comment` to true to give you a prompt asking for comment each time when you creating a bookmark.

### `require('lspmark.bookmarks').delete_visual_selection()`

This function is used for deleting the selection with bookmarks in **visual mode**, you can bind the key to delete text in visual mode (`d`) to it.

### `require('lspmark.bookmarks').delete_line()`

This function is used for deleting one line with a bookmark in **normal mode**, you can bind the key to delete line in normal mode (`dd`) to it.

### `require('lspmark.bookmarks').modify_comment()`

This function is used for modifying the comment for the bookmark under the cursor.

### `require('lspmark.bookmarks').show_comment()`

This function is used for showing the entire content for the bookmark under the cursor.

**Third**, Call the following code:

```lua
-- <new_dir> can be nil, by default it is cwd.
require("lspmark.bookmarks").load_bookmarks(<new_dir>)
```

when you switch to a new cwd. Alternatively, you can define the following autocmd:

```lua
vim.api.nvim_create_autocmd({ "DirChanged" }, {
    callback = require("lspmark.bookmarks").load_bookmarks,
    pattern = { "*" },
})
```

## Highlights

`LspMark`: The highlight group for the sign at left side.

`LspMarkComment`: The highlight group for the virtual text of the comment.

## FAQ

<details>
  <summary>What's the rationale behind the feature "delete and paste"?</summary>
  <br>
This plugin does not just aim for code navigating, it is also for code refactoring/writing, during which we will move the code snippets around frequently, so developers won't want to lose their bookmarks in a code snippet just because it is moved from a place to another.
</details>

<details>
  <summary>Why bookmarking with the help of LSP information?</summary>
  <br>
The symbols in LSP could be considered as the basic logical element for coding. For example, when we format, a line of text could be added, deleted, or even moved to another place, but the LSP symbols in the document won't change a lot. With the help of the information on each LSP symbol, we only need to save each bookmark's offset in that symbol so most of the bookmarks will be kept in their original place, given the fact that most of the developers prefer incremental format rather than format a file entirely. So only the bookmarks in the formatted symbols will be affected and may be placed in another place. This plugin aims to try to keep each bookmark in the place it should be. If you have any ideas to mitigate this, don't hesitate to submit an issue or PR!
</details>

## Known Issues

<details>
  <summary>Incorrect telescope preview when the buffer is modified but not saved</summary>
  <br>
  This is a known issue of Telescope, see this https://github.com/nvim-telescope/telescope.nvim/issues/2481 and https://github.com/nvim-telescope/telescope.nvim/pull/2946.
</details>

[^1]: "Sane" means it will try best to respect your intuition.
[^2]: "Project-wise" means the bookmarks are organized according to the cwd (project).
[^3]: "Persistent" means the bookmarks will be saved to file so they won't be lost when nvim is opened next time.
[^4]: "LSP" means we store each bookmark's information associated with their LSP symbol.


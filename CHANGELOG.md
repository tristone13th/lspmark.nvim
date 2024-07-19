# !!!BREAKING CHANGES!!!

## 2024-07-19

- [dd4e8fd](https://github.com/tristone13th/lspmark.nvim/commit/dd4e8fd0ddcacf98f594fb77e7f11d282004b4a5) ("
feat: Organize bookmarks per git branch"): This commit drops the auto command for loading the bookmarks to improve correctness, so you may find the bookmarks are not loaded when you launching Neovim or switching to another directory. User should set the auto command or call the load function manually from now, for details and instructions pls see the README.

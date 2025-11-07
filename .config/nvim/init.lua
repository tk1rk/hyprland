-- Bootstrap Turbine
local turbine_path = vim.fn.stdpath("data") .. "/turbine/plugins/turbine"
if vim.fn.isdirectory(turbine_path) == 0 then
  vim.fn.system({
    "git",
    "clone",
    "--depth=1",
    "https://github.com/tk1rk/turbine.nvim",
    turbine_path,
  })
end
vim.opt.rtp:prepend(turbine_path)
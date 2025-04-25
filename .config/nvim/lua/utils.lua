utils = {}

utils.executable = function(name)
  return vim.fn.executable(name) == 1
end

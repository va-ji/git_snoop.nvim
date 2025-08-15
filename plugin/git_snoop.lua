if vim.g.loaded_git_snoop then
	return
end
vim.g.loaded_git_snoop = 1

-- Create user commands
vim.api.nvim_create_user_command("GitSnoopFile", function(_)
	require("git_snoop").show_file_history()
end, { desc = "Show file history diff" })


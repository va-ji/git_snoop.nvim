local M = {}
local Job = require("plenary.job")

-- State for diff view
M.diff_state = {
	current_file = nil,
	commits = {},
	current_index = 1,
	diff_bufnr = nil,
	original_bufnr = nil,
	temp_current_bufnr = nil,
	blame_mode = false,
	blame_data = {},
}

-- Get git log for a specific file
local function get_file_commits(file_path)
	local results = {}
	Job:new({
		command = "git",
		args = { "log", "--oneline", "--follow", file_path },
		on_stdout = function(_, data)
			table.insert(results, data)
		end,
	}):sync()
	return results
end

-- Get git blame for a specific file at a specific commit
local function get_blame_for_commit(file_path, commit_hash)
	local results = {}
	local relative_path = vim.fn.fnamemodify(file_path, ":.")
	Job:new({
		command = "git",
		args = { "blame", "--line-porcelain", commit_hash, "--", relative_path },
		on_stdout = function(_, data)
			table.insert(results, data)
		end,
	}):sync()
	return results
end

-- Parse git blame output into structured data
local function parse_blame_data(blame_lines)
	local blame_info = {}
	local current_commit = nil
	local current_line = nil
	local line_number = 1
	
	for _, line in ipairs(blame_lines) do
		if line:match("^%w+%s+%d+%s+%d+") then
			-- New blame entry: commit hash, original line, final line
			local parts = vim.split(line, " ")
			current_commit = parts[1]
			current_line = {
				commit = current_commit,
				line_num = line_number,
				author = "",
				author_time = "",
				summary = ""
			}
		elseif line:match("^author ") then
			if current_line then
				current_line.author = line:sub(8) -- Remove "author "
			end
		elseif line:match("^author%-time ") then
			if current_line then
				local timestamp = tonumber(line:sub(13))
				if timestamp then
					current_line.author_time = os.date("%Y-%m-%d %H:%M", timestamp)
				end
			end
		elseif line:match("^summary ") then
			if current_line then
				current_line.summary = line:sub(9) -- Remove "summary "
			end
		elseif line:match("^\t") then
			-- This is the actual line content
			if current_line then
				current_line.content = line:sub(2) -- Remove leading tab
				table.insert(blame_info, current_line)
				line_number = line_number + 1
				current_line = nil
			end
		end
	end
	
	return blame_info
end

-- Close diff view and restore original state
local function close_diff_view()
	if M.diff_state.diff_bufnr and vim.api.nvim_buf_is_valid(M.diff_state.diff_bufnr) then
		local diff_win = vim.fn.bufwinid(M.diff_state.diff_bufnr)
		if diff_win ~= -1 then
			vim.api.nvim_win_close(diff_win, true)
		end
	end

	-- Clear diff options and restore original buffer if we created a temp one
	if M.diff_state.original_bufnr and vim.api.nvim_buf_is_valid(M.diff_state.original_bufnr) then
		local orig_win = vim.fn.bufwinid(M.diff_state.original_bufnr)
		if orig_win == -1 then
			-- Find window showing temp buffer and restore original
			if M.diff_state.temp_current_bufnr then
				local temp_win = vim.fn.bufwinid(M.diff_state.temp_current_bufnr)
				if temp_win ~= -1 then
					vim.api.nvim_win_set_buf(temp_win, M.diff_state.original_bufnr)
					vim.api.nvim_set_current_win(temp_win)
				end
			end
		else
			vim.api.nvim_set_current_win(orig_win)
		end
		vim.cmd("diffoff")
	end

	-- Clean up temporary current buffer
	if M.diff_state.temp_current_bufnr and vim.api.nvim_buf_is_valid(M.diff_state.temp_current_bufnr) then
		vim.api.nvim_buf_delete(M.diff_state.temp_current_bufnr, { force = true })
	end

	-- Reset state
	M.diff_state = {
		current_file = nil,
		commits = {},
		current_index = 1,
		diff_bufnr = nil,
		original_bufnr = nil,
		temp_current_bufnr = nil,
		blame_mode = false,
		blame_data = {},
	}
end

-- Forward declaration
local update_diff_view

-- Toggle blame mode
local function toggle_blame_mode()
	M.diff_state.blame_mode = not M.diff_state.blame_mode
	update_diff_view()
	
	local mode_str = M.diff_state.blame_mode and "enabled" or "disabled"
	vim.notify("Blame mode " .. mode_str)
end

-- Update diff view with commit at current index
update_diff_view = function()
	if #M.diff_state.commits == 0 or not M.diff_state.current_file then
		return
	end

	local commit_hash = M.diff_state.commits[M.diff_state.current_index]:match("(%w+)")
	if not commit_hash then
		return
	end

	local relative_path = vim.fn.fnamemodify(M.diff_state.current_file, ":.")

	if M.diff_state.blame_mode then
		-- Get blame data for this commit
		local blame_lines = get_blame_for_commit(M.diff_state.current_file, commit_hash)
		local blame_data = parse_blame_data(blame_lines)
		M.diff_state.blame_data = blame_data
		
		-- Create blame view content
		local blame_content = {}
		for i, blame_info in ipairs(blame_data) do
			local date_only = blame_info.author_time:match("(%d%d%d%d%-%d%d%-%d%d)") or blame_info.author_time
			local blame_line = string.format("%-20s %s | %s", 
				blame_info.author:sub(1, 20),
				date_only,
				blame_info.content
			)
			table.insert(blame_content, blame_line)
		end
		
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(M.diff_state.diff_bufnr) then
				-- Disable diff mode for blame view to prevent highlighting
				local diff_win = vim.fn.bufwinid(M.diff_state.diff_bufnr)
				if diff_win ~= -1 then
					local current_win = vim.api.nvim_get_current_win()
					vim.api.nvim_set_current_win(diff_win)
					vim.cmd("diffoff")
					vim.api.nvim_set_current_win(current_win)
				end

				-- Temporarily disable readonly warnings
				vim.api.nvim_set_option_value("readonly", false, { buf = M.diff_state.diff_bufnr })
				vim.api.nvim_set_option_value("modifiable", true, { buf = M.diff_state.diff_bufnr })

				vim.api.nvim_buf_set_lines(M.diff_state.diff_bufnr, 0, -1, false, blame_content)
				
				-- Restore readonly settings
				vim.api.nvim_set_option_value("modifiable", false, { buf = M.diff_state.diff_bufnr })
				vim.api.nvim_set_option_value("readonly", true, { buf = M.diff_state.diff_bufnr })

				-- Set up blame syntax highlighting
				local ft = vim.filetype.match({ filename = M.diff_state.current_file })
				if not ft then
					local ext = M.diff_state.current_file:match("%.([^%.]+)$")
					if ext then
						local ext_map = {
							ts = "typescript",
							js = "javascript", 
							lua = "lua",
							py = "python",
							go = "go",
							rs = "rust",
							c = "c",
							cpp = "cpp",
							h = "c",
							hpp = "cpp",
							jsx = "javascriptreact",
							tsx = "typescriptreact"
						}
						ft = ext_map[ext]
					end
				end
				
				-- Create a custom blame syntax that highlights both the blame info and code
				vim.defer_fn(function()
					if vim.api.nvim_buf_is_valid(M.diff_state.diff_bufnr) then
						local win = vim.fn.bufwinid(M.diff_state.diff_bufnr)
						if win ~= -1 then
							vim.api.nvim_win_call(win, function()
								-- Set up blame syntax highlighting
								vim.cmd([[
									syntax clear
									syntax match BlameAuthor /^[^|]*/ nextgroup=BlameCode
									syntax match BlameCode /|.*$/ contains=ALL
									hi BlameAuthor ctermfg=yellow guifg=#ffff00
									hi BlameCode ctermfg=white guifg=#ffffff
								]])
								
								-- Apply original file syntax to the code part
								if ft then
									vim.cmd("set filetype=" .. ft)
									vim.cmd("syntax include @CodeSyntax syntax/" .. ft .. ".vim")
									vim.cmd("syntax region BlameCodeHighlight start='|' end='$' contains=@CodeSyntax")
								end
							end)
						end
					end
				end, 50)

				-- Update buffer name to indicate blame mode
				local commit_msg = M.diff_state.commits[M.diff_state.current_index]:match("%w+%s+(.*)")
				local buf_name = string.format(
					"[%s] %s (BLAME) (%d/%d)",
					commit_hash:sub(1, 7),
					vim.fn.fnamemodify(M.diff_state.current_file, ":t"),
					M.diff_state.current_index,
					#M.diff_state.commits
				)
				vim.api.nvim_buf_set_name(M.diff_state.diff_bufnr, buf_name)
			end
		end)
	else
		-- Regular file content view
		local results = {}
		Job:new({
			command = "git",
			args = { "show", commit_hash .. ":" .. relative_path },
			on_stdout = function(_, data)
				table.insert(results, data)
			end,
			on_exit = function()
				vim.schedule(function()
					if vim.api.nvim_buf_is_valid(M.diff_state.diff_bufnr) then
						-- Temporarily disable readonly warnings
						local old_readonly = vim.api.nvim_get_option_value("readonly", { buf = M.diff_state.diff_bufnr })
						vim.api.nvim_set_option_value("readonly", false, { buf = M.diff_state.diff_bufnr })
						vim.api.nvim_set_option_value("modifiable", true, { buf = M.diff_state.diff_bufnr })

						local content_to_show = results
						vim.api.nvim_buf_set_lines(M.diff_state.diff_bufnr, 0, -1, false, content_to_show)
						
						-- Set filetype for syntax highlighting
						local ft = vim.filetype.match({ filename = M.diff_state.current_file })
						
						-- Try extension mapping if vim.filetype.match fails
						if not ft then
							local ext = M.diff_state.current_file:match("%.([^%.]+)$")
							if ext then
								local ext_map = {
									ts = "typescript",
									js = "javascript", 
									lua = "lua",
									py = "python",
									go = "go",
									rs = "rust",
									c = "c",
									cpp = "cpp",
									h = "c",
									hpp = "cpp",
									jsx = "javascriptreact",
									tsx = "typescriptreact"
								}
								ft = ext_map[ext]
							end
						end
						
						if ft then
							vim.api.nvim_set_option_value("filetype", ft, { buf = M.diff_state.diff_bufnr })
							
							-- Enable TreeSitter and force syntax highlighting
							vim.defer_fn(function()
								if vim.api.nvim_buf_is_valid(M.diff_state.diff_bufnr) then
									local win = vim.fn.bufwinid(M.diff_state.diff_bufnr)
									if win ~= -1 then
										-- Switch to the window temporarily for syntax setup
										local current_win = vim.api.nvim_get_current_win()
										vim.api.nvim_set_current_win(win)
										
										-- Multiple approaches to enable syntax
										pcall(function()
											vim.cmd("syntax on")
											vim.cmd("syntax enable")
										end)
										
										-- Force filetype detection
										pcall(function()
											vim.cmd("filetype detect")
											vim.cmd("doautocmd FileType " .. ft)
										end)
										
										-- Try TreeSitter
										pcall(function()
											local ts_status, ts_highlight = pcall(require, "nvim-treesitter.highlight")
											if ts_status and ts_highlight then
												ts_highlight.attach(M.diff_state.diff_bufnr, ft)
											end
										end)
										
										-- Try manual syntax loading
										pcall(function()
											vim.cmd("runtime! syntax/" .. ft .. ".vim")
										end)
										
										-- Restore window
										vim.api.nvim_set_current_win(current_win)
									end
								end
							end, 150)
						end
						
						-- Restore readonly settings
						vim.api.nvim_set_option_value("modifiable", false, { buf = M.diff_state.diff_bufnr })
						vim.api.nvim_set_option_value("readonly", true, { buf = M.diff_state.diff_bufnr })

						-- Re-enable diff mode when switching back from blame mode
						local diff_win = vim.fn.bufwinid(M.diff_state.diff_bufnr)
						local orig_win = vim.fn.bufwinid(M.diff_state.original_bufnr)
						if diff_win ~= -1 and orig_win ~= -1 then
							local current_win = vim.api.nvim_get_current_win()
							vim.api.nvim_set_current_win(orig_win)
							vim.cmd("diffthis")
							vim.api.nvim_set_current_win(diff_win)
							vim.cmd("diffthis")
							vim.api.nvim_set_current_win(current_win)
						end

						-- Update buffer name with function name if available
						local commit_msg = M.diff_state.commits[M.diff_state.current_index]:match("%w+%s+(.*)")
						local buf_name
						if M.diff_state.func_name then
							buf_name = string.format(
								"[%s] %s:%s (%d/%d)",
								commit_hash:sub(1, 7),
								vim.fn.fnamemodify(M.diff_state.current_file, ":t"),
								M.diff_state.func_name,
								M.diff_state.current_index,
								#M.diff_state.commits
							)
						else
							buf_name = string.format(
								"[%s] %s (%d/%d)",
								commit_hash:sub(1, 7),
								vim.fn.fnamemodify(M.diff_state.current_file, ":t"),
								M.diff_state.current_index,
								#M.diff_state.commits
							)
						end
						-- Set buffer name after filetype to avoid interference
						vim.api.nvim_buf_set_name(M.diff_state.diff_bufnr, buf_name)
						
						-- Ensure TreeSitter is active for syntax highlighting
						if ft then
							vim.defer_fn(function()
								if vim.api.nvim_buf_is_valid(M.diff_state.diff_bufnr) then
									local buf_ft = vim.api.nvim_get_option_value("filetype", { buf = M.diff_state.diff_bufnr })
									if buf_ft ~= ft then
										vim.api.nvim_set_option_value("filetype", ft, { buf = M.diff_state.diff_bufnr })
									end
								end
							end, 50)
						end
					end
				end)
			end,
		}):start()
	end
end

-- Navigate through commit history
local function navigate_history(direction)
	if #M.diff_state.commits == 0 then
		return
	end

	if direction > 0 and M.diff_state.current_index < #M.diff_state.commits then
		M.diff_state.current_index = M.diff_state.current_index + 1
		update_diff_view()
	elseif direction < 0 and M.diff_state.current_index > 1 then
		M.diff_state.current_index = M.diff_state.current_index - 1
		update_diff_view()
	end
end

-- Show file history diff
function M.show_file_history()
	local current_file = vim.fn.expand("%:p")
	if current_file == "" then
		vim.notify("No file is currently open", vim.log.levels.WARN)
		return
	end
	local commits = get_file_commits(current_file)
	if #commits == 0 then
		vim.notify("No git history found for this file", vim.log.levels.WARN)
		return
	end
	-- Store original buffer and window
	local original_bufnr = vim.api.nvim_get_current_buf()
	local original_win = vim.api.nvim_get_current_win()
	-- Create vertical split on the right
	vim.cmd("vsplit")
	local diff_win = vim.api.nvim_get_current_win()
	local diff_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(diff_win, diff_bufnr)
	-- Set up diff state
	M.diff_state = {
		current_file = current_file,
		commits = commits,
		current_index = 1,
		diff_bufnr = diff_bufnr,
		original_bufnr = original_bufnr,
		temp_current_bufnr = nil,
	}
	-- Configure diff buffer
	vim.api.nvim_set_option_value("readonly", true, { buf = diff_bufnr })
	vim.api.nvim_set_option_value("modifiable", false, { buf = diff_bufnr })
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = diff_bufnr })
	-- Set filetype to match original file
	local ft = vim.filetype.match({ filename = current_file })
	
	-- Try extension mapping if vim.filetype.match fails
	if not ft then
		local ext = current_file:match("%.([^%.]+)$")
		if ext then
			local ext_map = {
				ts = "typescript",
				js = "javascript", 
				lua = "lua",
				py = "python",
				go = "go",
				rs = "rust",
				c = "c",
				cpp = "cpp",
				h = "c",
				hpp = "cpp",
				jsx = "javascriptreact",
				tsx = "typescriptreact"
			}
			ft = ext_map[ext]
		end
	end
	
	if ft then
		vim.api.nvim_set_option_value("filetype", ft, { buf = diff_bufnr })
	end
	-- Enable diff mode
	vim.api.nvim_set_current_win(original_win)
	vim.cmd("diffthis")
	vim.api.nvim_set_current_win(diff_win)
	vim.cmd("diffthis")
	-- Set up local keybindings for navigation with hjkl
	local opts = { buffer = diff_bufnr, silent = true }
	vim.keymap.set("n", "j", function()
		navigate_history(1)
	end, vim.tbl_extend("force", opts, { desc = "Next commit (older)" }))
	vim.keymap.set("n", "k", function()
		navigate_history(-1)
	end, vim.tbl_extend("force", opts, { desc = "Previous commit (newer)" }))
	vim.keymap.set("n", "h", function()
		navigate_history(-1)
	end, vim.tbl_extend("force", opts, { desc = "Previous commit (newer)" }))
	vim.keymap.set("n", "l", function()
		navigate_history(1)
	end, vim.tbl_extend("force", opts, { desc = "Next commit (older)" }))
	vim.keymap.set("n", "b", toggle_blame_mode, vim.tbl_extend("force", opts, { desc = "Toggle blame mode" }))
	vim.keymap.set("n", "q", close_diff_view, vim.tbl_extend("force", opts, { desc = "Close diff view" }))

	-- Load initial commit (most recent)
	update_diff_view()

	vim.notify(string.format("Quick diff started. Use hjkl to navigate, b for blame mode, q to quit. (%d commits)", #commits))
end

function M.setup(opts)
	opts = opts or {}

	-- Set up key mappings if provided
	if opts.mappings then
		if opts.mappings.file_history then
			vim.keymap.set("n", opts.mappings.file_history, M.show_file_history, { desc = "Show file history diff" })
		end
	end
end

return M

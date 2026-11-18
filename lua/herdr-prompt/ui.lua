-- The composition surface: one floating scratch buffer for every prompt, so the
-- message being sent is visible and editable before it is sent.
-- See docs/adr/0007-compose-before-send.md

local M = {}

local function close(win, buf)
	if win and vim.api.nvim_win_is_valid(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if buf and vim.api.nvim_buf_is_valid(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
end

--- opts = {title, lines, on_submit(text), on_cancel(), on_yank? }
function M.compose_float(opts)
	local lines = opts.lines or { "" }
	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	-- markdown: fences in the payload highlight, so a broken block is visible.
	vim.bo[buf].filetype = "markdown"
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

	local width = math.max(40, math.min(120, vim.o.columns - 12))
	local height = math.max(6, math.min(#lines + 1, vim.o.lines - 8))
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		style = "minimal",
		border = "rounded",
		width = width,
		height = height,
		row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		title = " " .. (opts.title or "herdr-prompt") .. " ",
		title_pos = "center",
	})
	vim.wo[win].wrap = true
	vim.wo[win].conceallevel = 0

	local function submit()
		local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
		close(win, buf)
		vim.schedule(function()
			opts.on_submit(text)
		end)
	end

	local function cancel()
		close(win, buf)
		if opts.on_cancel then
			vim.schedule(opts.on_cancel)
		end
	end

	vim.keymap.set({ "n", "i" }, "<C-s>", submit, { buffer = buf, desc = "herdr-prompt: send" })
	vim.keymap.set({ "n", "i" }, "<Esc>", cancel, { buffer = buf, desc = "herdr-prompt: cancel" })
	vim.keymap.set("n", "q", cancel, { buffer = buf, desc = "herdr-prompt: cancel" })

	-- Put the cursor in the body, not at the end of the context block.
	vim.api.nvim_win_set_cursor(win, { 1, 0 })
	return buf, win
end

return M

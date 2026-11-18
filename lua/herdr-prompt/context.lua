-- The context payload: a location line, then a fenced block.
-- Shape and reasons: docs/adr/0004-context-payload-shape.md

local M = {}

local function realpath(path)
	local ok, resolved = pcall(vim.uv.fs_realpath, path)
	if ok and resolved and resolved ~= "" then
		return resolved
	end
	return path
end

--- Path shortened against the target agent's folder, so what we print resolves
--- from where the agent actually runs. Outside it, the absolute path is the
--- only spelling that still works.
---
--- Both spellings are tried: nvim hands back resolved paths, while a folder
--- typed by a person is often not (`/tmp` against `/private/tmp` on macOS).
local function relpath(file, cwd)
	if not cwd or cwd == "" then
		return file
	end
	for _, pair in ipairs({ { file, cwd }, { realpath(file), realpath(cwd) } }) do
		local f, base = pair[1], pair[2]:gsub("/+$", "")
		if base ~= "" and f:sub(1, #base + 1) == base .. "/" then
			return f:sub(#base + 2)
		end
	end
	return file
end

local function range_text(first, last)
	if first == last then
		return tostring(first)
	end
	return string.format("%d-%d", first, last)
end

local function buffer_path(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return nil
	end
	return vim.fn.fnamemodify(name, ":p")
end

local function fence_lang(bufnr)
	local ft = vim.bo[bufnr].filetype or ""
	return (ft:gsub("%s", ""))
end

local function git_diff(cwd)
	local function run(args)
		local ok, r = pcall(function()
			return vim.system(args, { cwd = cwd, text = true }):wait()
		end)
		if not ok or not r or r.code ~= 0 then
			return nil
		end
		return r.stdout
	end
	local staged = run({ "git", "diff", "--cached", "--no-color" })
	if staged and vim.trim(staged) ~= "" then
		return staged, "staged"
	end
	local unstaged = run({ "git", "diff", "--no-color" })
	if unstaged and vim.trim(unstaged) ~= "" then
		return unstaged, "unstaged"
	end
	return nil, nil
end

--- Build the payload.
--- kind: "line" | "selection" | "buffer" | "gitdiff" | "none"
--- opts: {bufnr, first, last, cwd, max_lines, line_numbers}
--- returns {payload, file, range, lang} or {error}
function M.build(kind, opts)
	opts = opts or {}
	local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()

	if kind == "none" then
		return { payload = "" }
	end

	if kind == "gitdiff" then
		local diff, which = git_diff(opts.cwd)
		if not diff then
			return { error = "no changes to diff (nothing staged, nothing unstaged)" }
		end
		local lines = { "```diff" }
		for line in (diff .. "\n"):gmatch("(.-)\r?\n") do
			table.insert(lines, line)
		end
		table.insert(lines, "```")
		return { payload = table.concat(lines, "\n"), file = nil, range = nil, lang = "diff", diff = which }
	end

	local first, last
	if kind == "buffer" then
		first, last = 1, vim.api.nvim_buf_line_count(bufnr)
	else
		first, last = opts.first, opts.last
	end
	if not first or not last or first < 1 or last < first then
		return { error = "nothing to send: no line or selection" }
	end

	local count = last - first + 1
	local max_lines = opts.max_lines or 2000
	if count > max_lines then
		return {
			error = string.format(
				"%d lines is over context.max_lines (%d) — narrow the selection or raise the limit",
				count,
				max_lines
			),
		}
	end

	local text = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
	local path = buffer_path(bufnr)
	local rel = path and relpath(path, opts.cwd) or nil
	local range = range_text(first, last)
	local location = rel and (rel .. ":" .. range) or "buffer"

	local code = {}
	for i, line in ipairs(text) do
		if opts.line_numbers then
			table.insert(code, string.format("%d: %s", first + i - 1, line))
		else
			table.insert(code, line)
		end
	end
	local lang = fence_lang(bufnr)
	local parts = { location, "```" .. lang }
	vim.list_extend(parts, code)
	table.insert(parts, "```")

	return {
		payload = table.concat(parts, "\n"),
		file = rel,
		range = range,
		lang = lang,
	}
end

return M

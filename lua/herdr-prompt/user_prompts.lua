-- User prompts: Markdown files with frontmatter, re-read on every picker open
-- so an edit lands on the next `:HerdrPrompt` with no reload.
-- See docs/adr/0006-user-prompts-on-disk.md

local M = {}

--- Split `---` frontmatter from the body. Only `key: value` lines, because a
--- YAML dependency for six keys would be the larger part of this plugin.
local function split_frontmatter(text)
	local lines = vim.split(text, "\r?\n", { plain = false })
	if lines[1] ~= "---" then
		return {}, text
	end
	local close
	for i = 2, #lines do
		if lines[i] == "---" then
			close = i
			break
		end
	end
	if not close then
		return {}, text
	end
	local meta = {}
	for i = 2, close - 1 do
		local key, value = lines[i]:match("^([%w_%-]+)%s*:%s*(.-)%s*$")
		if key then
			value = value:gsub('^"(.*)"$', "%1"):gsub("^'(.*)'$", "%1")
			meta[key] = value
		end
	end
	local body = {}
	for i = close + 1, #lines do
		table.insert(body, lines[i])
	end
	return meta, table.concat(body, "\n")
end

M._split_frontmatter = split_frontmatter

local function first_line(body)
	local line = body:match("[^\n]*") or ""
	return (line:gsub("^#+%s*", ""))
end

--- Everything in `dir` that parses. A bad file is reported and skipped: one
--- broken file must not hide the other nine.
function M.load(dir)
	local out = {}
	if not dir or dir == "" or vim.fn.isdirectory(dir) == 0 then
		return out
	end
	local names = {}
	for name, kind in vim.fs.dir(dir) do
		if kind == "file" and name:match("%.md$") then
			table.insert(names, name)
		end
	end
	table.sort(names)
	for _, name in ipairs(names) do
		local path = dir .. "/" .. name
		local ok, lines = pcall(vim.fn.readfile, path)
		if not ok then
			vim.notify("herdr-prompt: cannot read " .. path, vim.log.levels.WARN)
		else
			local meta, body = split_frontmatter(table.concat(lines, "\n"))
			body = vim.trim(body)
			if body == "" then
				vim.notify("herdr-prompt: " .. path .. " has no body", vim.log.levels.WARN)
			else
				table.insert(out, {
					name = meta.name or (name:gsub("%.md$", "")),
					description = meta.description or first_line(body),
					context = meta.context,
					submit = meta.submit ~= "false",
					body = body,
					source = path,
				})
			end
		end
	end
	return out
end

return M

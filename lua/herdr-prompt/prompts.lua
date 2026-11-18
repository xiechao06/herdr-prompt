-- The catalog: CopilotChat's seven prompt bodies, rewritten for a terminal
-- agent and stripped of every system_prompt. See
-- docs/adr/0005-catalog-prompts-rewritten.md
--
-- body    the task, sent as-is (with `{{context}}` where the code goes)
-- context default context kind; omit to follow the call site
--         (visual mode -> selection, otherwise the current line)

local M = {}

M.catalog = {
	{
		name = "Explain",
		description = "Explain what this code does",
		body = table.concat({
			"Explain this code. Say what it does, how it works, and anything a reader would not expect.",
			"Short paragraphs, no restating the code back to me.",
		}, "\n"),
	},
	{
		name = "Review",
		description = "Find issues, one per line as path:line",
		body = table.concat({
			"Review this code. Report each issue as `path:line: problem`, most serious first.",
			"Only report what you would change: bugs, unclear naming, missing or wrong error handling,",
			"security, duplication, unnecessary complexity. No style nits you would not act on.",
			"If there is nothing worth reporting, say so in one line and stop.",
		}, "\n"),
	},
	{
		name = "Fix",
		description = "Rewrite the code with the problems fixed",
		body = table.concat({
			"Find the problems in this code and rewrite it with the fixes applied.",
			"Explain each change in one line. If a fix needs a change outside this code, say where.",
		}, "\n"),
	},
	{
		name = "Optimize",
		description = "Improve performance and readability",
		body = table.concat({
			"Optimize this code for performance and readability.",
			"Explain the strategy and what it buys. If the current version is already the right",
			"trade-off, say so instead of changing it.",
		}, "\n"),
	},
	{
		name = "Docs",
		description = "Add documentation comments",
		body = table.concat({
			"Add documentation comments to this code.",
			"Match the style of the surrounding file; if there is none, use the language's",
			"conventional doc-comment form. Do not restate the signature.",
		}, "\n"),
	},
	{
		name = "Tests",
		description = "Write tests using the project's framework",
		body = table.concat({
			"Write tests for this code.",
			"Use the project's existing test framework, file layout and naming. Cover the cases",
			"that would actually break: boundaries, empty input, and error paths.",
			"If you cannot find a test setup, say so before writing any test.",
		}, "\n"),
	},
	{
		name = "Commit",
		description = "Write a commit message for the diff",
		context = "gitdiff",
		body = table.concat({
			"Write a commit message for this diff. Conventional Commits format,",
			"subject under 50 characters and imperative, body wrapped at 72 characters.",
		}, "\n"),
	},
}

--- Catalog plus user prompts plus the inline escape hatch, in picker order.
--- `user` is a list of the same shape as M.catalog.
function M.choices(user)
	local out = { "Write my own…" }
	for _, p in ipairs(user or {}) do
		out[#out + 1] = p
	end
	for _, p in ipairs(M.catalog) do
		out[#out + 1] = p
	end
	return out
end

function M.find(name, user)
	local want = name:lower()
	for _, list in ipairs({ user or {}, M.catalog }) do
		for _, p in ipairs(list) do
			if p.name:lower() == want then
				return p
			end
		end
	end
	return nil
end

function M.display(p)
	if type(p) == "string" then
		return p
	end
	return string.format("%s — %s", p.name or "prompt", p.description or "")
end

--- `vim.ui.select` is handed labels, and the choice mapped back: an entry is a
--- table here, and pickers that index into items should never see one.
--- `cb` receives the entry, or the string for "Write my own…".
function M.pick(choices, cb)
	local labels, by_label = {}, {}
	for i, item in ipairs(choices) do
		local label = M.display(item)
		if by_label[label] ~= nil then
			label = label .. " (" .. i .. ")"
		end
		labels[i] = label
		by_label[label] = item
	end
	vim.ui.select(labels, { prompt = "Prompt" }, function(choice)
		local item = choice and by_label[choice] or nil
		if item ~= nil then
			cb(item)
		end
	end)
end

return M

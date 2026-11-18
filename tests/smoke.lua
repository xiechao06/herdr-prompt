-- End-to-end smoke test, headless.
--
--   nvim --headless -u NONE -l tests/smoke.lua
--
-- It talks to the real herdr-core: it starts a `cat` terminal, sends a composed
-- message through the plugin's own path, and checks the bytes that arrived. No
-- agent is disturbed; nothing is sent to a live agent terminal.

local root = vim.fn.fnamemodify(vim.fn.getcwd(), ":p"):gsub("/$", "")
vim.opt.rtp:prepend(root)

local rpc = require("herdr-prompt.rpc")
local agents = require("herdr-prompt.agents")
local context = require("herdr-prompt.context")
local compose = require("herdr-prompt.compose")
local prompts = require("herdr-prompt.prompts")
local user_prompts = require("herdr-prompt.user_prompts")
local ui = require("herdr-prompt.ui")

local failures = {}
local checks = 0

local function check(name, ok, detail)
	checks = checks + 1
	if not ok then
		table.insert(failures, string.format("%s%s", name, detail and ("\n    " .. detail) or ""))
	end
end

local function eq(name, want, got)
	check(
		name,
		want == got,
		want == got and nil
			or string.format("want: %s\n    got:  %s", vim.inspect(want), vim.inspect(got))
	)
end

rpc.setup({ bin = "hc" })

local function call(method, params, timeout)
	local done, reply = false, nil
	rpc.request(method, params, function(msg)
		reply = msg
		done = true
	end)
	vim.wait(timeout or 15000, function()
		return done
	end, 20)
	return reply
end

-- ---------------------------------------------------------------- protocol

local hello = call("hello")
check("hello answers", hello ~= nil, "no reply from `hc connect`")
if hello and hello.result then
	eq("protocol generation is 1", 1, hello.result.generation)
	eq("framed mode stays off", false, hello.result.framed)
end

-- ------------------------------------------------------------- pure pieces

local body = "Review this.\n\n{{context}}"
eq(
	"compose substitutes {{context}}",
	"Review this.\n\n@f.lua:1\n```lua\nx\n```",
	compose.render(body, { payload = "@f.lua:1\n```lua\nx\n```" })
)

eq(
	"compose puts the context last when the body has no placeholder",
	"Review this.\n\n@f.lua:1",
	compose.render("Review this.", { payload = "@f.lua:1" })
)

eq("compose with no context is just the body", "hello", compose.render("hello", { payload = "" }))

local meta, rest = user_prompts._split_frontmatter("---\nname: Harden\ndescription: x\ncontext: buffer\n---\nDo it.")
eq("frontmatter name", "Harden", meta.name)
eq("frontmatter context", "buffer", meta.context)
eq("frontmatter body", "Do it.", rest)

eq("no frontmatter leaves the body alone", "Just text", (select(2, user_prompts._split_frontmatter("Just text"))))

-- ------------------------------------------------------- nulls and pickers

-- What `vim.json.decode` really produces for {"name": null}.
-- `cwd` is the launch folder, `foreground.cwd` the current one: they differ as
-- soon as an agent cds, and the label must follow the agent, not the launch.
local raw = { address = "t1", state = "live", cwd = "/Users/x/old", name = vim.NIL, title = vim.NIL,
	foreground = { cwd = "/Users/x/now" }, labels = { where = "now / 1" },
	status = { app = "pi", state = "done" } }

check(
	"denull turns JSON null into nil",
	vim.deep_equal(rpc._denull({ a = vim.NIL, b = { c = vim.NIL, d = "x" } }), { b = { d = "x" } }),
	vim.inspect(rpc._denull({ a = vim.NIL, b = { c = vim.NIL, d = "x" } }))
)

local normalized = agents._normalize(raw)
eq("normalize drops a null name", nil, normalized.name)
eq("normalize keeps the agent status word", "done", normalized.status)
eq("normalize keeps the terminal state", "live", normalized.state)
eq("normalize follows the current folder, not the launch folder", "/Users/x/now", normalized.folder)
eq("normalize keeps the pane label", "now / 1", normalized.where)
check("an agent with a null name is still an agent", agents._is_agent(raw) == true)
check("a finished terminal is not an agent", agents._is_agent({ address = "t9", state = "finished", status = { app = "pi", state = "done" } }) == false)
check("a plain terminal is not an agent", agents._is_agent({ address = "t8", state = "live", status = vim.NIL }) == false)

-- This is the shape that crashed: a null name reached table.concat.
local label = agents.display(normalized)
eq("label starts with the address and ends with the pane label", "t1 · pi · done · now / 1", label)

-- No labels (a terminal outside the app): fall back to the folder's tail.
local second = agents._normalize({ address = "t2", state = "live", cwd = "/Users/x/a",
	foreground = { cwd = "/Users/x/a" }, name = "review", status = { app = "pi", state = "idle" } })
eq("label falls back to the folder when there is no pane label", "t2 · pi · idle · review · a", agents.display(second))

local real_select = vim.ui.select
local function stub_select(choice_index)
	vim.ui.select = function(items, _, on_choice)
		for i, item in ipairs(items) do
			-- What every picker does somewhere: treat an item as text.
			if type(item) ~= "string" then
				error(string.format("item %d is %s, not a string", i, type(item)))
			end
		end
		on_choice(items[choice_index], choice_index)
	end
end

stub_select(2)
local picked
local ok, pick_err = pcall(agents.pick, { normalized, second }, function(a)
	picked = a
end)
vim.ui.select = real_select
check("agents.pick hands only strings to vim.ui.select", ok, pick_err)
check("agents.pick maps the label back to its agent", picked ~= nil and picked.address == "t2", vim.inspect(picked))

-- The agent prompts already go to is marked, and stays selectable.
local seen
local function capture_select(fn)
	vim.ui.select = function(items, opts, on_choice)
		seen = { items = items, prompt = (opts and opts.prompt) or "" }
		fn(items, on_choice)
	end
end

capture_select(function(items, on_choice)
	on_choice(items[1], 1)
end)
local marked_pick
local ok4, err4 = pcall(agents.pick, { normalized, second }, function(a)
	marked_pick = a
end, "t1")
vim.ui.select = real_select
check("a marked pick still works", ok4 and marked_pick ~= nil and marked_pick.address == "t1", err4 or vim.inspect(marked_pick))
eq("only the current agent is marked", 1, (function()
	local n = 0
	for _, item in ipairs(seen.items) do
		if item:sub(1, #agents.CURRENT) == agents.CURRENT then
			n = n + 1
		end
	end
	return n
end)())
check("the marked label starts with the marker", seen.items[1]:sub(1, #agents.CURRENT) == agents.CURRENT, seen.items[1])
check("an unmarked row keeps its old label", seen.items[2] == agents.display(second), seen.items[2])
check("labels are still strings", type(seen.items[1]) == "string" and type(seen.items[2]) == "string")
check("the prompt says what the marker means", seen.prompt:find("current", 1, true) ~= nil, seen.prompt)

stub_select(1)
local chosen
local ok2, err2 = pcall(prompts.pick, prompts.choices({}), function(c)
	chosen = c
end)
vim.ui.select = real_select
check("prompts.pick hands only strings to vim.ui.select", ok2, err2)
check(
	"prompts.pick maps the label back to the first entry",
	chosen ~= nil and chosen.name == prompts.catalog[1].name,
	vim.inspect(chosen)
)

stub_select(#prompts.choices({}))
local entry
local ok3, err3 = pcall(prompts.pick, prompts.choices({}), function(c)
	entry = c
end)
vim.ui.select = real_select
check("prompts.pick returns the last entry, not its label", ok3 and type(entry) == "table" and entry.name ~= nil, err3 or vim.inspect(entry))

-- ----------------------------------------------------------------- context

local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
local path = dir .. "/probe.lua"
vim.fn.writefile({ "local a = 1", "local b = 2", "local c = 3" }, path)

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_name(bufnr, path)
vim.bo[bufnr].filetype = "lua"
vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn.readfile(path))

local built = context.build("selection", { bufnr = bufnr, first = 2, last = 3, cwd = dir })
eq("the context is an @path:line reference", "@probe.lua:2-3", built.payload)
eq("the reference is relative to the agent cwd", "probe.lua", built.file)
check("no code is copied by default", built.copied_code == false, vim.inspect(built.copied_code))

local with_code = context.build("selection", { bufnr = bufnr, first = 2, last = 3, cwd = dir, code = true })
eq(
	"context.code copies the lines too",
	table.concat({
		"@probe.lua:2-3",
		"```lua",
		"local b = 2",
		"local c = 3",
		"```",
	}, "\n"),
	with_code.payload
)
eq(
	"context.line_numbers numbers copied lines",
	"@probe.lua:2\n```lua\n2: local b = 2\n```",
	context.build("line", { bufnr = bufnr, first = 2, last = 2, cwd = dir, code = true, line_numbers = true }).payload
)

local whole = context.build("buffer", { bufnr = bufnr, cwd = dir })
eq("buffer context covers every line", "@probe.lua:1-3", whole.payload)

local outside = context.build("line", { bufnr = bufnr, first = 1, last = 1, cwd = "/elsewhere" })
check(
	"a path outside the agent cwd is still relative",
	outside.payload:sub(1, 1) ~= "/"
		and outside.payload:sub(1, 3) == "@.."
		and outside.payload:find("probe.lua:1", 1, true) == #outside.payload - 10,
	outside.payload
)

local sibling_cwd = dir .. "/agent"
vim.fn.mkdir(sibling_cwd, "p")
local sibling = context.build("line", { bufnr = bufnr, first = 1, last = 1, cwd = sibling_cwd })
eq("a file beside the agent's folder climbs out with ..", "@../probe.lua:1", sibling.payload)

local deeper = context.build("line", { bufnr = bufnr, first = 1, last = 1, cwd = dir })
eq("a file inside the agent's folder has no prefix at all", "@probe.lua:1", deeper.payload)

-- No path to point at: the code has to travel, or the message says nothing.
local scratch = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(scratch, 0, -1, false, { "print('scratch')" })
local scratch_ctx = context.build("buffer", { bufnr = scratch, cwd = dir })
check("an unnamed buffer sends its code", scratch_ctx.payload:find("print('scratch')", 1, true) ~= nil, scratch_ctx.payload)
check("an unnamed buffer is not truncated", scratch_ctx.copied_code == true, vim.inspect(scratch_ctx))

local too_big = context.build("buffer", { bufnr = bufnr, cwd = dir, code = true, max_lines = 2 })
check("over max_lines is an error, not a truncation", too_big.error ~= nil, vim.inspect(too_big))

local no_code_no_limit = context.build("buffer", { bufnr = bufnr, cwd = dir, max_lines = 1 })
check("max_lines does not apply to a bare reference", no_code_no_limit.error == nil, vim.inspect(no_code_no_limit))

-- ------------------------------------------------------------------ diff

local repo = vim.fn.tempname()
vim.fn.mkdir(repo, "p")
local function sh(cmd)
	return vim.system(cmd, { cwd = repo, text = true }):wait()
end
sh({ "git", "init", "-q" })
sh({ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "x" })
vim.fn.writefile({ "before" }, repo .. "/d.txt")
sh({ "git", "add", "d.txt" })
sh({ "git", "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-q", "-m", "add d" })
vim.fn.writefile({ "after" }, repo .. "/d.txt")
sh({ "git", "add", "d.txt" })

local diff = context.build("gitdiff", { cwd = repo })
check("staged change produces a diff payload", diff.payload ~= nil and diff.payload ~= "", vim.inspect(diff))
if diff.payload then
	check("diff payload is a diff fence", diff.payload:find("^```diff"), diff.payload:sub(1, 40))
	check("diff payload carries the change", diff.payload:find("+after", 1, true) ~= nil, diff.payload)
end

local empty_repo = vim.fn.tempname()
vim.fn.mkdir(empty_repo, "p")
vim.system({ "git", "init", "-q" }, { cwd = empty_repo, text = true }):wait()
local no_diff = context.build("gitdiff", { cwd = empty_repo })
check("a clean tree is an error, not an empty message", no_diff.error ~= nil, vim.inspect(no_diff))

-- ----------------------------------------------------------------- sending

local inbox = dir .. "/inbox.txt"
local ran = call("terminal.run", {
	argv = { "sh", "-c", "cat > " .. inbox },
	name = "herdr-prompt-smoke",
	notify = false,
})
check("probe terminal started", ran and ran.result and ran.result.address ~= nil, vim.inspect(ran))

local address = ran and ran.result and ran.result.address
if address then
	local review = prompts.find("Review", {})
	check("catalog has Review", review ~= nil)

	-- Without the entry there is nothing to send; say so rather than throwing.
	local text = review and compose.render(review.body, context.build("selection", {
		bufnr = bufnr,
		first = 2,
		last = 3,
		cwd = dir,
	})) or ""

	local sent = call("terminal.send", { terminal = address, text = text })
	check("send accepted", sent and sent.result ~= nil, vim.inspect(sent))

	-- Give the program a moment to write the file to disk.
	local received = ""
	vim.wait(3000, function()
		received = table.concat(vim.fn.readfile(inbox), "\n")
		return received ~= ""
	end, 50)

	check("payload location arrived", received:find("@probe.lua:2-3", 1, true) ~= nil, received)
	check("the code itself is not copied", received:find("local b = 2", 1, true) == nil, received)
	check("no fence without code", received:find("```lua", 1, true) == nil, received)
	check("prompt body arrived", received:find("Review this code", 1, true) ~= nil, received)

	call("terminal.kill", { terminal = address })
	call("terminal.rm", { terminal = address })
end

-- ---------------------------------------------------------- context command

do
	local mod = require("herdr-prompt")
	local app = require("herdr-prompt.app")
	local saved_request, saved_select = rpc.request, vim.ui.select
	local saved_copy, saved_focus, saved_paste = app.copy, app.focus, app.paste
	local sent, copied, focused, pasted, keys_pressed, order = nil, nil, nil, nil, nil, {}

	local function install_stubs()
		app.copy = function(text)
			copied = text
			table.insert(order, "copy")
			return true
		end
		app.focus = function(terminal, cb)
			focused = terminal
			table.insert(order, "focus")
			if cb then
				cb(true)
			end
		end
		app.paste = function(cb)
			pasted = true
			table.insert(order, "paste")
			if cb then
				cb(true)
			end
		end
		rpc.request = function(method, params, cb)
			table.insert(order, method)
			if method == "terminal.list" then
				if cb then
					cb({ result = { terminals = { {
						address = "t1m", state = "live", cwd = "/Users/xiechao",
						foreground = { cwd = "/Users/xiechao/agent_workspace" },
						labels = { where = "agent_workspace / 1" },
						status = { app = "pi", state = "done" },
					} } } })
				end
				return
			end
			if method == "terminal.send" then
				sent = params
				if cb then
					cb({ result = { started = 1, status = "working", turn = 1 } })
				end
				return
			end
			if method == "terminal.keys" then
				keys_pressed = params.keys
				if cb then
					cb({ result = {} })
				end
				return
			end
			if cb then
				cb({ result = {} })
			end
		end
		vim.ui.select = function(items, _, on_choice)
			on_choice(items[1], 1)
		end
	end

	local function restore_stubs()
		rpc.request = saved_request
		vim.ui.select = saved_select
		app.copy = saved_copy
		app.focus = saved_focus
		app.paste = saved_paste
	end

	install_stubs()
	-- keymaps = {}: this test runs setup once, and mapping is not what it checks.
	mod.setup({ target = "t1m", confirm = true, keymaps = {} })

	local buf = vim.api.nvim_create_buf(true, false)
	vim.api.nvim_set_current_buf(buf)
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "local a = 1", "local b = 2" })
	-- Inside the agent's folder, so the reference is relative to it.
	vim.api.nvim_buf_set_name(buf, "/Users/xiechao/agent_workspace/x.lua")
	vim.bo[buf].filetype = "lua"
	vim.api.nvim_win_set_cursor(0, { 2, 0 })

	mod.context({})
	vim.wait(3000, function()
		return pasted ~= nil
	end, 20)

	eq("the reference goes to the clipboard with a space in front of it", " @x.lua:2", copied)
	eq("the context command focuses the agent", "t1m", focused)
	check("the reference is pasted into it", pasted == true, vim.inspect(pasted))
	check("nothing is submitted: no turn is started", sent == nil, vim.inspect(sent))
	-- One `ctrl+a` goes to the start of the line whatever the path length.
	-- `home` is ESC[H and an agent ignores it; `left` works but needs one press
	-- per character and overshoots into earlier text (all verified live).
	check(
		"the cursor is sent to the line start with one ctrl+a",
		vim.deep_equal({ "ctrl+a" }, keys_pressed),
		vim.inspect(keys_pressed)
	)
	eq(
		"copy, focus, paste, then a key press for the cursor",
		"copy,focus,paste,terminal.keys",
		table.concat(vim.tbl_filter(function(step)
			return step ~= "terminal.list"
		end, order), ",")
	)

	-- The picker no longer offers a row that is not a prompt.
	local names = {}
	for _, choice in ipairs(prompts.choices({})) do
		table.insert(names, choice.name)
	end
	check(
		"the picker has no inline row",
		not vim.tbl_contains(names, "Write my own…"),
		table.concat(names, ", ")
	)
	eq("the catalog still ends with Commit", "Commit", names[#names])
	eq("nothing but prompts reach the picker", #prompts.choices({}), #prompts.catalog)

	pcall(vim.api.nvim_buf_delete, buf, { force = true })
	restore_stubs()
	package.loaded["herdr-prompt"] = nil
	require("herdr-prompt")
end

-- The compose float with real key presses: <C-s> sends what is in the buffer.
do
	local typed
	ui.compose_float({
		title = "Review → t1m",
		lines = { "Review this code.", "", "@x.lua:1" },
		on_submit = function(text)
			typed = text
		end,
	})
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ggA  Please be brief.<C-s>", true, false, true), "x", false)
	vim.wait(1000, function()
		return typed ~= nil
	end, 20)
	eq("edits in the float are what gets sent", "Review this code.  Please be brief.\n\n@x.lua:1", typed)

	local untouched
	ui.compose_float({
		title = "Review → t1m",
		lines = { "Review this code.", "", "@x.lua:1" },
		on_submit = function(text)
			untouched = text
		end,
	})
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<C-s>", true, false, true), "x", false)
	vim.wait(1000, function()
		return untouched ~= nil
	end, 20)
	eq("an untouched float sends its lines unchanged", "Review this code.\n\n@x.lua:1", untouched)
end

-- ---------------------------------------------------------- agent picking

local list = nil
agents.list(function(l)
	list = l
end)
vim.wait(10000, function()
	return list ~= nil
end, 20)
check("agent list arrives", type(list) == "table", vim.inspect(list))
if type(list) == "table" then
	local names = {}
	for _, a in ipairs(list) do
		table.insert(names, a.address)
	end
	check(
		"the probe terminal is not offered as an agent",
		address == nil or not vim.tbl_contains(names, address),
		table.concat(names, ",")
	)
	check("every offered target is live with an app", (function()
		for _, a in ipairs(list) do
			if a.state ~= "live" or not a.app then
				return false
			end
		end
		return true
	end)())
	vim.notify(
		string.format("herdr-prompt smoke: %d agent terminal(s): %s", #list, table.concat(names, ", ")),
		vim.log.levels.INFO
	)
end

-- ------------------------------------------------------------------ report

vim.fn.delete(dir, "rf")
vim.fn.delete(repo, "rf")
vim.fn.delete(empty_repo, "rf")
rpc.stop()

if #failures == 0 then
	print(string.format("PASS %d checks", checks))
	os.exit(0)
end
for _, failure in ipairs(failures) do
	print("FAIL " .. failure)
end
print(string.format("FAILED %d of %d checks", #failures, checks))
os.exit(1)

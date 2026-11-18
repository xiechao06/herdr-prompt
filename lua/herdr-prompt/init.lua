-- herdr-prompt: send a prompt from nvim to an agent running in the Herdr app.
--
-- Transport is herdr-core (`hc connect`), so this works wherever the core runs,
-- not only inside a Herdr window. Design records live in docs/adr/.

local rpc = require("herdr-prompt.rpc")
local agents = require("herdr-prompt.agents")
local context = require("herdr-prompt.context")
local prompts = require("herdr-prompt.prompts")
local user_prompts = require("herdr-prompt.user_prompts")
local compose = require("herdr-prompt.compose")
local ui = require("herdr-prompt.ui")
local app = require("herdr-prompt.app")

local M = {}

M.config = {
	hc = "hc",
	-- ask the picker once per nvim session; nil = ask on first send
	target = nil,
	-- show the composed message for editing before sending
	confirm = true,
	-- move focus to the agent pane after a send
	focus_agent = false,
	-- extra prompts, same shape as prompts.catalog; same name overrides
	prompts = {},
	-- nil = <nvim config>/herdr-prompts
	user_prompts_dir = nil,
	context = {
		-- Send the lines too, not just `path:12-18`. Off by default: the agent
		-- is in the workspace and can read the file itself.
		code = false,
		-- `:HerdrContext`: leave the cursor at the start of the pasted reference,
		-- ready for the question that belongs in front of it.
		cursor_before = true,
		-- with `code`, prefix each line with its number (CopilotChat style)
		line_numbers = false,
		-- with `code`, refuse more lines than this rather than truncating
		max_lines = 2000,
	},
	keymaps = {
		prompt = "<leader>ap",
		context = "<leader>ac",
		target = "<leader>at",
	},
}

--- Session state, kept out of `config` so a later `setup()` cannot silently
--- retarget a session that is already pointed somewhere.
local state = { target = nil }

local function error_notify(msg)
	vim.notify("herdr-prompt: " .. msg, vim.log.levels.ERROR)
end

local function user_list()
	local list = user_prompts.load(M.config.user_prompts_dir or (vim.fn.stdpath("config") .. "/herdr-prompts"))
	for _, extra in ipairs(M.config.prompts or {}) do
		table.insert(list, extra)
	end
	return list
end

local function line_count(text)
	local n = 1
	for _ in text:gmatch("\n") do
		n = n + 1
	end
	return n
end

-- ---------------------------------------------------------------- target

local function use_target(agent)
	state.target = agent
	vim.notify("herdr-prompt: prompts go to " .. agents.display(agent), vim.log.levels.INFO)
end

--- Ask which agent, then remember it. A single live agent costs no picker:
--- there is nothing to choose between.
local function ask_target(cb)
	agents.list(function(list, err)
		if not list then
			return error_notify(err)
		end
		if #list == 0 then
			return error_notify("no live agent terminals — start an agent in Herdr first")
		end
		if #list == 1 then
			state.target = list[1]
			return cb(list[1])
		end
		agents.pick(list, function(choice)
			state.target = choice
			cb(choice)
		end, state.target and state.target.address)
	end)
end

--- Resolve the target, asking only when the answer is not already known.
local function with_target(cb)
	if not state.target then
		return ask_target(cb)
	end
	-- The address may have finished since it was chosen.
	agents.find(state.target.address, function(fresh)
		if fresh then
			state.target = fresh
			cb(fresh)
		else
			error_notify("agent " .. state.target.address .. " is gone — choose another")
			state.target = nil
		end
	end)
end

function M.choose_target(address)
	if address and address ~= "" then
		return agents.find(address, function(agent)
			if agent then
				use_target(agent)
			else
				error_notify("no live agent terminal at " .. address)
			end
		end)
	end
	agents.list(function(list, err)
		if not list then
			return error_notify(err)
		end
		if #list == 0 then
			return error_notify("no live agent terminals — start an agent in Herdr first")
		end
		agents.pick(list, use_target, state.target and state.target.address)
	end)
end

function M.target()
	return state.target
end

--- Addresses, for `:HerdrPromptTarget <Tab>`. A completion callback has to
--- answer now, so this one waits on the reply instead of returning a promise.
function M._complete_targets()
	local done, out = false, {}
	agents.list(function(list)
		for _, agent in ipairs(list or {}) do
			table.insert(out, agent.address)
		end
		done = true
	end)
	vim.wait(500, function()
		return done
	end, 20)
	return out
end

-- ------------------------------------------------------------------ send

local function do_send(agent, text, opts)
	opts = opts or {}
	if agent.status == "blocked" then
		return error_notify(agents.display(agent) .. " is blocked — answer its question in its pane first")
	end
	if agent.status == "working" then
		vim.notify(
			"herdr-prompt: " .. agents.display(agent) .. " is working — sending anyway",
			vim.log.levels.WARN
		)
	end
	rpc.request("terminal.send", { terminal = agent.address, text = text }, function(msg)
		if msg.error then
			return error_notify("send failed: " .. tostring(msg.error.message or "?"))
		end
		local result = msg.result or {}
		local note = string.format("sent %d lines → %s", line_count(text), agents.display(agent))
		if result.started == nil then
			note = note .. " (no agent status reported)"
		end
		vim.notify("herdr-prompt: " .. note, vim.log.levels.INFO)
		if opts.focus or M.config.focus_agent then
			app.focus(agent.address)
		end
	end)
end

-- ---------------------------------------------------------------- prompt

--- What the call site selected: a visual range when the command had one,
--- otherwise the cursor's line.
--- opts = {range?, line1?, line2?}
local function call_site(opts)
	local ranged = (opts.range or 0) > 0
	local first, last
	if ranged then
		first, last = opts.line1, opts.line2
	else
		first = vim.api.nvim_win_get_cursor(0)[1]
		last = first
	end
	return {
		bufnr = vim.api.nvim_get_current_buf(),
		first = first,
		last = last,
		-- A visual call means "this selection"; a plain call only has a line.
		kind = ranged and "selection" or "line",
	}
end

--- opts = {name?, range?, line1?, line2?}
function M.prompt(opts)
	opts = opts or {}
	local site = call_site(opts)
	local bufnr, first, last, default_kind = site.bufnr, site.first, site.last, site.kind

	with_target(function(agent)
		local function go(entry, submit)
			local payload = context.build(entry.context or default_kind, {
				bufnr = bufnr,
				first = first,
				last = last,
				cwd = agent.folder,
				code = M.config.context.code,
				max_lines = M.config.context.max_lines,
				line_numbers = M.config.context.line_numbers,
			})
			if payload.error then
				return error_notify(payload.error)
			end
			local text = compose.render(entry.body or "", payload)
			-- `confirm = false` sends without the review float.
			if not M.config.confirm then
				if submit == false then
					return error_notify("this prompt is sent without review, so an unsent one has nowhere to live")
				end
				return do_send(agent, text)
			end
			ui.compose_float({
				-- The address, not the app: two `pi` agents are two different
				-- places to send this.
				title = string.format("%s → %s", entry.name or "prompt", agent.address or agent.app),
				lines = vim.split(text, "\n", { plain = true }),
				on_submit = function(edited)
					if submit == false then
						return
					end
					do_send(agent, edited)
				end,
			})
		end

		local user = user_list()
		if opts.name and opts.name ~= "" then
			local entry = prompts.find(opts.name, user)
			if not entry then
				return error_notify(string.format("no prompt named %q", opts.name))
			end
			return go(entry, entry.submit ~= false)
		end

		prompts.pick(prompts.choices(user), function(choice)
			go(choice, choice.submit ~= false)
		end)
	end)
end

--- Send the reference and nothing else, then put you in the agent's pane so you
--- can go on talking there. A mention on its own is a complete message: the
--- agent reads the file and asks what you want.
--- opts = {range?, line1?, line2?}
function M.context(opts)
	local site = call_site(opts or {})
	with_target(function(agent)
		local payload = context.build(site.kind, {
			bufnr = site.bufnr,
			first = site.first,
			last = site.last,
			cwd = agent.folder,
			code = M.config.context.code,
			max_lines = M.config.context.max_lines,
			line_numbers = M.config.context.line_numbers,
		})
		if payload.error then
			return error_notify(payload.error)
		end
		if payload.payload == "" then
			return error_notify("nothing to send: no context here")
		end
		-- Not a message: the reference goes into the agent's input box, unsubmitted,
		-- and focus follows it there. herdr-core cannot paste without pressing
		-- Enter, so the text travels by the clipboard and the app's own paste.
		-- A space *before* the reference: the cursor is parked in front of it, so
		-- the question typed there ends up separated from the mention rather than
		-- touching it. Nothing trails the reference — the cursor is not there.
		local copied, copy_error = app.copy(" " .. payload.payload)
		if not copied then
			return error_notify("cannot use the clipboard, so nothing was pasted: " .. tostring(copy_error))
		end
		app.focus(agent.address, function(focused, focus_error)
			if not focused then
				return error_notify("could not focus " .. agent.address .. ": " .. tostring(focus_error))
			end
			app.paste(function(pasted, paste_error)
				if not pasted then
					return error_notify("could not paste into " .. agent.address .. ": " .. tostring(paste_error))
				end
				if M.config.context.cursor_before then
					-- A paste leaves the cursor after the text, and a cursor key in
					-- the clipboard cannot move it back: inside a bracketed paste the
					-- app wraps the text and the escape arrives as characters
					-- (verified: ESC[200~ ... ESC[201~).
					--
					-- `home` is no good either — herdr-core sends ESC[H for it and an
					-- agent's input box ignores that. `left` is ESC[D, which it does
					-- honour (verified in a real agent: nine lefts then a key press
					-- gave "q @x.lua:2"). So: one left per character pasted.
					local text = " " .. payload.payload
					local keys = {}
					for _ = 1, vim.fn.strchars(text) do
						table.insert(keys, "left")
					end
					rpc.request("terminal.keys", { terminal = agent.address, keys = keys }, function(msg)
						if msg.error then
							vim.notify(
								"herdr-prompt: could not move the cursor to the start: "
									.. tostring(msg.error.message or "?"),
								vim.log.levels.WARN
							)
						end
					end)
				end
				vim.notify(
					string.format(
						"herdr-prompt: %s pasted into %s — type your question there",
						payload.payload,
						agent.address
					),
					vim.log.levels.INFO
				)
			end)
		end)
	end)
end

-- ----------------------------------------------------------------- setup

local function map(mode, lhs, rhs, desc)
	if lhs == nil or lhs == "" then
		return
	end
	if not vim.tbl_isempty(vim.fn.maparg(lhs, mode, false, true)) then
		vim.notify(
			string.format("herdr-prompt: not overriding existing %s map %s", mode, lhs),
			vim.log.levels.WARN
		)
		return
	end
	vim.keymap.set(mode, lhs, rhs, { desc = desc })
end

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	rpc.setup({ bin = M.config.hc })
	if M.config.target then
		state.target = type(M.config.target) == "table" and M.config.target
			or { address = M.config.target, app = "?", status = "?", state = "live", folder = "" }
	end
	local keys = M.config.keymaps or {}
	map("n", keys.prompt, function()
		M.prompt({})
	end, "herdr-prompt: send a prompt")
	map("x", keys.prompt, function()
		vim.cmd("normal! \27")
		M.prompt({ range = 2, line1 = vim.fn.line("'<"), line2 = vim.fn.line("'>") })
	end, "herdr-prompt: send a prompt about the selection")
	map("x", keys.context, function()
		vim.cmd("normal! \27")
		M.context({ range = 2, line1 = vim.fn.line("'<"), line2 = vim.fn.line("'>") })
	end, "herdr-prompt: paste this selection into the agent")
	map("n", keys.context, function()
		M.context({})
	end, "herdr-prompt: paste this line into the agent")
	map("n", keys.target, function()
		M.choose_target(nil)
	end, "herdr-prompt: choose the agent")
end

function M.stop()
	rpc.stop()
end

return M

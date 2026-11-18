-- Which agent terminals can receive a prompt.
--
-- `terminal.list` returns every terminal as
--   {address, state, cwd, name, labels, status: {app, state}, ...}
-- Note `status` is an OBJECT here. `hc ls --json` flattens it to a string; the
-- two are not interchangeable (docs/adr/0002). An agent terminal is one whose
-- status carries an `app` (pi, claude, codex, …) and whose state is `live`.

local rpc = require("herdr-prompt.rpc")

local M = {}

local function tail(path)
	if not path or path == "" then
		return "?"
	end
	return vim.fn.fnamemodify(path, ":t")
end

--- Live agent terminals, sorted by agent kind then folder.
function M.list(cb)
	rpc.request("terminal.list", {}, function(msg)
		if msg.error then
			return cb(nil, tostring(msg.error.message or "terminal.list failed"))
		end
		local out = {}
		local me = vim.env.HC_TERMINAL_ID
		for _, t in ipairs((msg.result or {}).terminals or {}) do
			local st = t.status
			if t.state == "live" and type(st) == "table" and st.app and t.address ~= me then
				table.insert(out, {
					address = t.address,
					app = st.app,
					-- `status` is the agent's word (idle|working|done|blocked|error);
					-- `state` is the terminal's (live|finished). Never swap them.
					status = st.state or "unknown",
					state = t.state,
					cwd = t.cwd or "",
					name = t.name,
					title = t.title,
					where = (t.labels or {}).where,
				})
			end
		end
		table.sort(out, function(a, b)
			if a.app ~= b.app then
				return a.app < b.app
			end
			return a.cwd < b.cwd
		end)
		cb(out)
	end)
end

--- `pi · idle · herdr-app-prompt`, plus the terminal name when it has one.
function M.display(agent)
	local bits = { agent.app, agent.status }
	if agent.name and agent.name ~= "" then
		table.insert(bits, agent.name)
	end
	table.insert(bits, tail(agent.cwd))
	return table.concat(bits, " · ")
end

--- Ask the person which agent. `vim.ui.select` keeps this free of a picker
--- dependency; dressing.nvim turns it into a real floating picker.
function M.pick(list, cb)
	vim.ui.select(list, {
		prompt = "Send prompts to which agent?",
		format_item = M.display,
	}, function(choice)
		if choice then
			cb(choice)
		end
	end)
end

--- Find a fresh record for an address, or nil when it is gone.
function M.find(address, cb)
	M.list(function(list)
		for _, agent in ipairs(list or {}) do
			if agent.address == address then
				return cb(agent)
			end
		end
		cb(nil)
	end)
end

--- `herdr-app do agent.focus --terminal t7` — show the agent you just messaged.
function M.focus(address)
	vim.system({ "herdr-app", "do", "agent.focus", "--terminal", address }, { text = true }, function() end)
end

return M

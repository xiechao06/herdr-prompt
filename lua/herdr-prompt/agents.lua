-- Which agent terminals can receive a prompt.
--
-- `terminal.list` returns every terminal as
--   {address, state, cwd, name, labels, status: {app, state}, ...}
-- Note `status` is an OBJECT here. `hc ls --json` flattens it to a string; the
-- two are not interchangeable (docs/adr/0002). An agent terminal is one whose
-- status carries an `app` (pi, claude, codex, …) and whose state is `live`.

local rpc = require("herdr-prompt.rpc")

local M = {}

local function text(value)
	return type(value) == "string" and value or nil
end

--- One terminal from the core, as this plugin wants it: strings or nil, never
--- a JSON null, never a nested table. Exposed for tests.
function M._normalize(t)
	local status = type(t.status) == "table" and t.status or {}
	local labels = type(t.labels) == "table" and t.labels or {}
	local foreground = type(t.foreground) == "table" and t.foreground or {}
	return {
		address = text(t.address),
		app = text(status.app),
		-- `status` is the agent's word (idle|working|done|blocked|error);
		-- `state` is the terminal's (live|finished). Never swap them.
		status = text(status.state) or "unknown",
		state = text(t.state),
		-- Where it is *now*: `cwd` is the folder it was launched in, which goes
		-- stale the moment the agent cds anywhere (herdr-core's own manual says
		-- so). Paths are relativised against this.
		folder = text(foreground.cwd) or text(t.cwd) or "",
		-- The Herdr UI's own name for that pane: "<space> / <tab>".
		where = text(labels.where),
		name = text(t.name),
		title = text(t.title),
	}
end

--- Live, and running a program that reports an agent status.
function M._is_agent(t)
	local agent = M._normalize(t)
	return agent.address ~= nil and agent.state == "live" and agent.app ~= nil
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
			if M._is_agent(t) then
				local agent = M._normalize(t)
				if agent.address ~= me then
					table.insert(out, agent)
				end
			end
		end
		table.sort(out, function(a, b)
			if a.app ~= b.app then
				return a.app < b.app
			end
			return a.address < b.address
		end)
		cb(out)
	end)
end

local function tail(path)
	if not path or path == "" then
		return "?"
	end
	return vim.fn.fnamemodify(path, ":t")
end

--- `t1m · pi · done · agent_workspace / 1` — the address first, because it is
--- the name you type for `:HerdrPromptTarget`, then what it is, then the pane
--- label the Herdr window shows.
---
--- Every part is a string here: this is a picker label, and label builders that
--- concatenate whatever they are handed are how `vim.NIL` used to reach
--- `table.concat`.
function M.display(agent)
	local bits = {}
	for _, part in ipairs({ agent.address, agent.app, agent.status, agent.name }) do
		if type(part) == "string" and part ~= "" then
			table.insert(bits, part)
		end
	end
	table.insert(bits, agent.where or tail(agent.folder))
	return table.concat(bits, " · ")
end

--- The marker on the agent prompts are already going to.
M.CURRENT = "✓ "

--- Ask the person which agent. `vim.ui.select` is handed labels — plain
--- strings — and the answer is mapped back, so no picker implementation can
--- trip over the shape of a terminal record.
---
--- `current` is the address already chosen, marked with `✓` and named in the
--- prompt: re-opening the picker answers "where do my prompts go?" first.
function M.pick(list, cb, current)
	local labels, by_label = {}, {}
	local marked = false
	for i, agent in ipairs(list) do
		local label = M.display(agent)
		if current ~= nil and agent.address == current then
			label = M.CURRENT .. label
			marked = true
		end
		if by_label[label] ~= nil then
			-- Two terminals can read identically (same app, same folder).
			label = label .. " (" .. i .. ")"
		end
		labels[i] = label
		by_label[label] = agent
	end
	local prompt = "Send prompts to which agent?"
	if marked then
		prompt = prompt .. " (" .. vim.trim(M.CURRENT) .. " = current)"
	end
	vim.ui.select(labels, { prompt = prompt }, function(choice)
		local agent = choice and by_label[choice] or nil
		if agent then
			cb(agent)
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

return M

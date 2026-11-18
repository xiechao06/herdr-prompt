-- The Herdr window: focus a terminal, paste into it, and the clipboard.
--
-- Kept apart from `agents` because these are the app's commands, not
-- herdr-core's: the core cannot paste without submitting (`terminal.send`
-- always presses Enter), while the app's `terminal.paste` types the clipboard
-- into the focused terminal and leaves it there.

local M = {}

local function run(args, cb)
	cb = cb or function() end
	local argv = { "herdr-app", "do" }
	vim.list_extend(argv, args)
	vim.system(argv, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				local why = vim.trim(result.stderr or "")
				return cb(nil, why ~= "" and why or ("exit " .. result.code))
			end
			cb(true)
		end)
	end)
end

--- Show the terminal the agent runs in.
function M.focus(terminal, cb)
	run({ "agent.focus", "--terminal", terminal }, cb)
end

--- Paste the clipboard into the focused terminal. No Enter: this is how text
--- gets into an agent's input box without starting a turn.
function M.paste(cb)
	run({ "terminal.paste" }, cb)
end

--- The entries Herdr's + menu shows: programs the app can start, with the
--- command line each one runs. `knownAgents()` is a mod API we cannot call, but
--- the menu caches its answer per machine in shared state, which is the same
--- list it draws. Stale until that menu is opened again.
function M.menu_entries()
	local home = vim.env.HERDR_APP_HOME or (vim.fn.expand("~") .. "/.config/herdr-app")
	local ok, lines = pcall(vim.fn.readfile, home .. "/shared.json")
	if not ok then
		return {}
	end
	local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
	if not decoded or type(data) ~= "table" then
		return {}
	end
	local by_machine = data["new-menu.agents"]
	if type(by_machine) ~= "table" or type(by_machine[""]) ~= "table" then
		return {}
	end
	local out = {}
	for _, row in ipairs(by_machine[""]) do
		local run = type(row) == "table" and row.run or nil
		if type(run) == "table" and #run > 0 then
			table.insert(out, {
				key = row.key,
				name = row.name or row.key,
				run = run,
				installed = row.installed == true,
			})
		end
	end
	return out
end

--- Start one + menu entry in a new tab. `cb(address, error)` gets the terminal
--- the app says it created.
function M.launch(entry, cb)
	local argv = { "herdr-app", "do", "tab.new", "--name", entry.name, "--argv", vim.json.encode(entry.run) }
	vim.system(argv, { text = true }, function(result)
		vim.schedule(function()
			if result.code ~= 0 then
				local why = vim.trim(result.stderr or "")
				return cb(nil, why ~= "" and why or ("exit " .. result.code))
			end
			local decoded, reply = pcall(vim.json.decode, result.stdout or "")
			local address = decoded and type(reply) == "table" and reply.terminal or nil
			if not address then
				return cb(nil, "tab.new answered without a terminal")
			end
			cb(address)
		end)
	end)
end

--- Put `text` on the system clipboard, which is what the app's paste reads.
--- `+` is that clipboard on macOS and on X11 with a provider.
function M.copy(text)
	local ok, err = pcall(vim.fn.setreg, "+", text)
	if not ok then
		return nil, tostring(err)
	end
	if vim.fn.getreg("+") ~= text then
		return nil, "no clipboard provider"
	end
	return true
end

return M

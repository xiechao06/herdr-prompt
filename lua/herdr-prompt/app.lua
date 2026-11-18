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

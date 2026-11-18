-- One `hc connect` process, JSON-RPC 2.0, one message per line.
--
-- herdr-core answers `hello` with {generation, framed: false, methods, features}.
-- We keep `framed` off: newline-delimited JSON is what we can split reliably in
-- jobstart's on_stdout. See docs/adr/0002-jsonrpc-over-hc-connect.md.

local M = {}

local state = {
	bin = "hc",
	job = nil,
	hello = nil,
	partial = "",
	next_id = 0,
	pending = {}, -- id -> callback
	queue = {}, -- requests held until `hello` answers
	ready = false,
	stderr = {},
	listeners = {}, -- notification method -> { callback, ... }
}

local function notify_error(msg)
	vim.schedule(function()
		vim.notify("herdr-prompt: " .. msg, vim.log.levels.ERROR)
	end)
end

--- JSON `null` decodes to `vim.NIL`, a userdata: truthy, unlike anything else,
--- and fatal to `table.concat`. Core sends nulls for every unset field (`name`,
--- `exit_code`, `started`), so every reply is denulled here, once, instead of
--- every caller remembering.
local function denull(value)
	if value == vim.NIL then
		return nil
	end
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		if v ~= vim.NIL then
			out[k] = denull(v)
		end
	end
	return out
end

M._denull = denull

local function emit(method, params)
	for _, cb in ipairs(state.listeners[method] or {}) do
		pcall(cb, params)
	end
end

local function handle_line(line)
	if line == "" then
		return
	end
	local ok, msg = pcall(vim.json.decode, line)
	if not ok or type(msg) ~= "table" then
		return
	end
	if msg.id ~= nil then
		local cb = state.pending[msg.id]
		if cb then
			state.pending[msg.id] = nil
			msg.result = denull(msg.result)
			msg.params = denull(msg.params)
			vim.schedule(function()
				cb(msg)
			end)
		end
		return
	end
	if type(msg.method) == "string" then
		emit(msg.method, denull(msg.params))
	end
end

local function on_stdout(_, data)
	if not data then
		return
	end
	-- data[1] continues the previous partial line; every later element is a
	-- complete line except the last, which may itself be partial.
	local chunk = state.partial .. (data[1] or "")
	for i = 2, #data do
		handle_line(chunk)
		chunk = data[i]
	end
	state.partial = chunk
end

local function encode(msg)
	if msg.params == nil or next(msg.params) == nil then
		msg.params = nil
	end
	return vim.json.encode(msg) .. "\n"
end

local function send_now(method, params, cb)
	state.next_id = state.next_id + 1
	local id = state.next_id
	state.pending[id] = cb
	local body = encode({ jsonrpc = "2.0", id = id, method = method, params = params })
	local ok = state.job and pcall(vim.api.nvim_chan_send, state.job, body)
	if not ok then
		state.pending[id] = nil
		vim.schedule(function()
			cb({ error = { message = "hc connect is not accepting input" } })
		end)
	end
end

local function fail_all(reason)
	local pending = state.pending
	state.pending = {}
	local queue = state.queue
	state.queue = {}
	vim.schedule(function()
		for _, cb in pairs(pending) do
			cb({ error = { message = reason } })
		end
		for _, item in ipairs(queue) do
			item.cb({ error = { message = reason } })
		end
	end)
end

local function stop()
	local job = state.job
	state.job = nil
	state.ready = false
	state.partial = ""
	state.hello = nil
	if job then
		pcall(vim.fn.jobstop, job)
	end
end

local function start(bin)
	state.partial = ""
	state.stderr = {}
	local job
	job = vim.fn.jobstart({ bin, "connect" }, {
		stdout_buffered = false,
		on_stdout = on_stdout,
		on_stderr = function(_, data)
			if not data then
				return
			end
			for _, line in ipairs(data) do
				if line ~= "" then
					table.insert(state.stderr, line)
				end
			end
		end,
		on_exit = function(_, code)
			if state.job ~= job then
				return
			end
			local tail = #state.stderr > 0 and (": " .. state.stderr[#state.stderr]) or ""
			stop()
			fail_all(string.format("hc connect exited (%d)%s", code, tail))
		end,
	})
	if job <= 0 then
		fail_all(string.format("could not start `%s connect` — is herdr-core installed and on PATH?", bin))
		return
	end
	state.job = job
	send_now("hello", { calls_you = "herdr-prompt" }, function(msg)
		if msg.error then
			stop()
			notify_error("hello failed: " .. tostring(msg.error.message or "?"))
			fail_all("hello failed")
			return
		end
		state.hello = msg.result or {}
		if state.hello.generation and state.hello.generation ~= 1 then
			notify_error(
				string.format(
					"herdr-core speaks protocol generation %s, this plugin was written for 1",
					tostring(state.hello.generation)
				)
			)
		end
		state.ready = true
		local queue = state.queue
		state.queue = {}
		for _, item in ipairs(queue) do
			send_now(item.method, item.params, item.cb)
		end
	end)
end

--- Call one method. `cb` receives the whole JSON-RPC reply (`{result=}` or `{error=}`).
function M.request(method, params, cb)
	cb = cb or function() end
	if state.ready and state.job then
		send_now(method, params, cb)
		return
	end
	table.insert(state.queue, { method = method, params = params, cb = cb })
	if not state.job then
		start(state.bin)
	end
end

--- Listen for server-pushed notifications (e.g. `event` from events.subscribe).
function M.on(method, cb)
	state.listeners[method] = state.listeners[method] or {}
	table.insert(state.listeners[method], cb)
end

function M.hello()
	return state.hello
end

function M.is_ready()
	return state.ready and state.job ~= nil
end

function M.stop()
	stop()
end

function M.setup(opts)
	state.bin = (opts and opts.bin) or state.bin
end

return M

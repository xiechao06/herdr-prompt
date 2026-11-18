-- Putting the message together: the request, then the context.
--
-- The body may place the context itself with `{{context}}`; when it does not,
-- the body goes first, a blank line, then the payload. `{{file}}` and
-- `{{lines}}` are available too.
-- See docs/adr/0008-context-is-a-reference.md

local M = {}

--- `ctx` is what context.build returned: {payload, file, range, lang}.
function M.render(body, ctx)
	body = body or ""
	ctx = ctx or {}
	local placeholders = {
		["{{context}}"] = ctx.payload or "",
		["{{file}}"] = ctx.file or "",
		["{{lines}}"] = ctx.range or "",
	}
	local found = false
	local text = body:gsub("{{[%a_]+}}", function(token)
		local value = placeholders[token]
		if value == nil then
			return token
		end
		found = true
		return value
	end)
	if found then
		return vim.trim(text)
	end
	local payload = ctx.payload or ""
	body = vim.trim(text)
	if payload == "" then
		return body
	end
	if body == "" then
		return payload
	end
	-- Request first, reference after. The ask is what the agent has to act on;
	-- the reference is what it acts on, and reads as the closing line.
	return body .. "\n\n" .. payload
end

return M

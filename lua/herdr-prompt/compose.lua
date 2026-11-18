-- Putting the message together: prompt body + context payload.
--
-- The body may say where the context goes with `{{context}}`; when it does not,
-- the payload is appended after a blank line. `{{file}}` and `{{lines}}` are
-- available too.
-- See docs/adr/0004-context-payload-shape.md

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
	if payload == "" then
		return vim.trim(text)
	end
	if text == "" then
		return payload
	end
	return text .. "\n\n" .. payload
end

return M

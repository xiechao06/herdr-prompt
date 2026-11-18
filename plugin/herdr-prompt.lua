-- Commands, registered on load so `:HerdrPrompt` works without a setup() call.
-- setup() only changes defaults and adds keymaps.

if vim.g.loaded_herdr_prompt == 1 then
	return
end
vim.g.loaded_herdr_prompt = 1

vim.api.nvim_create_user_command("HerdrPrompt", function(opts)
	require("herdr-prompt").prompt({
		name = opts.args ~= "" and opts.args or nil,
		range = opts.range,
		line1 = opts.line1,
		line2 = opts.line2,
	})
end, {
	nargs = "?",
	range = true,
	desc = "Send a prompt to a Herdr agent, with this line or selection as context",
	complete = function(arg)
		local names = {}
		for _, p in ipairs(require("herdr-prompt.prompts").catalog) do
			table.insert(names, p.name)
		end
		return vim.tbl_filter(function(name)
			return name:lower():find(arg:lower(), 1, true) == 1
		end, names)
	end,
})

vim.api.nvim_create_user_command("HerdrPromptTarget", function(opts)
	require("herdr-prompt").choose_target(opts.args ~= "" and opts.args or nil)
end, {
	nargs = "?",
	desc = "Choose the Herdr agent that prompts are sent to",
	complete = function()
		return require("herdr-prompt")._complete_targets()
	end,
})

vim.api.nvim_create_user_command("HerdrPromptStop", function()
	require("herdr-prompt").stop()
end, {
	desc = "Close the herdr-prompt connection to herdr-core",
})

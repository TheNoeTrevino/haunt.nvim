---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.config", function()
	local config

	before_each(function()
		helpers.reset_modules()
		config = require("haunt.config")
	end)

	describe("default configuration", function()
		it("returns defaults when setup not called", function()
			local cfg = config.get()

			assert.are.equal("󱙝", cfg.sign)
			assert.are.equal("DiagnosticInfo", cfg.sign_hl)
			assert.are.equal("HauntAnnotation", cfg.virt_text_hl)
			assert.are.equal(" 󰆉 ", cfg.annotation_prefix)
			assert.is_nil(cfg.line_hl)
			assert.are.equal("eol", cfg.virt_text_pos)
		end)

		it("returns deep copy to prevent modification", function()
			local cfg1 = config.get()
			cfg1.sign = "modified"

			local cfg2 = config.get()
			assert.are.not_equal("modified", cfg2.sign)
		end)
	end)

	describe("annotation_suffix configuration", function()
		it("has empty string as default", function()
			local cfg = config.get()
			assert.are.equal("", cfg.annotation_suffix)
		end)

		it("accepts custom annotation_suffix", function()
			config.setup({ annotation_suffix = " >>>" })
			local cfg = config.get()
			assert.are.equal(" >>>", cfg.annotation_suffix)
		end)

		it("preserves annotation_suffix across setup calls", function()
			config.setup({ annotation_suffix = " <<<" })
			config.setup({ sign = "🔖" })

			local cfg = config.get()
			assert.are.equal(" <<<", cfg.annotation_suffix)
		end)

		it("allows both prefix and suffix", function()
			config.setup({
				annotation_prefix = "[ ",
				annotation_suffix = " ]",
			})
			local cfg = config.get()
			assert.are.equal("[ ", cfg.annotation_prefix)
			assert.are.equal(" ]", cfg.annotation_suffix)
		end)
	end)

	describe("setup()", function()
		it("merges single option with defaults", function()
			config.setup({ sign = "🔖" })
			local cfg = config.get()

			assert.are.equal("🔖", cfg.sign)
			assert.are.equal("DiagnosticInfo", cfg.sign_hl)
		end)

		it("merges multiple options with defaults", function()
			config.setup({
				sign = "🔖",
				sign_hl = "Error",
				virt_text_pos = "inline",
			})
			local cfg = config.get()

			assert.are.equal("🔖", cfg.sign)
			assert.are.equal("Error", cfg.sign_hl)
			assert.are.equal("inline", cfg.virt_text_pos)
			assert.are.equal("HauntAnnotation", cfg.virt_text_hl)
		end)

		it("handles empty table", function()
			config.setup({})
			local cfg = config.get()

			assert.are.equal("󱙝", cfg.sign)
			assert.are.equal("DiagnosticInfo", cfg.sign_hl)
		end)

		it("handles nil parameter", function()
			config.setup(nil)
			local cfg = config.get()

			assert.are.equal("󱙝", cfg.sign)
			assert.are.equal("DiagnosticInfo", cfg.sign_hl)
		end)
	end)

	describe("multiple setup() calls", function()
		it("preserves previous configuration on second call", function()
			config.setup({ sign = "🔖" })
			config.setup({ virt_text_hl = "Comment" })

			local cfg = config.get()
			assert.are.equal("🔖", cfg.sign)
			assert.are.equal("Comment", cfg.virt_text_hl)
			assert.are.equal("DiagnosticInfo", cfg.sign_hl)
		end)

		it("allows overriding specific fields", function()
			config.setup({ sign = "🔖", sign_hl = "Error" })
			config.setup({ sign = "📌" })

			local cfg = config.get()
			assert.are.equal("📌", cfg.sign)
			assert.are.equal("Error", cfg.sign_hl)
		end)

		it("preserves configuration when called with empty table", function()
			config.setup({ sign = "🔖", virt_text_hl = "Comment" })
			config.setup({})

			local cfg = config.get()
			assert.are.equal("🔖", cfg.sign)
			assert.are.equal("Comment", cfg.virt_text_hl)
		end)

		it("preserves configuration when called with nil", function()
			config.setup({ sign = "🔖", virt_text_hl = "Comment" })
			config.setup(nil)

			local cfg = config.get()
			assert.are.equal("🔖", cfg.sign)
			assert.are.equal("Comment", cfg.virt_text_hl)
		end)

		it("accumulates multiple configuration calls", function()
			config.setup({ sign = "🔖" })
			config.setup({ virt_text_hl = "Comment" })
			config.setup({ sign_hl = "Error" })
			config.setup({ virt_text_pos = "inline" })

			local cfg = config.get()
			assert.are.equal("🔖", cfg.sign)
			assert.are.equal("Comment", cfg.virt_text_hl)
			assert.are.equal("Error", cfg.sign_hl)
			assert.are.equal("inline", cfg.virt_text_pos)
		end)
	end)

	describe("nested configuration (picker_keys)", function()
		it("preserves default nested configuration", function()
			config.setup({ sign = "🔖" })

			local cfg = config.get()
			assert.is_table(cfg.picker_keys)
			assert.is_table(cfg.picker_keys.delete)
			assert.are.equal("d", cfg.picker_keys.delete.key)
		end)

		it("merges nested configuration deeply", function()
			config.setup({
				picker_keys = {
					delete = { key = "x", mode = { "n" } },
				},
			})

			local cfg = config.get()
			assert.are.equal("x", cfg.picker_keys.delete.key)
			assert.is_table(cfg.picker_keys.edit_annotation)
			assert.are.equal("a", cfg.picker_keys.edit_annotation.key)
		end)

		it("preserves nested config across multiple setup calls", function()
			config.setup({
				picker_keys = {
					delete = { key = "x", mode = { "n" } },
				},
			})
			config.setup({ sign = "🔖" })

			local cfg = config.get()
			assert.are.equal("x", cfg.picker_keys.delete.key)
			assert.are.equal("🔖", cfg.sign)
		end)
	end)

	describe("is_setup()", function()
		it("returns false when setup not called", function()
			assert.is_false(config.is_setup())
		end)

		it("returns true after setup called", function()
			config.setup()
			assert.is_true(config.is_setup())
		end)

		it("returns true after setup with options", function()
			config.setup({ sign = "🔖" })
			assert.is_true(config.is_setup())
		end)
	end)

	describe("data_dir configuration", function()
		it("allows custom data_dir", function()
			config.setup({ data_dir = "/custom/path" })
			local cfg = config.get()

			assert.are.equal("/custom/path", cfg.data_dir)
		end)

		it("preserves data_dir across setup calls", function()
			config.setup({ data_dir = "/custom/path" })
			config.setup({ sign = "🔖" })

			local cfg = config.get()
			assert.are.equal("/custom/path", cfg.data_dir)
		end)
	end)
end)

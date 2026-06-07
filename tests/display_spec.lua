---@module 'luassert'
---@diagnostic disable: need-check-nil, param-type-mismatch

local helpers = require("tests.helpers")

describe("haunt.display", function()
	local display
	---@class haunt.Persistence
	local persistence
	---@class haunt.Config
	local config

	before_each(function()
		helpers.reset_modules()
		display = require("haunt.display")
		persistence = require("haunt.persistence")
		config = require("haunt.config")
		config.setup() -- Initialize with defaults
	end)

	describe("setup_signs", function()
		it("initializes display module", function()
			assert.is_true(display.is_initialized())
		end)

		it("uses default config values", function()
			local cfg = display.get_config()
			assert.are.equal("󱙝", cfg.sign)
			assert.are.equal("DiagnosticInfo", cfg.sign_hl)
		end)

		local custom_configs = {
			{ field = "sign", value = "🔖" },
			{ field = "sign_hl", value = "WarningMsg" },
			{ field = "line_hl", value = "CursorLine" },
			{ field = "virt_text_hl", value = "Comment" },
		}

		for _, case in ipairs(custom_configs) do
			it("accepts custom " .. case.field, function()
				config.setup({ [case.field] = case.value })
				local cfg = display.get_config()
				assert.are.equal(case.value, cfg[case.field])
			end)
		end
	end)

	describe("show_annotation / hide_annotation", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("creates extmark with correct properties", function()
			local extmark_id = display.show_annotation(bufnr, 2, "Test note")

			assert.is_number(extmark_id)
			assert.is_true(extmark_id > 0)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, { details = true })
			local found = false
			for _, mark in ipairs(extmarks) do
				if mark[1] == extmark_id then
					found = true
					assert.is_not_nil(mark[4].virt_text)
				end
			end
			assert.is_true(found)
		end)

		it("removes extmark on hide", function()
			local extmark_id = display.show_annotation(bufnr, 2, "Test note")
			display.hide_annotation(bufnr, extmark_id)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			local found = false
			for _, mark in ipairs(extmarks) do
				if mark[1] == extmark_id then
					found = true
				end
			end
			assert.is_false(found)
		end)
	end)

	describe("annotation with suffix", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("includes suffix in virtual text", function()
			config.setup({
				annotation_prefix = "[ ",
				annotation_suffix = " ]",
			})

			local extmark_id = display.show_annotation(bufnr, 1, "TODO")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })

			assert.are.equal("[ TODO ]", details[3].virt_text[1][1])
		end)

		it("works with only suffix (no prefix)", function()
			config.setup({
				annotation_prefix = "",
				annotation_suffix = " 🔖",
			})

			local extmark_id = display.show_annotation(bufnr, 1, "Important")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })

			assert.are.equal("Important 🔖", details[3].virt_text[1][1])
		end)

		it("works with empty suffix (backward compatibility)", function()
			config.setup({
				annotation_prefix = ">>> ",
				annotation_suffix = "",
			})

			local extmark_id = display.show_annotation(bufnr, 1, "Note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })

			assert.are.equal(">>> Note", details[3].virt_text[1][1])
		end)
	end)

	describe("annotation with virt_text_pos = above", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("creates extmark with virt_lines above the line", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> " })

			local extmark_id = display.show_annotation(bufnr, 2, "Test note")
			assert.is_number(extmark_id)

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })

			assert.is_not_nil(details[3].virt_lines)
			assert.is_true(details[3].virt_lines_above)
		end)

		it("places virt_lines below line 1 (above row 0 is clipped by Neovim)", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> " })

			local extmark_id = display.show_annotation(bufnr, 1, "first line note")
			assert.is_number(extmark_id)

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })

			assert.is_not_nil(details[3].virt_lines)
			assert.is_false(details[3].virt_lines_above)
		end)

		it("renders single-line note as top + body + bottom", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> " })

			local extmark_id = display.show_annotation(bufnr, 2, "fix this")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			-- top border + 1 body row + bottom border = 3
			assert.are.equal(3, #virt_lines)
			-- Top border is 3 chunks: corner + edge + corner
			assert.are.equal(3, #virt_lines[1])
			assert.are.equal("╭", virt_lines[1][1][1])
			assert.are.equal("╮", virt_lines[1][3][1])
			-- Body row has border + content (padded to full width) + border
			assert.are.equal("│", virt_lines[2][1][1])
			assert.is_true(vim.startswith(virt_lines[2][2][1], "> fix this"))
			assert.are.equal("│", virt_lines[2][3][1])
		end)

		it("renders multi-line note with multiple body rows", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> " })

			local extmark_id = display.show_annotation(bufnr, 2, "line one\nline two")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			-- top border + 2 body rows + bottom border = 4
			assert.are.equal(4, #virt_lines)
			-- Body rows
			assert.are.equal("│", virt_lines[2][1][1])
			assert.are.equal("│", virt_lines[2][3][1])
			assert.are.equal("│", virt_lines[3][1][1])
			assert.are.equal("│", virt_lines[3][3][1])
		end)

		it("splits literal backslash-n as line breaks", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> " })

			local extmark_id = display.show_annotation(bufnr, 1, "first\\nsecond")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			-- top + 2 body rows + bottom = 4
			assert.are.equal(4, #virt_lines)
			assert.is_true(vim.startswith(virt_lines[2][2][1], "> first"))
			assert.is_true(vim.startswith(virt_lines[3][2][1], "  second"))
		end)

		it("wraps long text at above_max_width boundary", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_max_width = 20 })

			-- "> hello world foo bar" is 21 display cols, should wrap
			local extmark_id = display.show_annotation(bufnr, 1, "hello world foo bar")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			-- Should have more than 3 lines (top + multiple body rows + bottom)
			assert.is_true(#virt_lines > 3)
			-- All body rows must fit within the box width
			local box_width = 0
			for _, chunk in ipairs(virt_lines[1]) do
				box_width = box_width + vim.fn.strdisplaywidth(chunk[1])
			end
			for i = 2, #virt_lines - 1 do
				local row_width = 0
				for _, chunk in ipairs(virt_lines[i]) do
					row_width = row_width + vim.fn.strdisplaywidth(chunk[1])
				end
				assert.are.equal(box_width, row_width)
			end
		end)

		it("does not wrap short text", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_max_width = 80 })

			local extmark_id = display.show_annotation(bufnr, 1, "short")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			-- top + 1 body + bottom = 3
			assert.are.equal(3, #virt_lines)
		end)

		it("includes annotation suffix", function()
			config.setup({
				virt_text_pos = "above",
				annotation_prefix = "> ",
				annotation_suffix = "!",
			})

			local extmark_id = display.show_annotation(bufnr, 1, "fix this")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.is_true(vim.startswith(virt_lines[2][2][1], "> fix this!"))
		end)

		it("handles tiny above_max_width values without hanging", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_max_width = 1 })

			local extmark_id = display.show_annotation(bufnr, 1, "unbroken")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.is_true(#virt_lines > 3)
		end)

		it("can be hidden like regular annotations", function()
			config.setup({ virt_text_pos = "above" })

			local extmark_id = display.show_annotation(bufnr, 2, "note")
			local ok = display.hide_annotation(bufnr, extmark_id)
			assert.is_true(ok)

			local ns = display.get_namespace()
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, ns, 0, -1, {})
			local found = false
			for _, mark in ipairs(extmarks) do
				if mark[1] == extmark_id then
					found = true
				end
			end
			assert.is_false(found)
		end)

		it("uses single border when above_border = 'single'", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_border = "single" })

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.are.equal("┌", virt_lines[1][1][1])
			assert.are.equal("┐", virt_lines[1][3][1])
			assert.are.equal("│", virt_lines[2][1][1])
			assert.are.equal("│", virt_lines[2][3][1])
			local last = virt_lines[#virt_lines]
			assert.are.equal("└", last[1][1])
			assert.are.equal("┘", last[3][1])
		end)

		it("uses double border when above_border = 'double'", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_border = "double" })

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.are.equal("╔", virt_lines[1][1][1])
			assert.are.equal("╗", virt_lines[1][3][1])
			assert.are.equal("║", virt_lines[2][1][1])
			assert.are.equal("║", virt_lines[2][3][1])
		end)

		it("accepts custom 8-element border array", function()
			config.setup({
				virt_text_pos = "above",
				annotation_prefix = "> ",
				above_border = { "+", "-", "+", "|", "+", "-", "+", "|" },
			})

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.are.equal("+", virt_lines[1][1][1])
			assert.are.equal("+", virt_lines[1][3][1])
			assert.are.equal("|", virt_lines[2][1][1])
			assert.are.equal("|", virt_lines[2][3][1])
			local last = virt_lines[#virt_lines]
			assert.are.equal("+", last[1][1])
			assert.are.equal("+", last[3][1])
		end)

		it("accepts border elements with highlight groups", function()
			config.setup({
				virt_text_pos = "above",
				annotation_prefix = "> ",
				above_border = {
					{ "╭", "Special" },
					{ "─", "Title" },
					{ "╮", "Special" },
					{ "│", "Comment" },
					{ "╯", "Special" },
					{ "─", "Title" },
					{ "╰", "Special" },
					{ "│", "Comment" },
				},
			})

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			-- Top border: corner hl distinct from edge hl
			assert.are.equal("Special", virt_lines[1][1][2])
			assert.are.equal("Title", virt_lines[1][2][2])
			assert.are.equal("Special", virt_lines[1][3][2])
			-- Left/right borders use the side highlight
			assert.are.equal("Comment", virt_lines[2][1][2])
			assert.are.equal("Comment", virt_lines[2][3][2])
		end)

		it("renders empty border with above_border = 'none'", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_border = "none" })

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.are.equal("", virt_lines[1][1][1])
			assert.are.equal("", virt_lines[1][3][1])
			assert.are.equal("", virt_lines[2][1][1])
			assert.are.equal("", virt_lines[2][3][1])
		end)

		it("falls back to rounded for unknown preset strings", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_border = "shadow" })

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.are.equal("╭", virt_lines[1][1][1])
			assert.are.equal("│", virt_lines[2][1][1])
		end)

		it("falls back to rounded for array length that does not divide 8", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_border = { "a", "b", "c" } })

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.are.equal("╭", virt_lines[1][1][1])
			assert.are.equal("│", virt_lines[2][1][1])
		end)

		it("falls back to rounded for empty table", function()
			config.setup({ virt_text_pos = "above", annotation_prefix = "> ", above_border = {} })

			local extmark_id = display.show_annotation(bufnr, 2, "note")

			local ns = display.get_namespace()
			local details = vim.api.nvim_buf_get_extmark_by_id(bufnr, ns, extmark_id, { details = true })
			local virt_lines = details[3].virt_lines

			assert.are.equal("╭", virt_lines[1][1][1])
			assert.are.equal("│", virt_lines[2][1][1])
		end)
	end)

	describe("set_bookmark_mark / get_extmark_line / delete_bookmark_mark", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3", "Line 4", "Line 5" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("creates extmark at correct line", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			assert.not_nil(bookmark)
			---@cast bookmark -nil

			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)
			assert.not_nil(extmark_id)
			---@cast extmark_id -nil

			assert.is_number(extmark_id)
			assert.is_true(extmark_id > 0)

			local line = display.get_extmark_line(bufnr, extmark_id)
			assert.are.equal(3, line)
		end)

		it("tracks line movement on insert above", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			assert.not_nil(bookmark)
			---@cast bookmark -nil

			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)
			assert.not_nil(extmark_id)
			---@cast extmark_id -nil

			-- Insert line above
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "New Line" })

			local new_line = display.get_extmark_line(bufnr, extmark_id)
			assert.are.equal(4, new_line)
		end)

		it("tracks line movement on delete above", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)

			-- Insert then delete
			vim.api.nvim_buf_set_lines(bufnr, 0, 0, false, { "New Line" })
			vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, {})

			local line = display.get_extmark_line(bufnr, extmark_id)
			assert.are.equal(3, line)
		end)

		it("deletes extmark successfully", function()
			local bookmark = persistence.create_bookmark("test.lua", 3, "Test")
			local extmark_id = display.set_bookmark_mark(bufnr, bookmark)

			local delete_ok = display.delete_bookmark_mark(bufnr, extmark_id)
			assert.is_true(delete_ok)

			local line = display.get_extmark_line(bufnr, extmark_id)
			assert.is_nil(line)
		end)
	end)

	describe("clear_buffer_marks", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("clears all extmarks from buffer", function()
			local b1 = persistence.create_bookmark("test.lua", 1)
			local b2 = persistence.create_bookmark("test.lua", 2)
			local b3 = persistence.create_bookmark("test.lua", 3)

			local e1 = display.set_bookmark_mark(bufnr, b1)
			local e2 = display.set_bookmark_mark(bufnr, b2)
			local e3 = display.set_bookmark_mark(bufnr, b3)

			assert.is_not_nil(e1)
			assert.is_not_nil(e2)
			assert.is_not_nil(e3)

			local clear_ok = display.clear_buffer_marks(bufnr)
			assert.is_true(clear_ok)

			assert.is_nil(display.get_extmark_line(bufnr, e1))
			assert.is_nil(display.get_extmark_line(bufnr, e2))
			assert.is_nil(display.get_extmark_line(bufnr, e3))
		end)
	end)

	describe("place_sign / unplace_sign", function()
		local bufnr

		before_each(function()
			bufnr = vim.api.nvim_create_buf(false, true)
			vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "Line 1", "Line 2", "Line 3" })
		end)

		after_each(function()
			if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
				vim.api.nvim_buf_delete(bufnr, { force = true })
			end
		end)

		it("places sign at correct line", function()
			display.place_sign(bufnr, 2, 100)

			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			assert.is_true(#signs > 0)
			assert.is_true(#signs[1].signs > 0)

			local found = false
			for _, sign in ipairs(signs[1].signs) do
				if sign.id == 100 then
					found = true
					assert.are.equal(2, sign.lnum)
					assert.are.equal("HauntBookmark", sign.name)
				end
			end
			assert.is_true(found)
		end)

		it("removes sign on unplace", function()
			display.place_sign(bufnr, 2, 100)
			display.unplace_sign(bufnr, 100)

			local signs = vim.fn.sign_getplaced(bufnr, { group = "haunt_signs" })
			local found = false
			if #signs > 0 and #signs[1].signs > 0 then
				for _, sign in ipairs(signs[1].signs) do
					if sign.id == 100 then
						found = true
					end
				end
			end
			assert.is_false(found)
		end)
	end)
end)

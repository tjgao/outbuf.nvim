local last_command = nil

local function open_buf_with_float_win(bufnr, title, opts)
    local w = math.max(math.min(opts.width, vim.o.columns - 20), 20)
    local h = math.max(math.min(opts.height, vim.o.lines - 10), 20)
    return vim.api.nvim_open_win(bufnr, true, {
        relative = "editor",
        title = title,
        width = w,
        height = h,
        row = (vim.o.lines - h - 1) * 0.5,
        col = (vim.o.columns - w) * 0.5,
        border = "rounded",
        footer = "Press q to exit",
        footer_pos = "right",
        style = opts.style,
    })
end

-- merge multiple consecutive empty lines into one
local function merge_spaces(o)
    local ret, last_space = {}, false
    for i = 1, #o, 1 do
        if o[i]:gsub("^%s*(.-)%s*$", "%1") == "" then
            if not last_space then
                ret[#ret + 1] = o[i]
            end
            last_space = true
        else
            ret[#ret + 1] = o[i]
            last_space = false
        end
    end
    return ret
end

local function make_quitable(bufnr)
    vim.api.nvim_buf_set_keymap(bufnr, "n", "q", "<cmd>quit<CR>", {})
end

local function move_to_end(win, lines)
    vim.api.nvim_win_set_cursor(win, { #lines, 0 })
end

local function show_info(output, title, opts)
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, output)
    opts.width = opts.width or math.floor(vim.o.columns * 0.618)
    opts.height = opts.height or math.floor(vim.o.lines * 0.618)
    local win = open_buf_with_float_win(bufnr, title, opts)
    vim.api.nvim_set_option_value("wrap", (opts.wrap and true) or false, { win = win })
    vim.api.nvim_set_option_value("modifiable", (opts.modifiable and true) or false, { buf = bufnr })
    move_to_end(win, output)
    make_quitable(bufnr)
end

local function retrieve_results(opts, ...)
    local varg = { ... }
    local cmd = table.concat(varg, " ")
    local obj = vim.api.nvim_exec2(cmd, { output = true })
    if obj.output ~= "" then
        local output = vim.split(obj.output, "\n")
        if opts.merge_spaces == true then
            output = merge_spaces(output)
        end
        local cmd_show = cmd
        if string.len(cmd) > 33 then
            cmd_show = string.sub(cmd, 1, 30) .. "..."
        end
        show_info(output, "Output from: " .. cmd_show, opts)
    end
end

-- used for debug
local function reload()
    if package.loaded.outbuf then
        package.loaded["outbuf"] = nil
    end
    require("outbuf").setup({
        wrap = true,
        -- style = "minimal",
        -- modifiable = true,
        merge_spaces = true,
    })
end

-- by default
-- the values in cfg
-- cmd = "Ob", the user command for Outbuf
-- wrap = false
-- style = nil, or 'minimal', one possible value
-- modifiable = false
-- width, display_area_width * 0.618
-- height, display_area_height * 0.618
-- merge_spaces, merge multiple consective empty lines into one
local function setup(cfg)
    cfg = cfg or {}
    local cmd = cfg.cmd or "Ob"
    vim.api.nvim_create_user_command(cmd, function(opts)
        if opts.bang and last_command then
            retrieve_results(cfg, unpack(last_command))
        else
            if not opts.args or string.len(opts.args) < 1 then
                print("Usage: :" .. cmd .. " <command> <arg1>? <arg2>? ... or :" .. cmd .. "! to repeat last command")
                return
            end
            retrieve_results(cfg, unpack(opts.fargs))
            last_command = opts.fargs
        end
    end, {
        bang = true,
        nargs = "*",
        desc = "Outbuf command",
        complete = "command",
    })
end

return {
    -- used for debug
    -- reload = reload,
    setup = setup,
}

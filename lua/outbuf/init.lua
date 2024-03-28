local A = require("plenary.async")
local J = require("plenary.job")

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
        footer = ":set ma(!) :set wrap(!) | press q to exit",
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

local function shorten_string(str, len)
    if string.len(str) > len then
        return string.sub(str, 1, len - 3) .. "..."
    end
    return str
end

local function create_task_popup(opts, states)
    local bufnr = vim.api.nvim_create_buf(false, true)
    opts.width = opts.width or math.floor(vim.o.columns * 0.618)
    opts.height = opts.height or math.floor(vim.o.lines * 0.618)
    vim.api.nvim_buf_set_var(bufnr, "local_task_states", states)
    local show_cmd = "Output from: " .. shorten_string(states.cmd, 33)
    local win = open_buf_with_float_win(bufnr, show_cmd, opts)
    states["win"], states["bufnr"] = win, bufnr
    return win, bufnr
end

local function launch_sync(opts, states)
    local obj = vim.api.nvim_exec2(states.cmd, { output = true })
    if not obj.output or obj.output == "" then
        print("No output for this command")
        return
    end
    local output = vim.split(obj.output, "\n")
    if opts.merge_spaces == true then
        output = merge_spaces(output)
    end
    local win, bufnr = create_task_popup(opts, states)
    vim.api.nvim_buf_set_text(bufnr, 0, 0, 0, 0, output)
    vim.api.nvim_buf_set_lines(bufnr, -1, -1, true, output)
    vim.api.nvim_win_set_cursor(win, { #output, 0 })
    vim.api.nvim_set_option_value("wrap", (opts.wrap and true) or false, { win = win })
    vim.api.nvim_set_option_value("modifiable", (opts.modifiable and true) or false, { buf = bufnr })
    make_quitable(bufnr)
    states["running"] = false
end

local function launch_async(opts, states)
    local win, bufnr = create_task_popup(opts, states)
    vim.api.nvim_set_option_value("wrap", (opts.wrap and true) or false, { win = win })
    -- vim.api.nvim_set_option_value("modifiable", (opts.modifiable and true) or false, { buf = bufnr })

    local function start_job()
        local job = J:new({
            command = states.cmd,
            args = states.args,
            on_stdout = function(err, line, j)
                vim.schedule(function()
                    vim.api.nvim_buf_set_lines(states.bufnr, -1, -1, true, { line })
                    vim.cmd("norm G 0")
                end)
            end,
            on_exit = function(j, _)
                states["running"] = false
            end,
        })

        job:start()
    end

    A.void(start_job)("")
end

local function launch(opts, ...)
    local varg = { ... }
    if #varg < 1 then
        return
    end

    local task_states = {}
    if string.sub(varg[1], 1, 1) == "!" then
        -- external commands, we do it in the async way
        task_states["mode"] = "async"
        task_states["cmd"] = string.sub(varg[1], 2)
        table.remove(varg, 1)
        task_states["args"] = varg
        launch_async(opts, task_states)
    else
        -- internal commands
        task_states["mode"] = "sync"
        task_states["cmd"] = table.concat(varg, " ")
        launch_sync(opts, task_states)
    end
end

-- used for debug
---@diagnostic disable-next-line: unused-function
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
    if cfg.move_to_end == nil then
        cfg["move_to_end"] = true
    end
    local cmd = cfg.cmd or "Ob"
    vim.api.nvim_create_user_command(cmd, function(opts)
        if opts.bang then
            -- TODO: show outbuf list
            -- retrieve_results(cfg, unpack(last_command))
        else
            if not opts.args or string.len(opts.args) < 1 then
                print("Usage: :" .. cmd .. " <command> <arg1>? <arg2>? ... or :" .. cmd .. "! to repeat last command")
                return
            end
            launch(cfg, unpack(opts.fargs))
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
    reload = reload,
    setup = setup,
}

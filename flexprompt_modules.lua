--------------------------------------------------------------------------------
-- Built in modules for flexprompt.

if ((clink and clink.version_encoded) or 0) < 10020010 then
    return
end

--------------------------------------------------------------------------------
-- Internals.

-- Is reset to {} at each onbeginedit.
local _cached_state = {}

--------------------------------------------------------------------------------
-- BATTERY MODULE:  {battery:show=show_level:breakleft:breakright}
--  - show_level shows the battery module unless the battery level is greater
--    than show_level.
--  - 'breakleft' adds an empty segment to left of battery in rainbow style.
--  - 'breakright' adds an empty segment to right of battery in rainbow style.
--
-- The 'breakleft' and 'breakright' options may look better than having battery
-- segment colors adjacent to other similarly colored segments in rainbow style.

local rainbow_battery_colors =
{
    {
        fg = "38;2;239;65;54",
        bg = "48;2;239;65;54"
    },
    {
        fg = "38;2;252;176;64",
        bg = "48;2;252;176;64"
    },
    {
        fg = "38;2;248;237;50",
        bg = "48;2;248;237;50"
    },
    {
        fg = "38;2;142;198;64",
        bg = "48;2;142;198;64"
    },
    {
        fg = "38;2;1;148;68",
        bg = "48;2;1;148;68"
    }
}

local function get_battery_status()
    local level, acpower, charging
    local batt_symbol = flexprompt.get_symbol("battery")

    local status = os.getbatterystatus()
    level = status.level
    acpower = status.acpower
    charging = status.charging

    if not level or level < 0 or (acpower and not charging) then
        return "", 0
    end
    if charging then
        batt_symbol = flexprompt.get_symbol("charging")
    end

    return level..batt_symbol, level
end

local function get_battery_status_color(level)
    if flexprompt.can_use_extended_colors() then
        local index = ((((level > 0) and level or 1) - 1) / 20) + 1
        index = math.modf(index)
        return rainbow_battery_colors[index], index == 1
    elseif level > 50 then
        return "green"
    elseif level > 30 then
        return "yellow"
    end
    return "red", true
end

local prev_battery_status, prev_battery_level
local function update_battery_prompt()
    while true do
        local status,level = get_battery_status()
        if prev_battery_level ~= status or prev_battery_level ~= level then
            clink.refilterprompt()
        end
        coroutine.yield()
    end
end

local function render_battery(args)
    if not os.getbatterystatus then return end

    local show = tonumber(flexprompt.parse_arg_token(args, "s", "show") or "100")
    local batteryStatus,level = get_battery_status()
    prev_battery_status = batteryStatus
    prev_battery_level = level

    if clink.addcoroutine and flexprompt.settings.battery_idle_refresh ~= false and not _cached_state.battery_coroutine then
        local t = coroutine.create(update_battery_prompt)
        _cached_state.battery_coroutine = t
        clink.addcoroutine(t, flexprompt.settings.battery_refresh_interval or 15)
    end

    -- Hide when on AC power and fully charged, or when level is less than or
    -- equal to the specified 'show=level' ({battery:show=75} means "show at 75
    -- or lower").
    if not batteryStatus or batteryStatus == "" or level > (show or 80) then
        return
    end

    local style = get_style()

    -- The 'breakleft' and 'breakright' args add blank segments to force a color
    -- break between rainbow segments, in case adjacent colors are too similar.
    local bl, br
    if style == "rainbow" then
        bl = flexprompt.parse_arg_keyword(args, "bl", "breakleft")
        br = flexprompt.parse_arg_keyword(args, "br", "breakright")
    end

    local color, warning = get_battery_status_color(level)

    if warning and style == "classic" then
        -- batteryStatus = flexprompt.make_fluent_text(sgr(color.bg .. ";30") .. batteryStatus)
        -- The "22;" defeats the color parsing that would normally generate
        -- corresponding fg and bg colors even though only an explicit bg color
        -- was provided (versus a usual {fg=x,bg=y} color table).
        color = "22;" .. color.bg .. ";30"
    end

    local segments = {}
    if bl then table.insert(segments, { "", "black" }) end
    table.insert(segments, { batteryStatus, color, "black" })
    if br then table.insert(segments, { "", "black" }) end

    return segments
end

--------------------------------------------------------------------------------
-- CWD MODULE:  {cwd:color=color_name,alt_color_name:rootcolor=rootcolor_name:type=type_name}
--  - color_name is a name like "green", or an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style.
--  - rootcolor_name overrides the repo parent color when using "rootsmart".
--  - type_name is the format to use:
--      - "full" is the full path.
--      - "folder" is just the folder name.
--      - "smart" is the git repo\subdir, or the full path.
--      - "rootsmart" is the full path, with parent of git repo not colored.
--
-- The default type is "rootsmart" if not specified.

-- Returns the folder name of the specified directory.
--  - For c:\foo\bar it yields bar
--  - For c:\ it yields c:\
--  - For \\server\share\subdir it yields subdir
--  - For \\server\share it yields \\server\share
local function get_folder_name(dir)
    local parent,child = path.toparent(dir)
    dir = child
    if #dir == 0 then
        dir = parent
    end
    return dir
end

local function render_cwd(args)
    local colors = flexprompt.parse_arg_token(args, "c", "color")
    local color, altcolor
    local style = flexprompt.get_style()
    if style == "rainbow" then
        color = "blue"
        altcolor = "white"
    elseif style == "classic" then
        color = flexprompt.can_use_extended_colors() and "38;5;39" or "cyan"
    else
        color = flexprompt.can_use_extended_colors() and "38;5;33" or "blue"
    end
    color, altcolor = flexprompt.parse_colors(colors, color, altcolor)

    local wizard = flexprompt.get_wizard_state()
    local cwd = wizard and wizard.cwd or os.getcwd()
    local git_dir

    local sym
    local type = flexprompt.parse_arg_token(args, "t", "type") or "rootsmart"
    if wizard then
        -- Disable cwd/git integration in the configuration wizard.
    elseif type == "folder" then
        cwd = get_folder_name(cwd)
    else
        repeat
            if flexprompt.settings.use_home_tilde then
                local home = os.getenv("HOME")
                if home and string.find(string.lower(cwd), string.lower(home)) == 1 then
                    git_dir = flexprompt.get_git_dir(cwd) or false
                    if not git_dir then
                        cwd = "~" .. string.sub(cwd, #home + 1)
                        break
                    end
                end
            end

            if type == "smart" or type == "rootsmart" then
                if git_dir == nil then -- Don't double-hunt for it!
                    git_dir = flexprompt.get_git_dir()
                end
                if git_dir then
                    -- Get the root git folder name and reappend any part of the
                    -- directory that comes after.
                    -- Ex: C:\Users\username\some-repo\innerdir -> some-repo\innerdir
                    local git_root_dir = path.toparent(git_dir) -- Don't use get_parent() here!
                    local appended_dir = string.sub(cwd, string.len(git_root_dir) + 1)
                    local smart_dir = get_folder_name(git_root_dir) .. appended_dir
                    if type == "rootsmart" then
                        local rootcolor = flexprompt.parse_arg_token(args, "rc", "rootcolor")
                        local parent = cwd:sub(1, #cwd - #smart_dir)
                        cwd = flexprompt.make_fluent_text(parent, rootcolor or true) .. smart_dir
                    else
                        cwd = smart_dir
                    end
                    sym = flexprompt.get_icon("cwd_git_symbol")
                end
            end
        until true
    end

    cwd = flexprompt.append_text(flexprompt.get_dir_stack_depth(), cwd)
    cwd = flexprompt.append_text(sym or flexprompt.get_module_symbol(), cwd)

    return cwd, color, altcolor
end

--------------------------------------------------------------------------------
-- DURATION MODULE:  {duration:color=color_name,alt_color_name}
--  - color_name is a name like "green", or an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style.

local endedit_time
local last_duration

-- Clink v1.2.30 has a fix for Lua's os.clock() implementation failing after the
-- program has been running more than 24 days.  Without that fix, os.time() must
-- be used instead, but the resulting duration can be off by up to +/- 1 second.
local duration_clock = ((clink.version_encoded or 0) >= 10020030) and os.clock or os.time

local function duration_onbeginedit()
    last_duration = nil
    if endedit_time then
        local beginedit_time = duration_clock()
        local elapsed = beginedit_time - endedit_time
        if elapsed >= 0 then
            last_duration = math.floor(elapsed + 0.5)
        end
    end
end

local function duration_onendedit()
    endedit_time = duration_clock()
end

local function render_duration(args)
    local duration = _wizard and _wizard.duration or last_duration
    if (duration or 0) <= 0 then return end

    local colors = flexprompt.parse_arg_token(args, "c", "color")
    local color, altcolor
    if flexprompt.get_style() == "rainbow" then
        color = "yellow"
        altcolor = "black"
    else
        if not flexprompt.can_use_extended_colors() then
            color = "darkyellow"
        else
            color = "38;5;214"
        end
    end
    color, altcolor = flexprompt.parse_colors(colors, color, altcolor)

    local text
    text = (duration % 60) .. "s"
    duration = math.floor(duration / 60)
    if duration > 0 then
        text = flexprompt.append_text((duration % 60) .. "m", text)
        duration = math.floor(duration / 60)
        if duration > 0 then
            text = flexprompt.append_text(duration .. "h", text)
        end
    end

    if flexprompt.get_flow() == "fluent" then
        text = flexprompt.append_text(flexprompt.make_fluent_text("took"), text)
    end
    text = flexprompt.append_text(text, flexprompt.get_module_symbol())

    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- EXIT MODULE:  {exit:always:color=color_name,alt_color_name:hex}
--  - 'always' always shows the exit code even when 0.
--  - color_name is used when the exit code is 0, and is a name like "green", or
--    an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style when the
--    exit code is 0.
--  - 'hex' shows the exit code in hex when > 255 or < -255.

local function render_exit(args)
    if not os.geterrorlevel then return end

    local text
    local value = flexprompt.get_errorlevel()

    local always = flexprompt.parse_arg_keyword(args, "a", "always")
    if not always and value == 0 then return end

    local hex = flexprompt.parse_arg_keyword(args, "h", "hex")

    if hex and math.abs(value) > 255 then
        local lo = bit32.band(value, 0xffff)
        local hi = bit32.rshift(value, 16)
        if hi > 0 then
            hex = string.format("%x", hi) .. string.format("%04.4x", lo)
        else
            hex = string.format("%x", lo)
        end
        text = "0x" .. hex
    else
        text = value
    end

    local colors = flexprompt.parse_arg_token(args, "c", "color")
    local color, altcolor
    if flexprompt.get_style() == "rainbow" then
        color = "black"
        altcolor = "green"
    else
        color = "darkgreen"
    end
    color, altcolor = flexprompt.parse_colors(colors, color, altcolor)

    if value ~= 0 then
        color = "red"
        altcolor = "brightyellow"
    end

    local sym = flexprompt.get_module_symbol()
    if sym == "" then
        sym = flexprompt.get_icon(value ~= 0 and "exit_nonzero" or "exit_zero")
    end
    text = flexprompt.append_text(sym, text)

    if flexprompt.get_flow() == "fluent" then
        text = flexprompt.append_text(flexprompt.make_fluent_text("exit"), text)
    end

    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- GIT MODULE:  {git:nostaged:noaheadbehind:color_options}
--  - 'nostaged' omits the staged details.
--  - 'noaheadbehind' omits the ahead/behind details.
--  - 'nounpublished' omits the "unpublished" indicator in unpublished branches.
--  - 'showremote' shows the branch and its remote.
--  - color_options override status colors as follows:
--      - clean=color_name,alt_color_name       When status is clean.
--      - conflict=color_name,alt_color_name    When a conflict exists.
--      - dirty=color_name,alt_color_name       When status is dirty.
--      - remote=color_name,alt_color_name      For ahead/behind details.
--      - staged=color_name,alt_color_name      For staged details.
--      - unknown=color_name,alt_color_name     When status is unknown.

local git = {}
local cached_info = {}
local fetched_repos = {}

-- Add status details to the segment text.  Depending on git.status_details this
-- may show verbose counts for operations, or a concise overall count.
--
-- Synchronous call.
local function add_details(text, details)
    if git.status_details then
        if details.add > 0 then
            text = flexprompt.append_text(text, flexprompt.get_symbol("addcount") .. details.add)
        end
        if details.modify > 0 then
            text = flexprompt.append_text(text, flexprompt.get_symbol("modifycount") .. details.modify)
        end
        if details.delete > 0 then
            text = flexprompt.append_text(text, flexprompt.get_symbol("deletecount") .. details.delete)
        end
        if (details.rename or 0) > 0 then
            text = flexprompt.append_text(text, flexprompt.get_symbol("renamecount") .. details.rename)
        end
    else
        text = flexprompt.append_text(text, flexprompt.get_symbol("summarycount") .. (details.add + details.modify + details.delete + (details.rename or 0)))
    end
    if (details.untracked or 0) > 0 then
        text = flexprompt.append_text(text, flexprompt.get_symbol("untrackedcount") .. details.untracked)
    end
    return text
end

-- Collects git status info.
--
-- Uses async coroutine calls.
local function collect_git_info()
    if flexprompt.settings.git_fetch_interval then
        local git_dir = flexprompt.get_git_dir():lower()
        local when = fetched_repos[git_dir]
        if not when or os.clock() - when > flexprompt.settings.git_fetch_interval * 60 then
            local file = io.popenyield("git fetch 2>nul")
            if file then file:close() end

            fetched_repos[git_dir] = os.clock()
        end
    end

    local status = flexprompt.get_git_status()
    local conflict = flexprompt.get_git_conflict()
    local ahead, behind = flexprompt.get_git_ahead_behind()
    return { status=status, conflict=conflict, ahead=ahead, behind=behind, finished=true }
end

local function parse_color_token(args, colors)
    local parsed_colors = flexprompt.parse_arg_token(args, colors.token, colors.alttoken)
    local color, altcolor = flexprompt.parse_colors(parsed_colors, colors.name, colors.altname)
    return color, altcolor
end

local git_colors =
{
    clean       = { token="c",  alttoken="clean",       name="green",   altname="black" },
    conflict    = { token="!",  alttoken="conflict",    name="red",     altname="brightwhite" },
    dirty       = { token="d",  alttoken="dirty",       name="yellow",  altname="black" },
    remote      = { token="r",  alttoken="remote",      name="cyan",    altname="black" },
    staged      = { token="s",  alttoken="staged",      name="magenta", altname="black" },
    unknown     = { token="u",  alttoken="unknown",     name="white",   altname="black" },
}

local function render_git(args)
    local git_dir
    local branch, detached
    local info
    local wizard = flexprompt.get_wizard_state()

    if wizard then
        git_dir = true
        branch = wizard.branch or "main"
        info = { finished=true }
    else
        git_dir = flexprompt.get_git_dir()
        if not git_dir then return end

        branch, detached = flexprompt.get_git_branch(git_dir)
        if not branch then return end

        -- Discard cached info if from a different repo or branch.
        if (cached_info.git_dir ~= git_dir) or (cached_info.git_branch ~= branch) then
            cached_info = {}
            cached_info.git_dir = git_dir
            cached_info.git_branch = branch
        end

        -- Use coroutine to collect status info asynchronously.
        info = flexprompt.promptcoroutine(collect_git_info)

        -- Use cached info until coroutine is finished.
        if not info then
            info = cached_info.git_info or {}
        else
            cached_info.git_info = info
        end

        -- Add remote to branch name if requested.
        if flexprompt.parse_arg_keyword(args, "sr", "showremote") then
            local remote = flexprompt.get_git_remote(git_dir)
            if remote then
                branch = branch .. flexprompt.make_fluent_text("->") .. remote
            end
        end
    end

    -- Segments.
    local segments = {}

    -- Local status.
    local style = flexprompt.get_style()
    local flow = flexprompt.get_flow()
    local gitStatus = info.status
    local gitConflict = info.conflict
    local gitUnknown = not info.finished
    local colors = git_colors.clean
    text = flexprompt.format_branch_name(branch)
    if gitConflict then
        colors = git_colors.conflict
        text = flexprompt.append_text(text, flexprompt.get_symbol("conflict"))
    elseif gitStatus and gitStatus.working then
        colors = git_colors.dirty
        text = add_details(text, gitStatus.working)
    elseif gitUnknown then
        colors = git_colors.unknown
    end

    local color, altcolor = parse_color_token(args, colors)
    table.insert(segments, { text, color, altcolor })

    -- Staged status.
    local noStaged = flexprompt.parse_arg_keyword(args, "ns", "nostaged")
    if not noStaged and gitStatus and gitStatus.staged then
        text = flexprompt.append_text("", flexprompt.get_symbol("staged"))
        colors = git_colors.staged
        text = add_details(text, gitStatus.staged)
        color, altcolor = parse_color_token(args, colors)
        table.insert(segments, { text, color, altcolor })
    end

    -- Remote status (ahead/behind).
    local noAheadBehind = flexprompt.parse_arg_keyword(args, "nab", "noaheadbehind")
    if not noAheadBehind then
        local ahead = info.ahead or "0"
        local behind = info.behind or "0"
        if ahead ~= "0" or behind ~= "0" then
            text = flexprompt.append_text("", flexprompt.get_symbol("aheadbehind"))
            colors = git_colors.remote
            if ahead ~= "0" then
                text = flexprompt.append_text(text, flexprompt.get_symbol("aheadcount") .. ahead)
            end
            if behind ~= "0" then
                text = flexprompt.append_text(text, flexprompt.get_symbol("behindcount") .. behind)
            end
            color, altcolor = parse_color_token(args, colors)
            table.insert(segments, { text, color, altcolor })
        end
    end

    -- Unpublished.
    local noUnpublished = flexprompt.parse_arg_keyword(args, "nup", "nounpublished")
    if not noUnpublished and not detached and gitStatus and gitStatus.unpublished then
        text = flexprompt.get_symbol("unpublished")
        if text == "" then text = "not published" end
        color = "magenta"
        if flexprompt.can_use_extended_colors() then
            if flexprompt.get_style() == "rainbow" then
                color = "38;5;125"
            else
                color = "38;5;198"
            end
        end
        color, altcolor = parse_color_token(args, { token="up", alttoken="unpublished", name=color, altname="black" })
        table.insert(segments, { text, color, altcolor })
    end

    return segments
end

--------------------------------------------------------------------------------
-- HG MODULE:  {hg:color_options}
--  - color_options override status colors as follows:
--      - clean=color_name,alt_color_name       When status is clean.
--      - dirty=color_name,alt_color_name       When status is dirty (modified files).

local hg_colors =
{
    clean       = { "c", "clean", "green", "black" },
    dirty       = { "d", "dirty", "red", "white" },
}

local function get_hg_dir(dir)
    return flexprompt.scan_upwards(dir, function (dir)
        -- Return if it's a hg (Mercurial) dir.
        return has_dir(dir, ".hg")
    end)
end

local function render_hg(args)
    local hg_dir = get_hg_dir()
    if not hg_dir then return end

    -- We're inside of hg repo, read branch and status.
    local pipe = io.popen("hg branch 2>&1")
    local output = pipe:read('*all')
    local rc = { pipe:close() }

    -- Strip the trailing newline from the branch name.
    local n = #output
    while n > 0 and output:find("^%s", n) do n = n - 1 end
    local branch = output:sub(1, n)
    if not branch then return end
    if string.sub(branch,1,7) == "abort: " then return end
    if string.find(branch, "is not recognized") then return end

    local flow = flexprompt.get_flow()
    local text = flexprompt.format_branch_name(branch)

    local colors
    local pipe = io.popen("hg status -amrd 2>&1")
    local output = pipe:read('*all')
    local rc = { pipe:close() }
    if (output or "") ~= "" then
        text = flexprompt.append_text(text, get_symbol("modifycount"))
        colors = hg_colors.dirty
    else
        colors = hg_colors.clean
    end

    local color, altcolor = parse_color_token(args, colors)
    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- MAVEN MODULE:  {maven:color=color_name,alt_color_name}
--  - color_name is a name like "green", or an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style.

local function get_pom_xml_dir(dir)
    return flexprompt.scan_upwards(dir, function (dir)
        local pom_file = path.join(dir, "pom.xml")
        -- More efficient than opening the file.
        if os.isfile(pom_file) then return true end
    end)
end

local function render_maven(args)
    if get_pom_xml_dir() then
        local handle = io.popen('xmllint --xpath "//*[local-name()=\'project\']/*[local-name()=\'groupId\']/text()" pom.xml 2>NUL')
        local package_group = handle:read("*a")
        handle:close()
        if package_group == nil or package_group == "" then
            local parent_handle = io.popen('xmllint --xpath "//*[local-name()=\'project\']/*[local-name()=\'parent\']/*[local-name()=\'groupId\']/text()" pom.xml 2>NUL')
            package_group = parent_handle:read("*a")
            parent_handle:close()
            if not package_group then package_group = "" end
        end

        handle = io.popen('xmllint --xpath "//*[local-name()=\'project\']/*[local-name()=\'artifactId\']/text()" pom.xml 2>NUL')
        local package_artifact = handle:read("*a")
        handle:close()
        if not package_artifact then package_artifact = "" end

        handle = io.popen('xmllint --xpath "//*[local-name()=\'project\']/*[local-name()=\'version\']/text()" pom.xml 2>NUL')
        local package_version = handle:read("*a")
        handle:close()
        if package_version == nil or package_version == "" then
            local parent_handle = io.popen('xmllint --xpath "//*[local-name()=\'project\']/*[local-name()=\'parent\']/*[local-name()=\'version\']/text()" pom.xml 2>NUL')
            package_version = parent_handle:read("*a")
            parent_handle:close()
            if not package_version then package_version = "" end
        end

        local text = package_group .. ":" .. package_artifact .. ":" .. package_version
        text = flexprompt.append_text(flexprompt.get_module_symbol(), text)

        local color, altcolor = parse_color_token(args, { "c", "color", "cyan", "white" })
        return text, color, altcolor
    end
end

--------------------------------------------------------------------------------
-- NPM MODULE:  {npm:color=color_name,alt_color_name}
--  - color_name is a name like "green", or an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style.

local function get_package_json_file(dir)
    return flexprompt.scan_upwards(dir, function (dir)
        local file = io.open(path.join(dir, "package.json"))
        if file then return file end
    end)
end

local function render_npm(args)
    local file = get_package_json_file()
    if not file then return end

    local package_info = file:read('*a')
    file:close()

    local package_name = string.match(package_info, '"name"%s*:%s*"(%g-)"') or ""
    local package_version = string.match(package_info, '"version"%s*:%s*"(.-)"') or ""

    local text = package_name .. "@" .. package_version
    text = flexprompt.append_text(flexprompt.get_module_symbol(), text)

    local color, altcolor = parse_color_token(args, { "c", "color", "cyan", "white" })
    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- PYTHON MODULE:  {python:always:color=color_name,alt_color_name}
--  - 'always' shows the python module even if there are no python files.
--  - color_name is a name like "green", or an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style.

local function get_virtual_env(env_var)
    local venv_path = false

    -- Return the folder name of the current virtual env, or false.
    local function get_virtual_env_var(var)
        env_path = clink.get_env(var)
        return env_path and string.match(env_path, "[^\\/:]+$") or false
    end

    local venv = (env_var and get_virtual_env_var(env_var)) or
        get_virtual_env_var("VIRTUAL_ENV") or
        get_virtual_env_var("CONDA_DEFAULT_ENV") or false
    return venv
end

local function has_py_files(dir)
    return flexprompt.scan_upwards(dir, function (dir)
        for _ in pairs(os.globfiles(path.join(dir, "*.py"))) do
            return true
        end
    end)
end

local function render_python(args)
    -- flexprompt.python_virtual_env_variable can be nil.
    local venv = get_virtual_env(flexprompt.python_virtual_env_variable)
    if not venv then return end

    local always = flexprompt.parse_arg_keyword(args, "a", "always")
    if not always and not has_py_files() then return end

    local text = "[" .. venv .. "]"
    text = flexprompt.append_text(flexprompt.get_module_symbol(), text)

    local color, altcolor = parse_color_token(args, { "c", "color", "cyan", "white" })
    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- SVN MODULE:  {hg:color_options}
--  - color_options override status colors as follows:
--      - clean=color_name,alt_color_name       When status is clean.
--      - dirty=color_name,alt_color_name       When status is dirty (modified files).

local svn_colors =
{
    clean       = { "c", "clean", "green", "black" },
    dirty       = { "d", "dirty", "red", "white" },
}

local function get_svn_dir(dir)
    return flexprompt.scan_upwards(dir, function (dir)
        -- Return if it's a svn (Subversion) dir.
        local has = has_dir(dir, ".svn")
        if has then return has end
    end)
end

local function get_svn_branch()
    local file = io.popen("svn info 2>nul")
    for line in file:lines() do
        local m = line:match("^Relative URL:")
        if m then
            file:close()
            return line:sub(line:find("/")+1,line:len())
        end
    end
    file:close()
end

local function get_svn_status()
    local file = io.popen("svn status -q")
    for line in file:lines() do
        file:close()
        return true
    end
    file:close()
end

local function render_svn(args)
    local svn_dir = get_svn_dir()
    if not svn_dir then return end

    local branch = get_svn_branch()
    if not branch then return end

    local flow = flexprompt.get_flow()
    local text = flexprompt.format_branch_name(branch)

    local colors = svn_colors.clean
    if get_svn_status() then
        colors = svn_colors.dirty
        text = flexprompt.append_text(text, flexprompt.get_symbol("modifycount"))
    end

    local color, altcolor = parse_color_token(args, colors)
    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- TIME MODULE:  {time:color=color_name,alt_color_name:format=format_string}
--  - color_name is a name like "green", or an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style.
--  - format_string uses the rest of the text as a format string for os.date().
--
-- If present, the 'format=' option must be last (otherwise it could never
-- include colons).

local function render_time(args)
    local colors = flexprompt.parse_arg_token(args, "c", "color")
    local color, altcolor
    if flexprompt.get_style() == "rainbow" then
        color = "white"
        altcolor = "black"
    else
        color = "darkcyan"
    end
    color, altcolor = flexprompt.parse_colors(colors, color, altcolor)

    local format = flexprompt.parse_arg_token(args, "f", "format", true)
    if not format then
        format = "%a %H:%M"
    end

    local text = os.date(format)

    if flexprompt.get_flow() == "fluent" then
        text = flexprompt.append_text(flexprompt.make_fluent_text("at"), text)
    end

    text = flexprompt.append_text(text, flexprompt.get_module_symbol())

    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- USER MODULE:  {user:type=type_name:color=color_name,alt_color_name}
--  - type_name is any of 'computer', 'user', or 'both' (the default).
--  - color_name is a name like "green", or an sgr code like "38;5;60".
--  - alt_color_name is optional; it is the text color in rainbow style.

local function render_user(args)
    local colors = flexprompt.parse_arg_token(args, "c", "color")
    local color, altcolor
    local style = flexprompt.get_style()
    if not flexprompt.can_use_extended_colors() then
        color = "magenta"
    elseif style == "rainbow" then
        color = "38;5;90"
        altcolor = "white"
    elseif style == "classic" then
        color = "38;5;171"
    else
        color = "38;5;135"
    end
    color, altcolor = flexprompt.parse_colors(colors, color, altcolor)

    local type = flexprompt.parse_arg_token(args, "t", "type") or "both"
    local user = (type ~= "computer") and os.getenv("username") or ""
    local computer = (type ~= "user") and os.getenv("computername") or ""
    if #computer > 0 then
        local prefix = "@"
        -- if #user == 0 then prefix = "\\\\" end
        computer = prefix .. computer
    end

    local text = user..computer
    return text, color, altcolor
end

--------------------------------------------------------------------------------
-- Event handlers.  Since this file contains multiple modules, let them all
-- share one event handler per event type, rather than adding separate handlers
-- for separate modules.

local function builtin_modules_onbeginedit()
    _cached_state = {}
    duration_onbeginedit()
end

local function builtin_modules_onendedit()
    duration_onendedit()
end

clink.onbeginedit(builtin_modules_onbeginedit)
clink.onendedit(builtin_modules_onendedit)

--------------------------------------------------------------------------------
-- Initialize the built-in modules.

flexprompt.add_module( "battery",   render_battery                      )
flexprompt.add_module( "cwd",       render_cwd,         { unicode="" } )
flexprompt.add_module( "duration",  render_duration,    { unicode="" } )
flexprompt.add_module( "exit",      render_exit                         )
flexprompt.add_module( "git",       render_git,         { unicode="" } )
flexprompt.add_module( "hg",        render_hg                           )
flexprompt.add_module( "maven",     render_maven                        )
flexprompt.add_module( "npm",       render_npm                          )
flexprompt.add_module( "python",    render_python,      { unicode="" } )
flexprompt.add_module( "svn",       render_svn                          )
flexprompt.add_module( "time",      render_time,        { unicode="" } )
flexprompt.add_module( "user",      render_user,        { unicode="" } )

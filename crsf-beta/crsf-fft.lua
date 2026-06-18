--[[
-- crsf-fft.lua
-- A CRSF menu for configuring FFT spectrum visualization settings.
-- Provides in-field configuration of FFT visualization directly from the transmitter.
-- Version 1.0
--]]

local crsf_helper = require('crsf_helper')
local MAV_SEVERITY = crsf_helper.MAV_SEVERITY
local CRSF_COMMAND_STATUS = crsf_helper.CRSF_COMMAND_STATUS

-- ####################
-- # PARAMETER BINDING
-- ####################

local fft_enable = assert(Parameter('FFT_ENABLE'), "FFT_ENABLE not found - FFT not available")
local fft_vis_mask = assert(Parameter('FFT_VIS_MASK'), "FFT_VIS_MASK not found")
local fft_window_size = assert(Parameter('FFT_WINDOW_SIZE'), "FFT_WINDOW_SIZE not found")
local fft_sample_mode = assert(Parameter('FFT_SAMPLE_MODE'), "FFT_SAMPLE_MODE not found")
local fft_num_frames = assert(Parameter('FFT_NUM_FRAMES'), "FFT_NUM_FRAMES not found")
local fft_options = assert(Parameter('FFT_OPTIONS'), "FFT_OPTIONS not found")
local ins_gyro_rate = Parameter('INS_GYRO_RATE')  -- Optional, may not exist on all boards
local sched_loop_rate = Parameter('SCHED_LOOP_RATE')  -- Optional, for loop rate modes

-- FFT_OPTIONS bit definitions
local OPT_POST_FILTER = 1  -- Bit 0: use post-filter samples

-- ####################
-- # STATE MANAGEMENT
-- ####################

-- Remember mask value when disabled for restore
local saved_mask = 7

-- Track if reboot-required params have changed
local pending_reboot = false

-- Scheduled reboot time (nil = no reboot pending)
-- We delay reboot to allow CRSF response to be sent first
local reboot_time_ms = nil
local REBOOT_DELAY_MS = 300

-- Axis options map to FFT_VIS_MASK bitmask values
local AXIS_OPTIONS = {"X", "Y", "Z", "X+Y", "X+Z", "Y+Z", "All"}
local AXIS_VALUES  = { 1,   2,   4,    3,     5,     6,     7  }

-- Reverse lookup: mask value -> option index (1-based)
local MASK_TO_INDEX = {[1]=1, [2]=2, [4]=3, [3]=4, [5]=5, [6]=6, [7]=7}

-- Window size options (must be powers of 2)
local WINDOW_OPTIONS = {"32", "64", "128", "256", "512"}
local WINDOW_VALUES  = { 32,   64,   128,   256,   512 }
local WINDOW_TO_INDEX = {[32]=1, [64]=2, [128]=3, [256]=4, [512]=5}

-- Averaging options (FFT_NUM_FRAMES: 0=off, 2-8 valid)
local AVG_OPTIONS = {"Off", "Light", "Medium", "Heavy"}
local AVG_VALUES  = { 0,     2,       4,        8      }
local AVG_TO_INDEX = {[0]=1, [2]=2, [4]=3, [8]=4}

-- Filter options (FFT_OPTIONS bit 0)
local FILTER_OPTIONS = {"Pre-filter", "Post-filter"}

-- RC aux function option values for zoom/pan
local RC_OPTION_FFT_VIS_PAN = 186
local RC_OPTION_FFT_VIS_ZOOM = 187

-- ####################
-- # FORWARD DECLARATIONS
-- ####################

local enable_item, axis_item, window_item, resolution_item, averaging_item, filter_item
local pan_channel_item, zoom_channel_item
local freq_range_item, status_item

-- ####################
-- # HELPER FUNCTIONS
-- ####################

--- Check if FFT is enabled at the system level
local function is_fft_enabled()
    return fft_enable:get() == 1
end

--- Get gyro sample rate in Hz from INS_GYRO_RATE parameter
-- INS_GYRO_RATE: 0=1kHz, 1=2kHz, 2=4kHz, 3=8kHz
local function get_gyro_rate_hz()
    if ins_gyro_rate then
        local rate_idx = ins_gyro_rate:get()
        if rate_idx then
            return 1000 * (2 ^ rate_idx)
        end
    end
    return 1000  -- Default to 1kHz if parameter not available
end

--- Get loop rate in Hz from SCHED_LOOP_RATE parameter
local function get_loop_rate_hz()
    if sched_loop_rate then
        local rate = sched_loop_rate:get()
        if rate and rate > 0 then
            return rate
        end
    end
    return 400  -- Default to 400Hz if parameter not available
end

--- Get sample rate for a given FFT_SAMPLE_MODE
-- Mode 0: Gyro rate, Mode 1: Loop rate, Mode 2: Loop/2, Mode 3: Loop/3
local function get_sample_rate_for_mode(mode)
    if mode == 0 then
        return get_gyro_rate_hz()
    else
        local loop_rate = get_loop_rate_hz()
        return loop_rate / mode  -- mode 1=loop, 2=loop/2, 3=loop/3
    end
end

--- Calculate bin resolution for a given sample mode
local function get_resolution_for_mode(mode)
    local sample_rate = get_sample_rate_for_mode(mode)
    local window_size = fft_window_size:get() or 64
    return sample_rate / window_size
end

--- Format bin resolution for display
local function format_resolution(res)
    if res >= 100 then
        return string.format("%.0fHz", res)
    elseif res >= 10 then
        return string.format("%.1fHz", res)
    else
        return string.format("%.2fHz", res)
    end
end

--- Build resolution options and values for current window size
-- Returns two tables: options (strings) and values (sample mode integers)
local function build_resolution_options()
    local options = {}
    local values = {}
    for mode = 0, 3 do
        local res = get_resolution_for_mode(mode)
        table.insert(options, format_resolution(res))
        table.insert(values, mode)
    end
    return options, values
end

-- Build resolution options at startup (based on current window size)
local RESOLUTION_OPTIONS, RESOLUTION_VALUES = build_resolution_options()

--- Get max frequency (Nyquist) for current sample mode
local function get_max_freq_for_mode(mode)
    local sample_rate = get_sample_rate_for_mode(mode)
    return sample_rate / 2
end

--- Format frequency range string for current sample mode
local function format_freq_range()
    local mode = fft_sample_mode:get() or 0
    local max_freq = get_max_freq_for_mode(mode)
    return string.format("0-%dHz", math.floor(max_freq))
end

--- Get 1-based index for Resolution menu based on current FFT_SAMPLE_MODE
local function get_default_resolution_idx()
    local mode = fft_sample_mode:get()
    for i, v in ipairs(RESOLUTION_VALUES) do
        if v == mode then
            return i
        end
    end
    return 1  -- Default to first option
end

--- Get 1-based index for Enable menu based on current FFT_VIS_MASK
local function get_default_enable_idx()
    local mask = fft_vis_mask:get()
    return (mask > 0) and 2 or 1  -- 1="Off", 2="On"
end

--- Get 1-based index for Axis menu based on current FFT_VIS_MASK
local function get_default_axis_idx()
    local mask = fft_vis_mask:get()
    if mask == 0 then
        return 7  -- Default to "All" when disabled
    end
    return MASK_TO_INDEX[mask] or 7
end

--- Get 1-based index for Window Size menu
local function get_default_window_idx()
    local size = fft_window_size:get()
    return WINDOW_TO_INDEX[size] or 2  -- Default to 64 if unknown
end

--- Get 1-based index for Averaging menu
local function get_default_averaging_idx()
    local frames = fft_num_frames:get()
    return AVG_TO_INDEX[frames] or 3  -- Default to "Medium" if unknown
end

--- Get 1-based index for Filter menu based on FFT_OPTIONS bit 0
local function get_default_filter_idx()
    local opts = fft_options:get() or 0
    if (opts & OPT_POST_FILTER) ~= 0 then
        return 2  -- Post-filter
    end
    return 1  -- Pre-filter
end

--- Update frequency range INFO item
local function update_freq_range_info()
    if not freq_range_item then return end
    freq_range_item.info = format_freq_range()
end

--- Find which RC channel (5-16) has a specific option value set
-- Returns channel number (5-16) or 0 if not found
local function find_channel_with_option(option_value)
    for ch = 5, 16 do
        local param = Parameter(string.format("RC%d_OPTION", ch))
        if param then
            local val = param:get()
            if val and val == option_value then
                return ch
            end
        end
    end
    return 0  -- Not assigned
end

--- Build list of available RC channels for an aux option
-- Returns options table, values table, and default index
-- Includes: "None", unassigned channels (RC_OPTION=0), and current assignment
local function build_available_channels(current_option_value)
    local options = {"None"}
    local values = {0}
    local default_idx = 1

    local current_ch = find_channel_with_option(current_option_value)

    for ch = 5, 16 do
        local param = Parameter(string.format("RC%d_OPTION", ch))
        if param then
            local val = param:get()
            -- Include if: unassigned (0) OR currently assigned to our option
            if val == 0 or ch == current_ch then
                table.insert(options, string.format("CH%d", ch))
                table.insert(values, ch)
                if ch == current_ch then
                    default_idx = #options
                end
            end
        end
    end

    return options, values, default_idx
end

--- Parse channel number from selection string ("None" or "CH5", "CH6", etc.)
local function parse_channel_selection(selection)
    if selection == "None" then
        return 0
    end
    local ch = tonumber(selection:match("CH(%d+)"))
    return ch or 0
end

--- Set RC channel option, clearing any previous assignment
local function set_channel_option(new_channel, option_value)
    -- First, clear any existing channel with this option
    local existing = find_channel_with_option(option_value)
    if existing > 0 and existing ~= new_channel then
        local param = Parameter(string.format("RC%d_OPTION", existing))
        if param then
            param:set_and_save(0)
        end
    end

    -- Set the new channel (if not "None")
    if new_channel > 0 then
        local param = Parameter(string.format("RC%d_OPTION", new_channel))
        if param then
            param:set_and_save(option_value)
        end
    end
end

--- Update status INFO item with current state info
local function update_status_info()
    if not status_item then return end

    if not is_fft_enabled() then
        status_item.info = "FFT Disabled"
    elseif pending_reboot then
        status_item.info = "Reboot needed!"
    else
        local mask = fft_vis_mask:get()
        if mask == 0 then
            status_item.info = "Vis: Off"
        else
            status_item.info = "Active"
        end
    end
end

-- ####################
-- # CALLBACKS
-- ####################

--- Enable/Disable callback - toggles FFT_VIS_MASK between 0 and saved value
local function on_enable_change(selection)
    if selection == "Off" then
        local current = fft_vis_mask:get()
        if current > 0 then
            saved_mask = current  -- Remember for restore
        end
        fft_vis_mask:set(0)
        gcs:send_text(MAV_SEVERITY.INFO, "FFT visualization disabled")
    else
        local restore = (saved_mask > 0) and saved_mask or 7
        fft_vis_mask:set(restore)
        gcs:send_text(MAV_SEVERITY.INFO, "FFT visualization enabled")
    end
    update_status_info()
end

--- Axis selection callback - sets FFT_VIS_MASK to selected axes
local function on_axis_change(selection)
    for i, opt in ipairs(AXIS_OPTIONS) do
        if opt == selection then
            fft_vis_mask:set(AXIS_VALUES[i])
            saved_mask = AXIS_VALUES[i]  -- Update saved for enable toggle

            -- Also ensure Enable shows "On" since we just set a non-zero mask
            if enable_item then
                enable_item.current_idx = 2
            end

            gcs:send_text(MAV_SEVERITY.INFO, "FFT axis: " .. selection)
            break
        end
    end
    update_status_info()
end

--- Window size callback - requires reboot
local function on_window_change(selection)
    for i, opt in ipairs(WINDOW_OPTIONS) do
        if opt == selection then
            fft_window_size:set_and_save(WINDOW_VALUES[i])
            pending_reboot = true
            update_status_info()
            gcs:send_text(MAV_SEVERITY.WARNING, "FFT window: " .. selection .. " - REBOOT")
            break
        end
    end
end

--- Resolution callback - sets FFT_SAMPLE_MODE, requires reboot
local function on_resolution_change(selection)
    for i, opt in ipairs(RESOLUTION_OPTIONS) do
        if opt == selection then
            fft_sample_mode:set_and_save(RESOLUTION_VALUES[i])
            pending_reboot = true
            update_freq_range_info()
            update_status_info()
            gcs:send_text(MAV_SEVERITY.WARNING, "FFT resolution: " .. selection .. " - REBOOT")
            break
        end
    end
end

--- Averaging callback - sets FFT_NUM_FRAMES, requires reboot
local function on_averaging_change(selection)
    for i, opt in ipairs(AVG_OPTIONS) do
        if opt == selection then
            fft_num_frames:set_and_save(AVG_VALUES[i])
            pending_reboot = true
            update_status_info()
            gcs:send_text(MAV_SEVERITY.WARNING, "FFT averaging: " .. selection .. " - REBOOT")
            break
        end
    end
end

--- Filter callback - sets FFT_OPTIONS bit 0, requires reboot
local function on_filter_change(selection)
    local opts = fft_options:get() or 0
    if selection == "Post-filter" then
        opts = opts | OPT_POST_FILTER  -- Set bit 0
    else
        opts = opts & (~OPT_POST_FILTER)  -- Clear bit 0
    end
    fft_options:set_and_save(opts)
    pending_reboot = true
    update_status_info()
    gcs:send_text(MAV_SEVERITY.WARNING, "FFT filter: " .. selection .. " - REBOOT")
end

--- Pan channel callback - assigns RC channel to FFT_VIS_PAN aux function
local function on_pan_channel_change(selection)
    local ch = parse_channel_selection(selection)
    set_channel_option(ch, RC_OPTION_FFT_VIS_PAN)
    if ch > 0 then
        gcs:send_text(MAV_SEVERITY.INFO, "FFT pan: " .. selection)
    else
        gcs:send_text(MAV_SEVERITY.INFO, "FFT pan: disabled")
    end
end

--- Zoom channel callback - assigns RC channel to FFT_VIS_ZOOM aux function
local function on_zoom_channel_change(selection)
    local ch = parse_channel_selection(selection)
    set_channel_option(ch, RC_OPTION_FFT_VIS_ZOOM)
    if ch > 0 then
        gcs:send_text(MAV_SEVERITY.INFO, "FFT zoom: " .. selection)
    else
        gcs:send_text(MAV_SEVERITY.INFO, "FFT zoom: disabled")
    end
end

--- Reboot command callback
local function on_reboot_command(command_action)
    if command_action == CRSF_COMMAND_STATUS.START then
        if pending_reboot then
            -- Schedule reboot with delay to allow CRSF response to be sent
            gcs:send_text(MAV_SEVERITY.WARNING, "FFT: Rebooting")
            reboot_time_ms = millis():tofloat() + REBOOT_DELAY_MS
            return CRSF_COMMAND_STATUS.READY, "Rebooting"
        else
            return CRSF_COMMAND_STATUS.READY, "No changes"
        end
    end
    return CRSF_COMMAND_STATUS.READY, pending_reboot and "Reboot" or "No changes"
end

-- ####################
-- # MENU DEFINITION
-- ####################

enable_item = {
    type = 'SELECTION',
    name = "Enable",
    options = {"Off", "On"},
    default = get_default_enable_idx(),
    callback = on_enable_change
}

axis_item = {
    type = 'SELECTION',
    name = "Axis",
    options = AXIS_OPTIONS,
    default = get_default_axis_idx(),
    callback = on_axis_change
}

window_item = {
    type = 'SELECTION',
    name = "Window Size",
    options = WINDOW_OPTIONS,
    default = get_default_window_idx(),
    callback = on_window_change
}

resolution_item = {
    type = 'SELECTION',
    name = "Resolution",
    options = RESOLUTION_OPTIONS,
    default = get_default_resolution_idx(),
    callback = on_resolution_change
}

averaging_item = {
    type = 'SELECTION',
    name = "Averaging",
    options = AVG_OPTIONS,
    default = get_default_averaging_idx(),
    callback = on_averaging_change
}

filter_item = {
    type = 'SELECTION',
    name = "Sample Point",
    options = FILTER_OPTIONS,
    default = get_default_filter_idx(),
    callback = on_filter_change
}

-- Build available channel lists (only unassigned channels + current assignment)
local pan_options, _, pan_default = build_available_channels(RC_OPTION_FFT_VIS_PAN)
local zoom_options, _, zoom_default = build_available_channels(RC_OPTION_FFT_VIS_ZOOM)

pan_channel_item = {
    type = 'SELECTION',
    name = "Pan Channel",
    options = pan_options,
    default = pan_default,
    callback = on_pan_channel_change
}

zoom_channel_item = {
    type = 'SELECTION',
    name = "Zoom Channel",
    options = zoom_options,
    default = zoom_default,
    callback = on_zoom_channel_change
}

freq_range_item = {
    type = 'INFO',
    name = "Freq Range",
    info = format_freq_range()
}

-- Initialize status info text based on current parameter state
local function get_initial_status()
    if not is_fft_enabled() then
        return "FFT Disabled"
    end
    local mask = fft_vis_mask:get()
    if mask == 0 then
        return "Vis: Off"
    end
    return "Active"
end

status_item = {
    type = 'INFO',
    name = "Status",
    info = get_initial_status()
}

local menu_definition = {
    name = "Noise Spectrum",
    items = {
        enable_item,
        axis_item,
        window_item,
        resolution_item,
        averaging_item,
        filter_item,
        pan_channel_item,
        zoom_channel_item,
        freq_range_item,
        status_item,
        {
            type = 'COMMAND',
            name = "Reboot FC",
            info = "No changes",
            callback = on_reboot_command
        }
    }
}

-- ####################
-- # REGISTRATION
-- ####################

-- Initialize saved_mask from current parameter value
local current_mask = fft_vis_mask:get()
if current_mask > 0 then
    saved_mask = current_mask
end

-- Get the CRSF event handler from crsf_helper
local crsf_event_handler, crsf_delay = crsf_helper.register_menu(menu_definition)
if not crsf_event_handler then
    gcs:send_text(MAV_SEVERITY.ERROR, "FFT CRSF menu init failed")
    return
end

--- Main loop wrapper that handles scheduled reboot before CRSF events
local function main_loop()
    -- Check for scheduled reboot (must happen before CRSF event handling)
    if reboot_time_ms and millis():tofloat() >= reboot_time_ms then
        reboot_time_ms = nil
        vehicle:reboot(false)
        return  -- FC is rebooting, won't return
    end

    -- Delegate to CRSF event handler
    local next_fn, next_delay = crsf_event_handler()
    if next_fn then
        crsf_event_handler = next_fn
    end

    -- Return our wrapper with CRSF's timing
    return main_loop, next_delay or 100
end

gcs:send_text(MAV_SEVERITY.INFO, "FFT CRSF menu loaded")
return main_loop, crsf_delay

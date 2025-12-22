-- Luacheck configuration for ArduPilot Lua scripts
-- These globals are provided by the ArduPilot scripting environment

std = "lua53"

-- ArduPilot runtime globals
globals = {
    "Parameter",
    "gcs",
    "hal",
    "periph",
    "arming",
    "ahrs",
    "vehicle",
    "rc",
    "param",
    "mission",
    "terrain",
    "relay",
    "servo",
    "SRV_Channels",
    "battery",
    "gps",
    "notify",
    "logger",
    "i2c",
    "efi",
    "CAN",
    "motors",
    "FWVersion",
    "millis",
    "micros",
    "location",
    "Location",
    "crsf",
}

-- Read-only globals
read_globals = {
    "math",
    "string",
    "table",
    "tonumber",
    "tostring",
    "type",
    "pairs",
    "ipairs",
    "assert",
    "error",
    "pcall",
    "require",
    "select",
    "unpack",
}

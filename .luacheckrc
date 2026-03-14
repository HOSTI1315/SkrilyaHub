-- Luacheck configuration for Roblox Lua scripts
std = "lua51"
max_line_length = false

globals = {
    "game",
    "workspace",
    "script",
    "task",
    "warn",
    "typeof",
    "getgenv",
    "setclipboard",
    "setfpscap",
    "getrawmetatable",
    "setreadonly",
    "hookmetamethod",
    "checkcaller",
    "newcclosure",
    "iscclosure",
    "firetouchinterest",
    "fireproximityprompt",
    "fireclickdetector",
    "gethui",
    "cloneref",
    "loadstring",
    "syn",
    "fluxus",
    "http_request",
    "request",
    "http",
    "queue_on_teleport",
    "identifyexecutor",
}

read_globals = {
    "Enum",
    "Instance",
    "Vector3",
    "Vector2",
    "CFrame",
    "Color3",
    "BrickColor",
    "UDim2",
    "UDim",
    "Rect",
    "Region3",
    "TweenInfo",
    "NumberRange",
    "NumberSequence",
    "NumberSequenceKeypoint",
    "ColorSequence",
    "ColorSequenceKeypoint",
    "PhysicalProperties",
    "Ray",
    "Random",
    "tick",
    "time",
    "wait",
    "spawn",
    "delay",
    "bit32",
    "utf8",
    "os",
    "debug",
    "Drawing",
    "RaycastParams",
    "OverlapParams",
}

ignore = {
    "211",  -- unused variable
    "212",  -- unused argument
    "213",  -- unused loop variable
    "311",  -- value assigned to variable is unused
    "411",  -- variable was previously defined
    "412",  -- variable was previously defined as argument
    "421",  -- shadowing definition
    "431",  -- shadowing upvalue
    "432",  -- shadowing upvalue argument
    "542",  -- empty if branch
}

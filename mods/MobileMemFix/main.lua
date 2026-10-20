-- Mobile Memory Fix
--
-- 1. Steamodded keeps `atlas.image_data` (a full uncompressed RGBA copy of every
--    sprite sheet) alive after creating the GPU texture. Nothing reads it later.
--    Release it right after the texture is built.
-- 2. On phones GPU textures live in the same RAM. A mod whose 2x art is huge
--    (Pokermon: ~2.4 GB decoded, ~3 GB with mipmaps) gets the game OOM-killed
--    on an 8 GB phone, so such mods load their 1x art instead (same on-screen
--    size, because the engine works in DPI-scaled points). Vanilla and small
--    mods keep 2x.

local IS_MOBILE = love.system.getOS() == 'Android' or love.system.getOS() == 'iOS'
-- Per-mod budget for decoded 2x art before that mod drops to 1x.
local PER_MOD_2X_BUDGET = 256 * 1048576

local freed_bytes, freed_count = 0, 0
local lowres_mods, mod_2x_bytes = {}, {}

local function png_bytes(path)
    local head = NFS.read(path, 24)
    if not head or #head < 24 or head:sub(2, 4) ~= 'PNG' then return 0 end
    local function u32(i)
        local a, b, c, d = head:byte(i, i + 3)
        return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return u32(17) * u32(21) * 4
end

local function dir_png_bytes(dir)
    local total = 0
    for _, name in ipairs(NFS.getDirectoryItems(dir) or {}) do
        local p = dir .. '/' .. name
        local info = NFS.getInfo(p)
        if info and info.type == 'directory' then
            total = total + dir_png_bytes(p)
        elseif name:lower():match('%.png$') then
            total = total + png_bytes(p)
        end
    end
    return total
end

local function use_lowres(mod)
    if not IS_MOBILE or not mod or not mod.path then return false end
    if mod_2x_bytes[mod.id] == nil then
        local has_1x = NFS.getInfo(mod.path .. 'assets/1x')
        mod_2x_bytes[mod.id] = has_1x and dir_png_bytes(mod.path .. 'assets/2x') or 0
        if mod_2x_bytes[mod.id] > PER_MOD_2X_BUDGET then
            lowres_mods[#lowres_mods + 1] = ('%s (%.0f MB at 2x)'):format(mod.id, mod_2x_bytes[mod.id] / 1048576)
        end
    end
    return mod_2x_bytes[mod.id] > PER_MOD_2X_BUDGET
end

local atlas_inject_ref = SMODS.Atlas.inject
SMODS.Atlas.inject = function(self, ...)
    local scaling = G.SETTINGS.GRAPHICS.texture_scaling
    local lowres = scaling == 2 and use_lowres(self.mod)
    if lowres then G.SETTINGS.GRAPHICS.texture_scaling = 1 end
    local ok, ret = pcall(atlas_inject_ref, self, ...)
    G.SETTINGS.GRAPHICS.texture_scaling = scaling
    if not ok then error(ret, 0) end
    if lowres and self.image then
        -- 1x art is drawn upscaled: keep pixels crisp when magnified
        self.image:setFilter('linear', 'nearest')
    end
    local data = rawget(self, 'image_data')
    if data and self.image then
        freed_bytes = freed_bytes + data:getWidth() * data:getHeight() * 4
        freed_count = freed_count + 1
        data:release()
        self.image_data = nil
    end
    return ret
end

local inject_items_ref = SMODS.injectItems
function SMODS.injectItems(...)
    local ret = inject_items_ref(...)
    collectgarbage('collect')
    sendInfoMessage(('Released %d atlas image copies (%.0f MB)'):format(freed_count, freed_bytes / 1048576),
        'MobileMemFix')
    if #lowres_mods > 0 then
        sendInfoMessage('Using 1x art for: ' .. table.concat(lowres_mods, ', '), 'MobileMemFix')
    end
    return ret
end

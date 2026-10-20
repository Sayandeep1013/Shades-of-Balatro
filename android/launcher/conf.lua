-- Shades of Balatro launcher. Contains no Balatro code and ships no main.lua.
--
-- The player puts their own Balatro.exe (from Steam) in this app's save folder, either with
-- `shades phone` over adb or with a file manager. Balatro.exe is a LÖVE game with a zip appended,
-- so it can be mounted like any archive. Mounting it here, in conf.lua, makes its main.lua the
-- only one LÖVE finds, so the game boots exactly as it would on its own and Lovely patches it the
-- same way. (A launcher main.lua would itself be patched as if it were the game's.)

_RELEASE_MODE = true
_DEMO = false

local GAME = "Balatro.exe"
local IDENTITY = "ASET" -- the save folder Lovely Mobile Maker's Android builds use for saves and Mods

local function show_help(title, body)
	local font
	function love.load()
		font = love.graphics.newFont(math.max(14, math.floor(love.graphics.getHeight() / 32)))
	end
	function love.draw()
		love.graphics.clear(0.13, 0.17, 0.19)
		love.graphics.setFont(font)
		local w = love.graphics.getWidth() * 0.86
		local x = (love.graphics.getWidth() - w) / 2
		love.graphics.setColor(0.99, 0.3, 0.29)
		love.graphics.printf(title, x, love.graphics.getHeight() * 0.18, w, "center")
		love.graphics.setColor(1, 1, 1)
		love.graphics.printf(body, x, love.graphics.getHeight() * 0.32, w, "center")
	end
	function love.touchpressed() love.event.quit() end
	function love.keypressed() love.event.quit() end
end

local function mount_game()
	love.filesystem.setIdentity(IDENTITY, true)
	if not love.filesystem.getInfo(GAME, "file") then
		show_help("Balatro.exe needed",
			"This app runs your own copy of Balatro and doesn't include the game.\n\n"
			.. "Connect the phone to your PC and run:   shades phone\n"
			.. "or copy Balatro.exe from your Steam folder into this app's folder "
			.. "(Material Files: Add storage > External storage > this app), then reopen.\n\n"
			.. "Tap to close.")
		return
	end
	if not love.filesystem.mount(GAME, "", false) then
		show_help("Couldn't open Balatro.exe",
			"The file is there but isn't a readable Balatro build. Copy it again from "
			.. "Steam\\steamapps\\common\\Balatro\\Balatro.exe and reopen.\n\nTap to close.")
	end
end

function love.conf(t)
	mount_game()
	t.identity = IDENTITY
	t.console = false
	t.title = "Balatro"
	t.window.width = 0
	t.window.height = 0
	t.window.minwidth = 100
	t.window.minheight = 100
end


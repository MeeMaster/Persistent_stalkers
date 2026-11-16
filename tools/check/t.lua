-- Fake engine for PS_v2: the main menu with its panel, and the arrival.
local ROOT_V2, ROOT_MC = ...
local fails, checks = 0, 0
local function check(cond, what)
	checks = checks + 1
	if not cond then
		fails = fails + 1
		print("FAIL: " .. what)
	else
		print("ok:   " .. what)
	end
end

local LOG = {}
function printf(fmt, ...)
	local ok, s = pcall(string.format, fmt, ...)
	s = ok and s or fmt
	LOG[#LOG + 1] = s
	if s:find("!") then print("   LOG " .. s) end
end
function log(s) LOG[#LOG + 1] = tostring(s) end
local function logged(pat)
	for _, l in ipairs(LOG) do
		if l:find(pat) then return true end
	end
	return false
end

-- files in memory
local FILES = {}
io = io or {}
io.open = function(path, mode)
	if mode:find("r") then
		local text = FILES[path]
		if not text then return nil end
		return { read = function() return text end, close = function() end }
	end
	local buf = {}
	return { write = function(_, s) buf[#buf + 1] = s; return true end, close = function() FILES[path] = table.concat(buf) end }
end
function getFS() return {
	update_path = function(_, _, f) return "app/" .. f end,
	exist = function(_, alias, f) return alias == "$game_spawn$" and f == "ps_lobby.spawn" and SPAWN_PRESENT or nil end,
	-- the save list (the lobby's Last save): newest first
	file_list_open_ex = function()
		return {
			Size = function() return #SAVES end,
			Sort = function() end,
			GetAt = function(_, i) local n = SAVES[i + 1]; return { NameFull = function() return n .. ".scop" end } end,
		}
	end,
} end

-- modules: each script is its own namespace over _G
local current
local function load_script(root, name)
	local text = assert(read_source(root .. name .. ".script")):gsub(string.char(13), "")
	local env = setmetatable({}, { __index = _G })
	_G[name] = env
	current = env
	local chunk = assert(load(text, "@" .. name, "t", env))
	chunk()
	current = nil
	return env
end

-- windows: any method starting with a capital exists
local function wnd(node)
	local w = { node = node, shown = true, x = 10, y = 10, w = 200, h = 400, text = "" }
	local own = {
		GetWndPos = function(s) return { x = s.x, y = s.y } end,
		SetWndPos = function(s, v) s.x, s.y = v.x, v.y end,
		SetWndSize = function(s, v) s.w, s.h = v.x, v.y end,
		GetWidth = function(s) return s.w end,
		GetHeight = function(s) return s.h end,
		SetText = function(s, t) s.text = t end,
		GetText = function(s) return s.text end,
		Show = function(s, v) s.shown = v end,
		IsShown = function(s) return s.shown end,
		ShowDialog = function(s) s.shown = true end,
		HideDialog = function(s) s.shown = false end,
		IsCursorOverWindow = function() return false end,
		GetTextureRect = function() return { x1 = 0, y1 = 0, x2 = 100, y2 = 200 } end,
		TextControl = function(s) s.tc = s.tc or wnd("text"); return s.tc end,
		SetCheck = function(s, v) s.check = v end,
		AllowMovement = function(s, v) s.moves = v end,
		Register = function(s, c, n) s.reg = s.reg or {}; s.reg[n] = c end,
		AddCallback = function(s, n, ev, fn, o) s.cb = s.cb or {}; s.cb[n .. ":" .. tostring(ev)] = { fn, o } end,
	}
	return setmetatable(w, { __index = function(t, k)
		if own[k] then return own[k] end
		if type(k) == "string" and k:match("^%u") then
			return function() return wnd(k) end
		end
		return nil
	end })
end
local function click(w, name)
	local cb = w.cb[name .. ":" .. tostring(ui_events.BUTTON_CLICKED)]
	assert(cb, "no callback " .. name)
	cb[1](cb[2])
end

CUIScriptWnd = wnd("CUIScriptWnd")
CUIScriptWnd.OnKeyboard = function() return false end
CUIScriptWnd.Update = function() end
function class(name)
	local cls = {}
	local env = current
	local base
	env[name] = setmetatable(cls, { __call = function(c, ...)
		local o = base and wnd(name) or {}
		local mt = getmetatable(o) or {}
		local old = mt.__index
		mt.__index = function(t, k)
			local v = rawget(cls, k)
			if v ~= nil then return v end
			if old then return old(t, k) end
		end
		setmetatable(o, mt)
		super = function() end
		cls.__init(o, ...)
		return o
	end })
	return function(b) base = b end
end

local XML_NODES = {}
XML_FROM = {} -- node -> the file it was made from
function CScriptXmlInit()
	local x = {}
	return setmetatable(x, { __index = function(t, k)
		if k == "ParseFile" then return function(_, f) x.file = f end end
		return function(_, node, parent)
			local w = wnd(node)
			XML_NODES[node] = w
			XML_FROM[node] = x.file
			if node == "menu:equip" then w.w, w.h = 240, 500 end
			if node == "menu:bag" then w.x, w.w, w.h = 464, 280, 480 end
			if node == "menu:row" then w.w, w.h = 184, 26 end
			return w
		end
	end })
end
function CUIMessageBoxEx() return wnd("msgbox") end

-- engine
local NOW = 0
function time_global() return NOW end
local PRESENT = false
LEVEL_NAME = "l01_escape"
DIRS = {}
CAM = {} -- what the lobby did to the camera, input and HUD
level = {
	present = function() return PRESENT end,
	game_id = function() return 1 end,
	name = function() return LEVEL_NAME end,
	object_by_id = function(id) return OBJECTS and OBJECTS[id] end,
	set_cam_custom_position_direction = function(pos, hp) CAM.pos, CAM.hp = pos, hp end,
	remove_cam_custom_position_direction = function() CAM.pos = nil end,
	set_active_cam = function(m) CAM.mode = m end,
	get_active_cam = function() return CAM.mode or 0 end,
	disable_input = function() CAM.input = false end,
	enable_input = function() CAM.input = true end,
	hide_indicators_safe = function() CAM.hud = false end,
	show_indicators = function() CAM.hud = true end,
}
function vector()
	local v = { x = 0, y = 0, z = 0 }
	v.set = function(s, x, y, z) s.x, s.y, s.z = x, y, z; return s end
	v.getH = function(s) return -math.atan(s.x, s.z) end
	v.getP = function(s) return math.atan(s.y, math.sqrt(s.x * s.x + s.z * s.z)) end
	v.setHP = function(s, h, p) s.x, s.y, s.z = -math.sin(h), 0, math.cos(h); return s end
	return v
end
db = {}
game = { translate_string = function(s) return s end }
function GetARGB(a, r, g, b) return a end
function vector2() local v = {}; v.set = function(s, x, y) s.x, s.y = x, y; return s end; return v end
function Frect() local v = {}; v.set = function(s, a, b, c, d) s.x1, s.y1, s.x2, s.y2 = a, b, c, d; return s end; return v end
ui_events = setmetatable({}, { __index = function(_, k) return k end })
DIK_keys = setmetatable({}, { __index = function(_, k) return k end })
key_bindings = {}
function dik_to_bind() return nil end
function device() return { time_continual = function() return 1 end, pause = function() end } end
function alife() return nil end
CMDS = {}
function exec_console_cmd(c) CMDS[#CMDS + 1] = c; local v = c:match("^keypress_on_start (%d)$"); if v then KEYPRESS = v == "1" end end
KEYPRESS = true
function get_console_cmd(kind, name) if name == "keypress_on_start" then return KEYPRESS end end
xrs_debug_tools = { on_game_start = function() end }
local CB = {}
function RegisterScriptCallback(n, f) CB[n] = CB[n] or {}; table.insert(CB[n], f) end
function UnregisterScriptCallback() end
function SendScriptCallback(n, ...) for _, f in ipairs(CB[n] or {}) do if type(f) == "function" then f(...) end end end
local function fire(n, ...)
	if n == "actor_on_update" and MC_PENDING and #MC_PENDING > 0 then
		local p = MC_PENDING
		MC_PENDING = {}
		for _, f in ipairs(p) do f() end
	end
	for _, f in ipairs(CB[n] or {}) do if type(f) == "function" then f(...) end end
end
-- the old dropdown's "off" is left in the options: it must be ignored now
local MCM = { ["persistent_stalkers/mode"] = "off" }
ui_mcm = { get = function(k) return MCM[k] end, init_opt_base = function() end, UI_MCM = function() return wnd("mcm") end }
-- the main menu's dialogs (the lobby opens them through the main menu's methods)
ui_load_dialog = { UILoadDialog = function() return wnd("load") end }
UI_OPTS = { ["video/player/animations"] = true }
ui_options = { UIOptions = function() return wnd("options") end,
	get = function(k) return UI_OPTS[k] end, set = function(k, v) UI_OPTS[k] = v end }
ui_mm_faction_select = { UINewGame = function(owner) local w = wnd("new_game"); w.owner = owner; return w end }
-- items in the world (the lobby's wardrobe): Master Core's create comes back
-- on the next update, as items come online a frame later
OBJECTS, INV, SLOTS, RELEASED, MC_PENDING, LOWERED = {}, {}, {}, 0, {}, false
local next_id = 1000
master_core_items = { create = function(rec, where, opts)
	next_id = next_id + 1
	local id = next_id
	local obj = { section = rec.section }
	obj.id = function() return id end
	obj.section_name = function() return rec.section end
	OBJECTS[id] = obj
	INV[id] = true
	MC_PENDING[#MC_PENDING + 1] = function() if opts.done then opts.done(id, true) end end
	return { id = id }
end }
function alife_release_id(id) OBJECTS[id] = nil; if NPCS then NPCS[id] = nil end; INV[id] = nil; RELEASED = RELEASED + 1; for s, o in pairs(SLOTS) do if o == id then SLOTS[s] = nil end end; return true end
-- NPCs (the lobby's stand-ins): alife_create at a position, online at once
NPCS = {}
look = { direction = "direction" }
function alife_create(section, pos, lvid, gvid)
	next_id = next_id + 1
	local id = next_id
	local o = { section = section, pos = { x = pos.x, y = pos.y, z = pos.z } }
	o.id = function() return id end
	o.position = function(s) return s.pos end
	o.set_npc_position = function(s, v) s.pos = { x = v.x, y = v.y, z = v.z } end
	o.set_sight = function(s, kind, d) s.sight = { kind = kind, x = d.x, z = d.z } end
	OBJECTS[id] = o
	NPCS[id] = o
	return { id = id }
end
game.actor_weapon_lowered = function() return LOWERED end
game.actor_lower_weapon = function(v) LOWERED = v end
SAVES = { "mysave" }
FS = { FS_ListFiles = 1, FS_RootOnly = 2, FS_sort_by_modif_down = 3 }
function bit_or(a, b) return a + b end
CLEARED = {}
SETCFG = {}
axr_main = { config = { r_value = function() return nil end, w_value = function(_, sec, k, v) if v == nil then CLEARED[k] = true; SETCFG[k] = nil else SETCFG[k] = v; CLEARED[k] = nil end end, save = function() end } }
main_menu = { get_main_menu = function() return {} end }
local SECS = { wpn_ak = { inv_grid_width = 5, inv_grid_height = 2 }, bread = {}, outfit = { inv_grid_width = 2, inv_grid_height = 3, artefact_count = 2 } }
ini_sys = {
	section_exist = function(_, s) return SECS[s] ~= nil end,
	r_float_ex = function(_, s, k) return SECS[s] and SECS[s][k] end,
	r_string_ex = function() return nil end,
	r_bool_ex = function(_, s, k, d) return d end,
}
utils_xml = { screen_ratio = function() return 0.75 end }
utils_ui = { UIInfoItem = function() return { Update = function() end, Show = function() end } end }
news_manager = { send_tip = function() end }
local HOST = true
XrrNet = nil

-- Master Core: the real text and profiles; net and world faked
load_script(ROOT_MC, "master_core_text")
load_script(ROOT_MC, "master_core_profiles")
master_core = { need = function() end }
local SENT = {}
master_core_net = {
	session = function() return nil end,
	is_host = function() return HOST end,
	nick = function() return "Mee" end,
	peers = function() return {} end,
	send_table = function(n, target, t) SENT[#SENT + 1] = n end,
	register = function(n, f) CB["net_" .. n] = { f } end,
}
master_core_world = { death_busy = function() return false end, death_rule = function() return nil end, KEEP_SLOTS = { 5, 8, 10 } }

-- the mod: the state module faked
local ACTOR = { money = 100, items = { { section = "bread" } } }
local APPLIED = {}
persistent_stalkers_state = {
	read = function() return master_core_text.decode(master_core_text.encode(ACTOR)) end,
	apply = function(c, parts, done)
		APPLIED[#APPLIED + 1] = c
		ACTOR = master_core_text.decode(master_core_text.encode(c))
		done({ missing = 0, refused = 0, misplaced = 0 })
		return true
	end,
	busy = function() return false end,
	update = function() end,
	cancel = function() end,
	summary = function(c) return c and (tostring(#(c.items or {})) .. " items") or "nothing" end,
}
load_script(ROOT_V2, "persistent_stalkers_skin")
local P = load_script(ROOT_V2, "persistent_stalkers_profile")
local C = load_script(ROOT_V2, "persistent_stalkers")
local M = load_script(ROOT_V2, "persistent_stalkers_menu")
local MCMP = load_script(ROOT_V2, "persistent_stalkers_mcm")
local MM = load_script(ROOT_V2, "ui_main_menu")

local function text_of(node) return XML_NODES[node] and XML_NODES[node].text or "" end
local function restart()
	-- a new Lua state for the profile module, as after a game restart
	P = load_script(ROOT_V2, "persistent_stalkers_profile")
end

------------------------------------------------------------------ 1. main menu
print("-- 1. the main menu")
local t = MCMP.on_mcm_load()
check(type(t) == "table" and #t.gr > 10, "the MCM page builds")
for _, e in ipairs(t.gr) do
	check(not (e.id or ""):find("profile") and e.id ~= "status" and e.id ~= "create" and e.id ~= "remove" and e.id ~= "new_name", "no profile control in MCM: " .. tostring(e.id))
end
for _, e in ipairs(t.gr) do
	check(e.id ~= "menu_key" and e.id ~= "open_menu" and e.id ~= "pause_menu" and e.id ~= "active", "no menu option " .. tostring(e.id))
	if e.id == "menu_key" then break end
end
local last = t.gr[#t.gr]
check(last.id == "constant_saves" and last.type == "check" and last.def == false, "constant saves: a checkbox, last, off by default")
for _, e in ipairs(t.gr) do
	check(e.id ~= "mode", "no mode dropdown: " .. tostring(e.id))
end
local mm = MM.main_menu()
check(mm.pst_panel ~= nil, "the panel is attached")
check(XML_NODES["options"] ~= nil, "the options were moved")
check(XML_FROM["background"] == "ui_persistent_stalkers.xml", "default skin: our background")
check(mm.pst_panel.skin.name == "default" and mm.pst_panel.bag ~= nil and mm.pst_panel.what ~= nil, "default skin: the full panel")
check(not logged("could not be"), "no build errors")
local panel = mm.pst_panel
check(#panel.entries == 2 and panel.entries[1] == "none" and panel.entries[2] == "default", "rows: None, default")
check(panel.chosen == "default", "default is selected first")
check(panel.row_texts[2].text:find("empty"), "default is shown empty: " .. panel.row_texts[2].text)
check(text_of("menu:what"):find("is empty"), "what: " .. text_of("menu:what"))
mm:Update()
check(mm.pst_panel ~= nil, "Update keeps the panel")

click(mm, "pst_row_1")
check(P.selected_profile() == "none" and FILES["app/persistent_stalkers_selected.txt"]:find("none"), "a click on None selects it, remembered")
check(text_of("menu:what"):find("No profile"), "what for None")
click(mm, "pst_btn_new")
local dlg = mm.pst_new_dlg
check(dlg and dlg:IsShown(), "New profile opens its box")
dlg.name.text = "bad name!"
dlg:OnCreate()
check(dlg:IsShown() and dlg.hint.text:find("letters"), "a bad name is refused: " .. dlg.hint.text)
dlg.name.text = "alt"
dlg:OnKeyboard("DIK_RETURN", "WINDOW_KEY_PRESSED")
check(not dlg:IsShown() and P.selected_profile() == "alt" and panel.chosen == "alt", "Enter creates alt and selects it")
check(#panel.entries == 3, "three rows now")
check(panel.btn_remove.shown == true, "Remove shown for alt")
-- remove alt: a warning box, then default is selected and a backup kept
FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 3, character = { money = 7, items = {} } })
click(mm, "pst_btn_remove")
local rdlg = mm.pst_remove_dlg
check(rdlg and rdlg:IsShown() and rdlg.name == "alt", "Remove opens the warning")
check(rdlg.text.text:find("create a new profile") and rdlg.text.text:find("backup"), "the warning says how to get it back: " .. rdlg.text.text)
rdlg:OnKeyboard("DIK_RETURN", "WINDOW_KEY_PRESSED")
check(rdlg:IsShown() and P.has_profile("alt"), "Enter does not remove")
rdlg:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED")
check(not rdlg:IsShown() and P.has_profile("alt"), "Esc cancels")
click(mm, "pst_btn_remove")
rdlg = mm.pst_remove_dlg
click(rdlg, "btn_remove")
check(not rdlg:IsShown() and not P.has_profile("alt") and P.selected_profile() == "default" and panel.chosen == "default", "Remove removes alt, default selected")
local bak
for k, v in pairs(FILES) do if k:find("profile_alt%.removed%-") and v:find("money") then bak = k end end
check(bak, "a backup of alt is kept")
check(#panel.entries == 2 and panel.btn_remove.shown == false, "two rows, no Remove for default")
click(mm, "pst_row_1")
check(panel.btn_remove.shown == false, "no Remove for None")
-- alt again, empty: it adopts like any new profile
click(mm, "pst_btn_new")
dlg = mm.pst_new_dlg
dlg.name.text = "alt"
dlg:OnCreate()
check(P.selected_profile() == "alt" and not P.info("alt").character, "alt created again, empty")
click(mm, "pst_row_2")
check(P.selected_profile() == "default", "a click on default selects it")
restart()
check(P.selected_profile() == "default", "the selection survives a restart")

------------------------------------------------------------------ 2. a new game
print("-- 2. save mode, a new game with an empty profile: adopt")
local function start_game(m_data)
	PRESENT = true
	ACTOR_POS = { x = 10, y = 0, z = 20 }
	db.actor = {
		alive = function() return true end,
		position = function() return ACTOR_POS end,
		direction = function() return { x = 0, y = 0, z = 1 } end,
		level_vertex_id = function() return 1 end,
		game_vertex_id = function() return 1 end,
		set_actor_position = function(_, v) ACTOR_POS = { x = v.x, y = v.y, z = v.z } end,
		iterate_inventory = function(_, fn, a) for id in pairs(INV) do fn(a, OBJECTS[id]) end end,
		item_in_slot = function(_, s) return SLOTS[s] and OBJECTS[SLOTS[s]] end,
		move_to_slot = function(_, o, s) for k, v in pairs(SLOTS) do if v == o:id() then SLOTS[k] = nil end end; SLOTS[s] = o:id() end,
		move_to_ruck = function(_, o) for k, v in pairs(SLOTS) do if v == o:id() then SLOTS[k] = nil end end end,
		activate_slot = function(_, s) if DROP_DRAWS and DROP_DRAWS > 0 then DROP_DRAWS = DROP_DRAWS - 1 else ACTIVE_SLOT = s end end,
		set_actor_direction = function(_, h) ACTOR_DIR = h; DIRS[#DIRS + 1] = { h = h, mode = CAM.mode } end,
		active_slot = function() return ACTIVE_SLOT end,
	}
	C.on_game_start()
	M.on_game_start()
	if LOBBY then LOBBY.on_game_start() end
	fire("load_state", m_data or {})
	fire("actor_on_first_update")
	for i = 1, 40 do NOW = NOW + 100; fire("actor_on_update") end
end
local function end_game()
	fire("actor_on_net_destroy")
	CB = {}
	PRESENT = false
	db.actor = nil
	C = load_script(ROOT_V2, "persistent_stalkers")
	restart()
end
start_game()
check(C.get_phase() == "live", "live after the settle, no question")
check(P.character() and P.character().money == 100, "the empty profile took the character")
local save = {}
fire("save_state", save)
check(save.persistent_stalkers.profile == "default", "the save is recorded as default")
-- the pause menu
mm = MM.main_menu()
panel = mm.pst_panel
check(panel and #panel.entries == 1 and panel.entries[1] == "default", "pause menu: only the profile in use")
click(mm, "pst_row_1")
check(P.current_profile() == "default", "pause menu: a click changes nothing")
check(panel.btn_new.shown == false, "pause menu: no New profile")
check(text_of("menu:what"):find("quit to the main menu"), "pause menu: " .. text_of("menu:what"))
check(text_of("menu:details"):find("Money: 100"), "pause menu shows the stored character")

print("-- 3. reload that save: the character follows it")
ACTOR.money = 250
end_game()
start_game(save)
check(C.get_phase() == "live" and #APPLIED == 0, "nothing applied")
check(logged("the character follows it"), "logged")
fire("save_state", save)
check(P.character().money == 250, "written at the save")

print("-- 4. alt (empty) selected at the main menu, the same save: a copy")
end_game()
mm = MM.main_menu()
check(mm.pst_panel.chosen == "default", "the main menu shows default")
click(mm, "pst_row_3")
check(P.selected_profile() == "alt", "alt selected")
start_game(save)
check(C.get_phase() == "live" and #APPLIED == 0 and P.current_profile() == "alt", "alt is live, nothing applied")
check(P.character() and P.character().money == 250, "alt took a copy of the save's character")
local save_alt = {}
ACTOR.money = 900
ACTOR.items = { { section = "wpn_ak", slot = 3, cond = 0.5, upgrades = {} }, { section = "outfit", slot = 7 }, { section = "bread" }, { section = "bread" }, { section = "gone" }, { section = "bread", belt = 0 } }
fire("save_state", save_alt)
check(save_alt.persistent_stalkers.profile == "alt" and P.character().money == 900, "alt's save")

print("-- 5. default selected, alt's save: default's file is applied")
end_game()
mm = MM.main_menu()
check(mm.pst_panel.chosen == "alt", "the main menu shows alt")
check(not logged("loadout failed"), "the loadout draws")
check(#mm.pst_panel.cells == 4, "icons: rifle, outfit, belt, a stack of bread (" .. #mm.pst_panel.cells .. ")")
click(mm, "pst_row_2")
start_game(save_alt)
check(#APPLIED == 1 and APPLIED[1].money == 250 and C.get_phase() == "live", "default applied over alt's save")

print("-- 6. None: the save's character, nothing written")
end_game()
mm = MM.main_menu()
click(mm, "pst_row_1")
ACTOR.money = 5
local before = FILES["app/persistent_stalkers_profile_default.txt"]
start_game(save_alt)
check(C.get_phase() == "none" and #APPLIED == 1, "phase none, nothing applied")
local s6 = {}
fire("save_state", s6)
check(s6.persistent_stalkers.profile == "none" and FILES["app/persistent_stalkers_profile_default.txt"] == before, "a save recorded none, no profile written")
mm = MM.main_menu()
check(text_of("menu:what"):find("without a profile"), "pause menu with None: " .. text_of("menu:what"))

print("-- 7. constant saves: the profile is applied on every load")
end_game()
MCM["persistent_stalkers/constant_saves"] = true
mm = MM.main_menu()
click(mm, "pst_row_2")
check(text_of("menu:what"):find("exactly as you left it"), "what in profile mode")
ACTOR.money = 5
start_game(save)
check(#APPLIED == 2 and APPLIED[2].money == 250, "default applied over its own save")
ACTOR.money = 300
for i = 1, 60 do NOW = NOW + 100; fire("actor_on_update") end
check(P.character().money == 300, "written within 5 s")

print("-- 8. F8 switches in a game, in debug mode only")
local function f8() fire("on_key_press", "DIK_F8"); fire("on_key_release", "DIK_F8") end
DEV_DEBUG = false
f8()
check(not M.is_open(), "F8 without -dbg does nothing")
DEV_DEBUG = true
f8()
check(M.is_open(), "F8 with -dbg opens the switch window")
local sw = M.GUI
local sp = sw.panel
check(sp and sp.how == "switch" and #sp.entries == 3, "every row in the window")
check(sp.row_texts[2].text:find("in use"), "default marked in use: " .. sp.row_texts[2].text)
check(sp.btn_new.shown == false and sp.btn_remove.shown == false, "no New or Remove in a game")
click(sw, "pst_row_3")
check(sp.chosen == "alt" and P.current_profile() == "default", "a click only shows alt")
check(text_of("menu:what"):find("default is written first"), "what: " .. text_of("menu:what"))
click(sw, "pst_btn_switch")
check(not M.is_open(), "Switch closes the window")
NOW = NOW + 100; fire("actor_on_update")
check(P.current_profile() == "alt" and #APPLIED == 3 and APPLIED[3].money == 900 and P.selected_profile() == "alt", "then alt is applied and selected")
check(P.character_of("default").money == 300, "default was written first")
f8()
check(M.is_open(), "F8 opens it again")
M.GUI:OnKeyboard("DIK_F8", "WINDOW_KEY_PRESSED")
fire("on_key_release", "DIK_F8")
check(not M.is_open(), "F8 closes it, and its release does not reopen it")
f8()
M.GUI:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED")
check(not M.is_open(), "Esc closes it")
f8()
click(M.GUI, "pst_btn_close")
check(not M.is_open(), "Close closes it")
NOW = NOW + 100; fire("actor_on_update")
check(P.current_profile() == "alt" and #APPLIED == 3, "closing switches nothing")
C.switch_to("nope")
check(P.current_profile() == "alt", "the console: an unknown name is refused")
DEV_DEBUG = false

print("-- 9. constant saves unticked mid-game")
MCM["persistent_stalkers/constant_saves"] = false
fire("on_option_change")
check(logged("constant saves off"), "a tip says so")
local rev = P.revision()
ACTOR.money = 777
for i = 1, 60 do NOW = NOW + 100; fire("actor_on_update") end
check(P.revision() == rev, "nothing written between saves")
fire("save_state", {})
check(P.character().money == 777, "written at the save")

print("-- 10. client in save mode")
end_game()
HOST = false
ACTOR.money = 40
start_game()
check(C.get_phase() == "waiting", "waits for the key")
CB["net_pst_world"][1](master_core_text.encode({ key = "k-1" }))
for i = 1, 60 do NOW = NOW + 100; fire("actor_on_update") end
check(C.get_phase() == "live" and #APPLIED == 4 and APPLIED[4].money == 777, "no snapshot: alt's file applied (as step 9 saved it)")
ACTOR.money = 41
CB["net_pst_saved"][1](master_core_text.encode({ key = "k-2" }))
check(P.snapshot("k-2") and P.snapshot("k-2").money == 41, "a host save stores a snapshot")
end_game()
ACTOR.money = 1
start_game()
CB["net_pst_world"][1](master_core_text.encode({ key = "k-2" }))
for i = 1, 60 do NOW = NOW + 100; fire("actor_on_update") end
check(#APPLIED == 5 and APPLIED[5].money == 41, "a rejoin into that key applies the snapshot")

print("-- 11. the ROMEO skin (romeo\\gamedata)")
end_game()
HOST = true
load_script(ROOT_V2:gsub("gamedata[/\\]scripts[/\\]$", "romeo/gamedata/scripts/"), "persistent_stalkers_skin")
XML_NODES["options"] = nil
XML_NODES["menu:background"] = nil
mm = MM.main_menu()
panel = mm.pst_panel
check(panel and panel.skin.name == "romeo", "the ROMEO skin is taken")
check(XML_NODES["menu:background"] == nil, "ROMEO: no frame behind the panel (a plain texture in a frame crashed)")
check(XML_FROM["background"] == "ui_mm_main.xml", "ROMEO: the stock background (ROMEO patches it)")
check(XML_NODES["options"] == nil, "ROMEO: the options are left where ROMEO puts them")
check(XML_FROM["menu:panel"] == "ui_persistent_stalkers_romeo.xml", "ROMEO: its compact layout")
check(#panel.rows == 5 and panel.bag == nil and panel.note == nil and panel.what == nil, "ROMEO: 5 rows, no backpack, note or what")
check(panel.btn_new.tc.text == "New", "ROMEO: short button labels")
click(mm, "pst_row_3")
check(P.selected_profile() == "alt" and panel.chosen == "alt", "ROMEO: a click selects alt")
local d = text_of("menu:details")
check(d:find("Money: 41 RU") and d:find("Rank:") and not d:find("Reputation"), "ROMEO: short details: " .. d)
check(#panel.cells == 3, "ROMEO: only what is equipped is drawn (rifle, outfit, belt): " .. #panel.cells)
start_game()
check(C.get_phase() == "live", "ROMEO: a game starts as alt")
mm = MM.main_menu()
check(mm.pst_panel.how == "pause" and mm.pst_panel.skin.name == "romeo", "ROMEO: the pause menu is compact too")
DEV_DEBUG = true
f8()
check(M.is_open() and M.GUI.panel.skin.name == "default" and M.GUI.panel.bag ~= nil, "the debug F8 window keeps the full layout")
M.GUI:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED")
DEV_DEBUG = false
load_script(ROOT_V2, "persistent_stalkers_skin")

print("-- 12. the lobby spike (fake_start)")
end_game()
LOBBY = load_script(ROOT_V2, "persistent_stalkers_lobby")
local marker = "app/persistent_stalkers_lobby.txt"
mm = MM.main_menu()
check(mm.pst_panel.btn_lobby ~= nil, "main menu: an Enter the lobby button")
-- with the lobby's own spawn: the main menu's start command reads it, for that call only
SPAWN_PRESENT = true
mm.StartGame = function() exec_console_cmd("start server(all/single/alife/new) client(localhost)") end
local n_cmds = #CMDS
click(mm, "pst_btn_lobby")
local start_cmd = nil
for i = n_cmds + 1, #CMDS do if CMDS[i]:find("^start server") then start_cmd = CMDS[i] end end
check(start_cmd == "start server(ps_lobby/single/alife/new) client(localhost)", "enter with ps_lobby.spawn: the new game reads it")
exec_console_cmd("start server(all/single/alife/new) client(localhost)")
check(CMDS[#CMDS] == "start server(all/single/alife/new) client(localhost)", "after enter, the start command is no longer redirected")
SPAWN_PRESENT = nil
KEYPRESS = true -- as before the first enter above (it switched it off; that lobby never started)
local started = false
mm.StartGame = function() started = true end
click(mm, "pst_btn_lobby")
check(started and FILES[marker] and FILES[marker] ~= "", "enter: the marker is written and the new game started")
check(CLEARED.new_game_faction and CLEARED.new_game_map, "enter: no faction or start map, so nothing leaves fake_start")
check(SETCFG.new_game_test == true, "enter: the debug test map's switch is set (no squads filled)")
check(KEYPRESS == false and master_core_text.decode(FILES[marker]).kp == true, "enter: no \"press any key\" for the lobby's load, the marker remembers it")
-- that new game, on fake_start
LEVEL_NAME = "fake_start"
local n_applied = #APPLIED
-- what the two profiles wear
FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 9, character = { money = 41, active = 3,
	items = { { section = "outfit_alt", slot = 7 }, { section = "wpn_rifle", slot = 3 }, { section = "bread" }, { section = "wpn_knife", slot = 1 } } } })
FILES["app/persistent_stalkers_profile_default.txt"] = master_core_text.encode({ version = 1, revision = 9, character = { money = 250, active = 2,
	items = { { section = "outfit_def", slot = 7 }, { section = "wpn_pistol", slot = 2 } } } })
local alt_file, def_file = FILES["app/persistent_stalkers_profile_alt.txt"], FILES["app/persistent_stalkers_profile_default.txt"]
-- the new game's own kit, a knife among it; and an autosave made since the main menu
OBJECTS[1] = { id = function() return 1 end, section = "wpn_knife" }
INV[1] = true
SAVES = { "lobby autosave", "mysave" }
local function worn(s) return SLOTS[s] and OBJECTS[SLOTS[s]] and OBJECTS[SLOTS[s]].section end
start_game()
check(C.get_phase() == "idle", "the core does not start on fake_start")
check(LOBBY.is_active() and FILES[marker] == "", "the lobby started, the marker is used up")
check(KEYPRESS == true, "the lobby started: \"press any key\" is on again for later loads")
check(CAM.pos == nil and CAM.input == nil and CAM.hud == false and CAM.mode == 2, "free-look camera, no custom camera, HUD off, input not disabled (the dialog holds it)")
-- aimed: the bodies face the row's heading plus pi (TUNE.face); in mode 1 turned away from that, then in free look to it
local d1, d2 = DIRS[#DIRS - 1], DIRS[#DIRS]
check(d1 and d1.mode == 1 and math.abs(d1.h) < 0.001 and d2.mode == 2 and math.abs(math.abs(d2.h) - math.pi) < 0.001,
	"aimed: in mode 1 away from the bodies' heading, then the bodies' heading (row + pi) in free look")
local lw = LOBBY.GUI
check(lw and lw:IsShown() and lw.panel.how == "lobby" and lw.panel.skin.name == "lobby" and lw.panel.bag == nil, "the lobby window: the compact panel")
check(#lw.panel.entries == 3, "the lobby lists every profile")
check(#APPLIED == n_applied, "no restore in the lobby (the wardrobe instead)")
check(INV[1] == nil and RELEASED >= 1, "the actor's own kit is released: no knife for quick melee")
local made = 0
for _ in pairs(INV) do made = made + 1 end
check(made == 4, "the wardrobe: each profile's worn items made once, nothing else (" .. made .. ")")
check(worn(7) == "outfit_alt" and worn(3) == "wpn_rifle" and worn(1) == nil and ACTIVE_SLOT == 3, "the model wears alt's outfit and rifle")
check(LOWERED == true, "the weapon is held low")
local stand, xs = 0, {}
for id, o in pairs(NPCS) do stand = stand + 1; xs[#xs + 1] = string.format("%.1f", o.pos.x) end
table.sort(xs)
check(stand == 4 and table.concat(xs, ",") == "10.0,11.1,12.2,8.9" and math.abs(ACTOR_POS.x - 7.8) < 0.01,
	"the host leftmost, four stand-ins to its right: " .. table.concat(xs, ","))
local some_npc = next(NPCS)
NPCS[some_npc].pos = { x = 0, y = 0, z = 0 }
NPCS[some_npc].sight = nil
NOW = NOW + 100; fire("actor_on_update")
check(math.abs(NPCS[some_npc].pos.z - 20) < 0.01 and NPCS[some_npc].sight and math.abs(NPCS[some_npc].sight.z + 1) < 0.001,
	"a stand-in that walked off is put back, looking at the camera")
-- a draw sent while the old weapon is put away is dropped: it is sent again
DROP_DRAWS = 2
click(lw, "pst_row_2")
local made2 = 0
for _ in pairs(INV) do made2 = made2 + 1 end
check(P.selected_profile() == "default" and worn(7) == "outfit_def" and worn(2) == "wpn_pistol" and worn(3) == nil,
	"a click selects default and the model wears it at once")
for i = 1, 12 do NOW = NOW + 100; fire("actor_on_update") end
check(ACTIVE_SLOT == 2 and LOWERED == true, "its pistol is drawn after two dropped draws, then lowered")
check(made2 == 4 and #MC_PENDING == 0, "nothing made or released for a click")
click(lw, "pst_row_1")
check(P.selected_profile() == "none" and worn(7) == nil and worn(2) == nil, "None: selected, the model bare")
click(lw, "pst_row_3")
check(worn(7) == "outfit_alt" and worn(3) == "wpn_rifle", "alt again, at once")
ACTOR_POS = { x = 50, y = 0, z = 50 }
for i = 1, 3 do NOW = NOW + 100; fire("actor_on_update") end
check(math.abs(ACTOR_POS.x - 7.8) < 0.01 and math.abs(ACTOR_POS.z - 20) < 0.01, "an actor that drifted is put back on its spot")
local s12 = {}
fire("save_state", s12)
check(s12.persistent_stalkers.profile == nil, "a save made in the lobby names no profile")
check(FILES["app/persistent_stalkers_profile_alt.txt"] == alt_file and FILES["app/persistent_stalkers_profile_default.txt"] == def_file, "nothing is written to any profile in the lobby")
local n_cmds = #CMDS
check(lw:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED") == true and lw:OnKeyboard("DIK_I", "WINDOW_KEY_PRESSED") == true
	and #CMDS == n_cmds and lw:IsShown(), "the lobby window takes every key: Esc does not leave it")
local shown_opts = {}
for _, o in ipairs(lw.options) do if o.button.shown ~= false then shown_opts[#shown_opts + 1] = o.name end end
check(table.concat(shown_opts, ",") == "btn_newgame,btn_load,btn_lastsave,btn_options,btn_mcm,btn_quit_to_mm,btn_quit",
	"the main menu's options on the right: " .. table.concat(shown_opts, ","))
check(lw.options[2].button.y == lw.options[1].button.y + 38, "the options one under the other")
-- Load game: the main menu's own load dialog, this window its owner
click(lw, "btn_load")
check(lw.load_dlg and lw.load_dlg:IsShown() and lw.load_dlg.owner == lw and not lw:IsShown() and CMDS[#CMDS] ~= "main_menu on",
	"Load game opens the load dialog directly (not the pause menu)")
for i = 1, 20 do NOW = NOW + 100; fire("actor_on_update") end
check(LOBBY.GUI == lw and not lw:IsShown(), "the window is not reopened over the load dialog")
-- the dialog's Back, as the game's: owner:ShowDialog(true), owner:Show(true)
lw.load_dlg:HideDialog(); lw:ShowDialog(true); lw:Show(true)
check(lw:IsShown() and LOBBY.GUI == lw, "back from the load dialog: the lobby again")
click(lw, "btn_options")
check(lw.opt_dlg and lw.opt_dlg:IsShown() and lw.opt_dlg.owner == lw, "Options: the game's options dialog")
lw.opt_dlg:HideDialog(); lw:ShowDialog(true)
click(lw, "btn_mcm")
check(lw.mcm_dlg and lw.mcm_dlg:IsShown(), "MCM: its dialog")
lw.mcm_dlg:HideDialog(); lw:ShowDialog(true)
click(lw, "btn_newgame")
check(lw.new_game_dlg and lw.new_game_dlg:IsShown() and lw.new_game_dlg.owner == lw, "New game: the faction select")
lw.new_game_dlg:HideDialog(); lw:ShowDialog(true)
-- Last save: the main menu's box, then the save that was newest at the main menu
local old_alife = alife
alife = function() return {} end -- in a game
click(lw, "btn_lastsave")
local ycb = lw.cb["msg_box:MESSAGE_BOX_YES_CLICKED"]
ycb[1](ycb[2])
alife = old_alife
check(CMDS[#CMDS] == "load mysave", "Last save loads the newest save at the main menu, not the lobby's autosave: " .. tostring(CMDS[#CMDS]))
-- Leave: the main menu's quit-game box, then disconnect
click(lw, "btn_quit_to_mm")
local qcb = lw.cb["msg_box:MESSAGE_BOX_QUIT_GAME_CLICKED"]
check(qcb ~= nil, "Leave asks with the main menu's box")
qcb[1](qcb[2])
check(CMDS[#CMDS] == "disconnect", "Leave: disconnect")
fire("actor_on_net_destroy")
check(not LOBBY.is_active() and CAM.pos == nil and CAM.hud == true and LOWERED == false, "the level goes: camera, HUD and weapon back")
-- stop() without a level change (the console) releases the stand-ins
LOBBY.stop()
-- a real new game passes through fake_start too: no marker, no lobby
end_game()
start_game()
check(not LOBBY.is_active() and C.get_phase() == "idle", "fake_start without a marker (a real new game): no lobby")
-- a lobby game that never started: the main menu clears its marker and the test-map switch
end_game()
FILES[marker] = master_core_text.encode({ t = os.time() })
SETCFG.new_game_test = true
MM.main_menu()
check(FILES[marker] == "" and SETCFG.new_game_test == nil, "a stale lobby marker at the main menu: it and the test-map switch are cleared")
KEYPRESS = false
FILES[marker] = master_core_text.encode({ t = os.time(), kp = true })
MM.main_menu()
check(KEYPRESS == true, "a stale lobby marker that switched \"press any key\" off: on again at the main menu")
local mm_ok = MM.main_menu()
check(SETCFG.new_game_test == nil and FILES[marker] == "", "no marker: nothing to clear")
start_game()
LEVEL_NAME = "l01_escape"

print("-- 13. a lobby game isolates every callback")
-- axr_main's registry, as the game has it (registrants run in order, no pcall)
local REG = {}
axr_main.callback_set = function(name, f) REG[name] = REG[name] or {}; table.insert(REG[name], f) end
axr_main.callback_unset = function(name, f)
	for i, g in ipairs(REG[name] or {}) do if g == f then table.remove(REG[name], i); return end end
end
local function send(name, ...)
	for _, f in ipairs(REG[name] or {}) do
		if type(f) == "function" then f(...) else f[name](f, ...) end
	end
end
-- a real game (no marker): the script loads and wraps nothing
FILES[marker] = ""
local plain = axr_main.callback_set
load_script(ROOT_V2, "persistent_stalkers_lobby")
check(axr_main.callback_set == plain and not persistent_stalkers_lobby.isolation(), "no marker: callbacks are not wrapped")
-- the new game started from enter(): a fresh marker when the script loads
FILES[marker] = master_core_text.encode({ t = os.time() })
local ISO = load_script(ROOT_V2, "persistent_stalkers_lobby")
check(axr_main.callback_set ~= plain and ISO.isolation(), "a fresh marker: every callback is wrapped")
local ran = {}
local function bad() error("SIMBOARD.smarts_by_names[...] is nil") end
local function good() ran.good = (ran.good or 0) + 1 end
local obj = { actor_on_first_update = function(self, x) ran.obj = x end }
axr_main.callback_set("actor_on_first_update", bad)
axr_main.callback_set("actor_on_first_update", good)
axr_main.callback_set("actor_on_first_update", obj)
local ok_send = pcall(send, "actor_on_first_update", 7)
check(ok_send and ran.good == 1 and ran.obj == 7, "a failing first update does not stop the later ones (functions and objects)")
axr_main.callback_set("actor_on_update", function() error("head_tbl.volume is nil") end)
local n_log = #LOG
for _ = 1, 3 do pcall(send, "actor_on_update") end
local said = 0
for i = n_log + 1, #LOG do if LOG[i]:find("isolated: actor_on_update", 1, true) then said = said + 1 end end
local sent_ok = pcall(send, "actor_on_update")
local _, failed = ISO.isolation()
check(sent_ok and said == 1 and failed == 5, "an update error is caught every time and logged once")
axr_main.callback_unset("actor_on_first_update", good)
ran.good = 0
send("actor_on_first_update", 8)
check(ran.good == 0 and ran.obj == 8, "unregistering by the original function removes its wrapper")
-- loaded again in the same Lua (no new game): not wrapped twice
local set_now = axr_main.callback_set
load_script(ROOT_V2, "persistent_stalkers_lobby")
check(axr_main.callback_set == set_now, "wrapped only once")
-- our axr_main asks startup_skip() before any script starts
-- the engine loads a script when it is first named: _G's __index
local G_MT_OLD = getmetatable(_G)
local UI_MCM_OLD = rawget(_G, "ui_mcm"); rawset(_G, "ui_mcm", nil)
local FAKE_MCM = { gather_options = function() return pst_test_skipped, pst_test_kept end, get = function(id) FAKE_MCM_ASKED = (FAKE_MCM_ASKED or 0) + 1; if id == "kept/x" then return 3 end end }
setmetatable(_G, { __index = function(t, k) if k == "pst_test_kept" or k == "pst_test_skipped" then return { loaded = k } elseif k == "ui_mcm" then return FAKE_MCM end end })
persistent_stalkers_skip = { names = { ["quickdraw.script"] = true, ["pst_test_skipped.script"] = true } }
local skip_now = ISO.startup_skip()
check(skip_now and skip_now["quickdraw.script"], "a fresh marker: startup_skip gives the skip list")
local n_bl = #LOG
local g_sk, g_kept = ui_mcm.gather_options()
local g_sk2 = ui_mcm.gather_options()
check(g_sk == nil and g_sk2 == nil and g_kept and g_kept.loaded == "pst_test_kept", "while MCM gathers its options, a skipped script is not loaded; a kept one is")
check(pst_test_skipped and pst_test_skipped.loaded == "pst_test_skipped", "outside the gather a skipped script still loads when named (sim_board needs smr_civil_war)")
FILES[getFS():update_path("$app_data_root$", "persistent_stalkers_lobby_mcm.txt")] = master_core_text.encode({ ["stealth/memory"] = 0.5, ["a/b"] = true })
check(ui_mcm.get("kept/x") == 3 and ui_mcm.get("stealth/memory") == 0.5 and ui_mcm.get("a/b") == true and ui_mcm.get("none/y") == nil, "MCM in the lobby: a skipped mod's setting comes from the main menu's snapshot, a kept one from MCM")
local asked0 = FAKE_MCM_ASKED
for _ = 1, 5 do ui_mcm.get("stealth/memory"); ui_mcm.get("none/y") end
check(FAKE_MCM_ASKED == asked0 and ui_mcm.get("stealth/memory") == 0.5, "a path MCM did not know is not asked again (no \"bad path\" spam)")
ISO.status()
local bl_text = table.concat(LOG, string.char(10), n_bl + 1)
check(bl_text:find("skipped scripts asked for and not loaded: 1", 1, true) and bl_text:find("2x pst_test_skipped", 1, true), "status: the blocked script and how often it was asked for")
setmetatable(_G, G_MT_OLD)
rawset(_G, "ui_mcm", UI_MCM_OLD)
persistent_stalkers_skip = nil
check(ISO.startup_skip() == nil, "no skip list built: every script starts")
FILES[marker] = ""
persistent_stalkers_skip = { names = { ["quickdraw.script"] = true } }
check(ISO.startup_skip() == nil, "no marker (any other game): nothing skipped")
persistent_stalkers_skip = nil
FILES[marker] = ""

local n_rep = #LOG
ISO.startup_report({ a = 0.5, b = 2.0, c = 0.01 }, { b = 1.25 })
local rep_text = table.concat(LOG, "\n", n_rep + 1)
check(rep_text:find("load (the file, and every script it names): 3 scripts, 2510 ms", 1, true) and rep_text:find("2000 ms  b", 1, true)
	and rep_text:find("on_game_start (and every script it names): 1 scripts, 1250 ms", 1, true)
	and rep_text:find("2000 ms  b", 1, true) < rep_text:find(" 500 ms  a", 1, true), "the startup report: totals, and the slowest first")

do
	local old_mcm = rawget(_G, "ui_mcm")
	local asked = {}
	rawset(_G, "ui_mcm", { options = { { id = "SMR", gr = { { id = "smr_stalkers", sh = true, gr = {
		{ id = "title", type = "slide" }, { id = "stalker", type = "check", val = 1, def = true }, { id = "memory", type = "track", val = 2, def = 1 } } } } } },
		get = function(id) asked[#asked + 1] = id; if id == "SMR/smr_stalkers/stalker" then return false end; return 2 end })
	local n = ISO.mcm_snapshot()
	local snap = master_core_text.decode(FILES[getFS():update_path("$app_data_root$", "persistent_stalkers_lobby_mcm.txt")])
	check(n == 2 and snap["SMR/smr_stalkers/stalker"] == false and snap["SMR/smr_stalkers/memory"] == 2 and #asked == 2, "the MCM snapshot: every option by its MCM path, values as MCM gives them")
	-- the main menu after a lobby: MCM has only the kept mods' pages
	rawset(_G, "ui_mcm", { options = { { id = "pst", gr = { { id = "carry_money", type = "check", val = 1, def = true } } } },
		get = function(id) return true end })
	local n2 = ISO.mcm_snapshot()
	snap = master_core_text.decode(FILES[getFS():update_path("$app_data_root$", "persistent_stalkers_lobby_mcm.txt")])
	check(n2 == 1 and snap["pst/carry_money"] == true and snap["SMR/smr_stalkers/stalker"] == false and snap["SMR/smr_stalkers/memory"] == 2,
		"a partial MCM (the main menu after a lobby) adds to the snapshot and keeps the earlier values")
	rawset(_G, "ui_mcm", old_mcm)
end

do
	local n0 = #LOG
	ISO.callback_report(5)
	local txt = table.concat(LOG, string.char(10), n0 + 1)
	check(txt:find("callbacks until the lobby started", 1, true) ~= nil and txt:find("actor_on_first_update", 1, true) ~= nil, "the callback report: totals per callback and the slowest registrants")
end

print(string.format("%d checks, %d failed", checks, fails))

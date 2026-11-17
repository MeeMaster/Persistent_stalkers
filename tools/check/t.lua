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
	set_cam_custom_position_direction = function(pos, hp, _, hud) CAM.pos, CAM.hp, CAM.hud_draw = pos, hp, hud end,
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
game = { translate_string = function(s) return s end,
	world2ui = function(pos) return { x = 200 + (pos.x or 0) * 10, y = 520 } end }
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
-- the old dropdown's "off" is left in the options: it must be ignored now.
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
	o.set_character_community = function(s, c) s.community = c end
	o.set_character_rank = function(s, r) s.rank = r end
	o.set_bone_visible = function(s, _, vis) s.bone_vis = vis end
	o.visual = "actors\\stalker_neutral\\stalker_neutral_1"
	o.get_visual_name = function(s) return s.visual end
	o.set_visual = function(s, v) s.visual = v end
	o.set_visual_name = function(s, v) s.visual = v end
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
	apply_edits = function(e)
		EDITS[#EDITS + 1] = e
		if e.faction then ACTOR.faction = e.faction end
		if e.goodwill then ACTOR.goodwill = master_core_text.decode(master_core_text.encode(e.goodwill)) end
	end,
	busy = function() return false end,
	update = function() end,
	cancel = function() end,
	summary = function(c) return c and (tostring(#(c.items or {})) .. " items") or "nothing" end,
}
load_script(ROOT_V2, "persistent_stalkers_skin")
PLACE = load_script(ROOT_V2, "persistent_stalkers_place")
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
check(t.gr[2].id == "title_parts", "no start-with-lobby option: the lobby starts from its button")
for _, e in ipairs(t.gr) do
	check(e.id ~= "mode", "no mode dropdown: " .. tostring(e.id))
end
local mm = MM.main_menu()
check(mm.pst_panel ~= nil, "the panel is attached")
check(XML_NODES["options"] ~= nil and XML_NODES["menu_box"] == nil, "the options are moved, with no box around them")
check(XML_FROM["background"] == "ui_persistent_stalkers.xml", "default skin: our background")
check(mm.pst_panel.skin.name == "default" and mm.pst_panel.equip ~= nil and mm.pst_panel.bag ~= nil
	and mm.pst_panel.details == nil and mm.pst_panel.what == nil and #mm.pst_panel.rows == 8
	and mm.pst_panel.btn_new.tc.text == "New",
	"default skin: the list and the inventory, on the left")
check(not logged("could not be"), "no build errors")
local panel = mm.pst_panel
check(#panel.entries == 2 and panel.entries[1] == "none" and panel.entries[2] == "default", "rows: None, default")
check(panel.chosen == "default", "default is selected first")
check(panel.row_texts[2].text:find("empty"), "default is shown empty: " .. panel.row_texts[2].text)
mm:Update()
check(mm.pst_panel ~= nil, "Update keeps the panel")

click(mm, "pst_row_1")
check(P.selected_profile() == "none" and FILES["app/persistent_stalkers_selected.txt"]:find("none"), "a click on None selects it, remembered")
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
check(panel.btn_new.shown == false and panel.what == nil and panel.details == nil, "pause menu: the profile in use, list only")

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

print("-- 7. constant saves: the profile is applied on every load")
end_game()
MCM["persistent_stalkers/constant_saves"] = true
mm = MM.main_menu()
click(mm, "pst_row_2")
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
-- the lobby: the boot (markers, script skip, MCM, carry), the join, the
-- window, hand tuning, and the scene
function load_lobby()
	LB = load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
	LJ = load_script(ROOT_V2, "persistent_stalkers_lobby_join")
	load_script(ROOT_V2, "persistent_stalkers_newgame")
	load_script(ROOT_V2, "persistent_stalkers_lobby_ui")
	LT = load_script(ROOT_V2, "persistent_stalkers_lobby_tune")
	LOBBY = load_script(ROOT_V2, "persistent_stalkers_lobby")
	return LOBBY
end
load_lobby()
local marker = "app/persistent_stalkers_lobby.txt"
mm = MM.main_menu()
check(mm.pst_panel.btn_lobby ~= nil and mm.pst_panel.btn_lobby:TextControl():GetText() == "Start the lobby", "main menu: a Start the lobby button")
-- with the lobby's own spawn: the main menu's start command reads it, for that call only
SPAWN_PRESENT = true
-- a spawn header: chunk id, size, version, the spawn's GUID, the graph's GUID
local function spawn_head(graph) return string.rep(string.char(0), 12) .. string.rep("S", 16) .. graph .. "rest" end
FILES["app/ps_lobby.spawn"] = spawn_head(string.rep("G", 16))
FILES["app/all.spawn"] = spawn_head(string.rep("G", 16))
mm.StartGame = function() exec_console_cmd("start server(all/single/alife/new) client(localhost)") end
local n_cmds = #CMDS
click(mm, "pst_btn_lobby")
local start_cmd = nil
for i = n_cmds + 1, #CMDS do if CMDS[i]:find("^start server") then start_cmd = CMDS[i] end end
check(start_cmd == "start server(ps_lobby/single/alife/new) client(localhost)", "enter with ps_lobby.spawn: the new game reads it")
exec_console_cmd("start server(all/single/alife/new) client(localhost)")
check(CMDS[#CMDS] == "start server(all/single/alife/new) client(localhost)", "after enter, the start command is no longer redirected")
-- made for another world graph, or all.spawn unreadable: the lobby starts from all.spawn
FILES["app/all.spawn"] = spawn_head(string.rep("H", 16))
local n_log = #LOG
check(LB.has_spawn() == false and table.concat(LOG, " ", n_log + 1):find("made for another world graph", 1, true),
	"ps_lobby.spawn made for another world graph: all.spawn, logged")
FILES["app/all.spawn"] = nil
check(LB.has_spawn() == false, "all.spawn packed (not a file) and ps_lobby.spawn not for Anomaly's graph: all.spawn")
local anomaly_graph = ("defae07743cab24b9c71f4729f54e866"):gsub("%x%x", function(b) return string.char(tonumber(b, 16)) end)
FILES["app/ps_lobby.spawn"] = spawn_head(anomaly_graph)
check(LB.has_spawn() == true, "all.spawn packed (base Anomaly) and ps_lobby.spawn for Anomaly's graph: ps_lobby.spawn")
FILES["app/ps_lobby.spawn"] = spawn_head(string.rep("G", 16))
FILES["app/all.spawn"] = spawn_head(string.rep("G", 16))
check(LB.has_spawn() == true, "the same world graph: ps_lobby.spawn")
SPAWN_PRESENT = nil
check(LB.has_spawn() == false, "no ps_lobby.spawn: all.spawn")
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
	faction = "stalker", skill_tree = { class = "sniper" },
	items = { { section = "outfit_alt", slot = 7 }, { section = "wpn_rifle", slot = 3 }, { section = "bread" }, { section = "wpn_knife", slot = 1 } } } })
FILES["app/persistent_stalkers_profile_default.txt"] = master_core_text.encode({ version = 1, revision = 9, character = { money = 250, active = 2,
	items = { { section = "outfit_def", slot = 7 }, { section = "wpn_pistol", slot = 2 } } } })
local alt_file, def_file = FILES["app/persistent_stalkers_profile_alt.txt"], FILES["app/persistent_stalkers_profile_default.txt"]
local alt_now = P.character()
if alt_now then
	alt_now.faction = "stalker"
	alt_now.skill_tree = { class = "sniper" }
end
-- the new game's own kit, a knife among it; and an autosave made since the main menu
OBJECTS[1] = { id = function() return 1 end, section = "wpn_knife" }
INV[1] = true
SAVES = { "lobby autosave", "mysave" }
-- itms_manager schedules this on the first update; the lobby must drop it
EVQ = {}
function CreateTimeEvent(ev, act, timer, f)
	EVQ[tostring(ev) .. "\0" .. tostring(act)] = f
end
function RemoveTimeEvent(ev, act)
	EVQ[tostring(ev) .. "\0" .. tostring(act)] = nil
end
RegisterScriptCallback("actor_on_first_update", function()
	CreateTimeEvent(0, "delay_new_game_autosave", 4, function()
		exec_console_cmd("save user - autosave")
	end)
end)
local function worn(s) return SLOTS[s] and OBJECTS[SLOTS[s]] and OBJECTS[SLOTS[s]].section end
start_game()
check(C.get_phase() == "idle", "the core does not start on fake_start")
check(LOBBY.is_active() and FILES[marker] == "", "the lobby started, the marker is used up")
check(EVQ["0\0delay_new_game_autosave"] == nil, "the lobby cancels the new-game autosave")
local n_save = #CMDS
exec_console_cmd("save user - autosave")
exec_console_cmd("save my manual")
exec_console_cmd("save user - quicksave_1")
exec_console_cmd("save")
check(#CMDS == n_save, "the lobby writes no save: not an autosave, a named save, a quicksave, or a bare save")
local save_flags = { ret = false }
fire("on_before_save_input", save_flags, 2, "save")
check(save_flags.ret == true, "a quicksave key is refused in the lobby")
check(KEYPRESS == false, "the lobby started: \"press any key\" stays off, so the host's next load does not wait")
check(CAM.pos == nil and CAM.input == nil and CAM.hud == false and CAM.mode == 2, "free-look camera, no custom camera, HUD off, input not disabled (the dialog holds it)")
-- aimed: the bodies face the row's heading plus pi (TUNE.face); in mode 1 turned away from that, then in free look to it
local d1, d2 = DIRS[#DIRS - 1], DIRS[#DIRS]
check(d1 and d1.mode == 1 and math.abs(d1.h) < 0.001 and d2.mode == 2 and math.abs(math.abs(d2.h) - math.pi) < 0.001,
	"aimed: in mode 1 away from the bodies' heading, then the bodies' heading (row + pi) in free look")
local lw = LOBBY.GUI
check(lw and lw:IsShown() and lw.panel.how == "lobby" and lw.panel.skin.name == "lobby" and lw.panel.bag
	and lw.panel.bag.y > lw.panel.equip.y + lw.panel.equip.h * 0.5 and lw.panel.bag.w >= lw.panel.wnd.w - 30
	and lw.panel.wnd.shown == false, "the lobby window: the compact panel, hidden on the lineup, inventory under the loadout")
check(lw.plates and lw.plates[1].shown == true and lw.plates[1].text:find("Mee") and lw.plates[1].text:find("<alt>")
	and lw.plates[1].text:find("stalker") and lw.plates[1].text:find("sniper") and lw.plates[1].y < 520
	and lw.plates[2].shown ~= true,
	"name, profile, faction and class over the player, none over a stand-in")
check(#lw.panel.entries == 3, "the lobby lists every profile")
check(#APPLIED == n_applied, "no restore in the lobby (the wardrobe instead)")
check(INV[1] == nil and RELEASED >= 1, "the actor's own kit is released: no knife for quick melee")
local made = 0
for _ in pairs(INV) do made = made + 1 end
check(made == 4, "the wardrobe: each profile's worn items made once, nothing else (" .. made .. ")")
check(worn(7) == "outfit_alt" and worn(3) == "wpn_rifle" and worn(1) == nil and ACTIVE_SLOT == 3, "the model wears alt's outfit and rifle")
check(LOWERED == true, "the weapon is held low")
local none = 0
for _ in pairs(NPCS) do none = none + 1 end
check(none == 0, "no stand-ins unless tune(\"npcs\", 1)")
LOBBY.tune("npcs", 1)
NOW = NOW + 100; fire("actor_on_update")
local stand, xs = 0, {}
for id, o in pairs(NPCS) do stand = stand + 1; xs[#xs + 1] = string.format("%.1f", o.pos.x) end
table.sort(xs)
check(stand == 4 and table.concat(xs, ",") == "11.1,12.2,13.3,14.4" and math.abs(ACTOR_POS.x - 10) < 0.01,
	"no place for the map: the host where the actor stands, four stand-ins to its left (the camera's right): " .. table.concat(xs, ","))
local by_x = {}
for _, o in pairs(NPCS) do by_x[#by_x + 1] = o end
table.sort(by_x, function(a, b) return a.pos.x < b.pos.x end)
local got = {}
for _, o in ipairs(by_x) do got[#got + 1] = o.section .. "=" .. tostring(o.community) .. ":" .. tostring(o.rank) end
check(table.concat(got, ",") == "sim_default_stalker_0=stalker:2000,sim_default_stalker_2=stalker:8000,sim_default_stalker_3=stalker:20000,sim_default_stalker_4=stalker:40000",
	"stand-ins are loners, rank increasing to the right: " .. table.concat(got, ","))
local some_npc = next(NPCS)
NPCS[some_npc].pos = { x = 0, y = 0, z = 0 }
NPCS[some_npc].sight = nil
NOW = NOW + 100; fire("actor_on_update")
check(math.abs(NPCS[some_npc].pos.z - 20) < 0.01 and NPCS[some_npc].sight and math.abs(NPCS[some_npc].sight.z + 1) < 0.001,
	"a stand-in that walked off is put back, looking at the camera")
-- a draw sent while the old weapon is put away is dropped: it is sent again
DROP_DRAWS = 2
click(lw, "btn_change")
check(lw.panel.wnd.shown == true and lw.panel.wnd.x == 12 and lw.panel.wnd.y == 12
	and lw.btn_done.shown == true and lw.btn_change.shown == false,
	"Change profile: the panel on the left, Done in its place")
click(lw, "pst_row_2")
local made2 = 0
for _ in pairs(INV) do made2 = made2 + 1 end
check(P.selected_profile() == "alt" and worn(7) == "outfit_def" and worn(2) == "wpn_pistol" and worn(3) == nil,
	"a row wears default and does not select it yet")
for i = 1, 12 do NOW = NOW + 100; fire("actor_on_update") end
check(ACTIVE_SLOT == 2 and LOWERED == true, "its pistol is drawn after two dropped draws, then lowered")
check(made2 == 4 and #MC_PENDING == 0, "nothing made or released for a click")
lw:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED")
check(P.selected_profile() == "alt" and worn(7) == "outfit_alt" and lw.panel.wnd.shown == false and lw:IsShown(),
	"Esc puts the previous profile back and returns to the lineup")
click(lw, "btn_change")
click(lw, "pst_row_2")
click(lw, "btn_done")
check(P.selected_profile() == "default" and worn(7) == "outfit_def" and lw.panel.wnd.shown == false,
	"Done selects the profile and returns to the lineup")
click(lw, "btn_change")
click(lw, "pst_row_1")
click(lw, "btn_done")
check(P.selected_profile() == "none" and worn(7) == nil and worn(2) == nil, "Done on None: no profile, the model bare")
click(lw, "btn_change")
click(lw, "pst_row_3")
click(lw, "btn_done")
check(worn(7) == "outfit_alt" and worn(3) == "wpn_rifle" and P.selected_profile() == "alt", "alt again, on Done")
ACTOR_POS = { x = 50, y = 0, z = 50 }
for i = 1, 3 do NOW = NOW + 100; fire("actor_on_update") end
check(math.abs(ACTOR_POS.x - 10) < 0.01 and math.abs(ACTOR_POS.z - 20) < 0.01, "an actor that drifted is put back on its spot")
local s12 = {}
fire("save_state", s12)
check(s12.persistent_stalkers.profile == nil, "a save made in the lobby names no profile")
check(FILES["app/persistent_stalkers_profile_alt.txt"] == alt_file and FILES["app/persistent_stalkers_profile_default.txt"] == def_file, "nothing is written to any profile in the lobby")
click(lw, "btn_change")
check(lw.gw and lw.gw.shown and lw.gw_act and lw.gw_act.shown and lw.gw.x == 812 and lw.gw.w == 200
	and lw.gw_act.x == lw.gw.x and lw.gw_act.w == lw.gw.w and lw.gw_act.y > lw.gw.y + lw.gw.h - 1
	and lw.gw_title.text == "Goodwill" and lw.gw_act_title.text == "Reset faction" and lw.gw_act_sub.text == "Goodwill"
	and lw.btn_gw_keep:TextControl():GetText() == "Keep" and lw.btn_gw_reset:TextControl():GetText() == "Reset"
	and lw.btn_gw_keep.y == lw.btn_gw_reset.y and lw.btn_gw_reset.x > lw.btn_gw_keep.x and #lw.gw_rows == 12
	and lw.gw_name.y > lw.gw_rows[12].button.y,
	"close-up: Goodwill column, and under it Reset faction / Goodwill with Keep and Reset side by side")
relation_registry = {
	community_relation = function(a, b)
		if a == "actor_stalker" and b == "bandit" then return -2000 end
		if a == "actor_stalker" and b == "freedom" then return 1500 end
		if a == "actor_stalker" and b == "dolg" then return 0 end
		return 300
	end,
}
lw:FillGoodwill()
local function gw_row(id)
	for _, row in ipairs(lw.gw_rows) do if row.id == id then return row end end
end
check(gw_row("bandit").rel:GetText():find("175,50,50", 1, true) and gw_row("bandit").rel_n == -2000, "a hostile faction relation is red")
check(gw_row("freedom").rel:GetText():find("50,175,50", 1, true) and gw_row("freedom").rel_n == 1500, "a friendly faction relation is green")
check(gw_row("dolg").rel:GetText():find("175,175,50", 1, true) and gw_row("dolg").rel_kind == "neutral", "a neutral faction relation is yellow")
check(gw_row("bandit").you_n == nil and gw_row("bandit").you:GetText():find("140,140,140", 1, true), "goodwill that was never stored stays unset")
relation_registry = nil
lw:FillGoodwill()
local lit = 0
for _, row in ipairs(lw.gw_rows) do
	if row.patch_tex == "ui_mm_faction_" .. row.id then lit = lit + 1 end
	check(row.hint == row.id and (row.patch_tex == "ui_mm_faction_" .. row.id or row.patch_tex == "ui_mm_faction_" .. row.id .. "_inactive"), "patch " .. row.id)
end
check(lit == 1 and lw.gw_rows[12].patch_tex == "ui_mm_faction_stalker" and lw.gw_name.text:find("stalker", 1, true) and lw.gw_rows[12].you_n == nil,
	"the faction in use shows its patch, and goodwill that was never stored is not a number")
check(P.set_faction(P.NONE, "dolg", true) == false, "None has no faction to change")
check(P.set_faction("no_such_profile", "dolg", true) == false, "an unknown profile is refused")
check(P.set_faction("alt", "stalker", false) == false, "keeping goodwill while already that faction is refused")
click(lw, "gw_dolg")
check(lw.gw_target == "dolg", "a faction row is the one the buttons will write")
click(lw, "gw_reset")
check(lw.faction_warn and lw.faction_warn:IsShown()
	and lw.faction_warn.text.text:find("0", 1, true)
	and lw.faction_warn.text.text:find("bak1", 1, true)
	and lw.faction_warn.text.text:find("next time a game is loaded", 1, true)
	and lw.faction_warn.btn_go:TextControl():GetText():find("reset", 1, true),
	"reset warns, and names the backup, before it writes")
lw.faction_warn:OnKeyboard("DIK_RETURN", "WINDOW_KEY_PRESSED")
check(lw.faction_warn:IsShown() and FILES["app/persistent_stalkers_profile_alt.txt"] == alt_file, "Enter does not change the faction")
check(lw:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED") == true and lw.gw.shown and lw.faction_warn:IsShown(),
	"Esc on the lobby does not leave the close-up while the warning is up")
lw.faction_warn:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED")
check(not lw.faction_warn:IsShown() and lw.gw.shown and FILES["app/persistent_stalkers_profile_alt.txt"] == alt_file, "Esc cancels the warning")
click(lw, "gw_reset")
click(lw.faction_warn, "btn_go")
local written = master_core_text.decode(FILES["app/persistent_stalkers_profile_alt.txt"])
check(written.character.faction == "dolg" and written.character.goodwill.stalker == 0 and written.character.goodwill.dolg == 0
	and written.character.goodwill.freedom == 0 and FILES["app/persistent_stalkers_profile_alt.txt.bak1"] == alt_file,
	"reset writes Duty and zeros every goodwill, and keeps the old file")
check(lw.gw.shown and not lw.faction_warn:IsShown(), "the warning closes back to the close-up")
local now_dolg = gw_row("dolg")
check(now_dolg and now_dolg.you_n == 0 and now_dolg.you_kind == "neutral" and now_dolg.patch_tex == "ui_mm_faction_dolg",
	"the panel shows the reset goodwill in yellow, on Duty's patch")
click(lw, "gw_freedom")
click(lw, "gw_keep")
check(lw.faction_warn.text.text:find("Goodwill stays", 1, true), "keep warns that the numbers stay")
click(lw.faction_warn, "btn_go")
written = master_core_text.decode(FILES["app/persistent_stalkers_profile_alt.txt"])
check(written.character.faction == "freedom" and written.character.goodwill.dolg == 0, "keep changes the faction and leaves the numbers")
FILES["app/persistent_stalkers_profile_alt.txt"] = alt_file
lw:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED")
check(lw.gw.shown == false, "leaving the close-up hides the goodwill panel")
local n_cmds = #CMDS
check(lw:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED") == true and lw:OnKeyboard("DIK_I", "WINDOW_KEY_PRESSED") == true
	and #CMDS == n_cmds and lw:IsShown(), "the lobby window takes every key: Esc does not leave it")
local shown_opts = {}
for _, o in ipairs(lw.options) do if o.button.shown ~= false then shown_opts[#shown_opts + 1] = o.name end end
check(table.concat(shown_opts, ",") == "btn_newgame,btn_load,btn_lastsave,btn_options,btn_mcm,btn_quit_to_mm,btn_quit",
	"the main menu's options: " .. table.concat(shown_opts, ","))
check(lw.btn_change.shown == true and lw.btn_change.y == lw.options[1].button.y and lw.btn_change.y > 640
	and lw.options[2].button.y == lw.options[1].button.y and lw.options[2].button.x > lw.options[1].button.x,
	"Change profile and the options along the bottom")
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
KEYPRESS = true
click(lw, "btn_lastsave")
local ycb = lw.cb["msg_box:MESSAGE_BOX_YES_CLICKED"]
ycb[1](ycb[2])
alife = old_alife
check(CMDS[#CMDS] == "load mysave" and KEYPRESS == false, "Last save loads the newest save at the main menu, not the lobby's autosave, and does not ask for a key: " .. tostring(CMDS[#CMDS]))
-- Leave: the main menu's quit-game box, then disconnect
click(lw, "btn_quit_to_mm")
local qcb = lw.cb["msg_box:MESSAGE_BOX_QUIT_GAME_CLICKED"]
check(qcb ~= nil, "Leave asks with the main menu's box")
qcb[1](qcb[2])
check(CMDS[#CMDS] == "disconnect", "Leave: disconnect, back to the main menu")
fire("actor_on_net_destroy")
check(not LOBBY.is_active() and CAM.pos == nil and CAM.hud == true and LOWERED == false, "the level goes: camera, HUD and weapon back")
local function saw_cmd(s)
	for _, c in ipairs(CMDS) do if c == s then return true end end
	return false
end
check(saw_cmd("hud_draw 0") and saw_cmd("hud_draw 1"), "joining the lobby turns the HUD off, leaving turns it back on")
-- stop() without a level change (the console) releases the stand-ins
LOBBY.stop()
-- a real new game passes through fake_start too: no marker, no lobby
end_game()
start_game()
check(not LOBBY.is_active() and C.get_phase() == "idle", "fake_start without a marker (a real new game): no lobby")
-- a place in the config: the slots and cameras relative to the host's slot
end_game()
local cam_file = getFS():update_path("$game_config$", "mod_system_persistent_stalkers.ltx")
local function cam_ltx(place)
	local t = { "; the lobby (a comment that must stay)", "![actor_free_cam]", "lim_zoom = 0.4, 6.6", "",
		"[persistent_stalkers_lobby]", "place = " .. place.name, "spacing = " .. (place.spacing or 1.1), "",
		"[ps_lobby_place_" .. place.name .. "]", "map = " .. place.map,
		"host_position = " .. place.pos, "host_rotation = " .. place.rot }
	for _, k in ipairs({ "camera", "close", "close_3" }) do
		if place[k] then t[#t + 1] = k .. " = " .. place[k] end
	end
	return table.concat(t, "\r\n") .. "\r\n"
end
local function near(v, x, y, z)
	return v and math.abs(v.x - x) < 0.01 and math.abs(v.y - y) < 0.01 and math.abs(v.z - z) < 0.01
end
local function dev_at(x, y, z, dx, dy, dz)
	device = function()
		return { time_continual = function() return 1 end, pause = function() end,
			cam_pos = vector():set(x, y, z), cam_dir = vector():set(dx, dy, dz) }
	end
end
local keep_device = device
FILES[marker] = master_core_text.encode({ t = os.time() })
-- the host at 10, 0, 20 facing south: the camera 4 m in front of it, looking back at it, 10 degrees down
FILES[cam_file] = cam_ltx({ name = "t", map = "fake_start", pos = "10, 0, 20", rot = "180",
	camera = "0, 1.5, 4, 180, -10", close = "0.5, 1, 1.5, 180, 0", close_3 = "0, 2, 2, 180, 0" })
CAM = {}
DIRS = {}
NPCS = {} -- the last lobby's stand-ins went with its level
start_game()
check(LOBBY.is_active() and CAM.mode == nil and near(CAM.pos, 10, 1.5, 16) and CAM.hp and math.abs(CAM.hp.x) < 0.001
	and math.abs(CAM.hp.y + math.rad(10)) < 0.001,
	"a place: the camera from the host's slot, turned by host_rotation, forced, free look not engaged")
local function cmd_count(s)
	local n = 0
	for _, c in ipairs(CMDS) do if c == s then n = n + 1 end end
	return n
end
check(cmd_count("show_actor_body 2") == 1 and CAM.hud_draw == false,
	"a camera config: the character model is drawn, the first-person hands are not")
local fd2 = DIRS[#DIRS]
check(fd2 and math.abs(math.abs(fd2.h) - math.pi) < 0.001, "the bodies face the place's host_rotation (south)")
check(math.abs(ACTOR_POS.x - 10) < 0.01 and math.abs(ACTOR_POS.z - 20) < 0.01, "the host stands on host_position")
local xs2 = {}
for _, o in pairs(NPCS) do xs2[#xs2 + 1] = string.format("%.1f", o.pos.x) end
table.sort(xs2)
check(table.concat(xs2, ",") == "11.1,12.2,13.3,14.4", "the other slots spacing apart, to the host's left: " .. table.concat(xs2, ","))
local c2, c3 = LOBBY.close_for(2), LOBBY.close_for(3)
check(near(c2, 10.6, 1, 18.5) and math.abs(c2.h) < 0.001 and near(c3, 12.2, 2, 18),
	"each close-up is relative to its own slot, and close_3 overrides slot 3's")
-- the camera on screen, recorded relative to the host's slot
dev_at(10, 2, 17, 0, 0, 1)
LOBBY.snapshot()
local saved = FILES[cam_file]
check(saved:find("camera = 0, 2, 3, 180, 0", 1, true) and saved:find("a comment that must stay", 1, true)
	and saved:find("lim_zoom", 1, true) and saved:find("close_3 = 0, 2, 2, 180, 0", 1, true),
	"snapshot writes the camera relative to the host's slot, the rest of the file as it was")
NOW = NOW + 100
fire("actor_on_update")
check(near(CAM.pos, 10, 2, 17) and math.abs(CAM.hp.x) < 0.001 and math.abs(CAM.hp.y) < 0.001,
	"the recorded pose is the camera on the next update")
dev_at(9, 1.2, 18, 0, 0, 1)
LOBBY.snapshot("close")
dev_at(12, 1, 18, 0, 0, 1)
LOBBY.snapshot("close", 3)
device = keep_device
local both = FILES[cam_file]
check(both:find("camera = 0, 2, 3, 180, 0", 1, true) and both:find("close = 1, 1.2, 2, 180, 0", 1, true)
	and both:find("close_3 = 0.2, 1, 2, 180, 0", 1, true),
	"snapshot(\"close\") records the close-up from this slot, snapshot(\"close\", 3) slot 3's own")
check(near(LOBBY.close_for(2), 10.1, 1.2, 18), "slot 2's close-up is the same pose from slot 2")
-- tuning the spacing moves the slots and their close-ups
LOBBY.tune("spacing", 2)
check(near(LOBBY.close_for(2), 11, 1.2, 18), "tune(\"spacing\", 2): slot 2 two metres from the host")
LOBBY.tune("spacing", 1.1)
local lw2 = LOBBY.GUI
click(lw2, "btn_change")
check(near(CAM.pos, 10, 2, 17), "the close-up starts at the lineup camera")
NOW = NOW + 150
fire("actor_on_update")
check(near(CAM.pos, 9.5, 1.6, 17.5), "the camera is halfway after 0.15 s")
NOW = NOW + 150
fire("actor_on_update")
check(near(CAM.pos, 9, 1.2, 18), "Change profile reaches this slot's close-up after 0.3 s")
local function hidden_models()
	local n, inv = 0, 0
	for _, o in pairs(NPCS) do
		if o.bone_vis == false then n = n + 1 end
		if o.visual and o.visual:find("invisible", 1, true) then inv = inv + 1 end
	end
	return n, inv
end
local hid, inv = hidden_models()
check(hid == 4 and inv == 4, "the close-up hides the other four models on this machine")
lw2:OnKeyboard("DIK_ESCAPE", "WINDOW_KEY_PRESSED")
NOW = NOW + 300
fire("actor_on_update")
hid, inv = hidden_models()
check(near(CAM.pos, 10, 2, 17) and hid == 0 and inv == 0, "leaving the editor returns to the lineup and shows the other models")
end_game()
check(cmd_count("show_actor_body 0") == 1, "leaving the lobby restores show_actor_body")
-- the place helper: frames as Private Backrooms' doors
local fr = PLACE.frame(1, 2, 3, 90)
local wx, wy, wz = PLACE.to_world(fr, 1, 0, 2)
local r, u, f = PLACE.to_local(fr, wx, wy, wz)
check(math.abs(wx - 3) < 1e-6 and math.abs(wz - 2) < 1e-6 and math.abs(r - 1) < 1e-6 and math.abs(u) < 1e-6 and math.abs(f - 2) < 1e-6,
	"place: yaw 90 faces east, its right is south; to_local undoes to_world")
local dx, dy, dz = PLACE.dir_world(fr, 30, 20)
local yw, pt = PLACE.dir_local(fr, dx, dy, dz)
check(math.abs(yw - 30) < 1e-6 and math.abs(pt - 20) < 1e-6, "place: a direction's yaw and pitch round-trip")
local edited = PLACE.set_key("; c\r\n[a]\r\nx = 1\r\n\r\n[b]\r\ny = 2\r\n", "a", "z", "3")
edited = PLACE.set_key(edited, "b", "y", "5")
edited = PLACE.set_key(edited, "c", "w", "6")
check(edited == "; c\r\n[a]\r\nx = 1\r\nz = 3\r\n\r\n[b]\r\ny = 5\r\n\r\n[c]\r\nw = 6\r\n",
	"place: set_key adds to a section, replaces a key, adds a section, and keeps the rest")
-- hand tuning: the place moved while the lobby runs, logged, saved
local function logged_plain(text)
	for _, l in ipairs(LOG) do
		if l:find(text, 1, true) then return true end
	end
	return false
end
FILES[marker] = master_core_text.encode({ t = os.time() })
FILES[cam_file] = cam_ltx({ name = "t", map = "fake_start", pos = "10, 0, 20", rot = "180",
	camera = "0, 1.5, 4, 180, -10", close = "0.5, 1, 1.5, 180, 0" })
CAM = {}
NPCS = {}
start_game()
LT.host_move(1, 0, 0)
NOW = NOW + 100; fire("actor_on_update")
check(math.abs(ACTOR_POS.x - 11) < 0.01 and logged_plain("host_position = 11, 0, 20") and near(CAM.pos, 11, 1.5, 16),
	"host_move(1, 0, 0): the host a metre to the screen's right, the camera with it, logged")
LT.cam_move(0, 0.5, 1)
NOW = NOW + 100; fire("actor_on_update")
check(near(CAM.pos, 11, 2, 17) and logged_plain("camera = 0, 2, 3, 180, -10"), "cam_move(0, 0.5, 1): the camera up, and toward where it looks")
LT.cam_turn(10, 5)
check(logged_plain("camera = 0, 2, 3, 190, -5"), "cam_turn(10, 5): turned right and up")
LT.set_spacing(2)
NOW = NOW + 100; fire("actor_on_update")
local xs3 = {}
for _, o in pairs(NPCS) do xs3[#xs3 + 1] = string.format("%.1f", o.pos.x) end
table.sort(xs3)
check(table.concat(xs3, ",") == "13.0,15.0,17.0,19.0" and logged_plain("spacing = 2"), "set_spacing(2): the stand-ins two metres apart: " .. table.concat(xs3, ","))
LT.host_turn(90)
check(logged_plain("host_rotation = 270"), "host_turn(90): the host turned right")
LT.host_turn(-90)
DEV_DEBUG = true
local lw3 = LOBBY.GUI
lw3:OnKeyboard("DIK_F7", "WINDOW_KEY_PRESSED")
check(LT.tuning_on() and logged_plain("tuning host"), "F7 (debug mode): tuning on, the host first")
lw3:OnKeyboard("DIK_RIGHT", "WINDOW_KEY_PRESSED")
check(logged_plain("host_position = 11.1, 0, 20"), "right arrow: the host 0.1 m to the screen's right")
lw3:OnKeyboard("DIK_TAB", "WINDOW_KEY_PRESSED")
lw3:OnKeyboard("DIK_TAB", "WINDOW_KEY_PRESSED")
check(LOBBY.previewing() and logged_plain("tuning close"), "Tab, Tab: the close-up, Change profile opened to show it")
lw3:OnKeyboard("DIK_PRIOR", "WINDOW_KEY_PRESSED")
check(logged_plain("close = 0.5, 1.1, 1.5, 180, 0"), "Page Up: the close-up 0.1 m up")
lw3:OnKeyboard("DIK_RETURN", "WINDOW_KEY_PRESSED")
local sv = FILES[cam_file]
check(sv:find("host_position = 11.1, 0, 20", 1, true) and sv:find("host_rotation = 180", 1, true)
	and sv:find("camera = 0, 2, 3, 190, -5", 1, true) and sv:find("close = 0.5, 1.1, 1.5, 180, 0", 1, true)
	and sv:find("spacing = 2", 1, true) and sv:find("a comment that must stay", 1, true),
	"Enter saves the place into the config, the rest of the file as it was")
lw3:OnKeyboard("DIK_F7", "WINDOW_KEY_PRESSED")
check(not LT.tuning_on() and not LOBBY.previewing(), "F7 again: tuning off, Change profile closed")
DEV_DEBUG = false
lw3:OnKeyboard("DIK_F7", "WINDOW_KEY_PRESSED")
check(not LT.tuning_on(), "without debug mode F7 does nothing")
LOBBY.tune("spacing", 1.1)
end_game()
-- a config that cannot be read: free look
FILES[marker] = master_core_text.encode({ t = os.time() })
FILES[cam_file] = "{"
CAM = {}
local bodies_before = cmd_count("show_actor_body 2")
start_game()
check(CAM.mode == 2 and CAM.pos == nil and logged("the camera config could not be read") and cmd_count("show_actor_body 2") == bodies_before,
	"a camera config that cannot be read: free look, as with no file")
end_game()
FILES[cam_file] = ""
FILES[marker] = ""
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
-- the main menu never starts the lobby; Start the lobby is the button
KEYPRESS = true
FILES[marker] = ""
local n_auto = #CMDS
local mm_stay = MM.main_menu()
mm_stay:Update()
local started = false
for i = n_auto + 1, #CMDS do if CMDS[i]:find("^start server") then started = true end end
check(not started and KEYPRESS == true and mm_stay.pst_panel.btn_lobby:TextControl():GetText() == "Start the lobby",
	"the main menu stays: the lobby starts only from its button")
FILES[marker] = ""
SETCFG.new_game_test = nil
FILES["app/persistent_stalkers_keypress.txt"] = ""
start_game()
LEVEL_NAME = "l01_escape"

print("-- 12b. the lobby in Cordon (ps_lobby.spawn puts the actor at the rookie village)")
end_game()
FILES[marker] = master_core_text.encode({ t = os.time() })
-- the config has a place on fake_start only
FILES[cam_file] = cam_ltx({ name = "fs", map = "fake_start", pos = "0, 0, 0", rot = "180", camera = "0, 1.5, 4, 180, 0" })
CAM = {}
local function fire_at(dx)
	local f = { on = false }
	f.is_on = function(self) return self.on end
	f.turn_on = function(self) self.on = true end
	return { object = { position = function() return { x = ACTOR_POS.x + dx, y = 0, z = ACTOR_POS.z } end }, campfire = f }
end
local near_fire, far_fire = fire_at(4), fire_at(100)
bind_campfire = { campfires_all = { [901] = near_fire, [902] = far_fire } }
start_game()
check(LOBBY.is_active() and LOBBY.lobby_game(), "a lobby game on l01_escape: the lobby starts there")
check(C.get_phase() == "idle" and C.lobby_game(), "the core is idle in the lobby on a real level")
check(C.write("check") == false, "nothing is written from the lobby on a real level")
check(CAM.mode == 2 and CAM.pos == nil and logged("no place for l01_escape in the config"),
	"no place on this map: free look, the place on fake_start is not used")
NOW = NOW + 100; fire("actor_on_update")
check(near_fire.campfire.on == true and far_fire.campfire.on == false, "the campfire near the row is lit, a far one is not")
near_fire.campfire.on = false
NOW = NOW + 3100; fire("actor_on_update")
check(near_fire.campfire.on == true, "a campfire put out is lit again")
check(PLACE.add("cordon") == true, "place.add writes a place here")
local cordon = FILES[cam_file]
check(cordon:find("[ps_lobby_place_cordon]\r\nmap = l01_escape\r\nhost_position = ", 1, true) and cordon:find("host_rotation = 0", 1, true)
	and cordon:find("camera = 0, 1.5, 4, 180, 0", 1, true) and cordon:find("place = cordon", 1, true)
	and cordon:find("[ps_lobby_place_fs]", 1, true),
	"place.add: this map, your position and yaw, the selected place's camera copied, and it is selected")
check(PLACE.choose("fs") == true and FILES[cam_file]:find("place = fs", 1, true) and PLACE.choose("nope") == false,
	"place.choose selects a place in the config, and refuses one that is not")
-- the relations table set again by the file's own column order (Anomaly's
-- reset_all_relations reads it shifted)
local REL = {}
relation_registry = { set_community_relation = function(a, b, v) REL[a .. "|" .. b] = v end,
	community_relation = function(a, b) return REL[a .. "|" .. b] end }
local REL_INI = { game_relations = { communities = "actor, 0, monster, 1, trader, 2, stalker, 3" },
	communities_relations = { actor = "0, -2000, 0, 0", monster = "-2000, 0, 0, -2000", trader = "0, 0, 0, 0",
		stalker = "0,	-2000,  0, 300" } }
ini_file = function(name)
	return { r_string_ex = function(_, sec, key) return name == "creatures\\game_relations.ltx" and REL_INI[sec] and REL_INI[sec][key] or nil end }
end
check(LOBBY.fix_relations() == 16 and REL["stalker|stalker"] == 300 and REL["stalker|monster"] == -2000 and REL["monster|stalker"] == -2000
	and REL["actor|monster"] == -2000 and REL["stalker|trader"] == 0,
	"the relations: every pair set by the file's column order (loners friendly to loners)")
relation_registry, ini_file = nil, nil
LOBBY.stop()
check(not LOBBY.lobby_game(), "the lobby stopped: no longer a lobby game")
exec_console_cmd("save user - autosave")
check(CMDS[#CMDS] == "save user - autosave", "left the lobby: a save is not held")
exec_console_cmd("save user - quicksave_1")
check(CMDS[#CMDS] == "save user - quicksave_1", "left the lobby: a quicksave is not held")
save_flags = { ret = false }
fire("on_before_save_input", save_flags, 2, "save")
check(save_flags.ret ~= true, "left the lobby: a quicksave key is not refused")
end_game()
bind_campfire = nil
FILES[cam_file] = ""
FILES[marker] = ""
start_game()
LEVEL_NAME = "l01_escape"

do
print("-- 12c. a place on another map: the lobby changes level first (one spawn for every place)")
end_game()
FILES[marker] = master_core_text.encode({ t = os.time(), last = "mysave" })
FILES[cam_file] = cam_ltx({ name = "bar", map = "l05_bar", pos = "100, 0, 50", rot = "90", camera = "0, 1.5, 4, 180, 0" })
FILES[cam_file] = FILES[cam_file] .. "spacing = 2.5\r\n" -- the bar's own spacing (the general one is 1.1)
local VERTS = { { lvl = 1, p = { x = 100, y = 0, z = 50 }, lv = 11 }, { lvl = 5, p = { x = 300, y = 0, z = 50 }, lv = 51 },
	{ lvl = 5, p = { x = 102, y = 0, z = 49 }, lv = 52 } }
game_graph = function()
	return { valid_vertex_id = function(_, i) return VERTS[i + 1] ~= nil end,
		vertex = function(_, i)
			local v = VERTS[i + 1]
			return { level_id = function() return v.lvl end, level_point = function() return v.p end,
				level_vertex_id = function() return v.lv end }
		end }
end
local LEVEL_IDS = { [1] = "l01_escape", [5] = "l05_bar" }
local alife_before_travel = alife
alife = function() return { level_name = function(_, id) return LEVEL_IDS[id] end } end
local TRAVEL
ChangeLevel = function(pos, lvid, gvid, dir) TRAVEL = { pos = pos, lvid = lvid, gvid = gvid } end
VEC_ZERO = vector()
-- the saves folder: the player's own autosave, and a quicksave
local SAVEDIR = { ["player - autosave.scop"] = "real", ["player - autosave.scoc"] = "real", ["quick.scop"] = "q" }
local fs_before_travel = getFS
getFS = function()
	local f = fs_before_travel()
	local list, exist = f.file_list_open_ex, f.exist
	f.file_list_open_ex = function(self, root, flags, pattern)
		if root == "$game_saves$" and pattern == "*" then
			local names = {}
			for n in pairs(SAVEDIR) do names[#names + 1] = n end
			table.sort(names)
			return { Size = function() return #names end, GetAt = function(_, i) return { NameFull = function() return names[i + 1] end } end }
		end
		return list(self, root, flags, pattern)
	end
	f.exist = function(self, alias, n)
		if alias == "$game_saves$" then return SAVEDIR[n] ~= nil end
		return exist(self, alias, n)
	end
	f.file_rename = function(_, a, b) a, b = a:gsub("^app/", ""), b:gsub("^app/", ""); SAVEDIR[b] = SAVEDIR[a]; SAVEDIR[a] = nil end
	f.file_delete = function(_, alias, n) SAVEDIR[n] = nil end
	return f
end
LEVEL_NAME = "l01_escape"
start_game()
check(TRAVEL and TRAVEL.gvid == 2 and TRAVEL.lvid == 52 and not LOBBY.is_active() and LOBBY.lobby_game() and C.get_phase() == "idle",
	"the selected place is on another map: a level change to its map's vertex nearest the host, the lobby not started, the core idle")
local mk = FILES[marker] ~= "" and master_core_text.decode(FILES[marker])
check(mk and mk.travelled == "l05_bar" and mk.last == "mysave", "the marker is written again, marked travelled, the last save kept")
check(SAVEDIR["player - autosave.scop.ps_keep"] == "real" and SAVEDIR["player - autosave.scoc.ps_keep"] == "real" and not SAVEDIR["player - autosave.scop"]
	and SAVEDIR["quick.scop"] == "q", "before the level change the player's autosave is set aside, other saves untouched")
-- the engine's level change: it saves the lobby's world as the autosave and loads it
SAVEDIR["Player - autosave.scop"], SAVEDIR["Player - autosave.scoc"] = "lobby", "lobby"
-- the arrival: the level goes, the same Lua, the Bar's first update
fire("actor_on_net_destroy")
TRAVEL = nil
LEVEL_NAME = "l05_bar"
fire("actor_on_first_update")
check(C.get_phase() == "idle" and LOBBY.lobby_game(), "arrived: still a lobby game, the core idle")
for i = 1, 10 do NOW = NOW + 100; fire("actor_on_update") end
check(LOBBY.is_active() and TRAVEL == nil and FILES[marker] == "" and near(ACTOR_POS, 100, 0, 50),
	"arrived: the lobby starts on the place's host spot, no second level change, the marker used up")
check(SAVEDIR["player - autosave.scop"] == "real" and SAVEDIR["player - autosave.scoc"] == "real" and not SAVEDIR["Player - autosave.scop"]
	and not SAVEDIR["player - autosave.scop.ps_keep"] and SAVEDIR["quick.scop"] == "q",
	"arrived: the lobby's autosave is deleted and the player's is back")
-- a level change that never arrived (a crash on the way): the main menu puts it back
SAVEDIR = { ["player - autosave.scop"] = "real" }
check(persistent_stalkers_lobby_boot.keep_autosaves() and SAVEDIR["player - autosave.scop.ps_keep"] == "real", "set aside again")
SAVEDIR["Player - autosave.scop"] = "lobby"
persistent_stalkers_lobby_boot.main_menu_check()
check(SAVEDIR["player - autosave.scop"] == "real" and not SAVEDIR["Player - autosave.scop"] and not SAVEDIR["player - autosave.scop.ps_keep"],
	"a level change that never arrived: the main menu deletes the lobby's autosave and puts the player's back")
check(LOBBY.TUNE.spacing == 2.5, "a place's own spacing is used over the general one")
LOBBY.stop()
-- the place on this map: no level change
end_game()
FILES[marker] = master_core_text.encode({ t = os.time() })
start_game()
check(TRAVEL == nil and LOBBY.is_active(), "the place on the map the spawn starts on: no level change, the lobby starts")
LOBBY.stop()
end_game()
game_graph, ChangeLevel, VEC_ZERO = nil, nil, nil
getFS = fs_before_travel
alife = alife_before_travel
FILES[cam_file] = ""
FILES[marker] = ""
end
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
load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
check(axr_main.callback_set == plain and not persistent_stalkers_lobby_boot.isolation(), "no marker: callbacks are not wrapped")
-- the new game started from enter(): a fresh marker when the script loads
FILES[marker] = master_core_text.encode({ t = os.time() })
local ISO = load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
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
load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
check(axr_main.callback_set == set_now, "wrapped only once")
-- our axr_main asks startup_skip() before any script starts
-- the engine loads a script when it is first named: _G's __index
local G_MT_OLD = getmetatable(_G)
local UI_MCM_OLD = rawget(_G, "ui_mcm"); rawset(_G, "ui_mcm", nil)
local FAKE_MCM = { gather_options = function() return pst_test_skipped, pst_test_kept end, get = function(id) FAKE_MCM_ASKED = (FAKE_MCM_ASKED or 0) + 1; if id == "kept/x" then return 3 end end }
local seen = {}
setmetatable(_G, { __index = function(t, k)
	if k == "pst_test_kept" or k == "pst_test_skipped" then
		seen[k] = (seen[k] or 0) + 1
		return { loaded = k, on_mcm_load = function(options)
			if type(options) == "table" then options[#options + 1] = { id = k } end
		end }
	elseif k == "ui_mcm" then
		return FAKE_MCM
	end
end })
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
-- a skipped mod's setting is read live from axr_options, typed by the snapshot
local rv_old = axr_main.config.r_value
local LIVE = { ["stealth/memory"] = 0.75 }
axr_main.config.r_value = function(_, sec, k, typ, def) if sec == "mcm" and typ == 2 and LIVE[k] ~= nil then return LIVE[k] end return def end
check(ui_mcm.get("stealth/memory") == 0.75 and ui_mcm.get("a/b") == true, "a skipped mod's setting is read live from axr_options (the snapshot gives its type and the default)")
-- the lobby gathers every page in the background, a slice per update, from the
-- first update. The click finishes whatever is left. Nothing is blocked.
local fs_old = getFS
getFS = function()
	local fs = fs_old()
	local list = fs.file_list_open_ex
	fs.file_list_open_ex = function(self, root, flags, pattern)
		if pattern == "*mcm.script" then
			local names = { "pst_test_skipped.script", "ui_mcm.script", "pst_test_kept.script" }
			return {
				Size = function() return #names end,
				GetAt = function(_, i)
					local n = names[i + 1]
					return { NameShort = function() return n end, Size = function() return 8 end }
				end,
			}
		end
		return list(self, root, flags, pattern)
	end
	return fs
end
FAKE_MCM.init_opt_base = function()
	FAKE_MCM.options = {}
	FAKE_MCM.gather_options()
end
local before_s, before_k = seen.pst_test_skipped or 0, seen.pst_test_kept or 0
check(ISO.mcm_gather_begin() == true, "the lobby starts gathering every MCM page in the background")
local asked_mid = FAKE_MCM_ASKED
check(ISO.mcm_gather_step(0) == true, "one update gathers one script and leaves the rest")
check((seen.pst_test_skipped or 0) > before_s and (seen.pst_test_kept or 0) == before_k,
	"the first slice loads a skipped mod's script (nothing blocked) and stops before the next")
check(ui_mcm.get("stealth/memory") == 0.75 and FAKE_MCM_ASKED == asked_mid,
	"while a slice is paused, a setting is answered without asking MCM")
check(ISO.mcm_gather_all() == true and #FAKE_MCM.options == 2
	and FAKE_MCM.options[1].id == "pst_test_skipped" and FAKE_MCM.options[2].id == "pst_test_kept",
	"opening MCM finishes the gather: both pages, and ui_mcm.script is not one")
check(ISO.mcm_gather_all() == false and ISO.mcm_gather_begin() == false, "every page is gathered once per lobby game")
getFS = fs_old
local asked1 = FAKE_MCM_ASKED
ui_mcm.get("stealth/memory")
check(FAKE_MCM_ASKED == asked1 + 1, "after the full gather, a path MCM did not know before is asked of MCM again")
local g_after = ui_mcm.gather_options()
check(g_after == nil, "a later gather (MCM's own) blocks skipped scripts again")
axr_main.config.r_value = rv_old
ISO.report()
local bl_text = table.concat(LOG, string.char(10), n_bl + 1)
check(bl_text:find("skipped scripts asked for and not loaded: 1", 1, true) and bl_text:find("3x pst_test_skipped", 1, true), "status: the blocked script and how often it was asked for")
check(bl_text:find("every MCM page gathered: true", 1, true), "status: the full MCM was gathered")
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

print("-- 14. a client joining the lobby; player markers off in the lobby")
do
	local L = LOBBY or persistent_stalkers_lobby
	-- xrRazom's MCM overlay and net, faked
	local AUTH, FLUSHED = {}, 0
	local OVERLAY = {}
	local NET = { connected = false, host = true }
	local SELECTED
	rawset(_G, "XrrMcm", function()
		return {
			AuthoritySetBool = function(_, k, v) AUTH[k] = v end,
			AuthorityRemove = function(_, k) AUTH[k] = nil end,
			AuthorityFlush = function() FLUSHED = FLUSHED + 1 end,
			OverlayTag = function(_, k) return OVERLAY[k] ~= nil and 1 or -1 end,
			OverlayBool = function(_, k) return OVERLAY[k] == true end,
		}
	end)
	rawset(_G, "XrrNet", function()
		return { IsConnected = function() return NET.connected end, IsHost = function() return NET.host end }
	end)
	rawset(_G, "XrrPlayers", function()
		return { SendCharacterSelect = function(_, f, m, items) SELECTED = { f, m, items } end }
	end)
	-- the markers' console settings, faked
	local CV = { xrr_show_names = true, xrr_show_marks = true, xrr_show_players_hp = false, xrr_show_net_health = true }
	local old_get, old_exec = get_console_cmd, exec_console_cmd
	get_console_cmd = function(kind, name) if CV[name] ~= nil then return CV[name] end return old_get(kind, name) end
	exec_console_cmd = function(c, ...)
		local n, v = c:match("^(xrr_show_[%w_]+) (%a+)$")
		if n then CV[n] = v == "on" end
		return old_exec(c, ...)
	end
	-- the host's lobby: announced, markers off; stopped: taken back, markers on
	check(LJ.plates_off() == 3 and CV.xrr_show_names == false and CV.xrr_show_marks == false and CV.xrr_show_net_health == false
		and CV.xrr_show_players_hp == false, "markers off: the three that were on")
	check(LJ.announce(true) and AUTH[LJ.LOBBY_KEY] == true and FLUSHED == 1, "the host announces the lobby to the clients")
	check(LJ.announce(false) and AUTH[LJ.LOBBY_KEY] == nil and FLUSHED == 2, "the host takes it back")
	check(LJ.plates_back() == 3 and CV.xrr_show_names == true and CV.xrr_show_marks == true and CV.xrr_show_net_health == true
		and CV.xrr_show_players_hp == false, "markers back: only those that were on")
	check(LJ.plates_back() == 0, "markers back again: nothing to do")
	-- a client: not joining a lobby without the host's flag
	NET.connected, NET.host = true, false
	check(not LJ.joining_lobby(), "a connected client with no lobby flag: not a lobby join")
	OVERLAY[LJ.LOBBY_KEY] = true
	check(LJ.joining_lobby(), "the host's flag in the overlay: a lobby join")
	-- the gear screen
	local cls = { }
	local opened = 0
	cls.ShowFactionUI = function(self) opened = opened + 1 end
	local old_mm = rawget(_G, "ui_main_menu")
	rawset(_G, "ui_main_menu", { main_menu = cls })
	LJ.guard_faction_ui()
	local wrapped = cls.ShowFactionUI
	LJ.guard_faction_ui()
	check(cls.ShowFactionUI == wrapped, "the gear screen is wrapped once")
	cls.ShowFactionUI({})
	check(opened == 0 and SELECTED and SELECTED[1] == "stalker" and SELECTED[2] == 0 and SELECTED[3] == "",
		"a lobby join: no gear screen, a loner with no kit is sent")
	OVERLAY[LJ.LOBBY_KEY] = nil
	-- a save that does not know this client: the profile is the character
	local PR = persistent_stalkers_profile
	local keep_sel = PR.selected_profile()
	PR.choose(PR.NONE)
	SELECTED = nil
	cls.ShowFactionUI({})
	check(opened == 1 and SELECTED == nil, "a join with None selected: the gear screen opens")
	FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 3,
		character = { faction = "actor_dolg", money = 10, items = { { section = "wpn_rifle", slot = 3 } } } })
	PR.choose("alt")
	SELECTED = nil
	cls.ShowFactionUI({})
	check(opened == 1 and SELECTED and SELECTED[1] == "dolg" and SELECTED[2] == 0 and SELECTED[3] == ""
		and logged_plain("joining as alt (applied on arrival): the gear screen is skipped (dolg, no kit)"),
		"a join with a profile: no gear screen, the profile's faction, no kit (the arrival applies the profile)")
	FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 0 })
	PR.choose("alt")
	SELECTED = nil
	cls.ShowFactionUI({})
	check(opened == 2 and SELECTED == nil, "a join with an empty profile: the gear screen opens (it adopts the kit picked)")
	NET.connected = false
	FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 3, character = { faction = "stalker" } })
	PR.choose("alt")
	SELECTED = nil
	cls.ShowFactionUI({})
	check(opened == 3 and SELECTED == nil, "not a connected client (a solo new game): the faction select as usual")
	NET.connected = true
	PR.choose(keep_sel)
	rawset(_G, "ui_main_menu", old_mm)
	-- the client's load: its own marker
	FILES[marker] = ""
	OVERLAY[LJ.LOBBY_KEY] = true
	KEYPRESS = true
	exec_console_cmd("start server(all/single/alife/new) client(localhost)")
	local mk = FILES[marker] ~= "" and master_core_text.decode(FILES[marker])
	check(type(mk) == "table" and mk.client == true and mk.kp == true and KEYPRESS == false,
		"a lobby join's load writes a client marker and switches \"press any key\" off")
	OVERLAY[LJ.LOBBY_KEY] = nil
	FILES[marker] = ""
	exec_console_cmd("start server(all/single/alife/new) client(localhost)")
	check(FILES[marker] == "", "a normal join's load writes none")
	-- a selected profile's nameplate goes to the host and every client, and a
	-- received one is shown on that player's spot
	local old_session, old_host, old_send = master_core_net.session, master_core_net.is_host, master_core_net.send_table
	local old_nick, old_nick_of = master_core_net.nick, master_core_net.nick_of
	local sent = {}
	master_core_net.session = function() return true end
	master_core_net.is_host = function() return false end
	master_core_net.nick = function() return "Mee" end
	master_core_net.nick_of = function(s) if s == "host" then return "Host" elseif s == "2" then return "Bee" end end
	master_core_net.send_table = function(n, target, t) sent[#sent + 1] = { n = n, target = target, t = t }; return true end
	LEVEL_NAME = "fake_start"
	P.choose("alt")
	start_game()
	local lobby_ev = CB["net_pst_lobby"] and CB["net_pst_lobby"][1]
	check(type(lobby_ev) == "function" and type(CB["net_pst_lobby_card"][1]) == "function", "the lobby listens for a nameplate")
	lobby_ev(master_core_text.encode({
		x = 10, y = 0, z = 20, fx = 0, fz = 1, order = { "Host", "Mee", "Bee" },
		cards = {
			Host = { profile = "alpha", faction = "Loner" },
			Mee = { profile = "alt", faction = "stalker", class = "sniper" },
			Bee = { profile = "old", faction = "Bandit" },
		},
	}), "host")
	local plates = L.GUI
	plates:PlacePlates()
	local function plate(i) return plates.plates[i] and plates.plates[i].text or "" end
	check(plate(1):find("Host") and plate(1):find("<alpha>") and plate(1):find("Loner")
		and plate(3):find("Bee") and plate(3):find("<old>"),
		"the host's broadcast puts each nameplate on its spot: " .. plate(1) .. " | " .. plate(3))
	CB["net_pst_lobby_card"][1](master_core_text.encode({ nick = "Bee", card = { profile = "nova", faction = "Freedom", class = "medic" } }), "2")
	plates:PlacePlates()
	check(plate(3):find("Bee") and plate(3):find("<nova>") and plate(3):find("Freedom") and plate(3):find("medic"),
		"a nameplate message updates that player: " .. plate(3))
	sent = {}
	L.selected("alt")
	check(#sent == 1 and sent[1].n == "pst_lobby_card" and sent[1].target == nil
		and sent[1].t.nick == "Mee" and sent[1].t.card and sent[1].t.card.profile == "alt",
		"selecting a profile sends the nameplate to the host and every client")
	-- the host broadcasts its card every couple of seconds: a row tried on
	-- must stay off that broadcast until Done
	master_core_net.is_host = function() return true end
	sent = {}
	plates:BeginEdit()
	if plates.panel then plates.panel.chosen = "default" end
	NOW = NOW + 100
	fire("actor_on_update")
	local saw, leaked = false, false
	for _, s in ipairs(sent) do
		if s.n == "pst_lobby_card" then leaked = true end
		local mine = s.n == "pst_lobby" and s.t and s.t.cards and s.t.cards.Mee
		if mine then
			saw = true
			if mine.profile ~= "alt" then leaked = true end
		end
	end
	check(saw and not leaked, "trying a profile on does not change the nameplate until Done")
	plates:EndEdit(false)
	master_core_net.session, master_core_net.is_host, master_core_net.send_table = old_session, old_host, old_send
	master_core_net.nick, master_core_net.nick_of = old_nick, old_nick_of
	L.stop()
	-- the client's new game reads it: the whole game is the lobby
	FILES[marker] = master_core_text.encode({ t = os.time(), client = true })
	local L2 = load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
	check(L2.CLIENT_LOBBY == true and L.lobby_game(), "a client's lobby game: the core sees a lobby for the whole game")
	FILES[marker] = ""
	get_console_cmd, exec_console_cmd = old_get, old_exec
	rawset(_G, "XrrMcm", nil)
	rawset(_G, "XrrNet", nil)
	rawset(_G, "XrrPlayers", nil)
end

print("-- 15. the new game screen with a profile")
do
	local PR = persistent_stalkers_profile
	local keep_sel = PR.selected_profile()
	local NG = load_script(ROOT_V2, "persistent_stalkers_newgame")
	-- G.A.M.M.A.'s UINewGame, faked: the methods the wrap touches, as they call each other
	local function txt()
		local t = { text = "" }
		function t:SetText(s) self.text = s end
		function t:GetText() return self.text end
		function t:AdjustHeightToText() end
		function t:SetWndSize() end
		function t:GetWidth() return 100 end
		function t:GetHeight() return 100 end
		function t:SetAutoDelete() end
		return t
	end
	local function cc()
		local c = { items = {}, shown = true }
		function c:Reinit(t) self.items = t end
		function c:Show(v) self.shown = v end
		return c
	end
	local K = {}
	function K.OnFactionClicked(self) self.popup = true end
	function K.LoadFaction(self, rand, faction)
		self.selected_faction = faction or "stalker"
		self.selected_money = 500
		self:UpdateMoney()
	end
	function K.LoadMap(self) self.maps = self.selected_faction .. "_start_locations" end
	function K.LoadLoadout(self) self.CC.inventory:Reinit({ "wpn_pm", "bread" }) end
	function K.UpdateMoney(self) self.text_money:SetText(self.selected_money .. " RU") end
	function K.UpdateDescr(self) self.text_descr:SetText("st_faction_" .. self.selected_faction .. "_desc") end
	function K.UpdateAll(self, rand, faction)
		self:LoadFaction(rand, faction)
		self:LoadMap(rand)
		self:UpdateDescr()
		self:LoadLoadout(rand)
	end
	function K.OnFactionSelect(self, f) self.selected_faction = f; self:UpdateAll(false, f) end
	function K.OnRandomize(self)
		local n = 0
		for _ in pairs(self.table_faction) do n = n + 1 end
		self.seen_factions = n
		self.selected_faction = next(self.table_faction)
		self:UpdateAll(true, self.selected_faction)
	end
	local made = 0
	setmetatable(K, { __call = function(_, owner)
		made = made + 1
		local d = setmetatable({ owner = owner, table_faction = { stalker = true, bandit = true, dolg = true },
			CC = { inventory = cc(), loadout = cc() }, text_money = txt(), text_descr = txt(),
			text_points_used = txt(), text_points_left = txt() }, { __index = K })
		d.cb_faction = d.OnFactionClicked -- AddCallback takes the method when the dialog is made
		function d:ShowDialog() self.shown = true end
		d:UpdateAll(false)
		return d
	end })
	local old_fs = ui_mm_faction_select
	ui_mm_faction_select = { UINewGame = K }
	local owner = { HideDialog = function() end, Show = function() end }
	local show = (ui_main_menu or MM).main_menu.ShowFactionUI
	-- None: the screen as it is
	PR.choose(PR.NONE)
	show(owner)
	local d = owner.new_game_dlg
	check(d and NG.WRAPPED == K and #d.CC.inventory.items == 2 and d.text_money.text == "500 RU" and not d.pst_lock,
		"None: the new game screen as it is (loadout, money)")
	d.cb_faction(d)
	check(d.popup == true, "None: the faction can be picked")
	-- a profile with a character: the faction is the profile's, no loadout
	FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 3,
		character = { faction = "actor_dolg", money = 1234, items = { { section = "wpn_rifle", slot = 3 } } } })
	PR.choose("alt")
	show(owner)
	local d2 = owner.new_game_dlg
	check(d2 ~= d and made == 2, "a profile selected since: a new dialog is made")
	check(d2.pst_lock and d2.selected_faction == "dolg" and d2.maps == "dolg_start_locations",
		"alt: the profile's faction (dolg), and its start locations")
	check(#d2.CC.inventory.items == 0 and d2.CC.inventory.shown == false and d2.CC.loadout.shown == false
		and d2.text_points_left.text == "-", "alt: the loadout is empty and hidden")
	check(d2.text_money.text == "1234 RU", "alt: the money shown is the profile's")
	local head, body = d2.text_descr.text:find("st_ps_newgame_head", 1, true), d2.text_descr.text:find("st_ps_newgame_body", 1, true)
	local fdesc = d2.text_descr.text:find("st_faction_dolg_desc", 1, true)
	check(head and body and fdesc and head < body and body < fdesc,
		"alt: the description says the profile is played, the faction's description under it")
	d2.cb_faction(d2)
	check(not d2.popup, "alt: the faction button does nothing")
	d2:OnFactionSelect("bandit")
	check(d2.selected_faction == "dolg", "alt: another faction cannot be selected")
	d2:OnRandomize()
	local n = 0
	for _ in pairs(d2.table_faction) do n = n + 1 end
	check(d2.selected_faction == "dolg" and d2.seen_factions == 1 and n == 3 and #d2.CC.inventory.items == 0,
		"alt: Randomize keeps the faction and the empty loadout; the faction table is put back")
	show(owner)
	check(owner.new_game_dlg == d2 and made == 2, "shown again with the same profile: the same dialog")
	-- an empty profile adopts the new game's character: the screen as it is
	FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 0 })
	PR.choose("alt")
	show(owner)
	local d3 = owner.new_game_dlg
	check(d3 ~= d2 and not d3.pst_lock and #d3.CC.inventory.items == 2 and d3.text_money.text == "500 RU",
		"an empty profile: a new dialog, the screen as it is")
	d3:OnFactionSelect("bandit")
	check(d3.selected_faction == "bandit", "an empty profile: any faction")
	-- a profile with an unknown faction: a loner
	FILES["app/persistent_stalkers_profile_alt.txt"] = master_core_text.encode({ version = 1, revision = 3,
		character = { faction = "actor_monster", money = 5 } })
	PR.choose("alt")
	show(owner)
	check(owner.new_game_dlg.selected_faction == "stalker", "a faction the screen does not know: a loner")
	ui_mm_faction_select = old_fs
	PR.choose(keep_sel)
end

print("-- 16. a new game from the lobby: the new game screen's choices carried")
do
	local L = LB
	local CC = { new_game_faction = "dolg", new_game_map = "dolg_start_1", new_game_money = "1000",
		new_game_story_mode = "true", new_game_test = "", new_game_icon = "" }
	local saved = 0
	local old_cfg = axr_main.config
	axr_main.config = {
		collect_section = function(_, sec) local t = {} for k, v in pairs(CC) do t[k] = v end return t end,
		r_value = function(_, sec, k) local v = CC[k]; if v == "" then return nil end return v end,
		w_value = function(_, sec, k, v) CC[k] = v ~= nil and tostring(v) or "" end,
		save = function() saved = saved + 1 end,
	}
	local path = L.carry_path()
	FILES[path] = ""
	check(L.carry_new_game() == 4, "the lobby's StartGame carries the four set values (not the test switch, not empty ones)")
	local t = master_core_text.decode(FILES[path])
	check(type(t) == "table" and t.keys.new_game_faction == "dolg" and t.keys.new_game_map == "dolg_start_1"
		and t.keys.new_game_test == nil, "the carry file holds them")
	-- the next game: axr_options lost them
	for k in pairs(CC) do CC[k] = "" end
	local old_alife = alife
	alife = function() return {} end
	check(L.carry_back() == true and CC.new_game_faction == "dolg" and CC.new_game_map == "dolg_start_1"
		and CC.new_game_money == "1000" and saved >= 1 and FILES[path] == "",
		"the next game puts them back before the scripts read them, and uses the file up")
	check(L.carry_back() == false, "once only")
	-- axr_options kept them: nothing put back
	FILES[path] = master_core_text.encode({ t = os.time(), keys = { new_game_faction = "army" } })
	check(L.carry_back() == false and CC.new_game_faction == "dolg", "axr_options has a faction: it is left")
	-- a main menu between: fills the config, keeps the file for the game
	CC.new_game_faction = ""
	alife = function() return nil end
	FILES[path] = master_core_text.encode({ t = os.time(), keys = { new_game_faction = "army" } })
	check(L.carry_back() == true and CC.new_game_faction == "army" and FILES[path] ~= "", "no game yet: put back, the file kept")
	-- stale
	CC.new_game_faction = ""
	FILES[path] = master_core_text.encode({ t = os.time() - 600, keys = { new_game_faction = "army" } })
	check(L.carry_back() == false and CC.new_game_faction == "" and FILES[path] == "", "a stale carry: dropped")
	-- startup_skip runs it first
	alife = function() return {} end
	FILES[path] = master_core_text.encode({ t = os.time(), keys = { new_game_faction = "csky" } })
	L.startup_skip()
	check(CC.new_game_faction == "csky", "axr_main's startup_skip puts them back")
	-- no faction written: logged
	CC = { new_game_map = "x" }
	L.carry_new_game()
	check(logged_plain("the new game screen left no faction in axr_options"), "no faction to carry: logged")
	alife = old_alife
	axr_main.config = old_cfg
	FILES[path] = ""
end

do
	print("-- 31. save mode: a save is followed only in the profile's own world; lobby edits go on top")
	EDITS = {}
	end_game()
	LEVEL_NAME = "l01_escape"
	LOBBY, persistent_stalkers_lobby = nil, nil -- the lobby sections are over: a plain game from here
	HOST = true
	MCM["persistent_stalkers/constant_saves"] = false
	P.set_selected("default")
	ACTOR.faction = "stalker"
	ACTOR.goodwill = { dolg = 300, freedom = -200 }
	-- world A: a new game
	start_game()
	local save_a = {}
	fire("save_state", save_a)
	local wa = save_a.persistent_stalkers.session
	check(C.get_phase() == "live" and wa and P.world() == wa, "a new game is a world of its own; the profile knows it (" .. tostring(P.world()) .. ")")
	-- world B: another new game, progress there
	end_game()
	start_game()
	ACTOR.money = 222
	local save_b = {}
	fire("save_state", save_b)
	local wb = save_b.persistent_stalkers.session
	check(wb and wb ~= wa and P.world() == wb and P.character().money == 222, "world B: its own session, the profile written there")
	-- back to A's save: played with default, but in another world: the profile, not the save
	end_game()
	local n = #APPLIED
	start_game(save_a)
	check(#APPLIED == n + 1 and APPLIED[#APPLIED].money == 222, "A's save gets the profile's progress from B")
	check(logged("in another world"), "logged: another world")
	check(P.world() == wa, "the profile is in world A now")
	-- an older save of the same world: followed, as a reload
	ACTOR.money = 333
	fire("save_state", {})
	end_game()
	n = #APPLIED
	start_game(save_a)
	check(#APPLIED == n and logged("the character follows it"), "the same world's older save: followed, nothing applied")
	-- the lobby's faction change (keep goodwill), then that same world's save: followed, the edit on top
	end_game()
	check(P.set_faction("default", "dolg", false) == true and P.pending() and P.pending().faction == "dolg", "the faction change is kept as pending")
	ACTOR.faction = "stalker"
	n = #APPLIED
	start_game(save_a)
	check(#APPLIED == n and ACTOR.faction == "dolg", "the save is followed, the new faction put on it")
	check(not P.pending() and P.character().faction == "dolg", "the edit cleared, the profile written with it")
	check(logged("edits made outside a game put on: faction dolg"), "logged")
	-- reset goodwill, then world B's save: the profile applied, the reset on top
	end_game()
	check(P.set_faction("default", "freedom", true) == true and P.pending().goodwill, "reset kept as pending")
	start_game(save_b)
	check(ACTOR.faction == "freedom" and ACTOR.goodwill and ACTOR.goodwill.dolg == 0 and ACTOR.goodwill.freedom == 0, "the profile applied, the reset on top")
	check(not P.pending(), "cleared")
	-- the next load has nothing pending
	local e = #EDITS
	end_game()
	start_game(save_b)
	check(#EDITS == e, "nothing pending the next time")
end

print("-- 32. The gate and the in-game skip list")
do
	load_script(ROOT_V2, "persistent_stalkers_lobby_known")
	local LIST = { "__persistent_stalkers_gate.script", "_g_patches.script", "bind_stalker.script", "mp_settings.script",
		"quickdraw.script", "smr_civil_war.script", "xr_logic.script", "xrr_patch_common.script", "xrr_patch_paw.script", "zzz_dante.script" }
	FILES["app/xrr_patch_paw.script"] = "-- quickdraw patch\nlocal f = quickdraw.on_key\naxr_main.config = nil\n"
	FILES["app/xrr_patch_common.script"] = "quickdraw.x = 1\naxr_main.a()\nbind_stalker.b()\nxr_logic.c()\nsim_board.d()\nutils_obj.e()\n"
	local fs_old = getFS
	getFS = function()
		local fs = fs_old()
		local list = fs.file_list_open_ex
		fs.file_list_open_ex = function(self, root, flags, pattern)
			if root == "$game_scripts$" and pattern == "*.script" then
				return {
					Size = function() return #LIST end,
					GetAt = function(_, i)
						local n = LIST[i + 1]
						return { NameShort = function() return n end, Size = function() return 8 end }
					end,
				}
			end
			return list(self, root, flags, pattern)
		end
		return fs
	end
	local G_MT_OLD = getmetatable(_G)
	local loaded, started = {}, {}
	local function mod(name, body)
		return function()
			local m = { on_game_start = function() started[#started + 1] = name end }
			if body then body(m) end
			return m
		end
	end
	local MODS = {
		_g_patches = mod("_g_patches"),
		bind_stalker = mod("bind_stalker", function() local _ = smr_civil_war end), -- names a skipped script at load
		mp_settings = mod("mp_settings"),
		quickdraw = mod("quickdraw"),
		smr_civil_war = mod("smr_civil_war"),
		xr_logic = mod("xr_logic", function(m) m.on_game_start = function() error("xr_logic broke") end end),
		xrr_patch_common = mod("xrr_patch_common"),
		xrr_patch_paw = mod("xrr_patch_paw"),
		zzz_dante = mod("zzz_dante"),
	}
	local function engine_loader(t, k)
		if k == "__persistent_stalkers_gate" then
			loaded[k] = true
			return load_script(ROOT_V2, k)
		elseif MODS[k] then
			loaded[k] = true
			local m = MODS[k]()
			rawset(t, k, m)
			return m
		end
	end
	local function reset()
		for k in pairs(MODS) do rawset(_G, k, nil) end
		rawset(_G, "__persistent_stalkers_gate", nil)
		loaded, started = {}, {}
		setmetatable(_G, { __index = engine_loader })
	end
	-- axr_main.on_game_start's loop, as the game's own file has it
	local axr_loop = assert(load([=[
		local names = ...
		local t = {}
		for _, f in ipairs(names) do
			local n = f:sub(1, -8)
			if _G[n] and _G[n].on_game_start then t[#t + 1] = n end
		end
		for i = 1, #t do _G[t[i]].on_game_start() end
	]=], "@axr_main.script", "t", _G))

	-- a lobby game, the game's own axr_main
	reset()
	FILES[marker] = master_core_text.encode({ t = os.time() })
	local GB = load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
	local names, n, patches = GB.skip_names()
	check(names["quickdraw.script"] and names["smr_civil_war.script"] and names["xrr_patch_paw.script"]
		and not names["xrr_patch_common.script"] and not names["bind_stalker.script"] and not names["zzz_dante.script"]
		and not names["mp_settings.script"] and not names["_g_patches.script"] and not names["__persistent_stalkers_gate.script"]
		and n == 3 and #patches == 1 and patches[1] == "xrr_patch_paw",
		"the skip list in game: the mods' scripts and the patch for one; Anomaly's, loose, kept by prefix, and a broad patch stay")
	local n_log = #LOG
	local loop_ok = pcall(axr_loop, LIST)
	local text = table.concat(LOG, "\n", n_log + 1)
	check(loop_ok and loaded.__persistent_stalkers_gate and started[1] == "_g_patches",
		"the gate loads first and starts first (before any other on_game_start)")
	check(not loaded.quickdraw and not loaded.xrr_patch_paw, "axr_main's loop does not load a skipped script")
	check(loaded.smr_civil_war and not table.concat(started, " "):find("smr_civil_war", 1, true),
		"a skipped script another one names at load still loads, and is not started")
	check(table.concat(started, " ") == "_g_patches bind_stalker mp_settings xrr_patch_common zzz_dante",
		"every kept script is started, the one after a failing on_game_start too")
	check(text:find("on_game_start of xr_logic failed", 1, true), "a failing on_game_start is logged")
	check(text:find("gate: 2 skipped scripts not loaded by axr_main, 1 loaded by other scripts and not started", 1, true)
		and text:find("startup, load", 1, true) and text:find("startup, on_game_start", 1, true),
		"after the last one, the gate's report and the timing")
	check(rawget(_G, "bind_stalker").on_game_start ~= nil and not GB.gate_state().open, "the gate is closed after the start")
	local qd = quickdraw
	check(type(qd) == "table" and loaded.quickdraw, "after the start a skipped script loads when named (sim_board needs smr_civil_war)")

	-- any other game: everything as the game has it
	reset()
	FILES[marker] = ""
	GB = load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
	pcall(axr_loop, LIST)
	check(loaded.quickdraw and table.concat(started, " "):find("quickdraw", 1, true) and table.concat(started, " "):find("smr_civil_war", 1, true)
		and GB.gate_state() == nil, "no marker: the gate does nothing, every script loads and starts")

	-- a patched axr_main asked first: the gate stands aside
	reset()
	FILES[marker] = master_core_text.encode({ t = os.time() })
	GB = load_script(ROOT_V2, "persistent_stalkers_lobby_boot")
	local s2 = GB.startup_skip()
	check(s2 and s2["quickdraw.script"] and GB.gate_begin() == false and GB.gate_state() == nil,
		"a patched axr_main gets the in-game list, and the gate stands aside")
	FILES[marker] = ""

	setmetatable(_G, G_MT_OLD)
	for k in pairs(MODS) do rawset(_G, k, nil) end
	rawset(_G, "__persistent_stalkers_gate", nil)
	getFS = fs_old
end

print(string.format("%d checks, %d failed", checks, fails))

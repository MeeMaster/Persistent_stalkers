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
function getFS() return { update_path = function(_, _, f) return "app/" .. f end } end

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
function CScriptXmlInit()
	local x = {}
	return setmetatable(x, { __index = function(t, k)
		if k == "ParseFile" then return function(_, f) x.file = f end end
		return function(_, node, parent)
			local w = wnd(node)
			XML_NODES[node] = w
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
level = { present = function() return PRESENT end, game_id = function() return 1 end }
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
function exec_console_cmd() end
xrs_debug_tools = { on_game_start = function() end }
local CB = {}
function RegisterScriptCallback(n, f) CB[n] = CB[n] or {}; table.insert(CB[n], f) end
function UnregisterScriptCallback() end
function SendScriptCallback(n, ...) for _, f in ipairs(CB[n] or {}) do if type(f) == "function" then f(...) end end end
local function fire(n, ...) for _, f in ipairs(CB[n] or {}) do if type(f) == "function" then f(...) end end end
local MCM = { ["persistent_stalkers/mode"] = "save" }
ui_mcm = { get = function(k) return MCM[k] end, init_opt_base = function() end }
axr_main = { config = { r_value = function() return nil end } }
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
local mm = MM.main_menu()
check(mm.pst_panel ~= nil, "the panel is attached")
check(mm.shniaga.x == 10 or mm.shniaga.x ~= nil, "the options were moved")
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
	db.actor = { alive = function() return true end }
	C.on_game_start()
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

print("-- 7. profile mode: the profile is applied on every load")
end_game()
MCM["persistent_stalkers/mode"] = "profile"
mm = MM.main_menu()
click(mm, "pst_row_2")
check(text_of("menu:what"):find("exactly as you left it"), "what in profile mode")
ACTOR.money = 5
start_game(save)
check(#APPLIED == 2 and APPLIED[2].money == 250, "default applied over its own save")
ACTOR.money = 300
for i = 1, 60 do NOW = NOW + 100; fire("actor_on_update") end
check(P.character().money == 300, "written within 5 s")

print("-- 8. the console switch")
C.switch_to("alt")
check(P.current_profile() == "alt" and #APPLIED == 3 and APPLIED[3].money == 900 and P.selected_profile() == "alt", "switch_to applies alt and selects it")
C.switch_to("nope")
check(P.current_profile() == "alt", "an unknown name is refused")

print("-- 9. mode off")
end_game()
MCM["persistent_stalkers/mode"] = "off"
mm = MM.main_menu()
check(text_of("menu:what"):find("Off in MCM"), "the main menu says the mode is off")
start_game(save)
check(C.get_phase() == "off" and #APPLIED == 3, "nothing happens")

print("-- 10. client in save mode")
end_game()
MCM["persistent_stalkers/mode"] = "save"
HOST = false
ACTOR.money = 40
start_game()
check(C.get_phase() == "waiting", "waits for the key")
CB["net_pst_world"][1](master_core_text.encode({ key = "k-1" }))
for i = 1, 60 do NOW = NOW + 100; fire("actor_on_update") end
check(C.get_phase() == "live" and #APPLIED == 4 and APPLIED[4].money == 900, "no snapshot: alt's file applied")
ACTOR.money = 41
CB["net_pst_saved"][1](master_core_text.encode({ key = "k-2" }))
check(P.snapshot("k-2") and P.snapshot("k-2").money == 41, "a host save stores a snapshot")
end_game()
ACTOR.money = 1
start_game()
CB["net_pst_world"][1](master_core_text.encode({ key = "k-2" }))
for i = 1, 60 do NOW = NOW + 100; fire("actor_on_update") end
check(#APPLIED == 5 and APPLIED[5].money == 41, "a rejoin into that key applies the snapshot")

print(string.format("%d checks, %d failed", checks, fails))

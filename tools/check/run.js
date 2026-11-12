// Runs t.lua in fengari (Lua 5.3) against a fake engine: node run.js (after npm i fengari here).
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require("fengari");
const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);
const path = require("path");
const v2 = path.join(__dirname, "../../gamedata/scripts/");
const mc = path.join(__dirname, "../../../Master_core/gamedata/scripts/");
if (lauxlib.luaL_loadfile(L, to_luastring(__dirname + "/t.lua")) !== lua.LUA_OK) {
	console.log("load error: " + to_jsstring(lua.lua_tostring(L, -1)));
	process.exit(1);
}
lua.lua_pushcfunction(L, (L) => { try { lua.lua_pushstring(L, to_luastring(require("fs").readFileSync(to_jsstring(lua.lua_tostring(L, 1)), "latin1"))); } catch (e) { lua.lua_pushnil(L); } return 1; });
lua.lua_setglobal(L, to_luastring("read_source"));
lua.lua_pushstring(L, to_luastring(v2));
lua.lua_pushstring(L, to_luastring(mc));
lua.lua_pushcfunction(L, (L) => {
	lauxlib.luaL_traceback(L, L, lua.lua_tostring(L, 1), 1);
	return 1;
});
lua.lua_insert(L, -4);
if (lua.lua_pcall(L, 2, 0, -4) !== lua.LUA_OK) {
	console.log("error: " + to_jsstring(lua.lua_tostring(L, -1)));
	process.exit(1);
}

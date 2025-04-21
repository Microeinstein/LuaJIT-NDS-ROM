#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include <luajit.h>

#include <nds.h>

#include "luamain.h"


static int foo(lua_State* L) {
    lua_Integer a = luaL_checkinteger(L, 1);
    lua_Integer b = luaL_checkinteger(L, 2);
    lua_pushinteger(L, a + b);
    return 1;
}


static luaL_Reg const foolib[] = {
    { "foo", foo },
    { 0, 0 }
};


// https://stackoverflow.com/questions/63570555/how-do-i-improve-lua-internal-error-messages-to-include-line-numbers
// https://stackoverflow.com/questions/30021904/lua-set-default-error-handler
// https://www.lua.org/source/5.4/lua.c.html#msghandler
int msghandler(lua_State *L) {
    const char *msg = lua_tostring(L, 1);
    if (msg == NULL) {
        if (luaL_callmeta(L, 1, "__tostring") && lua_type(L, -1) == LUA_TSTRING) {
            return 1;
        } else {
            msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
        }
    }
    luaL_traceback(L, L, msg, 1);
    return 1;
}


int lua_mypcall(lua_State* L, int nargs, int nret) {
    int hpos = lua_gettop(L) - nargs;
    int ret = 0;
    lua_pushcfunction(L, msghandler);
    lua_insert(L, hpos);
    if ((ret = lua_pcall(L, nargs, nret, hpos))) {
        iprintf("%s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    lua_remove(L, hpos);
    return ret;
}


void run_lua(lua_State *L) {
    luaL_openlibs(L);
    luaL_register(L, "foolib", foolib);
    
    // char * code = "print('hello from lua')";
    // luaL_dostring(L, code);
    
    int err;
    if (err = luaL_loadstring(L, (const char*)luamain)) {
        iprintf("Error loading Lua code... (%d)\n", err);
        return;
    };
    
    if (lua_mypcall(L, 0, LUA_MULTRET)) {
        return;
    }
    
    // if (luaL_loadbufferx(L, (const char*)luamain, luamain_size, "luamain", "t") == LUA_OK) {
    //     if (lua_pcall(L, 0, LUA_MULTRET, 0) == LUA_OK) {
    //         lua_pop(L, lua_gettop(L));
    //     }
    // }
}


int main(){
    // NOTE: on MelonDS, disable JIT
    consoleDemoInit();
    defaultExceptionHandler();

	iprintf("Hello from C\n");

    lua_State *L = luaL_newstate();
    run_lua(L);
    lua_close(L);

	while(pmMainLoop()) {
		swiWaitForVBlank();
    }

    return 0;
}

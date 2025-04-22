extern "C" {
    #pragma GCC diagnostic push
    #pragma GCC diagnostic ignored "-Wignored-qualifiers"

    #include <nds.h>
    #include <filesystem.h>

    #include <stdio.h>
    #include <stdlib.h>
    #include <string.h>
    #include <dirent.h>

    #include <lua.h>
    #include <lualib.h>
    #include <lauxlib.h>
    #include <luajit.h>

    // #include "luamain.h"
    #include "font.h"

    #pragma GCC diagnostic pop
}


typedef char* string;
typedef const char* cstring;


void sleep(const int ms) {
    for (int f = 0; f <= (ms / 17); f++) {
        swiWaitForVBlank();
    }
}


int hang() {
    while(pmMainLoop()) {
		swiWaitForVBlank();
    }
    return 0;
}


#define debugv(fmt, ...) { printf("> " fmt "\n", __VA_ARGS__); sleep(1000); }
#define debug(fmt)       { printf("> " fmt "\n"); sleep(1000); }


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
        printf("%s", lua_tostring(L, -1));
        lua_pop(L, 1);
    }
    lua_remove(L, hpos);
    return ret;
}


int load_lua(lua_State *L, cstring code) {
    luaL_openlibs(L);
    luaL_register(L, "foolib", foolib);
    
    // string code = "print('hello from lua')";
    // luaL_dostring(L, code);
    
    int err;
    if ((err = luaL_loadstring(L, code))) {
        printf("Error loading Lua code... (%d)\n", err);
        return 1;
    };
    
    // if (luaL_loadbufferx(L, code, luamain_size, "luamain", "t") == LUA_OK) {
    //     if (lua_pcall(L, 0, LUA_MULTRET, 0) == LUA_OK) {
    //         lua_pop(L, lua_gettop(L));
    //     }
    // }
    return 0;
}


template<typename Loader>
int read_file(cstring path, Loader loader) {
    int err = 0;
    
    FILE* inf = fopen(path, "rb");
    if (!inf) {
        printf("Cannot open nitro file...\n");
        return 1;
    }
    // debug("file opened");

    size_t len;
    fseek(inf, 0, SEEK_END);
    len = ftell(inf);
    fseek(inf, 0, SEEK_SET);

    string content = (string)malloc(len+1);
    content[len] = 0;
    // char content[512] = {};
    if (fread(content, 1, len, inf) != len) {
        printf("savage error reading the bytes from the file!\n");
        err = 1;
    } else {
        err = loader(content);
    }
    free(content);
    fclose(inf);

    return err;
}


void init_console() {
    consoleDemoInit();
    return;

	const int map_base = 20;
    const int tile_base = 0;

	videoSetMode(0);

	videoSetModeSub(MODE_5_2D);
	vramSetBankC(VRAM_C_SUB_BG);

	PrintConsole *console = consoleInit(
        0, 3, BgType_ExRotation, BgSize_ER_256x256,
        map_base, tile_base, false, false
    );

	int offset = 0;

    auto set_font = [&]() {
        ConsoleFont font;

        font.gfx = (u16*)fontTiles;
        font.pal = (u16*)fontPal;
        font.convertSingleColor = false;
        font.numColors =  fontPalLen / 2;
        font.bpp = 8;

        // font.numChars = 71;
        font.numChars = 97;

        // width * height * palette * chars
        // font.asciiOffset = 32;
        font.asciiOffset = offset;

        consoleSetFont(console, &font);

        printf("Custom Font Demo\n");
    };
    set_font();

    while(pmMainLoop()) {
		scanKeys();
		u32 keys = keysHeld();

		if (keys & KEY_UP)   offset--;
		if (keys & KEY_DOWN) offset++;

        swiWaitForVBlank();

        if (keys) {
            set_font();
            sleep(16);
        }

        // bgUpdate();
    }
}


int main() {
    // NOTE: on MelonDS, disable JIT
    init_console();
    defaultExceptionHandler();

	printf("Hello from C\n");

    if (!nitroFSInit(NULL)) {
        printf("Cannot initialize nitro FS...\n");
        return hang();
    }

    lua_State *L = luaL_newstate();
    auto loader = [&](cstring content) { return load_lua(L, content); };
    if (read_file("nitro:/luamain.lua", loader)) {
        return hang();
    }

    if (lua_mypcall(L, 0, LUA_MULTRET)) { }

    lua_close(L);

    return hang();
}

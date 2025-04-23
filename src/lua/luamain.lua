package.path = '/lua/?.lua;/lua/?/init.lua;nitro:/?.lua;nitro:/?/init.lua'

require('foolib')

ffi = require('ffi')

print('Hello from lua')
print(foolib.foo(8, 5))

-- clib = ffi.load('nitro:/libsimple')

ffi.cdef [[
    typedef struct foo { int a, b; } foo_t;
    int dyn(int a, int b);
]]


data = ffi.new('foo_t')
data.a = 2
print(data.a)

-- print(clib.dyn)
-- local ok, ret = pcall(ffi.C.printf, "%s\n", "HELLO FROM FFI");
-- print(ret);


local no_return = {
    ['and']      = true,
    ['break']    = true,
    ['do']       = true,
    ['else']     = true,
    ['elseif']   = true,
    ['end']      = true,
    ['for']      = true,
    ['function'] = true,
    ['if']       = true,
    ['in']       = true,
    ['local']    = true,
    ['not']      = true,
    ['or']       = true,
    ['repeat']   = true,
    ['return']   = true,
    ['then']     = true,
    ['until']    = true,
    ['while']    = true,
    ['true']     = false,
    ['nil']      = false,
    ['false']    = false,
}


local function my_repl()
    local ok, ret, msg, code, fkey

    while true do
        print()
        io.write('> ')
        code = io.read()
        fkey = string.match(code, '^%s*(%w+)')
        if not fkey or not no_return[fkey] then
            code = 'return ' .. code
        end
        
        ret, msg = load(code)
        if not ret then
            print(msg)
            goto continue
        end

        ok, ret = pcall(ret)
        print(ret)

        ::continue::
    end
end

my_repl()

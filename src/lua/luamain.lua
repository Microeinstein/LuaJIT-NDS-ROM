package.path = '/lua/?.lua;/lua/?/init.lua;nitro:/?.lua;nitro:/?/init.lua'

require('foolib')

ffi = require('ffi')

print('Hello from lua')
print(foolib.foo(8, 5))

dsl = ffi.load('/libcalculator.dsl')

ffi.cdef [[
    typedef struct foo { int a, b; } foo_t;
    int printf (const char *restrict format, ...);
    int dyn(int a, int b);
    int op_add(int a, int b);
    int operation_arm(int value);
]]

data = ffi.new('foo_t')
data.a = 2
print(data.a)

print(ffi.C)
print(dsl.op_add(7, 9))
print(dsl.operation_arm(2))
-- for k, v in pairs(ffi.C) do
--     print(k)
-- end
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

    local stdin = io.input()
    while true do
        print()
        io.write('> ')
        code = stdin:read()
        fkey1 = string.match(code, '^%s*(%w+)')
        sym = string.match(code, '[=]')
        if not (fkey and no_return[fkey]) then
            if sym then
                code = code .. '; return ' .. fkey1
            else
                code = 'return ' .. code
            end
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

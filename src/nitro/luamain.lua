package.path = 'nitro:/?.lua;nitro:/?/init.lua'

require('foolib')

-- local ffi = require('ffi')

print('Hello from lua')
print(foolib.foo(8, 5))


local keywords = {
    ['and']      = true,
    ['break']    = true,
    ['do']       = true,
    ['else']     = true,
    ['elseif']   = true,
    ['end']      = true,
    ['false']    = true,
    ['for']      = true,
    ['function'] = true,
    ['if']       = true,
    ['in']       = true,
    ['local']    = true,
    ['nil']      = true,
    ['not']      = true,
    ['or']       = true,
    ['repeat']   = true,
    ['return']   = true,
    ['then']     = true,
    ['true']     = true,
    ['until']    = true,
    ['while']    = true,
}


local function my_repl()
    local ok, ret, msg, code, fkey

    while true do
        print()
        io.write('> ')
        code = io.read()
        fkey = string.match(code, '^%s*(%w+)')
        if not fkey or not keywords[fkey] then
            code = 'return ' .. code
        end
        
        ret, msg = load(code)
        if not ret then
            print(msg)
            goto continue
        end

        ok, ret = pcall(ret)
        if ret then print(ret) end

        ::continue::
    end
end

my_repl()

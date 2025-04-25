#!/bin/bash

set -euo pipefail

SELF="${BASH_SOURCE[0]}"
SELF="$(realpath -ms "$SELF")"
cd "$(dirname "$SELF")" || exit 99

DIR_LJ="$PWD/foreign/luajit"
DIR_GFX="$PWD/gfx"
DIR_SRC="$PWD/src"
DIR_OUT="$PWD/out"


source '/etc/profile.d/devkit-env.sh' 2>/dev/null || :

_WONDER="${WONDERFUL_TOOLCHAIN:-}/toolchain/gcc-arm-none-eabi/bin"
_WONDERINC="${WONDERFUL_TOOLCHAIN:-}/toolchain/gcc-arm-none-eabi/arm-none-eabi/include"
_BLOCKSDS="${WONDERFUL_TOOLCHAIN:-}/thirdparty/blocksds/core"

if ! [[ -d "$_WONDER" && -d "$_BLOCKSDS" ]]; then
    echo "Please install BlocksDS!"
    exit 1
fi


# global cc args for target
cc_args=(
    -O2
    -fomit-frame-pointer
    -lm
)

arch_args=(
    # -march=armv5te
    # -mtune=arm946e-s
    -mthumb
    -mcpu=arm946e-s+nofp
)

arm9_kind=(
    -specs="$_BLOCKSDS/sys/crts/ds_arm9.specs"
)

arm9_dsl_kind=(
    -specs="$_BLOCKSDS/sys/crts/ds_arm9_dsl.specs"
)

xcc_args=(
    "${arch_args[@]}"
    # -I"$DEVKITPRO/libnds/include"
    # -I"$DEVKITPRO/calico/include"
    -isystem "$_BLOCKSDS/libs/libnds/include/machine"
    -isystem "$_BLOCKSDS/libs/libnds/include/sys"
    -isystem "$_BLOCKSDS/libs/libnds/include"
    -isystem "$_WONDERINC"
    # $(find "$_BLOCKSDS/libs/libnds/include" -mindepth 1 -maxdepth 1 -type d -printf '-I%p\n')
    # $(find "$_WONDERINC" -mindepth 1 -maxdepth 1 -type d -printf '-I%p\n')
    -c
    -g
    -MMD
    -MP
    -Wall
    -Wextra
    -Wfatal-errors
    # -fmax-errors=3
    -fomit-frame-pointer
    -ffunction-sections
    -fdata-sections
    -DARM9
    -D__NDS__

    # -DSDK_DEVKITPRO
    -DSDK_BLOCKSDS

    -DUSE_NITRO
    # -DUSE_FAT
)

xld_args=(
    "${arch_args[@]}"
    -g
    # -specs="$DEVKITPRO/calico/share/ds9.specs"
    # -L"$DEVKITPRO/libnds/lib"
    # -L"$DEVKITPRO/calico/lib"
    -L"$_BLOCKSDS/libs/libnds/lib"
)

# shellcheck disable=SC2054
xld_lib_args=(
    "${arch_args[@]}"
    -g
    -nostdlib
    -Wl,--emit-relocs
    -Wl,--unresolved-symbols=ignore-all
    -Wl,--nmagic
)

debug_build=true
if "$debug_build"; then
    xcc_args+=( -g  -Og  -DDEBUG )
else
    xcc_args+=( -Oz  -DNDEBUG )
fi

XCC="$_WONDER/arm-none-eabi-gcc"
XPP="$_WONDER/arm-none-eabi-g++"
XAS="$_WONDER/arm-none-eabi-as"
XAR="$_WONDER/arm-none-eabi-ar"
XLD="$_WONDER/arm-none-eabi-gcc"


error() {
    local err=$?
    echo "Program exited: $err"
    exit $err
} >&2


json_open() {
    exec 3> "${1:-.}/compile_commands.json"
    echo '[' >&3
    JSON_I=0
}


json_append() {
    local src i
    {
        for src in "${sources[@]}"; do
            ((JSON_I++ == 0)) || echo -ne ',\n'
            echo -e '{\n  "arguments": ['
            local args=("$@")
            for ((i = 0; i < $#; i++)); do
                ((i == 0)) || echo -ne ',\n'
                echo -n "    \"${args[$i]}\""
            done
            echo -ne '\n  ],\n  "directory": "'
            echo -n "$PWD"
            echo -ne '",\n  "file": "'
            echo -n "$src"
            echo -ne '",\n  "output": "'
            echo -n "$out"
            echo -ne '"\n}'
        done
    } >&3

    # echo -ne '\n\n'
    # printf '  [%s]\n' "$@"
    "$@"
}


json_close() {
    [[ "$JSON_I" ]] || return 0
    JSON_I=
    echo -e '\n]' >&3
    exec 3>&-
}


cleanup() {
    json_close
}


build_minilua() (
    cd "$DIR_LJ/src"
    # ! [[ -x "minilua" ]] || return 0
    gcc "${cc_args[@]}" host/minilua.c -o minilua
    #./minilua || error
)


minilua_genfiles() (
    cd "$DIR_LJ/src"
    local dasm_args=(
        "$DIR_LJ/dynasm/dynasm.lua"
        -LN
        # -D FPU
        # -D HFABI  # hard float ABI (hardware float)
        -D LJ_TARGET_NDS
        -D LUAJIT_TARGET=LUAJIT_ARCH_ARM
        -D LUAJIT_OS=LUAJIT_OS_OTHER
        # -D LUAJIT_DISABLE_JIT
        # -D LUAJIT_DISABLE_FFI
        -D JIT
        -D FFI
        -o 'host/buildvm_arch.h'
        'vm_arm.dasc'
    )

    git show -s --format=%ct >luajit_relver.txt
    ./minilua host/genversion.lua || error
    ./minilua "${dasm_args[@]}"
)


build_buildvm() (
    cd "$DIR_LJ/src"
    # ! [[ -x "buildvm" ]] || return 0
    local buildvm_args=(
        -m32
        "${cc_args[@]}"
        -I.
        -I"$DIR_LJ/dynasm"
        -DLUAJIT_TARGET=LUAJIT_ARCH_ARM
        -DLUAJIT_OS=LUAJIT_OS_OTHER
        # -DLUAJIT_DISABLE_JIT
        # -DLUAJIT_DISABLE_FFI
        -DLJ_TARGET_NDS
        -o 'buildvm'
        'host/buildvm'*.c
    )
    gcc "${buildvm_args[@]}"
)


buildvm_genfiles() (
    cd "$DIR_LJ/src"
    local all_libs=(
        lib_base.c
        lib_math.c
        lib_bit.c
        lib_string.c
        lib_table.c
        lib_io.c
        lib_os.c
        lib_package.c
        lib_debug.c
        lib_jit.c
        lib_ffi.c
        lib_buffer.c
    )

    ./buildvm -m elfasm  -o lj_vm.s
    ./buildvm -m bcdef   -o lj_bcdef.h     "${all_libs[@]}"
    ./buildvm -m ffdef   -o lj_ffdef.h     "${all_libs[@]}"
    ./buildvm -m libdef  -o lj_libdef.h    "${all_libs[@]}"
    ./buildvm -m recdef  -o lj_recdef.h    "${all_libs[@]}"
    ./buildvm -m vmdef   -o jit/vmdef.lua  "${all_libs[@]}"
    ./buildvm -m folddef -o lj_folddef.h   lj_opt_fold.c
)


build_luajit() (
    cd "$DIR_LJ/src"
    local luacc_args=(
        "${xcc_args[@]}"
        "${arm9_kind[@]}"
        -DLJ_TARGET_NDS
        # -DLUAJIT_DISABLE_FFI
        -DLUAJIT_USE_SYSMALLOC
        -DLUAJIT_SECURITY_PRNG=0 # no secure random prng for nintendo ds
    )

    if "$debug_build"; then
        target=libluajitD.a
    else
        target=libluajit.a
    fi

    local sources out

    sources=(lj_vm.s)
    out=lj_vm.o
    json_append "$XAS" -o "$out"  "${sources[@]}"

    sources=(ljamalg.c)
    out=ljamalg.o
    json_append "$XCC" "${luacc_args[@]}" -o "$out"  "${sources[@]}"

    sources=(ljamalg.o lj_vm.o)
    out="$target"
    json_append "$XAR" rc "$out"  "${sources[@]}"
)


build_test() (
    cd "$DIR_OUT"

    # raw2c "$DIR_SRC/luamain.lua"
    # sed -i 's/\}/, 0x00}/' "$DIR_OUT/luamain.c"
    # grit "$DIR_GFX/NDS-true-bios-16.bmp" -gt -mR! -m! -gB8 -ah$((11 * 96)) -tw11 -th11 -fts -o'font'
    # grit "$DIR_GFX/erusfont.bmp" -gt -mR! -m! -gB8 -aw6 -ah$((11 * 96)) -tw6 -th15 -fts -o'font'
    # grit "$DIR_GFX/out.bmp" -gt -mR! -m! -gB8 -ah$((6 * 96)) -tw6 -th6 -fts -o'font'
    # grit "$DIR_GFX/font.bmp" -gt -mR! -m! -gB8 -fts -o'font'
    
    local _sources objects libs  sources out  file
    _sources=(
        "$DIR_SRC/test.cpp"
        "$DIR_SRC/libcalculator.c"
        # "$DIR_OUT/font.s"
    )
    objects=()
    libs=()

    _calc_out() {
        out="${1##*/}"
        out="${out//.*/.$2}"
    }

    local cc_args=(
        "${xcc_args[@]}"
        -I"$DIR_LJ/src"
        -I"$DIR_SRC"
        -I"$DIR_OUT"
    )
    
    for file in "${_sources[@]}"; do
        _calc_out "$file" o

        sources=( "$file" )
        local _cmd=()
        case "$file" in
            *.s)   _cmd+=( "$XPP"  -x assembler-with-cpp ) ;;
            *.c)   _cmd+=( "$XCC"  --std=gnu17 ) ;;
            *.cpp) _cmd+=( "$XPP"  --std=gnu++17  -fno-exceptions  -fno-rtti ) ;;
        esac
        json_append "${_cmd[@]}"  "${cc_args[@]}"  "${arm9_kind[@]}"  -o "$out"  "$file"

        case "$out" in
            lib*)
                file="$out"
                _calc_out "$file" elf
                sources=( "$file" )
                json_append "$XLD"  "${xld_lib_args[@]}"  "${arm9_dsl_kind[@]}"  -o "$out"  "$file"
                libs+=( "$out" )
                ;;
            *)
                objects+=( "$out" )
                ;;
        esac
    done

    # "$XPP"  "${cc_args[@]}"  -fPIC  -o libsimple.o  "$DIR_SRC/libsimple.cpp"
    # "$XLD"  "${arch_args[@]}" -g  -o "$DIR_SRC/lua/libsimple"  libsimple.o
    
    _calc_out "${_sources[0]}" elf
    local main="$out"
    unset sources
    local -n sources=objects
    # shellcheck disable=SC2054
    local ld_args=(
        -L"$DIR_LJ/src"
        "${xld_args[@]}"
        "${arm9_kind[@]}"

        -o "$out"
        "${sources[@]}"

        -Wl,-Map,test.map
        -Wl,-z,noexecstack
        -Wl,--start-group
        
        -lluajitD
        # -lfat
        -lnds9d
        # -lcalico_ds9
        -lm
        -lstdc++
        -lc

        -Wl,--end-group
    )
    json_append "$XLD"  "${ld_args[@]}"

    for lib in "${libs[@]}"; do
        _calc_out "$lib" dsl
        local dsl_args=(
            -i "$lib"
            -o "$DIR_SRC/lua/$out"
            -m "$main"
        )
        "$_BLOCKSDS/tools/dsltool/dsltool" "${dsl_args[@]}"
    done
)


build_nds() (
    cd "$DIR_OUT"
    # local nitro=()
    # mapfile -t nitro < <(find "$DIR_SRC/nitro" -type f)
    # local IFS=','
    # local nitro_ls="${nitro[*]}"

    local args=(
        -c test.nds
        -9 test.elf
        # -7 "$DEVKITPRO/calico/bin/ds7_maine.elf"
        -7 "$_BLOCKSDS/sys/arm7/main_core/arm7_dswifi_maxmod.elf"
        # -b "$DEVKITPRO/calico/share/nds-icon.bmp"
        -b "$DIR_GFX/favicon.bmp"
        "LuaJIT;description;description2"
        -d "$DIR_SRC/lua"
    )
    "$_BLOCKSDS/tools/ndstool/ndstool" "${args[@]}"
)


run_steps() {
    for step in "${steps[@]}"; do
        echo
        echo -e "\e[1m> $step\e[0m"
        "$step"
    done
}


make_luajit() {
    local steps=(
        # build_minilua
        # minilua_genfiles

        # build_buildvm
        # buildvm_genfiles

        build_luajit
    )
    json_open "$DIR_LJ"
    run_steps
    json_close
}


make_target() {
    local steps=(
        build_test
        build_nds
    )
    json_open
    run_steps
    json_close
}


# set -x
trap cleanup EXIT
# make_luajit
make_target
echo -e "\e[1mOK\e[0m"

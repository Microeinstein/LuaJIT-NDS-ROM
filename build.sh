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

if ! [[ "$DEVKITPRO" ]] || ! [[ -d "$DEVKITPRO/devkitARM" ]]; then
    echo "Please install devkitarm!"
    exit 1
fi

debug_build=true

# global cc args for target
cc_args=(
    -O2
    -fomit-frame-pointer
    -lm
)

# /opt/devkitpro/examples/nds/hello_world/Makefile

arch_args=(
    -march=armv5te
    -mtune=arm946e-s
    -mthumb
)

libs=(
    -lfat
    -lnds9
    -lcalico_ds9
    -lluajitD
    -lm
)

xcc_args=(
    "${arch_args[@]}"
    -c
    -g
    -Wall
    -Wextra
    -Wfatal-errors
    # -fmax-errors=3
    -fomit-frame-pointer
    -ffunction-sections
    -fdata-sections
    -DARM9
    -D__NDS__
)

xld_args=(
    "${arch_args[@]}"
    -g
    -specs="$DEVKITPRO/calico/share/ds9.specs"
    -L"$DEVKITPRO/libnds/lib"
    -L"$DEVKITPRO/calico/lib"
)

if "$debug_build"; then
    xcc_args+=(
        -g
        -Og
        -DDEBUG
    )
else
    xcc_args+=(
    #    -g
        -Oz
        -DNDEBUG
    )
fi

XCC="$DEVKITARM/bin/arm-none-eabi-gcc"
XPP="$DEVKITARM/bin/arm-none-eabi-g++"
XAS="$DEVKITARM/bin/arm-none-eabi-as"
XAR="$DEVKITARM/bin/arm-none-eabi-ar"
XLD="$DEVKITARM/bin/arm-none-eabi-gcc"


error() {
    local err=$?
    echo "Program exited: $err"
    exit $err
} >&2


mk_minilua() (
    cd "$DIR_LJ/src"
    # ! [[ -x "minilua" ]] || return 0
    gcc "${cc_args[@]}" host/minilua.c -o minilua
    #./minilua || error
)


genfiles_minilua() (
    cd "$DIR_LJ/src"
    local dasm_args=(
        "$DIR_LJ/dynasm/dynasm.lua"
        -LN
        # -D FPU
        # -D HFABI  # hard float ABI (hardware float)
        -D LUAJIT_TARGET=LUAJIT_ARCH_ARM
        -D LJ_TARGET_NDS
        -D LUAJIT_OS=LUAJIT_OS_OTHER
        -D LUAJIT_DISABLE_JIT
        -D LUAJIT_DISABLE_FFI
        # -D JIT
        # -D FFI
        -o 'host/buildvm_arch.h'
        'vm_arm.dasc'
    )

    git show -s --format=%ct >luajit_relver.txt
    ./minilua host/genversion.lua || error
    ./minilua "${dasm_args[@]}"
)


mk_buildvm() (
    cd "$DIR_LJ/src"
#     ! [[ -x "buildvm" ]] || return 0
    local buildvm_args=(
        -m32
        "${cc_args[@]}"
        -I.
        -I"$DIR_LJ/dynasm"
        -DLUAJIT_TARGET=LUAJIT_ARCH_ARM
        -DLUAJIT_OS=LUAJIT_OS_OTHER
        -DLUAJIT_DISABLE_JIT
        -DLUAJIT_DISABLE_FFI
        -DLJ_TARGET_NDS=1
        -o 'buildvm'
        'host/buildvm'*.c
    )
    gcc "${buildvm_args[@]}"
)


gen_vm() (
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


build_target() (
    cd "$DIR_LJ/src"
    local luacc_args=(
        "${xcc_args[@]}"
        -DLUAJIT_DISABLE_FFI
        -DLUAJIT_USE_SYSMALLOC
        -DLUAJIT_SECURITY_PRNG=0 # no secure random prng for nintendo ds
    )

    if "$debug_build"; then
        target=libluajitD.a
    else
        target=libluajit.a
    fi

    "$XAS" -o lj_vm.o  lj_vm.s
    "$XCC" "${luacc_args[@]}" -o ljamalg.o ljamalg.c
    "$XAR" rc "$target"  ljamalg.o lj_vm.o
)


# /opt/devkitpro/libnds/include
# /opt/devkitpro/calico/include
# /opt/devkitpro/devkitARM/lib/gcc/arm-none-eabi/14.2.0/plugin/include
# /opt/devkitpro/devkitARM/lib/gcc/arm-none-eabi/14.2.0/install-tools/include
# /opt/devkitpro/devkitARM/lib/gcc/arm-none-eabi/14.2.0/include
# /opt/devkitpro/devkitARM/arm-none-eabi/include
# /opt/devkitpro/devkitARM/include

# /opt/devkitpro/libnds/lib
# /opt/devkitpro/calico/lib
# /opt/devkitpro/devkitARM/lib
# /opt/devkitpro/devkitARM/arm-none-eabi/lib

build_test() (
    cd "$DIR_OUT"
    local asm_args=(
        -x assembler-with-cpp
    )
    local cc_args=(
        "${xcc_args[@]}"
        --std=gnu++23
        -I"$DIR_LJ/src"
        -I"$DIR_SRC"
        -I"$DIR_OUT"
        -I"$DEVKITPRO/libnds/include"
        -I"$DEVKITPRO/calico/include"
    )
    # shellcheck disable=SC2054
    local ld_args=(
        -Wl,-Map,test.map
        -o test.elf
        -L"$DIR_LJ/src"
        "${xld_args[@]}"
    )

    # raw2c "$DIR_SRC/luamain.lua"
    # sed -i 's/\}/, 0x00}/' "$DIR_OUT/luamain.c"
    # grit "$DIR_GFX/NDS-true-bios-16.bmp" -gt -mR! -m! -gB8 -ah$((11 * 96)) -tw11 -th11 -fts -o'font'
    # grit "$DIR_GFX/erusfont.bmp" -gt -mR! -m! -gB8 -aw6 -ah$((11 * 96)) -tw6 -th15 -fts -o'font'
    # grit "$DIR_GFX/out.bmp" -gt -mR! -m! -gB8 -ah$((6 * 96)) -tw6 -th6 -fts -o'font'
    # grit "$DIR_GFX/font.bmp" -gt -mR! -m! -gB8 -fts -o'font'
    
    local src=(
        "$DIR_SRC/test.cpp"
        "$DIR_OUT/font.s"
    )
    for file in "${src[@]}"; do
        if [[ "$file" == *.s ]]; then
            "$XPP" "${asm_args[@]}" "${cc_args[@]}"  "$file"
        else
            "$XPP"  "${cc_args[@]}"  "$file"
        fi
    done

    src=( "${src[@]##*/}" )
    src=( "${src[@]//.*/.o}" )
    "$XLD"  "${ld_args[@]}"  "${src[@]}"  "${libs[@]}"
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
        -7 "$DEVKITPRO/calico/bin/ds7_maine.elf"
        # -b "$DEVKITPRO/calico/share/nds-icon.bmp"
        -b "$DIR_GFX/favicon.bmp"
        "LuaJIT;description;description2"
        -d "$DIR_SRC/lua"
    )
    "$DEVKITPRO/tools/bin/ndstool" "${args[@]}"
)


steps=(
    # mk_minilua
    # genfiles_minilua
    # mk_buildvm
    # gen_vm
    # build_target

    build_test
    build_nds
)

# set -x
for step in "${steps[@]}"; do
    echo
    echo -e "\e[1m> $step\e[0m"
    "$step"
done

echo -e "\e[1mOK\e[0m"

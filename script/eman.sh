#!/bin/bash

help() {
cat <<EOF
Usage:
    eman help                       : Show this help
    eman check-verilator            : Print the version of the first found Verilator (if there are multiple version of Verilator installed)
    eman verilator-example <PATH>   : Compile and run the Verilator example(s) with example path
    eman c-compiler-version         : Print the version of default C compiler and the version of GNU Make
    eman c-compiler-example <PATH>  : Compile and run the C/C++ example(s) with example path
EOF
}

check_verilator() {
    if command -v verilator >/dev/null 2>&1; then
        verilator --version
    else
        echo "Verilator not found. Please ensure it is installed."
        exit 1
    fi
}

c_compiler_version() {
    if command -v gcc >/dev/null 2>&1; then
        echo "C Compiler (gcc) version: $(gcc --version | head -n1)"
        echo "GNU Make version: $(make --version | head -n1)"
    else
        echo "gcc or make not found. Please install it first."
        exit 1
    fi
}

case "$1" in
    help)
        help
        ;;
    check-verilator)
        check_verilator
        ;;
    verilator-example)
        shift
        cd "$1" && make clean all;;
    c-compiler-version)
        c_compiler_version
        ;;
    c-compiler-example)
        shift
        cd "$1" && make clean all;;
    *)
        echo "Unknown command. Use 'eman help' for usage."
        exit 1
        ;;
esac

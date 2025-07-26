#!/bin/bash

EXAMPLE_DIR=${AOC_LAB0_DIR:-/home/myuser/aoc-lab0}

help() {
    cat <<EOF
    
    Usage: eman <command> [args]

    Available commands:
    eman help                    : Show this help message
    eman check-verilator         : Print the version of the first found Verilator (if multiple versions installed)
    eman verilator-example       : Compile and run the Verilator example(s) from $EXAMPLE_DIR/verilog/counter

    eman c-compiler-version      : Print the version of default C compiler and GNU Make
    eman c-compiler-example      : Compile and run the C/C++ example(s) from $EXAMPLE_DIR/c_cpp/arrays/multidim_array

EOF
}

check_verilator() {
    verilator --version
}

verilator_example() {
    local verilog_dir="$EXAMPLE_DIR/verilog/counter"
    if [ ! -d "$verilog_dir" ]; then
        echo "Error: Verilog example directory $verilog_dir not found. Please clone AOC - Lab 0 repo to $EXAMPLE_DIR."
        exit 1
    fi
    cd "$verilog_dir" || exit 1
    make run 2>/dev/null || { echo "Verilator example failed to compile or run."; exit 1; }
    echo "Verilator example completed. Check wave.vcd for waveform."
    cd - >/dev/null
}

c_compiler_version() {
    if command -v gcc >/dev/null 2>&1; then
        echo "C Compiler (gcc) version: $(gcc --version | head -n1)"
    else
        echo "gcc not found. Please install it first."
        exit 1
    fi
}

c_compiler_example() {
    local c_dir="$EXAMPLE_DIR/c_cpp/arrays/multidim_array"
    cd "$c_dir" || exit 1
    make run 2>/dev/null || { echo "C example failed to compile or run."; exit 1; }
    echo "C example completed successfully."
    cd - >/dev/null
}

case "$1" in
    help)
        help
        ;;
    check-verilator)
        check_verilator
        ;;
    verilator-example)
        verilator_example
        ;;
    c-compiler-version)
        c_compiler_version
        ;;
    c-compiler-example)
        c_compiler_example
        ;;
    *)
        echo "Unknown command. Use 'eman help' for usage."
        exit 1
        ;;
esac
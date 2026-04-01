# FPGA Validation and Benchmarking

This directory provides utilities to run the design on a Digilent Nexys Video board communicating via the UART/FTDI connector.

## Requirements
The scripts require Vivado for bitstream generation and OpenOCD to flash the board.
Furthermore, please provide an openocd configuration file for the digilent nexys video board (can also be downloaded [here](https://github.com/openocd-org/openocd/blob/master/tcl/board/digilent_nexys_video.cfg))

## Generating the bitstreams
Simply execute `python3 generate_bitstreams.py` to generate 18 bitstreams for the corresponding parameter sets.
They will be written to the `bitstreams` directory.

## Running the tests
Running `python3 run_nexys.py` will automatically flash the generated bitstreams, execute (by default) 10k keygen, sign and verify runs and store the corresponding
cycle counts in a `.csv` in the `cc_results` subdirectory.
The default UART baudrate 2000000 and should not be changed - changes also require configurations in the vhdl test harness.
By default, the UART communicates via `ttyUSB0`, but this might have to be changed in `run_nexys.py` depending on your setup.

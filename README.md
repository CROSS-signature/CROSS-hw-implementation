# CROSS Hardware Implementation

This repository hosts the Register Transfer Level (RTL) SystemVerilog code implementing a hardware accelerator for the [Codes and Restricted Objects Signature Scheme (CROSS)](https://www.cross-crypto.com/) (v2.2), including testbenches for behavioral simulation and utility scripts for the Vivado (FPGA) synthesis tool.

The repository structure is primarily designed to align with the specifications of the [FuseSoC package manager](https://github.com/olofk/fusesoc), encouraging HDL code modularity and broad compatibility with EDA tools thanks to the underlying [Edalize library](https://github.com/olofk/edalize).

Testing of hardware modules is automated via the GitHub Actions continuous integration (CI).
Configuration files are in the [.github/workflows](.github/workflows) folder.

The code is released under the [Solderpad Hardware License v 2.1](LICENSE),
excluding [FIFO and spill register](fusesoc/designs/cross/common/rtl_external) ([Solderpad Hardware License v 0.51](fusesoc/designs/cross/common/rtl_external/LICENSE)).

- [Repository structure](#repository-structure)
- [User guide](#user-guide)
  - [Dependencies](#dependencies)
  - [EDA tool execution](#eda-tool-execution)
- [Developer guide](#developer-guide)
  - [Design Verification](#design-verification)
- [Bibliography](#bibliography)

# Repository structure

The tree below shows the first three levels of directories in the repository:

- [`./fusesoc/designs`](./fusesoc/designs): contains the design, testbench and linter files. `misc` includes the C reference implementation of CROSS which is used as golden model in top-level functional simulation and functional tests run on FPGA.
- [`./fusesoc/fpga`](./fusesoc/fpga): contains Vivado utility scripts for out-of-context synthesis runs.
- [`./fusesoc/test`](./fusesoc/test): contains a test harness written in VHDL and corresponding constraint files for the Digilent Nexys Video board.
- [`./utils`](./utils): contains build and test scripts to run the design on the Digilent Nexys Video while automatically checking the output against the C reference implementation.

```
.
├── fusesoc
│   ├── designs
│   │   ├── axi
│   │   ├── cross
│   │   ├── misc
│   │   ├── modulo
│   │   └── sha3
│   ├── fpga
│   │   └── scripts
│   └── test
│       ├── lint
│       ├── rtl
│       ├── tcl
│       └── xdc
└── utils

```

# User guide

## Dependencies

System dependencies for Debian-based distributions are:
```console
# apt install --no-install-recommends -y \
    git \
    build-essential \
    make \
    cmake \
    ninja-build \
    g++ \
    ccache \
    curl \
    bzip2
```

The following binaries are expected to be present in any of the `$PATH` directories:
- `verible` (latest version)
- `vivado` (version `2023.1`)
- `openocd` (version `0.12.0`, required only for test on Digilent Nexys Video)

> Older versions of that software are not guaranteed to work correctly.

Python and other system dependencies are listed in the [environment.yml](environment.yml) file, which can be used by any conda-compatible package manager, like [micromamba](https://mamba.readthedocs.io/en/latest/), to create the environment with the command
```console
$ micromamba create --file environment.yml --yes
```
The environment is then cached and can be activated by calling
```console
$ micromamba activate cross-hw-design
```

> For the sake of reproducibility, the latest working (x86_64) environment can be rebuilt using the [env_freeze.yml](env_freeze.yml) and [pip_freeze.txt](pip_freeze.txt).

## EDA tool execution

The code is managed by the FuseSoC repository manager, which:
- solves the dependency graph and gathers the required source files
- may dynamically generate some specialized code (generators)
- creates the appropriate project for the requested EDA tool
- optionally runs the EDA tool

All these steps are performed by analyzing the `.core` module definitions in the [fusesoc](fusesoc/) directory.

The base command is:
```console
$ fusesoc run --target <target> <VLNV> [<parameters> ...]
```

where `<target>` is typically either `sim` or `synth` depending on the operation to perform, `<VLNV>` is the colon-separated Vendor, Library, Name, and Version (VLNV) string identifying a module definition in a `.core` file.

> You can list all the available cores, along with a short description, with the command `fusesoc core list`.

The `<parameters>` are dynamically generated depending on the content of the `.core` files gathered by the solved dependency graph, and can be listed by appending the `--help` argument.

See [FuseSoC](https://fusesoc.readthedocs.io/en/stable/) and [Edalize](https://edalize.readthedocs.io/en/latest/) documentation for further information.

### Simulation target

To run the behavioral simulation of a module, use the `sim` target.
> For example, this command runs the behavioral simulation of the exponentiation vector:
> ```console
> $ fusesoc run --target sim cross:arithmetic:exp_vector
> ```

This will create a working directory `./build` containing the simulation report (e.g., `report.html`) and all files used during simulation.
Using the `--setup` flag creates the working directory under without starting the simulation. 

There are several testbenches, targeting the internal submodules (e.g., the arithmetic units, the sampling units, the SHA-3 hash function) etc.
When running the top-level test, keygen, sign and verify are tested for all parameter sets and different internal configurations of the width of the matrix multiplier and number of unrolled Keccak rounds.
Top-level and sampling related tests are automatically checked against the C reference implementation of CROSS.

All currently available simulation targets are listed below:

| Name | Command |
|------|---------|
| Mersenne prime modulo                 | `fusesoc run --target sim cross:modulo:mersenne`                  |
| Crandall prime modulo                 | `fusesoc run --target sim cross:modulo:crandall`                  |
| Keccak core                           | `fusesoc run --target sim hash:sha3:core`                         |
| AXI stream asymmetric FIFO            | `fusesoc run --target sim cross:axi:axis_asym_fifo`               |
| Vectorized addition/subtraction       | `fusesoc run --target sim cross:arithmetic:add_sub_vector`        |
| Vectorized point-wise multiplication  | `fusesoc run --target sim cross:arithmetic:mul_vector`            |
| Vector-Matrix multiplication          | `fusesoc run --target sim cross:arithmetic:mul_vector_matrix`     |
| Vectorized exponentiation             | `fusesoc run --target sim cross:arithmetic:exp_vector`            |
| Arithmetic unit                       | `fusesoc run --target sim cross:arithmetic:arithmetic_unit`       |
| Sample unit                           | `fusesoc run --target sim cross:sampling:sample_unit`             |
| F_z rejection sampler                 | `fusesoc run --target sim_zk_sample cross:sampling:sample_unit`   |
| Tree unit (fast version)              | `fusesoc run --target sim cross:trees:no_tree_unit`               |
| Merkle tree addressing                | `fusesoc run --target sim_mtree_addr cross:trees:tree_unit`       |
| Merkle tree interface                 | `fusesoc run --target sim_mtree_intf cross:trees:tree_unit`       |
| Seed tree addressing                  | `fusesoc run --target sim_stree_addr cross:trees:tree_unit`       |
| Seed tree interface                   | `fusesoc run --target sim_stree_intf cross:trees:tree_unit`       |
| Tree unit                             | `fusesoc run --target sim_tree_unit cross:trees:tree_unit`        |
| Pack                                  | `fusesoc run --target sim cross:packing:packing_unit`             |
| TOP                                   | `fusesoc run --target sim cross:top:top`                          |

More details are provided in the [design Verification](#design-verification) section.

### FPGA synthesis target

The HDL files are FPGA manufacturer agnostic.

> Here there is a command example which starts the synthesis of the CROSS vectorized exponentiation module setting the SystemVerilog define `RSDP` and `CATEGORY_1` parameter choice:
> ```console
> $ fusesoc run --build --target synth cross:arithmetic:exp_vector --RSDP --CATEGORY_1
> ```

> The `--build` flag skips the automatic loading of the bitstream to the FPGA connected to the host.
> The `--setup` flag skips the synthesis and only creates the working directory containing `.tcl` scripts for Vivado.

> The default synthesis tool is Vivado, but it can be overwritten by appending `--tool <EDA_TOOL_NAME>` to the previous command.

During the FPGA synthesis with the Vivado EDA tool, some environment variables are used to apply common configurations:
- `XLX_SYNTH_OOC`: enable out-of-context synthesis for early evaluation of non-top-level modules
- `XLX_SYNTH_STRAT`: specifies one of the supported synthesis strategies (see Vivado manual)
- `XLX_IMPL_STRAT`: specifies one of the supported implementation strategies (see Vivado manual)
- `XLX_FLAT_HIER`: disable flat hierarchy to maintain module structure and simplify the debugging process


### FPGA validation
The repository provides a test harness to run the design on a Digilent Nexys Video board.
Required scripts and corresponding [README](./utils/README.md) can be found under [`./utils`](./utils).


# Developer guide

Linting of the SystemVerilog code is performed with [verible](https://github.com/chipsalliance/verible) upon commit automatically by the git [pre-commit hook](https://pre-commit.com/) using the [verible-lint.py](verible-lint.py) script.
> Install the pre-commit hook running `pre-commit install` in a shell after having activated the conda environment

> Manually run the hook with `pre-commit run --all-files`

## Design Verification

The hardware modules undergo behavioral simulation, employing the open-source [Verilator simulator](https://github.com/verilator/verilator).
Verilator translates Verilog and SystemVerilog code into C++ sources.

Testbenches have been redesigned to utilize the [Cocotb](https://www.cocotb.org/) framework, which enables the rapid creation of cross-simulator testbenches using the Python language.
For the top-level test as well as for several sampling modules, the output is automatically checked against the C reference implementation, which is made accessible in Python via [ctypes](https://docs.python.org/3/library/ctypes.html).
Therefore, the C files are compiled into shared objects (`.so`) when invoking fusesoc for the first time.

The development could be defining the following environment variables:
- `export DUMP_FST=true` to produce the simulation traces to be inspected (i.e. with [gtkwave](https://gtkwave.sourceforge.net/))
- `export RANDOM_SEED=<seed>` to fix the seed and generate reproducible Cocotb-based tests for arithmetic modules. In case the CI detects a failing test, the used seed is present in the logs
- `export LOGLEVEL=DEBUG` to select the desired Python logging verbosity

> [!NOTE]
> To limit the number of workers available for the verification, set the environment variable `PYTEST_XDIST_AUTO_NUM_WORKERS`
> to the desired number of processes.

The GitHub Actions CI configurations can be tested locally with [nektos' act](https://github.com/nektos/act), and immediately test a workflow or even a single job.
```console
$ act --bind --workflows .github/workflows/<test>.yaml --rm --quiet
```
> If you are using Podman, append `--container-daemon-socket $XDG_RUNTIME_DIR/podman/podman.sock` to the previous command.

# Bibliography
The corresponding [paper](https://eprint.iacr.org/2025/1161) to our work can be cited as follows:

```console
@misc{cryptoeprint:2025/1161,
      author = {Patrick Karl and Francesco Antognazza and Alessandro Barenghi and Gerardo Pelosi and Georg Sigl},
      title = {High-Performance {FPGA} Accelerator for the Post-quantum Signature Scheme {CROSS}},
      howpublished = {Cryptology {ePrint} Archive, Paper 2025/1161},
      year = {2025},
      url = {https://eprint.iacr.org/2025/1161}
}
```

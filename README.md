# APB Slave Design with SVA Protocol Checker

An AMBA APB slave written in SystemVerilog, with an SVA protocol checker attached using `bind`, functional coverage, and a directed testbench that includes negative tests.

## Files
- `design.sv`: `apb_if` (interface), `apb_slave` (DUT), `apb_checker` (SVA + coverage), and the `bind` statement
- `testbench.sv`: `tb_apb`, with write/read tasks, directed tests and negative tests

## Design
- 3-state FSM: IDLE -> SETUP -> ACCESS
- 32-bit data, 8-bit address, async active-low reset (`PRESETn`)
- Register map (word-aligned):

| Address | Register |
|---------|----------|
| 0x00 | REG0 (R/W) |
| 0x04 | REG1 (R/W) |
| 0x08 | REG2 (R/W) |
| 0x0C | REG3 (R/W) |
| 0x10 | WAIT_CFG (R/W, bits [1:0] = number of wait states, 0-3) |

- `PREADY` is held low for `WAIT_CFG` cycles in the ACCESS phase
- `PSLVERR` is asserted in the completing ACCESS cycle for unaligned or out-of-range addresses
- The interface provides `master`, `slave` and `monitor` modports

## SVA protocol checker
Bound non-intrusively to the slave with `bind apb_slave apb_checker`.

| ID | Property |
|----|----------|
| A1 | PSEL rising is followed by PENABLE one cycle later (SETUP then ACCESS) |
| A2 | PADDR stable while waiting (PREADY low) |
| A3 | PWRITE stable while waiting |
| A4 | PWDATA stable while waiting on a write |
| A5 | PSEL stays high until the transfer completes |
| A6 | PSLVERR only during a completing ACCESS |
| A7 | PSEL/PENABLE idle after reset release |
| A8 | PENABLE never high without PSEL |

## Functional coverage
Sampled on every completed transfer (PSEL && PENABLE && PREADY):
- `cp_write`: read / write
- `cp_slverr`: PSLVERR 0 / 1
- `cp_addr`: the 5 valid registers (plus a default bin for the invalid region)
- `cp_wait`: configured wait states 0-3
- `cx_wr_addr`: cross of read/write x register address

## Testbench
Directed tests:
1. Basic write/read, 0 wait states
2. Configure 2 wait states, write/read
3. Back-to-back writes
4. Out-of-range address -> PSLVERR
5. WAIT_CFG read (reset value and after write), 1 and 3 wait states

Negative tests (use `force` to inject violations; checker errors are expected):
- A: PENABLE raised together with PSEL
- B: PADDR changed mid-transfer
- C: PENABLE high without PSEL

## Run
Any SystemVerilog simulator with SVA and covergroup support (developed on EDA Playground).
Add `design.sv` and `testbench.sv`, set the top module to `tb_apb`, and run.
The negative tests print `[APB_CHK]` errors on purpose, so the simulator exits with a non-zero code.

## Results
Simulator: Cadence Xcelium 25.03 (EDA Playground)

- Directed tests 1-5: all pass, no `$error`
- Negative tests: each violation is caught by its intended assertion
  - A -> `a_setup_then_access`
  - B -> `a_addr_stable`
  - C -> `a_no_enable_without_sel`
  The forced signals also trigger knock-on stability assertions (`a_write_stable`, `a_wdata_stable`, `a_psel_no_early_drop`).
- Functional coverage: 100% of the defined bins, including the read/write x register cross

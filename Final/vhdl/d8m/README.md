# D8M camera support files

Terasic Verilog from the DE10-Nano D8M reference design, copied here so
the project has everything `d8m.vhd` needs in one place.

`d8m.vhd` instantiates exactly one of these — `MIPI_BRIDGE_CAMERA_Config`
— but that module pulls in ten more. Add **all** of them to the Quartus
project.

## What each one does

| File | Role |
|---|---|
| `MIPI_BRIDGE_CAMERA_Config.v` | Top of the tree. The only module `d8m.vhd` names. |
| `MIPI_CAMERA_CONFIG.v` | I2C register script for the image sensor. Sets 640×480 (`0x3808`–`0x380b`), binning, mirror and flip. |
| `MIPI_BRIDGE_CONFIG.v` | I2C register script for the TC358748 MIPI-to-parallel bridge. |
| `I2C_WRITE_PTR.v` | I2C master: register pointer write |
| `I2C_WRITE_WDATA.v` | I2C master: data write |
| `I2C_READ_DATA.v` | I2C master: read back |
| `I2C_RESET_DELAY.v` | Startup delay inside the I2C sequencer |
| `CLOCKMEM.v` | Clock divider. Both config blocks use it to make the 400 kHz I2C clock from the 50 MHz input. |
| `R_GAIN.v` `.qip` | `lpm_constant`, red gain = `0x44A` |
| `G_GAIN.v` `.qip` | `lpm_constant`, green gain = `0x4C0` |
| `B_GAIN.v` `.qip` | `lpm_constant`, blue gain = `0x400` |

## Notes

**The `*_bb.v` black-box stubs are deliberately not here.** Each
megafunction ships as `X_GAIN.v` (the implementation) plus `X_GAIN_bb.v`
(a black-box declaration). Both define a module of the same name, so
adding both to a project is a duplicate-definition error. The `.qip`
files list the `_bb.v` as `MISC_FILE`, meaning "do not compile".

**The gain megafunctions are just constants.** They were generated for
Stratix V, which is a portability risk on a different family. All three
do nothing but drive a fixed 14-bit value, so if Quartus complains they
can be replaced with three lines in `MIPI_CAMERA_CONFIG.v`:

```verilog
assign RR = 14'h44A;
assign GG = 14'h4C0;
assign BB = 14'h400;
```

and then `R_GAIN`, `G_GAIN`, `B_GAIN` and their `.qip` files can all be
deleted.

**Nothing else is required.** The dependency tree is closed — all 11
modules are defined here, no module is defined twice, and nothing
references an Altera library primitive beyond `lpm_constant`, which
Quartus supplies.

## What is deliberately absent

The reference design also contains autofocus (`AUTO_FOCUS_ON`,
`FOCUS_ADJ` and the whole VCM subtree) and gamma correction
(`D8M_LUT`). Neither is used:

- Autofocus was dropped — the lens stays where it is set. Adding it back
  means copying those files too and muxing `camera_i2c_scl` between the
  focus controller and the config block.
- `D8M_LUT` is instantiated with its enable tied low even in the
  reference design, so it is a passthrough there as well.

`RESET_DELAY` is also absent: `d8m.vhd` does that in a process, with the
delay as a generic so a testbench can shorten it.


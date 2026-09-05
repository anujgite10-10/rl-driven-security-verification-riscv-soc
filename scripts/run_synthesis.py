#!/usr/bin/env python3
"""
SecVeriRL — Synthesis Script (Yosys + OpenLane)
================================================
Runs logic synthesis via Yosys and optionally the full
RTL-to-GDSII flow via OpenLane 2 / OpenROAD.
"""

import os
import sys
import json
import yaml
import argparse
import subprocess
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def run_yosys_synthesis(config, output_dir):
    """Run Yosys logic synthesis."""
    print("\n" + "="*60)
    print("  Yosys Logic Synthesis")
    print("="*60)

    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate Yosys TCL script
    rtl_files = config.get('dut', {}).get('rtl_files', [])
    top_module = config.get('dut', {}).get('top_module', 'secverirl_soc_top')
    target_freq = config.get('synthesis', {}).get('target_frequency_mhz', 50)
    period_ns = 1000.0 / target_freq

    tcl_content = f"""# SecVeriRL Yosys Synthesis Script
# Auto-generated on {datetime.now().isoformat()}

# Read RTL
"""
    for rtl in rtl_files:
        tcl_content += f"read_verilog -sv {PROJECT_ROOT / rtl}\n"

    tcl_content += f"""
# Elaborate
hierarchy -top {top_module}

# Technology-independent optimizations
proc; opt; fsm; opt; memory; opt
techmap; opt

# Map to Sky130
synth -top {top_module}

# Reports
stat -top {top_module}
tee -o {output_dir / 'synth_stats.txt'} stat -top {top_module}

# Write outputs
write_verilog {output_dir / 'synth_netlist.v'}
write_json {output_dir / 'synth_stats.json'}

# ABC mapping for area/timing estimate
abc -liberty {PROJECT_ROOT / 'synthesis' / 'constraints' / 'sky130_fd_sc_hd__tt_025C_1v80.lib'} -constr {PROJECT_ROOT / 'synthesis' / 'constraints' / 'timing.sdc'}
tee -o {output_dir / 'abc_stats.txt'} stat
"""

    tcl_path = output_dir / 'synth.tcl'
    with open(tcl_path, 'w') as f:
        f.write(tcl_content)

    print(f"  TCL script: {tcl_path}")

    # Run Yosys
    try:
        cmd = ['yosys', '-s', str(tcl_path)]
        print(f"  Running: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=600)

        with open(output_dir / 'yosys.log', 'w') as f:
            f.write(result.stdout)

        if result.returncode == 0:
            print("  ✓ Synthesis completed successfully")
            _parse_synth_results(output_dir)
        else:
            print(f"  ✗ Synthesis failed: {result.stderr[-500:]}")

        return result.returncode == 0

    except FileNotFoundError:
        print("  [WARN] Yosys not found. Install: apt install yosys")
        print("  [INFO] TCL script generated for manual run")
        return False


def _parse_synth_results(output_dir):
    """Parse and display synthesis results."""
    stats_file = output_dir / 'synth_stats.txt'
    if stats_file.exists():
        with open(stats_file) as f:
            content = f.read()
        print("\n  --- Synthesis Statistics ---")
        for line in content.split('\n'):
            if any(k in line.lower() for k in ['cells', 'wire', 'area', 'memory']):
                print(f"    {line.strip()}")


def generate_openlane_config(config, output_dir):
    """Generate OpenLane 2 configuration for GDSII flow."""
    print("\n" + "="*60)
    print("  OpenLane Configuration")
    print("="*60)

    output_dir.mkdir(parents=True, exist_ok=True)

    top_module = config.get('dut', {}).get('top_module', 'secverirl_soc_top')
    rtl_files = config.get('dut', {}).get('rtl_files', [])
    synth_config = config.get('synthesis', {})

    openlane_config = {
        "DESIGN_NAME": top_module,
        "VERILOG_FILES": [str(PROJECT_ROOT / f) for f in rtl_files],
        "CLOCK_PORT": config.get('dut', {}).get('clock_name', 'clk'),
        "CLOCK_PERIOD": str(1000.0 / synth_config.get('target_frequency_mhz', 50)),
        "DIE_AREA": synth_config.get('die_area', '0 0 1000 1000'),
        "FP_CORE_UTIL": "40",
        "PL_TARGET_DENSITY": "0.5",
        "FP_PDN_MULTILAYER": "true",
        "RT_MAX_LAYER": "met4",
        "pdk::sky130A": {
            "STD_CELL_LIBRARY": "sky130_fd_sc_hd",
            "MAX_FANOUT_CONSTRAINT": "6",
            "FP_SIZING": "absolute",
        }
    }

    config_path = output_dir / 'config.json'
    with open(config_path, 'w') as f:
        json.dump(openlane_config, f, indent=2)

    print(f"  Config generated: {config_path}")
    print(f"  Design: {top_module}")
    print(f"  Clock period: {openlane_config['CLOCK_PERIOD']} ns")

    # Generate run script
    run_script = output_dir / 'run_openlane.sh'
    with open(run_script, 'w') as f:
        f.write(f"""#!/bin/bash
# SecVeriRL OpenLane 2 GDSII Flow
# Run from the project root directory

set -e

echo "Running OpenLane 2 for {top_module}..."

# Option 1: Docker-based (recommended)
# docker run --rm -v $(pwd):/work -w /work \\
#   efabless/openlane2:latest \\
#   openlane {config_path}

# Option 2: Local install
openlane --run-tag secverirl_gdsii {config_path}

echo "GDSII flow complete!"
echo "Results in: results/openlane/"
""")

    os.chmod(run_script, 0o755) if os.name != 'nt' else None
    print(f"  Run script: {run_script}")

    return config_path


def generate_timing_sdc(config, output_dir):
    """Generate SDC timing constraints."""
    output_dir.mkdir(parents=True, exist_ok=True)

    freq_mhz = config.get('synthesis', {}).get('target_frequency_mhz', 50)
    period_ns = 1000.0 / freq_mhz
    clock_name = config.get('dut', {}).get('clock_name', 'clk')

    sdc = f"""# SecVeriRL Timing Constraints
# Target: {freq_mhz} MHz ({period_ns:.2f} ns period)

create_clock -name {clock_name} -period {period_ns:.2f} [get_ports {{{clock_name}}}]

set_input_delay  [expr {period_ns:.2f} * 0.3] -clock {clock_name} [all_inputs]
set_output_delay [expr {period_ns:.2f} * 0.3] -clock {clock_name} [all_outputs]

set_load 0.01 [all_outputs]
set_driving_cell -lib_cell sky130_fd_sc_hd__inv_2 -pin Y [all_inputs]
"""

    sdc_path = output_dir / 'timing.sdc'
    with open(sdc_path, 'w') as f:
        f.write(sdc)

    print(f"  SDC constraints: {sdc_path}")
    return sdc_path


def main():
    parser = argparse.ArgumentParser(description='SecVeriRL Synthesis')
    parser.add_argument('--config', type=str,
                       default='config/dut_profiles/rv32i_basic.yaml')
    parser.add_argument('--yosys-only', action='store_true',
                       help='Run Yosys synthesis only (no GDSII)')
    parser.add_argument('--gen-config', action='store_true',
                       help='Generate OpenLane config only')
    args = parser.parse_args()

    config_path = PROJECT_ROOT / args.config
    with open(config_path) as f:
        config = yaml.safe_load(f)

    synth_dir = PROJECT_ROOT / 'results' / 'synthesis'

    # Generate timing constraints
    generate_timing_sdc(config, PROJECT_ROOT / 'synthesis' / 'constraints')

    if args.gen_config:
        generate_openlane_config(config, PROJECT_ROOT / 'synthesis' / 'openlane')
        return

    if args.yosys_only:
        run_yosys_synthesis(config, synth_dir / 'yosys')
        return

    # Full flow: Yosys → OpenLane
    run_yosys_synthesis(config, synth_dir / 'yosys')
    generate_openlane_config(config, PROJECT_ROOT / 'synthesis' / 'openlane')

    print("\n  To run GDSII flow:")
    print(f"    bash {PROJECT_ROOT / 'synthesis' / 'openlane' / 'run_openlane.sh'}")


if __name__ == '__main__':
    main()

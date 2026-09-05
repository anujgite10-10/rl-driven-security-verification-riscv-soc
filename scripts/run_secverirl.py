#!/usr/bin/env python3
"""
SecVeriRL — Main Orchestrator
==============================
Runs the full closed-loop verification flow:
  1. Run formal verification → extract counterexamples
  2. Translate counterexamples to RL seeds
  3. Train/run RL agent with coverage feedback
  4. Run simulation with RL-generated test knobs
  5. Repeat until coverage targets are met
"""

import os
import sys
import json
import yaml
import time
import argparse
import subprocess
import shutil
from pathlib import Path
from datetime import datetime

# Add project root to path
PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))


def load_config(config_path):
    """Load project and DUT configuration."""
    with open(config_path, 'r') as f:
        config = yaml.safe_load(f)

    # Also load master config
    master_config_path = PROJECT_ROOT / 'config' / 'project_config.yaml'
    if master_config_path.exists():
        with open(master_config_path, 'r') as f:
            master = yaml.safe_load(f)
        # Merge (DUT config overrides master)
        merged = {**master, **config}
        return merged

    return config


def setup_results_dir(config):
    """Create timestamped results directory."""
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    results_dir = PROJECT_ROOT / 'results' / f'run_{timestamp}'
    results_dir.mkdir(parents=True, exist_ok=True)

    # Create subdirectories
    (results_dir / 'coverage').mkdir(exist_ok=True)
    (results_dir / 'formal').mkdir(exist_ok=True)
    (results_dir / 'rl_logs').mkdir(exist_ok=True)
    (results_dir / 'waveforms').mkdir(exist_ok=True)
    (results_dir / 'reports').mkdir(exist_ok=True)

    return results_dir


def run_formal_verification(config, results_dir):
    """Step 1: Run SymbiYosys formal verification."""
    print("\n" + "="*70)
    print("  STEP 1: Formal Verification (SymbiYosys)")
    print("="*70)

    formal_dir = results_dir / 'formal'
    sby_file = PROJECT_ROOT / 'verification' / 'formal' / 'security.sby'

    if not sby_file.exists():
        print(f"  [WARN] SBY file not found: {sby_file}")
        print("  [INFO] Skipping formal verification")
        return {'status': 'skipped', 'counterexamples': []}

    try:
        cmd = ['sby', '-f', str(sby_file), '-d', str(formal_dir / 'sby_output')]
        print(f"  Running: {' '.join(cmd)}")
        result = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=config.get('formal', {}).get('timeout_sec', 3600),
                              cwd=str(PROJECT_ROOT))

        # Parse results
        formal_results = {
            'status': 'pass' if result.returncode == 0 else 'fail',
            'stdout': result.stdout[-2000:] if result.stdout else '',
            'stderr': result.stderr[-1000:] if result.stderr else '',
            'counterexamples': [],
        }

        # Count failed properties
        if result.stdout:
            for line in result.stdout.split('\n'):
                if 'FAIL' in line:
                    formal_results['counterexamples'].append(line.strip())

        with open(formal_dir / 'formal_results.json', 'w') as f:
            json.dump(formal_results, f, indent=2)

        n_fail = len(formal_results['counterexamples'])
        print(f"  Result: {formal_results['status']} ({n_fail} failed properties)")
        return formal_results

    except FileNotFoundError:
        print("  [WARN] SymbiYosys (sby) not found in PATH")
        print("  [INFO] Install with: pip install symbiyosys")
        return {'status': 'skipped', 'counterexamples': []}
    except subprocess.TimeoutExpired:
        print("  [WARN] Formal verification timed out")
        return {'status': 'timeout', 'counterexamples': []}


def translate_counterexamples(formal_results, results_dir):
    """Step 2: Translate formal counterexamples to RL seeds."""
    print("\n" + "="*70)
    print("  STEP 2: Translating Counterexamples to RL Seeds")
    print("="*70)

    from ai_engine.feedback.formal_feedback import FormalFeedbackEngine

    formal_dir = results_dir / 'formal'
    engine = FormalFeedbackEngine(str(formal_dir))
    cexs = engine.parse_results()
    stimuli = engine.translate_to_stimuli()
    seeds = engine.get_rl_seeds()

    print(f"  Counterexamples found: {len(cexs)}")
    print(f"  Translated stimuli: {len(stimuli)}")
    print(f"  RL seeds generated: {len(seeds)}")

    # Save seeds
    seeds_path = results_dir / 'rl_logs' / 'formal_seeds.json'
    with open(seeds_path, 'w') as f:
        json.dump(seeds, f, indent=2)

    return seeds


def run_rl_training(config, results_dir, formal_seeds=None, use_live_sim=False):
    """Step 3: Train RL agent with coverage feedback.
    
    Args:
        config: Project configuration dict
        results_dir: Path to store results
        formal_seeds: Seeds from formal counterexamples (injected into replay buffer)
        use_live_sim: If True, runs real Verilator simulation each training step.
                      If False, uses simulated coverage (faster, for testing).
    """
    print("\n" + "="*70)
    print("  STEP 3: RL Agent Training")
    print("="*70)

    algorithm = config.get('rl_agent', {}).get('algorithm', 'A2C')
    timesteps = config.get('rl_agent', {}).get('total_timesteps', 10000)
    config_path = PROJECT_ROOT / 'config' / 'project_config.yaml'
    config_str = str(config_path) if config_path.exists() else None

    training_output = results_dir / 'rl_training'

    if use_live_sim:
        # LIVE mode: each RL step runs a real Verilator+cocotb simulation
        from scripts.train_agent import train_live
        print("  Mode: LIVE (real RTL simulation per step)")
        print(f"  ⚠ This will run ~{timesteps} Verilator simulations!")
        model = train_live(config_str, timesteps, algorithm, training_output)
    else:
        # MOCK mode: uses simulated coverage (fast, for pipeline testing)
        from scripts.train_agent import train_mock
        print("  Mode: MOCK (simulated coverage — no simulator needed)")
        model = train_mock(config_str, timesteps, algorithm, training_output)

    # Copy training logs
    training_log = training_output / 'logs' / 'training_metrics.json'
    if training_log.exists():
        shutil.copy(training_log, results_dir / 'rl_logs' / 'training_metrics.json')

    summary = training_output / 'logs' / 'training_summary.json'
    if summary.exists():
        shutil.copy(summary, results_dir / 'rl_logs' / 'training_summary.json')

    print(f"  Training complete. Model saved to: {training_output / 'final_model'}")
    return model


def run_simulation(config, results_dir, iteration=0):
    """Step 4: Run cocotb simulation with RL-generated knobs."""
    print("\n" + "="*70)
    print(f"  STEP 4: Simulation (Iteration {iteration})")
    print("="*70)

    # Check for Verilator
    makefile = PROJECT_ROOT / 'verification' / 'Makefile'
    if not makefile.exists():
        print("  [INFO] Running in standalone mode (no simulator)")
        return _simulate_standalone(config, results_dir, iteration)

    try:
        cmd = [
            'make', '-f', str(makefile),
            f'SIM=verilator',
            f'TESTCASE=test_rl_driven',
            f'COCOTB_RESULTS_FILE={results_dir}/coverage/sim_{iteration}.xml',
        ]
        env = os.environ.copy()
        env['SECVERIRL_KNOBS'] = str(PROJECT_ROOT / 'results' / 'current_knobs.json')

        result = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=config.get('simulation', {}).get('sim_timeout_ms', 60000) // 1000,
                              cwd=str(PROJECT_ROOT), env=env)

        # Read coverage result
        cov_path = PROJECT_ROOT / 'results' / 'coverage_result.json'
        if cov_path.exists():
            with open(cov_path) as f:
                return json.load(f)

        return {'status': 'error', 'message': result.stderr[-500:]}

    except FileNotFoundError:
        print("  [WARN] make/verilator not found, using standalone mode")
        return _simulate_standalone(config, results_dir, iteration)


def _simulate_standalone(config, results_dir, iteration):
    """Standalone coverage simulation (no RTL simulator needed)."""
    import numpy as np

    # Read knobs if available
    knobs_path = PROJECT_ROOT / 'results' / 'current_knobs.json'
    if knobs_path.exists():
        with open(knobs_path) as f:
            knobs = json.load(f)
    else:
        knobs = {'test_scenario': 'mixed', 'test_length': 100}

    # Simulated coverage
    base = 0.4 + iteration * 0.05
    scenario = knobs.get('test_scenario', 'mixed')
    sec_boost = 0.3 if scenario in ['pmp_violation', 'privilege_switch'] else 0.1

    coverage = {
        'functional_coverage': min(base + np.random.random() * 0.2, 1.0),
        'security_coverage': min(base * 0.7 + sec_boost + np.random.random() * 0.1, 1.0),
        'pmp_coverage': min(base * 0.5 + np.random.random() * 0.2, 1.0),
        'iteration': iteration,
    }

    # Save
    with open(results_dir / 'coverage' / f'cov_{iteration}.json', 'w') as f:
        json.dump(coverage, f, indent=2)

    print(f"  Func: {coverage['functional_coverage']:.2%}, "
          f"Sec: {coverage['security_coverage']:.2%}, "
          f"PMP: {coverage['pmp_coverage']:.2%}")

    return coverage


def check_coverage_targets(coverage, config):
    """Check if all coverage targets are met."""
    targets = config.get('coverage', {})
    func_target = targets.get('functional_target', 0.95)
    sec_target = targets.get('security_target', 0.90)

    func_met = coverage.get('functional_coverage', 0) >= func_target
    sec_met = coverage.get('security_coverage', 0) >= sec_target

    return func_met and sec_met


def generate_report(all_coverage, results_dir, config):
    """Generate final verification report."""
    print("\n" + "="*70)
    print("  GENERATING FINAL REPORT")
    print("="*70)

    report = {
        'project': 'SecVeriRL',
        'timestamp': datetime.now().isoformat(),
        'dut': config.get('dut', {}).get('name', 'Unknown'),
        'total_iterations': len(all_coverage),
        'final_coverage': all_coverage[-1] if all_coverage else {},
        'coverage_progression': all_coverage,
        'targets': config.get('coverage', {}),
        'targets_met': check_coverage_targets(all_coverage[-1], config) if all_coverage else False,
    }

    report_path = results_dir / 'reports' / 'verification_report.json'
    with open(report_path, 'w') as f:
        json.dump(report, f, indent=2)

    # Print summary
    if all_coverage:
        final = all_coverage[-1]
        print(f"\n  Final Functional Coverage: {final.get('functional_coverage', 0):.2%}")
        print(f"  Final Security Coverage:   {final.get('security_coverage', 0):.2%}")
        print(f"  Final PMP Coverage:        {final.get('pmp_coverage', 0):.2%}")
        print(f"  Targets Met:               {report['targets_met']}")

    print(f"\n  Report saved to: {report_path}")
    return report


def main():
    parser = argparse.ArgumentParser(description='SecVeriRL Orchestrator')
    parser.add_argument('--config', type=str,
                       default='config/dut_profiles/rv32i_basic.yaml',
                       help='DUT configuration file')
    parser.add_argument('--iterations', type=int, default=10,
                       help='Max verification loop iterations')
    parser.add_argument('--skip-formal', action='store_true',
                       help='Skip formal verification step')
    parser.add_argument('--skip-rl', action='store_true',
                       help='Skip RL training (use existing model)')
    parser.add_argument('--standalone', action='store_true',
                       help='Run without RTL simulator (for testing)')
    parser.add_argument('--live', action='store_true',
                       help='Use live Verilator simulation for RL training (slow but accurate)')
    args = parser.parse_args()

    print("="*70)
    print("  SecVeriRL — Closed-Loop Adaptive Verification Framework")
    print("="*70)

    # Load configuration
    config_path = PROJECT_ROOT / args.config
    if config_path.exists():
        config = load_config(str(config_path))
    else:
        print(f"Config not found: {config_path}, using defaults")
        config = {}

    # Setup results directory
    results_dir = setup_results_dir(config)
    print(f"  Results directory: {results_dir}")

    # Save config snapshot
    with open(results_dir / 'config_snapshot.yaml', 'w') as f:
        yaml.dump(config, f, default_flow_style=False)

    all_coverage = []

    # ===== STEP 1: Formal Verification =====
    if not args.skip_formal:
        formal_results = run_formal_verification(config, results_dir)
        formal_seeds = translate_counterexamples(formal_results, results_dir)
    else:
        formal_seeds = []
        print("\n  [SKIP] Formal verification skipped")

    # ===== STEP 2: RL Agent Training =====
    if not args.skip_rl:
        model = run_rl_training(config, results_dir, formal_seeds,
                               use_live_sim=args.live)
    else:
        print("\n  [SKIP] RL training skipped")

    # ===== STEP 3: Closed-Loop Verification =====
    print("\n" + "="*70)
    print("  CLOSED-LOOP VERIFICATION")
    print("="*70)

    for iteration in range(args.iterations):
        # Run simulation
        coverage = run_simulation(config, results_dir, iteration)
        all_coverage.append(coverage)

        # Check targets
        if check_coverage_targets(coverage, config):
            print(f"\n  ✓ Coverage targets met at iteration {iteration}!")
            break

        print(f"  Iteration {iteration}: targets not yet met, continuing...")

    # ===== STEP 4: Report Generation =====
    report = generate_report(all_coverage, results_dir, config)

    print("\n" + "="*70)
    print("  SecVeriRL Run Complete!")
    print("="*70)

    return 0 if report.get('targets_met', False) else 1


if __name__ == '__main__':
    sys.exit(main())

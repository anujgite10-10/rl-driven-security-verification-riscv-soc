#!/usr/bin/env python3
"""
SecVeriRL — RL Agent Training Pipeline
=======================================
Trains the A2C/PPO agent by running actual RTL simulations via
Verilator+cocotb, collecting real coverage feedback, and updating
the agent's policy to maximize multi-objective security coverage.

Training Modes:
  1. --mode live    : Runs real Verilator simulation each step (slow, accurate)
  2. --mode offline : Trains on previously collected coverage data (fast)
  3. --mode mock    : Uses simulated coverage for testing the pipeline (no RTL needed)

Usage:
  python scripts/train_agent.py --mode mock --timesteps 5000
  python scripts/train_agent.py --mode live --timesteps 500 --config config/dut_profiles/rv32i_basic.yaml
  python scripts/train_agent.py --mode offline --data results/coverage_history.json
"""

import os
import sys
import json
import time
import yaml
import shutil
import argparse
import subprocess
import numpy as np
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from ai_engine.agent.secverirl_agent import (
    VerificationEnv,
    CoverageCallback,
)
from ai_engine.llm_debugger import analyze_coverage_gaps

try:
    from stable_baselines3 import A2C, PPO
    from stable_baselines3.common.callbacks import (
        BaseCallback, CheckpointCallback, EvalCallback
    )
    from stable_baselines3.common.monitor import Monitor
    HAS_SB3 = True
except ImportError:
    HAS_SB3 = False
    print("[ERROR] stable-baselines3 not installed.")
    print("  Install with: pip install stable-baselines3[extra]")


# =========================================================================
# Live Simulation Environment (connects RL ↔ Verilator/cocotb)
# =========================================================================

class LiveVerificationEnv(VerificationEnv):
    """
    Extends VerificationEnv to run ACTUAL Verilator/cocotb simulations
    instead of the mock _simulate_coverage().
    """

    def __init__(self, config_path=None, project_root=None, sim_timeout=120):
        super().__init__(config_path=config_path, project_root=project_root)
        self.sim_timeout = sim_timeout
        self.sim_count = 0
        self.sim_times = []

    def _run_simulation(self, knobs):
        """Run a REAL cocotb simulation and return actual coverage."""
        self.sim_count += 1
        t_start = time.time()

        # 1. Write knobs for the cocotb testbench to read
        knobs_path = self.results_dir / 'current_knobs.json'
        with open(knobs_path, 'w') as f:
            json.dump(knobs, f, indent=2)

        # 2. Set environment variable so cocotb test picks up knobs
        env = os.environ.copy()
        env['SECVERIRL_KNOBS'] = str(knobs_path)
        env['COCOTB_RESULTS_FILE'] = str(
            self.results_dir / f'sim_results_{self.sim_count}.xml'
        )

        # 3. Run simulation via Makefile
        makefile = self.project_root / 'verification' / 'Makefile'
        cmd = [
            'make', '-f', str(makefile),
            'SIM=verilator',
            'TESTCASE=test_rl_driven',
        ]

        print(f"  [Sim {self.sim_count}] Running with scenario={knobs.get('test_scenario', '?')}...",
              end='', flush=True)

        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=self.sim_timeout,
                cwd=str(self.project_root),
                env=env,
            )

            t_elapsed = time.time() - t_start
            self.sim_times.append(t_elapsed)

            if result.returncode != 0:
                print(f" FAIL ({t_elapsed:.1f}s)")
                # Log error but continue training
                with open(self.results_dir / 'sim_errors.log', 'a') as f:
                    f.write(f"Sim {self.sim_count}: {result.stderr[-500:]}\n")
                return self._fallback_coverage(knobs)

            # 4. Read coverage result written by cocotb testbench
            cov_path = self.results_dir / 'coverage_result.json'
            if cov_path.exists():
                with open(cov_path) as f:
                    coverage = json.load(f)
                print(f" OK func={coverage.get('functional_coverage', 0):.1%} "
                      f"sec={coverage.get('security_coverage', 0):.1%} ({t_elapsed:.1f}s)")
                return coverage
            else:
                print(f" NO COV FILE ({t_elapsed:.1f}s)")
                return self._fallback_coverage(knobs)

        except subprocess.TimeoutExpired:
            print(f" TIMEOUT ({self.sim_timeout}s)")
            return self._fallback_coverage(knobs)

        except FileNotFoundError:
            print(" MAKE NOT FOUND — falling back to mock")
            return self._simulate_coverage(knobs)

    def _fallback_coverage(self, knobs):
        """Return minimal coverage when simulation fails."""
        return {
            'functional_coverage': 0.0,
            'security_coverage': 0.0,
            'pmp_coverage': 0.0,
            'instruction_types_hit': 0,
            'instruction_types_total': 11,
            'security_alerts_hit': 0,
            'security_alerts_total': 6,
            'privilege_modes_hit': 0,
            'error': True,
        }

    def get_training_stats(self):
        """Return training statistics."""
        return {
            'total_simulations': self.sim_count,
            'avg_sim_time': np.mean(self.sim_times) if self.sim_times else 0,
            'total_sim_time': sum(self.sim_times),
            'coverage_history': self.coverage_history,
        }


# =========================================================================
# Offline Training Environment (trains on pre-collected data)
# =========================================================================

class OfflineVerificationEnv(VerificationEnv):
    """
    Trains on previously collected coverage data.
    Replays simulation results instead of running new simulations.
    """

    def __init__(self, data_path, config_path=None, project_root=None):
        super().__init__(config_path=config_path, project_root=project_root)

        # Load pre-collected data
        with open(data_path) as f:
            self.replay_data = json.load(f)

        self.replay_idx = 0
        print(f"  Loaded {len(self.replay_data)} pre-collected coverage samples")

    def _run_simulation(self, knobs):
        """Replay pre-collected coverage data."""
        if self.replay_idx >= len(self.replay_data):
            self.replay_idx = 0  # Loop

        data = self.replay_data[self.replay_idx]
        self.replay_idx += 1

        # Convert replay data format to expected coverage format
        if 'func_cov' in data:
            return {
                'functional_coverage': data['func_cov'],
                'security_coverage': data.get('sec_cov', 0),
                'pmp_coverage': data.get('pmp_cov', 0),
                'instruction_types_hit': int(data['func_cov'] * 11),
                'instruction_types_total': 11,
                'security_alerts_hit': int(data.get('sec_cov', 0) * 6),
                'security_alerts_total': 6,
                'privilege_modes_hit': 2 if data.get('sec_cov', 0) > 0.3 else 1,
            }
        return data


# =========================================================================
# Training Callbacks
# =========================================================================

class DetailedLoggingCallback(BaseCallback):
    """Logs detailed training metrics to JSON for analysis."""

    def __init__(self, log_dir, verbose=0):
        super().__init__(verbose)
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.metrics = []
        self.best_reward = -float('inf')

    def _on_step(self):
        if self.locals.get('infos'):
            for info in self.locals['infos']:
                entry = {
                    'timestep': self.num_timesteps,
                    'reward': float(info.get('reward', 0)),
                }
                if 'coverage_report' in info:
                    cov = info['coverage_report']
                    entry['func_cov'] = cov.get('functional_coverage', 0)
                    entry['sec_cov'] = cov.get('security_coverage', 0)
                    entry['pmp_cov'] = cov.get('pmp_coverage', 0)
                self.metrics.append(entry)

        # Save periodically
        if self.num_timesteps % 100 == 0 and self.metrics:
            self._save_metrics()

        return True

    def _on_training_end(self):
        self._save_metrics()
        self._save_summary()

    def _save_metrics(self):
        with open(self.log_dir / 'training_metrics.json', 'w') as f:
            json.dump(self.metrics, f, indent=2)

    def _save_summary(self):
        if not self.metrics:
            return

        # Compute summary statistics
        rewards = [m.get('reward', 0) for m in self.metrics]
        func_covs = [m.get('func_cov', 0) for m in self.metrics if 'func_cov' in m]
        sec_covs = [m.get('sec_cov', 0) for m in self.metrics if 'sec_cov' in m]

        summary = {
            'total_timesteps': self.num_timesteps,
            'total_episodes': len(self.metrics),
            'reward': {
                'mean': float(np.mean(rewards)),
                'max': float(np.max(rewards)),
                'min': float(np.min(rewards)),
                'final_10_mean': float(np.mean(rewards[-10:])),
            },
            'functional_coverage': {
                'mean': float(np.mean(func_covs)) if func_covs else 0,
                'max': float(np.max(func_covs)) if func_covs else 0,
                'final': float(func_covs[-1]) if func_covs else 0,
            },
            'security_coverage': {
                'mean': float(np.mean(sec_covs)) if sec_covs else 0,
                'max': float(np.max(sec_covs)) if sec_covs else 0,
                'final': float(sec_covs[-1]) if sec_covs else 0,
            },
        }

        with open(self.log_dir / 'training_summary.json', 'w') as f:
            json.dump(summary, f, indent=2)

        print(f"\n  Training Summary:")
        print(f"    Total timesteps: {summary['total_timesteps']}")
        print(f"    Mean reward:     {summary['reward']['mean']:.4f}")
        print(f"    Max func cov:    {summary['functional_coverage']['max']:.2%}")
        print(f"    Max sec cov:     {summary['security_coverage']['max']:.2%}")


# =========================================================================
# Main Training Functions
# =========================================================================

def train_live(config_path, timesteps, algorithm, output_dir):
    """Train with live RTL simulation (Verilator + cocotb)."""
    print("\n" + "="*60)
    print("  SecVeriRL — LIVE Training Mode")
    print("  Each step runs a real Verilator simulation")
    print("="*60)

    env = LiveVerificationEnv(
        config_path=config_path,
        project_root=str(PROJECT_ROOT),
        sim_timeout=120,
    )
    env = Monitor(env, str(output_dir / 'monitor'))

    return _train(env, timesteps, algorithm, output_dir)


def train_mock(config_path, timesteps, algorithm, output_dir):
    """Train with simulated coverage (no RTL simulator needed)."""
    print("\n" + "="*60)
    print("  SecVeriRL — MOCK Training Mode")
    print("  Using simulated coverage (no simulator required)")
    print("="*60)

    env = VerificationEnv(
        config_path=config_path,
        project_root=str(PROJECT_ROOT),
    )
    env = Monitor(env, str(output_dir / 'monitor'))

    return _train(env, timesteps, algorithm, output_dir)


def train_offline(data_path, config_path, timesteps, algorithm, output_dir):
    """Train on pre-collected coverage data."""
    print("\n" + "="*60)
    print("  SecVeriRL — OFFLINE Training Mode")
    print(f"  Replaying data from: {data_path}")
    print("="*60)

    env = OfflineVerificationEnv(
        data_path=data_path,
        config_path=config_path,
        project_root=str(PROJECT_ROOT),
    )
    env = Monitor(env, str(output_dir / 'monitor'))

    return _train(env, timesteps, algorithm, output_dir)


def _train(env, timesteps, algorithm, output_dir):
    """Core training loop (shared by all modes)."""
    if not HAS_SB3:
        print("[ERROR] stable-baselines3 required. Install: pip install stable-baselines3")
        return None

    output_dir.mkdir(parents=True, exist_ok=True)

    # Create model
    if algorithm.upper() == 'PPO':
        model = PPO(
            "MlpPolicy", env,
            verbose=1,
            learning_rate=3e-4,
            n_steps=32,
            batch_size=16,
            n_epochs=4,
            gamma=0.99,
            gae_lambda=0.95,
            clip_range=0.2,
            tensorboard_log=str(output_dir / 'tb_logs'),
        )
    else:  # A2C
        model = A2C(
            "MlpPolicy", env,
            verbose=1,
            learning_rate=7e-4,
            n_steps=5,
            gamma=0.99,
            gae_lambda=1.0,
            ent_coef=0.01,
            vf_coef=0.5,
            max_grad_norm=0.5,
            tensorboard_log=str(output_dir / 'tb_logs'),
        )

    print(f"\n  Algorithm: {algorithm}")
    print(f"  Timesteps: {timesteps}")
    print(f"  Output:    {output_dir}")
    print(f"  Policy:    MlpPolicy (64x64 hidden layers)")
    print()

    # Callbacks
    callbacks = [
        DetailedLoggingCallback(log_dir=str(output_dir / 'logs')),
        CheckpointCallback(
            save_freq=max(timesteps // 5, 100),
            save_path=str(output_dir / 'checkpoints'),
            name_prefix='secverirl',
        ),
    ]

    # Train
    t_start = time.time()
    model.learn(total_timesteps=timesteps, callback=callbacks)
    t_train = time.time() - t_start

    # Save final model
    model_path = output_dir / 'final_model'
    model.save(str(model_path))

    # Save training metadata
    metadata = {
        'algorithm': algorithm,
        'timesteps': timesteps,
        'training_time_sec': t_train,
        'model_path': str(model_path),
        'timestamp': datetime.now().isoformat(),
    }
    with open(output_dir / 'training_metadata.json', 'w') as f:
        json.dump(metadata, f, indent=2)

    print(f"\n  ✓ Training complete in {t_train:.1f}s")
    print(f"  ✓ Model saved: {model_path}")

    return model


def run_trained_agent(model_path, config_path, n_episodes=10, output_dir=None):
    """Run a trained agent to generate optimized test configurations."""
    print("\n" + "="*60)
    print("  SecVeriRL — Running Trained Agent")
    print("="*60)

    if not HAS_SB3:
        return

    env = VerificationEnv(
        config_path=config_path,
        project_root=str(PROJECT_ROOT),
    )

    model = A2C.load(str(model_path))

    best_coverage = {'functional_coverage': 0, 'security_coverage': 0}
    all_knobs = []
    all_results = []

    for ep in range(n_episodes):
        obs, _ = env.reset()
        done = False
        ep_reward = 0
        ep_knobs = []

        while not done:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, info = env.step(action)
            ep_reward += reward
            done = terminated or truncated

            if 'knobs' in info:
                ep_knobs.append(info['knobs'])

        cov = info.get('coverage_report', {})
        all_results.append({
            'episode': ep,
            'reward': float(ep_reward),
            'functional_coverage': cov.get('functional_coverage', 0),
            'security_coverage': cov.get('security_coverage', 0),
            'knobs_used': ep_knobs,
        })

        # Track best
        if cov.get('security_coverage', 0) > best_coverage['security_coverage']:
            best_coverage = cov

        print(f"  Episode {ep:2d}: reward={ep_reward:+.3f}  "
              f"func={cov.get('functional_coverage', 0):.1%}  "
              f"sec={cov.get('security_coverage', 0):.1%}")

    # Save results
    if output_dir:
        output_dir = Path(output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        with open(output_dir / 'inference_results.json', 'w') as f:
            json.dump(all_results, f, indent=2)

    print(f"\n  Best security coverage achieved: {best_coverage.get('security_coverage', 0):.2%}")

    # === LLM Gap Analysis ===
    func_cov = best_coverage.get('functional_coverage', 0)
    sec_cov = best_coverage.get('security_coverage', 0)
    pmp_cov = best_coverage.get('pmp_coverage', 0)

    if func_cov < 1.0 or sec_cov < 1.0 or pmp_cov < 1.0:
        print("\n  Coverage < 100% — Running LLM gap analysis...")
        try:
            analyze_coverage_gaps(
                coverage_report=best_coverage,
                project_root=str(PROJECT_ROOT),
                output_dir=str(output_dir) if output_dir else None,
            )
        except Exception as e:
            print(f"  [WARN] LLM analysis failed: {e}")
    else:
        print("\n  ✓ 100% coverage achieved! No LLM analysis needed.")

    return all_results


# =========================================================================
# Entry Point
# =========================================================================

def main():
    parser = argparse.ArgumentParser(
        description='SecVeriRL RL Agent Training',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Quick test (no simulator needed)
  python scripts/train_agent.py --mode mock --timesteps 5000

  # Train with real simulation
  python scripts/train_agent.py --mode live --timesteps 500

  # Train on collected data
  python scripts/train_agent.py --mode offline --data results/coverage_history.json

  # Run trained agent
  python scripts/train_agent.py --mode infer --model results/training/final_model
        """,
    )
    parser.add_argument('--mode', choices=['live', 'mock', 'offline', 'infer'],
                       default='mock',
                       help='Training mode (default: mock)')
    parser.add_argument('--config', type=str,
                       default='config/dut_profiles/rv32i_basic.yaml',
                       help='DUT configuration file')
    parser.add_argument('--timesteps', type=int, default=5000,
                       help='Total training timesteps (default: 5000)')
    parser.add_argument('--algorithm', type=str, default='A2C',
                       choices=['A2C', 'PPO'],
                       help='RL algorithm (default: A2C)')
    parser.add_argument('--data', type=str, default=None,
                       help='Path to coverage data (for offline mode)')
    parser.add_argument('--model', type=str, default=None,
                       help='Path to trained model (for infer mode)')
    parser.add_argument('--episodes', type=int, default=10,
                       help='Inference episodes (for infer mode)')
    parser.add_argument('--output', type=str, default=None,
                       help='Output directory')
    args = parser.parse_args()

    # Resolve paths
    config_path = str(PROJECT_ROOT / args.config)
    if not os.path.exists(config_path):
        config_path = None

    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    output_dir = Path(args.output) if args.output else \
                 PROJECT_ROOT / 'results' / 'training' / f'{args.mode}_{timestamp}'

    # Dispatch
    if args.mode == 'live':
        train_live(config_path, args.timesteps, args.algorithm, output_dir)

    elif args.mode == 'mock':
        train_mock(config_path, args.timesteps, args.algorithm, output_dir)

    elif args.mode == 'offline':
        if not args.data:
            print("[ERROR] --data required for offline mode")
            sys.exit(1)
        train_offline(args.data, config_path, args.timesteps, args.algorithm, output_dir)

    elif args.mode == 'infer':
        model_path = args.model
        if not model_path:
            # Try to find latest trained model
            training_dir = PROJECT_ROOT / 'results' / 'training'
            if training_dir.exists():
                runs = sorted(training_dir.glob('*/final_model.zip'))
                if runs:
                    model_path = str(runs[-1]).replace('.zip', '')
        if not model_path:
            print("[ERROR] No trained model found. Train first with --mode mock")
            sys.exit(1)
        run_trained_agent(model_path, config_path, args.episodes, output_dir)


if __name__ == '__main__':
    main()

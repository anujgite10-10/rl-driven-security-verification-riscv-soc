"""
SecVeriRL — RL Agent (A2C-based Adaptive Test Generator)
========================================================
Reinforcement Learning agent that observes coverage state and
generates test knobs to maximize multi-objective coverage.
"""

import os
import json
import numpy as np
import gymnasium as gym
from gymnasium import spaces
from stable_baselines3 import A2C, PPO
from stable_baselines3.common.callbacks import BaseCallback
import yaml
import subprocess
import time
from pathlib import Path


class VerificationEnv(gym.Env):
    """
    Gymnasium environment that wraps the hardware verification loop.

    Observation: coverage vector (functional + security + assertion bins)
    Action: test knob configuration
    Reward: multi-objective coverage improvement
    """

    metadata = {"render_modes": ["human"]}

    # Test scenario options
    SCENARIOS = ['random_alu', 'memory_stress', 'pmp_violation',
                 'privilege_switch', 'interrupt_storm', 'csr_access',
                 'bus_protocol', 'security_alerts', 'mixed']

    PMP_MODES = ['all_open', 'm_only_secure', 'mixed_permissions', 'locked_regions']

    def __init__(self, config_path=None, project_root=None):
        super().__init__()

        self.project_root = Path(project_root or os.getcwd())
        self.results_dir = self.project_root / 'results'
        self.results_dir.mkdir(parents=True, exist_ok=True)

        # Load config
        if config_path:
            with open(config_path, 'r') as f:
                self.config = yaml.safe_load(f)
        else:
            self.config = self._default_config()

        # Coverage vector dimension
        self.cov_dim = 30  # insn_types(11) + priv(3) + security(6) + pmp(7) + traps(2) + extra

        # Observation space: coverage vector (values 0-1)
        self.observation_space = spaces.Box(
            low=0.0, high=1.0, shape=(self.cov_dim,), dtype=np.float32
        )

        # Action space: normalized to [-1.0, 1.0] for stable-baselines3 continuous policies
        # [scenario, pmp_mode, priv_bias, mem_pattern, irq_freq, illegal_rate, test_length]
        self.action_space = spaces.Box(
            low=-1.0, high=1.0, shape=(7,), dtype=np.float32
        )

        # State tracking
        self.current_coverage = np.zeros(self.cov_dim, dtype=np.float32)
        self.prev_coverage = np.zeros(self.cov_dim, dtype=np.float32)
        self.episode_step = 0
        self.max_steps = self.config.get('rl_agent', {}).get('max_steps_per_episode', 50)
        self.total_simulations = 0

        # Reward weights from config
        rw = self.config.get('rl_agent', {}).get('reward_weights', {})
        self.w_func = rw.get('functional_coverage', 0.3)
        self.w_sec = rw.get('security_coverage', 0.4)
        self.w_assert = rw.get('assertion_coverage', 0.2)
        self.w_bug = rw.get('bug_detection', 0.1)

        # Coverage history for analysis
        self.coverage_history = []

    def reset(self, seed=None, options=None):
        super().reset(seed=seed)
        self.current_coverage = np.zeros(self.cov_dim, dtype=np.float32)
        self.prev_coverage = np.zeros(self.cov_dim, dtype=np.float32)
        self.episode_step = 0
        return self.current_coverage.copy(), {}

    def step(self, action):
        """Execute one verification iteration with the given test knobs."""
        self.episode_step += 1
        self.total_simulations += 1

        # Decode action into test knobs
        knobs = self._decode_action(action)

        # Run simulation with these knobs
        coverage_result = self._run_simulation(knobs)

        # Update coverage state
        self.prev_coverage = self.current_coverage.copy()
        new_coverage = self._parse_coverage(coverage_result)
        
        # Accumulate coverage across the episode
        self.current_coverage = np.maximum(self.current_coverage, new_coverage)

        # Calculate reward based on the accumulated delta
        reward = self._calculate_reward()

        # Check termination based on cumulative targets
        terminated = self._check_coverage_target()
        truncated = (self.episode_step >= self.max_steps)

        # Info dict
        info = {
            'step': self.episode_step,
            'total_sims': self.total_simulations,
            'coverage_report': coverage_result,
            'knobs': knobs,
            'reward': reward,
        }

        # Calculate cumulative percentages for logging
        cum_func_cov = float(np.mean(self.current_coverage[:11]))
        cum_sec_cov = float(np.mean(self.current_coverage[14:20]))

        self.coverage_history.append({
            'step': self.episode_step,
            'func_cov': cum_func_cov,
            'sec_cov': cum_sec_cov,
            'reward': float(reward),
        })

        return self.current_coverage.copy(), reward, terminated, truncated, info

    def _decode_action(self, action):
        """Convert continuous normalized action vector [-1, 1] to test knobs dict."""
        # Helper to map [-1, 1] to [min_val, max_val]
        def unnormalize(val, min_val, max_val):
            return min_val + (val + 1.0) / 2.0 * (max_val - min_val)

        scenario_idx = int(np.clip(unnormalize(action[0], 0, len(self.SCENARIOS) - 1 + 0.99), 0, len(self.SCENARIOS) - 1))
        pmp_mode_idx = int(np.clip(unnormalize(action[1], 0, len(self.PMP_MODES) - 1 + 0.99), 0, len(self.PMP_MODES) - 1))

        return {
            'test_scenario': self.SCENARIOS[scenario_idx],
            'pmp_config_mode': self.PMP_MODES[pmp_mode_idx],
            'privilege_bias': float(np.clip(unnormalize(action[2], 0.0, 1.0), 0.0, 1.0)),
            'memory_pattern': ['sequential', 'random', 'boundary', 'crossing'][int(np.clip(unnormalize(action[3], 0, 3.99), 0, 3))],
            'interrupt_rate': float(np.clip(unnormalize(action[4], 0.0, 1.0), 0.0, 1.0)),
            'illegal_insn_rate': float(np.clip(unnormalize(action[5], 0.0, 0.3), 0.0, 0.3)),
            'test_length': int(unnormalize(action[6], 50, 500)),
        }

    def _run_simulation(self, knobs):
        """Run a single simulation iteration and return coverage."""
        # Write knobs to file for cocotb testbench to read
        knobs_path = self.results_dir / 'current_knobs.json'
        with open(knobs_path, 'w') as f:
            json.dump(knobs, f, indent=2)

        # Remove the sim_build directory to force a clean run (Verilator doesn't always rebuild testbench cleanly)
        import shutil
        sim_build_dir = self.project_root / 'sim_build'
        if sim_build_dir.exists():
            shutil.rmtree(sim_build_dir)

        # Invoke the real verification run
        print(f"Running simulation with scenario: {knobs['test_scenario']}...")
        try:
            result = subprocess.run(
                ['make', '-f', 'verification/Makefile', 'SIM=verilator', 'TESTCASE=test_rl_driven'],
                cwd=str(self.project_root),
                capture_output=True,
                text=True,
                timeout=120
            )
            if result.returncode != 0:
                print(f"Simulation failed with return code {result.returncode}")
                print(f"STDOUT: {result.stdout}")
                print(f"STDERR: {result.stderr}")
                # Return empty coverage on failure
                return {}
        except subprocess.TimeoutExpired:
            print("Simulation timed out!")
            return {}

        # Read the generated coverage result
        cov_path = self.results_dir / 'coverage_result.json'
        if cov_path.exists():
            try:
                with open(cov_path, 'r') as f:
                    return json.load(f)
            except json.JSONDecodeError:
                print("Failed to parse coverage JSON")
                return {}
        else:
            print("Coverage result file not found!")
            return {}

    def _simulate_coverage(self, knobs):
        """Simulate coverage results (for standalone agent testing)."""
        # This simulates what the actual cocotb testbench would return
        base_func = 0.4 + np.random.random() * 0.3
        base_sec = 0.1 + np.random.random() * 0.2

        # Scenario-dependent boosts
        scenario = knobs['test_scenario']
        if scenario == 'pmp_violation':
            base_sec += 0.3
        elif scenario == 'privilege_switch':
            base_sec += 0.2
            base_func += 0.1
        elif scenario == 'memory_stress':
            base_func += 0.2
        elif scenario == 'mixed':
            base_func += 0.15
            base_sec += 0.1

        # Interrupt injection helps security coverage
        base_sec += knobs['interrupt_rate'] * 0.1

        # Determine which specific bins were hit
        insn_opcodes = [0x37, 0x17, 0x6F, 0x67, 0x63, 0x03, 0x23, 0x13, 0x33, 0x0F, 0x73]
        n_insn = int(min(base_func * 11, 11))
        insn_hit = {str(op): (i < n_insn) for i, op in enumerate(insn_opcodes)}

        sec_codes = [0x01, 0x02, 0x03, 0x04, 0x05, 0x06]
        n_sec = int(min(base_sec * 6, 6))
        sec_hit = {str(c): (i < n_sec) for i, c in enumerate(sec_codes)}

        pmp_names = ['u_read_m_region', 'u_write_m_region', 'u_exec_m_region',
                     'm_read_all', 'm_write_all', 'pmp_cfg_written', 'pmp_locked']
        n_pmp = int(min(base_sec * 7, 7))
        pmp_hit = {name: (i < n_pmp) for i, name in enumerate(pmp_names)}

        priv_hit = {'0': scenario in ['privilege_switch', 'mixed'],
                    '1': False,
                    '3': True}

        return {
            'functional_coverage': min(base_func, 1.0),
            'security_coverage': min(base_sec, 1.0),
            'pmp_coverage': min(base_sec * 0.8, 1.0),
            'instruction_types_hit': n_insn,
            'instruction_types_total': 11,
            'security_alerts_hit': n_sec,
            'security_alerts_total': 6,
            'privilege_modes_hit': 2 if scenario in ['privilege_switch', 'mixed'] else 1,
            'details': {
                'insn_types': insn_hit,
                'security_alerts': sec_hit,
                'pmp_scenarios': pmp_hit,
                'priv_modes': priv_hit,
            }
        }

    def _parse_coverage(self, cov_result):
        """Convert coverage report to observation vector using specific bins."""
        vec = np.zeros(self.cov_dim, dtype=np.float32)

        details = cov_result.get('details', {})

        # Functional / Instruction types (0-10)
        insn_types = details.get('insn_types', {})
        # Opcodes based on CoverageCollector in tb_top.py
        # 55=LUI, 23=AUIPC, 111=JAL, 103=JALR, 99=BRANCH, 3=LOAD, 35=STORE, 19=IMM, 51=REG, 15=FENCE, 115=SYSTEM
        insn_opcodes = ['55', '23', '111', '103', '99', '3', '35', '19', '51', '15', '115']
        for i, op in enumerate(insn_opcodes):
            if insn_types.get(op, False):
                vec[i] = 1.0

        # Privilege modes (bins 11-13)
        priv_modes = details.get('priv_modes', {})
        if priv_modes.get('0', False): vec[11] = 1.0
        if priv_modes.get('1', False): vec[12] = 1.0
        if priv_modes.get('3', False): vec[13] = 1.0

        # Security alerts (bins 14-19)
        sec_alerts = details.get('security_alerts', {})
        for i, alert in enumerate(['1', '2', '3', '4', '5', '6']):
            if sec_alerts.get(alert, False):
                vec[14 + i] = 1.0

        # PMP scenarios (bins 20-26)
        pmp_scenarios = details.get('pmp_scenarios', {})
        pmp_names = ['u_read_m_region', 'u_write_m_region', 'u_exec_m_region',
                     'm_read_all', 'm_write_all', 'pmp_cfg_written', 'pmp_locked']
        for i, name in enumerate(pmp_names):
            if pmp_scenarios.get(name, False):
                vec[20 + i] = 1.0

        # Overall metrics (bins 27-29) - holds max per run
        vec[27] = cov_result.get('functional_coverage', 0)
        vec[28] = cov_result.get('security_coverage', 0)
        vec[29] = cov_result.get('pmp_coverage', 0)

        return vec

    def _calculate_reward(self):
        """Multi-objective reward: coverage improvement."""
        delta = self.current_coverage - self.prev_coverage
        delta_positive = np.maximum(delta, 0)  # Only reward improvement

        # Weighted coverage improvement
        # Functional bins (0-10)
        func_gain = np.sum(delta_positive[:11]) / 11.0
        # Security bins (14-19)
        sec_gain = np.sum(delta_positive[14:20]) / 6.0
        # PMP bins
        pmp_gain = float(delta_positive[20])

        reward = (self.w_func * func_gain +
                  self.w_sec * sec_gain +
                  self.w_assert * pmp_gain)

        # Bonus for hitting new coverage bins
        new_bins = np.sum((self.prev_coverage == 0) & (self.current_coverage > 0))
        reward += 0.1 * new_bins

        # Penalty for stagnation
        if np.sum(delta_positive) < 0.001:
            reward -= 0.05

        return float(reward)

    def _check_coverage_target(self):
        """Check if coverage targets are met."""
        targets = self.config.get('coverage', {})
        func_target = targets.get('functional_target', 0.95)
        sec_target = targets.get('security_target', 0.90)

        func_cov = np.mean(self.current_coverage[:11])
        sec_cov = np.mean(self.current_coverage[14:20])

        return (func_cov >= func_target) and (sec_cov >= sec_target)

    def _default_config(self):
        return {
            'rl_agent': {
                'max_steps_per_episode': 50,
                'reward_weights': {
                    'functional_coverage': 0.3,
                    'security_coverage': 0.4,
                    'assertion_coverage': 0.2,
                    'bug_detection': 0.1,
                }
            },
            'coverage': {
                'functional_target': 0.95,
                'security_target': 0.90,
            }
        }


class CoverageCallback(BaseCallback):
    """Callback to log coverage progress during training."""

    def __init__(self, log_dir, verbose=0):
        super().__init__(verbose)
        self.log_dir = Path(log_dir)
        self.log_dir.mkdir(parents=True, exist_ok=True)
        self.episode_rewards = []
        self.coverage_data = []

    def _on_step(self):
        # Log info from environment
        if self.locals.get('infos'):
            for info in self.locals['infos']:
                if 'coverage_report' in info:
                    self.coverage_data.append({
                        'timestep': self.num_timesteps,
                        'func_cov': info['coverage_report'].get('functional_coverage', 0),
                        'sec_cov': info['coverage_report'].get('security_coverage', 0),
                    })
        return True

    def _on_training_end(self):
        # Save training log
        with open(self.log_dir / 'training_log.json', 'w') as f:
            json.dump(self.coverage_data, f, indent=2)


def train_agent(config_path=None, project_root=None, total_timesteps=10000,
                algorithm='A2C', save_path=None):
    """Train the RL agent."""
    project_root = Path(project_root or os.getcwd())

    # Create environment
    env = VerificationEnv(config_path=config_path, project_root=str(project_root))

    # Select algorithm
    if algorithm.upper() == 'PPO':
        model = PPO("MlpPolicy", env, verbose=1,
                    learning_rate=0.0003, n_steps=32, batch_size=16)
    else:
        model = A2C("MlpPolicy", env, verbose=1,
                    learning_rate=0.0007, n_steps=5)

    # Callback
    callback = CoverageCallback(log_dir=str(project_root / 'results' / 'rl_logs'))

    # Train
    print(f"Training {algorithm} agent for {total_timesteps} timesteps...")
    model.learn(total_timesteps=total_timesteps, callback=callback)

    # Save model
    save_path = save_path or str(project_root / 'results' / 'rl_model')
    model.save(save_path)
    print(f"Model saved to {save_path}")

    # Save coverage history
    with open(project_root / 'results' / 'coverage_history.json', 'w') as f:
        json.dump(env.coverage_history, f, indent=2)

    return model, env


def run_inference(model_path, config_path=None, project_root=None, n_episodes=10):
    """Run trained agent for test generation."""
    project_root = Path(project_root or os.getcwd())
    env = VerificationEnv(config_path=config_path, project_root=str(project_root))

    model = A2C.load(model_path)

    all_results = []
    for ep in range(n_episodes):
        obs, _ = env.reset()
        done = False
        ep_reward = 0

        while not done:
            action, _ = model.predict(obs, deterministic=True)
            obs, reward, terminated, truncated, info = env.step(action)
            ep_reward += reward
            done = terminated or truncated

        all_results.append({
            'episode': ep,
            'total_reward': ep_reward,
            'final_coverage': info.get('coverage_report', {}),
            'steps': info.get('step', 0),
        })
        print(f"Episode {ep}: reward={ep_reward:.3f}, "
              f"func={info['coverage_report'].get('functional_coverage', 0):.2%}, "
              f"sec={info['coverage_report'].get('security_coverage', 0):.2%}")

    # Save results
    with open(project_root / 'results' / 'inference_results.json', 'w') as f:
        json.dump(all_results, f, indent=2)

    return all_results


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='SecVeriRL RL Agent')
    parser.add_argument('--mode', choices=['train', 'infer'], default='train')
    parser.add_argument('--config', type=str, default=None)
    parser.add_argument('--project-root', type=str, default='.')
    parser.add_argument('--timesteps', type=int, default=10000)
    parser.add_argument('--algorithm', type=str, default='A2C')
    parser.add_argument('--model-path', type=str, default=None)
    parser.add_argument('--episodes', type=int, default=10)
    args = parser.parse_args()

    if args.mode == 'train':
        train_agent(
            config_path=args.config,
            project_root=args.project_root,
            total_timesteps=args.timesteps,
            algorithm=args.algorithm,
        )
    else:
        model_path = args.model_path or 'results/rl_model'
        run_inference(
            model_path=model_path,
            config_path=args.config,
            project_root=args.project_root,
            n_episodes=args.episodes,
        )

"""
SecVeriRL — Coverage Analysis & Visualization
==============================================
Generates coverage reports, trend plots, and comparison charts
for the verification results.
"""

import json
import os
import sys
from pathlib import Path
from datetime import datetime

try:
    import matplotlib
    matplotlib.use('Agg')
    import matplotlib.pyplot as plt
    import matplotlib.ticker as mticker
    HAS_MPL = True
except ImportError:
    HAS_MPL = False

try:
    import numpy as np
    HAS_NP = True
except ImportError:
    HAS_NP = False


def load_coverage_history(results_dir):
    """Load all coverage data from a results directory."""
    results_dir = Path(results_dir)
    coverage_data = []

    # Load from coverage subdirectory
    cov_dir = results_dir / 'coverage'
    if cov_dir.exists():
        for f in sorted(cov_dir.glob('cov_*.json')):
            with open(f) as fh:
                data = json.load(fh)
                data['source_file'] = f.name
                coverage_data.append(data)

    # Also try coverage_history.json
    hist_file = results_dir / 'coverage_history.json'
    if hist_file.exists():
        with open(hist_file) as f:
            coverage_data = json.load(f)

    return coverage_data


def generate_coverage_plot(coverage_data, output_path):
    """Generate coverage progression plot."""
    if not HAS_MPL or not HAS_NP:
        print("  [WARN] matplotlib/numpy not available, skipping plot")
        return

    steps = list(range(len(coverage_data)))
    func_cov = [d.get('functional_coverage', d.get('func_cov', 0)) for d in coverage_data]
    sec_cov = [d.get('security_coverage', d.get('sec_cov', 0)) for d in coverage_data]

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    # Coverage progression
    ax1.plot(steps, func_cov, 'b-o', label='Functional', linewidth=2, markersize=4)
    ax1.plot(steps, sec_cov, 'r-s', label='Security', linewidth=2, markersize=4)
    ax1.axhline(y=0.95, color='b', linestyle='--', alpha=0.5, label='Func Target (95%)')
    ax1.axhline(y=0.90, color='r', linestyle='--', alpha=0.5, label='Sec Target (90%)')
    ax1.set_xlabel('Iteration')
    ax1.set_ylabel('Coverage')
    ax1.set_title('Coverage Progression')
    ax1.legend()
    ax1.grid(True, alpha=0.3)
    ax1.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=1.0))

    # Coverage bar chart (final state)
    if coverage_data:
        final = coverage_data[-1]
        categories = ['Functional', 'Security', 'PMP']
        values = [
            final.get('functional_coverage', final.get('func_cov', 0)),
            final.get('security_coverage', final.get('sec_cov', 0)),
            final.get('pmp_coverage', 0),
        ]
        targets = [0.95, 0.90, 0.85]
        colors = ['#4CAF50' if v >= t else '#FF5722' for v, t in zip(values, targets)]

        bars = ax2.bar(categories, values, color=colors, alpha=0.8, edgecolor='black')
        for bar, target in zip(bars, targets):
            ax2.axhline(y=target, color='gray', linestyle='--', alpha=0.5)

        ax2.set_ylabel('Coverage')
        ax2.set_title('Final Coverage Summary')
        ax2.set_ylim(0, 1.1)
        ax2.yaxis.set_major_formatter(mticker.PercentFormatter(xmax=1.0))

        # Add value labels
        for bar, val in zip(bars, values):
            ax2.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.02,
                    f'{val:.1%}', ha='center', va='bottom', fontweight='bold')

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Plot saved: {output_path}")


def generate_comparison_plot(baseline_data, rl_data, output_path):
    """Generate baseline vs RL comparison chart."""
    if not HAS_MPL or not HAS_NP:
        return

    fig, ax = plt.subplots(figsize=(10, 6))

    categories = ['Functional\nCoverage', 'Security\nCoverage', 'PMP\nCoverage',
                  'Simulation\nCycles']

    if baseline_data and rl_data:
        baseline_vals = [
            baseline_data.get('functional_coverage', 0),
            baseline_data.get('security_coverage', 0),
            baseline_data.get('pmp_coverage', 0),
            baseline_data.get('cycles', 0) / 1000,
        ]
        rl_vals = [
            rl_data.get('functional_coverage', 0),
            rl_data.get('security_coverage', 0),
            rl_data.get('pmp_coverage', 0),
            rl_data.get('cycles', 0) / 1000,
        ]

        x = np.arange(len(categories))
        width = 0.35

        ax.bar(x - width/2, baseline_vals, width, label='CRV Baseline',
               color='#90CAF9', edgecolor='black')
        ax.bar(x + width/2, rl_vals, width, label='SecVeriRL (RL)',
               color='#66BB6A', edgecolor='black')

        ax.set_xticks(x)
        ax.set_xticklabels(categories)
        ax.legend()
        ax.set_title('Baseline vs SecVeriRL Comparison')
        ax.grid(True, alpha=0.3, axis='y')

    plt.tight_layout()
    plt.savefig(output_path, dpi=150, bbox_inches='tight')
    plt.close()
    print(f"  Comparison plot saved: {output_path}")


def generate_text_report(coverage_data, output_path):
    """Generate text-based coverage report."""
    with open(output_path, 'w') as f:
        f.write("="*70 + "\n")
        f.write("  SecVeriRL Verification Report\n")
        f.write(f"  Generated: {datetime.now().isoformat()}\n")
        f.write("="*70 + "\n\n")

        if not coverage_data:
            f.write("  No coverage data available.\n")
            return

        final = coverage_data[-1]

        f.write("  FINAL COVERAGE SUMMARY\n")
        f.write("  " + "-"*40 + "\n")
        f.write(f"  Functional Coverage: {final.get('functional_coverage', 0):.2%}\n")
        f.write(f"  Security Coverage:   {final.get('security_coverage', 0):.2%}\n")
        f.write(f"  PMP Coverage:        {final.get('pmp_coverage', 0):.2%}\n")
        f.write(f"  Total Iterations:    {len(coverage_data)}\n")
        f.write("\n")

        f.write("  COVERAGE PROGRESSION\n")
        f.write("  " + "-"*40 + "\n")
        for i, d in enumerate(coverage_data):
            func = d.get('functional_coverage', d.get('func_cov', 0))
            sec = d.get('security_coverage', d.get('sec_cov', 0))
            f.write(f"  Iter {i:3d}: Func={func:.2%}  Sec={sec:.2%}\n")

    print(f"  Text report saved: {output_path}")


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description='Coverage Analysis')
    parser.add_argument('--results-dir', type=str, required=True)
    parser.add_argument('--output-dir', type=str, default=None)
    args = parser.parse_args()

    results_dir = Path(args.results_dir)
    output_dir = Path(args.output_dir) if args.output_dir else results_dir / 'reports'
    output_dir.mkdir(parents=True, exist_ok=True)

    data = load_coverage_history(results_dir)
    generate_text_report(data, output_dir / 'coverage_report.txt')
    generate_coverage_plot(data, output_dir / 'coverage_plot.png')

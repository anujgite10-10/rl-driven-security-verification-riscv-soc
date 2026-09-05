"""
SecVeriRL — Formal Counterexample Feedback Module
=================================================
Parses SymbiYosys counterexample traces and translates them into
simulation test stimuli for the RL agent's experience buffer.
"""

import json
import re
import os
from pathlib import Path
from dataclasses import dataclass, field
from typing import List, Dict, Optional


@dataclass
class FormalCounterexample:
    """Represents a formal verification counterexample."""
    property_name: str
    trace_length: int
    signals: Dict[str, List[int]] = field(default_factory=dict)
    is_security: bool = False
    severity: str = "medium"  # low, medium, high, critical


@dataclass
class TranslatedStimulus:
    """A counterexample translated into simulation test parameters."""
    source_property: str
    knobs: Dict
    priority: float  # Higher = more important
    instructions: List[int] = field(default_factory=list)


class FormalFeedbackEngine:
    """
    Parses formal verification results from SymbiYosys and translates
    counterexamples into directed test stimuli.
    """

    # Map property names to test scenarios
    PROPERTY_SCENARIO_MAP = {
        'prop_pmp_read_enforce': 'pmp_violation',
        'prop_pmp_write_enforce': 'pmp_violation',
        'prop_pmp_exec_enforce': 'pmp_violation',
        'prop_priv_no_escalation': 'privilege_switch',
        'prop_csr_access_control': 'csr_access',
        'prop_illegal_insn_trap': 'mixed',
        'prop_interrupt_priority': 'interrupt_storm',
        'prop_axi_protocol': 'bus_protocol',
    }

    PROPERTY_SEVERITY = {
        'prop_pmp_read_enforce': 'critical',
        'prop_pmp_write_enforce': 'critical',
        'prop_pmp_exec_enforce': 'critical',
        'prop_priv_no_escalation': 'critical',
        'prop_csr_access_control': 'high',
        'prop_illegal_insn_trap': 'high',
        'prop_interrupt_priority': 'medium',
        'prop_axi_protocol': 'medium',
    }

    def __init__(self, formal_results_dir):
        self.results_dir = Path(formal_results_dir)
        self.counterexamples = []
        self.translated_stimuli = []

    def parse_results(self):
        """Parse all SymbiYosys result files."""
        self.counterexamples = []

        # Look for .vcd trace files from SymbiYosys
        for vcd_file in self.results_dir.glob('**/*.vcd'):
            cex = self._parse_vcd_trace(vcd_file)
            if cex:
                self.counterexamples.append(cex)

        # Also parse the SymbiYosys log for property status
        for log_file in self.results_dir.glob('**/*.log'):
            self._parse_sby_log(log_file)

        # Parse JSON results if available
        json_results = self.results_dir / 'formal_results.json'
        if json_results.exists():
            with open(json_results) as f:
                results = json.load(f)
            for prop in results.get('failed_properties', []):
                cex = FormalCounterexample(
                    property_name=prop['name'],
                    trace_length=prop.get('trace_depth', 0),
                    is_security='pmp' in prop['name'] or 'priv' in prop['name'] or 'csr' in prop['name'],
                    severity=self.PROPERTY_SEVERITY.get(prop['name'], 'medium'),
                )
                self.counterexamples.append(cex)

        return self.counterexamples

    def translate_to_stimuli(self):
        """Convert counterexamples into directed test stimuli."""
        self.translated_stimuli = []

        for cex in self.counterexamples:
            stimulus = self._translate_single(cex)
            if stimulus:
                self.translated_stimuli.append(stimulus)

        # Sort by priority (security-critical first)
        self.translated_stimuli.sort(key=lambda s: s.priority, reverse=True)

        return self.translated_stimuli

    def get_rl_seeds(self):
        """Get high-priority stimuli as seed actions for RL agent."""
        seeds = []
        for stim in self.translated_stimuli:
            seed_action = self._knobs_to_action(stim.knobs)
            seeds.append({
                'action': seed_action,
                'priority': stim.priority,
                'source': stim.source_property,
            })
        return seeds

    def _translate_single(self, cex: FormalCounterexample) -> Optional[TranslatedStimulus]:
        """Translate one counterexample to a test stimulus."""
        scenario = self.PROPERTY_SCENARIO_MAP.get(cex.property_name, 'mixed')

        # Determine test knobs based on the property that failed
        knobs = {
            'test_scenario': scenario,
            'test_length': max(cex.trace_length * 2, 100),
        }

        # Security-specific knob tuning
        if 'pmp' in cex.property_name:
            knobs['pmp_config_mode'] = 'm_only_secure'
            knobs['privilege_bias'] = 0.9  # Mostly U-mode to trigger PMP
            knobs['illegal_insn_rate'] = 0.0

        elif 'priv' in cex.property_name:
            knobs['pmp_config_mode'] = 'mixed_permissions'
            knobs['privilege_bias'] = 0.5
            knobs['interrupt_rate'] = 0.3  # Interrupts cause priv changes

        elif 'csr' in cex.property_name:
            knobs['privilege_bias'] = 0.7
            knobs['illegal_insn_rate'] = 0.1

        elif 'interrupt' in cex.property_name:
            knobs['interrupt_rate'] = 0.8

        # Priority based on severity
        priority_map = {'critical': 1.0, 'high': 0.8, 'medium': 0.5, 'low': 0.2}
        priority = priority_map.get(cex.severity, 0.5)

        # Extract signal trace to generate specific instructions
        instructions = self._extract_instructions_from_trace(cex)

        return TranslatedStimulus(
            source_property=cex.property_name,
            knobs=knobs,
            priority=priority,
            instructions=instructions,
        )

    def _extract_instructions_from_trace(self, cex: FormalCounterexample) -> List[int]:
        """Extract instruction sequence from formal trace signals."""
        instructions = []

        # If we have signal data, extract the instruction stream
        if 'rvfi_insn' in cex.signals:
            instructions = cex.signals['rvfi_insn']
        elif 'imem_rdata' in cex.signals:
            instructions = cex.signals['imem_rdata']

        return instructions

    def _knobs_to_action(self, knobs):
        """Convert knob dict to RL action vector."""
        scenarios = ['random_alu', 'memory_stress', 'pmp_violation',
                    'privilege_switch', 'interrupt_storm', 'csr_access',
                    'bus_protocol', 'mixed']
        pmp_modes = ['all_open', 'm_only_secure', 'mixed_permissions', 'locked_regions']

        scenario_idx = scenarios.index(knobs.get('test_scenario', 'mixed'))
        pmp_idx = pmp_modes.index(knobs.get('pmp_config_mode', 'all_open'))

        return [
            float(scenario_idx),
            float(pmp_idx),
            knobs.get('privilege_bias', 0.5),
            0.0,  # memory pattern
            knobs.get('interrupt_rate', 0.1),
            knobs.get('illegal_insn_rate', 0.05),
            (knobs.get('test_length', 100) - 50) / 450.0,
        ]

    def _parse_vcd_trace(self, vcd_path):
        """Parse a VCD file for counterexample signals."""
        # Simplified VCD parser — extracts key signals
        try:
            property_name = vcd_path.stem  # Use filename as property name
            cex = FormalCounterexample(
                property_name=property_name,
                trace_length=0,
                is_security='pmp' in property_name or 'priv' in property_name,
                severity=self.PROPERTY_SEVERITY.get(property_name, 'medium'),
            )

            with open(vcd_path, 'r') as f:
                content = f.read()
                # Count timesteps
                cex.trace_length = content.count('#')

            return cex
        except Exception:
            return None

    def _parse_sby_log(self, log_path):
        """Parse SymbiYosys log for property results."""
        try:
            with open(log_path, 'r') as f:
                for line in f:
                    if 'FAIL' in line or 'Assert failed' in line:
                        # Extract property name
                        match = re.search(r'property\s+(\w+)', line)
                        if match:
                            prop_name = match.group(1)
                            cex = FormalCounterexample(
                                property_name=prop_name,
                                trace_length=30,
                                is_security='pmp' in prop_name or 'priv' in prop_name,
                                severity=self.PROPERTY_SEVERITY.get(prop_name, 'medium'),
                            )
                            self.counterexamples.append(cex)
        except Exception:
            pass


def generate_formal_feedback_report(formal_dir, output_path):
    """Generate a JSON report of formal verification feedback."""
    engine = FormalFeedbackEngine(formal_dir)
    cexs = engine.parse_results()
    stimuli = engine.translate_to_stimuli()
    seeds = engine.get_rl_seeds()

    report = {
        'total_counterexamples': len(cexs),
        'security_counterexamples': sum(1 for c in cexs if c.is_security),
        'translated_stimuli': len(stimuli),
        'rl_seeds': seeds,
        'counterexamples': [
            {
                'property': c.property_name,
                'trace_length': c.trace_length,
                'is_security': c.is_security,
                'severity': c.severity,
            }
            for c in cexs
        ],
    }

    with open(output_path, 'w') as f:
        json.dump(report, f, indent=2)

    return report

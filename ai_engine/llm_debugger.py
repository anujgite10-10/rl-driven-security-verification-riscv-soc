"""
SecVeriRL — LLM Coverage Gap Analyzer
======================================
Uses Google Gemini to analyze coverage gaps after RL training.
When coverage is below 100%, this module:
  1. Identifies which coverage bins are NOT hit
  2. Reads the relevant RTL source code
  3. Sends a structured prompt to Gemini
  4. Returns actionable suggestions (RTL fixes or test improvements)

Setup:
  1. pip install google-genai
  2. Set your API key:
     export GEMINI_API_KEY="your-key-here"
     OR create a .env file in the project root with:
     GEMINI_API_KEY=your-key-here
"""

import os
import json
from pathlib import Path
from typing import Dict, List, Optional


# Coverage bin descriptions for human-readable prompts
INSN_TYPE_NAMES = {
    0x37: "LUI (Load Upper Immediate)",
    0x17: "AUIPC (Add Upper Immediate to PC)",
    0x6F: "JAL (Jump and Link)",
    0x67: "JALR (Jump and Link Register)",
    0x63: "BRANCH (BEQ/BNE/BLT/BGE/BLTU/BGEU)",
    0x03: "LOAD (LB/LH/LW/LBU/LHU)",
    0x23: "STORE (SB/SH/SW)",
    0x13: "IMM (ADDI/SLTI/ANDI/ORI/XORI/SLLI/SRLI/SRAI)",
    0x33: "REG (ADD/SUB/SLL/SLT/XOR/SRL/SRA/OR/AND)",
    0x0F: "FENCE",
    0x73: "SYSTEM (ECALL/EBREAK/CSR instructions)",
}

SECURITY_ALERT_NAMES = {
    0x01: "PMP Violation (access to protected memory region)",
    0x02: "Privilege Escalation (illegal U→M transition)",
    0x03: "Illegal CSR Access (U-mode writing M-mode CSR)",
    0x04: "Illegal Instruction (invalid opcode executed)",
    0x05: "Secure Region Access (access to secure peripheral space)",
    0x06: "Rapid Traps (excessive trap frequency — DoS detection)",
}

PMP_SCENARIO_NAMES = {
    'u_read_m_region':  "User-mode READ from Machine-mode protected region",
    'u_write_m_region': "User-mode WRITE to Machine-mode protected region",
    'u_exec_m_region':  "User-mode EXECUTE from Machine-mode protected region",
    'm_read_all':       "Machine-mode READ from all regions (baseline)",
    'm_write_all':      "Machine-mode WRITE to all regions (baseline)",
    'pmp_cfg_written':  "PMP configuration register was written",
    'pmp_locked':       "PMP region was locked (L-bit set in pmpcfg)",
}

# Map coverage bins to relevant RTL files
COVERAGE_TO_RTL = {
    'insn_types': [
        'rtl/core/rv32i_core.sv',
        'rtl/core/rv32i_decoder.sv',
        'rtl/core/rv32i_alu.sv',
    ],
    'security_alerts': [
        'rtl/security/sec_monitor.sv',
        'rtl/security/pmp_unit.sv',
        'rtl/top/secverirl_soc_top.sv',
    ],
    'pmp_scenarios': [
        'rtl/security/pmp_unit.sv',
        'rtl/core/rv32i_core.sv',
    ],
    'priv_modes': [
        'rtl/core/rv32i_core.sv',
        'rtl/security/sec_monitor.sv',
    ],
}


def _load_api_key(project_root: str) -> Optional[str]:
    """Load Gemini API key from environment or .env file."""
    # Check environment variable first
    key = os.environ.get('GEMINI_API_KEY')
    if key:
        return key

    # Check .env file in project root
    env_file = Path(project_root) / '.env'
    if env_file.exists():
        with open(env_file) as f:
            for line in f:
                line = line.strip()
                if line.startswith('GEMINI_API_KEY='):
                    return line.split('=', 1)[1].strip().strip('"').strip("'")

    return None


def _load_rtl_files(project_root: str, file_list: List[str]) -> Dict[str, str]:
    """Load RTL source files and return as {filename: content} dict."""
    sources = {}
    for rel_path in file_list:
        full_path = Path(project_root) / rel_path
        if full_path.exists():
            try:
                content = full_path.read_text(encoding='utf-8', errors='replace')
                # Truncate very long files to stay within token limits
                if len(content) > 8000:
                    content = content[:8000] + "\n\n... [TRUNCATED — file too long] ..."
                sources[rel_path] = content
            except Exception as e:
                sources[rel_path] = f"[ERROR reading file: {e}]"
    return sources


def _build_gap_description(coverage_report: Dict) -> str:
    """Build a human-readable description of what coverage bins are missing."""
    lines = []
    details = coverage_report.get('details', {})

    # Instruction types
    insn_types = details.get('insn_types', {})
    missing_insn = [k for k, v in insn_types.items() if not v]
    if missing_insn:
        lines.append("## Missing Instruction Types")
        for opcode_str in missing_insn:
            opcode = int(opcode_str)
            name = INSN_TYPE_NAMES.get(opcode, f"Unknown opcode 0x{opcode:02X}")
            lines.append(f"  - opcode 0x{opcode:02X}: {name}")
        lines.append("")

    # Security alerts
    sec_alerts = details.get('security_alerts', {})
    missing_sec = [k for k, v in sec_alerts.items() if not v]
    if missing_sec:
        lines.append("## Missing Security Alerts")
        for code_str in missing_sec:
            code = int(code_str)
            name = SECURITY_ALERT_NAMES.get(code, f"Unknown alert 0x{code:02X}")
            lines.append(f"  - alert 0x{code:02X}: {name}")
        lines.append("")

    # PMP scenarios
    pmp = details.get('pmp_scenarios', {})
    missing_pmp = [k for k, v in pmp.items() if not v]
    if missing_pmp:
        lines.append("## Missing PMP Scenarios")
        for scenario in missing_pmp:
            name = PMP_SCENARIO_NAMES.get(scenario, scenario)
            lines.append(f"  - {scenario}: {name}")
        lines.append("")

    # Privilege modes
    priv = details.get('priv_modes', {})
    missing_priv = [k for k, v in priv.items() if not v]
    if missing_priv:
        priv_names = {0: "User (U)", 1: "Supervisor (S)", 3: "Machine (M)"}
        lines.append("## Missing Privilege Modes")
        for mode_str in missing_priv:
            mode = int(mode_str)
            lines.append(f"  - Mode {mode}: {priv_names.get(mode, 'Unknown')}")
        lines.append("")

    return "\n".join(lines)


def _determine_relevant_rtl(coverage_report: Dict) -> List[str]:
    """Determine which RTL files to include based on what's missing."""
    details = coverage_report.get('details', {})
    rtl_files = set()

    insn_types = details.get('insn_types', {})
    if any(not v for v in insn_types.values()):
        rtl_files.update(COVERAGE_TO_RTL['insn_types'])

    sec_alerts = details.get('security_alerts', {})
    if any(not v for v in sec_alerts.values()):
        rtl_files.update(COVERAGE_TO_RTL['security_alerts'])

    pmp = details.get('pmp_scenarios', {})
    if any(not v for v in pmp.values()):
        rtl_files.update(COVERAGE_TO_RTL['pmp_scenarios'])

    priv = details.get('priv_modes', {})
    if any(not v for v in priv.values()):
        rtl_files.update(COVERAGE_TO_RTL['priv_modes'])

    return sorted(rtl_files)


def _build_prompt(coverage_report: Dict, gap_description: str,
                  rtl_sources: Dict[str, str], testbench_snippet: str) -> str:
    """Build the structured prompt for Gemini."""
    func_cov = coverage_report.get('functional_coverage', 0)
    sec_cov = coverage_report.get('security_coverage', 0)
    pmp_cov = coverage_report.get('pmp_coverage', 0)

    rtl_section = ""
    for filename, content in rtl_sources.items():
        rtl_section += f"\n### {filename}\n```systemverilog\n{content}\n```\n"

    prompt = f"""You are an expert RISC-V hardware verification engineer. 
You are analyzing a RISC-V SoC design called SecVeriRL that has security features 
(PMP — Physical Memory Protection, privilege modes, security monitor).

An RL-based verification agent has been running tests against this design but 
has NOT achieved 100% coverage. Your job is to analyze the coverage gaps and 
provide actionable recommendations.

## Current Coverage Results
- Functional Coverage: {func_cov:.1%}
- Security Coverage: {sec_cov:.1%}
- PMP Coverage: {pmp_cov:.1%}

## Coverage Gaps (What is NOT covered)
{gap_description}

## RTL Source Code (Relevant Modules)
{rtl_section}

## Test Program Generator (cocotb testbench)
```python
{testbench_snippet}
```

## Your Task
For EACH missing coverage bin listed above, provide:

1. **Root Cause**: Why is this bin not being hit? Is it:
   - A bug in the RTL (the hardware logic is wrong)?
   - A limitation in the test generator (it doesn't generate the right stimulus)?
   - A signal connectivity issue (the coverage monitor can't see the event)?

2. **Specific Fix**: Provide the EXACT code change needed. For RTL bugs, show the 
   SystemVerilog fix. For test generator issues, show the Python fix.

3. **Verification Command**: After the fix, what test should the user run to 
   confirm the bin is now covered?

Format your response as a structured report with clear sections for each gap.
Be specific — reference exact file names, line numbers, signal names, and opcodes.
"""
    return prompt


def analyze_coverage_gaps(
    coverage_report: Dict,
    project_root: str,
    output_dir: Optional[str] = None,
) -> Optional[Dict]:
    """
    Main entry point: Analyze coverage gaps using Gemini.
    
    Args:
        coverage_report: The coverage report dict from CoverageCollector.get_report()
        project_root: Path to the SecVeriRL project root
        output_dir: Optional directory to save the analysis report
    
    Returns:
        Dict with 'analysis' (Gemini's response) and 'gaps' (structured gap info),
        or None if Gemini is not available.
    """
    # Check if coverage is already 100%
    func_cov = coverage_report.get('functional_coverage', 0)
    sec_cov = coverage_report.get('security_coverage', 0)
    pmp_cov = coverage_report.get('pmp_coverage', 0)

    if func_cov >= 1.0 and sec_cov >= 1.0 and pmp_cov >= 1.0:
        print("\n  ✓ 100% coverage achieved! No gaps to analyze.")
        return {'analysis': 'Full coverage achieved.', 'gaps': []}

    # Load API key
    api_key = _load_api_key(project_root)
    if not api_key:
        print("\n  [WARN] GEMINI_API_KEY not found.")
        print("  To enable LLM-powered gap analysis:")
        print("    1. Get a key from https://aistudio.google.com/apikey")
        print("    2. Set it: export GEMINI_API_KEY='your-key-here'")
        print("       OR add to .env file: GEMINI_API_KEY=your-key-here")
        return None

    # Import Gemini SDK
    try:
        from google import genai
    except ImportError:
        print("\n  [WARN] google-genai not installed.")
        print("  Install with: pip install google-genai")
        return None

    print("\n" + "=" * 60)
    print("  SecVeriRL — LLM Coverage Gap Analysis (Gemini)")
    print("=" * 60)

    # Build gap description
    gap_description = _build_gap_description(coverage_report)
    print(f"\n  Coverage gaps identified:")
    for line in gap_description.split('\n'):
        if line.strip():
            print(f"    {line}")

    # Load relevant RTL source code
    relevant_files = _determine_relevant_rtl(coverage_report)
    print(f"\n  Loading {len(relevant_files)} RTL files for analysis...")
    rtl_sources = _load_rtl_files(project_root, relevant_files)

    # Load test generator snippet
    tb_path = Path(project_root) / 'verification' / 'cocotb_env' / 'tb_top.py'
    tb_snippet = ""
    if tb_path.exists():
        content = tb_path.read_text(encoding='utf-8', errors='replace')
        # Extract just the generate_test_program function
        start = content.find('def generate_test_program')
        if start != -1:
            # Get ~200 lines from that point
            lines = content[start:].split('\n')[:200]
            tb_snippet = '\n'.join(lines)

    # Build and send prompt
    prompt = _build_prompt(coverage_report, gap_description, rtl_sources, tb_snippet)

    print(f"  Sending analysis request to Gemini...")
    print(f"  (Prompt size: {len(prompt)} chars, ~{len(prompt)//4} tokens)")

    import time as _time
    max_retries = 3
    analysis_text = None
    for attempt in range(max_retries):
        try:
            client = genai.Client(api_key=api_key)
            response = client.models.generate_content(
                model="gemini-3.6-flash",
                contents=prompt,
            )
            analysis_text = response.text
            break
        except Exception as e:
            err_str = str(e)
            if '503' in err_str and attempt < max_retries - 1:
                wait = 10 * (2 ** attempt)
                print(f"  [RETRY] Gemini overloaded, waiting {wait}s... (attempt {attempt+1}/{max_retries})")
                _time.sleep(wait)
            else:
                print(f"\n  [ERROR] Gemini API call failed: {e}")
                return None

    if analysis_text is None:
        print(f"\n  [ERROR] All {max_retries} Gemini attempts failed.")
        return None

    # Print the analysis
    print("\n" + "=" * 60)
    print("  GEMINI ANALYSIS REPORT")
    print("=" * 60)
    print(analysis_text)

    # Save to file
    result = {
        'coverage_report': coverage_report,
        'gap_description': gap_description,
        'analysis': analysis_text,
        'rtl_files_analyzed': list(rtl_sources.keys()),
    }

    if output_dir:
        out_path = Path(output_dir)
        out_path.mkdir(parents=True, exist_ok=True)
        report_file = out_path / 'llm_gap_analysis.json'
        with open(report_file, 'w') as f:
            json.dump(result, f, indent=2, default=str)
        print(f"\n  ✓ Analysis saved to: {report_file}")

        # Also save readable markdown report
        md_file = out_path / 'gap_analysis_report.md'
        with open(md_file, 'w') as f:
            f.write(f"# SecVeriRL — Coverage Gap Analysis Report\n\n")
            f.write(f"## Coverage Summary\n")
            f.write(f"- Functional: {func_cov:.1%}\n")
            f.write(f"- Security: {sec_cov:.1%}\n")
            f.write(f"- PMP: {pmp_cov:.1%}\n\n")
            f.write(f"## Identified Gaps\n{gap_description}\n\n")
            f.write(f"## Gemini Analysis\n{analysis_text}\n")
        print(f"  ✓ Markdown report saved to: {md_file}")

    return result


# =========================================================================
# Standalone CLI
# =========================================================================

if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(
        description='SecVeriRL LLM Coverage Gap Analyzer',
    )
    parser.add_argument('--coverage', type=str, required=True,
                        help='Path to coverage_result.json')
    parser.add_argument('--output', type=str, default='results/llm_analysis',
                        help='Output directory for reports')
    args = parser.parse_args()

    project_root = str(Path(__file__).resolve().parent.parent)

    with open(args.coverage) as f:
        cov = json.load(f)

    result = analyze_coverage_gaps(cov, project_root, args.output)
    if result:
        print("\n  ✓ Analysis complete!")
    else:
        print("\n  ✗ Analysis could not be completed.")

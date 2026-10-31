#!/bin/bash
# ============================================================================
# SecVeriRL — Cadence Incisive Run Script
# ============================================================================
# Usage:
#   chmod +x run_incisive.sh
#   ./run_incisive.sh              # Compile + Simulate + Waves
#   ./run_incisive.sh compile      # Compile only
#   ./run_incisive.sh sim          # Simulate only (after compile)
#   ./run_incisive.sh clean        # Clean all outputs
# ============================================================================

# Project paths (adjust if your directory structure is different)
PROJ_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CADENCE_DIR="${PROJ_ROOT}/verification/cadence"

# Output directories
WORK_DIR="${CADENCE_DIR}/work"
LOG_DIR="${CADENCE_DIR}/logs"
WAVE_DIR="${CADENCE_DIR}/waves.shm"

echo "============================================================"
echo "  SecVeriRL — Cadence Incisive 15.2 Verification"
echo "============================================================"
echo "  Project root:  ${PROJ_ROOT}"
echo "  Cadence dir:   ${CADENCE_DIR}"
echo "============================================================"

# Create directories
mkdir -p "${WORK_DIR}" "${LOG_DIR}"

# ---- Clean ----
do_clean() {
    echo "[CLEAN] Removing build artifacts..."
    rm -rf "${WORK_DIR}" "${LOG_DIR}" "${WAVE_DIR}"
    rm -rf "${CADENCE_DIR}/INCA_libs" "${CADENCE_DIR}/cds.lib" "${CADENCE_DIR}/hdl.var"
    rm -rf "${CADENCE_DIR}/ncsim.log" "${CADENCE_DIR}/ncvlog.log" "${CADENCE_DIR}/ncelab.log"
    rm -rf "${CADENCE_DIR}/irun.log" "${CADENCE_DIR}/waves.shm"
    echo "[CLEAN] Done."
}

# ---- Single-command flow with irun ----
do_irun() {
    echo ""
    echo "[IRUN] Running single-command compile + elaborate + simulate..."
    echo ""

    cd "${CADENCE_DIR}"

    irun \
        -f filelist.f \
        -sv \
        -access +rwc \
        -timescale 1ns/1ps \
        -top tb_secverirl_top \
        -input "database -open waves -shm; probe -create tb_secverirl_top.u_dut -all -depth all -shm; run; exit" \
        -logfile "${LOG_DIR}/irun.log" \
        -errormax 10 \
        -nowarn DSEM2009 \
        -v93 \
        2>&1 | tee "${LOG_DIR}/irun_console.log"

    echo ""
    echo "[IRUN] Simulation complete. Check:"
    echo "  Log:   ${LOG_DIR}/irun.log"
    echo "  Waves: ${CADENCE_DIR}/waves.shm  (open with SimVision)"
}

# ---- 3-Step Flow (alternative) ----
do_compile() {
    echo ""
    echo "[COMPILE] ncvlog — Compiling SystemVerilog sources..."
    cd "${CADENCE_DIR}"

    ncvlog -sv \
        -f filelist.f \
        -logfile "${LOG_DIR}/ncvlog.log" \
        -nowarn DSEM2009 \
        -work "${WORK_DIR}" \
        2>&1 | tee "${LOG_DIR}/ncvlog_console.log"

    echo "[COMPILE] Done. Log: ${LOG_DIR}/ncvlog.log"
}

do_elaborate() {
    echo ""
    echo "[ELABORATE] ncelab — Elaborating design..."
    cd "${CADENCE_DIR}"

    ncelab \
        -access +rwc \
        -timescale 1ns/1ps \
        -logfile "${LOG_DIR}/ncelab.log" \
        -work "${WORK_DIR}" \
        work.tb_secverirl_top \
        2>&1 | tee "${LOG_DIR}/ncelab_console.log"

    echo "[ELABORATE] Done. Log: ${LOG_DIR}/ncelab.log"
}

do_simulate() {
    echo ""
    echo "[SIMULATE] ncsim — Running simulation..."
    cd "${CADENCE_DIR}"

    ncsim \
        -logfile "${LOG_DIR}/ncsim.log" \
        -input "database -open waves -shm; probe -create tb_secverirl_top.u_dut -all -depth all -shm; run; exit" \
        work.tb_secverirl_top \
        2>&1 | tee "${LOG_DIR}/ncsim_console.log"

    echo "[SIMULATE] Done."
    echo "  Log:   ${LOG_DIR}/ncsim.log"
    echo "  Waves: Open with: simvision waves.shm"
}

# ---- Dispatch ----
case "${1:-irun}" in
    clean)
        do_clean
        ;;
    compile)
        do_compile
        ;;
    elaborate)
        do_compile
        do_elaborate
        ;;
    sim)
        do_simulate
        ;;
    3step)
        do_compile
        do_elaborate
        do_simulate
        ;;
    irun|*)
        do_irun
        ;;
esac

echo ""
echo "============================================================"
echo "  Done!"
echo "============================================================"


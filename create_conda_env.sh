#!/bin/bash
# =============================================================================
# create_conda_env.sh
# Builds the Phase 1 conda environment — bioinformatics tools ONLY.
# No R packages — R analysis (DESeq2, tximeta, etc.) is Phase 2
# and runs separately on a machine where R packages can be installed.
#
# Tools installed:
#   FastQC, MultiQC, fastp, STAR, Salmon, samtools, pigz, RSeQC, Picard
#
# Usage:
#   bash create_conda_env.sh           # fresh install
#   bash create_conda_env.sh --force   # rebuild from scratch
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"

LOG="${LOG_DIR}/conda_install_$(date +%Y%m%d_%H%M%S).log"
mkdir -p "$(dirname "${LOG}")"
echo "============================================================"
echo "Phase 1 conda env — bioinformatics tools only (no R)"
echo "Prefix : ${CONDA_ENV}"
echo "Log    : ${LOG}"
echo "Started: $(date)"
echo "============================================================"
echo ""

# ── Initialise conda ──────────────────────────────────────────────────────────
CONDA_INIT="${CONDA_BASE}/etc/profile.d/conda.sh"
if [[ ! -f "${CONDA_INIT}" ]]; then
    echo "ERROR: ${CONDA_INIT} not found."
    echo "       Run: conda info --base  to find your CONDA_BASE"
    echo "       Then edit CONDA_BASE in project_config.sh"
    exit 1
fi
source "${CONDA_INIT}"
echo "conda : $(conda --version)"
echo ""

# ── Guard ─────────────────────────────────────────────────────────────────────
if [[ -d "${CONDA_ENV}" ]] && [[ "${1:-}" != "--force" ]]; then
    echo "WARNING: ${CONDA_ENV} already exists."
    echo "         Skipping install — jumping to verification."
    echo "         To rebuild: bash create_conda_env.sh --force"
    SKIP_INSTALL=true
else
    SKIP_INSTALL=false
    if [[ "${1:-}" == "--force" ]] && [[ -d "${CONDA_ENV}" ]]; then
        echo "Removing existing env (--force)..."
        conda env remove --prefix "${CONDA_ENV}" -y 2>/dev/null || true
    fi
fi

if [[ "${SKIP_INSTALL}" == "false" ]]; then

    # Write per-env .condarc — channel config scoped to this prefix only
    mkdir -p "${CONDA_ENV}"
    cat > "${CONDA_ENV}/.condarc" << 'CONDARC'
channels:
  - conda-forge
  - bioconda
  - defaults
channel_priority: strict
CONDARC
    echo "Per-env .condarc written (scoped to this prefix only)"
    echo ""

    echo "============================================================"
    echo "[1/1] conda create --prefix + all Phase 1 tools"
    echo "      FastQC | MultiQC | fastp | STAR | Salmon"
    echo "      samtools | pigz | RSeQC | Picard | subread"
    echo "============================================================"

    conda create -y \
        --prefix  "${CONDA_ENV}" \
        --channel conda-forge \
        --channel bioconda \
        python=3.10 \
        fastqc=0.12.1 \
        multiqc=1.21 \
        fastp=0.23.4 \
        star=2.7.11a \
        salmon=1.10.3 \
        samtools=1.19 \
        rseqc=5.0.1 \
        picard=3.1.1 \
        pigz \
        subread \
        2>&1 | tee -a "${LOG}"

fi  # end SKIP_INSTALL

# ── Verification ─────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "[VERIFY] Testing: ${CONDA_ENV}"
echo "============================================================"

conda activate "${CONDA_ENV}"

# Confirm correct prefix is active
ACTIVE=$(conda info --json 2>/dev/null \
         | python3 -c "import sys,json
d=json.load(sys.stdin)
print(d.get('active_prefix','unknown'))" 2>/dev/null || echo "unknown")

echo "Expected : ${CONDA_ENV}"
echo "Active   : ${ACTIVE}"
if [[ "${ACTIVE}" != "${CONDA_ENV}" ]]; then
    echo "ERROR: Wrong env is active. Check: conda env list"
    exit 1
fi
echo ""

PASS=true
chk() {
    local TOOL="$1" CMD="$2"
    if eval "${CMD}" &>/dev/null; then
        printf "  [OK]   %-14s %s\n" "${TOOL}" "$(eval "${CMD}" 2>&1 | head -1)"
    else
        printf "  [FAIL] %-14s\n" "${TOOL}"
        PASS=false
    fi
}

chk "python"   "python --version"
chk "fastqc"   "fastqc --version"
chk "multiqc"  "multiqc --version"
chk "fastp"    "fastp --version 2>&1 | head -1"
chk "STAR"     "STAR --version 2>&1 | head -1"
chk "salmon"   "salmon --version 2>&1 | head -1"
chk "samtools" "samtools --version | head -1"
chk "picard"   "picard --version 2>&1 | head -1"
chk "pigz"     "pigz --version 2>&1 | head -1"
chk "python3 RSeQC" "python3 -c 'import RseQC' 2>/dev/null || infer_experiment.py --version 2>&1 | head -1"

conda deactivate

echo ""
echo "============================================================"
if [[ "${PASS}" == "true" ]]; then
    echo "ENVIRONMENT READY"
    echo ""
    echo "Prefix   : ${CONDA_ENV}"
    echo "Activate : source activate ${CONDA_ENV}"
    echo ""
    echo "Installs: FastQC, MultiQC, fastp, STAR, Salmon,"
    echo "          samtools, pigz, RSeQC, Picard"
    echo ""
    echo "NOTE: R packages (DESeq2, tximeta, etc.) are Phase 2."
    echo "      Install them separately on a machine that supports them."
    echo "      Phase 1 outputs (quant.sf, BAMs) are the input to Phase 2."
else
    echo "SOME TOOLS FAILED — see ${LOG}"
    echo ""
    echo "Try installing failing tools individually:"
    echo "  conda install -y --prefix ${CONDA_ENV} <toolname>"
fi
echo "Log : ${LOG}"
echo "============================================================"

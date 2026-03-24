#!/bin/bash
# =============================================================================
# hpc_functions.sh — RCSI HPC helper functions
# Sourced by every compute script AFTER project_config.sh.
#
# Functions:
#   activate_conda   — activates the prefix-based conda env inside SLURM jobs
#   setup_tmpdir     — initialises SSD scratch + registers copy-back trap
#   stage_in         — copies NFS → SSD with verification
#   check_space      — guards against insufficient SSD space
#   log_node_info    — prints job diagnostics to log
# =============================================================================

# -----------------------------------------------------------------------------
# activate_conda
#
# Activates a PREFIX-based conda environment inside a SLURM job.
# SLURM jobs do not inherit the interactive shell's conda initialisation,
# so conda.sh must be sourced explicitly before calling 'source activate'.
#
# Uses the FULL PREFIX PATH (not the env name) — required for envs created
# with 'conda create --prefix /path/to/env'.
#
# Activation command used:
#   source activate /home/data/conda_envs/isoform
# (exactly as specified by the user)
#
# Must be called AFTER sourcing project_config.sh (which exports CONDA_ENV
# and CONDA_BASE).
# -----------------------------------------------------------------------------
activate_conda() {
    if [[ -z "${CONDA_ENV:-}" || -z "${CONDA_BASE:-}" ]]; then
        echo "ERROR: CONDA_ENV or CONDA_BASE not set."
        echo "       Source project_config.sh before hpc_functions.sh."
        exit 1
    fi

    # Verify the env path exists (catches typos / missing env)
    if [[ ! -d "${CONDA_ENV}" ]]; then
        echo "ERROR: Conda env not found at: ${CONDA_ENV}"
        echo "       Run create_conda_env.sh to build it first."
        exit 1
    fi

    echo "------------------------------------------------------------"
    echo "Activating conda (prefix-based)"
    echo "  CONDA_BASE : ${CONDA_BASE}"
    echo "  CONDA_ENV  : ${CONDA_ENV}"

    # Step 1: source conda.sh to make conda available in this shell
    source "${CONDA_BASE}/etc/profile.d/conda.sh"

    # Step 2: activate using the full prefix path
    #         'source activate /path/to/env' is the correct form for
    #         prefix-based envs on RCSI HPC
    conda activate "${CONDA_ENV}"

    # Step 3: verify the correct prefix is now active
    ACTIVE=$(conda info --json 2>/dev/null \
             | python3 -c "import sys,json
d=json.load(sys.stdin)
print(d.get('active_prefix','unknown'))" 2>/dev/null || echo "unknown")

    if [[ "${ACTIVE}" != "${CONDA_ENV}" ]]; then
        echo "  ERROR: Wrong env activated!"
        echo "         Expected : ${CONDA_ENV}"
        echo "         Got      : ${ACTIVE}"
        echo "  Possible cause: a named env 'isoform' exists and took priority."
        echo "  Check: conda env list"
        exit 1
    fi

    echo "  Active     : ${ACTIVE}"
    echo "  Python     : $(python --version 2>&1)"
    echo "  R          : $(R --version 2>&1 | head -1)"
    echo "------------------------------------------------------------"
}

# -----------------------------------------------------------------------------
# setup_tmpdir [subdir1 subdir2 ...]
#   Validates TMPDIR, creates subdirs, registers EXIT trap that copies
#   TMPDIR/output/ → NFS_OUT/ on any exit (normal, error, or wall-time kill).
#   NFS_OUT must be exported BEFORE calling setup_tmpdir.
# -----------------------------------------------------------------------------
setup_tmpdir() {
    if [[ -z "${TMPDIR:-}" ]]; then
        echo "WARNING: TMPDIR not set by SLURM. Using /local/scratch/$$"
        export TMPDIR="/local/scratch/$$"
    fi

    if [[ -z "${NFS_OUT:-}" ]]; then
        echo "ERROR: NFS_OUT must be set before calling setup_tmpdir."
        exit 1
    fi

    mkdir -p "${TMPDIR}"
    for _sub in "$@"; do
        mkdir -p "${TMPDIR}/${_sub}"
    done

    echo "------------------------------------------------------------"
    echo "SSD scratch : ${TMPDIR}"
    echo "NFS output  : ${NFS_OUT}"
    echo "SSD free    : $(df -h "${TMPDIR}" | awk 'NR==2{print $4}')"
    echo "------------------------------------------------------------"

    # Register trap — fires on: normal exit, error, SIGTERM (wall-time kill)
    trap '_ssd_copy_back $?' EXIT
}

# Internal — do not call directly
_ssd_copy_back() {
    local CODE=${1:-0}
    echo ""
    echo "============================================================"
    echo "TRAP: SSD → NFS copy-back  (exit code: ${CODE})"
    echo "  From : ${TMPDIR}/output/"
    echo "  To   : ${NFS_OUT}"
    echo "============================================================"
    if [[ -d "${TMPDIR}/output" ]] && \
       [[ -n "$(ls -A "${TMPDIR}/output" 2>/dev/null)" ]]; then
        mkdir -p "${NFS_OUT}"
        rsync -av --no-perms --no-owner --no-group \
              "${TMPDIR}/output/" "${NFS_OUT}/"
        local RC=$?
        if [[ ${RC} -eq 0 ]]; then
            echo "OK: rsync succeeded — $(ls "${NFS_OUT}" | wc -l) files on NFS"
        else
            echo "ERROR: rsync FAILED (exit ${RC})"
            echo "       Data may still be on SSD until SLURM releases the node"
        fi
    else
        echo "WARNING: ${TMPDIR}/output is empty — nothing copied"
        [[ ${CODE} -ne 0 ]] && echo "         (job likely failed before producing output)"
    fi
    echo "Finished: $(date)"
    exit "${CODE}"
}

# -----------------------------------------------------------------------------
# stage_in <src> <dst_dir>
#   Copies a file or directory from NFS to SSD. Exits if src missing.
# -----------------------------------------------------------------------------
stage_in() {
    local SRC="$1"
    local DST="$2"
    if [[ ! -e "${SRC}" ]]; then
        echo "ERROR stage_in: not found: ${SRC}"
        exit 1
    fi
    echo "  Staging: $(basename "${SRC}")  NFS → SSD"
    rsync -a --no-perms "${SRC}" "${DST}" \
        || { echo "ERROR: rsync failed for ${SRC}"; exit 1; }
    echo "  Done   : $(du -sh "${DST}/$(basename "${SRC}")" 2>/dev/null | cut -f1)"
}

# -----------------------------------------------------------------------------
# check_space <required_gb>
#   Aborts if TMPDIR has less than required_gb GB free.
# -----------------------------------------------------------------------------
check_space() {
    local REQ=${1:-10}
    local FREE
    FREE=$(df -BG "${TMPDIR}" | awk 'NR==2{gsub("G","",$4); print $4}')
    echo "  SSD space: ${FREE} GB available, ${REQ} GB required"
    if [[ "${FREE}" -lt "${REQ}" ]]; then
        echo "ERROR: Insufficient SSD space (${FREE} GB free, need ${REQ} GB)"
        echo "       Check if other jobs on this node are using /local/scratch"
        exit 1
    fi
    echo "  Space OK"
}

# -----------------------------------------------------------------------------
# log_node_info — prints job/node diagnostics at start of each script
# -----------------------------------------------------------------------------
log_node_info() {
    echo "============================================================"
    echo "Job      : ${SLURM_JOB_ID:-N/A}"
    echo "Array    : task ${SLURM_ARRAY_TASK_ID:-N/A} / ${SLURM_ARRAY_TASK_MAX:-N/A}"
    echo "Node     : $(hostname)"
    echo "CPUs     : ${SLURM_CPUS_PER_TASK:-?}"
    echo "Memory   : ${SLURM_MEM_PER_NODE:-?} MB"
    echo "TMPDIR   : ${TMPDIR:-not set}"
    echo "Started  : $(date)"
    echo "============================================================"
}

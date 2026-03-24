#!/bin/bash
# =============================================================================
# 00_preflight_check.sh
# Run MANUALLY on login node BEFORE submitting any SLURM jobs.
# Validates all 18 FASTQ pairs and creates standardised symlinks.
# Usage: bash 00_preflight_check.sh
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"

PASS=true; WARNS=0; ERRS=0
ok()   { echo "  [OK]   $*"; }
warn() { echo "  [WARN] $*"; WARNS=$((WARNS+1)); }
err()  { echo "  [ERR]  $*"; ERRS=$((ERRS+1)); PASS=false; }
sec()  { echo ""; echo "--- $* ---"; }

echo "============================================================"
echo "Pre-flight check | Hormone x IPF RNA-seq"
echo "PROJ_DIR : ${PROJ_DIR}"
echo "FASTQ_DIR: ${FASTQ_DIR}"
echo "Suffixes : R1=${R1_SUFFIX}  R2=${R2_SUFFIX}"
echo "Samples  : $(wc -l < ${SAMPLES})"
echo "Date     : $(date)"
echo "============================================================"

sec "1. Essential paths"
[[ -d "${PROJ_DIR}" ]]  && ok "PROJ_DIR"   || err "PROJ_DIR not found: ${PROJ_DIR}"
[[ -d "${FASTQ_DIR}" ]] && ok "FASTQ_DIR"  || err "FASTQ_DIR not found: ${FASTQ_DIR}"
[[ -f "${SAMPLES}" ]]   && ok "samples.txt ($(wc -l < ${SAMPLES}) samples)" \
                         || err "samples.txt not found: ${SAMPLES}"
[[ -f "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh" ]] && ok "hpc_functions.sh" \
    || err "hpc_functions.sh missing from /home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts"
[[ -d "${CONDA_ENV}" ]] && ok "conda env: ${CONDA_ENV}" \
    || warn "conda env not found yet — run create_conda_env.sh first"

sec "2. FASTQ discovery  (${FASTQ_DIR})"
FOUND=0; declare -a PAIRS=()

while read SAMPLE; do
    R1="${FASTQ_DIR}/${SAMPLE}${R1_SUFFIX}"
    R2="${FASTQ_DIR}/${SAMPLE}${R2_SUFFIX}"

    # Fallback glob for non-standard naming
    [[ ! -f "${R1}" ]] && R1=$(ls ${FASTQ_DIR}/${SAMPLE}*_1*.f*q.gz \
                                  ${FASTQ_DIR}/${SAMPLE}*R1*.f*q.gz \
                                  2>/dev/null | head -1 || echo "")
    [[ ! -f "${R2}" ]] && R2=$(ls ${FASTQ_DIR}/${SAMPLE}*_2*.f*q.gz \
                                  ${FASTQ_DIR}/${SAMPLE}*R2*.f*q.gz \
                                  2>/dev/null | head -1 || echo "")

    if [[ -f "${R1}" && -f "${R2}" ]]; then
        SZ1=$(du -sh "${R1}" | cut -f1)
        SZ2=$(du -sh "${R2}" | cut -f1)
        ok "${SAMPLE}  R1: $(basename ${R1}) [${SZ1}]  R2: $(basename ${R2}) [${SZ2}]"
        PAIRS+=("${SAMPLE}|${R1}|${R2}")
        FOUND=$((FOUND+1))
    else
        [[ ! -f "${R1}" ]] && err "${SAMPLE}: R1 not found"
        [[ ! -f "${R2}" ]] && err "${SAMPLE}: R2 not found"
        echo "  Files in dir matching ${SAMPLE}*:"
        ls ${FASTQ_DIR}/${SAMPLE}* 2>/dev/null | sed 's/^/    /' || echo "    (none)"
    fi
done < "${SAMPLES}"

echo ""
echo "  Found: ${FOUND}/$(wc -l < ${SAMPLES}) pairs"

sec "3. Standardised symlinks  (${FASTQ_LINKS})"
LINKED=0
for PAIR in "${PAIRS[@]}"; do
    SAMPLE=$(echo "${PAIR}" | cut -d'|' -f1)
    R1SRC=$(echo  "${PAIR}" | cut -d'|' -f2)
    R2SRC=$(echo  "${PAIR}" | cut -d'|' -f3)

    L1="${FASTQ_LINKS}/${SAMPLE}${R1_SUFFIX}"
    L2="${FASTQ_LINKS}/${SAMPLE}${R2_SUFFIX}"

    ln -sf "${R1SRC}" "${L1}"
    ln -sf "${R2SRC}" "${L2}"
    ok "Linked: ${SAMPLE}${R1_SUFFIX} → $(basename ${R1SRC})"
    LINKED=$((LINKED+1))
done

sec "4. Storage"
echo "  Raw FASTQ total : $(du -sh ${FASTQ_DIR}/ 2>/dev/null | cut -f1)"
echo "  NFS project     :"; df -h "${PROJ_DIR}" | awk 'NR==2{printf "    Used %s / %s (%s)\n",$3,$2,$5}'
echo "  SSD per node    : 900 GB (auto-managed by SLURM)"

echo ""
echo "============================================================"
echo "  Samples found  : ${FOUND}/$(wc -l < ${SAMPLES})"
echo "  Symlinks       : ${LINKED}"
echo "  Warnings       : ${WARNS}"
echo "  Errors         : ${ERRS}"
echo ""
if [[ "${PASS}" == "true" && ${FOUND} -eq $(wc -l < ${SAMPLES}) ]]; then
    echo "  STATUS: ALL CHECKS PASSED"
    echo ""
    echo "  FASTQs accessible at:"
    echo "    ${FASTQ_LINKS}/\${SAMPLE}${R1_SUFFIX}"
    echo ""
    echo "  NEXT: bash submit_all_phase1.sh"
else
    echo "  STATUS: FAILED — fix errors above before submitting"
    echo ""
    echo "  Common fixes:"
    echo "    Wrong suffix? Check: ls ${FASTQ_DIR}/ | head -5"
    echo "    Then edit R1_SUFFIX / R2_SUFFIX in project_config.sh"
fi
echo "============================================================"

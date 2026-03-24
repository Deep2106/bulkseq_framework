#!/bin/bash
# =============================================================================
# submit_stringtie2_pipeline.sh
# Submits the complete novel transcript discovery pipeline.
# Run AFTER Phase 1 (STAR BAMs must exist).
#
# Dependency chain:
#   S9a StringTie2 assembly (18 samples, array)
#   S9b StringTie2 merge + gffcompare        → after S9a
#   S9c Build augmented Salmon index          → after S9b
#   S9d Re-quantify all 18 samples (array)    → after S9c
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"

SCRIPTS="/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts"
cd "${SCRIPTS}"

# Verify STAR BAMs exist before submitting
echo "Checking STAR BAMs..."
MISSING=0
while read SAMPLE; do
    BAM="${RES_STAR}/${SAMPLE}_pass2/${SAMPLE}.bam"
    [[ ! -f "${BAM}" ]] && { echo "  MISSING: ${BAM}"; MISSING=$((MISSING+1)); }
done < "${SAMPLES}"

if [[ ${MISSING} -gt 0 ]]; then
    echo "ERROR: ${MISSING} BAM files missing. Complete Phase 1 first."
    exit 1
fi
echo "All 18 BAMs confirmed. Submitting StringTie2 pipeline..."
echo ""

sub() {
    sbatch --parsable \
           --partition="${HPC_PARTITION}" \
           "$@"
}

# S9a — StringTie2 per-sample assembly
J_ST=$(sub \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    09a_stringtie2_assembly.sh)
echo "[S9a] StringTie2 assembly    JOB ${J_ST}  (18 samples)"

# S9b — Merge + gffcompare
J_MERGE=$(sub \
    --dependency=afterok:${J_ST} \
    --output="${LOG_DIR}/%x_%j.log" \
    --error="${LOG_DIR}/%x_%j.err" \
    09b_stringtie_merge.sh)
echo "[S9b] StringTie merge        JOB ${J_MERGE}  (after S9a)"

# S9c — Build augmented Salmon index
J_IDX=$(sub \
    --dependency=afterok:${J_MERGE} \
    --output="${LOG_DIR}/%x_%j.log" \
    --error="${LOG_DIR}/%x_%j.err" \
    09c_build_augmented_index.sh)
echo "[S9c] Augmented index build  JOB ${J_IDX}  (after S9b)"

# S9d — Re-quantify all 18 samples
J_QUANT=$(sub \
    --dependency=afterok:${J_IDX} \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    09d_salmon_requant_augmented.sh)
echo "[S9d] Salmon re-quant array  JOB ${J_QUANT}  (after S9c)"

echo ""
echo "============================================================"
echo "StringTie2 pipeline submitted"
echo "  S9a StringTie2 assembly   ${J_ST}"
echo "  S9b Merge + gffcompare    ${J_MERGE}  → after S9a"
echo "  S9c Augmented index       ${J_IDX}  → after S9b"
echo "  S9d Re-quantification     ${J_QUANT}  → after S9c"
echo ""
echo "Estimated time: 3-4 hours total"
echo ""
echo "OUTPUTS when complete:"
echo "  Novel transcript GTF:"
echo "    ${RES_DIR}/stringtie_merged/novel_transcripts.gtf"
echo ""
echo "  gffcompare classification:"
echo "    ${RES_DIR}/stringtie_merged/gffcompare/gffcmp.annotated.gtf"
echo ""
echo "  Augmented Salmon quant (GENCODE v45 + novel):"
echo "    ${RES_DIR}/salmon_augmented/\${SAMPLE}/quant.sf"
echo ""
echo "  These replace results/salmon/ as input to Phase 2 R analysis"
echo "============================================================"

#!/bin/bash
#SBATCH --job-name=post_align_qc
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --mem=24G
#SBATCH --cpus-per-task=4
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%18
# =============================================================================
# Step 08: Post-alignment QC — SSD accelerated
# BAM random-access tools (RSeQC, Picard) are ~5-8x faster on SSD vs NFS.
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
NFS_OUT="${RES_QC}/${SAMPLE}"
setup_tmpdir "input" "output"
log_node_info
activate_conda
check_space 15   # BAM ~8 GB + BAI + BED

BAM_NFS="${RES_STAR}/${SAMPLE}_pass2/${SAMPLE}.bam"
BAI_NFS="${RES_STAR}/${SAMPLE}_pass2/${SAMPLE}.bam.bai"
[[ ! -f "${BAM_NFS}" ]] && { echo "ERROR: BAM not found: ${BAM_NFS}"; exit 1; }

echo "[1/2] Staging BAM + reference BED to SSD: ${SAMPLE}"
stage_in "${BAM_NFS}" "${TMPDIR}/input/"
stage_in "${BAI_NFS}" "${TMPDIR}/input/"
[[ -f "${REF_BED12}" ]] && stage_in "${REF_BED12}" "${TMPDIR}/input/" \
                        || echo "  NOTE: BED12 not found — RSeQC steps will skip"

BAM="${TMPDIR}/input/${SAMPLE}.bam"
BED="${TMPDIR}/input/$(basename ${REF_BED12})"

echo "[2/2] Running QC tools on SSD..."

# 1. samtools flagstat
echo "  [1/5] samtools flagstat..."
samtools flagstat -@ 4 "${BAM}" > "${TMPDIR}/output/${SAMPLE}_flagstat.txt"
grep "mapped (" "${TMPDIR}/output/${SAMPLE}_flagstat.txt" | head -1

# 2-5. RSeQC tools (require BED12)
if [[ -f "${BED}" ]]; then
    echo "  [2/5] infer_experiment.py (strandedness — critical for DESeq2)..."
    infer_experiment.py -i "${BAM}" -r "${BED}" \
        > "${TMPDIR}/output/${SAMPLE}_infer_experiment.txt" 2>&1
    grep "Fraction" "${TMPDIR}/output/${SAMPLE}_infer_experiment.txt" | head -3

    echo "  [3/5] junction_saturation.py..."
    junction_saturation.py -i "${BAM}" -r "${BED}" \
        -o "${TMPDIR}/output/${SAMPLE}_junc_sat" \
        > "${TMPDIR}/output/${SAMPLE}_junc_sat.log" 2>&1

    echo "  [4/5] read_distribution.py..."
    read_distribution.py -i "${BAM}" -r "${BED}" \
        > "${TMPDIR}/output/${SAMPLE}_read_dist.txt" 2>&1

    echo "  [5/5] inner_distance.py..."
    inner_distance.py -i "${BAM}" -r "${BED}" \
        -o "${TMPDIR}/output/${SAMPLE}_inner_dist" \
        > "${TMPDIR}/output/${SAMPLE}_inner_dist.log" 2>&1
else
    echo "  [2-5/5] RSeQC SKIPPED — BED12 not found at ${REF_BED12}"
    echo "  Generate with: gtfToGenePred + genePredToBed (from UCSC tools)"
fi

# Picard CollectRnaSeqMetrics (optional — requires refFlat + rRNA intervals)
if [[ -f "${REF_FLAT}" && -f "${RRNA_INTERVALS}" ]]; then
    echo "  Picard CollectRnaSeqMetrics..."
    picard CollectRnaSeqMetrics \
        -Xmx16g \
        INPUT="${BAM}" \
        OUTPUT="${TMPDIR}/output/${SAMPLE}_rnaseq_metrics.txt" \
        REF_FLAT="${REF_FLAT}" \
        RIBOSOMAL_INTERVALS="${RRNA_INTERVALS}" \
        STRAND_SPECIFICITY=SECOND_READ_TRANSCRIPTION_STRAND \
        2>&1 | tail -5
fi

echo ""
echo "QC complete for ${SAMPLE}: $(ls ${TMPDIR}/output/ | wc -l) output files"
echo "Copying QC reports to NFS via trap..."

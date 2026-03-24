#!/bin/bash
#SBATCH --job-name=stringtie2
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=16
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%9
# =============================================================================
# StringTie2 per-sample transcript assembly
# Uses STAR pass2 BAMs — discovers novel transcripts not in GENCODE v45
#
# Key flags:
#   -G  : guide assembly using reference GTF (keeps known + finds novel)
#   -e  : NOT used here — we want novel discovery (use -e only for quant)
#   -b  : output coverage info for Ballgown (optional)
#   -p  : threads
#   -v  : verbose
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
NFS_OUT="${RES_DIR}/stringtie/${SAMPLE}"
setup_tmpdir "input" "output"
log_node_info
activate_conda
check_space 20

BAM="${RES_STAR}/${SAMPLE}_pass2/${SAMPLE}.bam"
[[ ! -f "${BAM}" ]] && { echo "ERROR: BAM not found: ${BAM}"; exit 1; }

echo "[1/3] Staging BAM to SSD: ${SAMPLE}"
stage_in "${BAM}"       "${TMPDIR}/input/"
stage_in "${BAM}.bai"   "${TMPDIR}/input/"

echo "[2/3] StringTie2 assembly on SSD..."
stringtie \
    "${TMPDIR}/input/${SAMPLE}.bam" \
    -G  "${GTF}" \
    -o  "${TMPDIR}/output/${SAMPLE}.gtf" \
    -A  "${TMPDIR}/output/${SAMPLE}_gene_abund.tab" \
    -C  "${TMPDIR}/output/${SAMPLE}_cov_refs.gtf" \
    -p  16 \
    -v \
    2>&1 | tee "${TMPDIR}/output/${SAMPLE}_stringtie.log"

echo "[3/3] Assembly stats for ${SAMPLE}:"
echo "  Transcripts assembled: $(grep -c "transcript" ${TMPDIR}/output/${SAMPLE}.gtf || echo 0)"
echo "  Genes assembled      : $(grep -c "gene_id" ${TMPDIR}/output/${SAMPLE}.gtf | head -1 || echo 0)"

echo "Copying to NFS via trap..."

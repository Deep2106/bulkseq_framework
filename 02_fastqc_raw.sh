#!/bin/bash
#SBATCH --job-name=fastqc_raw
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=00:45:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=4
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%18
# =============================================================================
# Step 02: FastQC on raw reads — SLURM array (all 18 samples in parallel)
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
NFS_OUT="${RES_FASTQC_RAW}"
setup_tmpdir "input" "output"
log_node_info
activate_conda
check_space 20

echo "[1/3] Staging FASTQs to SSD: ${SAMPLE}"
echo "  ${FASTQ_DIR}/${SAMPLE}${R1_SUFFIX}"
stage_in "${FASTQ_DIR}/${SAMPLE}${R1_SUFFIX}" "${TMPDIR}/input/"
stage_in "${FASTQ_DIR}/${SAMPLE}${R2_SUFFIX}" "${TMPDIR}/input/"

echo "[2/3] FastQC..."
fastqc \
    --outdir  "${TMPDIR}/output" \
    --threads 4 \
    --extract \
    "${TMPDIR}/input/${SAMPLE}${R1_SUFFIX}" \
    "${TMPDIR}/input/${SAMPLE}${R2_SUFFIX}"

echo "[3/3] Done: $(ls ${TMPDIR}/output/ | tr '\n' ' ')"
echo "Copying QC reports to NFS via trap..."

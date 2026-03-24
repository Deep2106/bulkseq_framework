#!/bin/bash
#SBATCH --job-name=star_pass1
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=16
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%18
# =============================================================================
# Step 06a: STAR Pass 1 — junction discovery, SSD accelerated
#
# Pass 1 aligns each sample independently to discover novel splice junctions.
# IMPORTANT: only SJ.out.tab (~few MB) is copied to NFS.
# The pass 1 BAM is intentionally left on SSD and auto-wiped by SLURM.
# This saves ~90 GB NFS space across 18 samples — pass 1 BAMs have no
# downstream use; only the junction catalogue matters.
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
NFS_OUT="${RES_STAR}/${SAMPLE}_pass1"
setup_tmpdir "input/fastq" "input/index" "output" "nfs_copy"
log_node_info
activate_conda
check_space 55   # index 30 GB + trimmed FASTQs 14 GB + pass1 BAM 5 GB

echo "[1/3] Staging STAR index + trimmed FASTQs to SSD: ${SAMPLE}"
echo "  Index: ${STAR_INDEX} (~30 GB — takes a few minutes)"
stage_in "${STAR_INDEX}/"                                         "${TMPDIR}/input/index/"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R1_TRIM_SUFFIX}"     "${TMPDIR}/input/fastq/"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R2_TRIM_SUFFIX}"     "${TMPDIR}/input/fastq/"

echo "[2/3] STAR pass 1 on SSD..."
STAR \
    --runMode alignReads \
    --runThreadN 16 \
    --genomeDir   "${TMPDIR}/input/index" \
    --readFilesIn \
        "${TMPDIR}/input/fastq/${SAMPLE}${R1_TRIM_SUFFIX}" \
        "${TMPDIR}/input/fastq/${SAMPLE}${R2_TRIM_SUFFIX}" \
    --readFilesCommand zcat \
    --outSAMtype BAM SortedByCoordinate \
    --outSAMattributes NH HI AS NM MD \
    --outSAMstrandField intronMotif \
    --outSAMunmapped Within \
    --outFilterMultimapNmax 20 \
    --outFilterMismatchNoverReadLmax 0.04 \
    --outFilterIntronMotifs RemoveNoncanonical \
    --alignSJoverhangMin 8 \
    --alignSJDBoverhangMin 3 \
    --alignIntronMin 20 \
    --alignIntronMax 1000000 \
    --alignMatesGapMax 1000000 \
    --quantMode GeneCounts \
    --outFileNamePrefix "${TMPDIR}/output/" \
    --outBAMsortingThreadN 4 \
    --limitBAMsortRAM 20000000000

echo "[3/3] Pass 1 complete for ${SAMPLE}"
echo "  Novel junctions: $(wc -l < ${TMPDIR}/output/SJ.out.tab)"

# Only copy the small files to NFS — pass1 BAM stays on SSD and is wiped
cp "${TMPDIR}/output/SJ.out.tab"              "${TMPDIR}/nfs_copy/"
cp "${TMPDIR}/output/Log.final.out"           "${TMPDIR}/nfs_copy/"
cp "${TMPDIR}/output/ReadsPerGene.out.tab"    "${TMPDIR}/nfs_copy/" 2>/dev/null || true

# Redirect the trap target to only the small files
rm -rf "${TMPDIR}/output"
mv "${TMPDIR}/nfs_copy" "${TMPDIR}/output"

echo "  Pass1 BAM discarded (saves ~$(du -sh ${TMPDIR}/input/fastq/ | cut -f1) NFS I/O)"
echo "  Copying SJ.out.tab + logs to NFS via trap..."

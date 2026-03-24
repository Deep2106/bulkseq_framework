#!/bin/bash
#SBATCH --job-name=star_pass2
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=02:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=16
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%18
# =============================================================================
# Step 06c: STAR Pass 2 — final BAM production, SSD accelerated
#
# These BAMs are permanent outputs used for:
#   Phase 1: Post-alignment QC (RSeQC, Picard, samtools flagstat)
#   Phase 2: rMATS splicing event analysis, IGV visualisation
#
# SSD benefit is greatest here: sorted BAM write (2-3 GB/s SSD vs 200 MB/s NFS)
# and BAM indexing (pure random I/O — SSD is ~10x faster than NFS).
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
NFS_OUT="${RES_STAR}/${SAMPLE}_pass2"
setup_tmpdir "input/fastq" "input/index" "output"
log_node_info
activate_conda
check_space 60   # index 30 GB + trimmed FASTQs 14 GB + pass2 BAM 8 GB

POOLED_SJ="${RES_STAR}/pooled_junctions_pass1.SJ.out.tab"
[[ ! -f "${POOLED_SJ}" ]] && { echo "ERROR: ${POOLED_SJ} not found"; exit 1; }

echo "[1/4] Staging inputs to SSD: ${SAMPLE}"
echo "  Index: ${STAR_INDEX} (~30 GB)"
stage_in "${STAR_INDEX}/"                                         "${TMPDIR}/input/index/"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R1_TRIM_SUFFIX}"     "${TMPDIR}/input/fastq/"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R2_TRIM_SUFFIX}"     "${TMPDIR}/input/fastq/"
echo "  Pooled junctions: $(wc -l < ${POOLED_SJ})"

echo "[2/4] STAR pass 2 on SSD..."
STAR \
    --runMode alignReads \
    --runThreadN 16 \
    --genomeDir   "${TMPDIR}/input/index" \
    --readFilesIn \
        "${TMPDIR}/input/fastq/${SAMPLE}${R1_TRIM_SUFFIX}" \
        "${TMPDIR}/input/fastq/${SAMPLE}${R2_TRIM_SUFFIX}" \
    --readFilesCommand zcat \
    --sjdbFileChrStartEnd "${POOLED_SJ}" \
    --sjdbOverhang        "${SJDB_OVERHANG}" \
    --outSAMtype BAM SortedByCoordinate \
    --outSAMattributes NH HI AS NM MD \
    --outSAMstrandField intronMotif \
    --outSAMunmapped Within \
    --outSAMattrRGline "ID:${SAMPLE} SM:${SAMPLE} PL:ILLUMINA LB:${SAMPLE}" \
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

echo "[3/4] Indexing BAM on SSD (random I/O — SSD critical)..."
mv "${TMPDIR}/output/Aligned.sortedByCoord.out.bam" \
   "${TMPDIR}/output/${SAMPLE}.bam"
samtools index -@ 4 "${TMPDIR}/output/${SAMPLE}.bam"

echo "[4/4] Alignment stats for ${SAMPLE}:"
samtools flagstat -@ 4 "${TMPDIR}/output/${SAMPLE}.bam" \
    | grep -E "mapped|properly paired"

MAP=$(samtools flagstat "${TMPDIR}/output/${SAMPLE}.bam" \
      | grep "mapped (" | head -1 | grep -oP '\d+\.\d+(?=%)' | head -1)
echo "  Mapping rate: ${MAP}%"
[[ $(echo "${MAP} < 75" | bc -l) -eq 1 ]] && \
    echo "  WARNING: mapping rate <75% — check strandedness / FASTQ quality"

echo "  BAM size: $(du -sh ${TMPDIR}/output/${SAMPLE}.bam | cut -f1)"
echo "Copying BAM + BAI + logs to NFS via trap..."

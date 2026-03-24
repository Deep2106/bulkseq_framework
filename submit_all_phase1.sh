#!/bin/bash
# =============================================================================
# submit_all_phase1.sh — Master submission script
# Submits all Phase 1 jobs with correct SLURM dependency chain.
# SLURM handles execution order automatically.
#
# Phase 1 scope: FASTQ → QC → trim → align (STAR) → quantify (Salmon) → QC
# Phase 1 output: quant.sf files (Salmon) + BAM files (STAR)
#
# Phase 2 (DESeq2, tximeta, ISA etc.) runs SEPARATELY after Phase 1 completes,
# on a machine where R packages can be installed.
#
# *** ZERO EDITS NEEDED — all paths come from project_config.sh ***
#
# Prerequisites:
#   1. Edit project_config.sh  (PROJ_DIR, FASTQ_DIR, READ_LENGTH)
#   2. Run: bash create_conda_env.sh
#   3. Run: bash 00_preflight_check.sh
#   4. Run: bash submit_all_phase1.sh   ← this script
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
cd "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts"

# ── Pre-flight guard ──────────────────────────────────────────────────────────
if [[ ! -d "${FASTQ_LINKS}" ]] || \
   [[ -z "$(ls -A "${FASTQ_LINKS}" 2>/dev/null)" ]]; then
    echo "ERROR: ${FASTQ_LINKS}/ is empty."
    echo "       Run 00_preflight_check.sh before submitting."
    exit 1
fi

echo "============================================================"
echo "Phase 1 — Hormone x IPF RNAseq | RCSI HPC"
echo "PROJ_DIR  : ${PROJ_DIR}"
echo "FASTQ_DIR : ${FASTQ_DIR}"
echo "CONDA_ENV : ${CONDA_ENV}"
echo "PARTITION : ${HPC_PARTITION}"
echo "READ LEN  : ${READ_LENGTH} bp  (sjdbOverhang=${SJDB_OVERHANG})"
echo "Submitting: $(date)"
echo "============================================================"
echo ""

# Helper: submit job and return job ID
sub() {
    sbatch --parsable \
           --partition="${HPC_PARTITION}" \
           ${SLURM_ACCOUNT:+--account="${SLURM_ACCOUNT}"} \
           "$@"
}

# ── S0: Download references ───────────────────────────────────────────────────
#J_REFS=$(sub \
#    --output="${LOG_DIR}/%x_%j.log" \
#    --error="${LOG_DIR}/%x_%j.err" \
#    00_download_references.sh)
#echo "[S0]  Download refs         JOB ${J_REFS}"

# ── S1a+S1b: Build indexes (parallel, both after S0) ─────────────────────────
J_STAR_IDX=$(sub \
    --output="${LOG_DIR}/%x_%j.log" \
    --error="${LOG_DIR}/%x_%j.err" \
    01a_star_index.sh)
echo "[S1a] STAR index            JOB ${J_STAR_IDX}   (after S0)"

J_SAL_IDX=$(sub \
    --output="${LOG_DIR}/%x_%j.log" \
    --error="${LOG_DIR}/%x_%j.err" \
    01b_salmon_index.sh)
echo "[S1b] Salmon index          JOB ${J_SAL_IDX}   (after S0)"

# ── S2: FastQC raw (immediate — no ref dependency) ───────────────────────────
J_FQC_RAW=$(sub \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    02_fastqc_raw.sh)
echo "[S2]  FastQC raw array      JOB ${J_FQC_RAW}"

J_MQC_RAW=$(sub \
    --dependency=afterok:${J_FQC_RAW} \
    --job-name=multiqc_raw \
    --time=00:30:00 --mem=8G --cpus-per-task=2 \
    --output="${LOG_DIR}/multiqc_raw_%j.log" \
    --error="${LOG_DIR}/multiqc_raw_%j.err" \
    --wrap="source /home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh && \
            source ${CONDA_BASE}/etc/profile.d/conda.sh && \
            conda activate ${CONDA_ENV} && \
            bash /home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/03_multiqc.sh raw")
echo "[S3]  MultiQC raw           JOB ${J_MQC_RAW}   (after S2)"

# ── S4: fastp trimming (immediate) ───────────────────────────────────────────
J_FASTP=$(sub \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    04_fastp_trim.sh)
echo "[S4]  fastp array           JOB ${J_FASTP}"

# Post-trim FastQC + MultiQC
J_MQC_TRIM=$(sub \
    --dependency=afterok:${J_FASTP} \
    --job-name=multiqc_trimmed \
    --time=01:00:00 --mem=8G --cpus-per-task=4 \
    --output="${LOG_DIR}/multiqc_trimmed_%j.log" \
    --error="${LOG_DIR}/multiqc_trimmed_%j.err" \
    --wrap="source /home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh && \
            source ${CONDA_BASE}/etc/profile.d/conda.sh && \
            conda activate ${CONDA_ENV} && \
            fastqc --outdir ${RES_FASTQC_TRIM} --threads 4 \
                   ${RES_FASTP}/*/*${R1_TRIM_SUFFIX} \
                   ${RES_FASTP}/*/*${R2_TRIM_SUFFIX} && \
            bash /home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/03_multiqc.sh trimmed")
echo "[S5]  FastQC+MultiQC trim   JOB ${J_MQC_TRIM}  (after S4)"

# ── S6a: STAR pass 1 (after fastp + STAR index) ───────────────────────────────
J_STAR_P1=$(sub \
    --dependency=afterok:${J_FASTP}:${J_STAR_IDX} \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    06a_star_pass1.sh)
echo "[S6a] STAR pass1 array      JOB ${J_STAR_P1}  (after S4+S1a)"

# ── S6b: Pool junctions ───────────────────────────────────────────────────────
J_POOL=$(sub \
    --dependency=afterok:${J_STAR_P1} \
    --output="${LOG_DIR}/%x_%j.log" \
    --error="${LOG_DIR}/%x_%j.err" \
    06b_star_pool_junctions.sh)
echo "[S6b] Junction pooling      JOB ${J_POOL}    (after S6a)"

# ── S6c: STAR pass 2 — final BAMs ────────────────────────────────────────────
J_STAR_P2=$(sub \
    --dependency=afterok:${J_POOL} \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    06c_star_pass2.sh)
echo "[S6c] STAR pass2 array      JOB ${J_STAR_P2}  (after S6b)"

# ── S7: Salmon quant (parallel with STAR — after fastp + salmon index) ────────
J_SALMON=$(sub \
    --dependency=afterok:${J_FASTP}:${J_SAL_IDX} \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    07_salmon_quant.sh)
echo "[S7]  Salmon array          JOB ${J_SALMON}  (after S4+S1b) [parallel with S6]"

# ── S8: Post-alignment QC (after pass2 BAMs) ─────────────────────────────────
J_PAQC=$(sub \
    --dependency=afterok:${J_STAR_P2} \
    --output="${LOG_DIR}/%x_%A_%a.log" \
    --error="${LOG_DIR}/%x_%A_%a.err" \
    08_post_align_qc.sh)
echo "[S8]  Post-align QC array   JOB ${J_PAQC}   (after S6c)"

# ── S9: Final MultiQC — the definitive QC report ─────────────────────────────
J_MQC_ALIGN=$(sub \
    --dependency=afterok:${J_PAQC}:${J_SALMON} \
    --job-name=multiqc_alignment \
    --time=00:30:00 --mem=8G --cpus-per-task=2 \
    --output="${LOG_DIR}/multiqc_alignment_%j.log" \
    --error="${LOG_DIR}/multiqc_alignment_%j.err" \
    --wrap="source /home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh && \
            source ${CONDA_BASE}/etc/profile.d/conda.sh && \
            conda activate ${CONDA_ENV} && \
            bash /home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/03_multiqc.sh alignment")
echo "[S9]  MultiQC alignment     JOB ${J_MQC_ALIGN}  (after S8+S7) ← PHASE 1 COMPLETE"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "ALL JOBS QUEUED"
echo "============================================================"
echo ""
echo "Dependency chain:"
echo "  S0  refs download    ${J_REFS}"
echo "  S1a STAR index       ${J_STAR_IDX}  → after S0"
echo "  S1b Salmon index     ${J_SAL_IDX}  → after S0"
echo "  S2  FastQC raw       ${J_FQC_RAW}  → immediate"
echo "  S3  MultiQC raw      ${J_MQC_RAW}  → after S2"
echo "  S4  fastp            ${J_FASTP}  → immediate"
echo "  S5  MultiQC trim     ${J_MQC_TRIM}  → after S4"
echo "  S6a STAR pass1       ${J_STAR_P1}  → after S4+S1a"
echo "  S6b junction pool    ${J_POOL}  → after S6a"
echo "  S6c STAR pass2       ${J_STAR_P2}  → after S6b"
echo "  S7  Salmon quant     ${J_SALMON}  → after S4+S1b  (parallel with S6)"
echo "  S8  post-align QC    ${J_PAQC}  → after S6c"
echo "  S9  MultiQC align    ${J_MQC_ALIGN}  → after S8+S7  *** END OF PHASE 1 ***"
echo ""
echo "Monitor : watch -n 30 'squeue -u \$USER'"
echo "Details : sacct -u \$USER --format=JobID,JobName,State,Elapsed"
echo ""
echo "─────────────────────────────────────────────────────────────"
echo "PHASE 1 COMPLETE when JOB ${J_MQC_ALIGN} shows COMPLETED"
echo "Estimated wall time: 6-8 hours"
echo "─────────────────────────────────────────────────────────────"
echo ""
echo "PHASE 1 OUTPUTS (inputs to Phase 2 R analysis):"
echo ""
echo "  Salmon quantification (gene + isoform level):"
echo "    ${RES_SALMON}/\${SAMPLE}/quant.sf        transcript counts + TPM"
echo "    ${RES_SALMON}/\${SAMPLE}/quant.genes.sf   gene-level counts + TPM"
echo "    ${RES_SALMON}/\${SAMPLE}/aux_info/        bootstrap replicates"
echo ""
echo "  STAR alignments (for rMATS splicing in Phase 2):"
echo "    ${RES_STAR}/\${SAMPLE}_pass2/\${SAMPLE}.bam"
echo "    ${RES_STAR}/\${SAMPLE}_pass2/\${SAMPLE}.bam.bai"
echo ""
echo "  QC reports:"
echo "    ${RES_MULTIQC}/multiqc_raw.html"
echo "    ${RES_MULTIQC}/multiqc_trimmed.html"
echo "    ${RES_MULTIQC}/multiqc_alignment.html"
echo ""
echo "NEXT: Transfer quant.sf files to a machine with R installed"
echo "      for Phase 2 (DESeq2, tximeta, IsoformSwitchAnalyzeR etc.)"
echo "============================================================"

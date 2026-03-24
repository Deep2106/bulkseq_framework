#!/bin/bash
#SBATCH --job-name=augmented_index
#SBATCH --output=%x_%j.log
#SBATCH --error=%x_%j.err
#SBATCH --time=02:00:00
#SBATCH --mem=96G
#SBATCH --cpus-per-task=24
#SBATCH --partition=ProdQ
# =============================================================================
# Step 09c: Build augmented Salmon index
# Combines GENCODE v45 transcripts + novel transcripts from StringTie2
# then builds a new decoy-aware Salmon index
#
# Scientific rationale:
#   Standard Salmon index only quantifies annotated transcripts.
#   Novel disease-specific transcripts in IPF (e.g. novel SFTPC isoforms,
#   MUC5B variants, stress-response lncRNAs) are invisible to standard
#   quantification. This augmented index captures them.
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

NFS_OUT="${REF_DIR}/salmon_index_augmented"
setup_tmpdir "input" "output"
log_node_info
activate_conda
check_space 65   # transcriptome FASTA + novel FASTA + gentrome + index

MERGE_DIR="${RES_DIR}/stringtie_merged"
NOVEL_GTF="${MERGE_DIR}/novel_transcripts.gtf"
AUG_DIR="${REF_DIR}/augmented"
mkdir -p "${AUG_DIR}"

echo "============================================================"
echo "Building augmented Salmon index"
echo "  Reference : GENCODE v45"
echo "  Novel GTF : ${NOVEL_GTF}"
echo "============================================================"

# ── [1/5] Extract novel transcript sequences using gffread ───────────────────
echo "[1/5] Extracting novel transcript sequences with gffread..."
NOVEL_FA="${AUG_DIR}/novel_transcripts.fa"

gffread \
    "${NOVEL_GTF}" \
    -g "${GENOME_FA}" \
    -w "${NOVEL_FA}"

NOVEL_TX=$(grep -c "^>" "${NOVEL_FA}" || echo 0)
echo "  Novel transcript sequences extracted: ${NOVEL_TX}"

if [[ "${NOVEL_TX}" -eq 0 ]]; then
    echo "WARNING: No novel transcripts extracted."
    echo "         Check that novel_transcripts.gtf is not empty."
    echo "         Proceeding with standard GENCODE v45 index only."
    cp "${SALMON_INDEX}" "${NFS_OUT}" -r 2>/dev/null || true
    exit 0
fi

# ── [2/5] Concatenate GENCODE v45 + novel transcripts ────────────────────────
echo ""
echo "[2/5] Building augmented transcriptome FASTA..."
AUG_TX_FA="${AUG_DIR}/transcripts_gencodev45_plus_novel.fa"

cat "${TX_FA}" "${NOVEL_FA}" > "${AUG_TX_FA}"

TOTAL_TX=$(grep -c "^>" "${AUG_TX_FA}")
GENCODE_TX=$(grep -c "^>" "${TX_FA}")
echo "  GENCODE v45 transcripts : ${GENCODE_TX}"
echo "  Novel transcripts       : ${NOVEL_TX}"
echo "  Total in augmented FA   : ${TOTAL_TX}"

# ── [3/5] Build augmented gentrome ───────────────────────────────────────────
echo ""
echo "[3/5] Staging files to SSD and building augmented gentrome..."
stage_in "${AUG_TX_FA}"   "${TMPDIR}/input/"
stage_in "${GENOME_FA}"   "${TMPDIR}/input/"
stage_in "${DECOYS}"      "${TMPDIR}/input/"

# Augmented gentrome = novel + GENCODE transcripts + genome (as decoy)
cat "${TMPDIR}/input/$(basename ${AUG_TX_FA})" \
    "${TMPDIR}/input/$(basename ${GENOME_FA})" \
    > "${TMPDIR}/input/gentrome_augmented.fa"

echo "  Augmented gentrome: $(du -sh ${TMPDIR}/input/gentrome_augmented.fa | cut -f1)"

# ── [4/5] Build Salmon index ──────────────────────────────────────────────────
echo ""
echo "[4/5] Building Salmon index on SSD..."
salmon index \
    --transcripts "${TMPDIR}/input/gentrome_augmented.fa" \
    --decoys       "${TMPDIR}/input/$(basename ${DECOYS})" \
    --index        "${TMPDIR}/output" \
    --gencode \
    --threads 24 \
    --keepDuplicates \
    2>&1 | tee "${TMPDIR}/output/salmon_index.log"

echo "  Index size: $(du -sh ${TMPDIR}/output | cut -f1)"


echo ""
echo "============================================================"
echo "Augmented index built."
echo "  Index location  : ${NFS_OUT}"
echo "  Novel sequences : ${NOVEL_TX}"
echo "  Total transcripts in index: ${TOTAL_TX}"
echo ""
echo "NEXT: Run 09d_salmon_requant_augmented.sh"
echo "      Re-quantify all 18 samples against augmented index"
echo "Completed: $(date)"
echo "============================================================"

echo "Copying index to NFS via trap..."

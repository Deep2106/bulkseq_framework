#!/bin/bash
#SBATCH --job-name=stringtie_merge
#SBATCH --output=%x_%j.log
#SBATCH --error=%x_%j.err
#SBATCH --time=01:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --partition=ProdQ
# =============================================================================
# Step 09b: Merge per-sample StringTie2 GTFs into one consensus GTF
#           then classify transcripts with gffcompare
#
# gffcompare class codes for novel transcripts:
#   u = unknown intergenic transcript    (novel locus)
#   x = exonic overlap on opposite strand
#   i = intronic transcript              (retained intron candidate)
#   o = generic exonic overlap
#   j = multi-exon with at least one novel junction  ← most interesting
#   e = single exon transcript overlapping reference
#   c = contained in reference exon
#
# We keep: j (novel junctions) + u (novel loci) + i (intron retention)
# We discard: single-exon novel transcripts (high false positive rate)
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"
activate_conda

STRINGTIE_DIR="${RES_DIR}/stringtie"
MERGE_DIR="${RES_DIR}/stringtie_merged"
mkdir -p "${MERGE_DIR}"

echo "============================================================"
echo "StringTie2 merge + gffcompare classification"
echo "Started: $(date)"
echo "============================================================"

# ── [1/5] Verify all 18 per-sample GTFs exist ────────────────────────────────
echo "[1/5] Checking per-sample GTF files..."
GTF_LIST="${MERGE_DIR}/gtf_list.txt"
> "${GTF_LIST}"

while read SAMPLE; do
    GTF_FILE="${STRINGTIE_DIR}/${SAMPLE}/${SAMPLE}.gtf"
    if [[ ! -f "${GTF_FILE}" ]]; then
        echo "ERROR: Missing ${GTF_FILE}"
        echo "       Run 09a_stringtie2_assembly.sh first"
        exit 1
    fi
    echo "${GTF_FILE}" >> "${GTF_LIST}"
    echo "  Found: ${SAMPLE}.gtf ($(grep -c 'transcript_id' ${GTF_FILE}) features)"
done < "${SAMPLES}"

echo "  All $(wc -l < ${GTF_LIST}) GTF files confirmed."

# ── [2/5] Merge all per-sample GTFs ──────────────────────────────────────────
echo ""
echo "[2/5] Merging with stringtie --merge..."
MERGED_GTF="${MERGE_DIR}/merged_all_samples.gtf"

stringtie --merge \
    -G  "${GTF}" \
    -o  "${MERGED_GTF}" \
    -m  50 \
    -T  1.0 \
    -f  0.01 \
    -i \
    "${GTF_LIST}" \
    2>&1 | tee "${MERGE_DIR}/stringtie_merge.log"

# --merge flags:
#   -m 50    minimum transcript length (bp) — removes very short artifacts
#   -T 1.0   minimum TPM across samples — removes very lowly expressed transcripts
#   -f 0.01  minimum isoform fraction — removes very rare isoforms
#   -i       keep retained introns — important for IPF ER stress analysis

TOTAL_TX=$(grep -c "transcript_id" "${MERGED_GTF}" || echo 0)
echo "  Total transcripts in merged GTF: ${TOTAL_TX}"

# ── [3/5] gffcompare — classify vs reference GENCODE v45 ─────────────────────
echo ""
echo "[3/5] gffcompare classification vs GENCODE v45..."
GFFCMP_DIR="${MERGE_DIR}/gffcompare"
mkdir -p "${GFFCMP_DIR}"

gffcompare \
    -r "${GTF}" \
    -G \
    -o "${GFFCMP_DIR}/gffcmp" \
    "${MERGED_GTF}" \
    2>&1 | tee "${GFFCMP_DIR}/gffcompare.log"

# Report class code distribution
echo ""
echo "  Transcript class code distribution:"
awk '$3=="transcript"' "${GFFCMP_DIR}/gffcmp.annotated.gtf" \
    | grep -oP 'class_code "[^"]+"' \
    | sort | uniq -c | sort -rn \
    | sed 's/^/    /'

# ── [4/5] Extract novel transcripts ──────────────────────────────────────────
echo ""
echo "[4/5] Filtering novel transcripts..."
NOVEL_GTF="${MERGE_DIR}/novel_transcripts.gtf"

# Keep transcripts with novel junction (j), novel locus (u), intron retention (i)
# Exclude single-exon novel transcripts (high false positive rate)
awk '$3=="transcript"' "${GFFCMP_DIR}/gffcmp.annotated.gtf" \
    | grep -E 'class_code "[jui]"' \
    | grep -oP 'transcript_id "[^"]+"' \
    | sort -u \
    > "${MERGE_DIR}/novel_tx_ids.txt"

# Also require minimum 2 exons (filter single-exon)
NOVEL_COUNT=$(wc -l < "${MERGE_DIR}/novel_tx_ids.txt")
echo "  Novel transcript candidates: ${NOVEL_COUNT}"
echo "  Class codes kept: j (novel junction), u (novel locus), i (intron retention)"

# Extract novel transcripts from merged GTF
grep -F -f "${MERGE_DIR}/novel_tx_ids.txt" "${MERGED_GTF}" \
    > "${NOVEL_GTF}"

echo "  Novel GTF entries: $(wc -l < ${NOVEL_GTF})"

# ── [5/5] Summary ─────────────────────────────────────────────────────────────
echo ""
echo "============================================================"
echo "MERGE SUMMARY"
echo "============================================================"
echo "  Merged GTF          : ${MERGED_GTF}"
echo "  gffcompare output   : ${GFFCMP_DIR}/"
echo "  Novel transcript IDs: ${MERGE_DIR}/novel_tx_ids.txt"
echo "  Novel GTF           : ${NOVEL_GTF}"
echo ""
echo "  NEXT: Run 09c_build_augmented_index.sh"
echo "        This combines GENCODE v45 + novel transcripts"
echo "        then rebuilds the Salmon index"
echo "Completed: $(date)"
echo "============================================================"

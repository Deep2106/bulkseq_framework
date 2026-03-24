#!/bin/bash
#SBATCH --job-name=multiqc
#SBATCH --output=%x_%j.log
#SBATCH --error=%x_%j.err
#SBATCH --time=00:30:00
#SBATCH --mem=8G
#SBATCH --cpus-per-task=2
#SBATCH --partition=ProdQ
# =============================================================================
# Step 03 / 05b / 09: MultiQC aggregation
# Called 3 times with a STAGE argument:
#   sbatch 03_multiqc.sh raw         — after FastQC on raw reads
#   sbatch 03_multiqc.sh trimmed     — after FastQC on trimmed reads
#   sbatch 03_multiqc.sh alignment   — after STAR + RSeQC + Picard
#
# Runs entirely on NFS — QC report files are small; no SSD benefit.
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"
activate_conda

STAGE="${1:-raw}"
echo "MultiQC — stage: ${STAGE} | $(date)"

case "${STAGE}" in
    raw)
        multiqc "${RES_FASTQC_RAW}" \
            --outdir  "${RES_MULTIQC}" \
            --filename multiqc_raw \
            --title   "Raw reads QC — Hormone x IPF" \
            --force
        ;;
    trimmed)
        multiqc "${RES_FASTQC_TRIM}" "${RES_FASTP}" \
            --outdir  "${RES_MULTIQC}" \
            --filename multiqc_trimmed \
            --title   "Post-trim QC — Hormone x IPF" \
            --force
        ;;
    alignment)
        multiqc "${RES_DIR}" \
            --outdir  "${RES_MULTIQC}" \
            --filename multiqc_alignment \
            --title   "Alignment QC — Hormone x IPF" \
            --ignore "${RES_MATRICES}" \
            --force
        ;;
    *)
        echo "ERROR: unknown stage '${STAGE}'. Use: raw | trimmed | alignment"
        exit 1
        ;;
esac

echo ""
echo "Report: ${RES_MULTIQC}/multiqc_${STAGE}.html"
echo "Done: $(date)"
echo ""
echo "========================================================"
echo "REVIEW CHECKLIST — ${STAGE}"
case "${STAGE}" in
    raw)
        echo "  [ ] Per-base quality Q30 >80% all samples?"
        echo "  [ ] GC content unimodal, ~50%?"
        echo "  [ ] Duplication rate <60%?"
        echo "  [ ] Adapter content identified?"
        ;;
    trimmed)
        echo "  [ ] Adapter content = 0%?"
        echo "  [ ] Q30 >85% all samples?"
        echo "  [ ] fastp pass rate >80% all samples?"
        echo "  [ ] Insert size consistent within groups?"
        ;;
    alignment)
        echo "  [ ] Mapping rate >80% all samples?"
        echo "  [ ] Strandedness consistent across 18 samples?"
        echo "  [ ] Junction saturation >80%?"
        echo "  [ ] Exonic reads >60%?"
        echo "  [ ] Any samples to exclude? Document in methods."
        ;;
esac
echo "========================================================"

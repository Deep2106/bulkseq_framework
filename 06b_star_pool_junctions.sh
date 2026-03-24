#!/bin/bash
#SBATCH --job-name=pool_junctions
#SBATCH --output=%x_%j.log
#SBATCH --error=%x_%j.err
#SBATCH --time=00:15:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --partition=ProdQ
# =============================================================================
# Step 06b: Pool splice junctions from all 18 STAR pass-1 runs
# Files are tiny (~MB each) — runs entirely on NFS, no SSD needed.
# Filters: canonical motif (col5>0) AND ≥3 uniquely-mapped reads (col7>2)
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"
activate_conda

POOLED="${RES_STAR}/pooled_junctions_pass1.SJ.out.tab"

echo "Pooling junctions from all 18 STAR pass-1 runs | $(date)"

# Verify all 18 SJ.out.tab files are present
while read SAMPLE; do
    SJ="${RES_STAR}/${SAMPLE}_pass1/SJ.out.tab"
    [[ ! -f "${SJ}" ]] && { echo "ERROR: Missing ${SJ}"; exit 1; }
done < "${SAMPLES}"
echo "All 18 SJ.out.tab files confirmed."

# Pool with quality filters
cat $(while read S; do echo "${RES_STAR}/${S}_pass1/SJ.out.tab"; done < "${SAMPLES}") \
    | awk '($5>0 && $7>2)' \
    | cut -f1-6 \
    | sort -u \
    > "${POOLED}"

TOTAL=$(wc -l < "${POOLED}")
NOVEL=$(awk '$6==0' "${POOLED}" | wc -l)
ANNOT=$((TOTAL - NOVEL))

echo ""
echo "Pooled junctions  : ${TOTAL}"
echo "  Annotated       : ${ANNOT}"
echo "  Novel           : ${NOVEL}  ($(echo "scale=1; 100*${NOVEL}/${TOTAL}" | bc)%)"
echo "Saved: ${POOLED}"
echo "Done: $(date)"

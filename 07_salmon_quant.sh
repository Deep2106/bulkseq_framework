#!/bin/bash
#SBATCH --job-name=salmon_quant
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=01:00:00
#SBATCH --mem=32G
#SBATCH --cpus-per-task=8
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%18
# =============================================================================
# Step 07: Salmon quantification — SSD accelerated
# Selective alignment = random index I/O; 30 bootstraps = significant writes.
# Both benefit from SSD. Runs in PARALLEL with STAR steps (independent).
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
NFS_OUT="${RES_SALMON}/${SAMPLE}"
setup_tmpdir "input/fastq" "input/index" "output"
log_node_info
activate_conda
check_space 20   # index 2 GB + trimmed FASTQs 14 GB + quant output 0.3 GB

echo "[1/3] Staging Salmon index + trimmed FASTQs to SSD: ${SAMPLE}"
echo "  Staging Salmon index NFS → SSD..."
rsync -a --no-perms "${SALMON_INDEX}/" "${TMPDIR}/input/index/" \
    || { echo "ERROR: index staging failed"; exit 1; }
echo "  Index staged: $(ls ${TMPDIR}/input/index/ | wc -l) files"
echo "  Key file check: $(ls ${TMPDIR}/input/index/mphf.bin 2>/dev/null && echo OK || echo MISSING)"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R1_TRIM_SUFFIX}"     "${TMPDIR}/input/fastq/"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R2_TRIM_SUFFIX}"     "${TMPDIR}/input/fastq/"

# Add this line immediately before salmon quant:
echo "  Index path contents: $(ls ${TMPDIR}/input/index/ | head -5)"

echo "[2/3] Salmon quant on SSD..."
set -x
salmon quant \
    --index   "${TMPDIR}/input/index" \
    --libType A \
    --mates1  "${TMPDIR}/input/fastq/${SAMPLE}${R1_TRIM_SUFFIX}" \
    --mates2  "${TMPDIR}/input/fastq/${SAMPLE}${R2_TRIM_SUFFIX}" \
    --validateMappings \
    --gcBias \
    --seqBias \
    --posBias \
    --rangeFactorizationBins 4 \
    --numBootstraps 30 \
    --geneMap "${GTF}" \
    --threads 8 \
    --output "${TMPDIR}/output"
set +x

echo "[3/3] Mapping stats for ${SAMPLE}:"
python3 -c "
import json
with open('${TMPDIR}/output/aux_info/meta_info.json') as f:
    d = json.load(f)
print(f'  Mapping rate : {d.get(\"percent_mapped\", \"N/A\")}%')
print(f'  Mapped reads : {d.get(\"num_mapped\", \"N/A\")}')
print(f'  Total reads  : {d.get(\"num_processed\", \"N/A\")}')
"
echo "  Transcripts  : $(tail -n+2 ${TMPDIR}/output/quant.sf | wc -l)"
echo "  Bootstraps   : $(ls ${TMPDIR}/output/aux_info/bootstrap/ 2>/dev/null | wc -l)"
echo "  Output size  : $(du -sh ${TMPDIR}/output | cut -f1)"
echo "Copying quant dir to NFS via trap..."

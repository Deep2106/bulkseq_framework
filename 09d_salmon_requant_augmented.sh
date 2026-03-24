#!/bin/bash
#SBATCH --job-name=salmon_augmented
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=01:00:00
#SBATCH --mem=48G
#SBATCH --cpus-per-task=16
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%8
# =============================================================================
# Step 09d: Re-quantify all 18 samples against augmented Salmon index
# (GENCODE v45 + novel StringTie2 transcripts)
#
# Outputs go to results/salmon_augmented/${SAMPLE}/
# Original results/salmon/ (GENCODE only) are preserved for comparison.
# =============================================================================
set -euo pipefail

source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
AUG_INDEX="${REF_DIR}/salmon_index_augmented"
AUG_RESULTS="${RES_DIR}/salmon_augmented"

NFS_OUT="${AUG_RESULTS}/${SAMPLE}"
setup_tmpdir "input/fastq" "input/index" "output"
log_node_info
activate_conda
check_space 20

[[ ! -d "${AUG_INDEX}" ]] && {
    echo "ERROR: Augmented index not found: ${AUG_INDEX}"
    echo "       Run 09c_build_augmented_index.sh first"
    exit 1
}

echo "[1/3] Staging augmented index + trimmed FASTQs to SSD: ${SAMPLE}"
stage_in "${AUG_INDEX}/"                                          "${TMPDIR}/input/index/"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R1_TRIM_SUFFIX}"      "${TMPDIR}/input/fastq/"
stage_in "${RES_FASTP}/${SAMPLE}/${SAMPLE}${R2_TRIM_SUFFIX}"      "${TMPDIR}/input/fastq/"

echo "[2/3] Salmon quantification against augmented index..."
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
    --threads 16 \
    --output "${TMPDIR}/output" \
    2>&1 | tee "${TMPDIR}/output/salmon_augmented.log"

echo "[3/3] Mapping stats for ${SAMPLE} (augmented):"
python3 -c "
import json
with open('${TMPDIR}/output/aux_info/meta_info.json') as f:
    d = json.load(f)
print(f'  Mapping rate : {d.get(\"percent_mapped\", \"N/A\")}%')
print(f'  Mapped reads : {d.get(\"num_mapped\", \"N/A\")}')
"

# Compare mapping rate vs original Salmon
ORIG_META="${RES_SALMON}/${SAMPLE}/aux_info/meta_info.json"
if [[ -f "${ORIG_META}" ]]; then
    ORIG_RATE=$(python3 -c "
import json
with open('${ORIG_META}') as f:
    d=json.load(f)
print(d.get('percent_mapped','N/A'))
")
    echo "  Original mapping rate  : ${ORIG_RATE}%"
    echo "  (improvement = reads now mapping to novel transcripts)"
fi

echo "Copying augmented quant to NFS via trap..."

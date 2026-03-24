#!/bin/bash
#SBATCH --job-name=fastp_trim
#SBATCH --output=%x_%A_%a.log
#SBATCH --error=%x_%A_%a.err
#SBATCH --time=01:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=8
#SBATCH --partition=ProdQ
#SBATCH --array=1-18%18
# =============================================================================
# Step 04: fastp adapter trimming + QC — SSD accelerated (I/O bound)
# Stage raw FASTQs → SSD, trim, copy trimmed FASTQs + JSON/HTML → NFS
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

SAMPLE=$(sed -n "${SLURM_ARRAY_TASK_ID}p" "${SAMPLES}")
NFS_OUT="${RES_FASTP}/${SAMPLE}"
setup_tmpdir "input" "output"
log_node_info
activate_conda
check_space 35   # raw R1+R2 ~14 GB + trimmed output ~13 GB

echo "[1/3] Staging raw FASTQs to SSD: ${SAMPLE}"
echo "  ${FASTQ_DIR}/${SAMPLE}${R1_SUFFIX}"
stage_in "${FASTQ_DIR}/${SAMPLE}${R1_SUFFIX}" "${TMPDIR}/input/"
stage_in "${FASTQ_DIR}/${SAMPLE}${R2_SUFFIX}" "${TMPDIR}/input/"

echo "[2/3] fastp trimming on SSD..."
fastp \
    --in1  "${TMPDIR}/input/${SAMPLE}${R1_SUFFIX}" \
    --in2  "${TMPDIR}/input/${SAMPLE}${R2_SUFFIX}" \
    --out1 "${TMPDIR}/output/${SAMPLE}${R1_TRIM_SUFFIX}" \
    --out2 "${TMPDIR}/output/${SAMPLE}${R2_TRIM_SUFFIX}" \
    --detect_adapter_for_pe \
    --correction \
    --qualified_quality_phred 20 \
    --unqualified_percent_limit 40 \
    --length_required 36 \
    --poly_g_min_len 10 \
    --poly_x_min_len 10 \
    --overrepresentation_analysis \
    --overrepresentation_sampling 20 \
    --low_complexity_filter \
    --complexity_threshold 30 \
    --thread 8 \
    --json "${TMPDIR}/output/${SAMPLE}_fastp.json" \
    --html "${TMPDIR}/output/${SAMPLE}_fastp.html" \
    --report_title "${SAMPLE} fastp QC"

echo "[3/3] fastp complete for ${SAMPLE}"
PASS_RATE=$(python3 -c "
import json
with open('${TMPDIR}/output/${SAMPLE}_fastp.json') as f:
    d = json.load(f)
t = d['summary']['before_filtering']['total_reads']
p = d['summary']['after_filtering']['total_reads']
print(f'{100*p/t:.1f}')
")
echo "  Pass rate: ${PASS_RATE}%"
python3 -c "
r = float('${PASS_RATE}')
if r < 80: print('  WARNING: >20% reads discarded — inspect fastp HTML')
else:      print('  OK')
"
ls -lh "${TMPDIR}/output/"
echo "Copying trimmed FASTQs + QC reports to NFS via trap..."

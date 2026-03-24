#!/bin/bash
#SBATCH --job-name=salmon_index
#SBATCH --output=%x_%j.log
#SBATCH --error=%x_%j.err
#SBATCH --time=01:30:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --partition=ProdQ
# =============================================================================
# Step 01b: Build Salmon decoy-aware index on SSD
# gentrome (29 GB) staged to SSD; index (~2 GB) copied to NFS
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

NFS_OUT="${SALMON_INDEX}"
setup_tmpdir "input" "output"
log_node_info
activate_conda
check_space 35   # gentrome 29 GB + index 2 GB

echo "[1/3] Staging gentrome + decoys to SSD..."
stage_in "${GENTROME}" "${TMPDIR}/input/"
stage_in "${DECOYS}"   "${TMPDIR}/input/"

echo "[2/3] Building Salmon decoy-aware index on SSD..."
salmon index \
    --transcripts "${TMPDIR}/input/$(basename ${GENTROME})" \
    --decoys       "${TMPDIR}/input/$(basename ${DECOYS})" \
    --index        "${TMPDIR}/output" \
    --gencode \
    --threads 16 \
    --keepDuplicates

echo "[3/3] Index size: $(du -sh ${TMPDIR}/output | cut -f1)"
echo "Copying index to NFS via trap..."

#!/bin/bash
#SBATCH --job-name=star_index
#SBATCH --output=%x_%j.log
#SBATCH --error=%x_%j.err
#SBATCH --time=02:00:00
#SBATCH --mem=64G
#SBATCH --cpus-per-task=16
#SBATCH --partition=ProdQ
# =============================================================================
# Step 01a: Build STAR genome index on SSD
# SSD ~2x faster than NFS for index build (random I/O intensive)
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

NFS_OUT="${STAR_INDEX}"
setup_tmpdir "input" "output"
log_node_info
activate_conda
check_space 65   # genome 28 GB + index output 30 GB

echo "[1/3] Staging genome + GTF to SSD..."
stage_in "${GENOME_FA}" "${TMPDIR}/input/"
stage_in "${GTF}"       "${TMPDIR}/input/"

echo "[2/3] Building STAR index on SSD..."
echo "  sjdbOverhang: ${SJDB_OVERHANG} (read length ${READ_LENGTH} bp)"
STAR \
    --runMode genomeGenerate \
    --runThreadN 16 \
    --genomeDir            "${TMPDIR}/output" \
    --genomeFastaFiles     "${TMPDIR}/input/$(basename ${GENOME_FA})" \
    --sjdbGTFfile          "${TMPDIR}/input/$(basename ${GTF})" \
    --sjdbOverhang         "${SJDB_OVERHANG}" \
    --genomeSAindexNbases  14

echo "[3/3] Index size: $(du -sh ${TMPDIR}/output | cut -f1)"
echo "Copying index to NFS via trap..."

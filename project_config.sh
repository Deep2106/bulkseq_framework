#!/bin/bash
# =============================================================================
# project_config.sh — Single source of truth for ALL paths and settings
# *** THIS IS THE ONLY FILE YOU NEED TO EDIT ***
#
# Sourced automatically by every script via:
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
# =============================================================================

# -----------------------------------------------------------------------------
# 1. PROJECT ROOT — your NFS permanent storage
# -----------------------------------------------------------------------------
export PROJ_DIR="/home/data/bulkRNA/May2024/Reanalysis_Feb26"                # <-- EDIT

# -----------------------------------------------------------------------------
# 2. RAW FASTQ LOCATION — where sequencing facility delivered files
# -----------------------------------------------------------------------------
export FASTQ_DIR="/home/data/bulkRNA/May2024/01.RawData"        # <-- EDIT
# e.g. export FASTQ_DIR="data/sequencing/run001/fastqs"

# -----------------------------------------------------------------------------
# 3. FASTQ NAMING — confirmed from your files:
#    Estrogenctr1_1.fq.gz  Estrogenctr1_2.fq.gz
# -----------------------------------------------------------------------------
export R1_SUFFIX="_1.fq.gz"     # ---> edit if required for another data
export R2_SUFFIX="_2.fq.gz"     # ---> edit if required for another data 
export R1_TRIM_SUFFIX="_1_trimmed.fq.gz"    # fastp output — named by us
export R2_TRIM_SUFFIX="_2_trimmed.fq.gz"

# -----------------------------------------------------------------------------
# 4. CONDA ENVIRONMENT
# -----------------------------------------------------------------------------
export CONDA_ENV="/home/data/conda_envs/isoform"
export CONDA_BASE=$(conda info --base 2>/dev/null || echo "/home/sdata/miniconda3")

# -----------------------------------------------------------------------------
# 5. SLURM
# -----------------------------------------------------------------------------
export HPC_PARTITION="ProdQ"              # <-- EDIT if different on your cluster
export SLURM_ACCOUNT="deepakbharti"                     # set if your cluster requires --account

# -----------------------------------------------------------------------------
# 6. SEQUENCING PARAMETERS
# -----------------------------------------------------------------------------
export READ_LENGTH=150
export SJDB_OVERHANG=$((READ_LENGTH - 1))  # = 149

# -----------------------------------------------------------------------------
# 7. REFERENCE PATHS  (populated by 00_download_references.sh)
# -----------------------------------------------------------------------------
export REF_DIR="${PROJ_DIR}/refs"
export GENOME_FA="${REF_DIR}/GRCh38.primary_assembly.genome.fa"
export GENOME_FA_GZ="${REF_DIR}/GRCh38.primary_assembly.genome.fa.gz"
export GTF="${REF_DIR}/gencode.v44.annotation.gtf"
export GTF_GZ="${REF_DIR}/gencode.v44.annotation.gtf.gz"
export TX_FA="${REF_DIR}/gencode.v44.transcripts.fa"
export TX_FA_GZ="${REF_DIR}/gencode.v44.transcripts.fa.gz"
export GENTROME="${REF_DIR}/gentrome.fa"
export DECOYS="${REF_DIR}/decoys.txt"
export STAR_INDEX="${REF_DIR}/star_index_GRCh38_GENCODEv44"
export SALMON_INDEX="${REF_DIR}/salmon_index_GENCODEv44_decoy"
export REF_BED12="${REF_DIR}/gencode.v44.annotation.bed12"
export REF_FLAT="${REF_DIR}/gencode.v44.refFlat.txt"
export RRNA_INTERVALS="${REF_DIR}/gencode.v44.rRNA.interval_list"

# -----------------------------------------------------------------------------
# 8. RESULT DIRECTORIES
# -----------------------------------------------------------------------------
export FASTQ_LINKS="${PROJ_DIR}/fastq/links"
export RES_DIR="${PROJ_DIR}/results"
export RES_FASTQC_RAW="${RES_DIR}/fastqc_raw"
export RES_FASTQC_TRIM="${RES_DIR}/fastqc_trim"
export RES_FASTP="${RES_DIR}/fastp"
export RES_STAR="${RES_DIR}/star"
export RES_SALMON="${RES_DIR}/salmon"
export RES_QC="${RES_DIR}/qc_post_align"
export RES_MULTIQC="${RES_DIR}/multiqc"
export RES_MATRICES="${RES_DIR}/matrices"
export LOG_DIR="${PROJ_DIR}/logs"

# -----------------------------------------------------------------------------
# 9. SAMPLE LIST
# -----------------------------------------------------------------------------
export SAMPLES="${PROJ_DIR}/scripts/samples.txt"

# -----------------------------------------------------------------------------
# Auto-create result directories (idempotent)
# -----------------------------------------------------------------------------
for _d in "${RES_FASTQC_RAW}" "${RES_FASTQC_TRIM}" "${RES_FASTP}" \
           "${RES_STAR}" "${RES_SALMON}" "${RES_QC}" \
           "${RES_MULTIQC}" "${RES_MATRICES}" "${LOG_DIR}" \
           "${FASTQ_LINKS}" "${REF_DIR}"; do
    mkdir -p "${_d}"
done

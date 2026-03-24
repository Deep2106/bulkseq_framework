#!/bin/bash
#SBATCH --job-name=download_refs
#SBATCH --output=%x_%j.log
#SBATCH --error=%x_%j.err
#SBATCH --time=05:00:00
#SBATCH --mem=16G
#SBATCH --cpus-per-task=4
#SBATCH --partition=ProdQ
# =============================================================================
# Step 00: Download GRCh38 primary assembly + GENCODE v44
# Downloads and builds gentrome on SSD, copies everything to NFS refs dir.
# =============================================================================
set -euo pipefail
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/project_config.sh"
source "/home/data/bulkRNA/May2024/Reanalysis_Feb26/scripts/hpc_functions.sh"

NFS_OUT="${REF_DIR}"
setup_tmpdir "output"
log_node_info
activate_conda
check_space 120

cd "${TMPDIR}/output"
BASE="https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_44"

echo "[1/6] Downloading GRCh38 primary assembly..."
wget -q -c "${BASE}/GRCh38.primary_assembly.genome.fa.gz" \
     -O GRCh38.primary_assembly.genome.fa.gz

echo "[2/6] Downloading GENCODE v44 GTF..."
wget -q -c "${BASE}/gencode.v44.annotation.gtf.gz" \
     -O gencode.v44.annotation.gtf.gz

echo "[3/6] Downloading GENCODE v44 transcriptome FASTA..."
wget -q -c "${BASE}/gencode.v44.transcripts.fa.gz" \
     -O gencode.v44.transcripts.fa.gz

echo "[4/6] Decompressing on SSD..."
pigz -dk -p 4 GRCh38.primary_assembly.genome.fa.gz
pigz -dk -p 4 gencode.v44.annotation.gtf.gz
pigz -dk -p 4 gencode.v44.transcripts.fa.gz

echo "[5/6] Building Salmon gentrome + decoy list..."
grep "^>" GRCh38.primary_assembly.genome.fa | cut -d" " -f1 | sed 's/>//' > decoys.txt
cat gencode.v44.transcripts.fa GRCh38.primary_assembly.genome.fa > gentrome.fa
echo "  Decoys : $(wc -l < decoys.txt)"
echo "  Gentrome: $(du -sh gentrome.fa | cut -f1)"

echo "[6/6] MD5 checksums..."
md5sum *.gz > checksums_refs.md5

echo ""
echo "SSD contents: $(du -sh ${TMPDIR}/output | cut -f1)"
echo "Copying to NFS via trap..."
# EXIT trap fires → rsync TMPDIR/output/ → NFS_OUT/

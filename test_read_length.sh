# Run on login node — checks one read from every sample
module load Miniconda3
conda activate /home/data/conda_envs/isoform

FASTQ_DIR="/home/data/bulkRNA/May2024/01.RawData"

echo "Sample                    R1_len  R2_len"
echo "-------------------------------------------"
while read SAMPLE; do
    R1="${FASTQ_DIR}/${SAMPLE}_1.fq.gz"
    R2="${FASTQ_DIR}/${SAMPLE}_2.fq.gz"
    LEN_R1=$(zcat "${R1}" | awk 'NR==2{print length($0); exit}')
    LEN_R2=$(zcat "${R2}" | awk 'NR==2{print length($0); exit}')
    printf "%-28s %s       %s\n" "${SAMPLE}" "${LEN_R1}" "${LEN_R2}"
done < /home/data/bulkRNA/May2024/Reanalysis_Feb26/samples.txt

# Bulk RNA-seq Phase 1 Pipeline
## FASTQ → Expression Matrices (Gene + Isoform)
### Hormone × IPF (Pulmonary Fibrosis) Study | RCSI HPC

---

## Table of Contents

1. [Overview](#overview)
2. [Pipeline Architecture](#pipeline-architecture)
3. [Prerequisites](#prerequisites)
4. [Directory Structure](#directory-structure)
5. [Script Reference](#script-reference)
6. [FIRST RUN : Complete Setup](#first-run)
7. [SUBSEQUENT RUNS : New Dataset](#subsequent-runs)
8. [Monitoring Jobs](#monitoring-jobs)
9. [Expected Outputs](#expected-outputs)
10. [Troubleshooting](#troubleshooting)
11. [Phase 2 Handoff](#phase-2-handoff)

---

## Overview

This pipeline processes bulk RNA-seq data from raw FASTQ files to
expression matrices suitable for downstream differential expression
and isoform analysis (Phase 2).

**Experimental design:**
- 18 samples: 6 groups × 3 replicates
- Groups: MeOHctr, Estrogenctr, Testoctr, MeOHprofib, Estrprofib, Testoprofib
- Comparisons: each treatment vs MeOH control (not treatment vs treatment)

**Key tools:**
- Quality control : FastQC, MultiQC
- Trimming        : fastp
- Alignment       : STAR (2-pass, genome-guided)
- Quantification  : Salmon (quasi-mapping, bias-corrected)
- Novel transcripts: StringTie2 + gffcompare
- Post-align QC  : RSeQC, Picard, samtools

**Reference:** GENCODE v44 | GRCh38 primary assembly

**HPC:** RCSI cluster | SLURM scheduler
**SSD scratch:** /local/scratch/${SLURM_JOB_ID} per job  (auto-wiped)

---

## Pipeline Architecture

```
FASTQ files
    │
    ├── FastQC (raw)          S2  → QC reports
    │
    ├── fastp                 S4  → trimmed FASTQs
    │       │
    │       ├── FastQC (trimmed) → QC reports
    │       │
    │       ├── STAR pass1    S6a → SJ.out.tab (junction files)
    │       │       ↓
    │       │   Junction pool S6b → pooled junctions
    │       │       ↓
    │       │   STAR pass2    S6c → BAM files  ──────────────────┐
    │       │       ↓                                            │
    │       │   Post-align QC S8  → RSeQC/Picard reports        │
    │       │       ↓                                            │
    │       │   MultiQC align S9  → Final QC report             │
    │       │                                                    │
    │       └── Salmon quant  S7  → quant.sf files              │
    │                                                            │
    └── StringTie2 pipeline (optional, after BAMs ready)        │
            ├── S9a per-sample assembly ←──────────────────────┘
            ├── S9b merge + gffcompare
            ├── S9c augmented Salmon index
            └── S9d re-quantification → quant.sf (with novel tx)

Phase 1 outputs:
    results/salmon/${SAMPLE}/quant.sf          ← primary (Phase 2 input)
    results/salmon_augmented/${SAMPLE}/quant.sf ← with novel transcripts
    results/star/${SAMPLE}_pass2/${SAMPLE}.bam  ← for rMATS (Phase 2)
    results/multiqc/multiqc_alignment.html      ← QC report
```

---

## Prerequisites

### Conda environment (built once, reused forever)
```
/home/data/conda_envs/isoform
```
Contains: FastQC, MultiQC, fastp, STAR, Salmon, samtools,
          pigz, RSeQC, Picard, StringTie2, gffcompare, gffread

### Activate environment
```bash
source activate /home/data/conda_envs/isoform
```

### FASTQ naming convention
This pipeline expects paired-end FASTQs in one of these formats:
- `{SAMPLE}_1.fq.gz` and `{SAMPLE}_2.fq.gz`  (batch 1)
- `{SAMPLE}_R1_001.fastq.gz` and `{SAMPLE}_R2_001.fastq.gz` (batch 2)

Set the correct suffix in `project_config.sh` before running.

---

## Directory Structure

```
/home/data/bulkRNA/{RUN_ID}/
├── scripts/                    ← ALL scripts live here
│   ├── project_config.sh       ← THE ONLY FILE YOU EDIT
│   ├── hpc_functions.sh        ← helper functions (do not edit)
│   ├── samples.txt             ← one sample name per line
│   ├── create_conda_env.sh     ← run once to build conda env
│   ├── 00_preflight_check.sh
│   ├── 00_download_references.sh
│   ├── 01a_star_index.sh
│   ├── 01b_salmon_index.sh
│   ├── 02_fastqc_raw.sh
│   ├── 03_multiqc.sh
│   ├── 04_fastp_trim.sh
│   ├── 06a_star_pass1.sh
│   ├── 06b_star_pool_junctions.sh
│   ├── 06c_star_pass2.sh
│   ├── 07_salmon_quant.sh
│   ├── 08_post_align_qc.sh
│   ├── 09a_stringtie2_assembly.sh
│   ├── 09b_stringtie_merge.sh
│   ├── 09c_build_augmented_index.sh
│   ├── 09d_salmon_requant_augmented.sh
│   ├── submit_all_phase1.sh
│   └── submit_stringtie2_pipeline.sh
│
├── refs/                       ← reference files (shared across runs)
│   ├── GRCh38.primary_assembly.genome.fa
│   ├── gencode.v44.annotation.gtf
│   ├── gencode.v44.transcripts.fa
│   ├── gentrome.fa
│   ├── decoys.txt
│   ├── star_index_GRCh38_GENCODEv44/
│   ├── salmon_index_GENCODEv44_decoy/
│   └── salmon_index_augmented/      ← built by StringTie2 pipeline
│
├── fastq/
│   └── links/                  ← standardised symlinks created by preflight
│
├── results/
│   ├── fastqc_raw/
│   ├── fastqc_trim/
│   ├── fastp/
│   ├── star/
│   ├── salmon/                 ← PRIMARY quantification output
│   ├── salmon_augmented/       ← quantification with novel transcripts
│   ├── stringtie/
│   ├── stringtie_merged/
│   ├── qc_post_align/
│   └── multiqc/
│
└── logs/                       ← all SLURM job logs
```

---

## Script Reference

| Script | Purpose | Runs on |
|--------|---------|---------|
| `project_config.sh` | All paths and parameters : only file you edit | sourced |
| `hpc_functions.sh` | SSD scratch, conda activation, helpers | sourced |
| `create_conda_env.sh` | Build conda environment | login node |
| `00_preflight_check.sh` | Validate FASTQs, create symlinks | login node |
| `00_download_references.sh` | Download genome + GTF + transcriptome | SLURM |
| `01a_star_index.sh` | Build STAR genome index | SLURM |
| `01b_salmon_index.sh` | Build Salmon decoy-aware index | SLURM |
| `02_fastqc_raw.sh` | FastQC on raw reads (array) | SLURM array |
| `03_multiqc.sh` | MultiQC aggregation (3 stages) | SLURM |
| `04_fastp_trim.sh` | Adapter trimming (array) | SLURM array |
| `06a_star_pass1.sh` | STAR pass 1 : junction discovery (array) | SLURM array |
| `06b_star_pool_junctions.sh` | Pool junctions from all samples | SLURM |
| `06c_star_pass2.sh` | STAR pass 2 : final BAMs (array) | SLURM array |
| `07_salmon_quant.sh` | Salmon quantification (array) | SLURM array |
| `08_post_align_qc.sh` | RSeQC + Picard + flagstat (array) | SLURM array |
| `09a_stringtie2_assembly.sh` | StringTie2 per-sample assembly | SLURM array |
| `09b_stringtie_merge.sh` | Merge GTFs + gffcompare classification | SLURM |
| `09c_build_augmented_index.sh` | Build augmented Salmon index | SLURM |
| `09d_salmon_requant_augmented.sh` | Re-quantify against augmented index | SLURM array |
| `submit_all_phase1.sh` | Master submission : submits S0–S9 | login node |
| `submit_stringtie2_pipeline.sh` | Submit StringTie2 S9a–S9d pipeline | login node |

---

## FIRST RUN

### Step 1 : Copy scripts to your project directory

```bash
# Create project directory
PROJ="/home/data/bulkRNA/YOUR_RUN_ID/Reanalysis_Feb26"
mkdir -p ${PROJ}/{scripts,logs,results,refs,fastq/links}

# Copy all scripts
cp /path/to/downloaded/scripts/* ${PROJ}/scripts/
chmod +x ${PROJ}/scripts/*.sh

# Set SCRIPTS_DIR in your environment (add to ~/.bashrc for persistence)
export SCRIPTS_DIR="${PROJ}/scripts"
echo "export SCRIPTS_DIR=\"${PROJ}/scripts\"" >> ~/.bashrc
```

---

### Step 2 : Edit project_config.sh (THE ONLY FILE YOU EDIT)

```bash
nano ${PROJ}/scripts/project_config.sh
```

Change these lines:

```bash
# Line 1: your project directory
export PROJ_DIR="/home/data/bulkRNA/YOUR_RUN_ID/Reanalysis_Feb26"

# Line 2: where your raw FASTQs are located
export FASTQ_DIR="/path/to/your/raw/fastq/files"

# Line 3: FASTQ naming suffix (check your actual files)
export R1_SUFFIX="_1.fq.gz"         # e.g. MeOHctr1_1.fq.gz
export R2_SUFFIX="_2.fq.gz"         # e.g. MeOHctr1_2.fq.gz

# Line 4: SLURM partition name
export HPC_PARTITION="ProdQ"

# Line 5: Read length (check with command below)
export READ_LENGTH=150
```

**Check your read length before setting:**
```bash
zcat /path/to/fastq/SAMPLE_1.fq.gz | awk 'NR==2{print length($0); exit}'
```

---

### Step 3 : Update samples.txt

```bash
nano ${PROJ}/scripts/samples.txt
```

One sample name per line, matching the prefix before the suffix.
For files `MeOHctr1_1.fq.gz`, the sample name is `MeOHctr1`:

```
Estrogenctr1
Estrogenctr2
Estrogenctr3
Estrprofib1
Estrprofib2
Estrprofib3
MeOHctr1
MeOHctr2
MeOHctr3
MeOHprofib1
MeOHprofib2
MeOHprofib3
Testoctr1
Testoctr2
Testoctr3
Testoprofib1
Testoprofib2
Testoprofib3
```

---

### Step 4 : Build conda environment (once, ~30-60 min)

```bash
# Start a persistent session (survives disconnect)
screen -S conda_build

cd ${PROJ}/scripts
bash create_conda_env.sh

# Detach: Ctrl+A then D
# Reattach later: screen -r conda_build
```

If any R packages fail in pass 4:
```bash
source activate /home/data/conda_envs/isoform
Rscript install_missing_r_packages.R
```

---

### Step 5 : Validate FASTQs

```bash
cd ${PROJ}/scripts
bash 00_preflight_check.sh
```

Expected output:
```
[OK] MeOHctr1   R1: MeOHctr1_1.fq.gz [6.8G]   R2: MeOHctr1_2.fq.gz [6.9G]
[OK] MeOHctr2   ...
...
STATUS: ALL CHECKS PASSED
NEXT: bash submit_all_phase1.sh
```

Fix if failed: check `FASTQ_DIR` and `R1_SUFFIX` in `project_config.sh`.

---

### Step 6 : Download references (~30-90 min)

```bash
sbatch 00_download_references.sh

# Monitor
tail -f ../logs/download_refs_*.log
```

Expected files in `refs/` when complete:
```
GRCh38.primary_assembly.genome.fa    ~1.6 GB
gencode.v44.annotation.gtf           ~160 MB
gencode.v44.transcripts.fa           ~230 MB
gentrome.fa                          ~1.8 GB
decoys.txt                           ~24 KB
```

---

### Step 7 : Submit the full pipeline (one command)

```bash
bash submit_all_phase1.sh
```

This submits all jobs (S0–S9) with automatic dependencies.
Total estimated time: **6–8 hours**.

Monitor:
```bash
watch -n 30 'squeue -u $USER'
sacct -u $USER --format=JobID,JobName,State,Elapsed,NodeList
```

---

### Step 8 : Review QC checkpoints

**Checkpoint 1** : after MultiQC raw (job S3 complete, ~2h):
```bash
# Open in browser
results/multiqc/multiqc_raw.html
```
Check: Q30 >80%, GC content unimodal, no major outliers.

**Checkpoint 2** : after MultiQC alignment (job S9 complete, ~6-7h):
```bash
results/multiqc/multiqc_alignment.html
```
Check: mapping rate >80%, strandedness consistent across all samples,
junction saturation >80%, exonic reads >60%.

**Critical:** Confirm strandedness from `infer_experiment.py` output.
All 18 samples must show the same directionality. Wrong strandedness
in DESeq2 produces completely incorrect results.

---

### Step 9 : Novel transcript discovery with StringTie2 (optional)

Run after Phase 1 BAMs are complete. Adds ~3-4 hours.

```bash
# Install StringTie2 if not already in env
conda install -y --prefix /home/data/conda_envs/isoform \
    stringtie gffcompare gffread

# Submit pipeline
bash submit_stringtie2_pipeline.sh
```

Outputs:
- `results/stringtie_merged/novel_transcripts.gtf` : novel transcript annotations
- `results/stringtie_merged/gffcompare/gffcmp.stats` : classification summary
- `results/salmon_augmented/${SAMPLE}/quant.sf` : expression with novel transcripts

---

## SUBSEQUENT RUNS : New Dataset

For a new batch of samples using the SAME reference genome and annotation,
you can reuse all reference files and indexes. Only 4 things change.

### Step 1 : Create new project directory and copy scripts

```bash
NEW_PROJ="/home/data/<NEW_PROJECT>/<NEW_RUN_ID>/<analysis>"
mkdir -p ${NEW_PROJ}/{scripts,logs,results,fastq/links}

# Copy scripts from previous run
cp /path/to/previous/run/scripts/* ${NEW_PROJ}/scripts/
chmod +x ${NEW_PROJ}/scripts/*.sh
```

### Step 2 : Update SCRIPTS_DIR

```bash
export SCRIPTS_DIR="${NEW_PROJ}/scripts"
```

### Step 3 : Edit project_config.sh (4 lines only)

```bash
nano ${NEW_PROJ}/scripts/project_config.sh
```

```bash
# Change 1: new project directory
export PROJ_DIR="/path/do/directory"

# Change 2: new FASTQ location
export FASTQ_DIR="/path/to/new/batch/fastqs"

# Change 3: new FASTQ suffix if different naming convention
export R1_SUFFIX="_R1_001.fastq.gz"   # check your actual filenames
export R2_SUFFIX="_R2_001.fastq.gz"

# Change 4: POINT TO EXISTING REFS : do not change REF_DIR to new path
export REF_DIR="/path/to/refs"
# This reuses: STAR index, Salmon index, genome, GTF : no rebuild needed
```

### Step 4 : Update samples.txt

```bash
# Overwrite with new sample names
cat > ${NEW_PROJ}/scripts/samples.txt << 'EOF'
NewSample1
NewSample2
...
EOF
```

Auto-generate from FASTQ directory:
```bash
ls ${FASTQ_DIR}/*${R1_SUFFIX} \
    | sed 's|.*/||; s/${R1_SUFFIX}//' \
    | sort > ${NEW_PROJ}/scripts/samples.txt

echo "$(wc -l < ${NEW_PROJ}/scripts/samples.txt) samples found"
```

### Step 5 : Update array sizes to match new sample count

```bash
cd ${NEW_PROJ}/scripts
N=$(wc -l < samples.txt)
echo "Sample count: ${N}"

sed -i "s/--array=1-[0-9]*%4/--array=1-${N}%4/" \
    06a_star_pass1.sh 06c_star_pass2.sh

sed -i "s/--array=1-[0-9]*%8/--array=1-${N}%8/" \
    07_salmon_quant.sh 08_post_align_qc.sh \
    09a_stringtie2_assembly.sh 09d_salmon_requant_augmented.sh

sed -i "s/--array=1-[0-9]*%18/--array=1-${N}%18/" \
    02_fastqc_raw.sh 04_fastp_trim.sh
```

### Step 6 : Edit submit_all_phase1.sh to skip existing steps

Open `submit_all_phase1.sh` and comment out steps already completed:

```bash
nano ${NEW_PROJ}/scripts/submit_all_phase1.sh
```

Comment out S0 (refs), S1a (STAR index), S1b (Salmon index):
```bash
# S0-S1b SKIP : refs and indexes already exist from previous run
# J_REFS=$(sub ...)       # commented out : refs already downloaded
# J_STAR_IDX=$(sub ...)   # commented out : STAR index already built
# J_SAL_IDX=$(sub ...)    # commented out : Salmon index already built
```

Also remove `afterok:${J_REFS}` dependencies from S6a and S7 since
`J_REFS` is no longer defined.

### Step 7 : Validate and submit

```bash
cd ${NEW_PROJ}/scripts

# Validate FASTQs
bash 00_preflight_check.sh

# Submit (skips ref download and index builds)
bash submit_all_phase1.sh
```

---

## Monitoring Jobs

```bash
# Live queue view (refreshes every 30s)
watch -n 30 'squeue -u $USER'

# Full job history with states
sacct -u $USER --format=JobID,JobName,State,ExitCode,Elapsed,NodeList

# Check specific job
sacct -j JOBID --format=JobID,JobName,State,MaxRSS,Elapsed

# Follow a log file live
tail -f logs/JOBNAME_JOBID.log

# Check for failed jobs
sacct -u $USER --format=JobID,JobName,State | grep FAILED
```

### SLURM job states explained

| State | Meaning | Action |
|-------|---------|--------|
| `PD (Resources)` | Waiting for free node | Normal : wait |
| `PD (Dependency)` | Waiting for upstream job | Normal : correct behaviour |
| `PD (DependencyNeverSatisfied)` | Upstream job failed | Cancel + fix + resubmit |
| `R` | Running | Normal |
| `COMPLETED` | Finished successfully | Check outputs |
| `FAILED` | Error : check .err log | Fix + resubmit from failed step |

---

## Expected Outputs

After Phase 1 completes successfully:

```
results/
├── multiqc/
│   ├── multiqc_raw.html           ← Supplementary Figure: raw QC
│   ├── multiqc_trimmed.html       ← Supplementary Figure: post-trim QC
│   └── multiqc_alignment.html     ← Supplementary Figure: alignment QC
│
├── salmon/
│   └── {SAMPLE}/
│       ├── quant.sf               ← MAIN OUTPUT: transcript counts + TPM
│       ├── quant.genes.sf         ← gene-level counts + TPM (if --geneMap used)
│       └── aux_info/bootstrap/    ← 30 bootstrap replicates for DRIMSeq
│
├── salmon_augmented/              ← if StringTie2 pipeline was run
│   └── {SAMPLE}/
│       └── quant.sf               ← counts including novel transcripts
│
└── star/
    └── {SAMPLE}_pass2/
        ├── {SAMPLE}.bam           ← sorted, indexed alignment
        └── {SAMPLE}.bam.bai       ← BAM index
```

### Sanity check all outputs

```bash
# Check all Salmon quant.sf files exist
while read S; do
    F="results/salmon/${S}/quant.sf"
    [[ -f "$F" ]] && echo "OK  ${S}" || echo "MISSING  ${S}"
done < scripts/samples.txt

# Check all BAM files exist
while read S; do
    F="results/star/${S}_pass2/${S}.bam"
    [[ -f "$F" ]] && echo "OK  ${S}" || echo "MISSING  ${S}"
done < scripts/samples.txt

# Quick mapping rate summary
for S in $(cat scripts/samples.txt); do
    RATE=$(python3 -c "
import json
with open('results/salmon/${S}/aux_info/meta_info.json') as f:
    d=json.load(f)
print(d.get('percent_mapped','N/A'))
" 2>/dev/null)
    echo "${S}: ${RATE}%"
done
```

---

## Troubleshooting

### Job fails with "No such file or directory" on source line
**Cause:** `SCRIPTS_DIR` not set in SLURM job environment.
**Fix:**
```bash
export SCRIPTS_DIR="/path/to/your/scripts"
# Add to ~/.bashrc for persistence
```
Ensure `submit_all_phase1.sh` uses `--export=ALL` in the `sub()` function.

### wget fails with "unrecognized option --show-progress"
**Cause:** Older wget version on compute node.
**Fix:** Remove `--show-progress` from `00_download_references.sh`.

### "source activate: No such file or directory"
**Cause:** HPC uses `conda activate` not `source activate`.
**Fix:**
```bash
sed -i 's/source activate/conda activate/' scripts/hpc_functions.sh
```

### TMPDIR permission denied
**Cause:** Running script directly on login node with `bash`, not via `sbatch`.
**Fix:** Always submit compute jobs with `sbatch`. The SSD `/local/scratch`
only exists on compute nodes allocated by SLURM.

### DependencyNeverSatisfied
**Cause:** An upstream job in the dependency chain failed.
**Fix:**
```bash
# Find which job failed
sacct -u $USER --format=JobID,JobName,State,ExitCode | grep FAILED
# Check its error log
cat logs/JOBNAME_JOBID.err
# Cancel stuck downstream jobs
scancel JOBID
# Fix the error, resubmit from failed step only
```

### Low mapping rate (<70%)
**Causes to check in order:**
1. Wrong strandedness : run `infer_experiment.py` manually on one BAM
2. Wrong genome/annotation version mismatch
3. rRNA contamination : check `read_distribution.py` output
4. Wrong species contamination
5. Very short reads after trimming : check fastp pass rate

### Salmon mapping rate much lower than STAR
**Normal difference:** STAR aligns to genome (includes introns),
Salmon maps to transcriptome only. Typical rates:
- STAR: 90-95%
- Salmon: 75-85%
A >20% gap between them warrants investigation.

---

## Phase 2 Handoff

Phase 1 is complete when `multiqc_alignment.html` is generated.
The following files are inputs to Phase 2 R analysis:

| File | Phase 2 use |
|------|------------|
| `results/salmon/*/quant.sf` | tximeta → DESeq2 (gene-level DEG) |
| `results/salmon/*/quant.sf` | tximeta → IsoformSwitchAnalyzeR (DTU) |
| `results/salmon/*/aux_info/bootstrap/` | DRIMSeq uncertainty-aware DTU |
| `results/salmon_augmented/*/quant.sf` | Novel transcript analysis |
| `results/star/*_pass2/*.bam` | rMATS splicing event analysis |
| `results/multiqc/multiqc_alignment.html` | Supplementary QC figure |
| `results/stringtie_merged/novel_transcripts.gtf` | Novel transcript annotation |

**Transfer to R analysis machine:**
```bash
# Copy Salmon quant directories (lightweight : quant.sf files are small)
rsync -av results/salmon/ /path/to/r_analysis/salmon_batch1/
rsync -av results/salmon_augmented/ /path/to/r_analysis/salmon_augmented_batch1/

# BAMs stay on HPC : rMATS runs on the cluster in Phase 2
```

---

## Notes

- The `--geneMap` flag in `07_salmon_quant.sh` generates `quant.genes.sf`
  (gene-level) alongside `quant.sf` (transcript-level) in one Salmon run.
  If missing, tximeta's `summarizeToGene()` in Phase 2 collapses transcripts
  to gene level : both approaches give equivalent results.

- All compute jobs use the SSD scratch pattern:
  NFS → SSD (stage in) → compute → NFS (copy back via trap).
  The trap ensures results are copied even if the job hits wall-time limit.

- Pass 1 BAMs are intentionally discarded (not copied to NFS).
  Only `SJ.out.tab` junction files are kept. This saves ~90 GB.

- The augmented Salmon index (`salmon_index_augmented/`) is built once
  and shared across subsequent runs pointing to the same `REF_DIR`.

---

*Pipeline designed for RCSI HPC | GENCODE v44 | GRCh38 primary assembly*
*Contact: deepakbharti@rcsi.com | Bulk_RNASeq project*

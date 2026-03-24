#!/usr/bin/env Rscript
# =============================================================================
# install_missing_r_packages.R
# Fallback installer — run INSIDE the conda env if any R packages
# failed during create_conda_env.sh Pass 4.
#
# Usage (after activating the conda env):
#   source activate /home/sdata/precise_pf/conda_envs/isoform
#   Rscript install_missing_r_packages.R
# =============================================================================

options(repos = c(CRAN = "https://cran.r-project.org"))

if (!requireNamespace("BiocManager", quietly=TRUE))
    install.packages("BiocManager")

BiocManager::install(version="3.20", ask=FALSE, update=FALSE)

# ── Packages that MUST be installed via BiocManager (not on conda) ────────────
bioc_via_r <- c(
    "IsoformSwitchAnalyzeR",   # not reliably on bioconda
    "dorothea",                 # TF regulon database
    "viper",                    # TF activity inference
    "WGCNA",                    # weighted gene co-expression
    "ReactomePA",               # Reactome pathway analysis
    "decoupleR"                 # modern TF/pathway activity framework
)

# ── Additional Bioconductor packages (fallback if conda install failed) ───────
bioc_fallback <- c(
    "tximeta","tximport","DESeq2","edgeR","limma",
    "SummarizedExperiment","BiocParallel","GenomicFeatures",
    "DRIMSeq","stageR","DEXSeq",
    "ComplexHeatmap","EnhancedVolcano",
    "clusterProfiler","fgsea","GSVA",
    "org.Hs.eg.db","reactome.db"
)

# ── CRAN packages (fallback if conda install failed) ─────────────────────────
# NOTE: msigdbr is CRAN (not Bioconductor) — conda name is r-msigdbr
cran_fallback <- c(
    "msigdbr",    # MSigDB gene sets — CRAN package
    "ggplot2","ggrepel","dplyr","tidyr","tibble",
    "purrr","stringr","readr","data.table",
    "pheatmap","RColorBrewer","cowplot","patchwork",
    "UpSetR","ashr","scales"
)

cat("============================================================\n")
cat("Installing R packages not available via conda\n")
cat("============================================================\n\n")

cat("[1/3] BiocManager-only packages...\n")
BiocManager::install(bioc_via_r, ask=FALSE, update=FALSE, Ncpus=4)

cat("\n[2/3] Bioconductor fallbacks (if any failed via conda)...\n")
BiocManager::install(bioc_fallback, ask=FALSE, update=FALSE, Ncpus=4)

cat("\n[3/3] CRAN fallbacks...\n")
install.packages(cran_fallback, Ncpus=4, quiet=TRUE)

# ── Final verification ────────────────────────────────────────────────────────
cat("\n============================================================\n")
cat("Verification\n")
cat("============================================================\n")

all_pkgs <- c(
    bioc_via_r, bioc_fallback, cran_fallback,
    "ggplot2","dplyr","ashr"   # ensure core always checked
)
all_pkgs <- unique(all_pkgs)

ok <- sapply(all_pkgs, requireNamespace, quietly=TRUE)
for (p in names(ok))
    cat(sprintf("  %s  %s\n", ifelse(ok[p], "[OK]  ", "[FAIL]"), p))

n_ok   <- sum(ok)
n_fail <- sum(!ok)
cat(sprintf("\n%d / %d installed successfully\n", n_ok, length(ok)))
if (n_fail > 0) {
    cat(sprintf("Still failing (%d): %s\n",
        n_fail, paste(names(ok)[!ok], collapse=", ")))
} else {
    cat("All packages verified.\n")
}

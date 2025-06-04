#!/bin/bash

set -euo pipefail

show_help() {
cat <<EOF
Usage: $(basename "$0") [OPTIONS] <FASTQ> [FASTQ2] <GENOME_DIR>

A minimal RRBS processing pipeline using trim_galore, bismark, and MultiQC.

Positional Arguments:
  <FASTQ>           Input FASTQ file (R1 for paired-end or single-end)
  <FASTQ2>          Input R2 FASTQ file (optional; required for paired-end mode)
  <GENOME_DIR>      Path to the bismark (Bowtie2) genome index folder

Options:
  --dry-run         Show commands without executing them
  -h, --help        Show this help message and exit

Examples:
  Paired-end:
    $(basename "$0") sample_R1.fastq.gz sample_R2.fastq.gz /path/to/bowtie2_index

  Single-end:
    $(basename "$0") sample.fastq.gz /path/to/bowtie2_index

EOF
}

# ─────────────────
# Parse arguments
# ─────────────────
DRY_RUN=false

# Show help message if asked
for arg in "$@"; do
    if [[ "$arg" == "-h" || "$arg" == "--help" ]]; then
        show_help
        exit 0
    fi
done

NEW_ARGS=()
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
    else
        NEW_ARGS+=("$arg")
    fi
done
set -- "${NEW_ARGS[@]}"

# Remaining args
if [[ "$#" -eq 3 ]]; then
    MODE="paired"
    R1=$1
    R2=$2
    GENOME_DIR=$3
    SAMPLE=$(basename "$R1" | sed -E 's/\.R1\.f(ast)?q(\.gz)?$//')
elif [[ "$#" -eq 2 ]]; then
    MODE="single"
    FASTQ=$1
    GENOME_DIR=$2
    SAMPLE=$(basename "$FASTQ" | sed -E 's/\.R1\.f(ast)?q(\.gz)?$//')
else
    echo "Illegal Usage:"
    echo "Paired-end: $0 sample_R1.fastq.gz sample_R2.fastq.gz /path/to/genome [--dry-run]"
    echo "Single-end: $0 sample.fastq.gz /path/to/genome [--dry-run]"
    exit 1
fi

# ─────────────────
# Setup
# ─────────────────
LOGFILE="${SAMPLE}.log"

timestamp=$(date "+%Y-%m-%d %H:%M:%S")
echo "RRBS pipeline started at $timestamp" > "$LOGFILE"
echo "Sample: $SAMPLE | Mode: ${MODE}-end | Dry-run: $DRY_RUN" >> "$LOGFILE"
echo "==========================================" >> "$LOGFILE"

log_step() {
    echo -e "\n----------------------------------------------------------------------------------------------------" >> "$LOGFILE"
    echo "                                       STAGE ${1}: $2" >> "$LOGFILE"
    echo "----------------------------------------------------------------------------------------------------" >> "$LOGFILE"
}

run_cmd() {
    echo ">> $*" >> "$LOGFILE"
    if ! $DRY_RUN; then
        {
            echo -e "----- START COMMAND -----"
            echo "Command: $*"
            eval "$@"
            echo -e "----- END COMMAND -----\n"
        } >> "$LOGFILE" 2>&1
    fi
}

# ────────────────────────────────────────────
# Step 1: FastQC
# ────────────────────────────────────────────
log_step "1" "FastQC"
if [[ "$MODE" == "paired" ]]; then
    run_cmd fastqc "$R1" "$R2"
else
    run_cmd fastqc "$FASTQ"
fi

# ────────────────────────────────────────────
# Step 2: Trim Galore
# ────────────────────────────────────────────
log_step "2" "Trim Galore"
if [[ "$MODE" == "paired" ]]; then
    run_cmd trim_galore --paired --rrbs "$R1" "$R2"
    TRIMMED_1="${SAMPLE}.R1_val_1.fq.gz"
    TRIMMED_2="${SAMPLE}.R2_val_2.fq.gz"
else
    run_cmd trim_galore --rrbs "$FASTQ"
    TRIMMED="${SAMPLE}.R1_trimmed.fq.gz"
fi

# ────────────────────────────────────────────
# Step 3: Bismark Alignment
# ────────────────────────────────────────────
log_step "3" "Bismark Alignment"
if [[ "$MODE" == "paired" ]]; then
    run_cmd bismark --genome "$GENOME_DIR" -1 "$TRIMMED_1" -2 "$TRIMMED_2" -o .
    BAM="${SAMPLE}.R1_val_1_bismark_bt2_pe.bam"
else
    run_cmd bismark --genome "$GENOME_DIR" "$TRIMMED" -o .
    BAM="${SAMPLE}.R1_trimmed_bismark_bt2.bam"
fi

# ────────────────────────────────────────────
# Step 4: Deduplication
# ────────────────────────────────────────────
log_step "4" "Deduplicate BAM"
if [[ "$MODE" == "paired" ]]; then
    run_cmd deduplicate_bismark --paired "$BAM"
    DEDUP_BAM="${SAMPLE}.R1_val_1_bismark_bt2_pe.deduplicated.bam"
else
    run_cmd deduplicate_bismark "$BAM"
    DEDUP_BAM="${SAMPLE}.R1_trimmed_bismark_bt2.deduplicated.bam"
fi

# ────────────────────────────────────────────
# Step 5: Methylation Extraction
# ────────────────────────────────────────────
log_step "5" "Methylation Extraction"
METH_CMD="bismark_methylation_extractor"
[[ "$MODE" == "paired" ]] && METH_CMD+=" --paired-end"
METH_CMD+=" --bedGraph --gzip --no_overlap --output . $DEDUP_BAM"
run_cmd $METH_CMD

# ────────────────────────────────────────────
# Step 6: MultiQC
# ────────────────────────────────────────────
log_step "6" "MultiQC"
run_cmd multiqc . --outdir .


# ────────────────────────────────────────────
# Cleanup: Remove intermediate files
# ────────────────────────────────────────────
log_step "7" "Cleanup Intermediate Files"
run_cmd rm -f *deduplicated.txt.gz *bt2.bam *M-bias.txt *val_*.fq.gz

# Recreate key outputs
run_cmd mv "$DEDUP_BAM" "${SAMPLE}.deduplicated.bam"
DEDUP_BAM="${SAMPLE}.deduplicated.bam"

# ────────────────────────────────────────────
# Summary
# ────────────────────────────────────────────
timestamp_end=$(date "+%Y-%m-%d %H:%M:%S")

{
echo -e "\nPipeline completed at $timestamp_end"
echo -e "\n========== SUMMARY =========="
echo "Sample name     : $SAMPLE"
echo "Mode            : $MODE"
echo "Genome index    : $GENOME_DIR"
echo "Final BAM       : $DEDUP_BAM"
echo "Methylation     : ${DEDUP_BAM%.bam}_Methylation_report.txt (or .gz/bedGraph)"
echo "QC Report       : multiqc_report.html"
echo "Log saved to    : $LOGFILE"
} >> "$LOGFILE"




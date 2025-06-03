#!/bin/bash

# ===========================================
# RRBS Pipeline (With --dry-run Support)
# ===========================================

set -euo pipefail

# ────────────────────────────────────────────
# Parse arguments
# ────────────────────────────────────────────
DRY_RUN=false

# Extract --dry-run if present
for arg in "$@"; do
    if [[ "$arg" == "--dry-run" ]]; then
        DRY_RUN=true
        set -- "${@/--dry-run/}"  # Remove --dry-run from args
        break
    fi
done

# Remaining args
if [[ "$#" -eq 3 ]]; then
    MODE="paired"
    R1=$1
    R2=$2
    GENOME_DIR=$3
    SAMPLE=$(basename "$R1" | sed -E 's/_R1\.f(ast)?q(\.gz)?$//')
elif [[ "$#" -eq 2 ]]; then
    MODE="single"
    FASTQ=$1
    GENOME_DIR=$2
    SAMPLE=$(basename "$FASTQ" | sed -E 's/\.f(ast)?q(\.gz)?$//')
else
    echo "❌ Usage:"
    echo "  Paired-end: $0 sample_R1.fastq.gz sample_R2.fastq.gz /path/to/genome [--dry-run]"
    echo "  Single-end: $0 sample.fastq.gz /path/to/genome [--dry-run]"
    exit 1
fi

# ────────────────────────────────────────────
# Setup
# ────────────────────────────────────────────
OUTDIR="${SAMPLE}_rrbs_output"
LOGFILE="${OUTDIR}/${SAMPLE}.log"

mkdir -p "$OUTDIR"
cd "$OUTDIR"

timestamp=$(date "+%Y-%m-%d %H:%M:%S")
echo "🚀 RRBS pipeline started at $timestamp" > "$LOGFILE"
echo "Sample: $SAMPLE | Mode: $MODE | Dry-run: $DRY_RUN" >> "$LOGFILE"
echo "==========================================" >> "$LOGFILE"

log_step() {
    echo -e "\n\n====== STEP $1: $2 ======\n" >> "$LOGFILE"
}

run_cmd() {
    echo ">> $*" >> "$LOGFILE"
    if ! $DRY_RUN; then
        eval "$@"
    fi
}

# ────────────────────────────────────────────
# Step 1: FastQC
# ────────────────────────────────────────────
log_step "1" "FastQC"
if [[ "$MODE" == "paired" ]]; then
    run_cmd fastqc ../"$R1" ../"$R2"
else
    run_cmd fastqc ../"$FASTQ"
fi

# ────────────────────────────────────────────
# Step 2: Trim Galore
# ────────────────────────────────────────────
log_step "2" "Trim Galore"
if [[ "$MODE" == "paired" ]]; then
    run_cmd trim_galore --paired --rrbs ../"$R1" ../"$R2"
    TRIMMED_1="${SAMPLE}_R1_val_1.fq.gz"
    TRIMMED_2="${SAMPLE}_R2_val_2.fq.gz"
else
    run_cmd trim_galore --rrbs ../"$FASTQ"
    TRIMMED="${SAMPLE}_trimmed.fq.gz"
fi

# ────────────────────────────────────────────
# Step 3: Bismark Alignment
# ────────────────────────────────────────────
log_step "3" "Bismark Alignment"
if [[ "$MODE" == "paired" ]]; then
    run_cmd bismark --genome "$GENOME_DIR" -1 "$TRIMMED_1" -2 "$TRIMMED_2" -o .
    BAM="${SAMPLE}_R1_val_1_bismark_bt2_pe.bam"
else
    run_cmd bismark --genome "$GENOME_DIR" "$TRIMMED" -o .
    BAM="${SAMPLE}_trimmed_bismark_bt2.bam"
fi

# ────────────────────────────────────────────
# Step 4: Deduplication
# ────────────────────────────────────────────
log_step "4" "Deduplicate BAM"
if [[ "$MODE" == "paired" ]]; then
    run_cmd deduplicate_bismark --paired "$BAM"
    DEDUP_BAM="${SAMPLE}_R1_val_1_bismark_bt2_pe.deduplicated.bam"
else
    run_cmd deduplicate_bismark "$BAM"
    DEDUP_BAM="${SAMPLE}_trimmed_bismark_bt2.deduplicated.bam"
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
# Summary
# ────────────────────────────────────────────
timestamp_end=$(date "+%Y-%m-%d %H:%M:%S")
echo -e "\n✅ Pipeline completed at $timestamp_end" >> "$LOGFILE"

echo -e "\n========== SUMMARY ==========" >> "$LOGFILE"
echo "Sample name     : $SAMPLE" >> "$LOGFILE"
echo "Mode            : $MODE" >> "$LOGFILE"
echo "Genome index    : $GENOME_DIR" >> "$LOGFILE"
echo "Final BAM       : $DEDUP_BAM" >> "$LOGFILE"
echo "Methylation     : ${DEDUP_BAM%.bam}_Methylation_report.txt (or .gz/bedGraph)" >> "$LOGFILE"
echo "QC Report       : multiqc_report.html" >> "$LOGFILE"
echo "Log saved to    : $LOGFILE" >> "$LOGFILE"
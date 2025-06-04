# RRBS_pipeline

A lightweight and user-friendly Bash pipeline for Reduced Representation Bisulfite Sequencing (RRBS) data analysis. It performs quality control, adapter trimming, alignment, deduplication, methylation extraction, and summary reporting — all in a single script with optional dry-run mode.

## Features
- Supports both single-end and paired-end FASTQ files
- Automatic detection of mode based on arguments
- Integrates industry-standard tools: trim_galore, bismark, and multiqc
- Creates a detailed log file ({sample}.log) with timestamps and command summaries
- --dry-run option to preview commands without execution
- Clean and minimal dependencies — no workflow engine needed

## Requirements
	Trim Galore
	Bismark
	MultiQC
	Bowtie2

## Usage
```
chmod +x rrbs_pipeline.sh
./rrbs_pipeline.sh sample_R1.fastq.gz sample_R2.fastq.gz /path/to/bowtie2_index
```

For single-end:
```
./rrbs_pipeline.sh sample.fastq.gz /path/to/bowtie2_index
```

Dry-run mode (preview commands only):
```
./rrbs_pipeline.sh sample.fastq.gz /path/to/bowtie2_index --dry-run
```
## Output
- \*.log — per-sample execution log with steps and timestamps
- \*_dedup.bam — deduplicated aligned BAM file
- \*_Methylation_report.txt, \*.bedGraph.gz — methylation calls
- multiqc_report.html — combined quality control summary


## Logging

Each major processing step is logged to a file with command and execution details (sampleX.log).

A test example:
```text
RRBS pipeline started at 2025-06-04 07:46:55
Sample: SRR17518177 | Mode: paired-end | Dry-run: true
==========================================

----------------------------------------------------------------------------------------------------
                                       STAGE 1: FastQC
----------------------------------------------------------------------------------------------------
>> fastqc SRR17518177.R1.fq.gz SRR17518177.R2.fq.gz

----------------------------------------------------------------------------------------------------
                                       STAGE 2: Trim Galore
----------------------------------------------------------------------------------------------------
>> trim_galore --paired --rrbs SRR17518177.R1.fq.gz SRR17518177.R2.fq.gz

----------------------------------------------------------------------------------------------------
                                       STAGE 3: Bismark Alignment
----------------------------------------------------------------------------------------------------
>> bismark --genome /Users/dale/genomes/hg38/bowtie2_index -1 SRR17518177.R1_val_1.fq.gz -2 SRR17518177.R2_val_2.fq.gz -o .

----------------------------------------------------------------------------------------------------
                                       STAGE 4: Deduplicate BAM
----------------------------------------------------------------------------------------------------
>> deduplicate_bismark --paired SRR17518177.R1_val_1_bismark_bt2_pe.bam

----------------------------------------------------------------------------------------------------
                                       STAGE 5: Methylation Extraction
----------------------------------------------------------------------------------------------------
>> bismark_methylation_extractor --paired-end --bedGraph --gzip --no_overlap --output . SRR17518177.R1_val_1_bismark_bt2_pe.deduplicated.bam

----------------------------------------------------------------------------------------------------
                                       STAGE 6: MultiQC
----------------------------------------------------------------------------------------------------
>> multiqc . --outdir .

----------------------------------------------------------------------------------------------------
                                       STAGE 7: Cleanup Intermediate Files
----------------------------------------------------------------------------------------------------
>> rm -f *deduplicated.txt.gz *bt2.bam *M-bias.txt *val_*.fq.gz
>> mv SRR17518177.R1_val_1_bismark_bt2_pe.deduplicated.bam SRR17518177.deduplicated.bam

Pipeline completed at 2025-06-04 07:46:55

========== SUMMARY ==========
Sample name     : SRR17518177
Mode            : paired
Genome index    : /Users/dale/genomes/hg38/bowtie2_index
Final BAM       : SRR17518177.deduplicated.bam
Methylation     : SRR17518177.deduplicated_Methylation_report.txt (or .gz/bedGraph)
QC Report       : multiqc_report.html
Log saved to    : SRR17518177.log
```

## License

MIT License


Please let me know if you have any questions or suggestions about my pipeline script!

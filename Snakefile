#!/usr/bin/env python3.5
import os
# import IPython; 

# set config file
configfile: "./config.json"

#------------------------------------------------------
# --- Dependencies:

BWA        = config["progs"]["BWA"]
MM2        = config["progs"]["minimap"]
SAMTOOLS   = config["progs"]["SAMTOOLS"]
nanopolish = config["progs"]["nanopolish"]

RefTranscriptome = config["ref"]["Transcriptome"]
GENOME_VERSION   = config["ref"]["Genome_version"]

#------------------------------------------------------
# --- define output directories

DIR_ALIGNED_MINIMAP    = config["PATHOUT"]+"01_MM_aligned/"
DIR_FILTERED_MINIMAP   = config["PATHOUT"]+"02_MM_filtered/"
DIR_SORTED_MINIMAPPED  = config["PATHOUT"]+"03_MM_sortedbam/"
DIR_SORTED_ALIGNED_BWA = config["PATHOUT"]+"04_BWA_sortedbam/"
DIR_EVENTALIGN         = config["PATHOUT"]+"05_BWA_eventalign/"
DIR_GR                 = config["PATHOUT"]+"06_GRobjects"
DIR_REPORT             = config["PATHOUT"]+"07_report/"


#------------------------------------------------------
# --- enumerate "chunk" files list  
# blocks that the minion divides the ouput into 
# (usually 4000 reads per chunk) 
# This is done for both event alignments and bam files:
Sample_indices_int     = range(config["MAXSAMPLEi"] +1) 
Sample_indices_str     = [ str(item) for item in Sample_indices_int  ]

Ealign_FILES_list = list( chain( *[ expand ( os.path.join( DIR_EVENTALIGN, 'Ealign_'+chunk+'.cvs' ), ) for chunk in Sample_indices_str ] ) )

Ealign_FILES_quoted   = ",".join( Ealign_FILES_list )  
 
bami_FILES_list = list( chain( *[ expand ( os.path.join( DIR_SORTED_MINIMAPPED, "read_chunks", 'run_'+config["RUN_ID"]+ '_'+chunk+'.sorted.bam' ), ) for chunk in Sample_indices_str ] ) )

#------------------------------------------------------
# import rule definitions for the post-base-calling rules

include   : os.path.join( config["scripts"]["script_folder"], config["scripts"]["pyfunc_defs"] )
include   : os.path.join( config["scripts"]["script_folder"], config["scripts"]["rules_basecalled"] )

#------------------------------------------------------
# Define output files:

OUTPUT_FILES=  [
               # os.path.join( DIR_EVENTALIGN, 'E_aligned_all.cvs'),
               os.path.join( DIR_GR, config["RUN_ID"]+"_GR.RData"),
               os.path.join( DIR_REPORT, "run_" + config["RUN_ID"]+"_report.html")
               ]

# print("OUTPUT_FILES=")
# for x in OUTPUT_FILES: 
# IPython.embed()
# 
#=========================================================================
#
#   BEGIN RULES    
#
#=========================================================================

rule all:
    input:
        [ OUTPUT_FILES ]

#------------------------------------------------------

rule make_report:
# build the final output report in html format
    input:
        aligned_reads = os.path.join( DIR_SORTED_MINIMAPPED, "run_{sample}.all.sorted.bam"),
        transcriptome = RefTranscriptome
    output:
        os.path.join( DIR_REPORT, "run_{sample}_report.html")
    params:
        " readcov_THRESH = 10;   ",
        " yplotmax = 10000; "
    log:
        logfile = os.path.join( DIR_REPORT, "finale_report_{sample}.log")
    message: """--- producing final report."""

    shell: """  
        Rscript -e  '{params} fin_Transcript    = "{input.transcriptome}";   fin_readalignment = "{input.aligned_reads}";    Genome_version="{GENOME_VERSION}" ;  rmarkdown::render("Nanopore_report.Rmd", output_file = "{output}" ) '  
        """

#------------------------------------------------------
# TODO: work on this

rule create_GR_obj:
# produce GRanges object of reads saved to file in .RData format 
    input:
        table_files  = Ealign_FILES_list
    output:
        GRobj        = os.path.join( DIR_GR, "{sample}_GR.RData")
    params:
        Rfuncs_file  = os.path.join( config[ "scripts"]["script_folder"], config[ "scripts"]["Rfuncs_file"] ), 
        output       = os.path.join( DIR_GR, "{sample}_GR.RData"),
        Ealign_files = Ealign_FILES_quoted 
    log:
        os.path.join( DIR_GR, "{sample}_GR_conversion.log")
    message: fmt("Convert aligned NP reads to GRanges object")
    shell:
        nice('Rscript', ["./scripts/npreads_tables2GR.R",
                         "--Rfuncs_file={params.Rfuncs_file}",
                         "--output={params.output}",
                         "--logFile={log}",
                         "--Ealign_files={params.Ealign_files}"]
)

#------------------------------------------------------
# CHANGE OF PLANS: DON'T DO THIS. (IT PRODUCES REDUNDANT READIDs) 
# rule consolidate_alignments:
# # Pool the alignment files into a single table (with just one header) to gather all the statistics from
#     input:
#         Ealign_FILES_list
#     output: 
#         os.path.join( DIR_EVENTALIGN, 'E_aligned_all.cvs') 
#     shell:
#         " head -1 {Ealign_FILES_list[0]} > '{output}' && tail -q -n +2 {Ealign_FILES_list} >> '{output}' "
# 
#------------------------------------------------------

rule np_event_align:
# Align the events to the reference genome
    input:
        sortedbam             = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", "fastq_runid_"+config['RUN_ID']+'_{chunk}.bwaligned.sorted.bam'),
        NOTCALLED_indexedbam  = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", "fastq_runid_"+config['RUN_ID']+'_{chunk}.bwaligned.sorted.bam.bai'),
        fastq_file            = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq'),
        NOTCALLED_fastq_npi   = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq.index'),
        refgenome_fasta  = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa" ),
        NOTCALLED_bwt    = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa.bwt"),
        NOTCALLED_pac    = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa.pac")
    output:
        Ealigned         = os.path.join( DIR_EVENTALIGN, 'Ealign_{chunk}.cvs' )
    log:
        logfile  = os.path.join( DIR_EVENTALIGN, 'Ealign_{chunk}.log')
    message: """---- align events from chunk {wildcards.chunk} to the genome ----"""
    shell:
        " {nanopolish} eventalign --reads {input.fastq_file} --bam {input.sortedbam} --genome {input.refgenome_fasta} --scale-events  > {output}  2> {log.logfile} "


#------------------------------------------------------

# rule quickcheck:
# TODO:


#------------------------------------------------------

rule index_sortedbam:
# Index the sorted bam file
    input:
        sortedbam  = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", "fastq_runid_"+config['RUN_ID']+'_{chunk}.bwaligned.sorted.bam')
    output:
        indexedbam  = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", "fastq_runid_"+config['RUN_ID']+'_{chunk}.bwaligned.sorted.bam.bai')
    log:
        logfile  = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", 'index_{chunk}_bwaMemOnt2d.log')
    message: """---- index the bam files for chunk {wildcards.chunk} ----"""
    shell:
        " {SAMTOOLS} index  {input.sortedbam}  2> {log.logfile} "

#------------------------------------------------------

rule align_bwa_mem_ont2d:
# Align the reads to the reference
    input:
        refg_fasta = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa" ),
        refg_bwt   = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa.bwt"),
        reads      = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq'),
        npi        = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq.index')
    output:
        sortedbam  = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", "fastq_runid_"+config['RUN_ID']+'_{chunk}.bwaligned.sorted.bam')
    params:
        options    = " mem -x ont2d ",
        tempfile   = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", "fastq_runid_"+config['RUN_ID']+'_{chunk}.bwaligniment.log')
    log:
        logfile  = os.path.join( DIR_SORTED_ALIGNED_BWA, "chunks", 'alignment_{chunk}_bwaMemOnt2d.log')
    message: """---- Align the reads from chunk {wildcards.chunk} to the reference ----"""
    shell:
        " {BWA} {params.options} {input.refg_fasta} {input.reads} | samtools sort -o {output.sortedbam} -T {params.tempfile}  > {log.logfile} 2>&1 "

#------------------------------------------------------

rule np_index:
# Index the reads and the fast5 files themselves
    input:
        fast5_folder = os.path.join( config['PATHIN'], 'fast5', 'pass', '{chunk}' ),
        fastq_file   = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq') 
    output:
        npi    = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq.index'), 
        fai    = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq.index.fai'),
        gzi    = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq.index.gzi'),  
        readdb = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}.fastq.index.readdb')
    params:
        options    = " index -d "
    log:
        logfile  = os.path.join( config['PATHIN'], 'fastq', 'pass', "fastq_runid_"+config['RUN_ID']+'_{chunk}_npi.log' )
    message: """---- index the reads from chunk {wildcards.chunk} against the fast5 files from the same. ----"""
    shell:
        " nice -19 {nanopolish} {params.options} {input.fast5_folder} {input.fastq_file} 2> {log.logfile} "
        
#------------------------------------------------------

rule bwa_index:
# Create indexed version of reference genome for fast alignment with bwa later:
    input:
        refgenome_fasta  = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa" )
    output:
        bwt  = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa.bwt"),
        pac  = os.path.join(config['ref']['Genome_DIR'] , config['ref']['Genome_version']+ ".fa.pac")
    params:
        options  = " index  "
    log:
        logfile  = os.path.join( config['ref']['Genome_DIR'], config['ref']['Genome_version'], "_bwa_indexing.log")
    message: """---- creating bwa index of the reference genome. ----"""
    shell:
        "{BWA} {params.options}  {input} > {log.logfile}"

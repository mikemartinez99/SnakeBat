#----- Import required libraries
import pandas as pd

#----- Set config file
configfile: "config.yaml"

#----- Container image
# Applies to every rule in this workflow, including any added later.
# Only used when the pipeline is launched with --use-singularity (Snakemake 7)
# or --use-apptainer (Snakemake 8+); ignored otherwise, so the plain conda
# workflow described in the README is unaffected.
container: "docker://ghcr.io/mikemartinez99/snakebat:latest"

#----- Read in the folder file
sample_file = config["folders"]
samples_df = pd.read_csv(sample_file).set_index("sample", drop=False)

#----- Extract all sample names
sample_list = list(samples_df['sample'])

#---------------------------------------------#
# PIPELINE RULES
#---------------------------------------------#

#----- Rule all
rule all:
    input: 
        expand("RMS_Power/{sample}.RMS_Power", sample = sample_list),
    output: "done.txt"
    shell: """
    touch done.txt
    """


#----- Rule to calculate RMS Power
rule calc_RMS_Power:
    output: 
        rms_power = directory("RMS_Power/{sample}.RMS_Power")
    params:
        sample = lambda wildcards: wildcards.sample,
        folder = lambda wildcards: samples_df.loc[wildcards.sample, "folder"],
        rms_code = "code/01_calcRMS_Power.R",
        segDur = config["segmentDuration"],
        fileType = config["fileType"],
        samplingRate = config["samplingRate"],
        gainOffset = config["gainOffset"],
        bwFilterFrom = config["bwFilterFrom"],
        bwFilterTo = config["bwFilterTo"]
    #conda:
     #   "env_config/snakeBat.yaml",
    log:
        "logs/{sample}.log"
    shell: """
    
        #----- Run the RMS Power code
        Rscript {params.rms_code} \
            {params.folder} \
            {params.segDur} \
            {params.fileType} \
            {params.samplingRate} \
            {params.gainOffset} \
            {params.bwFilterFrom} \
            {params.bwFilterTo} \
            {output.rms_power} \
            &> {log}

    """


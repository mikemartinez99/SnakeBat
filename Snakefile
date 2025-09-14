#----- Import required libraries
import pandas as pd

#----- Set config file
configfile: "config.yaml"

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
    input: expand("RMS_Power/{sample}.RMS_Power", sample = sample_list)
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
        bwFilterFrom = config["bwFilterFrom"],
        bwFilterTo = config["bwFilterTo"]
    conda:
        "env_config/snakeBat.yaml",
    log:
        "logs/{sample}.log"
    shell: """
    
        #----- Run the RMS Power code
        RScript {params.rms_code} \
            {params.folder} \
            {params.segDur} \
            {params.fileType} \
            {params.samplingRate} \
            {params.bwFilterFrom} \
            {params.bwFilterTo} \
            {output.rms_power} \
            &> {log}

    """
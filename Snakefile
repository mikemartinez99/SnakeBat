#----- Import required libraries
import pandas as pd

#----- Set config file
configfile: "config.yaml"

#----- Read in the folder file
sample_file = config["folders"]
samples_df = pd.read_csv(sample_file).set_index("sample", drop=False)

#----- Extract all sample names
sample_list = list(samples_df['sample'])

#----- Root folder for every pipeline output. Change this one string to send
#      results somewhere else; every rule below is relative to it.
RESULTS = "results"

#----- Every rule log, in the order the pipeline produces them. rule all
#      concatenates these into a single run log. Add new rules here as they
#      are added to the workflow, so the combined log stays complete.
def ordered_logs():
    logs = []
    logs += [f"logs/{s}.log" for s in sample_list]          # 1. calc_RMS_Power
    logs += [f"logs/{s}_combine.log" for s in sample_list]  # 2. combine_site_totals
    logs += ["logs/collate_summary.log"]                    # 3. collate_summary
    logs += [f"logs/{s}_plot.log" for s in sample_list]     # 4. plot_site_totals
    return logs

#---------------------------------------------#
# PIPELINE RULES
#---------------------------------------------#

#----- Rule all
rule all:
    input:
        expand(RESULTS + "/RMS_Power/{sample}.RMS_Power", sample = sample_list),
        expand(RESULTS + "/Summary/{sample}_combined_daily_totals.csv", sample = sample_list),
        expand(RESULTS + "/plots/{sample}_nightly_rmse.png", sample = sample_list),
        RESULTS + "/Summary/all_samples_nightly_totals.csv"
    output:
        run_log = RESULTS + "/full_pipeline_run_log.log"
    params:
        logs = " ".join(ordered_logs())
    message:
        "[4/4] Pipeline complete - assembling full run log at {output.run_log}"
    shell: """

        #----- Header
        RULE=$(printf '=%.0s' $(seq 1 78))
        printf '%s\\n' "$RULE" > {output.run_log}
        printf '  SnakeBat - full pipeline run log\\n' >> {output.run_log}
        printf '  Generated: %s\\n' "$(date '+%Y-%m-%d %H:%M:%S')" >> {output.run_log}
        printf '%s\\n\\n' "$RULE" >> {output.run_log}

        #----- Append each rule's log in the order the pipeline produced them
        for f in {params.logs}; do
            printf '%s\\n' "$RULE" >> {output.run_log}
            printf '  %s\\n' "$f" >> {output.run_log}
            printf '%s\\n' "$RULE" >> {output.run_log}
            if [ -s "$f" ]; then
                cat "$f" >> {output.run_log}
            else
                printf '  (empty or missing - this rule may not have run)\\n' >> {output.run_log}
            fi
            printf '\\n' >> {output.run_log}
        done

        printf '%s\\n' "$RULE" >> {output.run_log}
        printf '  End of run log\\n' >> {output.run_log}
        printf '%s\\n' "$RULE" >> {output.run_log}

    """


#----- Rule to calculate RMS Power
rule calc_RMS_Power:
    output:
        rms_power = directory(RESULTS + "/RMS_Power/{sample}.RMS_Power")
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
    log:
        "logs/{sample}.log"
    message:
        "[1/4] Calculating RMS power for {wildcards.sample} "
        "({params.bwFilterFrom}-{params.bwFilterTo} Hz, {params.segDur}s segments) -> {log}"
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


#----- Rule to flatten one site's per-date files into a single CSV
#
# This is the awk one-liner that used to live in the README, promoted to a rule
# so it runs automatically and per site. It keeps the header from the first
# file and drops it from every subsequent one.
#
# NOTE: the output deliberately lands in Summary/ rather than inside
# Total_RMSE/{sample}.RMS_Power/. Writing it into the folder being globbed
# would make the *_total_RMSE.csv glob swallow its own output on a rerun.
#
# NOTE: the awk braces are doubled ({{ }}) because Snakemake runs this shell
# block through Python string formatting first - single braces would be read
# as a field reference and the rule would fail to build.
rule combine_site_totals:
    input:
        RESULTS + "/RMS_Power/{sample}.RMS_Power"
    output:
        combined = RESULTS + "/Summary/{sample}_combined_daily_totals.csv"
    params:
        totals_dir = lambda wildcards: RESULTS + "/Total_RMSE/" + wildcards.sample + ".RMS_Power"
    log:
        "logs/{sample}_combine.log"
    message:
        "[2/4] Combining nightly files for {wildcards.sample} -> {output.combined}"
    shell: """

        #----- Concatenate every per-date file, keeping only the first header
        awk 'FNR==1 && NR!=1 {{ next }} {{ print }}' \
            {params.totals_dir}/*_total_RMSE.csv \
            > {output.combined} 2> {log}

        #----- Record what was produced
        echo "Combined $(ls {params.totals_dir}/*_total_RMSE.csv | wc -l | tr -d ' ') date file(s)" >> {log}
        echo "Wrote $(wc -l < {output.combined} | tr -d ' ') lines to {output.combined}" >> {log}

    """


#----- Rule to plot one site's nightly adjusted RMS energy against Julian date
#
# Reads the combined per-site CSV, which holds one row per second. The plotting
# script reduces that to one row per night before plotting, because
# total_adj_rmse is a nightly constant repeated down every row - plotting it
# raw would stack thousands of identical points.
rule plot_site_totals:
    input:
        combined = RESULTS + "/Summary/{sample}_combined_daily_totals.csv"
    output:
        plot = RESULTS + "/plots/{sample}_nightly_rmse.png"
    params:
        plot_code = "code/03_plotSiteTotals.R",
        sample = lambda wildcards: wildcards.sample
    log:
        "logs/{sample}_plot.log"
    message:
        "[3/4] Plotting nightly RMS energy for {wildcards.sample} -> {output.plot}"
    shell: """

        #----- Plot nightly RMS energy for this site
        Rscript {params.plot_code} \
            {input.combined} \
            {params.sample} \
            {output.plot} \
            &> {log}

    """


#----- Rule to collate every per-date Total_RMSE file into one summary table
rule collate_summary:
    input:
        expand(RESULTS + "/RMS_Power/{sample}.RMS_Power", sample = sample_list)
    output:
        summary = RESULTS + "/Summary/all_samples_nightly_totals.csv"
    params:
        summary_code = "code/02_collateSummary.R",
        totals_dir = RESULTS + "/Total_RMSE"
    log:
        "logs/collate_summary.log"
    message:
        "[3/4] Collating nightly totals across all samples -> {output.summary}"
    shell: """

        #----- Collate the nightly totals across all samples
        Rscript {params.summary_code} \
            {params.totals_dir} \
            {output.summary} \
            &> {log}

    """

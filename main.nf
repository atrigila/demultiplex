#!/usr/bin/env nextflow
/*
========================================================================================
                         nf-core/demultiplex
========================================================================================
 nf-core/demultiplex Analysis Pipeline.
 #### Homepage / Documentation
 https://github.com/nf-core/demultiplex
 #### Authors
 Chelsea Sawyer <chelsea.sawyer@crick.ac.uk> - https://github.com/csawye01/nf-core-demultiplex
----------------------------------------------------------------------------------------
*/


def helpMessage() {
    // TODO nf-core: Add to this help message with new command line parameters
    log.info"""
    =======================================================
                                              ,--./,-.
              ___     __   __   __   ___     /,-._.--~\'
        |\\ | |__  __ /  ` /  \\ |__) |__         }  {
        | \\| |       \\__, \\__/ |  \\ |___     \\`-._,-`-,
                                              `._,._,\'

     nf-core/demultiplex v${workflow.manifest.version}
    =======================================================

    Usage:

    The typical command for running the pipeline is as follows:

    nextflow run nf-core/demultiplex --samplesheet /camp/stp/sequencing/inputs/instruments/sequencers/RUNFOLDER/SAMPLESHEET.csv -profile crick

    Mandatory arguments:

      --samplesheet                 Full pathway to samplesheet
      -profile                      Configuration profile to use. Can use multiple (comma separated)
                                    Available: conda, docker, crick, singularity, awsbatch, test and more.

    Options:
      --email                       Set this parameter to your e-mail address to get a summary e-mail with details of the run sent to you when the workflow exits
      --outdir                      The output directory where the results will be saved
      -name                         Name for the pipeline run. If not specified, Nextflow will automatically generate a random mnemonic.

    bcl2fastq Options:
      --adapter_stringency              The minimum match rate that would trigger the masking or trimming process
      --barcode_mismatches              Number of allowed mismatches per index
      --create_fastq_for_indexreads     Create FASTQ files also for Index Reads
      --ignore_missing_bcls             Missing or corrupt BCL files are ignored. Assumes 'N'/'#' for missing calls
      --ignore_missing_filter           Missing or corrupt filter files are ignored. Assumes Passing Filter for all clusters in tiles where filter files are missing
      --ignore_missing_positions        Missing or corrupt positions files are ignored. If corresponding position files are missing, bcl2fastq writes unique coordinate positions in FASTQ header.
      --minimum_trimmed_readlength      Minimum read length after adapter trimming.
      --mask_short_adapter_reads        This option applies when a read is shorter than the length specified by --minimum-trimmed-read-length (note that the read does not specifically have to be trimmed for this option to trigger, it need only fall below the —minimum-trimmed-read-length for any reason).
      --tiles                           The --tiles argument takes a regular expression to select for processing only a subset of the tiles available in the flow cell Multiple selections can be made by separating the regular expressions with commas
      --use_bases_mask                  The --use-bases-mask string specifies how to use each cycle
      --with_failed_reads               Include all clusters in the output, even clusters that are non-PF. These clusters would have been excluded by default
      --write_fastq_reversecomplement   Generate FASTQ files containing reverse complements of actual data.
      --no_bgzf_compression             Turn off BGZF compression, and use GZIP for FASTQ files. BGZF compression allows downstream applications to decompress in parallel.
      --fastq_compression_level         Zlib compression level (1–9) used for FASTQ files.
      --no_lane_splitting               Do not split FASTQ files by lane.
      --find_adapters_withsliding_window    Find adapters with simple sliding window algorithm. Insertions and deletions of bases inside the adapter sequence are not handled.

    AWSBatch options:
      --awsqueue                    The AWSBatch JobQueue that needs to be set when running on AWSBatch
      --awsregion                   The AWS Region for your AWS Batch job to run on
    """.stripIndent()
}

/*
 * SET UP CONFIGURATION VARIABLES
 */

//Show help message
if (params.help){
    helpMessage()
    exit 0
}

// // Has the run name been specified by the user?
// //  this has the bonus effect of catching both -name and --name
custom_runName = params.name
if( !(workflow.runName ==~ /[a-z]+_[a-z]+/) ){
  custom_runName = workflow.runName
}

// ////////////////////////////////////////////////////
// /* --          VALIDATE INPUTS                 -- */
// ////////////////////////////////////////////////////
if ( params.samplesheet ){
    ss_sheet = file(params.samplesheet)
    if( !ss_sheet.exists() ) exit 1, "Sample sheet not found: ${params.samplesheet}"
}

if( workflow.profile == 'awsbatch') {
  // AWSBatch sanity checking
  if (!params.awsqueue || !params.awsregion) exit 1, "Specify correct --awsqueue and --awsregion parameters on AWSBatch!"
  if (!workflow.workDir.startsWith('s3') || !params.outdir.startsWith('s3')) exit 1, "Specify S3 URLs for workDir and outdir parameters on AWSBatch!"
  // Check workDir/outdir paths to be S3 buckets if running on AWSBatch
  // related: https://github.com/nextflow-io/nextflow/issues/813
  if (!workflow.workDir.startsWith('s3:') || !params.outdir.startsWith('s3:')) exit 1, "Workdir or Outdir not on S3 - specify S3 Buckets for each to run on AWSBatch!"
}

// Stage config files
//ch_multiqc_config = Channel.fromPath(params.multiqc_config)
FSCREEN_CONF_FILEPATH = new File(params.fastq_screen_conf).getAbsolutePath()
MULTIQC_CONF_FILEPATH = new File(params.multiqc_config).getAbsolutePath()

ch_output_docs = Channel.fromPath("$baseDir/docs/output.md")


// Header log info
log.info """=======================================================
                                          ,--./,-.
          ___     __   __   __   ___     /,-._.--~\'
    |\\ | |__  __ /  ` /  \\ |__) |__         }  {
    | \\| |       \\__, \\__/ |  \\ |___     \\`-._,-`-,
                                          `._,._,\'

nf-core/demultiplex v${workflow.manifest.version}
======================================================="""
def summary = [:]
summary['Pipeline Name']  = 'nf-core/demultiplex'
summary['Pipeline Version'] = workflow.manifest.version
summary['Run Name']     = custom_runName ?: workflow.runName
summary['Adapter Stringency'] = params.adapter_stringency
summary['Barcode Mismatches'] = params.barcode_mismatches
summary['FastQ for IDX'] = params.create_fastq_for_indexreads
summary['Ignore Missing BCLs'] = params.ignore_missing_bcls
summary['Ignore Missing Filter'] = params.ignore_missing_filter
summary['Ignore Missing Positions'] = params.ignore_missing_positions
summary['Min Trim Read Length'] = params.minimum_trimmed_readlength
summary['Mask Short Adapter Reads'] = params.mask_short_adapter_reads
summary['No BGZF Compression'] = params.no_bgzf_compression
summary['Tiles'] = params.tiles
summary['Use Bases Mask'] = params.use_bases_mask
summary['With Failed Reads'] = params.with_failed_reads
summary['Write FastQ Rev Comp'] = params.write_fastq_reversecomplement
summary['FastQ Compression Level'] = params.fastq_compression_level
summary['No Lane Splitting'] = params.no_lane_splitting
summary['Find Adapt Sliding Window'] = params.find_adapters_withsliding_window
summary['Max Memory']   = params.max_memory
summary['Max CPUs']     = params.max_cpus
summary['Max Time']     = params.max_time
summary['Output dir']   = params.outdir
summary['Working dir']  = workflow.workDir
summary['Container Engine'] = workflow.containerEngine
if(workflow.containerEngine) summary['Container'] = workflow.container
summary['Current home']   = "$HOME"
summary['Current user']   = "$USER"
summary['Current path']   = "$PWD"
summary['Working dir']    = workflow.workDir
summary['Output dir']     = params.outdir
summary['Script dir']     = workflow.projectDir
summary['Config Profile'] = workflow.profile
if(workflow.profile == 'awsbatch'){
   summary['AWS Region'] = params.awsregion
   summary['AWS Queue'] = params.awsqueue
}
if (params.email) summary['E-mail Address'] = params.email
log.info summary.collect { k,v -> "${k.padRight(15)}: $v" }.join("\n")
log.info "========================================="


def create_workflow_summary(summary) {
    def yaml_file = workDir.resolve('workflow_summary_mqc.yaml')
    yaml_file.text  = """
    id: 'nf-core-demultiplex-summary'
    description: " - this information is collected when the pipeline is started."
    section_name: 'nf-core/demultiplex Workflow Summary'
    section_href: 'https://github.com/nf-core/demultiplex'
    plot_type: 'html'
    data: |
        <dl class=\"dl-horizontal\">
${summary.collect { k,v -> "            <dt>$k</dt><dd><samp>${v ?: '<span style=\"color:#999999;\">N/A</a>'}</samp></dd>" }.join("\n")}
        </dl>
    """.stripIndent()

   return yaml_file
}

/*
 * Parse software version numbers
 */
// process get_software_versions {
//     validExitStatus 0
//
//     output:
//     file 'software_versions_mqc.yaml' into software_versions_yaml
//
//     script:
//     """
//     echo $workflow.manifest.version > v_pipeline.txt
//     echo $workflow.nextflow.version > v_nextflow.txt
//     fastqc --version > v_fastqc.txt
//     fastq_screen --version > v_fastq_screen.txt
//     multiqc --version > v_multiqc.txt
//     bcl2fastq --version > v_bcl2fastq.txt
//     cellranger --version > v_cellranger.txt
//     cellranger-atac --version > v_cellrangeratac.txt
//     cellranger-dna --version > v_cellrangerdna.txt
//     scrape_software_versions.py > software_versions_mqc.yaml
//     """
// }
// python --version > v_python.txt


if (params.samplesheet){
    lastPath = params.samplesheet.lastIndexOf(File.separator)
    runName_dir =  params.samplesheet.substring(0,lastPath+1)
    runName =  params.samplesheet.substring(51,lastPath)
    samplesheet_string = params.samplesheet.substring(lastPath+1)
}

//outputDir = file("/camp/stp/sequencing/inputs/instruments/fastq/${runName}")
//outputDir = file("/camp/stp/babs/working/sawyerc/nf_pipeline_test/${runName}/")
//outDir_result = outputDir.mkdir()

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
/* --                                                                     -- */
/* --               Sample Sheet Reformatting and Check`                  -- */
/* --                                                                     -- */
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

/*
 * STEP 1 - Check sample sheet for iCLIP samples and 10X samples
 *        - This will collapse iCLIP samples into one sample and pull out 10X
 *          samples into new samplesheet
 */

process reformat_samplesheet {
  tag "${sheet.name}"
  label 'process_medium'

  input:
  file sheet from ss_sheet

  output:
  file "*.standard.csv" into standard_samplesheet1, standard_samplesheet2, standard_samplesheet3, standard_samplesheet4
  file "*.bcl2fastq.txt" into bcl2fastq_results1
  file "*.tenx.txt" into tenx_results1, tenx_results2, tenx_results3
  file "*tenx.csv" optional true into tenx_samplesheet1, tenx_samplesheet2

  script:
  """
  reformat_samplesheet.py --samplesheet "${sheet}"
  """
}

/*
 * STEP 2 - Check samplesheet for single and dual mixed lanes and long and short
 *          indexes on same lanes and output pass or fail file to next processes
 */

process check_samplesheet {
  tag "${sheet.name}"
  label 'process_medium'

  input:
  file sheet from standard_samplesheet1

  output:
  file "*.txt" into resultChannel1, resultChannel2, resultChannel3, resultChannel4, resultChannel5

  script:
  """
  check_samplesheet.py --samplesheet "${sheet}"
  """
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
/* --                                                                     -- */
/* --               Problem Sample Sheet Processes                       -- */
/* --                                                                     -- */
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

/*
 * STEP 3 - If previous process finds samples that will cause problems, this
 *          process will remove problem samples from entire sample and create
 *          a new one
 *          ONLY RUNS WHEN SAMPLESHEET FAILS
 */

process make_fake_SS {
  tag "problem_samplesheet"
  label 'process_medium'

  input:
  file sheet from standard_samplesheet2
  file result from resultChannel1

  when:
  result.name =~ /^fail.*/

  output:
  file "*.csv" into fake_samplesheet
  file "*.txt" into problem_samples_list1, problem_samples_list2

  script:
  """
  create_falseSS.py --samplesheet "${sheet}"
  """
}

/*
 * STEP 4 -  Running bcl2fastq on the false_samplesheet with problem samples
 *           removed
 *           ONLY RUNS WHEN SAMPLESHEET FAILS
 */

process bcl2fastq_problem_SS {
  tag "problem_samplesheet"
  label 'process_big'

  input:
  file sheet from fake_samplesheet
  file result from resultChannel2

  when:
  result.name =~ /^fail.*/

  output:
  file "Stats/Stats.json" into stats_json_file

  script:
  """
  bcl2fastq \\
      --runfolder-dir ${runName_dir} \\
      --output-dir . \\
      --sample-sheet ${sheet} \\
      --ignore-missing-bcls \\
      --ignore-missing-filter \\
      --with-failed-reads \\
      --barcode-mismatches 0 \\
      --loading-threads 8 \\
      --processing-threads 24 \\
      --writing-threads 6 \\
  """
}

/*
 * STEP 5 -  Parsing .json file output from the bcl2fastq run to access the
 *           unknown barcodes section. The barcodes that match the short indexes
 *           and/or missing index 2 with the highest count to remake the sample
 *           sheet so that bcl2fastq can run properly
 *           ONLY RUNS WHEN SAMPLESHEET FAILS
 */

updated_samplesheet2 = Channel.create()
process parse_jsonfile {
  tag "problem_samplesheet"
  label 'process_medium'

  input:
  file json from stats_json_file
  file sheet from standard_samplesheet3
  file samp_probs from problem_samples_list1
  file result from resultChannel3

  when:
  result.name =~ /^fail.*/

  output:
  file "*.csv" into updated_samplesheet1, updated_samplesheet2

  script:
  """
  parse_json.py --samplesheet "${sheet}" \\
  --jsonfile "${json}" \\
  --problemsamples "${samp_probs}"
  """
}

/*
 * STEP 6 -  Checking the remade sample sheet. If this fails again the pipeline
 *           will exit and fail
 *           ONLY RUNS WHEN SAMPLESHEET FAILS
 */

PROBLEM_SS_CHECK2 = Channel.create()
process recheck_samplesheet {
  tag "problem_samplesheet"
  label 'process_medium'

  input:
  file sheet from ss_sheet
  file ud_sheet from updated_samplesheet1
  file prob_samps from problem_samples_list2
  file result from resultChannel4

  when:
  result.name =~ /^fail.*/

  output:
  file "*.txt" into PROBLEM_SS_CHECK2

  script:
  """
  recheck_samplesheet.py --samplesheet "${sheet}" --newsamplesheet "${ud_sheet}" --problemsamples "${prob_samps}"
  """

}


///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
/* --                                                                     -- */
/* --               Single Cell Processes`                        -- */
/* --                                                                     -- */
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

/*
 * STEP 7 - CellRanger MkFastQ
 *      ONLY RUNS WHEN ANY TYPE OF 10X SAMPLESHEET EXISTS
 */

def getCellRangerProjectName(fqfile) {
     def projectName = (fqfile =~ /.*\/outs\/fastq_path\/(.*)\/.*\/.+_S\d+_L00\d_(I|R)(1|2|3)_001\.fastq\.gz/)
     if (projectName.find()) {
       return projectName.group(1)
     }
     return fqfile
 }

process cellRangerMkFastQ {
    tag "${sheet.name}"
    label 'process_big'
    publishDir path: "${params.outdir}", mode: 'copy'

    input:
    file sheet from tenx_samplesheet1
    file result from tenx_results1

    when:
    result.name =~ /^true.*/

    output:
    file "*/outs/fastq_path/Undetermined_*.fastq.gz" into cr_undetermined_default_fq_ch, cr_undetermined_fastqs_screen_ch mode flatten
    file "*/outs/fastq_path/*/**.fastq.gz" into cr_fastqs_count_ch, cr_fastqs_fqc_ch, cr_fastqs_screen_ch, cr_fastqs_copyfs_ch mode flatten
    file "*/outs/fastq_path/Reports" into cr_b2fq_default_reports_ch
    file "*/outs/fastq_path/Stats" into cr_b2fq_default_stats_ch


    script:
    if (sheet.name =~ /^*.tenx.csv/){
    """
    cellranger mkfastq --id mkfastq --run ${runName_dir} --samplesheet ${sheet} --tiles s_[1]
    """
    }
    else if (sheet.name =~ /^*.ATACtenx.csv/){
    """
    cellranger-atac mkfastq --id mkfastq --run ${runName_dir} --samplesheet ${sheet}
    """
    }
    else if (sheet.name =~ /^*.DNAtenx.csv/){
    """
    cellranger-dna mkfastq --id mkfastq --run ${runName_dir} --samplesheet ${sheet}
    """
    }
}

/*
 * STEP 8 - Copy CellRanger FastQ files to new folder
 *      ONLY RUNS WHEN ANY TYPE OF 10X SAMPLES EXISTS
 */

cr_fastqs_copyfs_tuple_ch = cr_fastqs_copyfs_ch.map { fqfile -> [ fqfile.getParent().getParent().getName(), fqfile.getParent().getName(), fqfile.getFileName() ] }

process cellRangerMoveFqs {
  tag "${fastq}"

  input:
  set projectName, sampleName, file(fastq) from cr_fastqs_copyfs_tuple_ch
  file result from tenx_results2

  when:
  result.name =~ /^true.*/

  script:
  """
  while [ ! -f ${params.outdir}/mkfastq/outs/fastq_path/${projectName}/${sampleName}/${fastq} ]; do sleep 15s; done
  mkdir -p "${params.outdir}/fastq/${projectName}" && cp ${params.outdir}/mkfastq/outs/fastq_path/${projectName}/${sampleName}/${fastq} ${params.outdir}/fastq/${projectName}
  """
}


/*
 * STEP 9 - CellRanger count
 * ONLY RUNS WHEN ANY TYPE OF 10X SAMPLESHEET EXISTS
 *
 */

cr_samplesheet_info_ch = tenx_samplesheet2.splitCsv(header: true, skip: 1).map { row -> [ row.Sample_ID, row.Sample_Project, row.ReferenceGenome, row.DataAnalysisType ] }
cr_fqname_fqfile_ch = cr_fastqs_count_ch.map { fqfile -> [ fqfile.getParent().getName(), fqfile.getParent().getParent() ] }.unique()

cr_fqname_fqfile_ch
   .phase(cr_samplesheet_info_ch)
   .map{ left, right ->
     def sampleID = left[0]
     def projectName = right[1]
     def refGenome = right[2]
     def dataType = right[3]
     def fastqDir = left[1]
     tuple(sampleID, projectName, refGenome, dataType, fastqDir)
   }
   .set { cr_grouped_fastq_dir_sample_ch }


process cellRangerCount {
   tag "${projectName}"
   publishDir "${params.outdir}/count/${projectName}", mode: 'copy'
   label 'process_big'
   errorStrategy 'ignore'

   echo true

   input:
   set sampleID, projectName, refGenome, dataType, file(fastqDir) from cr_grouped_fastq_dir_sample_ch
   file result from tenx_results3

   when:
   result.name =~ /^true.*/

   output:
   file "${sampleID}/" into count_output
   file "CR_Count_error.log" optional true into count_error_output

   script:
   genome_ref_conf_filepath = params.cellranger_genomes.get(refGenome, false)

   if (dataType =~ /10X-3prime/){
   """
   if !cellranger count --id=$sampleID --transcriptome=${genome_ref_conf_filepath.tenx_transcriptomes} --fastqs=$fastqDir --sample=$sampleID; then
      echo 'Error in Cell Ranger Count with sample $sampleID from project $projectName' > CR_Count_error.log
    fi
   """
   }
   else if (dataType =~ /10X-CNV/){
   """
   if !cellranger-dna cnv --id=$sampleID --transcriptome=${genome_ref_conf_filepath.tenx_cnv} --fastqs=$fastqDir --sample=$sampleID; then
     echo 'Error in Cell Ranger CNV Count with sample $sampleID from project $projectName' > CR_Count_error.log
    fi
   """
   }
   else if (dataType =~ /10X-ATAC/){
   """
   if !cellranger-atac count --id=$sampleID --transcriptome=${genome_ref_conf_filepath.tenx_atac} --fastqs=$fastqDir --sample=$sampleID; then
     echo 'Error in Cell Ranger ATAC Count with sample $sampleID from project $projectName' > CR_Count_error.log
    fi
   """
   }
}

///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////
/* --                                                                     -- */
/* --               Main Demultiplexing Processes`                        -- */
/* --                                                                     -- */
///////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////

/*
 * STEP 10 -  Running bcl2fastq on the remade samplesheet or a sample sheet that
 *           passed the initial check. bcl2fastq parameters can be changed when
 *           staring up the pipeline.
 *           ONLY RUNS WHEN SAMPLES REMAIN AFTER Single Cell SAMPLES ARE SPLIT OFF
 *           INTO SEPARATE SAMPLE SHEETS
 */

fastqs_fqc_ch = Channel.create()
fastqs_screen_ch = Channel.create()
process bcl2fastq_default {
    tag "${std_samplesheet.name}"
    publishDir path: "${params.outdir}/fastq", mode: 'copy'

    label 'process_big'

    input:
    file result2 from PROBLEM_SS_CHECK2.ifEmpty { true }
    file result from resultChannel5
    file std_samplesheet from standard_samplesheet4
    file sheet from updated_samplesheet2.ifEmpty { true }
    file bcl_result from bcl2fastq_results1

    when:
    bcl_result.name =~ /^true.bcl2fastq.txt/

    output:
    file "*/**.fastq.gz" into fastqs_fqc_ch, fastqs_screen_ch mode flatten
    file "*.fastq.gz" into undetermined_default_fq_ch, undetermined_default_fastqs_screen_ch mode flatten
    file "Reports" into b2fq_default_reports_ch
    file "Stats" into b2fq_default_stats_ch

    script:
    ignore_miss_bcls = params.ignore_missing_bcls ? "--ignore-missing-bcls " : ""
    ignore_miss_filt = params.ignore_missing_filter ? "--ignore-missing-filter " : ""
    ignore_miss_pos = params.ignore_missing_positions ? "--ignore-missing-positions " : ""
    bases_mask = params.use_bases_mask ? "--use-bases-mask ${params.use_bases_mask} " : ""
    tiles = params.tiles ? "--tiles ${params.tiles} " : ""
    fq_index_rds = params.create_fastq_for_indexreads ? "--create-fastq-for-index-reads " : ""
    failed_rds = params.with_failed_reads ? "--with-failed-reads " : ""
    fq_rev_comp = params.write_fastq_reversecomplement ? "--write-fastq-reverse-complement " : ""
    no_bgzf_comp = params.no_bgzf_compression ? "--no-bgzf-compression " : ""
    no_lane_split = params.no_lane_splitting ? "--no-lane-splitting " : ""
    slide_window_adapt =  params.find_adapters_withsliding_window ? "--find-adapters-with-sliding-window " : ""

    if (result.name =~ /^pass.*/){
      """
      bcl2fastq \\
          --runfolder-dir ${runName_dir} \\
          --output-dir . \\
          --sample-sheet ${std_samplesheet} \\
          --adapter-stringency ${params.adapter_stringency} \\
          $tiles \\
          $ignore_miss_bcls \\
          $ignore_miss_filt \\
          $ignore_miss_pos \\
          --minimum-trimmed-read-length ${params.minimum_trimmed_readlength} \\
          --mask-short-adapter-reads ${params.mask_short_adapter_reads} \\
          --fastq-compression-level ${params.fastq_compression_level} \\
          --barcode-mismatches ${params.barcode_mismatches} \\
          $bases_mask $fq_index_rds $failed_rds  \\
          $fq_rev_comp $no_bgzf_comp $no_lane_split $slide_window_adapt
      """
    }

    else if (result2.name =~ /^fail.*/){
      exit 1, "Remade sample sheet still contains problem samples"
    }

    else if (result.name =~ /^fail.*/){
      """
      bcl2fastq \\
          --runfolder-dir ${runName_dir} \\
          --output-dir . \\
          --sample-sheet ${sheet} \\
          --adapter-stringency ${params.adapter_stringency} \\
          $tiles \\
          $ignore_miss_bcls \\
          $ignore_miss_filt \\
          $ignore_miss_pos \\
          --minimum-trimmed-read-length ${params.minimum_trimmed_readlength} \\
          --mask-short-adapter-reads ${params.mask_short_adapter_reads} \\
          --fastq-compression-level ${params.fastq_compression_level} \\
          --barcode-mismatches ${params.barcode_mismatches}
          $bases_mask $fq_index_rds $failed_rds  \\
          $fq_rev_comp $no_bgzf_comp $no_lane_split $slide_window_adapt
      """
    }
}

/*
 * STEP 11 - FastQC
 */

fqname_fqfile_ch = fastqs_fqc_ch.map { fqFile -> [fqFile.getParent().getName(), fqFile ] }
undetermined_default_fqfile_tuple_ch = undetermined_default_fq_ch.map { fqFile -> ["Undetermined_default", fqFile ] }
cr_fqname_fqfile_fqc_ch =cr_fastqs_fqc_ch.map { fqFile -> [fqFile.getParent().getParent().getName(), fqFile ] }
cr_undetermined_default_fq_renamed_ch = cr_undetermined_default_fq_ch
cr_undetermined_default_fq_tuple_ch = cr_undetermined_default_fq_renamed_ch.map { fqFile -> ["Undetermined_default", fqFile ] }

process fastqc {
    tag "${projectName}"
    publishDir path: "${params.outdir}/fastqc/${projectName}", mode: 'copy'
    label 'process_big'

    input:
    set val(projectName), file(fqFile) from fqname_fqfile_ch.mix(cr_fqname_fqfile_fqc_ch, cr_undetermined_default_fq_tuple_ch, undetermined_default_fqfile_tuple_ch)

    output:
    set val(projectName), file("*_fastqc") into fqc_folder_ch, all_fcq_files_tuple
    file "*.html" into fqc_html_ch

    script:
    """
    fastqc --extract ${fqFile}
    """
}

/*
 * STEP 11 - FastQ Screen
 */

fastqs_screen_fqfile_ch = fastqs_screen_ch.map { fqFile -> [fqFile.getParent().getName(), fqFile ] }
undetermined_fastqs_screen_fqfile_ch = undetermined_default_fastqs_screen_ch.map { fqFile -> ["Undetermined_default", fqFile ] }
cr_fqname_fqfile_screen_ch =cr_fastqs_screen_ch.map { fqFile -> [fqFile.getParent().getParent().getName(), fqFile ] }
cr_undetermined_fastqs_screen_tuple_ch = cr_undetermined_fastqs_screen_ch.map { fqFile -> ["Undetermined_default", fqFile ] }

process fastq_screen {
    tag "${projectName}"
    publishDir "${params.outdir}/fastq_screen/${projectName}", mode: 'copy'
    label 'process_big'

    input:
    set val(projectName), file(fqFile) from fastqs_screen_fqfile_ch.mix(cr_fqname_fqfile_screen_ch, cr_undetermined_fastqs_screen_tuple_ch, undetermined_fastqs_screen_fqfile_ch)

    output:
    file("*.html") into fastq_screen_html
    file("*.txt") into fastq_screen_txt

    shell:
    """
    fastq_screen --force --subset 200000 --conf ${FSCREEN_CONF_FILEPATH} --aligner bowtie2 ${fqFile}
    """
}

/*
 * STEP 12A - MultiQC per project
 */

process multiqc {
    tag "${projectName}"
    publishDir path: "${params.outdir}/multiqc/${projectName}", mode: 'copy'
    label 'process_big'

    input:
    set val(projectName), file(fqFiles) from fqc_folder_ch.groupTuple()

    output:
    file "*multiqc_report.html" into multiqc_report
    file "*_data"

    shell:
    """
    multiqc ${fqFiles} --config ${MULTIQC_CONF_FILEPATH} .
    """
}

/*
 * STEP 12B- MultiQC for all projects
 */

all_fcq_files = all_fcq_files_tuple.map { k,v -> v }.flatten().collect()
process multiqcAll {
    tag "${runName}"
    publishDir path: "${params.outdir}/multiqc", mode: 'copy'
    label 'process_big'

    input:
    file fqFile from all_fcq_files

    output:
    file "*multiqc_report.html" into multiqc_report_all
    file "*_data"

    shell:
    """
    multiqc ${fqFile} --config ${MULTIQC_CONF_FILEPATH} .
    """
}


/*
 * STEP 13 - Output Description HTML
 */

// process output_documentation {
//     publishDir "${params.outdir}/Documentation", mode: 'copy'
//
//     input:
//     file output_docs from ch_output_docs
//
//     output:
//     file "results_description.html"
//
//     script:
//     """
//     markdown_to_html.r $output_docs results_description.html
//     """
// }

/*
 * Completion e-mail notification
 */
workflow.onComplete {

    // Set up the e-mail variables
    def subject = "[nf-core/demultiplex] Successful: $workflow.runName"
    if(!workflow.success){
      subject = "[nf-core/demultiplex] FAILED: $workflow.runName"
    }
    def email_fields = [:]
    email_fields['version'] = workflow.manifest.version
    email_fields['runName'] = custom_runName ?: workflow.runName
    email_fields['success'] = workflow.success
    email_fields['dateComplete'] = workflow.complete
    email_fields['duration'] = workflow.duration
    email_fields['exitStatus'] = workflow.exitStatus
    email_fields['errorMessage'] = (workflow.errorMessage ?: 'None')
    email_fields['errorReport'] = (workflow.errorReport ?: 'None')
    email_fields['commandLine'] = workflow.commandLine
    email_fields['projectDir'] = workflow.projectDir
    email_fields['summary'] = summary
    email_fields['summary']['Date Started'] = workflow.start
    email_fields['summary']['Date Completed'] = workflow.complete
    email_fields['summary']['Pipeline script file path'] = workflow.scriptFile
    email_fields['summary']['Pipeline script hash ID'] = workflow.scriptId
    if(workflow.repository) email_fields['summary']['Pipeline repository Git URL'] = workflow.repository
    if(workflow.commitId) email_fields['summary']['Pipeline repository Git Commit'] = workflow.commitId
    if(workflow.revision) email_fields['summary']['Pipeline Git branch/tag'] = workflow.revision
    email_fields['summary']['Nextflow Version'] = workflow.nextflow.version
    email_fields['summary']['Nextflow Build'] = workflow.nextflow.build
    email_fields['summary']['Nextflow Compile Timestamp'] = workflow.nextflow.timestamp

    // Render the TXT template
    def engine = new groovy.text.GStringTemplateEngine()
    def tf = new File("$baseDir/assets/email_template.txt")
    def txt_template = engine.createTemplate(tf).make(email_fields)
    def email_txt = txt_template.toString()

    // Render the HTML template
    def hf = new File("$baseDir/assets/email_template.html")
    def html_template = engine.createTemplate(hf).make(email_fields)
    def email_html = html_template.toString()

    // Render the sendmail template
    def smail_fields = [ email: params.email, subject: subject, email_txt: email_txt, email_html: email_html, baseDir: "$baseDir" ]
    def sf = new File("$baseDir/assets/sendmail_template.txt")
    def sendmail_template = engine.createTemplate(sf).make(smail_fields)
    def sendmail_html = sendmail_template.toString()

    // Send the HTML e-mail
    if (params.email) {
        try {
          if( params.plaintext_email ){ throw GroovyException('Send plaintext e-mail, not HTML') }
          // Try to send HTML e-mail using sendmail
          [ 'sendmail', '-t' ].execute() << sendmail_html
          log.info "[nf-core/demultiplex] Sent summary e-mail to $params.email (sendmail)"
        } catch (all) {
          // Catch failures and try with plaintext
          [ 'mail', '-s', subject, params.email ].execute() << email_txt
          log.info "[nf-core/demultiplex] Sent summary e-mail to $params.email (mail)"
        }
    }

    // Write summary e-mail HTML to a file
    def output_d = new File( "${params.outdir}/Documentation/" )
    if( !output_d.exists() ) {
      output_d.mkdirs()
    }
    def output_hf = new File( output_d, "pipeline_report.html" )
    output_hf.withWriter { w -> w << email_html }
    def output_tf = new File( output_d, "pipeline_report.txt" )
    output_tf.withWriter { w -> w << email_txt }

    log.info "[nf-core/demultiplex] Pipeline Complete"

}

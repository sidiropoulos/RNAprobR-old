###Function in the normalizing functions family.

#' Smooth Log2-ratio
#'
#' Performs smooth-log2-ratio calculation given control and treated
#' GRanges generated by comp() function.
#'
#' @param control_GR GRanges object made by comp() function from the control
#' sample.
#' @param treated_GR GRanges object made by comp() function from the treated
#' sample.
#' @param window_size if smoothing is to be performed, then what should be the
#' window size?  (use only odd numbers to ensure that windows are centred on a
#' nucleotide of interest) (default: 5)
#' @param nt_offset How many position in the 5' direction should the signal be
#' offset to account for the fact that reverse transcription termination occurs
#' before site of modification.
#' @param depth_correction One of three values: "no" - counts are used as
#' given, "all" - counts from sample with higher total sum of EUCs are
#' multiplied by sum of EUCs from sample with lower total sum of EUCs and
#' divided by sum of EUCs from sample with higher EUC count (default),
#' "RNA" as in "all" but on per RNA basis
#' @param pseudocount What pseudocount should be added to each nucleotide prior
#' to calculating log2 ratio (default: 5)
#' @param add_to GRanges object made by other normalization function (dtcr(),
#' slograt(), swinsor(), compdata()) to which normalized values should be
#' added.
#' @return GRanges object with "slograt" (smooth log2 ratio) and "slograt.p"
#' (p.value of comparing control and treated) metadata.
#' @author Lukasz Jan Kielpinski, Nikos Sidiropoulos
#' @seealso \code{\link{comp}}, \code{\link{dtcr}}, \code{\link{compdata}},
#' \code{\link{swinsor}}, \code{\link{GR2norm_df}}, \code{\link{plotRNA}},
#' \code{\link{norm2bedgraph}}
#' @references Wan, Y., Qu, K., Zhang, Q.C., Flynn, R.A., Manor, O., Ouyang,
#' Z., Zhang, J., Spitale, R.C., Snyder, M.P., Segal, E., et al. (2014).
#' Landscape and variation of RNA secondary structure across the human
#' transcriptome. Nature 505, 706-709.
#' @examples
#'
#' dummy_euc_GR_control <- GRanges(seqnames="DummyRNA",
#'                                 IRanges(start=round(runif(100)*100),
#'                                 width=round(runif(100)*100+1)), strand="+",
#'                                 EUC=round(runif(100)*100))
#' dummy_euc_GR_treated <- GRanges(seqnames="DummyRNA",
#'                                 IRanges(start=round(runif(100)*100),
#'                                 width=round(runif(100)*100+1)), strand="+",
#'                                 EUC=round(runif(100)*100))
#' dummy_comp_GR_control <- comp(dummy_euc_GR_control)
#' dummy_comp_GR_treated <- comp(dummy_euc_GR_treated)
#' slograt(control_GR=dummy_comp_GR_control, treated_GR=dummy_comp_GR_treated)
#'
#' @import GenomicRanges
#' @export slograt
slograt <- function(control_GR, treated_GR, window_size=5, nt_offset=1,
                    depth_correction="all", pseudocount=5, add_to){

###Check conditions:
    if(nt_offset < 0)
        stop("nt_offset must be >= 0")

    if(window_size < 1)
        stop("window_size must be >= 0")

    if((window_size%%2)!=1)
        stop("window_size must be odd")

    ###Function body:
    control <- GR2norm_df(control_GR)
    treated <- GR2norm_df(treated_GR)

    #Merge control and treated
    comp_merg <- merge(control, treated, by=c("RNAid", "Pos", "nt"), all=TRUE,
                       suffixes=c(".control",".treated"), sort= FALSE)
    #repair ordering after merging.
    comp_merg <- comp_merg[order(comp_merg$RNAid, comp_merg$Pos),]
    comp_merg[is.na(comp_merg)] <- 0 #Changes NA to 0

    ##Rename chosen depth correction function to dc_fun
    dc_fun <- switch(which(depth_correction==c("no", "RNA", "all")),
                     .no_dc, .RNA_dc, .all_dc)
    #Corrects the sequencing depth. dc_fun is a different function depending on
    #the depth_correction mode
    comp_merg_dc <- dc_fun(comp_merg)

    #Splits the data frame into a list of data frames, one for each RNA
    compmerg_dc_by_RNA <- split(comp_merg_dc, f=comp_merg_dc$RNAid, drop=TRUE)

    #Do processing (calculate smooth log ratio) and join into data frame
    normalized <- do.call(rbind, lapply(compmerg_dc_by_RNA,
                                        FUN=.process_oneRNA_compmerg_slograt,
                                        window_size, nt_offset, pseudocount))
    #Keep only relevant columns
    normalized <- data.frame(RNAid=normalized$RNAid, Pos=normalized$Pos,
                             nt=normalized$nt, slograt=normalized$slograt)

    ###Add p.values:
    #not depth corrected!
    compmerg_by_RNA <- split(comp_merg, f=comp_merg$RNAid, drop=TRUE)

    #Do processing (calculate pvalues) and join into data frame
    normalized2 <- do.call(rbind, lapply(compmerg_by_RNA,
                                   FUN=.process_oneRNA_compmerg_slograt_pvalues,
                                   window_size, nt_offset))
    #Keep only relevant columns
    normalized2 <- data.frame(RNAid=normalized2$RNAid, Pos=normalized2$Pos,
                             nt=normalized2$nt, slograt.p=normalized2$slograt.p)
    #merge with ratios:
    normalized <- merge(normalized, normalized2, by=c("RNAid","Pos","nt"),
                        sort= FALSE)
    #Change NaN to NA, for consistency [NaN often created at the 5' end of RNA]
    normalized$slograt[is.nan(normalized$slograt)] <- NA
    normalized$slograt.p[is.nan(normalized$slograt.p)] <- NA

    #If add_to specified, merge with existing normalized data frame:
    if(!missing(add_to)){
        add_to_df <- GR2norm_df(add_to)
        normalized <- merge(add_to_df, normalized, by=c("RNAid", "Pos", "nt"),
                            suffixes=c(".old",".new"))
    }
    ###

    normalized <- normalized[order(normalized$RNAid, normalized$Pos),]
    norm_df2GR(normalized)
}

###Auxiliary functions

#Function to calculate p-values for dtcr, it uses test for comparing Two
#Population Proportions: (z-test, as e.g. shown on
#http://www.socscistatistics.com/tests/ztest/
#or https://onlinecourses.science.psu.edu/stat414/node/268)
#Comparison done in windows of the same size as smoothing

#T_ctrl - terminations control, T_tr - terminations treated
.compare_prop_slograt <- function(T_ctrl, T_tr, window_size){

    window_side <- window_size/2-0.5

    #Prepare running sums (the same window as in for smoothing dtcr):
    Tc <- colSums(.construct_smoothing_matrix(T_ctrl, window_size),
                  na.rm=TRUE)[(window_side+1):(length(T_ctrl)+window_side)]
    Cc <- rep(sum(T_ctrl), length(Tc))
    Tt <- colSums(.construct_smoothing_matrix(T_tr, window_size),
                  na.rm=TRUE)[(window_side+1):(length(T_tr)+window_side)]
    Ct <- rep(sum(T_tr), length(Tt))

    #Calculate test statistics z:
    pp <- (Tc + Tt)/(Cc + Ct) #pooled proportion
    se <- sqrt(pp*(1-pp)*(1/Cc + 1/Ct)) #standard error
    z <- (Tc/Cc - Tt/Ct)/se

    #Transform 'z' to two-tailed p-value:
    pnorm(abs(z), lower.tail= FALSE)*2

}

##one RNA processing:
#Calculate smooth-log-ratio:
.process_oneRNA_compmerg_slograt <- function(oneRNA_compmerg, window_size,
                                            nt_offset, pseudocount){

    if(prod(diff(oneRNA_compmerg$Pos)==rep(1, nrow(oneRNA_compmerg)-1))!=1)
        oneRNA_compmerg <- .correct_merged(oneRNA_compmerg)

    #Check if data is properly sorted.
    if(prod(diff(oneRNA_compmerg$Pos)==rep(1, nrow(oneRNA_compmerg)-1))==1){
        window_side <- window_size/2-0.5

        treated_summed <- colSums(.construct_smoothing_matrix(
            oneRNA_compmerg$TC.treated, window_size) + pseudocount,
            na.rm=TRUE)[(window_side+1):(length(oneRNA_compmerg$TC.treated) +
                                             window_side)]
        control_summed <- colSums(.construct_smoothing_matrix(
            oneRNA_compmerg$TC.control, window_size) + pseudocount,
            na.rm=TRUE)[(window_side+1):(length(oneRNA_compmerg$TC.control) +
                                             window_side)]
        oneRNA_compmerg$slograt <- log2(treated_summed/control_summed)[
            (1 + nt_offset):(length(treated_summed) + nt_offset)]

        oneRNA_compmerg[1:(nrow(oneRNA_compmerg) - nt_offset),]

    }
    else {
        Message <- "Check if data was properly sorted by comp() function.
                    Problem with"
        stop(strwrap(paste(Message, oneRNA_compmerg$RNAid[1])))
    }
}

#Calculate p.values:
.process_oneRNA_compmerg_slograt_pvalues <- function(oneRNA_compmerg,
                                                     window_size, nt_offset){

    if(prod(diff(oneRNA_compmerg$Pos)==rep(1, nrow(oneRNA_compmerg)-1))!=1)
        oneRNA_compmerg <- .correct_merged(oneRNA_compmerg)

    #Check if data is properly sorted.
    if(prod(diff(oneRNA_compmerg$Pos)==rep(1, nrow(oneRNA_compmerg)-1))==1){
        oneRNA_compmerg$slograt.p <-
            .compare_prop_slograt(T_ctrl=oneRNA_compmerg$TC.control,
                                  T_tr=oneRNA_compmerg$TC.treated,
                                  window_size = window_size)[(1 + nt_offset):(
                                      nrow(oneRNA_compmerg) + nt_offset)]

        oneRNA_compmerg[1:(nrow(oneRNA_compmerg) - nt_offset),]
    }
    else {
        Message <- "Check if data was properly sorted by comp() function.
                    Problem with"
        stop(strwrap(paste(Message, oneRNA_compmerg$RNAid[1])))
    }
}

#Depth correction:

#No depth correction:
.no_dc <- function(Comp_df){
    Comp_df
}

#Global depth correction (to depth of a sample with lower coverage)
.all_dc <- function(Comp_df){

    control_sum <- sum(Comp_df$TC.control, na.rm=TRUE)
    treated_sum <- sum(Comp_df$TC.treated, na.rm=TRUE)

    ###Check if there are reads in both control and treated.
    #If yes - correction factor is a ratio between control and treated
    #reads, if not - set correction_factor to 1.
    if(control_sum*treated_sum > 0)
        correction_factor <- control_sum/treated_sum
    else{
        correction_factor <- 1
        switch(which(depth_correction==c("no", "RNA", "all")),
               "Something wrong",
               message(paste("For RNA", Comp_df[1,1],
                             "Depth correction factor set to 1")),
               "Depth correction factor set to 1")
    }

    if(control_sum > treated_sum)
        Comp_df$TC.control <- Comp_df$TC.control/correction_factor
    else
        #Multiply treated reads by correction factor
        Comp_df$TC.treated <- Comp_df$TC.treated*correction_factor

    Comp_df
}

#RNA based depth correction, it runs the all_dc function for each RNA
#separately:
.RNA_dc <- function(Comp_df){
    compmerg_by_RNA <- split(Comp_df, f=Comp_df$RNAid, drop=TRUE)

    do.call(rbind, lapply(compmerg_by_RNA, FUN=.all_dc))
}

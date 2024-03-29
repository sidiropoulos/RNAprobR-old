\name{swinsor}
\alias{swinsor}
\title{Smooth Winsorization}
\usage{
swinsor(Comp_GR, winsor_level = 0.9, window_size = 71, only_top = FALSE,
  nt_offset = 1, add_to)
}
\arguments{
\item{Comp_GR}{GRanges object made by comp() function.}

\item{winsor_level}{Winsorization level. Bottom outliers will be set to
(1-winsor_level)/2 quantile and top outliers to (1+winsor_level)/2 quantile.}

\item{window_size}{Size of a sliding window.}

\item{only_top}{If TRUE then bottom values are not Winsorized and are set to
0.}

\item{nt_offset}{How many position in the 5' direction should the signal be
offset to account for the fact that reverse transcription termination occurs
before site of modification.}

\item{add_to}{GRanges object made by other normalization function (dtcr(),
slograt(), swinsor(), compdata()) to which normalized values should be
added.}
}
\value{
GRanges object with "swinsor" (mean smooth-Winsor values) and
"swinsor.sd" (standard deviation of smooth-Winsor values) metadata.
}
\description{
Performs sliding window Winsorization given treated GRanges generated by
comp() function. It winsorizes values in windows (of a size specified by
window_size) sliding by 1 nt over whole transcript length and reports mean
winsorized value for each nucleotide (as well as standard deviation).
}
\examples{
dummy_euc_GR <- GRanges(seqnames="DummyRNA",
                        IRanges(start=round(runif(100)*100),
                        width=round(runif(100)*100+1)), strand="+",
                        EUC=round(runif(100)*100))
dummy_comp_GR <- comp(dummy_euc_GR)
swinsor(dummy_comp_GR)
}
\author{
Lukasz Jan Kielpinski, Jeppe Vinther, Nikos Sidiropoulos
}
\references{
"Analysis of sequencing based RNA structure probing data"
Kielpinski, Sidiropoulos, Vinther. Chapter in "Methods in Enzymology"
(in preparation)
}
\seealso{
\code{\link{comp}}, \code{\link{dtcr}}, \code{\link{slograt}},
\code{\link{compdata}}, \code{\link{GR2norm_df}},
\code{\link{plotRNA}}, \code{\link{norm2bedgraph}}, \code{\link{winsor}},
\code{\link{swinsor_vector}}
}


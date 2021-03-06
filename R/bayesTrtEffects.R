#' Bayesian Estimation of Treatment Effects in Panel Setting
#'
#' \code{bayesTrtEffects} performs Bayesian estimation of regression coefficients and according treatment effects
#'  on panel structured data on a certain outcome of interest. The dataset may be unbalanced, but needs to fullfill
#' some conditions to get proper results. The function offers some model choices, which determine the framework
#' in which the treatment effects will be estimated.
#'
#' @param base_mat a data frame or matrix file, containing id, maximum panel time on each subject,
#' the treatment indicator and the baseline features.
#' @param panel_mat a data frame of matrix file, containing id, panel times per subject, the panel outcomes
#' and other features, relevant for regression on the outcomes.
#' @param type contains one of two possible Strings to define the modelling approach of the regression
#' coefficients, correlation structure between outcomes and the treatment. Also will have an
#' influence on the resulting treatment effects ("SF" - Shared Factor, "SWR" - Switching Regression)
#' In general "SF" will take much less computation time, while "SWR" offers slightly more flexible
#' dependence structures.
#' @param covars By default is NULL. May Contain the following elements of a list, to further specify
#' fixed variables (that are not subject to variable selection) or common effects (variables get the same effect,
#' independent of treatment). MUST contain the following elements, if not all variables are automatically
#' subjected to selection, and assumed to be able to have different effects on the target under treatment.
#' \begin{itemize}
#' \item 'x_fix': a vector of 0s and 1s with length of the number of variables in treatment selection model.
#' Any 1 will not be target of variable selection. Defaults to all 0s.
#' \item 'y_fix': a vector of 0s and 1s with length of the number of variables in the outcome models.
#' Any 1 will not be target of variable selection. Defaults to all 0s.
#' \item 'y_common': a vector of 0s and 1s with length equal to number of variables in the outcome models. If a 1 occurs, the
#' corresponding variable will be estimated with indifference to treatment and only have a common effect. Is automatically excluded
#' from variable selection.
#' \item 'y_nb': number of base parameters
#' \item 'y_np': number of parameters in the selection model
#' \end{itemize}
#' @param model_name String which names the model, defaults to "model1"
#' @param sort_data boolean which indicates whether the baseline data and panel data
#' should be organised by treatment and panel time. If the dataset is not yet sorted
#' this option may sort data in correct format.
#' @param mcmc_control a list of items controlling the mcmc parameters, see examples
#' @param control a list with some general control parameters, the most important is
#' control$sort_data which sorts the data for ids, treatment and panel times.
#' @param cov_y_common by default is NULL. If not NULL, has to be a vector of 0s and 1s with length
#' matching the number of covariates in panel matrix. For the covariates indexed with 1,
#' the model does not estimate different effects w.r.t. treatment, but assumes the
#' covariate has an overall effect on the different panel outcomes.
#' @param model_name a character vector to store in the result object, for an automated
#' creation of many objects in sequence, based on different models.
#' @param data_name a character vector to store in the result object, for an automated
#' creation of many objects in sequence, based on different data.
#'
#' There are 2 main objects necessary for computation of treatment effects, base_mat and panel_mat.
#' base_mat contains a dataframe at the baseline (panel time 0) with specific features for latent utility computation.
#' panel_mat is a dataframe containing information at panel times, including features that influence
#' the panel outcomes. The datasets have to have certain properties.
#' See example dataset for more information on how to prepare the dataset
#' accordingly. For the datasets, the function first sets a lot of parameters
#' influencing estimation and MCMC sampling process. For the time being this
#' package includes the functionality of the Shared Factor Model.
#' It may also be of interest to look at \code{\link{selectTreatmentSF}} to
#' see how the function works.
#'
#' @return For adequate input files, \code{bayesTrtEffects} returns output a list
#' object containing all coefficients of the model.
#'
#' @export

bayesTrtEffects <- function(base_mat, panel_mat, type = 'SF', covars = NULL,
                            mcmc_control = list(burnin = 1000, select = 500, M = 1000),
                            prior_control = list(var_sel = 5, var_fix = 0.1),
                            control = list(fix_alpha=FALSE, fix_beta=FALSE, fix_sigma=FALSE,
                                           fix_f=FALSE, sort_data=TRUE, test=FALSE),
                            model_name = "model1", data_name = "treatment dataset 1"){

  data_list <- readPanelUb(base_mat, panel_mat, type = type, covars = covars,
                           name = model_name, sort_data = control$sort_data, control_test = control$test,
                           data_name = data_name)
  data <- data_list$data; model <- data_list$model;
  rm("data_list")
  Tmax <- dim(data$start_x)[1]
  # Define variables subject to selection and starting values for indicators
  # always keep intercept
  model$deltax_fix <- c(1, data$cov_x_fix)
  # model$deltay_fix <- c(1, data$cov_y_fix[1:(model$dys-1)], 0, data$cov_y_fix[1:(model$dys-1)])
  model$deltay_fix <- c(1, data$cov_y_fix[data$cov_y_fix!=1], 0, data$cov_y_fix[data$cov_y_fix!=1],
                        data$cov_y_fix[data$cov_y_fix==1])
  if (model$type == "SF"){
    model$deltax_fix <- c(model$deltax_fix, 1)
    model$deltay_fix <- c(model$deltay_fix, rep(1, 2*Tmax))  # for SF model: no selection on factors
  }
  prior <- list()
  prior$m <- 0.001
  prior$type <- 'conjugate'
  prior$par$invB0 <- c(prior$m, 1/prior_control$var_sel * (1 - model$deltay_fix[2:model$dy]) + (1/prior_control$var_fix) * model$deltay_fix[2:model$dy])
  prior$par$invA0 <- 1/prior_control$var_sel * rep(1, model$dx)
  prior$model$ax <- 1
  prior$model$bx <- 1
  prior$model$ay <- 1
  prior$model$by <- 1
  # Prior for variance covariance parameters
  if (model$type == "SRF"){
    prior$lnsig$c0 <- matrix(0, Tmax,2)
    prior$lnsig$C0inv <- matrix(1,Tmax,2)
    prior$rho$C0inv <- matrix(1,Tmax,2)
    prior$rho$c0 <- matrix(0,Tmax,2)
    prior_invL0 <- matrix(1,(2*Tmax),1)
  }
  if (model$type == "SRI"){
    prior$lnsig$c0 <- matrix(0,Tmax,2)
    prior$lnsig$C0inv <- matrix(1,Tmax,2)
    prior$rho$C0inv <- matrix(1,Tmax,2)
    prior$rho$c0 <- matrix(0,Tmax,2)
    prior$d <- 3
    prior$D <- 1
  }
  if (model$type== "SF"){
    prior$par$invA0 <- c(prior$par$invA0,1)
    prior$invL0 <- rep(1,(Tmax*2))
    prior$s0 <- matrix(0,Tmax,2)
    prior$S0 <- matrix(0,Tmax,2)
    prior$model$al <- 1
    prior$model$bl <- 1
  }
  mcmc <- list()
  mcmc$burnin <- mcmc_control$burnin
  mcmc$M <- mcmc_control$M
  mcmc$start_select <- mcmc_control$select     # iteration at which variables are susceptible to selection
  if (mcmc$start_select < mcmc$burnin + mcmc$M){
    model$name <- paste0(model$name, '_select')
  }
  starttime <- Sys.time()
  mcmc$start <- list()

  if (model$type == "SF"){
    mcmc$start$deltax <- rep(1,model$dx + 1)
    mcmc$start$deltay <- rep(1,model$dy + 2*Tmax)
    mcmc_select <- selectTreatmentSF(data, model, prior, mcmc, control)
  }else{
    mcmc$start$deltax <- rep(1,model$dx)
    mcmc$start$deltay <- rep(1,model$dy)
    mcmc$start$lnsig <- mcmc$start$rho <- matrix(0, Tmax, 2)
    mcmc_select <- selectTreatmentSWR(data, model, prior, mcmc)
  }
  trt_effect <- comp_trt_effects(mcmc_select = mcmc_select)
  return(list(mcmc = mcmc_select, effects = trt_effect))
}

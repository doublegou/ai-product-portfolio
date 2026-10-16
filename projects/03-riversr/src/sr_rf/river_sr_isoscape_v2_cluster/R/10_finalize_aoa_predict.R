source("R/functions/core.R")
source("R/functions/modeling.R")
source("R/functions/predictor_sets.R")
check_packages(c("dplyr","readr","CAST"))
cfg <- read_config(); ensure_dirs(cfg)
dat <- read_model_table()
pred_path <- file.path(project_root(),cfg$predictors$prediction_file)
stop_missing(pred_path,
  "Provide hydrorivers_prediction_table.rds with one row per reach and the same predictor columns.")
newdata <- readRDS(pred_path)

ranked <- readr::read_csv(file.path(project_root(),"outputs/diagnostics/global_model_ranking.csv"),
                          show_col_types=FALSE)
sets <- resolve_predictor_sets(dat,cfg)
best_set <- ranked$predictor_set[[1]]
best_alg <- ranked$algorithm[[1]]
predictors <- sets[[best_set]]
missing_pred <- setdiff(predictors,names(newdata))
if(length(missing_pred)) stop("Prediction table is missing: ",paste(missing_pred,collapse=", "))

# Reuse the most frequently selected parameter combination from experiment B tuning.
tune <- readRDS(file.path(project_root(),"outputs/experiment_B/inner_tuning.rds")) |>
  dplyr::filter(predictor_set==best_set,algorithm==best_alg)
best_param_id <- tune |>
  dplyr::group_by(outer_fold,param_id) |>
  dplyr::summarise(rmse=mean(rmse,na.rm=TRUE),.groups="drop") |>
  dplyr::group_by(outer_fold) |>
  dplyr::slice_min(rmse,n=1,with_ties=FALSE) |>
  dplyr::count(param_id,sort=TRUE) |>
  dplyr::slice(1) |>
  dplyr::pull(param_id)
grid <- expand_model_grid(cfg,best_alg)
params <- as.list(grid[as.integer(sub("^p","",best_param_id)),,drop=FALSE])
fit <- fit_one_model(dat,predictors,cfg$project$outcome,best_alg,params,
                     threads=cfg$project$threads,seed=cfg$project$seed)
newdata$global_prediction <- predict(fit,newdata)

# Model-agnostic AOA with equal predictor weights. Replace CVtest with your preferred
# final spatial scheme when a different scheme is selected.
folds <- readRDS(file.path(project_root(),"data/processed/folds_long.rds"))
scheme <- unique(folds$scheme)[1]
cv <- folds |> dplyr::filter(scheme==!!scheme)
train_for_aoa <- dat |> dplyr::select(dplyr::all_of(predictors))
new_for_aoa <- newdata |> dplyr::select(dplyr::all_of(predictors))
aoa_obj <- CAST::aoa(
  newdata=new_for_aoa,
  train=train_for_aoa,
  variables=predictors,
  CVtest=cv$fold,
  useWeight=FALSE,
  LPD=TRUE
)
extract_aoa_vector <- function(x) {
  if (is.null(x)) return(NULL)
  if (is.data.frame(x) || is.matrix(x)) return(as.numeric(x[[1]]))
  as.numeric(x)
}
newdata$DI <- extract_aoa_vector(aoa_obj$DI)
newdata$AOA <- extract_aoa_vector(aoa_obj$AOA)
if(!is.null(aoa_obj$LPD)) newdata$LPD <- extract_aoa_vector(aoa_obj$LPD)

write_atomic_rds(newdata,file.path(project_root(),"outputs/final/hydrorivers_predictions.rds"))
write_csv_safe(newdata,file.path(project_root(),"outputs/final/hydrorivers_predictions.csv"))
saveRDS(fit,file.path(project_root(),"outputs/final/global_model.rds"))
saveRDS(aoa_obj,file.path(project_root(),"outputs/final/aoa_object.rds"))
log_msg("Final global prediction and AOA outputs written.")
log_msg("Expert correction and calibrated predictive bounds remain separate required steps.")

source("R/functions/core.R")
source("R/functions/metrics.R")
source("R/functions/modeling.R")
source("R/functions/predictor_sets.R")
check_packages(c("dplyr","ranger","Cubist"))
cfg <- read_config(); ensure_dirs(cfg)
dat <- read_model_table()
resid_path <- file.path(project_root(),"outputs/diagnostics/best_global_oof_residuals.rds")
stop_missing(resid_path, "Run stage 06.")
oof <- readRDS(resid_path)
sets <- resolve_predictor_sets(dat,cfg)
ranked <- readr::read_csv(file.path(project_root(),"outputs/diagnostics/global_model_ranking.csv"),
                          show_col_types=FALSE)
best_set <- ranked$predictor_set[[1]]
best_alg <- ranked$algorithm[[1]]
predictors <- sets[[best_set]]

base_folds <- readRDS(file.path(project_root(),"data/processed/folds_long.rds"))
first_scheme <- unique(base_folds$scheme)[1]
base_folds <- base_folds |>
  dplyr::filter(scheme == first_scheme) |>
  dplyr::select(row_id, expert_fold=fold)

# C1: case-weighted global model, evaluated with the same nested spatial CV engine.
weight_fun <- function(train) ifelse(train$sr87_sr86 >= cfg$selection$high_threshold,
                                     cfg$experts$high_case_weight, 1)
case_res <- run_nested_cv(dat, base_folds |> dplyr::rename(fold=expert_fold),
                          predictors, cfg$project$outcome, best_alg, cfg,
                          case_weight_fun=weight_fun, seed=cfg$project$seed+20000)
case_metrics <- metric_row(case_res$predictions$observed,case_res$predictions$predicted,
                           cfg$selection$high_threshold) |>
  dplyr::mutate(model="C1_case_weighted_global",algorithm=best_alg,predictor_set=best_set)
write_atomic_rds(case_res$predictions,file.path(project_root(),"outputs/experiment_C/C1_predictions.rds"))

# C2: cross-fitted environmental gate and residual expert.
gate_predictors <- unique(c(
  grep("^p1__",names(oof),value=TRUE),
  grep("^p3__",names(oof),value=TRUE)
))
if (length(gate_predictors) < 2) {
  warning("C2 skipped: need at least two p1__/p3__ gate predictors.")
  write_csv_safe(case_metrics,file.path(project_root(),"outputs/experiment_C/metrics_summary.csv"))
  quit(save="no",status=0)
}

expert_dat <- oof |>
  dplyr::left_join(base_folds,by="row_id") |>
  dplyr::filter(is.finite(residual), !is.na(expert_fold))

c2_parts <- list()
bundle_parts <- list()

for (f in sort(unique(expert_dat$expert_fold))) {
  tr <- expert_dat |> dplyr::filter(expert_fold != f)
  te <- expert_dat |> dplyr::filter(expert_fold == f)

  gate_prep <- numeric_matrix_fit(tr,gate_predictors)
  gate_y <- factor(tr$observed >= cfg$selection$high_threshold,
                   levels=c(FALSE,TRUE),labels=c("low","high"))
  if (length(unique(gate_y)) < 2) {
    warning("C2 fold ",f," skipped: gate training data contain one class.")
    next
  }
  gate <- ranger::ranger(
    x=as.data.frame(gate_prep$x), y=gate_y, probability=TRUE,
    num.trees=1000, seed=cfg$project$seed+f, num.threads=cfg$project$threads
  )
  p_train <- predict(gate,data=as.data.frame(gate_prep$x))$predictions[,"high"]
  p_test <- predict(gate,data=as.data.frame(numeric_matrix_apply(te,gate_prep)))$predictions[,"high"]

  expert_cut <- stats::quantile(p_train,0.60,na.rm=TRUE)
  keep <- p_train >= expert_cut
  if (sum(keep) < cfg$experts$minimum_expert_rows) {
    warning("C2 fold ",f," skipped: insufficient residual-expert rows.")
    next
  }

  expert_prep <- numeric_matrix_fit(tr[keep,,drop=FALSE],gate_predictors)
  expert <- Cubist::cubist(
    x=as.data.frame(expert_prep$x),
    y=tr$residual[keep],
    committees=20,
    weights=1+p_train[keep]
  )
  corr_train <- as.numeric(predict(
    expert,
    newdata=as.data.frame(numeric_matrix_apply(tr,expert_prep)),
    neighbors=5
  ))
  corr_test <- as.numeric(predict(
    expert,
    newdata=as.data.frame(numeric_matrix_apply(te,expert_prep)),
    neighbors=5
  ))

  z <- p_train*corr_train
  denom <- sum(z^2,na.rm=TRUE)
  alpha <- if (denom > 0) sum(z*tr$residual,na.rm=TRUE)/denom else 0
  alpha <- max(0,min(1,alpha))

  c2_parts[[length(c2_parts)+1L]] <- te |>
    dplyr::transmute(
      row_id, observed, global_prediction=predicted,
      p_high=p_test, expert_correction=alpha*corr_test,
      predicted=predicted+p_test*alpha*corr_test,
      expert_fold=f, alpha=alpha
    )
  bundle_parts[[as.character(f)]] <- list(
    gate=gate,gate_prep=gate_prep,expert=expert,expert_prep=expert_prep,
    alpha=alpha,gate_predictors=gate_predictors
  )
}

c2_pred <- dplyr::bind_rows(c2_parts)
if (!nrow(c2_pred)) {
  warning("C2 produced no cross-fitted predictions.")
  write_csv_safe(case_metrics,file.path(project_root(),"outputs/experiment_C/metrics_summary.csv"))
  quit(save="no",status=0)
}
c2_metrics <- metric_row(c2_pred$observed,c2_pred$predicted,cfg$selection$high_threshold) |>
  dplyr::mutate(model="C2_crossfitted_gate_residual_expert",
                algorithm="RF gate + Cubist residual",predictor_set=best_set)
write_atomic_rds(c2_pred,file.path(project_root(),"outputs/experiment_C/C2_predictions.rds"))
write_csv_safe(dplyr::bind_rows(case_metrics,c2_metrics),
               file.path(project_root(),"outputs/experiment_C/metrics_summary.csv"))
saveRDS(bundle_parts,file.path(project_root(),"outputs/experiment_C/C2_crossfit_bundles.rds"))
log_msg("Experiment C complete. C2 uses held-out expert folds and OOF global residuals.")

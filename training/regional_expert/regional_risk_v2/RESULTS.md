# Regional Risk V2 — Final Result

## Final status

`NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE`

The frozen forward experiment completed successfully. All four prespecified candidates failed the complete Regional Risk V2 Gate under strict Nested Leave-One-Branch-Out validation. The experiment therefore stops without fitting a full-data model or creating a release.

## Gate result

Gate qualification used branch-sqrt-weighted metrics. A candidate had to meet all five criteria simultaneously: background FPR no greater than 10%, Recall at least 60%, Precision at least 30%, at least 9/14 positive branches detected and at least 2/4 extreme systems detected.

| Candidate | Background FPR | Recall | Precision | Positive branches | Extreme systems | Gate |
|---|---:|---:|---:|---:|---:|---|
| Probability RF — Full50 | **6.02%** | **45.54%** | **48.22%** | **6/14** | **2/4** | Fail |
| Probability RF — Full50 + Process14 | 6.07% | 38.12% | 40.89% | 6/14 | 1/4 | Fail |
| Shallow boosting — Full50 | 10.014% | 34.62% | 33.18% | 5/14 | 2/4 | Fail |
| Shallow boosting — Full50 + Process14 | 9.93% | 31.57% | 30.01% | 4/14 | 2/4 | Fail |

Probability RF with Full50 was closest to the Gate. It met the FPR, Precision and extreme-system criteria, but remained 14.46 percentage points below the Recall target and detected only 6 rather than 9 positive branches. Shallow boosting with Full50 rounds to 10.0% FPR in the compact decision table, but its exact weighted Outer FPR is 10.0137% and therefore exceeds the frozen cap.

## Ranking diagnostics

| Candidate | AP | AUROC | Weighted Brier | Weighted log loss |
|---|---:|---:|---:|---:|
| Probability RF — Full50 | 0.3491 | 0.6435 | 0.1648 | 0.5367 |
| Probability RF — Full50 + Process14 | 0.3293 | 0.6359 | 0.1664 | 0.5431 |
| Shallow boosting — Full50 | **0.4025** | **0.6968** | **0.1574** | **0.5079** |
| Shallow boosting — Full50 + Process14 | 0.3629 | 0.6763 | 0.1649 | 0.5316 |

Shallow boosting with Full50 gave the best station-level ranking and probability diagnostics, but a worse operational Gate than Probability RF. This directly demonstrates why pooled ranking quality cannot substitute for the predefined cross-branch Gate.

## Process14 assessment

Process14 did not add transferable predictive value in this run.

- With Probability RF, Process14 reduced Recall by 7.42 percentage points and Precision by 7.33 points, left positive-branch detection at 6/14, and reduced extreme-system detection from 2/4 to 1/4.
- With shallow boosting, Process14 reduced Recall by 3.05 points and Precision by 3.17 points, and reduced positive-branch detection from 5/14 to 4/14.
- AP, AUROC, Brier and log loss also worsened for both algorithms after Process14 was added.

The process features were used by the learners, especially the specific-discharge, upstream-to-local-area and relative-downstream-position proxies, but that use did not improve unseen-branch transfer. Because Process14 is constructed from existing regional inputs, this result does not show that hydrologic or geologic processes are irrelevant. It shows that these particular deterministic process representations do not resolve the missing-information problem.

## Cross-branch failure pattern

Probability RF with Full50 triggered 37/80 positive stations but detected positives in only 6/14 positive branches. Its detected positive branches were 001, 003, 004, 014, 015 and 016. The other eight positive branches had no high-Sr hit. Across the four extreme systems, only branches 003 and 015 were detected; branches 008 and 009 were entirely missed.

The evidence therefore supports a transferable signal concentrated in a minority of systems, not a unified decision boundary covering most high-Sr branches.

## Scientific conclusion and stopping rule

Increasing nonlinear capacity from the earlier GAM setting to fixed Probability RF and shallow boosting did not produce a Regional Risk Gate. Adding the frozen Process14 representation also did not solve the transfer problem. The evidence does not establish that all algorithms or all possible process measurements must fail; it rejects the two tested explanations within the frozen V2 scope.

The remaining explanation is more consistent with insufficient regional input information, mechanism heterogeneity among high-Sr branches, or both. New work would require genuinely new source/process evidence or an explicitly heterogeneous mechanism design, not further tuning of the current RF, boosting, Full50 or Process14 combinations.

The V2 stop rule is now active: preserve this experiment and do not tune its learners, thresholds or features against the observed Outer results. Any failure audit is a separate read-only downstream analysis.

## Forward-reproduction scope

The primary reproduction endpoint was the complete Gate decision. That endpoint agrees with the recovered V2 conclusion: no candidate supports a transferable Regional Risk Gate, branch coverage remains the central failure, and no deployment is authorized.

The secondary Process14 direction is not identical to the recovered narrative. The recovered account described a possible ranking improvement without broader branch coverage, whereas this forward run found no ranking improvement. The durable conclusion must follow the present frozen outputs: Process14 did not improve either ranking or Gate transfer here. This difference does not affect the primary Gate decision.

## Provenance and completeness

- Source Git commit: `5744bdc4e7d18f17ffbd02b421023cf9ea60d95d`
- Run ID: `regional_risk_v2_20260817_r1`
- Slurm jobs: check `66358`; 68-task array `66359`; aggregate `66360`
- Completion: 68/68 tasks, 1,156/1,156 model fits, 68/68 thresholds
- Formal Outer OOF: 1,488 rows; 372 unique stations for each of four candidates
- Outer branch present in Inner OOF: `false` for all tasks
- Calibration: `none`
- Data MD5: `174ee6a20b8b29149259730b6e17e738`
- Config MD5: `7e654e36cca4166b118dab7343f76609`
- Fold manifest MD5: `9ab7151edfade7b7dae37cb066ea4c9e`
- Full-data model fitted: `false`
- Release created: `false`
- Archive: `regional_risk_v2_regional_risk_v2_20260817_r1.tar.gz`
- Archive size: `2,082,737` bytes
- Archive SHA-256: `94dc9a8e41457ff90778656fd569ccfa47538d5d345653af0a92397bd0e6f699`

The checked archive retains all task-level predictions, thresholds, diagnostics and scheduler logs. The versioned top-level validation files are the compact formal evidence for the final conclusion.

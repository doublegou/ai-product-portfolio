# Regional Risk V2 — Final Result

## Final status

`NO_CANDIDATE_MET_COMPLETE_REGIONAL_GATE`

The frozen forward experiment completed successfully. All four prespecified candidates failed the complete Regional Risk V2 Gate under strict Nested Leave-One-Branch-Out validation. The experiment therefore stops without fitting a full-data model or creating a release.

## Gate result

Gate qualification used branch-sqrt-weighted metrics. A candidate had to meet all five criteria simultaneously: background FPR no greater than 10%, Recall at least 60%, Precision at least 30%, at least 9/14 positive branches detected and at least 2/4 extreme systems detected.

| Candidate | Background FPR | Recall | Precision | Positive branches | Extreme systems | Gate |
|---|---:|---:|---:|---:|---:|---|
| Probability RF — Full50 | **6.96%** | **45.54%** | **45.78%** | **6/14** | **2/4** | Fail |
| Probability RF — Full50 + Process14 | 7.11% | 38.12% | 40.77% | 6/14 | 1/4 | Fail |
| Shallow boosting — Full50 | 7.96% | 34.66% | 34.03% | 5/14 | 2/4 | Fail |
| Shallow boosting — Full50 + Process14 | 10.94% | 34.28% | 32.44% | 4/14 | 2/4 | Fail |

Probability RF with Full50 was closest to the Gate. It met the FPR, Precision and extreme-system criteria, but remained 14.46 percentage points below the Recall target and detected only 6 rather than 9 positive branches. Shallow boosting with Full50 now remains below the FPR cap, whereas shallow boosting with Process14 has an exact weighted Outer FPR of 10.9417% and exceeds it. Neither change resolves the Recall or positive-branch-coverage failure.

## Corrected-data retraining comparison

The corrected run preserves the previous and recovered historical decision: no candidate meets the complete Regional Risk Gate, Probability RF with Full50 remains closest, and branch coverage remains the central failure. Relative to the immediately preceding run, RF Full50 Recall and branch coverage are unchanged; weighted FPR rises from 6.02% to 6.96% and Precision falls from 48.22% to 45.78%. Shallow boosting Full50 improves FPR from 10.01% to 7.96% while Recall and branch coverage remain essentially unchanged. These shifts do not cross the complete Gate boundary.

## Ranking diagnostics

| Candidate | AP | AUROC | Weighted Brier | Weighted log loss |
|---|---:|---:|---:|---:|
| Probability RF — Full50 | 0.3427 | 0.6364 | 0.1660 | 0.5409 |
| Probability RF — Full50 + Process14 | 0.3256 | 0.6321 | 0.1677 | 0.5465 |
| Shallow boosting — Full50 | **0.3993** | **0.6923** | **0.1577** | **0.5112** |
| Shallow boosting — Full50 + Process14 | 0.3717 | 0.6766 | 0.1641 | 0.5298 |

Shallow boosting with Full50 gave the best station-level ranking and probability diagnostics, but a worse operational Gate than Probability RF. This directly demonstrates why pooled ranking quality cannot substitute for the predefined cross-branch Gate.

## Process14 assessment

Process14 did not add transferable predictive value in this run.

- With Probability RF, Process14 reduced Recall by 7.42 percentage points and Precision by 5.00 points, left positive-branch detection at 6/14, and reduced extreme-system detection from 2/4 to 1/4.
- With shallow boosting, Process14 reduced Recall by 0.38 points and Precision by 1.59 points, and reduced positive-branch detection from 5/14 to 4/14.
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

- Source Git commit: `36ad60251c939a02786ad7ae7ce8d13d5dc74fde`
- Run ID: `regional_risk_v2_20260817_corrected_r3`
- Slurm jobs: check `66847`; 68-task array `66848`; aggregate `66849`
- Completion: 68/68 tasks, 1,156/1,156 model fits, 68/68 thresholds
- Formal Outer OOF: 1,488 rows; 372 unique stations for each of four candidates
- Outer branch present in Inner OOF: `false` for all tasks
- Calibration: `none`
- Data MD5: `889ab17f9cb72efd63580807f845d700`
- Config MD5: `5005ba03fecfc2904d9c2b55178f561d`
- Fold manifest MD5: `2b0b48381014cf9d441e0060acde7cb4`
- Full-data model fitted: `false`
- Release created: `false`
- Archive: `regional_risk_v2_regional_risk_v2_20260817_corrected_r3.tar.gz`
- Archive size: `2,083,266` bytes
- Archive SHA-256: `8d867c458fc9550cde988cd47bfe0e868ac7f61231ac757a7f2b21050b9bd0b1`

The checked archive retains all task-level predictions, thresholds, diagnostics and scheduler logs. The first two corrected-data submission attempts stopped at the engineering check before any model fit because of a compute-node `libstdc++` load-order conflict; the dependency order was fixed without changing the statistical method, and the formal r3 chain then completed cleanly. The versioned top-level validation files are the compact formal evidence for the final conclusion.

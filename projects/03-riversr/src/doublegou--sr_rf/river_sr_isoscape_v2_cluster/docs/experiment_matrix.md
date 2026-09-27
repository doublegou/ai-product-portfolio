# Experiment matrix

## A — predictor architecture

- A0: `p0__`
- A1: `p0__ + p1__`
- A2 area: A1 + `p2a__`
- A3 runoff: A1 + `p2q__`
- A4 area + hydrogeology: A2 + `p3__`
- A4 runoff + hydrogeology: A3 + `p3__`

Algorithms: RF and Cubist.

## B — algorithm comparison

Use the two best predictor sets from A.

Algorithms:

- RF
- XGBoost
- Cubist
- Local Linear Forest

## C — high-value handling

- C0: best global model from B
- C1: high-value case-weighted global model
- C2: environmental gate × residual expert
- C3/C4: only after `south_tibet_flag` and basin groups are supplied

## D — hydrogeological non-stationarity

Diagnose OOF residuals first. An expert is eligible only if it has enough independent rows, sites and references. Final acceptance still requires leave-basin-out evaluation.

## E — physical upstream weighting

- E0: area weighting
- E1: runoff weighting
- E2: Sr-flux weighting, only after concentration-unit verification

## Validation

- Nested spatial CV
- Outer block schemes: 500, 1000 and 1500 km
- Leave-reference-group-out
- Tail diagnostics at 0.718, 0.720 and 0.722
- Overall, top-10%, top-5% and ≥0.720 metrics

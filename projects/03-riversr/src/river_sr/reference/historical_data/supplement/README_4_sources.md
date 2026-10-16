# Observation supplement for Base Model V2

`observations_supplement_v2.csv` is the single supplementary river/stream-water table collected in this search pass. It contains 1,596 rows from four public sources and is intended to be reviewed/deduplicated against `../observations.xlsx` before Base Model V2 training.

## What is included

| Source | Rows | Main value for V2 |
|---|---:|---|
| Kobbefjord, Greenland (Pain et al., 2025) | 39 | All >=0.75; 38 >=0.80; discharge, major ions, tributary/station IDs, and paired stream-sediment Sr ratios |
| Amazon surface waters (de Almeida Mereles et al., 2025) | 205 | Full supplementary table; 15 rows are new measurements from the study, including Aracá at 0.7721 |
| USGS national US water compilation (Hudson et al., 2025) | 1,166 | River/stream subset only; 66 observations are >=0.72 and <0.75, improving the transition range and US spatial coverage |
| Ganga floodplain and Nepal rivers (Bickle et al., 2018) | 186 | Targeted >=0.72 subset from Electronic Annex Table E1; 17 observations are 0.75–<0.80, with Sr concentration, major ions, temperature, stable isotopes, and exact coordinates |

Combined Sr bands:

- `<0.72`: 1,256 rows
- `0.72–<0.75`: 283 rows
- `0.75–<0.80`: 19 rows
- `>=0.80`: 38 rows

The `possible_existing_match` field is a first-pass duplicate flag. The original three sources were screened by latitude/longitude rounded to four decimals plus `87Sr/86Sr` rounded to six decimals; the Ganga source was additionally screened by original sample ID. Ten rows are currently flagged. This is only a screening flag, not the final deduplication key.

## Sources

1. Pain, A.; Martin, J.; Martin, E. (2025), *Biogeochemistry of streams draining to Kobbefjord, Greenland, 2019*. Arctic Data Center, DOI `10.18739/A2ZK55P2M`, CC0 1.0. Article DOI `10.1038/s43247-025-02404-z`. Source: <https://arcticdata.io/catalog/view/doi:10.18739/A2ZK55P2M>
2. de Almeida Mereles et al. (2025), *Distribution of strontium isotopes (87Sr/86Sr) in surface waters of the Amazon basin: A basis for studies on provenance*. DOI `10.1016/j.scitotenv.2025.178630`. Associated Mendeley dataset DOI `10.17632/5fdn3s9k8p.1`, CC BY 4.0. Source: <https://www.sciencedirect.com/science/article/pii/S0048969725002645>
3. Hudson et al. (2025), *National-scale dataset of strontium isotope compositions in environmental materials for the United States*. USGS DOI `10.5066/P13JVROU`, CC0 1.0. Source: <https://www.usgs.gov/data/national-scale-dataset-strontium-isotope-compositions-environmental-materials-united-states>
4. Bickle et al. (2018), *Chemical weathering outputs from the flood plain of the Ganga*. Article DOI `10.1016/j.gca.2018.01.003`; Cambridge repository DOI `10.17863/CAM.21128`, CC BY 4.0. Source: <https://www.repository.cam.ac.uk/items/eb85408c-01f1-4cf0-a9d4-e42f7be2b1da>

## Normalization notes

- Only USGS records explicitly labelled `Stream/River` or `River Stream` are included. Their maximum is `0.740407`. The previously quoted `0.7471` was the maximum across broader USGS water media, not the river/stream subset.
- Amazon X/Y values were converted to WGS84 longitude/latitude using the custom Albers Equal Area definition embedded in the associated GeoTIFF. Original X/Y and CRS are retained.
- Kobbefjord `QSout` has a source latitude typo (`61.14854`). It is corrected to `64.14854` using the repository's authoritative geographic bounds and flagged in `notes`.
- For the Ganga source, only observations at or above `0.72` were retained. Source Sr concentrations in nmol/L were converted to ppm using the Sr molar mass (87.62 g/mol), major ions in µmol/L were converted to mmol/L, and the reported 1-sigma ratio error in ppm was converted to an absolute ratio uncertainty.
- Blank fields mean the source did not provide that variable; no values were imputed.

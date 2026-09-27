# Observation supplement for Base Model V2

`observations_supplement_v2.csv` is the single normalized supplementary river/stream-water table for Base Model V2. As of 2026-08-12 it contains 1,950 observation records from nine public sources. Records with defensible coordinates and measured river-water `87Sr/86Sr` can enter the standard observation-to-site pipeline; `possible_existing_match` marks records held out as possible duplicates of the original observation table.

## Included sources

| Source | Observation records | Unique 5-decimal sites | Main value for V2 |
|---|---:|---:|---|
| Kobbefjord, Greenland (Pain et al., 2025) | 39 | — | High-Sr source; 38 records are >=0.80, with discharge, chemistry, tributary/station identity, and paired stream-sediment Sr ratios |
| Amazon surface waters (de Almeida Mereles et al., 2025) | 205 | — | Full public supplementary table; includes Aracá at 0.7721 |
| USGS United States water compilation (Hudson et al., 2025) | 1,166 | — | River/stream subset; adds transition-range observations and broad US coverage |
| Ganga floodplain and Nepal rivers (Bickle et al., 2018) | 186 | — | Targeted >=0.72 subset with Sr concentration, major ions, temperature, stable isotopes, and coordinates |
| Nagara River, Japan (Ida et al., 2025) | 115 | 115 | Observed river-water Table S1 with coordinates and Sr concentration |
| Mur River, Austria/Slovenia (Moser et al., 2026) | 166 | 79 | Repeat mainstem/tributary sampling with coordinates, Sr concentration, uncertainty, temperature, and major elements |
| Mulanxi River, China (Su et al., 2026) | 16 | 16 | Coordinate-resolved river-water subset with reported ratios, uncertainty, Sr concentration, and major ions; groundwater and sediment were excluded |
| Erren River, Taiwan (Chung et al., 2026) | 15 | 15 | Coordinate-resolved mainstem/tributary river-water observations transcribed from article Tables 1 and 3 |
| Panguingue Creek, Alaska (Roux et al., 2026) | 42 | 1 | Public supplementary table with repeated seasonal samples, Sr concentration, uncertainty, temperature, DOC, and stable water isotopes |

The 354 records added in the 2026-08-12 pass aggregate to 226 new sites. They do not duplicate an original or existing supplementary record under the screening key of coordinates rounded to five decimals plus `87Sr/86Sr` rounded to six decimals.

Combined observation-record Sr bands:

- `<0.72`: 1,610 records
- `0.72–<0.75`: 283 records
- `0.75–<0.80`: 19 records
- `>=0.80`: 38 records

The new 354-record pass is entirely below 0.72 (range 0.70726148–0.718111735). It improves independent-basin, mainstem/tributary, and seasonal coverage but does not add high-Sr training examples. The existing high-Sr counts therefore remain unchanged.

## Public-data status of screened 2025–2026 papers

“Public” was treated as three different cases: a downloadable point table that is directly trainable; a public supplement that lacks a required training key; or a paper with no public point dataset. A paper was not converted into a training record unless the measured water value could be tied to a defensible sample coordinate.

| Paper/data source | Public status found | Decision and reason |
|---|---|---|
| Ida et al. (2025), Nagara River, DOI `10.1007/s10201-025-00787-8` | Publisher XLSX is publicly downloadable | Included: measured Table S1 contains point IDs, coordinates, Sr concentrations, ratios, and sampling dates. Estimated reach tables were excluded. |
| Moser et al. (2026), Mur River, DOI `10.1007/s00027-025-01253-4` | Public publisher XLSX; article is CC BY 4.0 | Included: the ESI contains coordinate-resolved individual river samples. |
| Su et al. (2026), Mulanxi River, DOI `10.1016/j.chemgeo.2026.123289` | Publisher DOCX is publicly downloadable | Included only river-water rows with finite `87Sr/86Sr` and coordinates. Rows reported as `n.a.`, groundwater, suspended sediment, and bed sediment were excluded. |
| Chung et al. (2026), Erren River, DOI `10.3390/w18030368` | Open-access CC BY 4.0 article; required values and coordinates are in main-paper tables | Included: 15 river-water sites were transcribed and cross-checked between Tables 1 and 3. |
| Roux et al. (2026), Panguingue Creek, DOI `10.1016/j.chemgeo.2026.123427` | Full article is publicly downloadable from the UCLouvain repository, and publisher Supplementary Table S2 is a public XLSX | Included: 42 seasonal stream-water records. Spring/Summer/Autumn use the reported primary-site coordinate; four Winter samples collected about 100 m upstream are assigned to the same site and explicitly noted. |
| Zhang et al. (2025), Upper Mekong/Lancang, DOI `10.1021/acs.est.4c12202` | ACS Figshare SI PDF is public under CC BY-NC 4.0 and contains 45 sample values | Not included: the SI table does not provide sample-wise longitude/latitude. Coordinates cannot be recovered accurately enough from the sampling map to assign catchment Full50 features. |
| Ma et al. (2025), Bailong River, DOI `10.1016/j.chemgeo.2025.122854` | Publisher XLSX supplement is public | Not included: the available tables are derived/endmember and weathering summaries, not a complete raw river-water table that jointly supplies exact sample coordinates and measured `87Sr/86Sr`. |
| Hao & Li (2026), Chinese Loess Plateau, DOI `10.1016/j.palaeo.2026.113687` | Article metadata was found, but no public point-level SI or repository dataset was discoverable | Not included: no downloadable sample table with measured ratios and coordinates was found in this search pass. |
| Zhang et al. (2025), Yongding–Chaobai river system, DOI `10.1016/j.watres.2025.123402` | The paper states that data are available on request | Not included: “available on request” is not a public downloadable point dataset, and no coordinate-resolved table was found. |

These statuses describe what was publicly discoverable on 2026-08-12. The three “not public” cases could still become usable if authors provide the coordinate-resolved tables. The two public-but-incomplete supplements can also be retained for mechanism interpretation, but they are not safe inputs to the spatial training table as published.

## Source references

1. Pain, A.; Martin, J.; Martin, E. (2025), *Biogeochemistry of streams draining to Kobbefjord, Greenland, 2019*. Arctic Data Center DOI `10.18739/A2ZK55P2M`, CC0 1.0. Article DOI `10.1038/s43247-025-02404-z`. <https://arcticdata.io/catalog/view/doi:10.18739/A2ZK55P2M>
2. de Almeida Mereles et al. (2025), *Distribution of strontium isotopes (87Sr/86Sr) in surface waters of the Amazon basin: A basis for studies on provenance*. Article DOI `10.1016/j.scitotenv.2025.178630`; Mendeley dataset DOI `10.17632/5fdn3s9k8p.1`, CC BY 4.0. <https://www.sciencedirect.com/science/article/pii/S0048969725002645>
3. Hudson et al. (2025), *National-scale dataset of strontium isotope compositions in environmental materials for the United States*. USGS DOI `10.5066/P13JVROU`, CC0 1.0. <https://www.usgs.gov/data/national-scale-dataset-strontium-isotope-compositions-environmental-materials-united-states>
4. Bickle et al. (2018), *Chemical weathering outputs from the flood plain of the Ganga*. Article DOI `10.1016/j.gca.2018.01.003`; Cambridge repository DOI `10.17863/CAM.21128`, CC BY 4.0. <https://www.repository.cam.ac.uk/items/eb85408c-01f1-4cf0-a9d4-e42f7be2b1da>
5. Ida et al. (2025), Nagara River, DOI `10.1007/s10201-025-00787-8`. <https://link.springer.com/article/10.1007/s10201-025-00787-8>
6. Moser et al. (2026), Mur River, DOI `10.1007/s00027-025-01253-4`, CC BY 4.0. <https://link.springer.com/article/10.1007/s00027-025-01253-4>
7. Su et al. (2026), Mulanxi River, DOI `10.1016/j.chemgeo.2026.123289`. <https://www.sciencedirect.com/science/article/pii/S0009254126000586>
8. Chung et al. (2026), Erren River, DOI `10.3390/w18030368`, CC BY 4.0. <https://www.mdpi.com/2073-4441/18/3/368>
9. Roux et al. (2026), Panguingue Creek, DOI `10.1016/j.chemgeo.2026.123427`. <https://research.dial.uclouvain.be/entities/publication/48b7e370-d403-42b7-ac4a-b5bb79b6a28b>
10. Zhang et al. (2025), Upper Mekong SI. <https://acs.figshare.com/articles/journal_contribution/Bayesian_Model_Revealing_Segment-Scale_Elemental_Flux_Doubled_CO_sub_2_sub_Consumption_and_Potential_Anthropogenic_Impact_in_the_Upper_Mekong_Basin_Constraints_from_Strontium_Isotopes/29115326>

## Normalization and QC notes

- Site IDs downstream are formed from longitude and latitude rounded to five decimal places. Measurements at the same site are aggregated using the median `87Sr/86Sr`; observation dates remain in this raw supplement but are not treated as separate training sites.
- The `possible_existing_match` screen uses rounded coordinates and ratio; ten pre-existing supplement records remain flagged. No newly added record was flagged.
- Only USGS records explicitly labelled `Stream/River` or `River Stream` are included. Their maximum is `0.740407`; the broader water-media maximum is not used as a river observation.
- Amazon X/Y values were converted to WGS84 longitude/latitude using the custom Albers Equal Area definition embedded in the associated GeoTIFF. Original X/Y and CRS are retained.
- Kobbefjord `QSout` has a source latitude typo (`61.14854`). It is corrected to `64.14854` using the repository's geographic bounds and flagged in `notes`.
- For the Ganga source, only observations at or above `0.72` were retained. Sr in nmol/L was converted to ppm using 87.62 g/mol, major ions from µmol/L to mmol/L, and the reported 1-sigma ratio error in ppm to absolute ratio uncertainty.
- Nagara source coordinate headers are reversed relative to their numeric values; the normalized table assigns 136.x as longitude and 35.x as latitude.
- Mur Sr and major-element concentrations were converted from µg/L; reported isotope uncertainty is `U(k=2)`.
- Mulanxi Sr was converted from µmol/L to ppm using 87.62 g/mol; major ions were converted from µmol/L to mmol/L.
- Erren sampling occurred in July 2021, but the exact day is not reported; `sample_date` is therefore stored as `2021-07` rather than an invented day.
- Panguingue Sr was converted from µg/L to ppm and DOC from mg C/L to µmol C/L. The source reports the primary site as 63.90° N, 149.09° W; Winter sampling was approximately 100 m upstream, within the pipeline's 100 m site tolerance, and is aggregated with the primary site.
- Blank fields mean the source did not report the variable; no values were imputed.

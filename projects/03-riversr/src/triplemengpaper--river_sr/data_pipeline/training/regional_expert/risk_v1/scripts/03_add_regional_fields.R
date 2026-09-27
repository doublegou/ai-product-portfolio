regional_data_add_fields <- function(dat, context) {
  cfg <- context$config
  lon <- as.numeric(dat[[cfg$columns$longitude]])
  lat <- as.numeric(dat[[cfg$columns$latitude]])
  regional_data_assert(all(is.finite(lon)) && all(is.finite(lat)), "Regional coordinates are incomplete.")
  points <- sf::st_as_sf(data.frame(longitude = lon, latitude = lat), coords = c("longitude", "latitude"), crs = 4326)
  projected <- sf::st_transform(points, crs = as.character(cfg$projection$proj4))
  xy <- sf::st_coordinates(projected) / 1000
  dat[[cfg$projection$x_column]] <- as.numeric(xy[, 1L])
  dat[[cfg$projection$y_column]] <- as.numeric(xy[, 2L])
  observed <- as.numeric(dat[[cfg$columns$response]])
  regional_data_assert(all(is.finite(observed)), "Regional Sr response is incomplete.")
  dat$high_sr_label <- as.integer(observed >= as.numeric(cfg$domain$positive_lower))
  dat
}

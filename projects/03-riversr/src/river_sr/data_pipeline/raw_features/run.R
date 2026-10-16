file_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(file_arg) != 1L) {
  stop("Run this file with Rscript.", call. = FALSE)
}
script_path <- normalizePath(sub("^--file=", "", file_arg), mustWork = TRUE)
project_dir <- dirname(script_path)
repo_root <- project_dir
repeat {
  if (file.exists(file.path(repo_root, "env", "activate.R"))) break
  parent <- dirname(repo_root)
  if (identical(parent, repo_root)) stop("Cannot find the RiverSR repository root.", call. = FALSE)
  repo_root <- parent
}
repo_root <- normalizePath(repo_root, mustWork = TRUE)
source(file.path(repo_root, "env", "activate.R"), local = TRUE)
river_sr_activate(repo_root)
river_sr_assert <- function(condition, message) {
  if (!isTRUE(condition)) stop(message, call. = FALSE)
}

source_config_path <- file.path(project_dir, "config", "sources.yml")
source_config <- yaml::read_yaml(source_config_path)
raw_root <- file.path(repo_root, source_config$root)
dir.create(raw_root, recursive = TRUE, showWarnings = FALSE)

download_proxy <- Sys.getenv("RIVER_SR_DOWNLOAD_PROXY", unset = "")
if (!nzchar(download_proxy) && identical(.Platform$OS.type, "windows")) {
  internet_settings <- suppressWarnings(tryCatch(
    utils::readRegistry(
      "Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings",
      hive = "HCU"
    ),
    error = function(condition) NULL
  ))
  if (
    is.list(internet_settings) &&
      identical(as.integer(internet_settings$ProxyEnable), 1L) &&
      length(internet_settings$ProxyServer) == 1L
  ) {
    download_proxy <- internet_settings$ProxyServer
  }
}
if (nzchar(download_proxy) && grepl("=", download_proxy, fixed = TRUE)) {
  proxy_parts <- strsplit(download_proxy, ";", fixed = TRUE)[[1L]]
  proxy_values <- strsplit(proxy_parts, "=", fixed = TRUE)
  proxy_keys <- vapply(proxy_values, `[`, character(1L), 1L)
  proxy_hosts <- vapply(proxy_values, function(value) paste(value[-1L], collapse = "="), character(1L))
  preferred <- match(c("https", "http"), tolower(proxy_keys), nomatch = 0L)
  preferred <- preferred[preferred > 0L]
  download_proxy <- if (length(preferred) > 0L) proxy_hosts[preferred[1L]] else ""
}
if (nzchar(download_proxy) && !grepl("^[a-z]+://", download_proxy, ignore.case = TRUE)) {
  download_proxy <- paste0("http://", download_proxy)
}

download_one <- function(source) {
  destination <- file.path(raw_root, source$path)
  dir.create(dirname(destination), recursive = TRUE, showWarnings = FALSE)
  used_url <- source$url

  if (!file.exists(destination)) {
    partial <- paste0(destination, ".part")
    urls <- c(source$url, unlist(source$fallback_urls, use.names = FALSE))
    status <- 1L
    for (url in urls) {
      message("Downloading ", source$id, " from ", url)
      curl <- Sys.which("curl")
      status <- if (nzchar(curl)) {
        curl_args <- c(
          if (nzchar(download_proxy)) c("--proxy", shQuote(download_proxy)),
          "--fail", "--location", "--retry", "1",
          "--connect-timeout", "20", "--continue-at", "-",
          "--output", shQuote(partial), shQuote(url)
        )
        system2(
          curl,
          args = curl_args
        )
      } else {
        tryCatch(
          utils::download.file(
            url,
            destfile = partial,
            mode = "wb",
            method = "libcurl",
            quiet = FALSE
          ),
          error = function(condition) 1L
        )
      }
      if (identical(status, 0L)) {
        used_url <- url
        break
      }
      if (file.exists(partial)) {
        unlink(partial)
      }
    }
    river_sr_assert(identical(status, 0L), paste("Download failed:", source$id))
    river_sr_assert(file.rename(partial, destination), paste("Could not finalize:", destination))
  } else {
    message("Already downloaded: ", source$id)
  }

  if (!is.null(source$expected_bytes)) {
    river_sr_assert(
      identical(as.numeric(file.info(destination)$size), as.numeric(source$expected_bytes)),
      paste("File-size mismatch:", source$id)
    )
  }

  if (!is.null(source$md5)) {
    actual_md5 <- unname(tools::md5sum(destination))
    river_sr_assert(
      identical(tolower(actual_md5), tolower(source$md5)),
      paste("MD5 mismatch:", source$id)
    )
  }
  actual_sha256 <- digest::digest(file = destination, algo = "sha256", serialize = FALSE)
  if (!is.null(source$sha256)) {
    river_sr_assert(
      identical(tolower(actual_sha256), tolower(source$sha256)),
      paste("SHA-256 mismatch:", source$id)
    )
  }

  if (!is.null(source$extract_to)) {
    extract_dir <- file.path(raw_root, source$extract_to)
    marker <- file.path(extract_dir, ".extract_complete")
    if (!file.exists(marker)) {
      message("Extracting ", source$id, " -> ", extract_dir)
      dir.create(extract_dir, recursive = TRUE, showWarnings = FALSE)
      files <- if (is.null(source$extract_files)) NULL else unlist(source$extract_files, use.names = FALSE)
      utils::unzip(destination, files = files, exdir = extract_dir)
      writeLines(source$id, marker, useBytes = TRUE)
    } else {
      message("Already extracted: ", source$id)
    }
  }

  data.frame(
    id = source$id,
    group = source$group,
    path = source$path,
    bytes = file.info(destination)$size,
    sha256 = actual_sha256,
    url = used_url,
    canonical_url = if (is.null(source$canonical_url)) source$url else source$canonical_url,
    stringsAsFactors = FALSE
  )
}

download_status <- function(source) {
  tryCatch(
    {
      row <- download_one(source)
      row$status <- "verified"
      row$error <- NA_character_
      row
    },
    error = function(condition) {
      warning(conditionMessage(condition), call. = FALSE)
      data.frame(
        id = source$id,
        group = source$group,
        path = source$path,
        bytes = NA_real_,
        sha256 = NA_character_,
        url = source$url,
        canonical_url = if (is.null(source$canonical_url)) source$url else source$canonical_url,
        status = "failed",
        error = conditionMessage(condition),
        stringsAsFactors = FALSE
      )
    }
  )
}

inventory <- do.call(rbind, lapply(source_config$sources, download_status))
inventory_path <- file.path(raw_root, "download_inventory.csv")
data.table::fwrite(inventory, inventory_path)
failed <- inventory[inventory$status == "failed", , drop = FALSE]
message(sprintf("Raw acquisition complete: %d/%d source files verified: %s", nrow(inventory) - nrow(failed), nrow(inventory), inventory_path))
if (nrow(failed) > 0L) {
  stop(
    paste("Raw download incomplete; failed sources:", paste(failed$id, collapse = ", ")),
    call. = FALSE
  )
}

# Link previews: the card Facebook, X, iMessage and Slack show for a shared
# Atlas page, and the tags that name it (R/card.R).

repo_file <- function(...) testthat::test_path("..", "..", ...)

card_png_size <- function(bytes) {
  if (is.character(bytes)) bytes <- readBin(bytes, "raw", file.info(bytes)$size)
  number <- function(at) sum(as.integer(bytes[at:(at + 3)]) * 256^(3:0))
  c(width = number(17), height = number(21))
}

card_green_pixels <- function(path) {
  v <- terra::values(terra::rast(path), mat = TRUE)
  sum(v[, 2] > v[, 1] + 30 & v[, 2] > v[, 3] + 30)
}

# A strong map around Indiana, two collections, and the taxa table, in a
# fresh data directory.
with_card_data <- function(code, name = "Trametes versicolor") {
  with_data_dir({
    atlas_write_json(data.frame(scientific_name = name, records = 1234L, localities = 2L, fingerprint = "f"),
                     atlas_path("occurrences", "taxa-latest.json"))
    occurrences <- data.frame(
      id = c("1", "2"), scientific_name = name,
      latitude = c("39.7712", "41.0834"), longitude = c("-86.1623", "-85.1441"),
      state = "Indiana", country = "US", stringsAsFactors = FALSE
    )
    file <- "occurrences-20260101T000000Z.tsv.gz"
    atlas_write_tsv_gz(occurrences, atlas_path("occurrences", file))
    atlas_write_json(list(stamp = "20260101T000000Z", file = file, records = 2),
                     atlas_path("occurrences", "latest.json"))
    r <- terra::rast(xmin = 7e5, xmax = 1e6, ymin = -1e5, ymax = 3e5, resolution = 5000, crs = ATLAS_CRS)
    terra::values(r) <- terra::xFromCell(r, seq_len(terra::ncell(r)))
    drawn <- atlas_write_map_png(r, file.path(tempdir(), "card-map.png"))
    dir.create(atlas_model_dir("draft", "maxnet"), recursive = TRUE, showWarnings = FALSE)
    file.copy(drawn$path, atlas_model_path(name, "draft", ".png", "maxnet"), overwrite = TRUE)
    atlas_write_json(list(taxon = name, algorithm = "maxnet", skill = "passed", grade = "strong",
                          bounds = drawn$bounds, map_drawn_at = drawn$drawn_at),
                     atlas_model_path(name, "draft", ".json", "maxnet"))
    force(code)
  })
}

card_taxa <- function(name = "Trametes versicolor", records = 1234L, localities = 2L) {
  data.frame(scientific_name = name, records = records, localities = localities, fingerprint = "f",
             stringsAsFactors = FALSE)
}

meta_content <- function(html, attr, key) {
  m <- regmatches(html, regexec(sprintf('<meta %s="%s" content="([^"]*)" />', attr, key), html))[[1]]
  if (length(m) < 2) NULL else m[[2]]
}

# ---- the picture -------------------------------------------------------------

test_that("a card is 1200 by 630, Facebook's shape, with the map's colour on it", {
  skip_if_not_installed("terra")
  with_card_data({
    choice <- atlas_best_choice("Trametes versicolor")
    with_map <- tempfile(fileext = ".png")
    atlas_write_card_image(with_map, "Trametes versicolor", italic = TRUE, lines = atlas_card_line(1234),
                           metrics = list(bounds = choice$bounds, grade = choice$grade), overlay = choice$png,
                           site = "https://atlas.example.org")
    expect_equal(unname(card_png_size(with_map)), c(1200, 630))
    without <- tempfile(fileext = ".png")
    atlas_write_card_image(without, "Trametes versicolor", site = "https://atlas.example.org")
    # The brand's own green is on both; the map's colour on one.
    expect_gt(card_green_pixels(with_map), card_green_pixels(without) + 10000)
  })
})

test_that("a card never carries the collections: it takes no places to draw", {
  args <- names(formals(atlas_write_card_image))
  expect_false(any(c("cells", "points", "occurrences", "lat", "lng") %in% args))
})

test_that("a card's line counts the records in words a visitor reads", {
  expect_equal(atlas_card_line(1234), "Likely habitat, modelled from 1,234 DNA-validated MycoMap records")
  expect_equal(atlas_card_line(1), "Likely habitat, modelled from 1 DNA-validated MycoMap record")
  expect_equal(atlas_card_line(NA), character())
})

test_that("a long name shrinks to fit two lines, wraps at words, and what never fits ends in an ellipsis", {
  grDevices::png(tempfile(fileext = ".png"), width = 1200, height = 630, res = 144)
  on.exit(grDevices::dev.off(), add = TRUE)
  # The card's own plot: no margins, one unit a pixel.
  graphics::par(mar = c(0, 0, 0, 0))
  graphics::plot.new()
  graphics::plot.window(c(0, 1200), c(0, 630))
  # The title panel is 412 pixels wide.
  long <- atlas_card_title("Amanita muscaria subsp. flavivolvata", 412, font = 4)
  expect_length(long$lines, 2)
  expect_lt(long$cex, 2.6)
  expect_equal(paste(long$lines, collapse = " "), "Amanita muscaria subsp. flavivolvata")
  short <- atlas_card_title("Marasmius siccus", 412, font = 4)
  expect_equal(short$cex, 2.6)
  cut <- atlas_card_wrap(paste(rep("Cortinarius", 12), collapse = " "), 400, 2.6, 4, max_lines = 2L)
  expect_length(cut, 2)
  expect_match(cut[[2]], "\u2026$")
})

# ---- the tags ----------------------------------------------------------------

test_that("every quote, angle bracket and ampersand in a tag is escaped", {
  expect_equal(atlas_html_escape("a & \"b\" <c> 'd'"), "a &amp; &quot;b&quot; &lt;c&gt; &#39;d&#39;")
  share <- atlas_share_site("https://atlas.example.org")
  share$title <- "Mycena sp. \"IN10\" <script>alert('x')</script> & co"
  share$description <- share$title
  html <- atlas_share_html(share)
  expect_false(grepl("<script>", html, fixed = TRUE))
  expect_false(grepl("\"IN10\"", html, fixed = TRUE))
  expect_equal(meta_content(html, "property", "og:title"),
               "Mycena sp. &quot;IN10&quot; &lt;script&gt;alert(&#39;x&#39;)&lt;/script&gt; &amp; co")
})

test_that("a species page's card names it, counts its records, and links its own page and picture", {
  skip_if_not_installed("terra")
  with_card_data({
    share <- atlas_taxon_share("Trametes versicolor", card_taxa(), origin = "https://atlas.example.org")
    expect_equal(share$status, 200L)
    expect_equal(share$title, "Trametes versicolor \u2014 MycoMap Atlas")
    expect_equal(share$description, paste(
      "Where Trametes versicolor is likely to find habitat in North America, modelled from",
      "1,234 DNA-validated MycoMap records. Suitable habitat, not sightings."))
    expect_equal(share$url, "https://atlas.example.org/taxa/Trametes%20versicolor")
    expect_match(share$image, "^https://atlas[.]example[.]org/api/taxa/Trametes%20versicolor/card[.]png[?]v=[0-9a-f]{32}$")

    html <- atlas_share_html(share)
    expect_equal(meta_content(html, "property", "og:title"), share$title)
    expect_equal(meta_content(html, "name", "twitter:title"), share$title)
    expect_equal(meta_content(html, "property", "og:url"), share$url)
    expect_equal(meta_content(html, "property", "og:image"), share$image)
    expect_equal(meta_content(html, "name", "twitter:image"), share$image)
    expect_equal(meta_content(html, "property", "og:site_name"), "MycoMap Atlas")
    expect_equal(meta_content(html, "property", "og:type"), "website")
    expect_equal(meta_content(html, "name", "twitter:card"), "summary_large_image")
    expect_equal(meta_content(html, "property", "og:image:width"), "1200")
    expect_equal(meta_content(html, "property", "og:image:height"), "630")
    expect_null(meta_content(html, "name", "robots"))
  })
})

test_that("a preview never carries a place: no coordinate of any record reaches the tags", {
  skip_if_not_installed("terra")
  with_card_data({
    html <- atlas_share_html(atlas_taxon_share("Trametes versicolor", card_taxa(), origin = "https://atlas.example.org"))
    for (coordinate in c("39.77", "41.08", "86.16", "85.14", "39.8", "41.1", "86.2", "85.1")) {
      expect_false(grepl(coordinate, html, fixed = TRUE), label = coordinate)
    }
    expect_false(grepl("lat|lng|longitude|latitude|bounds", html, ignore.case = TRUE))
  })
})

test_that("a taxon with no map says why, over the site's own picture", {
  with_data_dir({
    share <- atlas_taxon_share("Mycena sp. 'IN10'", card_taxa("Mycena sp. 'IN10'", 2L, 2L),
                               origin = "https://atlas.example.org")
    expect_equal(share$status, 200L)
    expect_equal(share$image, "https://atlas.example.org/og-card.png")
    expect_equal(share$description, paste(
      "Mycena sp. 'IN10' on MycoMap Atlas: 2 DNA-validated MycoMap records.",
      "Found at 2 independent places so far; a first map needs 3."))
    expect_equal(share$url, "https://atlas.example.org/taxa/Mycena%20sp.%20%27IN10%27")
  })
})

test_that("a renamed taxon's preview carries the name its records have now, and links that page", {
  with_data_dir({
    renames <- data.frame(from = "Old name", to = "Trametes versicolor", stringsAsFactors = FALSE)
    share <- atlas_taxon_share("Old name", card_taxa(), renames, origin = "https://atlas.example.org")
    expect_equal(share$title, "Trametes versicolor \u2014 MycoMap Atlas")
    expect_equal(share$url, "https://atlas.example.org/taxa/Trametes%20versicolor")
  })
})

test_that("a name Atlas does not know is a 404 that search engines are told to drop", {
  with_data_dir({
    share <- atlas_taxon_share("Nothing here", card_taxa(), origin = "https://atlas.example.org")
    expect_equal(share$status, 404L)
    expect_equal(meta_content(atlas_share_html(share), "name", "robots"), "noindex")
  })
})

test_that("the site's card says the same in R, in web/index.html and in the web app", {
  index <- repo_file("web", "index.html")
  page_meta <- repo_file("web", "src", "lib", "pageMeta.ts")
  skip_if_not(file.exists(index) && file.exists(page_meta), "no web app in this tree")
  html <- gsub("\\s+", " ", paste(readLines(index, warn = FALSE), collapse = " "))
  content <- function(attr, key) {
    m <- regmatches(html, regexec(sprintf('<meta %s="%s" content="([^"]*)"', attr, key), html))[[1]]
    if (length(m) < 2) NA else gsub("&#39;", "'", m[[2]], fixed = TRUE)
  }
  expect_equal(content("property", "og:title"), ATLAS_SHARE_SITE_TITLE)
  expect_equal(content("name", "twitter:title"), ATLAS_SHARE_SITE_TITLE)
  expect_equal(content("property", "og:description"), ATLAS_SHARE_SITE_DESCRIPTION)
  expect_equal(content("name", "twitter:description"), ATLAS_SHARE_SITE_DESCRIPTION)
  expect_equal(content("property", "og:image"), paste0("https://atlas.mycomap.org", ATLAS_SHARE_SITE_IMAGE))
  expect_equal(content("property", "og:image:alt"), ATLAS_SHARE_SITE_IMAGE_ALT)
  expect_equal(content("name", "twitter:card"), "summary_large_image")
  ts <- paste(readLines(page_meta, warn = FALSE), collapse = "\n")
  expect_true(grepl(ATLAS_SHARE_SITE_TITLE, ts, fixed = TRUE))
  expect_true(grepl(ATLAS_SHARE_SITE_DESCRIPTION, gsub("\"\\s*\\+\\s*\"", "", ts), fixed = TRUE))
  card <- repo_file("web", "public", "og-card.png")
  expect_true(file.exists(card))
  expect_equal(unname(card_png_size(card)), c(1200, 630))
})

# ---- who is sent to the share page -------------------------------------------

link_preview_pattern <- function() {
  conf <- readLines(repo_file("deploy", "lightsail", "nginx", "atlas.conf"), warn = FALSE)
  at <- grep("^map [$]http_user_agent [$]atlas_link_preview", conf)
  line <- grep('^\\s*"~[*]', conf[seq(at, length(conf))], value = TRUE)[[1]]
  sub('^\\s*"~[*](.*)"\\s+1;\\s*$', "\\1", line)
}

test_that("link-preview robots are sent to the share page", {
  pattern <- link_preview_pattern()
  robots <- c(
    "facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)",
    "facebookexternalhit/1.1",
    "Facebot",
    # iMessage
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_11_1) AppleWebKit/601.2.4 (KHTML, like Gecko) Version/9.0.1 Safari/601.2.4 facebookexternalhit/1.1 Facebot Twitterbot/1.0",
    "Twitterbot/1.0",
    "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)",
    "Slackbot 1.0 (+https://api.slack.com/robots)",
    "LinkedInBot/1.0 (compatible; Mozilla/5.0; Apache-HttpClient +http://www.linkedin.com)",
    "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)",
    "WhatsApp/2.23.20.0 A",
    "TelegramBot (like TwitterBot)",
    "Mozilla/5.0 (compatible; Bluesky Cardyb/1.1; +mailto:support@bsky.app)",
    "http.rb/5.1.1 (Mastodon/4.2.1; +https://mastodon.social/) Bot"
  )
  for (ua in robots) expect_true(grepl(pattern, ua, perl = TRUE, ignore.case = TRUE), label = ua)
})

test_that("people, their in-app browsers and search engines get the app as before", {
  pattern <- link_preview_pattern()
  visitors <- c(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 14.0; rv:131.0) Gecko/20100101 Firefox/131.0",
    # Facebook's, Messenger's, Instagram's, X's, LinkedIn's and Snapchat's own browsers
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22A3354 [FBAN/FBIOS;FBAV/480.0.0.0;FBBV/1;FBDV/iPhone15,2]",
    "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0 Mobile Safari/537.36 [FB_IAB/FB4A;FBAV/480.0.0.0;]",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22A3354 [FBAN/MessengerForiOS;FBAV/480.0]",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22A3354 Instagram 350.0.0.0",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22A3354 Twitter for iPhone/10.60",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22A3354 [LinkedInApp]/9.30",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/22A3354 Snapchat/13.10.0.0",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Slack/4.41.97 Chrome/130.0 Electron/33.0 Safari/537.36 Sonic Slack_SSB/4.41.97",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) discord/1.0.9170 Chrome/128.0 Electron/32.2 Safari/537.36",
    # Search engines run the app, and must see what people see.
    "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)",
    "Mozilla/5.0 (compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)",
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_5) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/13.1.1 Safari/605.1.15 (Applebot/0.1; +http://www.apple.com/go/applebot)",
    ""
  )
  for (ua in visitors) expect_false(grepl(pattern, ua, perl = TRUE, ignore.case = TRUE), label = ua)
})

test_that("nginx sends a robot's species page to the share route, ahead of the app's pages", {
  conf <- paste(readLines(repo_file("deploy", "lightsail", "nginx", "atlas.conf"), warn = FALSE), collapse = "\n")
  taxon <- regexpr("location ~ \\^/taxa/\\[\\^/\\]\\+\\$ \\{", conf)
  pages <- regexpr("location ~ \\^/\\(maps\\|", conf)
  expect_gt(taxon, 0)
  expect_gt(pages, taxon)
  expect_match(conf, "proxy_pass http://127.0.0.1:5100/share$atlas_request_path;", fixed = TRUE)
})

# ---- through the API ---------------------------------------------------------

card_api <- function() test_api(c(ATLAS_PUBLIC_ORIGIN = "https://atlas.example.org"))

call_card <- function(api, path, query = "") {
  req <- new.env()
  req$REQUEST_METHOD <- "GET"
  req$PATH_INFO <- path
  req$QUERY_STRING <- if (nzchar(query)) paste0("?", query) else ""
  req$REMOTE_ADDR <- "203.0.113.5"
  req$SERVER_NAME <- "127.0.0.1"
  req$SERVER_PORT <- "5100"
  req$HTTP_HOST <- "atlas.example.org"
  req$rook.input <- list(read = function(...) raw(), rewind = function() invisible(), read_lines = function() character())
  suppressMessages(api$call(req))
}

test_that("anyone can fetch a species' card, kept for good under its map's version", {
  skip_if_not_installed("terra")
  with_card_data({
    api <- card_api()
    out <- call_card(api, "/api/taxa/Trametes%20versicolor/card.png", "v=abc")
    expect_equal(out$status, 200L)
    expect_equal(out$headers[["Content-Type"]], "image/png")
    expect_equal(unname(card_png_size(out$body)), c(1200, 630))
    expect_equal(out$headers[["Cache-Control"]], "public, max-age=31536000, immutable")
    expect_equal(call_card(api, "/api/taxa/Nothing%20here/card.png")$status, 404L)
  })
})

test_that("a species with no map has no card of its own", {
  with_data_dir({
    atlas_write_json(card_taxa("Mycena sp. 'IN10'", 2L, 2L), atlas_path("occurrences", "taxa-latest.json"))
    out <- call_card(card_api(), "/api/taxa/Mycena%20sp.%20%27IN10%27/card.png")
    expect_equal(out$status, 404L)
  })
})

test_that("the share page is HTML with the species' own tags, and an unknown name is a 404", {
  skip_if_not_installed("terra")
  with_card_data({
    api <- card_api()
    out <- call_card(api, "/share/taxa/Trametes%20versicolor")
    expect_equal(out$status, 200L)
    expect_equal(out$headers[["Content-Type"]], "text/html; charset=utf-8")
    expect_equal(out$headers[["Cache-Control"]], "public, max-age=3600")
    html <- if (is.raw(out$body)) rawToChar(out$body) else out$body
    expect_equal(meta_content(html, "property", "og:title"), "Trametes versicolor \u2014 MycoMap Atlas")
    expect_equal(meta_content(html, "property", "og:url"), "https://atlas.example.org/taxa/Trametes%20versicolor")
    expect_match(meta_content(html, "property", "og:image"), "/api/taxa/Trametes%20versicolor/card[.]png[?]v=")

    missing <- call_card(api, "/share/taxa/Nothing%20here")
    expect_equal(missing$status, 404L)
    expect_equal(missing$headers[["Cache-Control"]], "no-store")
  })
})

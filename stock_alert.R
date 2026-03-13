library(quantmod)
library(emayili)
library(yaml)
library(purrr)

config     <- yaml::read_yaml("config.yml")
EMAIL_USER <- Sys.getenv("EMAIL_USER")
EMAIL_PASS <- Sys.getenv("EMAIL_PASS")

# Helpers

send_email <- function(subject, body, to) {
  smtp <- emayili::server(
    host     = "smtp.gmail.com",
    port     = 587,
    username = EMAIL_USER,
    password = EMAIL_PASS,
    protocol = "smtp"
  )
  email <- emayili::envelope(
    to      = to,
    from    = EMAIL_USER,
    subject = subject,
    text    = body
  )
  smtp(email)
}

send_failure <- function(msg) {
  send_email(
    subject = "market-pulse: Script Failed",
    body    = paste("Script failed with error:\n\n", msg),
    to      = EMAIL_USER
  )
}

# Market hours guard (NSE: 09:15–15:30 IST = 03:45–10:00 UTC)

now_utc   <- as.POSIXct(Sys.time(), tz = "UTC")
open_utc  <- as.POSIXct(format(Sys.Date(), "%Y-%m-%d 03:45:00"), tz = "UTC")
close_utc <- as.POSIXct(format(Sys.Date(), "%Y-%m-%d 10:00:00"), tz = "UTC")

if (now_utc < open_utc || now_utc > close_utc) {
  cat("Market is closed. Skipping.\n")
  quit(status = 0)
}

# Fetch

get_stock_data <- function(ticker) {
  tryCatch({
    data <- quantmod::getQuote(
      ticker,
      what = quantmod::yahooQF(c("Previous Close", "Last Trade (Price Only)", "Days Low"))
    )
    prev_close <- data[["P. Close"]]
    current    <- data[["Last"]]
    day_low    <- data[["Low"]]
    
    if (is.na(prev_close) || is.na(current) || is.na(day_low) ||
        prev_close == 0 || current == 0 || day_low == 0) {
      return(list(
        error = sprintf(
          "Invalid data for %s: prev=%.2f current=%.2f day_low=%.2f",
          ticker, prev_close, current, day_low
        )
      ))
    }
    
    list(
      current     = current,
      prev_close  = prev_close,
      day_low     = day_low,
      day_low_pct = ((day_low - prev_close) / prev_close) * 100,
      current_pct = ((current - prev_close) / prev_close) * 100
    )
  }, error = function(e) {
    list(error = conditionMessage(e))
  })
}

# Main 

tryCatch({
  results <- purrr::map(config$stocks, \(stock) {
    list(stock = stock, result = get_stock_data(stock$ticker))
  })
  
  fetch_errors <- purrr::keep(results, \(x) !is.null(x$result$error))
  valid        <- purrr::keep(results, \(x) is.null(x$result$error))
  alerts       <- purrr::keep(valid, \(x) x$result$day_low_pct <= x$stock$threshold)
  
  purrr::walk(valid, \(x) {
    cat(sprintf(
      "%s: Day Low %.2f%% | Current %.2f%% (threshold: %.2f%%)\n",
      x$stock$name, x$result$day_low_pct, x$result$current_pct, x$stock$threshold
    ))
  })
  
  purrr::walk(fetch_errors, \(x) {
    cat(sprintf("Fetch failed for %s: %s\n", x$stock$name, x$result$error))
  })
  
  # Group alerts by recipient, send one email per person
  if (length(alerts) > 0) {
    all_recipients <- unique(unlist(purrr::map(alerts, \(x) x$stock$alert_emails)))
    
    purrr::walk(all_recipients, \(recipient) {
      recipient_alerts <- purrr::keep(alerts, \(x) recipient %in% x$stock$alert_emails)
      
      alert_lines <- purrr::map_chr(recipient_alerts, \(x) sprintf(
        "%s: Day Low has breached threshold at %.2f%% (Day Low: %.2f, Prev Close: %.2f, Threshold: %.2f%%)\nCurrent Price: %.2f (%.2f%% from prev close)",
        x$stock$name,
        x$result$day_low_pct,
        x$result$day_low,
        x$result$prev_close,
        x$stock$threshold,
        x$result$current,
        x$result$current_pct
      ))
      
      body <- sprintf(
        "The following indices breached their thresholds:\n\n%s",
        paste(alert_lines, collapse = "\n\n")
      )
      
      send_email(
        subject = sprintf("Stock Alert: Threshold Breached [%s]", Sys.Date()),
        body    = body,
        to      = recipient
      )
      cat(sprintf("Alert sent to %s.\n", recipient))
    })
  }
  
  # Report fetch errors to owner only
  if (length(fetch_errors) > 0) {
    error_lines <- purrr::map_chr(fetch_errors, \(x) sprintf("%s: %s", x$stock$name, x$result$error))
    send_failure(paste("Fetch failures:\n\n", paste(error_lines, collapse = "\n")))
  }
  
  if (length(alerts) == 0 && length(fetch_errors) == 0) {
    cat("No alerts triggered.\n")
  }

  quit(status = 0)

  
}, error = function(e) {
  send_failure(conditionMessage(e))
  stop(e)
})

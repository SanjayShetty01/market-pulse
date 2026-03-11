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
    port     = 465,
    username = EMAIL_USER,
    password = EMAIL_PASS
  )
  email <- emayili::envelope(
    to      = to,
    from    = EMAIL_USER,
    subject = subject,
    text    = body
  )
  smtp(email)
}

send_to_recipients <- function(subject, body, recipients) {
  purrr::walk(recipients, \(recipient) send_email(subject, body, recipient))
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

get_change_pct <- function(ticker) {
  tryCatch({
    data <- quantmod::getQuote(ticker, what = quantmod::yahooQF(c(
      "Previous Close", "Last Trade (Price Only)"
    )))
    prev_close <- data[["P. Close"]]
    current    <- data[["Last"]]
    
    if (is.na(prev_close) ||
        is.na(current) || prev_close == 0 || current == 0) {
      return(list(
        error = sprintf(
          "Invalid data for %s: prev=%.2f current=%.2f",
          ticker,
          prev_close,
          current
        )
      ))
    }
    
    change_pct <- ((current - prev_close) / prev_close) * 100
    list(current = current,
         prev_close = prev_close,
         change_pct = change_pct)
  }, error = function(e) {
    list(error = conditionMessage(e))
  })
}

# Main 

tryCatch({
  results <- purrr::map(config$stocks, \(stock) {
    list(stock = stock, result = get_change_pct(stock$ticker))
  })
  
  fetch_errors <- purrr::keep(results, \(x) ! is.null(x$result$error))
  valid        <- purrr::discard(results, \(x) ! is.null(x$result$error))
  alerts       <- purrr::keep(valid, \(x) x$result$change_pct <= x$stock$threshold)
  
  purrr::walk(valid, \(x) {
    cat(
      sprintf(
        "%s: %.2f%% (threshold: %.2f%%)\n",
        x$stock$name,
        x$result$change_pct,
        x$stock$threshold
      )
    )
  })
  
  purrr::walk(fetch_errors, \(x) {
    cat(sprintf("Fetch failed for %s: %s\n", x$stock$name, x$result$error))
  })
  
  # Send individual alert per stock to its recipients
  purrr::walk(alerts, \(x) {
    body <- sprintf(
      "The following indices breached their thresholds:\n\n%s: %.2f%% (Current: %.2f, Prev Close: %.2f, Threshold: %.2f%%)",
      x$stock$name,
      x$result$change_pct,
      x$result$current,
      x$result$prev_close,
      x$stock$threshold
    )
    send_to_recipients(
      subject    = sprintf("Stock Alert: Threshold Breached [%s]", Sys.Date()),
      body       = body,
      recipients = x$stock$alert_emails
    )
    cat(sprintf("Alert sent for %s.\n", x$stock$name))
  })
  
  # Report fetch errors to owner only
  if (length(fetch_errors) > 0) {
    error_lines <- purrr::map_chr(fetch_errors,
                                  \(x) sprintf("%s: %s", x$stock$name, x$result$error))
    send_failure(paste("Fetch failures:\n\n", paste(error_lines, collapse = "\n")))
  }
  
  if (length(alerts) == 0 && length(fetch_errors) == 0) {
    cat("No alerts triggered.\n")
  }
  
}, error = function(e) {
  send_failure(conditionMessage(e))
  stop(e)
})
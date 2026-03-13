[![Stock Alert (R)](https://github.com/SanjayShetty01/market-pulse/actions/workflows/stock_alert.yml/badge.svg)](https://github.com/SanjayShetty01/market-pulse/actions/workflows/stock_alert.yml)

# market-pulse

> **Disclaimer:** This tool is meant to help monitor index movements as a reference for mutual fund investments. Not a stock trading tool, not financial advice.

I built this because I wanted a simple daily nudge when the market dips, just an email at noon telling me if something worth paying attention to happened.

It runs every weekday at 12pm IST via GitHub Actions, checks the day's low for configured indices against a threshold, and sends an email if anything breaches it. 12pm gives a 2 hour window to act before the 2pm mutual fund cutoff - early enough to decide.

## How it works

- Fetches the **day's low** for each index (not the current price - day low is a stronger signal)
- Compares it against a configured **% drop threshold** from previous close
- If breached, sends an email with the day low details and current price
- Each recipient gets **one consolidated email** per run, not one per stock

## Project Structure

```
market-pulse/
├── check_stock.R                        # Main script
├── config.yml                           # Stocks, thresholds, recipients
└── .github/
    └── workflows/
        └── stock_alert.yml              # GitHub Actions workflow
```

## Configuration

Everything lives in `config.yml` - no code changes needed for adding stocks or recipients:

```yaml
stocks:
  - name: "NIFTY 50"
    ticker: "^NSEI"
    threshold: -1.0
    alert_emails:
      - "you@gmail.com"
  - name: "NIFTY MIDCAP 150"
    ticker: "NIFTYMIDCAP150.NS"
    threshold: -1.5
    alert_emails:
      - "you@gmail.com"
      - "friend@gmail.com"
```

- `threshold` - % drop from previous close that triggers the alert (e.g. `-1.0` means 1% drop)
- `alert_emails` - who gets notified for that stock

### Adding a new index

Just append to `config.yml`:

```yaml
  - name: "NIFTY BANK"
    ticker: "^NSEBANK"
    threshold: -1.5
    alert_emails:
      - "you@gmail.com"
```

To find the right ticker, search the index on [finance.yahoo.com](https://finance.yahoo.com) and copy the symbol.

## Local Setup

### 1. Gmail App Password

You'll need a Gmail App Password (not your regular password) to send emails:

1. Go to [myaccount.google.com](https://myaccount.google.com)
2. Security → 2-Step Verification → App Passwords
3. Generate one for "Mail" and copy the 16-character string

### 2. GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|--------|-------|
| `EMAIL_USER` | Gmail address used to send the alerts |
| `EMAIL_PASS` | App Password from above |

### 3. Local Development

Create a `.Renviron` at project root (add it to `.gitignore`):

```
EMAIL_USER=you@gmail.com
EMAIL_PASS=xxxx xxxx xxxx xxxx
```

## What the email looks like

**Subject:** `Stock Alert: Threshold Breached [2026-03-13]`

**Body:**
```
The following indices breached their thresholds:

NIFTY 50: Day Low has breached threshold at -1.30% (Day Low: 23850.00, Prev Close: 24261.60, Threshold: -1.00%)
Current Price: 24130.00 (-0.54% from prev close)
```

## Error handling

- Fetch failures and script crashes are reported only to the sender - recipients only get alerts, not noise
- If the market is closed, the script exits silently

## Dependencies

R packages: `quantmod`, `emayili`, `yaml`, `purrr`

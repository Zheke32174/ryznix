# Proof Logs

This directory is for reviewer-safe, redacted proof material.

Do not commit raw logs here. Commit only short, focused transcripts that prove one capability at a time.

## Good proof topics

- RYZ interpreter runs a program
- RYZ native compiler emits an executable
- AeSH launches and runs basic commands
- Ryznix status command reports expected runtime pieces
- Ryznix self-test passes
- package tooling reports a version or installs a harmless demo package

## Redaction markers

Replace local/private values with placeholders before committing:

```text
<REDACTED_TOKEN>
<REDACTED_HOST>
<REDACTED_IP>
<REDACTED_DEVICE_ID>
<REDACTED_USERNAME>
<REDACTED_PATH>
```

## Suggested files

```text
docs/proof/ryz-toolchain.redacted.txt
docs/proof/aesh-demo.redacted.txt
docs/proof/ryznix-status.redacted.txt
docs/proof/ryznix-selftest.redacted.txt
docs/proof/apt-demo.redacted.txt
docs/proof/package-tools.redacted.txt
```

## Minimum proof format

```text
# Proof: <name>
Date: YYYY-MM-DD
Environment: <short redacted description>

## Command
<redacted command>

## Output
<redacted output>

## Notes
- What this proves.
- What it does not prove.
- Known limitations.
```

## Rule

Keep proof logs boring, narrow, and verifiable.

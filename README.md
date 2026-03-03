# NFAT Facility

An NFAT Facility manages bespoke capital deployment deals between depositors (Primes) and borrowers (Halos). Depositors subscribe an asset (sUSDS) into a queue. When a deal is struck, the operator issues an ERC-721 Non-Fungible Allocation Token (NFAT) to the depositor and forwards the capital to the borrower. The borrower later repays into the facility, and the NFAT holder collects repayments (principal and interest). Deal terms (APY, maturity, payment frequency, etc) are tracked off-chain; the contract handles only capital flows.

## Assumptions

It is assumed that only simple, regular ERC-20 tokens will be used as `gem`. In particular, the supported tokens are assumed to revert on failure (instead of returning false), not to execute any hook or apply any fee on transfer, and not to execute any rebasing logic.

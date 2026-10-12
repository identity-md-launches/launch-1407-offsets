# Offsets token tests

Run `forge build` and `forge test`. The suites use the repository's existing
forge-std dependency and require no forks, environment variables, FFI, or downloads.
With Solidity 0.8.26 already installed, both commands also work with `--offline`.

`OffsetsToken.t.sol` is the original contributor suite. The additional coverage is:

- `OffsetsToken.EdgeCases.t.sol`: zero and one-unit operations, full-supply spends,
  maximum finite versus unlimited allowances, self-transfers and aliased roles,
  revocation and repeated approvals, independent owner/spender permissions,
  exact revert errors, and rollback of balances and allowances. Fuzz properties
  cover round trips, split versus delegated transfers, arbitrary recipients, and
  actual CREATE2 deployment by a contract. Each fuzz property runs 1,000 cases.
- `OffsetsToken.Invariant.t.sol`: 256 random sequences of 96 handler calls across
  four actors. The handler mixes direct and delegated transfers, finite and
  unlimited approvals, revocations, and invalid operations. Inputs are bounded;
  no fuzz cases are discarded with assumptions.

The invariant suite targets only the handler's nine action selectors. Successful
transfers stay within the four actors, making the sum of their balances exhaustive.
Cumulative sent/received amounts check each holder's entitlement independently of
the token's balance getters. Approval amounts and spending since the last approval
check every owner/spender pair, including self-approval. Rejected calls must return
the exact expected error and leave the accounting unchanged. Unexpected handler
reverts fail the campaign. After each sequence, every holder must still be able to
transfer its complete balance.

Run counts and invariant settings are inline in the test files. To keep generated
artifacts in disposable scratch space, append
`--out test/scratch/out --cache-path test/scratch/cache` to either command.

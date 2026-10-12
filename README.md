# Offsets (OFFSETS)

A plain, fixed-supply ERC-20 token for the IdentityMD custom-token launch on Ethereum.

| Field          | Value                                              |
| -------------- | -------------------------------------------------- |
| Contract       | `OffsetsToken` (`src/OffsetsToken.sol`)            |
| Name           | Offsets                                            |
| Symbol         | OFFSETS                                            |
| Decimals       | 18                                                 |
| Total supply   | 1,000,000,000 OFFSETS = `1000000000000000000000000000` minor units |
| Minting        | Once, in the constructor, all to `msg.sender`      |
| Constructor    | No arguments                                       |
| Owner / admin  | None                                               |

## Behaviour

- The constructor mints the whole supply to whoever deploys the contract and emits a single
  `Transfer(address(0), deployer, supply)`. It takes no arguments and calls no other contract,
  so it deploys on an empty chain and through a CREATE2 factory alike.
- `totalSupply()` is a constant. There is no `mint`, no `burn`, no owner, no minter role, no
  pause, no blacklist, no fee and no upgrade path. After construction the contract has no
  privileged function at all.
- `transfer`, `approve`, `transferFrom`, `allowance`, `balanceOf`, `name`, `symbol`,
  `decimals` follow ERC-20. Transfers to the zero address and approvals of the zero address
  revert. An allowance of `type(uint256).max` is unlimited and is not decremented.
- Failures revert with typed errors: `TransferToZeroAddress`, `ApproveToZeroAddress`,
  `InsufficientBalance(sender, balance, needed)`,
  `InsufficientAllowance(spender, allowance, needed)`.
- The contract has no `receive`/`fallback`, so plain ETH sent to it is refused.
- The runtime bytecode contains no `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.

## Assumptions

- The brief asks for a plain token: name, symbol, supply and a one-time mint to the deployer.
  No tax, burn, vesting, reflection or governance feature was requested, so none is implemented.
- "Deployer" means `msg.sender` of the constructor. In the IdentityMD launch that is the
  ProjectFactory, which then distributes the supply as the launch economics direct. Nothing in
  the token hard-codes any address.
- The token has no dependency beyond the Solidity compiler. It is written by hand rather than
  inherited from a library so there are no link placeholders in the bytecode and no behaviour
  beyond what is documented here. `lib/forge-std` is vendored as ordinary files for the tests.

## Deployment parameters

There are none. The constructor takes no arguments, so the launch manifest's
`token.constructorArgs` is empty and `token.totalSupply` is `1000000000000000000000000000`.

Launch values decided by the IdentityMD launch (recorded here for reference, not chosen by this
code): chain Ethereum (id 1); pool paired with IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`; pool fee 12500 (1.25%); tick spacing 60; the
requester's economics are `poolBps` 8000, `initialMarketCapWei` 2500 IMD and `remainderTo`
`0xd6302976e590b9b947da8774b7f1246164e0ce98`. The factory takes the swarm's 10%, seeds the pool
with 80% and forwards the remaining 10% to `remainderTo`. The manifest step writes `launch.json`;
this repository deliberately does not.

Because every transfer moves exactly what it says and nothing is exempt or taxed, the launch
flows (factory to distributor, distributor to claimant, factory to pool, pool to and from
traders) all arrive whole.

### Manual deployment (outside the launch)

`script/DeployOffsets.s.sol` deploys the token with whatever signer `forge script` is given.
It reads no environment variables. Example:

```
forge script script/DeployOffsets.s.sol --rpc-url <RPC> --private-key <KEY> --broadcast
```

The signer receives the whole supply. Verification on an explorer is done afterwards with
`forge verify-contract` using the pinned compiler settings in `foundry.toml`
(solc 0.8.26, optimizer on, 200 runs, `bytecode_hash = "none"`, EVM `cancun`).

## After launch

Nothing to configure. The token has no owner, no setters and no external references.

## Operational responsibilities

- **Supply custody.** The deployer holds 100% of the supply at construction. In the launch that
  is the factory, which pays it out immediately; in a manual deployment the signer must
  distribute it. The token cannot recover tokens sent to a wrong address or to a contract that
  cannot handle them.
- **No admin recourse.** There is no pause, freeze, upgrade or mint. If a different behaviour is
  ever wanted, a new contract must be deployed; this one cannot be changed.
- **Allowances.** Users changing a non-zero allowance are subject to the standard ERC-20
  approve race; set the allowance to zero first if that matters.
- **Review.** Tests passing is not a security audit. The code is small and standard, but the
  launch's independent review should still read it before release.

## Building and testing

```
forge build
forge test
forge fmt --check
```

`foundry.toml` pins `solc = "0.8.26"`, enables the optimizer (200 runs), sets
`bytecode_hash = "none"` as the launch requires, and enables nothing else (no `ffi`, no
`fs_permissions`).

The tests in `test/OffsetsToken.t.sol` cover metadata, the one-time mint (to any deployer, and
through the deploy script), every `transfer`/`approve`/`transferFrom` success and failure path
with exact error data and events, fuzzed supply conservation, the absence of mint/admin/freeze
entry points (every common selector reverts from a stranger and from the deployer), refusal of
plain ETH, and an opcode scan of the runtime for `DELEGATECALL`, `CALLCODE` and `SELFDESTRUCT`.
Tests read no environment variables and do not depend on the calling address, so they run in any
order and in parallel.

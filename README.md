<p align="center">
  <a href="https://github.com/pooltogether/pooltogether--brand-assets">
    <img src="https://github.com/pooltogether/pooltogether--brand-assets/blob/977e03604c49c63314450b5d432fe57d34747c66/logo/pooltogether-logo--purple-gradient.png?raw=true" alt="PoolTogether Brand" style="max-width:100%;" width="400">
  </a>
</p>

# PoolTogether V5 CGDA Liquidation Pair

[![Code Coverage](https://github.com/generationsoftware/pt-v5-cgda-liquidator/actions/workflows/coverage.yml/badge.svg)](https://github.com/generationsoftware/pt-v5-cgda-liquidator/actions/workflows/coverage.yml)
[![built-with openzeppelin](https://img.shields.io/badge/built%20with-OpenZeppelin-3677FF)](https://docs.openzeppelin.com/)
![MIT license](https://img.shields.io/badge/license-MIT-blue)

PoolTogether V5 uses the CGDA liquidator to sell yield for POOL tokens and contribute those tokens to the prize pool. There are three contracts in this repository:

- LiquidationPair: The core contract that runs a periodic continuous gradual dutch auction.
- LiquidationPairFactory: creates new LiquidationPairs and registers them.
- LiquidationRouter: provides a convenient interface to interact with LiquidationPairs

## LiquidationPair

The LiquidationPair sells one token for another using a periodic continuous gradual dutch auction. The pair does not hold liquidity, but rather prices liquidity held by a ILiquidationSource. The Liquidation Source makes liquidity available to the pair, which facilitates swaps.

A continuous gradual dutch auction is an algorithm that:

1. Prices the purchase of tokens against a bonding curve
2. Decays the purchase price as time elapses
3. Limits the number of tokens purchased according to an emissions rate.

What you get, in a sense, is that a CGDA auction will drop the price until purchases match the rate of emissions.

For more information read the origina Paradigm article on [Gradual Dutch Auctions](https://www.paradigm.xyz/2022/04/gda).

The LiquidationPair is _periodic_, in the sense that it runs a sequence of CGDAs. At the start of each auction period, the LiquidationPair will adjust the target price and emissions rate so that the available liquidity can be sold as efficiently as possible.

<strong>Have questions or want the latest news?</strong>
<br/>Join the PoolTogether Discord or follow us on Twitter:

[![Discord](https://badgen.net/badge/icon/discord?icon=discord&label)](https://pooltogether.com/discord)
[![Twitter](https://badgen.net/badge/icon/twitter?icon=twitter&label)](https://twitter.com/PoolTogether_)

## Development

### Installation

You may have to install the following tools to use this repository:

- [Foundry](https://github.com/foundry-rs/foundry) to compile and test contracts
- [direnv](https://direnv.net/) to handle environment variables
- [lcov](https://github.com/linux-test-project/lcov) to generate the code coverage report

Install dependencies:

```
npm i
```

## Derivations

### Price Function

$$ \frac{k}{l}\cdot\frac{\left(e^{\frac{lq}{r}}-1\right)}{e^{lt}} $$

### Inverse Price Function

Solve for q, knowing p

$$ p = \frac{k}{l}\cdot\frac{\left(e^{\frac{lq}{r}}-1\right)}{e^{lt}} $$

$$ p \cdot e^{lt} \cdot l = k\cdot(e^{\frac{lq}{r}}-1) $$

$$ p \cdot e^{lt} \cdot l = k \cdot e^{\frac{lq}{r}}- k $$

$$ \frac{p \cdot e^{lt} \cdot l + k}{k} = e^{\frac{lq}{r}} $$

$$ ln(\frac{p \cdot e^{lt} \cdot l + k}{k}) = \frac{lq}{r} $$

$$ r \cdot ln(\frac{p \cdot e^{lt} \cdot l + k}{k}) = l\cdot q $$

$$ \frac{r \cdot ln(\frac{p \cdot e^{lt} \cdot l + k}{k})}{l} = q $$

### Compute K

We know:

- r: emissionRate
- l: decayConstant
- t: targetFirstSaleTime
- q: purchaseAmount
- p: price

$$ p = \frac{k}{l}\cdot\frac{\left(e^{\frac{lq}{r}}-1\right)}{e^{lt}} $$

$$ l\cdot p\cdot e^{lt} = k\cdot\left(e^{\frac{lq}{r}}-1\right) $$

$$ \frac{l\cdot p\cdot e^{lt}}{(e^{\frac{lq}{r}}-1)} = k $$

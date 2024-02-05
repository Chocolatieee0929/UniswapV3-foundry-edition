// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.7.6;

import "./interfaces/IUniswapV3PoolDeployer.sol";

import "./UniswapV3Pool.sol";

contract UniswapV3PoolDeployer is IUniswapV3PoolDeployer {
    struct Parameters {
        address factory;
        address token0;
        address token1;
        uint24 fee;
        int24 tickSpacing;
    }

    /// @inheritdoc IUniswapV3PoolDeployer
    Parameters public override parameters;

    /// @dev Deploys a pool with the given parameters by transiently setting the parameters storage slot and then
    /// clearing it after deploying the pool.
    /// @param factory The contract address of the Uniswap V3 factory
    /// @param token0 The first token of the pool by address sort order
    /// @param token1 The second token of the pool by address sort order
    /// @param fee The fee collected upon every swap in the pool, denominated in hundredths of a bip
    /// @param tickSpacing The spacing between usable ticks
    // CREATE2 使用一个特殊的*盐值(salt)*来产生合约地址。
    // 这是一个由开发者选择的任意序列，能够使得地址产生更加确定性（并降低碰撞概率）：
    // KECCAK256(deployer.address, salt, contractCodeHash)
    function deploy(address factory, address token0, address token1, uint24 fee, int24 tickSpacing)
        internal
        returns (address pool)
    {
        parameters = Parameters({factory: factory, token0: token0, token1: token1, fee: fee, tickSpacing: tickSpacing});
        // parameters 其实是传给 UniswapV3Pool 的参数
        pool = address(new UniswapV3Pool{salt: keccak256(abi.encode(token0, token1, fee))}());
        delete parameters;
    }
}

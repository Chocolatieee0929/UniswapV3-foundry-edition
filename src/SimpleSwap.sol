// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "contracts/v3-periphery/interfaces/ISwapRouter.sol";
import "contracts/v3-periphery/libraries/TransferHelper.sol";
import {console2} from "forge-std/console2.sol";

contract SimpleSwap {
    ISwapRouter public immutable swapRouter;
    address public immutable WETH9;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    uint24 public constant feeTier = 3000;

    constructor(ISwapRouter _swapRouter, address _WETH9) {
        WETH9 = _WETH9;
        swapRouter = _swapRouter;
    }

    function swapWETHForDAI(
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        // Transfer the specified amount of WETH9 to this contract.
        TransferHelper.safeTransferFrom(
            WETH9,
            msg.sender,
            address(this),
            amountIn
        );
        // Approve the router to spend WETH9.
        TransferHelper.safeApprove(WETH9, address(swapRouter), amountIn);
        console2.log("Approve the router to spend WETH9: ", amountIn);
        // Note: To use this example, you should explicitly set slippage limits, omitting for simplicity
        uint256 minOut = /* Calculate min output */ 0;
        uint160 priceLimit = /* Calculate price limit */ 0;
        // Create the params that will be used to execute the swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: WETH9,
                tokenOut: DAI,
                fee: feeTier,
                recipient: msg.sender,
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: minOut,
                sqrtPriceLimitX96: priceLimit
            });
        // The call to `exactInputSingle` executes the swap.
        amountOut = swapRouter.exactInputSingle(params);
    }
}

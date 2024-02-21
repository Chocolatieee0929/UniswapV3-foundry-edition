//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import { console2 } from "forge-std/Test.sol";
import { BaseDeploy } from "test/utils/BaseDeploy.sol";

import { TransferHelper } from "contracts/v3-periphery/libraries/TransferHelper.sol";
import { INonfungiblePositionManager } from "contracts/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import { IERC721Receiver } from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "contracts/v3-periphery/interfaces/ISwapRouter.sol";

import "test/utils/TickHelper.sol";
import "test/utils/Path.sol";
import { encodePriceSqrt } from "test/utils/Math.sol";
import { TransferHelper } from "contracts/v3-periphery/libraries/TransferHelper.sol";

/*通过 v3-periphery 创建合约*/
contract SwapRouterTest is BaseDeploy {
	/*  State varies */
	address public pool1;
	address public pool2;
	address public pool3;

	struct Deposit {
		address owner;
		uint128 liquidity;
		address token0;
		address token1;
	}

	/// @dev deposits[tokenId] => Deposit
	mapping(uint256 => Deposit) public deposits;

	/* 
    初始化：建立好一个测试环境，包括部署池子工厂合约，创建测试代币，创建测试账户等。
     */
	function setUp() public override {
		super.setUp();
		vm.startPrank(deployer);

		// 创建费率为FEE_MEDIUM的池子
		pool1 = mintNewPool(tokens[0], tokens[1], FEE_MEDIUM, INIT_PRICE);
		pool2 = mintNewPool(tokens[1], tokens[2], FEE_MEDIUM, INIT_PRICE);

		mintNewPosition(
			tokens[0],
			tokens[1],
			getMinTick(TICK_MEDIUM),
			getMaxTick(TICK_MEDIUM),
			10000,
			10000
		);

		mintNewPosition(
			tokens[1],
			tokens[2],
			getMinTick(TICK_MEDIUM),
			getMaxTick(TICK_MEDIUM),
			10000,
			10000
		);

		vm.stopPrank();
	}

	/* 测试单池子的swapExactTokensForTokens功能。*/

	function test_OneToTwo() public {
		address token1 = tokens[1];
		address token2 = tokens[2];
		uint256 token1PoolBefore = IERC20(token1).balanceOf(pool2);
		uint256 token1DeployerBefore = IERC20(token1).balanceOf(deployer);

		/////////////////////////////////////////////////////////
		////	Error：vm.startBroadcast(deployer)未生效！！！	//
		/////////////////////////////////////////////////////////
		vm.startPrank(deployer);
		uint amountOut = swapExactInputSingleHop(token1, token2, FEE_MEDIUM, 3);

		uint256 token1PoolAfter = IERC20(token1).balanceOf(pool2);
		uint256 token1DeployerAfter = IERC20(token1).balanceOf(deployer);

		console2.log("token1DeployerBefore:", token1DeployerBefore);
		console2.log("token1DeployerAfter :", token1DeployerAfter);

		require(
			token1DeployerAfter == token1DeployerBefore - 3,
			"token1Deployer Error"
		);
		require(token1PoolAfter == token1PoolBefore + 3, "token1Pool Error");
		vm.stopPrank();
	}

	/* 测试多池子的swapExactTokensForTokens功能。*/
	function test_ZeroToOneToTwo() public {
		uint256 token0DeployerBefore = IERC20(tokens[0]).balanceOf(deployer);
		uint256 token2DeployerBefore = IERC20(tokens[2]).balanceOf(deployer);
		uint256 token1DeployerBefore = IERC20(tokens[1]).balanceOf(deployer);

		address[] memory m_tokens = new address[](3);
		m_tokens[0] = address(tokens[0]);
		m_tokens[1] = address(tokens[1]);
		m_tokens[2] = address(tokens[2]);

		uint24[] memory m_fees = new uint24[](2);
		m_fees[0] = FEE_MEDIUM;
		m_fees[1] = FEE_MEDIUM;

		bytes memory path = encodePath(m_tokens, m_fees);

		vm.startPrank(deployer);
		uint256 amountIn = 5;
		// IERC20(m_tokens[0]).transfer(address(this), amountIn);
		swapExactInputMultiHop(path, m_tokens[0], amountIn);

		uint256 token0DeployerAfter = IERC20(tokens[0]).balanceOf(deployer);
		uint256 token2DeployerAfter = IERC20(tokens[2]).balanceOf(deployer);

		require(
			token0DeployerAfter == token0DeployerBefore - 5,
			"token0Deployer error"
		);
		require(token2DeployerAfter > token2DeployerBefore, "token2Deployer error");
	}

	function mintNewPool(
		address token0,
		address token1,
		uint24 fee,
		uint160 currentPrice
	) internal returns (address) {
		(token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
		/* 创建池子 */
		return
			nonfungiblePositionManager.createAndInitializePoolIfNecessary(
				token0,
				token1,
				fee,
				currentPrice
			);
	}

	function mintNewPosition(
		address token0,
		address token1,
		// int24 tickSpacing,
		int24 tickLower,
		int24 tickUpper,
		uint256 amount0ToMint,
		uint256 amount1ToMint
	) internal {
		(token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
		INonfungiblePositionManager.MintParams
			memory liquidityParams = INonfungiblePositionManager.MintParams({
				token0: token0,
				token1: token1,
				fee: FEE_MEDIUM,
				tickLower: tickLower,
				tickUpper: tickUpper,
				recipient: deployer,
				amount0Desired: amount0ToMint,
				amount1Desired: amount1ToMint,
				amount0Min: 0,
				amount1Min: 0,
				deadline: 1
			});

		nonfungiblePositionManager.mint(liquidityParams);
	}

	function swapExactInputSingleHop(
		address tokenIn,
		address tokenOut,
		uint24 fee,
		uint amountIn
	) internal returns (uint amountOut) {
		// IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
		IERC20(tokenIn).approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
			.ExactInputSingleParams({
				tokenIn: tokenIn,
				tokenOut: tokenOut,
				fee: fee,
				recipient: msg.sender,
				deadline: block.timestamp,
				amountIn: amountIn,
				amountOutMinimum: 0,
				sqrtPriceLimitX96: 0
			});

		amountOut = swapRouter.exactInputSingle(params);
	}

	function swapExactInputMultiHop(
		bytes memory path,
		address tokenIn,
		uint amountIn
	) internal returns (uint amountOut) {
		// IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
		IERC20(tokenIn).approve(address(swapRouter), amountIn);

		ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
			path: path,
			recipient: deployer, // 正常情况下应该是msg.sender
			deadline: block.timestamp,
			amountIn: amountIn,
			amountOutMinimum: 0
		});
		amountOut = swapRouter.exactInput(params);
	}
}

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

		// 针对tokens[1],toekns[2] 创建3个池子
		pool1 = mintNewPool(tokens[1], tokens[2], FEE_LOW, INIT_PRICE);
		pool2 = mintNewPool(tokens[1], tokens[2], FEE_MEDIUM, INIT_PRICE);
		pool3 = mintNewPool(tokens[1], tokens[2], FEE_HIGH, INIT_PRICE);

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

		vm.startBroadcast(deployer);
		console2.log("deployer",deployer);
		console2.log("msg.sender",msg.sender);
		console2.log("this", address(this));
		uint amountOut = swapExactInputSingleHop(token1, token2, FEE_MEDIUM, 3);

		uint256 token1PoolAfter = IERC20(token1).balanceOf(pool1);
		uint256 token1DeployerAfter = IERC20(token1).balanceOf(deployer);
		require(token1DeployerAfter == token1DeployerBefore - 3);
		require(token1PoolAfter == token1PoolBefore + 3);

	}

	function test_TwoToOne() internal {
		// address pool = factory.getPool(
		// 	address(tokens[1]),
		// 	address(tokens[0]),
		// 	FEE_MEDIUM
		// );
		// Balances memory poolBefore = getBalances(pool);
		// Balances memory deployerBefore = getBalances(deployer);
		// address[] memory _tokens = new address[](2);
		// _tokens[0] = address(tokens[1]);
		// _tokens[1] = address(tokens[0]);
		// exactInput(_tokens, 3, 1);
		// Balances memory poolAfter = getBalances(pool);
		// Balances memory deployerAfter = getBalances(deployer);
		// require(deployerAfter.token0 == deployerBefore.token0 + 1);
		// require(deployerAfter.token1 == deployerBefore.token1 - 3);
		// require(poolAfter.token0 == poolBefore.token0 - 1);
		// require(poolAfter.token1 == poolBefore.token1 + 3);
	}

	function mintNewPool(
		address token0,
		address token1,
		uint24 fee,
		uint160 currentPrice
	) internal returns (address) {
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
		console2.log(msg.sender);

		IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
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
}

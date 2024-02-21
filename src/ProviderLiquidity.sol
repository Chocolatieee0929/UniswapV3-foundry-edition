// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity =0.7.6;
pragma abicoder v2;

import "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "contracts/v3-periphery/libraries/TransferHelper.sol";
import "contracts/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import "contracts/v3-periphery/base/LiquidityManagement.sol";
import "contracts/v3-periphery/interfaces/ISwapRouter.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/* 
这是UniswapV3官方文档简单测试用例，
在后续的测试里发现desposit存储的liquidity不准确，待修复
*/

contract ProviderLiquidity is IERC721Receiver {
	event createDeposit(address owner, uint256 tokenId);

	uint24 public constant poolFee = 3000;
	address private _owner;

	INonfungiblePositionManager public immutable nonfungiblePositionManager;
	ISwapRouter public immutable swapRouter;

	mapping(int24 => uint24) public tickSpacingFeeAmount;

	/// @notice Represents the deposit of an NFT
	struct Deposit {
		address owner;
		uint128 liquidity;
		address token0;
		address token1;
	}

	/// @dev deposits[tokenId] => Deposit
	mapping(uint256 => Deposit) public deposits;

	constructor(
		INonfungiblePositionManager _nonfungiblePositionManager,
		ISwapRouter _swapRouter
	) {
		nonfungiblePositionManager = _nonfungiblePositionManager;
		swapRouter = _swapRouter;

		_owner = msg.sender;
		tickSpacingFeeAmount[10] = 500;
		tickSpacingFeeAmount[60] = 3000;
		tickSpacingFeeAmount[200] = 10000;
	}

	// Implementing `onERC721Received` so this contract can receive custody of erc721 tokens
	function onERC721Received(
		address operator,
		address,
		uint256 tokenId,
		bytes calldata
	) external override returns (bytes4) {
		// get position information

		_createDeposit(operator, tokenId);

		return this.onERC721Received.selector;
	}

	function _createDeposit(address owner, uint256 tokenId) internal {
		(
			,
			,
			address token0,
			address token1,
			,
			,
			,
			uint128 liquidity,
			,
			,
			,

		) = nonfungiblePositionManager.positions(tokenId);

		// set the owner and data for position
		// operator is msg.sender
		deposits[tokenId] = Deposit({
			owner: owner,
			liquidity: liquidity,
			token0: token0,
			token1: token1
		});
		emit createDeposit(owner, tokenId);
	}

	/// @notice Calls the mint function defined in periphery, mints the same amount of each token.
	/// @return tokenId The id of the newly minted ERC721
	/// @return liquidity The amount of liquidity for the position
	/// @return amount0 The amount of token0
	/// @return amount1 The amount of token1

	function mintNewPosition(
		address token0,
		address token1,
		int24 tickSpacing,
		int24 tickLower,
		int24 tickUpper,
		uint256 amount0ToMint,
		uint256 amount1ToMint
	)
		public
		returns (
			uint256 tokenId,
			uint128 liquidity,
			uint256 amount0,
			uint256 amount1
		)
	{
		// For this example, we will provide equal amounts of liquidity in both assets.
		// Providing liquidity in both assets means liquidity will be earning fees and is considered in-range.

		(token0, token1) = token0 < token1 ? (token0, token1) : (token1, token0);
		// Approve the position manager
		TransferHelper.safeApprove(
			token0,
			address(nonfungiblePositionManager),
			type(uint256).max / 2
		);
		TransferHelper.safeApprove(
			token1,
			address(nonfungiblePositionManager),
			type(uint256).max / 2
		);
		INonfungiblePositionManager.MintParams
			memory params = INonfungiblePositionManager.MintParams({
				token0: token0,
				token1: token1,
				fee: tickSpacingFeeAmount[tickSpacing],
				tickLower: tickLower,
				tickUpper: tickUpper,
				amount0Desired: amount0ToMint,
				amount1Desired: amount1ToMint,
				amount0Min: 0,
				amount1Min: 0,
				recipient: address(this),
				deadline: block.timestamp + 1 days
			});

		(tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(
			params
		);
		// Create a deposit
		_createDeposit(msg.sender, tokenId);

		// Remove allowance and refund in both assets.
		if (amount0 < amount0ToMint) {
			TransferHelper.safeApprove(
				token0,
				address(nonfungiblePositionManager),
				0
			);
			uint256 refund0 = amount0ToMint - amount0;
			TransferHelper.safeTransfer(token0, msg.sender, refund0);
		}

		if (amount1 < amount1ToMint) {
			TransferHelper.safeApprove(
				token1,
				address(nonfungiblePositionManager),
				0
			);
			uint256 refund1 = amount1ToMint - amount1;
			TransferHelper.safeTransfer(token1, msg.sender, refund1);
		}
	}

	/// @notice Collects the fees associated with provided liquidity
	/// @dev The contract must hold the erc721 token before it can collect fees
	/// @param tokenId The id of the erc721 token
	/// @return amount0 The amount of fees collected in token0
	/// @return amount1 The amount of fees collected in token1
	function collectAllFees(
		uint256 tokenId
	) external returns (uint256 amount0, uint256 amount1) {
		// Caller must own the ERC721 position, meaning it must be a deposit

		// set amount0Max and amount1Max to uint256.max to collect all fees
		// alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
		INonfungiblePositionManager.CollectParams
			memory params = INonfungiblePositionManager.CollectParams({
				tokenId: tokenId,
				recipient: address(this),
				amount0Max: type(uint128).max,
				amount1Max: type(uint128).max
			});

		(amount0, amount1) = nonfungiblePositionManager.collect(params);

		// send collected feed back to owner
		_sendToOwner(tokenId, amount0, amount1);
	}

	/// @notice A function that decreases the current liquidity by half. An example to show how to call the `decreaseLiquidity` function defined in periphery.
	/// @param tokenId The id of the erc721 token
	/// @return amount0 The amount received back in token0
	/// @return amount1 The amount returned back in token1

	function decreaseLiquidityInHalf(
		uint256 tokenId
	) external returns (uint256 amount0, uint256 amount1) {
		decreaseLiquidity(tokenId, deposits[tokenId].liquidity / 2);
	}

	function decreaseLiquidityFull(
		uint256 tokenId
	) external returns (uint256 amount0, uint256 amount1) {
		decreaseLiquidity(tokenId, deposits[tokenId].liquidity);
	}
	function decreaseLiquidity(
		uint256 tokenId,
		uint128 liquidity
	) internal returns (uint256 amount0, uint256 amount1) {
		// caller must be the owner of the NFT
		require(msg.sender == deposits[tokenId].owner, "Not the owner");
		require(liquidity > 0, "Liquidity must be greater than 0");
		require(liquidity <= deposits[tokenId].liquidity, "Liquidity too high");

		// amount0Min and amount1Min are price slippage checks
		// if the amount received after burning is not greater than these minimums, transaction will fail
		INonfungiblePositionManager.DecreaseLiquidityParams
			memory params = INonfungiblePositionManager.DecreaseLiquidityParams({
				tokenId: tokenId,
				liquidity: liquidity,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp
			});

		(amount0, amount1) = nonfungiblePositionManager.decreaseLiquidity(params);
		deposits[tokenId].liquidity -= (liquidity);

		//send liquidity back to owner
		_sendToOwner(tokenId, amount0, amount1);
	}

	/// @notice Increases liquidity in the current range
	/// @dev Pool must be initialized already to add liquidity
	/// @param tokenId The id of the erc721 token
	/// @param amount0 The amount to add of token0
	/// @param amount1 The amount to add of token1
	function increaseLiquidityCurrentRange(
		uint256 tokenId,
		uint256 amountAdd0,
		uint256 amountAdd1
	) external returns (uint128 liquidity, uint256 amount0, uint256 amount1) {
		TransferHelper.safeApprove(
			deposits[tokenId].token0,
			address(nonfungiblePositionManager),
			amountAdd0
		);
		TransferHelper.safeApprove(
			deposits[tokenId].token1,
			address(nonfungiblePositionManager),
			amountAdd1
		);
		console.log("increaseLiquidityCurrentRange");
		INonfungiblePositionManager.IncreaseLiquidityParams
			memory params = INonfungiblePositionManager.IncreaseLiquidityParams({
				tokenId: tokenId,
				amount0Desired: amountAdd0,
				amount1Desired: amountAdd1,
				amount0Min: 0,
				amount1Min: 0,
				deadline: block.timestamp
			});

		(liquidity, amount0, amount1) = nonfungiblePositionManager
			.increaseLiquidity(params);
	}

	/// @notice Transfers funds to owner of NFT
	/// @param tokenId The id of the erc721
	/// @param amount0 The amount of token0
	/// @param amount1 The amount of token1
	function _sendToOwner(
		uint256 tokenId,
		uint256 amount0,
		uint256 amount1
	) internal {
		// get owner of contract
		address owner = deposits[tokenId].owner;

		address token0 = deposits[tokenId].token0;
		address token1 = deposits[tokenId].token1;
		// send collected fees to owner
		TransferHelper.safeTransfer(token0, owner, amount0);
		TransferHelper.safeTransfer(token1, owner, amount1);
	}

	/// @notice Transfers the NFT to the owner
	/// @param tokenId The id of the erc721
	function retrieveNFT(uint256 tokenId) external {
		// must be the owner of the NFT
		require(msg.sender == deposits[tokenId].owner, "Not the owner");
		// transfer ownership to original owner
		nonfungiblePositionManager.safeTransferFrom(
			address(this),
			msg.sender,
			tokenId
		);
		//remove information related to tokenId
		delete deposits[tokenId];
	}

	function swapToken(
		address tokenIn,
		address tokenOut,
		uint256 amountIn,
		uint24 fee
	) external returns (uint256 amountOut) {
		// Transfer the specified amount of tokenIn to this contract.
		TransferHelper.safeTransferFrom(tokenIn, msg.sender, address(this), amountIn);
		// Approve the router to spend tokenIn.
		TransferHelper.safeApprove(tokenIn, address(swapRouter), amountIn);
		console.log("Approve the router to spend TokenIn: ", amountIn);
		// Note: To use this example, you should explicitly set slippage limits, omitting for simplicity
		uint256 minOut = /* Calculate min output */ 0;
		uint160 priceLimit = /* Calculate price limit */ 0;
		// Create the params that will be used to execute the swap
		ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
			.ExactInputSingleParams({
				tokenIn: tokenIn,
				tokenOut: tokenOut,
				fee: fee,
				recipient: msg.sender,
				deadline: block.timestamp,
				amountIn: amountIn,
				amountOutMinimum: minOut,
				sqrtPriceLimitX96: priceLimit
			});
		// The call to `exactInputSingle` executes the swap.
		amountOut = swapRouter.exactInputSingle(params);
	}

	/* 提取token */
	function getToken(address token0) external {
		require(msg.sender == _owner, "Not Owner!");
		uint256 amount = IERC20(token0).balanceOf(address(this));
		TransferHelper.safeTransfer(token0, _owner, amount);
	}
	receive() external payable {}
}

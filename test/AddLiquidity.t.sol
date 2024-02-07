//SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;
pragma abicoder v2;

import {console2} from "forge-std/Test.sol";
import {BaseDeploy} from "test/utils/BaseDeploy.sol";

import {TransferHelper} from "contracts/v3-periphery/libraries/TransferHelper.sol";
import {INonfungiblePositionManager} from "contracts/v3-periphery/interfaces/INonfungiblePositionManager.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {SimpleSwap} from "src/SimpleSwap.sol";

contract SimpleSwapTest is BaseDeploy, IERC721Receiver {
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
    }

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

    function test_mintNewPosition() public {
        vm.startPrank(deployer);
        /* 创建池子 */
        mintNewPool(tokens[1], tokens[2], poolFee, INIT_PRICE);
        mintNewPosition(tokens[1], tokens[2]);
        vm.stopPrank();
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
    }

    function mintNewPool(
        address token0,
        address token1,
        uint24 poolFee,
        uint160 currentPrice
    ) internal {
        /* 创建池子 */
        nonfungiblePositionManager.createAndInitializePoolIfNecessary(
            token0,
            token1,
            poolFee,
            currentPrice
        );
    }

    function mintNewPosition(
        address token0,
        address token1
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
        uint256 amount0ToMint = 1000000;
        uint256 amount1ToMint = 1000000;

        (token0, token1) = token0 < token1
            ? (token0, token1)
            : (token1, token0);
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
        int24 tickSpacing = 60;
        int24 tickLower = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 tickUpper = ((TickMath.MAX_TICK / tickSpacing) * tickSpacing);

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: tickLower,
                tickUpper: tickUpper,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: deployer,
                deadline: block.timestamp + 1 days
            });

        // Note that the pool defined by DAI/USDC and fee tier 0.3% must already be created and initialized in order to mint
        (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager
            .mint(params);
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
}

//SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma abicoder v2;

import {Test, console2} from "forge-std/Test.sol";

import {SwapRouter} from "contracts/v3-periphery/SwapRouter.sol";
import {TransferHelper} from "contracts/v3-periphery/libraries/TransferHelper.sol";
import {LiquidityManagement} from "contracts/v3-periphery/base/LiquidityManagement.sol";
import {NonfungiblePositionManager} from "contracts/v3-periphery/NonfungiblePositionManager.sol";
import {INonfungiblePositionManager} from "contracts/v3-periphery/interfaces/INonfungiblePositionManager.sol";

import {UniswapV3Factory} from "contracts/v3-core/UniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "contracts/v3-periphery/libraries/PoolAddress.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {TestToken} from "src/TestToken.sol";
import {TestNonfungible} from "src/TestNonfungible.sol";
import {SimpleSwap} from "src/SimpleSwap.sol";
import "forge-std/StdUtils.sol";

contract SimpleSwapTest is Test, IERC721Receiver {
    address public deployer = vm.envAddress("LOCAL_DEPLOYER");
    UniswapV3Factory internal poolFactory;
    SwapRouter internal swapRouter;
    TestNonfungible internal testNonfungible;
    NonfungiblePositionManager internal nonfungiblePositionManager;

    address internal WETH9;
    address internal TUSDC;
    address internal TDAI;

    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint24 public constant poolFee = 500;
    uint160 internal constant INIT_PRICE = 5e10;

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
    function setUp() public {
        /* 配置Uniswap环境 */
        vm.startPrank(deployer);
        // Deploy WETH9 token
        WETH9 = address(new TestToken("WETH9", "WETH9"));
        TDAI = address(new TestToken("TESTDAI", "TDAI"));
        TUSDC = address(new TestToken("TESTUSDC", "TUSDC"));
        // Deploy UniswapV3Factory contract
        poolFactory = new UniswapV3Factory();
        // Deploy SwapRouter contract
        swapRouter = new SwapRouter(address(poolFactory), WETH9);
        // Deploy TestNonfungible contract
        testNonfungible = new TestNonfungible();
        nonfungiblePositionManager = new NonfungiblePositionManager(
            address(poolFactory),
            WETH9,
            address(testNonfungible)
        );

        /* 给deployer转足够数量的token */
        // deal(DAI, deployer, 10000);
        // deal(USDC, deployer, 10000e18);
        // if (IERC20(DAI).balanceOf(deployer) != 100e18) revert();
        // assert(IERC20(USDC).balanceOf(deployer) == 100e18);
        // console2.log("USDC amount:", IERC20(USDC).balanceOf(deployer));

        /* 创建池子 */
        address poolOne = nonfungiblePositionManager
            .createAndInitializePoolIfNecessary(DAI, USDC, poolFee, INIT_PRICE);

        PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
            token0: DAI,
            token1: USDC,
            fee: poolFee
        });

        address computeAddress = PoolAddress.computeAddress(
            address(poolFactory),
            poolKey
        );

        console2.log("computeAddress:", computeAddress);

        assertEq(computeAddress, address(poolOne));

        // mintNewPosition(USDC, DAI);
        mintNewPosition(DAI, USDC);
        vm.stopPrank();
    }

    function test_simpleSwap() public {
        vm.startBroadcast(deployer);
        SimpleSwap simpleSwap = new SimpleSwap(swapRouter, WETH9);
        IERC20(WETH9).approve(address(simpleSwap), 100);
        simpleSwap.swapWETHForDAI(10);
        vm.stopBroadcast();
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
        uint256 amount0ToMint = 1000;
        uint256 amount1ToMint = 1000;

        (token0, token1) = token0 < token1
            ? (token0, token1)
            : (token1, token0);

        // Approve the position manager
        TransferHelper.safeApprove(
            token0,
            address(nonfungiblePositionManager),
            amount0ToMint
        );
        TransferHelper.safeApprove(
            token1,
            address(nonfungiblePositionManager),
            amount1ToMint
        );

        INonfungiblePositionManager.MintParams
            memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: poolFee,
                tickLower: TickMath.MIN_TICK,
                tickUpper: TickMath.MAX_TICK,
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0,
                recipient: address(this),
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

# UniswapV3 学习之路 - - Foundry Edition

## 1. 项目代码概述

首先，UniswapV3 在代码层面的架构和 UniswapV2 的变化则不大，合约层面，主要还是两个库：

- **v3-core**
- **v3-periphery**

### **v3-core**

core 合约是 uniswap 中负责掌管 pool 和 factory 的仓库。

- **UniswapV3Pool**：：是资金存储和交换运算的合约。
- **UniswapV3Factory**：用于批量创造 Pool 的合约。这两个合约是整个 uniswap 的核心。就算在没有 periphery 的情况下，也能正常运行的最小合约。

### **v3-periphery**

periphery 存放的是外围合约，这些合约是给用户和开发者一个统一的接口或者是便捷的通证。核心合约有 NFTManager 和 SwapRouter。

- **NonfungiblePositionManager**：一个用于记录用户创建的流动性各类数据的合约。
- **SwapRouter**：包装类，将交换的各种逻辑进行包装抽象

与 UniswapV2 不同，不再由 Router 合约作为添加流动性、移除流动性和兑换交易的全部入口，而是把流动性相关的功能放到了单独的合约 NonfungiblePositionManager，而 SwapRouter 主要只用于交易入口。

## 2. 使用 Foundry 部署

## 使用 v3-periphery 部署 UniswapV3

- 具体的代码在`test/utils/BaseDeploy.sol:setUp`

### 1. 首先部署 v3-periphery

```solidity
string constant v3FactoryArtifact = "node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json";
string constant weth9Artifact = "test/utils/WETH9.json";
    function setUp() public virtual {
        ......
        // Deploy UniswapV3Factory contract
        address _factory = deployCode(v3FactoryArtifact);
        poolFactory = IUniswapV3Factory(_factory);
        // Deploy SwapRouter contract
        swapRouter = new SwapRouter(address(poolFactory), address(weth9));
        // Deploy TestNonfungible contract
        nonfungiblePositionManager = new NonfungiblePositionManager(
            address(poolFactory),
            address(weth9),
            address(
                new NonfungibleTokenPositionDescriptor(
                    address(_weth9),
                    bytes32("WETH9")
                )
            )
        );
        ......
    }
```

这块需要注意，UniswapV3Factory 合约通过读取`"node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"`以及`deployCode`来部署，这一步是为了保证通过 poolFactory 部署的 pool 跟 mintPosition 的池子解析的地址一致。

### 2. 部署 uniswap pool

在这采用的是 v3-periphery 的`createAndInitializePoolIfNecessary`方法来创建 pool，这个方法会调用`createPool`来创建 pool,并对池子进行初始化。pool 合约由交易币对和手续费组成。

```solidity
    nonfungiblePositionManager.createAndInitializePoolIfNecessary(
			token0,
			token1,
			fee,
			currentPrice
		);
```

实际上，每一对 token 最多只有 3 个池子合约，因为交易费率`fee`只有三个选择，poolFactory 合约参数如下：

```solidity
feeAmountTickSpacing[500] = 10;
feeAmountTickSpacing[3000] = 60;
feeAmountTickSpacing[10000] = 200;
```

### 3. 通过 mint position 来提供 uniswap pool 流动性

在这需要注意的是，mintPosition 方法会调用`NonfungiblePositionManager.mint`方法来提供流动性，在调用`mint`之前需要保证对应的池子合约已经存在，

```solidity
/// @notice Add liquidity to an initialized pool
    contracts/v3-periphery/base/LiquidityManagement.sol：
    function addLiquidity(
    	AddLiquidityParams memory params
    )
    	internal
    	returns (
    		uint128 liquidity,
    		uint256 amount0,
    		uint256 amount1,
    		IUniswapV3Pool pool
    	)
    {
@>    	PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
    		token0: params.token0,
    		token1: params.token1,
    		fee: params.fee
    	});

@>     	pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));

    	// compute the liquidity amount
    	{
    		(uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
    		uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
    		uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

    		liquidity = LiquidityAmounts.getLiquidityForAmounts(
    			sqrtPriceX96,
    			sqrtRatioAX96,
    			sqrtRatioBX96,
    			params.amount0Desired,
    			params.amount1Desired
    		);
    	}
    }
```

这块可以很明显地看到，`addLiquidity`方法会调用`PoolAddress.computeAddress`方法来获取池子的地址，然后通过`IUniswapV3Pool`来调用`mint`方法来提供流动性，如果使用 core 合约部署 poolFactory 合约，可能会出现`pool`地址不一致的情况。

```shell
revert:stdstorage find(stdstorage): Slot(s)not found

Failing tests:
Encountered 1 failing test in test/SimpleSwap.t.sol:SimpleSwapTest[FAIL. Reason: setup failed: revert: stdstorage find(stdstorage): slot(s) not found.] setUp()(gas: 0)
```

#### mint position 的边界情况

1. `tickLow` 和 `tickUpper`未被 `tickSpacing`整除

```solidity
// contracts/v3-core/libraries/TickBitmap.sol
function flipTick(...) internal {
@>	require(tick % tickSpacing == 0); // ensure that the tick is spaced
	(int16 wordPos, uint8 bitPos) = position(tick / tickSpacing);
	uint256 mask = 1 << bitPos;
	self[wordPos] ^= mask;
}
```

2. 流动性溢出

```solidity
// contracts/v3-core/libraries/Tick.sol:Tick.update:
function update(...) internal returns (bool flipped) {
        ...
        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

@>      require(liquidityGrossAfter <= maxLiquidity, 'LO');
		...
}
```
错误信息如下，
```shell
[65528] core_SimpleSwapTest::test_fuzz_core_MintNewPosition(-14010 [-1.401e4], 138730 [1.387e5], 1917569901783203986719870431556010 [1.917e33])
    ├─ [0] VM::assume(true) [staticcall]
    │   └─ ← ()
    ├─ [0] console::log("tickLower:", -14010 [-1.401e4]) [staticcall]
    │   └─ ← ()
    ├─ [0] console::log("tickUpper:", 138730 [1.387e5]) [staticcall]
    │   └─ ← ()
    ├─ [0] console::log("liquidity:", 1917569901783203986719870431556010 [1.917e33]) [staticcall]
    │   └─ ← ()
    ├─ [0] console::log("amount0ToMint:", 2709989481056669618208985953403326 [2.709e33]) [staticcall]
    │   └─ ← ()
    ├─ [0] console::log("amount1ToMint:", 404132314446474599733383343501835 [4.041e32]) [staticcall]
    │   └─ ← ()
    ├─ [2666] UniswapV3Factory::getPool(TestERC20: [0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0], TestERC20: [0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9], 500) [staticcall]
    │   └─ ← UniswapV3Pool: [0x48D5A48818b36843Ed03EE7217C9a2F911667FAe]
    ├─ [2696] UniswapV3Pool::slot0() [staticcall]
    │   └─ ← 56022770974786139918731938227 [5.602e28], -6932, 0, 1, 1, 0, true
    ├─ [16894] UniswapV3Pool::mint(DefaultSender: [0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38], -14010 [-1.401e4], 138730 [1.387e5], 1917569901783203986719870431555991 [1.917e33], 0x0000000000000000000000009fe46736679d2d9a65f0992f2272de9f3c7fa6e0000000000000000000000000cf7ed3acca5a467e9e704c703e8d87f634fb0fc900000000000000000000000000000000000000000000000000000000000001f4000000000000000000000000f39fd6e51aad88f6f4ce6ab8827279cfffb92266)
    │   └─ ← revert: LO
    └─ ← revert: LO
```

1.

## 使用 v3-core 部署 UniswapV3

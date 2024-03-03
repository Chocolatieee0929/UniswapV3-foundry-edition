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

这块需要注意，UniswapV3Factory 合约通过读取`"node_modules/@uniswap/v3-core/artifacts/contracts/UniswapV3Factory.sol/UniswapV3Factory.json"`以及`deployCode`来部署，这一步是为了保证通过 poolFactory 部署的 pool 跟 mintPosition 的池子解析的地址一致，为什么会不一致呢，我们后续再分析。

### 2. 部署 uniswap pool

在这采用的是 v3-periphery 的`createAndInitializePoolIfNecessary`方法来创建 pool，首先调用工厂合约的`createPool`函数来创建 pool,并对池子进行初始化，pool 合约由交易币对和手续费组成。
```solidity
    nonfungiblePositionManager.createAndInitializePoolIfNecessary(
			token0,
			token1,
			fee,
			currentPrice
		);
```
```
  function createAndInitializePoolIfNecessary(address token0,address token1,uint24 fee,uint160 sqrtPriceX96)
      external payable override
      returns (address pool) {
          ...
  @>          pool = IUniswapV3Factory(factory).createPool(token0, token1, fee);
              IUniswapV3Pool(pool).initialize(sqrtPriceX96);
          ...
    }
```
我们继续深入研究工厂合约是如何部署pool的，当调用 `createPool`函数时，工厂合约会首先会根据`require(getPool[token0][token1][fee] == address(0))` 判断池子是否存在，不存在才会往下执行，也就是说**交易对的地址以及选择的费率就决定了池子的唯一性**，之后通过 create2 方法进行部署。

```solidity
    function createPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external override noDelegateCall returns (address pool) {
        require(tokenA != tokenB);
        // 默认池子里的token是有序的 --> 盐值计算/zeroForOne
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0));
        int24 tickSpacing = feeAmountTickSpacing[fee];
        require(tickSpacing != 0);
        // 避免池子重复
        require(getPool[token0][token1][fee] == address(0));
@>      pool = deploy(address(this), token0, token1, fee, tickSpacing);
        getPool[token0][token1][fee] = pool;
        // populate mapping in the reverse direction, deliberate choice to avoid the cost of comparing addresses
        getPool[token1][token0][fee] = pool;
        emit PoolCreated(token0, token1, fee, tickSpacing, pool);
    }
    /// 函数在 contracts/v3-core/UniswapV3PoolDeployer.sol ，工厂合约继承了该合约
    function deploy(address factory, address token0, address token1, uint24 fee, int24 tickSpacing)
        internal
        returns (address pool)
    {
        parameters = Parameters({factory: factory, token0: token0, token1: token1, fee: fee, tickSpacing: tickSpacing});
        // parameters 其实是传给 UniswapV3Pool 的参数
        pool = address(new UniswapV3Pool{salt: keccak256(abi.encode(token0, token1, fee))}());
        delete parameters;
    }
```
使用new关键字创建了一个UniswapV3Pool合约的新实例，并使用salt选项指定了一个唯一的盐值。盐值是通过对token0、token1和fee参数进行串联后进行哈希得到的。这个唯一的盐值有助于在使用相似的初始化参数部署多个合约实例时避免碰撞。
```
contract UniswapV3Pool {
    ...
    constructor() {
        int24 _tickSpacing;
        (factory, token0, token1, fee, _tickSpacing) = IUniswapV3PoolDeployer(msg.sender).parameters();
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }
    ...
}
```
UniswapV3Pool合约的构造函数初始化了它的状态变量。它从调用者（即部署者）处获取IUniswapV3PoolDeployer合约返回的parameters结构体中提取了参数，如factory、token0、token1、fee和_tickSpacing。然后，它将合约的tickSpacing变量设置为_tickSpacing。

这一部分值得注意的：

1. 实际上，每一对 token 最多只有 3 个池子合约，因为交易费率`fee`只有三个选择，poolFactory 合约参数如下：

```solidity
feeAmountTickSpacing[500] = 10;
feeAmountTickSpacing[3000] = 60;
feeAmountTickSpacing[10000] = 200;
```

2. 任意用户都能够通过调用`nonfungiblePositionManager.createAndInitializePoolIfNecessary`来创建池子，在`v3-periphery/base/PoolInitializer.sol:createAndInitializePoolIfNecessary`可以看见该函数没有调用者的限制条件，实际上，是由 nonfungiblePositionManager 通过调用`UniswapV3Factory.createPool`来创建并初始化池子。


### 3. 通过 mint position 来提供 uniswap pool 流动性

在这需要注意的是，mintPosition 方法会调用`NonfungiblePositionManager.mint`方法来提供流动性，在调用`mint`之前需要保证对应的池子合约已经存在，调用的是`v3-periphery/base/LiquidityManagement.sol`的方法

```solidity
/// @notice Add liquidity to an initialized pool
    function addLiquidity(
    	AddLiquidityParams memory params
    )
    	internal
    	returns (uint128 liquidity,uint256 amount0,uint256 amount1,IUniswapV3Pool pool)
    {
           	PoolAddress.PoolKey memory poolKey = PoolAddress.PoolKey({
    		token0: params.token0,
    		token1: params.token1,
    		fee: params.fee
    	});

---    	pool = IUniswapV3Pool(PoolAddress.computeAddress(factory, poolKey));
|
|    	// compute the liquidity amount
|    	{
--- >    	(uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
    		uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(params.tickLower);
    		uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(params.tickUpper);

    		liquidity = LiquidityAmounts.getLiquidityForAmounts(sqrtPriceX96,sqrtRatioAX96,sqrtRatioBX96,
    			params.amount0Desired,
    			params.amount1Desired
    		);
    	}
    }
```

这块可以很明显地看到，`addLiquidity`方法会调用`PoolAddress.computeAddress`方法来获取池子的地址，然后通过`IUniswapV3Pool`来调用`mint`方法来提供流动性，如果使用`poolFactory = new UniswapV3Pool()`来部署，可能会出现`pool`地址不一致的情况。

```shell
revert:stdstorage find(stdstorage): Slot(s)not found

Failing tests:
Encountered 1 failing test in test/SimpleSwap.t.sol:SimpleSwapTest[FAIL. Reason: setup failed: revert: stdstorage find(stdstorage): slot(s) not found.] setUp()(gas: 0)
```
#### 如何计算 pool 地址
我们可以看一下 v3-periphery 是如何计算 pool 的地址，在 `contracts/v3-periphery/libraries/PoolAddress.sol`这个库里，
```
    bytes32 internal constant POOL_INIT_CODE_HASH = 0xf44a6ca8f731f3b2fbcec713be7a4aac0f6def89dde83092b2d61766e95c95e3;

    function computeAddress(address factory, PoolKey memory key) internal pure returns (address pool) {
        require(key.token0 < key.token1);
        pool = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex'ff',
                        factory,
                        keccak256(abi.encode(key.token0, key.token1, key.fee)),
                        POOL_INIT_CODE_HASH
                    )
                )
            )
        );
    }
```
`POOL_INIT_CODE_HASH`是什么呢，为什么可以通过`address(uint256(keccak256(abi.encodePacked(hex'ff',factory,keccak256(abi.encode(key.token0, key.token1, key.fee)),POOL_INIT_CODE_HASH)))))`计算出来，首先了解一下[create2](https://docs.soliditylang.org/en/latest/control-structures.html#salted-contract-creations-create2)，里面提到 create2 根据创建合约的地址、指定的 salt 值、创建的合约的（创建）字节码和构造函数参数来计算新合约的地址，同样也可以通过相应规则计算出地址。
```
// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.7.0 <0.9.0;
contract D {}
contract C {
    function createDSalted(bytes32 salt) public {
        address predictedAddress = address(uint160(uint(keccak256(abi.encodePacked(
            bytes1(0xff),
            address(this),
            salt,
            keccak256(abi.encodePacked(
                type(D).creationCode,
                abi.encode(arg)
            ))
        )))));

        D d = new D{salt: salt}();
        require(address(d) == predictedAddress);
    }
}
```
我们在Pool合约的任何操作都会改变其字节码，我们可以通过 `bytes32 POOL_INIT_CODE_HASH = keccak256(abi.encodePacked(type(UniswapV3Pool).creationCode))` 修改 POOL_INIT_CODE_HASH。
通过 core 部署工厂合约的测试代码[在这](https://github.com/Chocolatieee0929/UniswapV3-foundry-edition/blob/main/test/INIT_CODE.t.sol)。

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
对流动性边界测试完整代码[在这](https://github.com/Chocolatieee0929/UniswapV3-foundry-edition/blob/main/test/SwapRouter.t.sol)
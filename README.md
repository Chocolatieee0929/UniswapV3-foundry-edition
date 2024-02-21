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

## 使用 Foundry 框架部署 UniswapV3

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

// SPDX-License-Identifier:MIT
pragma solidity =0.7.6;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract TestNonfungible is ERC721 {
    constructor() ERC721("TestNonfungible", "TN") {
        _mint(msg.sender, 100000 * 10 ** 18);
    }
}

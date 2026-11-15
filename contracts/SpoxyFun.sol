// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Minimal interface for the Binance Agent ID ERC-721 registry.
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title SpoxyFun
/// @notice V2 collection: up to 800 free mints (max 3 per wallet, Agent ID required)
/// and unrestricted paid mints at 0.001 BNB each. The original 2,222-token
/// random draw pool and metadata behavior are retained.
contract SpoxyFun is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 2222;
    uint256 public constant FREE_SUPPLY = 800;
    uint256 public constant FREE_PER_WALLET = 3;
    uint256 public constant MINT_PRICE = 0.001 ether;

    address public immutable agentIdRegistry;
    bool public mintOpen;
    string public baseURI;
    uint256 public totalMinted;
    uint256 public freeMinted;
    uint256 public remaining = MAX_SUPPLY;
    mapping(address => uint256) public freeMintedByWallet;
    mapping(uint256 => uint256) private _pool;
    uint256 private _mintNonce;

    event SpoxyMinted(address indexed minter, uint256 indexed tokenId, uint256 pricePaid, bool freeMint);
    event MintOpenChanged(bool open);
    event BaseURIChanged(string baseURI);

    error MintClosed();
    error MissingAgentId();
    error InvalidAgentIdRegistry();
    error MaxSupplyReached();
    error FreeSupplyReached();
    error FreeWalletLimitReached();
    error InsufficientPayment(uint256 required, uint256 sent);
    error WithdrawFailed();

    constructor(address _agentIdRegistry, string memory _baseURI)
        ERC721("SpoxyFun", "SPOXY")
        Ownable(msg.sender)
    {
        if (_agentIdRegistry == address(0)) revert InvalidAgentIdRegistry();
        agentIdRegistry = _agentIdRegistry;
        baseURI = _baseURI;
    }

    function setMintOpen(bool open_) external onlyOwner {
        mintOpen = open_;
        emit MintOpenChanged(open_);
    }

    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    function currentPrice() external pure returns (uint256) {
        return MINT_PRICE;
    }

    /// @notice Free mint. Only Agent ID holders; maximum 800 total and 3 per wallet.
    function freeMint() external nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (IAgentIdRegistry(agentIdRegistry).balanceOf(msg.sender) == 0) revert MissingAgentId();
        if (totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();
        if (freeMinted >= FREE_SUPPLY) revert FreeSupplyReached();
        if (freeMintedByWallet[msg.sender] >= FREE_PER_WALLET) revert FreeWalletLimitReached();

        freeMinted += 1;
        freeMintedByWallet[msg.sender] += 1;
        uint256 tokenId = _drawTokenId();
        totalMinted += 1;
        _safeMint(msg.sender, tokenId);
        emit SpoxyMinted(msg.sender, tokenId, 0, true);
    }

    /// @notice Paid mint is available immediately to any wallet, without Agent ID.
    function mint() external payable nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();
        uint256 price = MINT_PRICE;
        if (msg.value < price) revert InsufficientPayment(price, msg.value);

        uint256 tokenId = _drawTokenId();
        totalMinted += 1;
        _safeMint(msg.sender, tokenId);
        emit SpoxyMinted(msg.sender, tokenId, price, false);
        _refund(msg.value - price);
    }

    function _drawTokenId() internal returns (uint256 tokenId) {
        uint256 left = remaining;
        uint256 rand = uint256(keccak256(abi.encodePacked(block.prevrandao, block.timestamp, msg.sender, _mintNonce)));
        _mintNonce += 1;
        uint256 idx = rand % left;
        tokenId = _pool[idx];
        if (tokenId == 0) tokenId = idx + 1;

        uint256 lastIdx = left - 1;
        uint256 lastId = _pool[lastIdx];
        if (lastId == 0) lastId = lastIdx + 1;
        if (idx != lastIdx) _pool[idx] = lastId;
        delete _pool[lastIdx];
        remaining = left - 1;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool ok,) = payable(owner()).call{value: balance}("");
        if (!ok) revert WithdrawFailed();
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory base = baseURI;
        if (bytes(base).length == 0) return "";
        return string.concat(base, tokenId.toString(), ".json");
    }

    function _refund(uint256 amount) internal {
        if (amount == 0) return;
        (bool ok,) = payable(msg.sender).call{value: amount}("");
        require(ok, "refund failed");
    }
}

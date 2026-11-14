// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @notice Minimal view of the Binance Agent ID registry (ERC-721):
/// minting only checks that the caller holds at least one Agent ID.
interface IAgentIdRegistry {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title SpoxyFun
/// @notice ERC721 collection of 2,222 cute spooky-fun ghosts on BNB Chain.
/// Minting is a random draw: each mint assigns a random unminted token ID
/// (swap-and-pop pool), so the minter never picks a number. Every ID 1-2222
/// is drawn exactly once. One mint price for every token ID: 0.0001 BNB.
/// Mint fees stay in the contract ("fee goes to the contract wallet") and
/// only the owner can withdraw them with withdraw().
/// Minting requires a Binance Agent ID: the minter must hold at least one
/// Agent ID (ERC-721) from the registry registered at deploy time.
/// No whitelist. Mint starts CLOSED. Nobody can mint until the owner
/// opens it with setMintOpen(true). The owner can close it again at any time.
/// Artwork lives off-chain: tokenURI returns baseURI + tokenId + ".json",
/// pointing at the hosted metadata folder. The base URI is set at deploy
/// time (it may be empty) and can be changed by the owner at any time
/// with setBaseURI. While the base URI is empty, tokenURI returns "".
contract SpoxyFun is ERC721, Ownable, ReentrancyGuard {
    using Strings for uint256;

    uint256 public constant MAX_SUPPLY = 2222;
    uint256 public constant MINT_PRICE = 0.0001 ether;

    /// @notice Binance Agent ID registry, registered once at deploy time
    /// via the constructor argument. Minting requires
    /// balanceOf(msg.sender) > 0 on this registry.
    address public immutable agentIdRegistry;

    /// @notice Mint starts CLOSED. Nobody can mint until the owner opens it
    /// with setMintOpen(true). The owner can close it again at any time.
    bool public mintOpen;

    /// @notice Base URI for token metadata, e.g.
    /// "https://example.com/nft/metadata/". tokenURI appends the token
    /// ID and ".json". Empty until the owner sets it.
    string public baseURI;

    uint256 public totalMinted;

    /// @notice How many token IDs are still unminted. Valid pool indices
    /// are 0 .. remaining-1; it starts at MAX_SUPPLY and drops by one
    /// per mint.
    uint256 public remaining = MAX_SUPPLY;

    /// @notice Unminted ID pool (swap-and-pop). _pool[i] is the token ID
    /// at index i, or 0 meaning the identity ID i + 1. Drawing an index
    /// removes its ID from the pool by moving the last ID into its slot.
    mapping(uint256 => uint256) private _pool;

    /// @notice Increments on every mint so consecutive draws differ even
    /// within the same block.
    uint256 private _mintNonce;

    event SpoxyMinted(address indexed minter, uint256 indexed tokenId, uint256 pricePaid);
    event MintOpenChanged(bool open);
    event BaseURIChanged(string baseURI);

    error MintClosed();
    error MissingAgentId();
    error InvalidAgentIdRegistry();
    error MaxSupplyReached();
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

    /// @notice Open or close minting. Owner only. Mint is closed at deploy.
    function setMintOpen(bool open_) external onlyOwner {
        mintOpen = open_;
        emit MintOpenChanged(open_);
    }

    /// @notice Set the metadata base URI. Owner only. tokenURI appends
    /// the token ID and ".json" to this value.
    function setBaseURI(string calldata newBaseURI) external onlyOwner {
        baseURI = newBaseURI;
        emit BaseURIChanged(newBaseURI);
    }

    /// @notice Price of the next mint. One price for every token ID.
    function currentPrice() external pure returns (uint256) {
        return MINT_PRICE;
    }

    /// @notice Mint a random unminted token ID. The ID is drawn by the
    /// contract from the unminted pool (swap-and-pop) — it cannot be
    /// chosen by the minter. Every ID 1-2222 is drawn exactly once.
    /// The caller must hold at least one Binance Agent ID from the
    /// registry registered at deploy time.
    function mint() external payable nonReentrant {
        if (!mintOpen) revert MintClosed();
        if (IAgentIdRegistry(agentIdRegistry).balanceOf(msg.sender) == 0) revert MissingAgentId();
        if (totalMinted >= MAX_SUPPLY) revert MaxSupplyReached();

        uint256 price = MINT_PRICE;
        if (msg.value < price) revert InsufficientPayment(price, msg.value);

        uint256 remaining_ = remaining;
        uint256 rand = uint256(
            keccak256(abi.encodePacked(block.prevrandao, block.timestamp, msg.sender, _mintNonce))
        );
        _mintNonce += 1;
        uint256 idx = rand % remaining_;
        uint256 tokenId = _pool[idx];
        if (tokenId == 0) tokenId = idx + 1;

        uint256 lastIdx = remaining_ - 1;
        uint256 lastId = _pool[lastIdx];
        if (lastId == 0) lastId = lastIdx + 1;
        if (idx != lastIdx) {
            _pool[idx] = lastId;
        }
        delete _pool[lastIdx];

        remaining = remaining_ - 1;
        totalMinted += 1;
        _safeMint(msg.sender, tokenId);
        emit SpoxyMinted(msg.sender, tokenId, price);

        _refund(msg.value - price);
    }

    /// @notice Withdraw collected mint fees to the owner.
    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        (bool ok, ) = payable(owner()).call{value: balance}("");
        if (!ok) revert WithdrawFailed();
    }

    /// @notice Metadata URI: baseURI + tokenId + ".json". Returns ""
    /// while no base URI is set. Reverts for unminted IDs.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);
        string memory base = baseURI;
        if (bytes(base).length == 0) return "";
        return string.concat(base, tokenId.toString(), ".json");
    }

    function _refund(uint256 amount) internal {
        if (amount == 0) return;
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "refund failed");
    }
}

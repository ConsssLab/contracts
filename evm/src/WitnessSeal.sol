// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

/// @title WitnessSeal — soulbound Validators' Witness (Battle 3 only).
/// @notice ERC-5192 soulbound NFT. Once minted, the seal cannot be transferred.
/// @dev W8 skeleton. Mirrors the Sui Move `chronicle::witness_seal` module.
interface IERC5192 {
    event Locked(uint256 tokenId);
    event Unlocked(uint256 tokenId);
    function locked(uint256 tokenId) external view returns (bool);
}

contract WitnessSeal is ERC721, Ownable, IERC5192 {
    // ---------- Errors ----------
    error InvalidBattle();
    error AlreadyMinted();
    error TitleTooLong();
    error TitleEmpty();
    error InscriptionTooLong();
    error InvalidHeroId();
    error InvalidRating();
    error Soulbound();

    // ---------- Constants ----------
    uint8 public constant WITNESS_BATTLE_ID = 3;
    uint256 public constant MAX_TITLE_LEN = 80;
    uint256 public constant MAX_INSCRIPTION_LEN = 50;
    uint8 public constant MAX_HERO_ID = 20;
    uint8 public constant MAX_RATING = 3;

    bytes4 private constant _INTERFACE_ID_ERC5192 = 0xb45a3c0e;

    // ---------- Storage ----------
    struct SealData {
        uint8 battleId;
        uint8 heroId;
        uint8 rating;
        bool isFirstChronicler;
        uint64 mintOrder;
        uint64 blockHeightAtMint;
        address player;
        string title;
        string inscription;
    }

    mapping(uint256 tokenId => SealData) private _seals;
    mapping(address player => bool) public hasMinted;
    uint256 public totalMinted;
    string private _baseTokenURI;

    event WitnessSealMinted(
        uint256 indexed tokenId,
        address indexed player,
        uint64 mintOrder,
        bool isFirst
    );

    constructor(string memory baseURI_)
        ERC721("Validators' Witness", "VWITNESS")
        Ownable(msg.sender)
    {
        _baseTokenURI = baseURI_;
    }

    // ---------- Mint ----------
    function mintWitness(
        uint8 battleId,
        uint8 heroId,
        string calldata title,
        string calldata inscription,
        uint8 rating
    ) external returns (uint256 tokenId) {
        if (battleId != WITNESS_BATTLE_ID) revert InvalidBattle();
        if (heroId == 0 || heroId > MAX_HERO_ID) revert InvalidHeroId();
        if (rating > MAX_RATING) revert InvalidRating();
        if (hasMinted[msg.sender]) revert AlreadyMinted();

        uint256 titleLen = bytes(title).length;
        if (titleLen == 0) revert TitleEmpty();
        if (titleLen > MAX_TITLE_LEN) revert TitleTooLong();
        if (bytes(inscription).length > MAX_INSCRIPTION_LEN) revert InscriptionTooLong();

        hasMinted[msg.sender] = true;
        totalMinted += 1;
        uint64 order = uint64(totalMinted);
        tokenId = order;

        bool isFirst = order == 1;
        _seals[tokenId] = SealData({
            battleId: battleId,
            heroId: heroId,
            rating: rating,
            isFirstChronicler: isFirst,
            mintOrder: order,
            blockHeightAtMint: uint64(block.number),
            player: msg.sender,
            title: title,
            inscription: inscription
        });

        _safeMint(msg.sender, tokenId);
        emit Locked(tokenId);
        emit WitnessSealMinted(tokenId, msg.sender, order, isFirst);
    }

    // ---------- Soulbound enforcement ----------
    function locked(uint256 tokenId) external view returns (bool) {
        _requireOwned(tokenId);
        return true;
    }

    /// @dev Allow mint (from == address(0)) and burn (to == address(0)) only;
    ///      revert any owner-to-owner transfer.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override
        returns (address)
    {
        address from = _ownerOf(tokenId);
        if (from != address(0) && to != address(0)) {
            revert Soulbound();
        }
        return super._update(to, tokenId, auth);
    }

    // ---------- ERC-165 ----------
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, IERC165)
        returns (bool)
    {
        return interfaceId == _INTERFACE_ID_ERC5192 || super.supportsInterface(interfaceId);
    }

    // ---------- Views ----------
    function sealOf(uint256 tokenId) external view returns (SealData memory) {
        _requireOwned(tokenId);
        return _seals[tokenId];
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata newBase) external onlyOwner {
        _baseTokenURI = newBase;
    }
}

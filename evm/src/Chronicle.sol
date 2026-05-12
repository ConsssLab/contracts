// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Chronicle — transferable Chainoa battle NFT.
/// @notice Mirrors the Sui Move `chronicle::chronicle` module.
/// @dev W8 skeleton. Final deployment target is TBD; expect tweaks once the
///      base URI and metadata pipeline are nailed down.
contract Chronicle is ERC721, Ownable {
    // ---------- Errors ----------
    error TitleTooLong();
    error InscriptionTooLong();
    error TitleEmpty();
    error InvalidBattleId();
    error InvalidHeroId();
    error InvalidRating();

    // ---------- Constants ----------
    uint256 public constant MAX_TITLE_LEN = 80;
    uint256 public constant MAX_INSCRIPTION_LEN = 50;
    uint8 public constant MAX_BATTLE_ID = 3;
    uint8 public constant MAX_HERO_ID = 20;
    uint8 public constant MAX_RATING = 3;

    // ---------- Storage ----------
    struct ChronicleData {
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

    mapping(uint256 tokenId => ChronicleData) private _chronicles;
    mapping(uint8 battleId => uint64 count) public mintCountByBattle;
    uint256 private _nextTokenId = 1;
    string private _baseTokenURI;

    // ---------- Events ----------
    event ChronicleMinted(
        uint256 indexed tokenId,
        address indexed player,
        uint8 battleId,
        uint64 mintOrder,
        bool isFirst
    );

    constructor(string memory baseURI_)
        ERC721("Chainoa Chronicle", "CHRON")
        Ownable(msg.sender)
    {
        _baseTokenURI = baseURI_;
    }

    // ---------- Mint ----------
    function mintChronicle(
        uint8 battleId,
        uint8 heroId,
        string calldata title,
        string calldata inscription,
        uint8 rating
    ) external returns (uint256 tokenId) {
        if (battleId == 0 || battleId > MAX_BATTLE_ID) revert InvalidBattleId();
        if (heroId == 0 || heroId > MAX_HERO_ID) revert InvalidHeroId();
        if (rating > MAX_RATING) revert InvalidRating();

        uint256 titleLen = bytes(title).length;
        if (titleLen == 0) revert TitleEmpty();
        if (titleLen > MAX_TITLE_LEN) revert TitleTooLong();
        if (bytes(inscription).length > MAX_INSCRIPTION_LEN) revert InscriptionTooLong();

        uint64 nextOrder = mintCountByBattle[battleId] + 1;
        mintCountByBattle[battleId] = nextOrder;

        tokenId = _nextTokenId++;
        bool isFirst = nextOrder == 1;

        _chronicles[tokenId] = ChronicleData({
            battleId: battleId,
            heroId: heroId,
            rating: rating,
            isFirstChronicler: isFirst,
            mintOrder: nextOrder,
            blockHeightAtMint: uint64(block.number),
            player: msg.sender,
            title: title,
            inscription: inscription
        });

        _safeMint(msg.sender, tokenId);
        emit ChronicleMinted(tokenId, msg.sender, battleId, nextOrder, isFirst);
    }

    // ---------- Views ----------
    function chronicleOf(uint256 tokenId) external view returns (ChronicleData memory) {
        _requireOwned(tokenId);
        return _chronicles[tokenId];
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    function setBaseURI(string calldata newBase) external onlyOwner {
        _baseTokenURI = newBase;
    }
}

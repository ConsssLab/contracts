// Chainoa Chronicle — Anchor program (W8 skeleton)
//
// One instruction, `mint_chronicle`, creates a Chronicle PDA owned by the
// player. A second per-battle `BattleCounter` PDA tracks mint order so each
// Chronicle records its global ranking ("the Nth chronicler of battle X").
//
// Metaplex Token Metadata integration is intentionally NOT here — that's a
// W8 task. See README.md.

use anchor_lang::prelude::*;

declare_id!("Chronic1eProgram1111111111111111111111111111");

pub const MAX_TITLE_LEN: usize = 80;
pub const MAX_INSCRIPTION_LEN: usize = 50;
pub const MAX_BATTLE_ID: u8 = 3;
pub const MAX_HERO_ID: u8 = 20;
pub const MAX_RATING: u8 = 3;

#[program]
pub mod chronicle {
    use super::*;

    pub fn init_battle_counter(ctx: Context<InitBattleCounter>, battle_id: u8) -> Result<()> {
        require!(
            battle_id >= 1 && battle_id <= MAX_BATTLE_ID,
            ChronicleError::InvalidBattleId
        );
        let counter = &mut ctx.accounts.counter;
        counter.battle_id = battle_id;
        counter.count = 0;
        counter.bump = ctx.bumps.counter;
        Ok(())
    }

    pub fn mint_chronicle(
        ctx: Context<MintChronicle>,
        battle_id: u8,
        hero_id: u8,
        title: String,
        inscription: String,
        rating: u8,
    ) -> Result<()> {
        require!(
            battle_id >= 1 && battle_id <= MAX_BATTLE_ID,
            ChronicleError::InvalidBattleId
        );
        require!(
            hero_id >= 1 && hero_id <= MAX_HERO_ID,
            ChronicleError::InvalidHeroId
        );
        require!(rating <= MAX_RATING, ChronicleError::InvalidRating);
        require!(!title.is_empty(), ChronicleError::TitleEmpty);
        require!(title.len() <= MAX_TITLE_LEN, ChronicleError::TitleTooLong);
        require!(
            inscription.len() <= MAX_INSCRIPTION_LEN,
            ChronicleError::InscriptionTooLong
        );

        let counter = &mut ctx.accounts.counter;
        require!(
            counter.battle_id == battle_id,
            ChronicleError::CounterMismatch
        );
        counter.count = counter
            .count
            .checked_add(1)
            .ok_or(ChronicleError::Overflow)?;
        let mint_order = counter.count;

        let chronicle = &mut ctx.accounts.chronicle;
        chronicle.battle_id = battle_id;
        chronicle.hero_id = hero_id;
        chronicle.title = title;
        chronicle.inscription = inscription;
        chronicle.rating = rating;
        chronicle.mint_order = mint_order;
        chronicle.is_first_chronicler = mint_order == 1;
        chronicle.block_height_at_mint = Clock::get()?.slot;
        chronicle.player = ctx.accounts.player.key();
        chronicle.bump = ctx.bumps.chronicle;

        emit!(ChronicleMinted {
            chronicle: chronicle.key(),
            player: chronicle.player,
            battle_id,
            mint_order,
            is_first: chronicle.is_first_chronicler,
        });

        Ok(())
    }
}

// ---------- Accounts ----------

#[derive(Accounts)]
#[instruction(battle_id: u8)]
pub struct InitBattleCounter<'info> {
    #[account(
        init,
        payer = payer,
        space = 8 + BattleCounter::SIZE,
        seeds = [b"battle_counter", &[battle_id]],
        bump,
    )]
    pub counter: Account<'info, BattleCounter>,
    #[account(mut)]
    pub payer: Signer<'info>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
#[instruction(battle_id: u8, hero_id: u8, title: String, inscription: String, rating: u8)]
pub struct MintChronicle<'info> {
    #[account(
        init,
        payer = player,
        space = 8 + ChronicleAccount::MAX_SIZE,
        seeds = [
            b"chronicle",
            player.key().as_ref(),
            &[battle_id],
            &counter.count.checked_add(1).unwrap_or(0).to_le_bytes(),
        ],
        bump,
    )]
    pub chronicle: Account<'info, ChronicleAccount>,
    #[account(
        mut,
        seeds = [b"battle_counter", &[battle_id]],
        bump = counter.bump,
    )]
    pub counter: Account<'info, BattleCounter>,
    #[account(mut)]
    pub player: Signer<'info>,
    pub system_program: Program<'info, System>,
}

// ---------- State ----------

#[account]
pub struct BattleCounter {
    pub battle_id: u8,
    pub count: u64,
    pub bump: u8,
}

impl BattleCounter {
    pub const SIZE: usize = 1 + 8 + 1;
}

#[account]
pub struct ChronicleAccount {
    pub battle_id: u8,
    pub hero_id: u8,
    pub rating: u8,
    pub is_first_chronicler: bool,
    pub mint_order: u64,
    pub block_height_at_mint: u64,
    pub player: Pubkey,
    pub bump: u8,
    pub title: String,
    pub inscription: String,
}

impl ChronicleAccount {
    // 1+1+1+1+8+8+32+1 = 53 fixed; +4+80 title; +4+50 inscription = 191
    pub const MAX_SIZE: usize = 1 + 1 + 1 + 1 + 8 + 8 + 32 + 1 + 4 + MAX_TITLE_LEN + 4 + MAX_INSCRIPTION_LEN;
}

// ---------- Events ----------

#[event]
pub struct ChronicleMinted {
    pub chronicle: Pubkey,
    pub player: Pubkey,
    pub battle_id: u8,
    pub mint_order: u64,
    pub is_first: bool,
}

// ---------- Errors ----------

#[error_code]
pub enum ChronicleError {
    #[msg("Battle id must be between 1 and 3.")]
    InvalidBattleId,
    #[msg("Hero id must be between 1 and 20.")]
    InvalidHeroId,
    #[msg("Rating must be between 0 and 3.")]
    InvalidRating,
    #[msg("Title cannot be empty.")]
    TitleEmpty,
    #[msg("Title exceeds 80 byte limit.")]
    TitleTooLong,
    #[msg("Inscription exceeds 50 byte limit.")]
    InscriptionTooLong,
    #[msg("Counter battle_id does not match instruction battle_id.")]
    CounterMismatch,
    #[msg("Counter overflow.")]
    Overflow,
}

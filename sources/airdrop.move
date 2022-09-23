
/// Airdop function
module movedao::airdrop {

    use aptos_framework::coin::{Self};
    use aptos_framework::managed_coin;
    use aptos_framework::account;
    use aptos_std::table_with_length::{Self, TableWithLength};

    use std::option::{Self, Option};
    use std::signer;

    struct AirdropBox<phantom CoinType> has key {
        // airdrop_addr: address,
        recipient_addr: address,
        // coin: Coin<CoinType>,
        amount: u64,
        airdrop_signer_cap: account::SignerCapability,
    }

    struct AirdropTable has key {
        airdrops: TableWithLength<address, address>,   // <recipient, airdrop>
    }

    const EACCOUNT_NOT_FOUND: u64 = 1;

    const EINVALID_AIRDROP_ADDRESS: u64 = 2;

    const EACCOUNT_ALREADY_EXISTS: u64 = 3;

    // find airdrop adderss
    public fun find_airdrop_by_recipient(sender_addr: address, recipient_addr: address, ): Option<address> acquires AirdropTable {
        let airdrop_table = &borrow_global_mut<AirdropTable>(sender_addr).airdrops;
        
        if (table_with_length::contains<address, address>(airdrop_table, recipient_addr)) {
            let airdrop_addr = table_with_length::borrow<address, address>(airdrop_table, recipient_addr);
            option::some<address>(*airdrop_addr)
        } else {
            option::none<address>()
        } 
    }

    public entry fun airdrop<CoinType>(sender: &signer, seed: vector<u8>, recipient_addr: address, amount: u64) acquires AirdropTable {
        let sender_addr = signer::address_of(sender);

        // create resource account with account
        let (airdrop_signer, airdrop_signer_cap) = account::create_resource_account(sender, seed);
        let airdrop_addr = signer::address_of(&airdrop_signer);
        assert!(account::exists_at(airdrop_addr), EACCOUNT_ALREADY_EXISTS);

        managed_coin::register<CoinType>(&airdrop_signer);
        coin::transfer<CoinType>(sender, airdrop_addr, amount);

        move_to(&airdrop_signer, AirdropBox<CoinType> { recipient_addr, amount, airdrop_signer_cap});

        if (!exists<AirdropTable>(sender_addr)) {           
            let airdrops = table_with_length::new<address, address>();
            move_to(sender, AirdropTable { airdrops });    
        };

        let airdrop_table = borrow_global_mut<AirdropTable>(sender_addr);

        // TODO handle many airdrop of someone
        table_with_length::add<address, address>(&mut airdrop_table.airdrops, recipient_addr, airdrop_addr);
        
    }

    // recipient claim the airdrop, and destroy the airdrop account
    public entry fun claim<CoinType>(recipient: &signer, airdrop_addr: address) acquires AirdropBox {
        let recipient_addr_o = signer::address_of(recipient);
        let airdrop_box = borrow_global_mut<AirdropBox<CoinType>>(airdrop_addr);

        if (!coin::is_account_registered<CoinType>(recipient_addr_o)) {
            managed_coin::register<CoinType>(recipient);
        };

        let AirdropBox { recipient_addr, amount, airdrop_signer_cap } = airdrop_box;

        assert!(recipient_addr_o == *recipient_addr, EINVALID_AIRDROP_ADDRESS);

        let airdrop_signer = account::create_signer_with_capability(airdrop_signer_cap);

        coin::transfer<CoinType>(&airdrop_signer, recipient_addr_o, *amount);
        
    }

    #[test(sender = @0x007, recipient = @0x008)]  
    fun test_airdrop_claim_e2e(sender: signer, recipient: signer) acquires AirdropTable, AirdropBox {
        use aptos_framework::managed_coin;
        use aptos_framework::coin;

        // use std::error;

        let sender_addr = signer::address_of(&sender);
        let recipient_addr = signer::address_of(&recipient);

        account::create_account_for_test(sender_addr);
        account::create_account_for_test(recipient_addr);

        managed_coin::initialize<TestPoint>(
            &sender,
            b"TestPoint",
            b"TPT",
            3,
            false,
        );

        managed_coin::register<TestPoint>(&sender);

        managed_coin::mint<TestPoint>(&sender, sender_addr, 10000);

        let airdrop_amount = 1000;
        let seed = b"009";

        // do airdrop
        airdrop<TestPoint>(&sender, seed, recipient_addr, airdrop_amount);

        // Determine AirdropTable is not empty in sender account
        assert!(exists<AirdropTable>(sender_addr), 0);
        assert!(coin::balance<TestPoint>(sender_addr) == 10000 - airdrop_amount, 0);

        // Determine Airdrop resource account for recipient addr
        let airdrop_addr_opt = &mut find_airdrop_by_recipient(sender_addr, recipient_addr);
        assert!(option::is_some(airdrop_addr_opt), 0);

        let airdrop_addr = option::extract(airdrop_addr_opt);

        assert!(exists<AirdropBox<TestPoint>>(airdrop_addr), 0);

        let before_balance = if (coin::is_account_registered<TestPoint>(recipient_addr)) {
            coin::balance<TestPoint>(recipient_addr)
        } else {
            0
        };

        claim<TestPoint>(&recipient, airdrop_addr);

        let after_balance = coin::balance<TestPoint>(recipient_addr);

        // Determine the airdrop account destroyed
        // assert!(!account::exists_at(airdrop_addr), error::not_found(EACCOUNT_NOT_FOUND));

        assert!(before_balance + airdrop_amount == after_balance, 0);

    }

    #[test_only]
    struct TestPoint has store { }
}
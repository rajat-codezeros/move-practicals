module admin_address::fund_deposit {
    use std::signer;
    use std::vector;
    use std::event;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin, Self};
    use aptos_framework::account;

    const NOT_WHITELISTED:u64 = 3;
    const ALREADY_WHITELISTED:u64 = 4;
    const USER_IS_NOT_ADMIN:u64 = 5;

    const SEED: vector<u8> = b"01";

    struct FundDeposits has key {
        amount: coin::Coin<AptosCoin>,
    }

    struct WhiteListedUsers has key {
        list_of_users: vector<address>,
    }

    #[event]
    struct WhiteListEvent has drop, store {
        action: Action,
        addresses: vector<address> 
    }

    public enum Action has drop, store {
        Added,
        Removed
    }

    #[event]
    struct DepositEvent has drop, store {
        depositor: address,
        amount: u64
    }

    fun assert_is_owner(addr: address) {
        assert!(addr == @admin_address, USER_IS_NOT_ADMIN);
    }

    fun assert_is_whitelisted(list: vector<address>, addr: address) {
        let (found, _index) = vector::index_of(&list, &addr);
        assert!(found, NOT_WHITELISTED);
    }

    fun assert_is_not_whitelisted(list: vector<address>, addr: address) {
        let (found, _index) = vector::index_of(&list, &addr);
        assert!(!found, ALREADY_WHITELISTED);
    }

    #[view]
    public fun is_user_whitelisted(addr: address): (bool, u64) acquires WhiteListedUsers {
        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        vector::index_of(&users.list_of_users, &addr)
    }

    #[view]
    public fun get_contract_balance(): u64 acquires FundDeposits {
        let resource_account_addr = get_resource_account();
        coin::value(&borrow_global<FundDeposits>(resource_account_addr).amount)
    }

    #[view]
    public fun get_users_list(): vector<address> acquires WhiteListedUsers {
        borrow_global_mut<WhiteListedUsers>(@admin_address).list_of_users
    }

    #[view]
    public fun get_resource_account(): address {
        account::create_resource_address(&@admin_address, SEED)
    }

    fun init_module(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert_is_owner(admin_addr);

        let (resource_signer, resource_signer_cap) = account::create_resource_account(admin, SEED);
        
        let fund_deposits = FundDeposits {
            amount: coin::zero<AptosCoin>(),
        };
        move_to(&resource_signer, fund_deposits);

        let whitelistedusers = WhiteListedUsers {
            list_of_users: vector::empty<address>(),
        };
        move_to(admin, whitelistedusers);
    }

    public entry fun deposit_funds(sender: &signer, amount: u64) acquires WhiteListedUsers, FundDeposits {

        let sender_addr = signer::address_of(sender);
        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        assert_is_whitelisted(users.list_of_users, sender_addr);

        let resource_account_addr = get_resource_account();

        let fundDeposits = borrow_global_mut<FundDeposits>(resource_account_addr);
        let apt_amount = coin::withdraw<AptosCoin>(sender, amount);
        coin::merge(&mut fundDeposits.amount, apt_amount);
        event::emit(DepositEvent {
            depositor: sender_addr,
            amount: amount
        });
    }

    public entry fun whitelist_user(admin: &signer, user_addresses: vector<address>) acquires WhiteListedUsers {
        let admin_addr: address = signer::address_of(admin);
        assert_is_owner(admin_addr);

        let users_store = borrow_global_mut<WhiteListedUsers>(signer::address_of(admin));

        let length = vector::length<address>(&user_addresses);
        for (i in 0..length) {
            assert_is_not_whitelisted(users_store.list_of_users, user_addresses[i]);
            vector::push_back(&mut users_store.list_of_users, user_addresses[i]);
        };

        event::emit(WhiteListEvent {
            action: Action::Added,
            addresses: user_addresses
        });
    }

    public entry fun remove_whitelist_user(admin: &signer, user_addresses: vector<address>) acquires WhiteListedUsers {
        let admin_addr: address = signer::address_of(admin);
        assert_is_owner(admin_addr);

        let users_store = borrow_global_mut<WhiteListedUsers>(admin_addr);

        let length = vector::length<address>(&user_addresses);
        for (i in 0..length) {
            assert_is_whitelisted(users_store.list_of_users, user_addresses[i]);

            let (found, index) = vector::index_of(&users_store.list_of_users, &user_addresses[i]);
            if (found) {
                vector::remove(&mut users_store.list_of_users, index);
            };
        };

        event::emit(WhiteListEvent {
            action: Action::Removed,
            addresses: user_addresses
        });
    }

    public entry fun transfer_funds(admin: &signer, to: address, amount: u64) acquires FundDeposits {
        assert_is_owner(signer::address_of(admin));

        let resource_account_addr = get_resource_account();
        let fund_deposits = borrow_global_mut<FundDeposits>(resource_account_addr);

        let coins_amount = coin::extract(&mut fund_deposits.amount, amount);
        coin::deposit(to, coins_amount);
    }


    #[test_only]
    fun mint_aptos_for_test(aptos_framework: &signer, receiver: &signer, amount: u64) {

        if (!coin::is_coin_initialized<aptos_coin::AptosCoin>()) {
            let (burn_cap, mint_cap) = aptos_coin::initialize_for_test(aptos_framework);
            coin::destroy_burn_cap(burn_cap);
            coin::destroy_mint_cap(mint_cap);
        };

        coin::register<aptos_coin::AptosCoin>(receiver);

        aptos_coin::mint(aptos_framework, signer::address_of(receiver), amount);
    }


    #[test(aptos_framework=@aptos_framework, admin=@admin_address, whitelist_user1=@0x123, whitelist_user2=@0x345)]
    public fun test_flow(aptos_framework: &signer, admin: &signer, whitelist_user1: &signer, whitelist_user2: &signer) acquires WhiteListedUsers, FundDeposits {

        let admin_addr = signer::address_of(admin);
        let whitelist_user1_addr = signer::address_of(whitelist_user1);
        let whitelist_user2_addr = signer::address_of(whitelist_user2);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(whitelist_user1_addr);
        account::create_account_for_test(whitelist_user2_addr);

        mint_aptos_for_test(aptos_framework, admin, 0);
        mint_aptos_for_test(aptos_framework, whitelist_user1, 10);
        mint_aptos_for_test(aptos_framework, whitelist_user2, 10);

        init_module(admin);

        // add users to whitelist
        let user_addresses: vector<address> = vector::empty<address>();
        vector::push_back(&mut user_addresses, whitelist_user1_addr);
        vector::push_back(&mut user_addresses, whitelist_user2_addr);

        whitelist_user(admin, user_addresses);

        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        assert_is_whitelisted(users.list_of_users, whitelist_user1_addr);
        assert_is_whitelisted(users.list_of_users, whitelist_user2_addr);

        let events = event::emitted_events<WhiteListEvent>();
        assert!(vector::length(&events) == 1, 0);

        // deposit funds by whitelisted users
        deposit_funds(whitelist_user1, 10);
        deposit_funds(whitelist_user2, 10);

        let balance_user1 = coin::balance<aptos_coin::AptosCoin>(whitelist_user1_addr);
        let balance_user2 = coin::balance<aptos_coin::AptosCoin>(whitelist_user1_addr);
        assert!((balance_user1 == 0) && (balance_user2 == 0), 11);

        let contract_balance = get_contract_balance();
        assert!(contract_balance == 20, 12);

        let events = event::emitted_events<DepositEvent>();
        assert!(vector::length(&events) == 2, 0);

        // remove users from whitelist
        let remove_list: vector<address> = vector::empty<address>();
        vector::push_back(&mut remove_list, whitelist_user1_addr);
        vector::push_back(&mut remove_list, whitelist_user2_addr);

        remove_whitelist_user(admin, remove_list);

        let events = event::emitted_events<WhiteListEvent>();
        assert!(vector::length(&events) == 2, 0);

        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        assert_is_not_whitelisted(users.list_of_users, whitelist_user1_addr);
        assert_is_not_whitelisted(users.list_of_users, whitelist_user2_addr);

        // admin transfer funds
        transfer_funds(admin, admin_addr, 10);
        let balance = coin::balance<aptos_coin::AptosCoin>(admin_addr);
        assert!(balance == 10, 15);
    }

    #[test(aptos_framework=@aptos_framework, admin=@admin_address, user=@0x356)]
    #[expected_failure(abort_code = NOT_WHITELISTED)]
    public fun fail_deposit_for_non_whitelist(aptos_framework: &signer, admin: &signer, user: &signer) acquires WhiteListedUsers, FundDeposits {
        let admin_addr = signer::address_of(admin);
        let user_addr = signer::address_of(user);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(user_addr);

        init_module(admin);

        mint_aptos_for_test(aptos_framework, user, 10);

        deposit_funds(user, 10);
    }

}

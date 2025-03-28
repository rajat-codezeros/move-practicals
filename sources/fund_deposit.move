module admin_address::FundDeposit {
    use std::signer;
    use std::vector;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::{AptosCoin, Self};
    use aptos_framework::account;
    use aptos_framework::event;

    const NOT_INITIALIZED:u64 = 1;
    const ALREADY_INITIALIZED:u64 = 2;
    const NOT_WHITELISTED:u64 = 3;
    const ALREADY_WHITELISTED:u64 = 4;
    const USER_IS_NOT_ADMIN:u64 = 5;

    struct FundDeposits has key {
        amount: coin::Coin<AptosCoin>,
        deposit_event: event::EventHandle<DepositEvent>
    }

    struct WhiteListedUsers has key {
        list_of_users: vector<address>,
        user_event: event::EventHandle<WhiteListEvent>
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

    fun assert_uninitialized(addr: address) {
        assert!(((!exists<FundDeposits>(addr)) || (!exists<WhiteListedUsers>(addr))), ALREADY_INITIALIZED);
    }

    fun assert_initialized(addr: address) {
        assert!(((exists<FundDeposits>(addr)) && (exists<WhiteListedUsers>(addr))), NOT_INITIALIZED);
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
    public fun isUserWhitelisted(addr: address): (bool, u64) acquires WhiteListedUsers {
        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        vector::index_of(&users.list_of_users, &addr)
    }

    #[view]
    public fun getContractBalance(): u64 acquires FundDeposits {
        coin::value(&borrow_global<FundDeposits>(@admin_address).amount)
    }

    #[view]
    public fun getUserslist(): vector<address> acquires WhiteListedUsers {
        borrow_global_mut<WhiteListedUsers>(@admin_address).list_of_users
    }

    public entry fun initialize(admin: &signer) {
        let admin_addr = signer::address_of(admin);
        assert_is_owner(admin_addr);
        assert_uninitialized(admin_addr);

        let fundDeposits = FundDeposits {
            amount: coin::zero<AptosCoin>(),
            deposit_event: account::new_event_handle<DepositEvent>(admin)
        };
        move_to(admin, fundDeposits);

        let whitelistedusers = WhiteListedUsers {
            list_of_users: vector::empty<address>(),
            user_event: account::new_event_handle<WhiteListEvent>(admin)
        };
        move_to(admin, whitelistedusers);
    }

    public entry fun depositFunds(sender: &signer, amount: u64) acquires WhiteListedUsers, FundDeposits {
        assert_initialized(@admin_address);

        let sender_addr = signer::address_of(sender);
        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        assert_is_whitelisted(users.list_of_users, sender_addr);

        let fundDeposits = borrow_global_mut<FundDeposits>(@admin_address);
        let apt_amount = coin::withdraw<AptosCoin>(sender, amount);
        coin::merge(&mut fundDeposits.amount, apt_amount);
        event::emit_event(&mut fundDeposits.deposit_event, DepositEvent { depositor: sender_addr, amount: amount });
    }

    public entry fun whiteListUser(admin: &signer, user_addresses: vector<address>) acquires WhiteListedUsers {
        let admin_addr: address = signer::address_of(admin);
        assert_initialized(admin_addr);
        assert_is_owner(admin_addr);

        let users_store = borrow_global_mut<WhiteListedUsers>(signer::address_of(admin));

        let length = vector::length<address>(&user_addresses);
        for (i in 0..length) {
            vector::push_back(&mut users_store.list_of_users, user_addresses[i]);
        };

        event::emit_event(&mut users_store.user_event, WhiteListEvent { action: Action::Added, addresses: user_addresses });
    }

    public entry fun removeWhiteListUser(admin: &signer, user_addresses: vector<address>) acquires WhiteListedUsers {
        let admin_addr: address = signer::address_of(admin);
        assert_initialized(admin_addr);
        assert_is_owner(admin_addr);

        let users_store = borrow_global_mut<WhiteListedUsers>(admin_addr);

        let length = vector::length<address>(&user_addresses);
        for (i in 0..length) {
            assert_is_whitelisted(users_store.list_of_users, user_addresses[i]);

            let (found, index) = vector::index_of(&users_store.list_of_users, &user_addresses[i]);
            if (found) {
                vector::swap_remove(&mut users_store.list_of_users, index);
            };
        };

        event::emit_event(&mut users_store.user_event, WhiteListEvent { action: Action::Removed, addresses: user_addresses });
    }

    public entry fun transferFunds(admin: &signer, to: address, amount: u64) acquires FundDeposits {
        assert_is_owner(signer::address_of(admin));

        let fundDeposits = borrow_global_mut<FundDeposits>(signer::address_of(admin));

        let coins_amount = coin::extract(&mut fundDeposits.amount, amount);
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


    #[test(aptos_framework=@aptos_framework, admin=@admin_address, whiteListUser1=@0x123, whiteListUser2=@0x345)]
    public fun test_flow(aptos_framework: &signer, admin: &signer, whiteListUser1: &signer, whiteListUser2: &signer) acquires WhiteListedUsers, FundDeposits {

        let admin_addr = signer::address_of(admin);
        let whitelist_user1_addr = signer::address_of(whiteListUser1);
        let whitelist_user2_addr = signer::address_of(whiteListUser2);

        account::create_account_for_test(admin_addr);
        account::create_account_for_test(whitelist_user1_addr);
        account::create_account_for_test(whitelist_user2_addr);

        mint_aptos_for_test(aptos_framework, admin, 0);
        mint_aptos_for_test(aptos_framework, whiteListUser1, 10);
        mint_aptos_for_test(aptos_framework, whiteListUser2, 10);

        initialize(admin);

        // add users to whitelist
        let user_addresses: vector<address> = vector::empty<address>();
        vector::push_back(&mut user_addresses, whitelist_user1_addr);
        vector::push_back(&mut user_addresses, whitelist_user2_addr);

        whiteListUser(admin, user_addresses);

        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        assert_is_whitelisted(users.list_of_users, whitelist_user1_addr);
        assert_is_whitelisted(users.list_of_users, whitelist_user2_addr);

        let whitelist_user_event_count = event::counter(&borrow_global<WhiteListedUsers>(admin_addr).user_event);
        assert!(whitelist_user_event_count == 1, 10);

        // deposit funds by whitelisted users
        depositFunds(whiteListUser1, 10);
        depositFunds(whiteListUser2, 10);

        let balance_user1 = coin::balance<aptos_coin::AptosCoin>(whitelist_user1_addr);
        let balance_user2 = coin::balance<aptos_coin::AptosCoin>(whitelist_user1_addr);
        assert!((balance_user1 == 0) && (balance_user2 == 0), 11);

        let contractBalance = getContractBalance();
        assert!(contractBalance == 20, 12);

        let deposit_event_count = event::counter(&borrow_global<FundDeposits>(admin_addr).deposit_event);
        assert!(deposit_event_count == 2, 13);

        // remove users from whitelist
        let removeList: vector<address> = vector::empty<address>();
        vector::push_back(&mut removeList, whitelist_user1_addr);
        vector::push_back(&mut removeList, whitelist_user2_addr);

        removeWhiteListUser(admin, removeList);

        let whitelist_user_event_count = event::counter(&borrow_global<WhiteListedUsers>(admin_addr).user_event);
        assert!(whitelist_user_event_count == 2, 14);

        let users = borrow_global_mut<WhiteListedUsers>(@admin_address);
        assert_is_not_whitelisted(users.list_of_users, whitelist_user1_addr);
        assert_is_not_whitelisted(users.list_of_users, whitelist_user2_addr);

        // admin transfer funds
        transferFunds(admin, admin_addr, 10);
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

        initialize(admin);

        mint_aptos_for_test(aptos_framework, user, 10);

        depositFunds(user, 10);
    }

}

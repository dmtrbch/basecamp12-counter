use contracts::counter::Counter;
use contracts::counter::{
    ICounterDispatcher, ICounterDispatcherTrait, ICounterSafeDispatcher,
    ICounterSafeDispatcherTrait,
};
use openzeppelin_access::ownable::interface::{IOwnableDispatcher, IOwnableDispatcherTrait};
use openzeppelin_token::erc20::interface::{IERC20Dispatcher, IERC20DispatcherTrait};
use snforge_std::{
    ContractClassTrait, DeclareResultTrait, EventSpyAssertionsTrait, declare, spy_events,
    start_cheat_caller_address, stop_cheat_caller_address,
};
use starknet::{ContractAddress, contract_address_const};

const ZERO_COUNT: u32 = 0;

fn OWNER() -> ContractAddress {
    'OWNER'.try_into().unwrap()
}

fn USER_1() -> ContractAddress {
    'USER_1'.try_into().unwrap()
}

pub fn token_name() -> ByteArray {
    "Starknet Token"
}

pub fn token_symbol() -> ByteArray {
    "STRK"
}

const token_supply: u256 = 1_000_000_000_000_000_000;

fn __deploy__(init_value: u32) -> (ICounterDispatcher, IOwnableDispatcher, ICounterSafeDispatcher) {
    let counter_contract_class = declare("Counter").unwrap().contract_class();

    // searialize constructor
    let mut counter_calldata: Array<felt252> = array![];
    init_value.serialize(ref counter_calldata);
    OWNER().serialize(ref counter_calldata);

    // deploy contract
    let (counter_address, _) = counter_contract_class.deploy(@counter_calldata).expect('failed to deploy');

    let counter = ICounterDispatcher { contract_address: counter_address };
    let ownable = IOwnableDispatcher { contract_address: counter_address };

    let safe_counter = ICounterSafeDispatcher { contract_address: counter_address };

    // deploy STRK token mock
    let token_contract_class = declare("Token").unwrap().contract_class();
    
    let mut token_calldata: Array<felt252> = array![];
    token_name().serialize(ref token_calldata);
    token_symbol().serialize(ref token_calldata);
    token_supply.serialize(ref token_calldata);
    OWNER().serialize(ref token_calldata);

    let strk_token_address: ContractAddress = contract_address_const::<0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d>();
    
    let (token_address, _) = token_contract_class.deploy_at(@token_calldata, strk_token_address).expect('failed to deploy');
    let token = IERC20Dispatcher { contract_address: token_address };

    start_cheat_caller_address(token_address, OWNER());
    token.approve(counter_address, token_supply);
    stop_cheat_caller_address(token_address);

    (counter, ownable, safe_counter)
}

#[test]
fn test_counter_deoployment() {
    let (counter, ownable, _) = __deploy__(ZERO_COUNT);

    let count_1 = counter.get_counter();

    // assertions
    assert(count_1 == ZERO_COUNT, 'count not set');
    assert(ownable.owner() == OWNER(), 'owner not set');
}

#[test]
fn test_increase_counter() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);

    let count_1 = counter.get_counter();

    assert(count_1 == ZERO_COUNT, 'count not set');

    counter.increase_counter();

    let count_2 = counter.get_counter();
    assert(count_2 == count_1 + 1, 'invalid count');
}

#[test]
fn test_emitted_increased_event() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);
    let mut spy = spy_events();

    start_cheat_caller_address(counter.contract_address, USER_1());
    counter.increase_counter();
    stop_cheat_caller_address(counter.contract_address);

    spy
        .assert_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Increased(Counter::Increased { account: USER_1() }),
                ),
            ],
        );

    spy
        .assert_not_emitted(
            @array![
                (
                    counter.contract_address,
                    Counter::Event::Decreased(Counter::Decreased { account: USER_1() }),
                ),
            ],
        )
}

#[test]
#[feature("safe_dispatcher")]
fn test_safe_panic_decrease_counter() {
    let (counter, _, safe_counter) = __deploy__(ZERO_COUNT);

    assert(counter.get_counter() == ZERO_COUNT, 'count not set');

    match safe_counter.decrease_counter() {
        Result::Ok(_) => panic!("cannot decrease 0"),
        Result::Err(e) => assert(*e[0] == 'Decreasing empty counter', *e.at(0)),
    }
}

#[test]
#[should_panic(expected: 'Decreasing empty counter')]
fn test_panic_decrease_counter() {
    let (counter, _, _) = __deploy__(ZERO_COUNT);

    assert(counter.get_counter() == ZERO_COUNT, 'invalid count');

    counter.decrease_counter();
}

#[test]
fn test_successful_decrease_counter() {
    let (counter, _, _) = __deploy__(5);

    let initial_count = counter.get_counter();
    assert(initial_count == 5, 'invalid count');

    // execute decrease_counter txn
    counter.decrease_counter();

    let final_count = counter.get_counter();
    assert(final_count == initial_count - 1, 'invalid decrease count');
}

// INFO: this test will no longer PASS since we have removed the only owner assertion
// in the counter contract when reseting the counter.
// #[test]
// #[feature("safe_dispatcher")]
// fn test_safe_panic_reset_counter_by_non_owner() {
//     let (counter, _, safe_counter) = __deploy__(ZERO_COUNT);

//     assert(counter.get_counter() == ZERO_COUNT, 'invalid count');

//     start_cheat_caller_address(counter.contract_address, USER_1());

//     match safe_counter.reset_counter() {
//         Result::Ok(_) => panic!("cannot reset"),
//         Result::Err(e) => assert(*e[0] == 'Caller is not the owner', *e.at(0)),
//     }
// }

#[test]
fn test_successful_reset_counter() {
    let (counter, _, _) = __deploy__(5);

    let count_1 = counter.get_counter();
    assert(count_1 == 5, 'invalid count');

    start_cheat_caller_address(counter.contract_address, OWNER());
    counter.reset_counter();
    stop_cheat_caller_address(counter.contract_address);

    assert(counter.get_counter() == ZERO_COUNT, 'not reset');
}


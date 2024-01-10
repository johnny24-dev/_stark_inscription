use starknet::{ContractAddress, ClassHash};

#[starknet::interface]
trait IMarket<TContractState> {
    fn list(ref self:TContractState, tick:felt252, amt:u128, price:u128) -> u128;
    fn delist(ref self:TContractState, inscriptions_id:u128) -> u128;
    fn buy(ref self:TContractState, inscriptions_id:u128, price:u128) -> u128;
    fn change_price(ref self:TContractState, inscriptions_id:u128, new_price:u128);

    fn upgrage(ref self: TContractState, _new_class_hash: ClassHash);
    fn update_fee(ref self:TContractState, new_fee:u128);
    fn update_new_fund_address(ref self:TContractState, new_addr:ContractAddress);
    fn update_new_inscriptions_address(ref self:TContractState, new_addr:ContractAddress);

    fn get_market_fee(self:@TContractState)->(u128,ContractAddress);
}

#[starknet::interface]
trait IInscriptions<TContractState> {
   fn transfer(
        ref self: TContractState, to: ContractAddress, tick: felt252, amt: u128, t: felt252
    ) -> u128;

    fn transfer_from(
        ref self: TContractState, from:ContractAddress ,to: ContractAddress, tick: felt252, amt: u128, t: felt252
    ) -> u128;

    fn get_user_balance(
        self: @TContractState, tick: felt252, user_address: ContractAddress
    ) -> u128;
}

#[starknet::interface]
trait IERC20<TState> {
    fn name(self: @TState) -> felt252;
    fn symbol(self: @TState) -> felt252;
    fn decimals(self: @TState) -> u8;
    fn total_supply(self: @TState) -> u256;
    fn balance_of(self: @TState, account: ContractAddress) -> u256;
    fn allowance(self: @TState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn transfer(ref self: TState, recipient: ContractAddress, amount: u256) -> bool;
    fn transfer_from(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
    fn approve(ref self: TState, spender: ContractAddress, amount: u256) -> bool;

    // for eth starknet
    fn transferFrom(
        ref self: TState, sender: ContractAddress, recipient: ContractAddress, amount: u256
    ) -> bool;
}



#[starknet::contract]
mod Market {

    use core::starknet::SyscallResultTrait;
    use core::traits::Into;
    use core::starknet::event::EventEmitter;
    use core::option::OptionTrait;
    use starknet::{ContractAddress,ClassHash, get_contract_address, get_caller_address, contract_address_try_from_felt252, replace_class_syscall};

    use super::{IInscriptionsDispatcher, IInscriptionsDispatcherTrait, IERC20Dispatcher, IERC20DispatcherTrait};


    #[storage]
    struct Storage {
        admin:ContractAddress,
        fee:u128,
        fund_address:ContractAddress,
        inscriptions_address:ContractAddress,
        listing_owner:LegacyMap<u128,ListingItem>
    }

    #[derive(Copy, Drop, Serde, starknet::Store)]
    struct ListingItem {
       seller:ContractAddress,
       tick:felt252,
       amt:u128,
       price:u128,
       is_listing:bool
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        ListEvent:ListEvent,
        BuyEvent:BuyEvent,
        DeListEvent:DeListEvent,
        ChangePriceEvent:ChangePriceEvent
    }


    #[derive(Drop, starknet::Event)]
    struct ListEvent {
        #[key]
        ev_name:felt252,
        #[key]
        seller:ContractAddress,
        #[key]
        tick:felt252,
        amt:u128,
        price:u128,
        new_inscriptions_id:u128
    }

    #[derive(Drop, starknet::Event)]
    struct BuyEvent {
        #[key]
        ev_name:felt252,
        #[key]
        buyer:ContractAddress,
        #[key]
        tick:felt252,
        amt:u128,
        price:u128,
        old_inscriptions_id:u128,
        new_inscriptions_id:u128,
        seller:ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct DeListEvent {
        #[key]
        ev_name:felt252,
        #[key]
        seller:ContractAddress,
        #[key]
        tick:felt252,
        amt:u128,
        old_inscriptions_id:u128,
        new_inscriptions_id:u128
    }

    #[derive(Drop, starknet::Event)]
    struct ChangePriceEvent {
        #[key]
        ev_name:felt252,
        #[key]
        seller:ContractAddress,
        #[key]
        tick:felt252,
        amt:u128,
        new_price:u128,
        inscriptions_id:u128
    }


    #[constructor]
    fn constructor(ref self: ContractState, 
        admin_address: felt252,
        fund_address:felt252,
        inscriptions_addr:felt252,
        fee:u128
    ) {
        let _addr = contract_address_try_from_felt252(admin_address).unwrap();
        let _fund_addr = contract_address_try_from_felt252(fund_address).unwrap();
        let _inscriptions_addr = contract_address_try_from_felt252(inscriptions_addr).unwrap();
        self.admin.write(_addr);
        self.inscriptions_address.write(_inscriptions_addr);
        self.fee.write(fee);
        self.fund_address.write(_fund_addr);
    }

    #[external(v0)]
    impl ImplMarket of super::IMarket <ContractState>{

        fn update_fee(ref self:ContractState, new_fee:u128){
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Invalid Admin');
            self.fee.write(new_fee);
        }

        fn update_new_fund_address(ref self:ContractState, new_addr:ContractAddress){
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Invalid Admin');
            self.fund_address.write(new_addr)

        }

        fn update_new_inscriptions_address(ref self:ContractState, new_addr:ContractAddress){
            let caller = get_caller_address();
            assert(caller == self.admin.read(), 'Invalid Admin');
            self.inscriptions_address.write(new_addr);
        }

        fn upgrage(ref self: ContractState, _new_class_hash: ClassHash){
            let caller = get_caller_address();
            let admin_addr = self.admin.read();
            assert(caller == admin_addr, 'Invalid Admin');

            assert(!_new_class_hash.is_zero(), 'Class hash cannot be zero');
            replace_class_syscall(_new_class_hash).unwrap_syscall();
        }

        fn list(ref self:ContractState, tick:felt252, amt:u128, price:u128) -> u128{
            let caller = get_caller_address();
            let this_address = get_contract_address();
            let inscriptions_id = IInscriptionsDispatcher{contract_address:self.inscriptions_address.read()}.transfer_from(caller,this_address,tick,amt,'coin/plain');
            self.listing_owner.write(inscriptions_id,ListingItem{
                seller:caller,
                tick,
                amt,
                price,
                is_listing:true
            });
            self.emit(ListEvent{
                ev_name:'list_token',
                seller:caller,
                tick,
                amt,
                price,
                new_inscriptions_id:inscriptions_id
            });

            inscriptions_id

        }
        fn delist(ref self:ContractState, inscriptions_id:u128) -> u128{
            let caller = get_caller_address();
            let listing_item = self.listing_owner.read(inscriptions_id);
            assert(listing_item.seller == caller, 'Invalid Owner');
            assert(listing_item.is_listing, 'delisted');
            let new_inscriptions_id = IInscriptionsDispatcher{contract_address:self.inscriptions_address.read()}.transfer(caller,listing_item.tick,listing_item.amt,'coin/plain');

            //update new status

            self.listing_owner.write(inscriptions_id,ListingItem{
                seller:caller,
                tick:listing_item.tick,
                amt:listing_item.amt,
                price:listing_item.price,
                is_listing:false
            });

            self.emit(DeListEvent{
                ev_name:'delist_token', 
                seller:caller,
                tick:listing_item.tick,
                amt:listing_item.amt,
                old_inscriptions_id:inscriptions_id,
                new_inscriptions_id
            });
            new_inscriptions_id
        }
        fn buy(ref self:ContractState, inscriptions_id:u128, price:u128) -> u128{
            let caller = get_caller_address();
            let listing_item = self.listing_owner.read(inscriptions_id);
            assert(listing_item.seller != caller, 'Invalid Buyer');
            assert(price == listing_item.price, 'Invalid price');
            assert(listing_item.is_listing, 'delistedOrBought');
            let eth_contract: ContractAddress = contract_address_try_from_felt252(0x049d36570d4e46f48e99674bd3fcc84644ddd6b96f7c741b1562b82f9e004dc7).unwrap();

            let market_fee = listing_item.price * self.fee.read() / 10000;
            let recived = listing_item.price - market_fee;

            IERC20Dispatcher {contract_address: eth_contract}.transferFrom(caller, listing_item.seller, recived.into());
            IERC20Dispatcher {contract_address: eth_contract}.transferFrom(caller, self.fund_address.read(), market_fee.into());

            let new_inscriptions_id = IInscriptionsDispatcher{contract_address:self.inscriptions_address.read()}.transfer(caller,listing_item.tick,listing_item.amt,'coin/plain');

            //update new state

            self.listing_owner.write(inscriptions_id,ListingItem{
                seller:caller,
                tick:listing_item.tick,
                amt:listing_item.amt,
                price:listing_item.price,
                is_listing:false
            });

            self.emit(BuyEvent{
                ev_name:'buy_token',
                buyer:caller,
                tick:listing_item.tick,
                amt:listing_item.amt,
                price:listing_item.price,
                old_inscriptions_id:inscriptions_id,
                new_inscriptions_id,
                seller:listing_item.seller
            });
            new_inscriptions_id

        }
        fn change_price(ref self:ContractState, inscriptions_id:u128, new_price:u128){
            let caller = get_caller_address();
            let listing_item = self.listing_owner.read(inscriptions_id);
            assert(caller == listing_item.seller, 'Invaid Owner');
            let new_listing_item = ListingItem{
                seller:caller,
                tick:listing_item.tick,
                amt:listing_item.amt,
                price:new_price,
                is_listing:true
            };
            self.listing_owner.write(inscriptions_id,new_listing_item);
            self.emit(ChangePriceEvent{
                ev_name:'change_price_token',
                seller:caller,
                tick:listing_item.tick,
                amt:listing_item.amt,
                new_price,
                inscriptions_id
            });
        }

        //view
        fn get_market_fee(self:@ContractState)->(u128,ContractAddress){
            (self.fee.read(),self.fund_address.read())
        }
    }

}





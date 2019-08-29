// Контракт по распределению премий участникам программы.

pragma solidity >=0.5.11 <0.6.0;

// ----------------------------------------------------------------------------------------------------------------------
//
//  Описание интерфейса EIP20. Перенес его сюда же, поскольку в прошлой реализации, используемой для SWZL token'ов, в 
//             явном виде была указана версия компилятора. И она не та, которую нам нужно в данном случае.
//
// ----------------------------------------------------------------------------------------------------------------------

contract EIP20Interface {
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() constant returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    /// total amount of tokens
    uint256 public totalSupply;

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) public view returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) public returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success);

    /// @notice `msg.sender` approves `_spender` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of tokens to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) public returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) public view returns (uint256 remaining);

    // solhint-disable-next-line no-simple-event-func-name
    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}


// ----------------------------------------------------------------------------------------------------------------------
//
//                  Контракт для распределения премий между участниками команды SwapZilla, а так
//                  же для поощрения сторонних лиц, участвовавших в продвижении проекта SwapZilla.
//
// ----------------------------------------------------------------------------------------------------------------------

contract SWZL_Bounty {
    
    // ------------------------------------------------------------------------------------------------------------------
    //                                               Установки Rinkeby
    //
    // address private swapzilla_contract_address = 0xe5a8c826c17E2D2b724D8987D3C4F33E5bc87fAe;
    
    // ------------------------------------------------------------------------------------------------------------------
    //                                               Установки MainNet
    //
    address private swapzilla_contract_address = 0x946eA588417fFa565976EFdA354d82c01719a2EA;
    
    // SWZL контракт
    EIP20Interface private _SWZL = EIP20Interface(swapzilla_contract_address);
    
    // Поощрения разбиты на этапы. Этап имеет номер и дату.
    // Также этап имеет некий процент. Весь имеющийся у владельца
    // контракта остаток токенов берется за 100%, из них в данном
    // этапе будет расеределен - указанный здесь процент.
    
    struct Stage {
        
        // Когда будет происходить (или произошел) данный этап.
        // Дата-время в UTC в формате unix time_t
        uint when;
        
        // Был ли данный этап выполнен.
        bool done;
        
        // Сумма монет, которая распределяется. Сумма может меняться - 
        // до тех пор, пока у этапа не установлен признак "выполнен".
        uint256 amount;
        
    }
    
    // Структура получателя награды.
    struct AwardReceiver {
        
        address wallet;
        
        // Этап. Выплата награды может быть распределена на этапы,
        // каждый из которых проходит в определенный момент времени.
        uint stage;
        
        // Сумма, которая будет перечислена данному получателю.
        uint256 amount;
        
        // Когда было оплачено.
        uint payed;
    }
    
    // Использование активности контракта вместо его уничтожения в блокчейне.
    bool private _active;

    // Этапы распределения наград. 
    Stage[2] private _stages;
    
    // Внутренняя переменная, содержащая адреса получателей и структуру распределения
    // на данный адрес. Иными словами - словарь, ключом которого является адрес
    // кошелька получателя, значением - структура AwardReceiver.
    AwardReceiver[9] private _award_receivers;
    

    // Владелец контракта.
    address private _owner;
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                                                  Конструктор контракта.
    //
    // ------------------------------------------------------------------------------------------------------------------
     
    constructor() public {
        
        // Запоминаем владельца контракта. Владелец понадобится для аутентификации платежа,
        // поскольку bounty-платеж не может делать любой желающий.
        _owner = msg.sender;
        _active = true;
        
        // Первоначально предусмотрено bounty-вознаграждение за продвижение проекта, 01 февраля 2020г.
        // Bounty составляет 2.5% от общей эмиссии. Или, что то же самое, 750 000 SWZL. 
        
        _stages[0].when = 1580497200; // 01 февраля 2020 г, 00:00:00 - в формате unit timestamp
        _stages[0].amount = 750000;
        _stages[0].done = false;
        
        // Следующим этапом идет распределение вознаграждения для команды.
        // 7% от всего проспекта эмиссии, это 2 100 000 SWZL.
        
        _stages[1].when = 1594753200;  // 15 июня 2020 г. 00:00:00
        _stages[1].amount = 2100000;
        _stages[1].done = false;
        
        // Идем по списку. Чтобы не запутаться в индексах, индекс сделан отдельной переменной.
        uint8 index = 0;
        uint8 stage = 0;
        
        // Второй этап. Вознаграждение команды. 15 июня 2020 г.
        stage ++;
        _set_receiver(index, stage, 0x424d2B06461ee8dCa1d52EE92e2F319850b5a579, 462000);  index ++;
        _set_receiver(index, stage, 0xC4d86de53f15Cfe9CA8976fa75e88Ee5a3Dcf444, 798000);  index ++;
        _set_receiver(index, stage, 0x887295Fcb356553f23FEDcae7F847950B2C7AADf, 336000);  index ++;
        _set_receiver(index, stage, 0x77F7c6888325a7dDe9a87f573934f29d0bB83064,  84000);  index ++;
        _set_receiver(index, stage, 0x705261C619a6204BC7aCA07662F0E11CA4188BE3,  84000);  index ++;
        _set_receiver(index, stage, 0x39Ba9b258FF9565b365AacD6ae93e88691998Df2,  84000);  index ++;
        _set_receiver(index, stage, 0x59D9fE023f071DD1829d7C58259ad9b392c1B6A8,  84000);  index ++;
        _set_receiver(index, stage, 0x4941Bc0e7125F71E2e5dc4557c1126892cf2F519,  84000);  index ++;
        _set_receiver(index, stage, 0x56E45f65dC33B0a9b969f34c9Bf55b69034cA02A,  84000);  index ++;
        
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    // 
    //                    Приватная функция занесения элемента в массив получателей вознаграждений.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function _set_receiver(uint8 index, uint8 stage, address wallet, uint256 amount ) private {
        // Функция приватная, никаких проверок безопасности - не производится.
        require(index < _award_receivers.length, "Index violation");
        _award_receivers[index].wallet = wallet;
        _award_receivers[index].amount = amount;
        _award_receivers[index].stage = stage;
        _award_receivers[index].payed = 0;
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //      Вернуть состояние активности контракта в блокчейне. Не зависит ни от чего, просто выдает переменную. 
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function is_active() public view returns (bool activity) {
        activity = _active;
    }
    

    // ------------------------------------------------------------------------------------------------------------------
    //
    //                                     Получить оставшийся "замороженный" SWZL-баланс.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    
    // Некоторая сумма от выпущенных токенов SWZL замораживается и не может быть продана.
    // Для "заморозки" используется данный контракт: на адрес его владельца перечисляется
    // определенная сумма SWZL токенов и там лежит. Функция возвращает оставшийся доступный
    // баланс для распределения в качестве "награды" между зафиксированными участниками.
    // Баланс - полный, не привязанный к конкретному этапу.
    
    function total_balance() public view returns (uint256 balance) {
        require(_active, "Contract deactivated.");
        balance = _SWZL.balanceOf(_owner);
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                                      Вернуть общее количество этапов поощрения.    
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function get_stages_count() public view returns(uint count) {
        require(_active, "Contract deactivated.");
        count = _stages.length; 
    }

    // ------------------------------------------------------------------------------------------------------------------
    //
    //                 Вернуть сумму, предусмотренную для распределения в ходе указанного этапа.    
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function get_stage_amount(uint index) public view returns (uint256 amount) {
        require(_active, "Contract deactivated.");
        require(index < _stages.length, "Index violation");
        amount = _stages[index].amount;
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                                  Вернуть дату-время прохождения данного этапа.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function get_stage_when(uint index) public view returns(uint when) {
        require(_active, "Contract deactivated.");
        require(index < _stages.length, "Index violation");
        when = _stages[index].when;
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                Вернуть количество получателей вознаграждения, предусмотренное для данного этапа.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function get_stage_receivers_count(uint index) public view returns (uint count) {
        require(_active, "Contract deactivated.");
        require(index < _stages.length, "Index violation");
        count = 0;
        for (uint i=0; i<_award_receivers.length; i++) {
            if ( _award_receivers[i].stage == index ) count++;
        }
    }

    // ------------------------------------------------------------------------------------------------------------------
    //
    //                                       Проверка корркетности заведения этапов.
    //
    // Сумма оставшихся этапов должна быть равна остатку баланса владельца контракта. Возвращает разницу между балансом 
    //    владельца контракта и суммой этапов. Если в результате не ноль - это ошибка и нужно перераспределять этапы.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function check_stages() public view returns (int difference) {
        require(_active, "Contract deactivated.");
        difference = int(total_balance());
        for (uint i=0; i<_stages.length; i++) {
            if ( !_stages[i].done ) {
                difference -= int(_stages[i].amount);
            }
        }
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //               Проверка соответствия суммы этапа и запланированных в ходе данного этапа вознаграждений.
    //
    //              Возвращает разницу между суммой этапа и суммой всех вознаграждений в ходе данного этапа.
    //                                      Если все правильно, то должен быть 0.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function check_stage(uint index) public view returns(int difference) {
        require(_active, "Contract deactivated.");
        require(index < _stages.length, "Index violation");
        difference = int(_stages[index].amount);
        for ( uint i=0; i<_award_receivers.length; i++ ) {
            if ( _award_receivers[i].stage == index ) {
                difference -= int(_award_receivers[i].amount);
            }
        }
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                   Возвращает индекс этапа, который может быть оплачен, если такой индекс есть.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function stage_can_be_awarded() public view returns (int index) {
        require(_active, "Contract deactivated.");
        index = -1;
        // Из всех невыполненных этапов берется тот, у которого дата-время - минимальное.
        uint found_when = 0;
        
        for (uint i=0; i<_stages.length; i++) {
            if (
                (_stages[i].when <= now ) 
                && ( !_stages[i].done) 
                && ( found_when < _stages[i].when )
            ) {
                index = int(i);
                found_when = _stages[i].when;
            }
        }
        
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                          Возвращает общее количество элементов массива _award_receivers
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    
    function get_receivers_count() public view returns (uint count) {
        require(_active, "Contract deactivated.");
        count = _award_receivers.length;
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //               Возвращает кошелек получателя награды, расположенного в массиве по указанному индексу.
    //
    // ------------------------------------------------------------------------------------------------------------------

    function get_receiver_wallet(uint index) public view returns (address wallet) {
        require(_active, "Contract deactivated.");
        require(index < _award_receivers.length, "Index violation");
        wallet = _award_receivers[index].wallet;
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //             Возвращает сумму вознаграждения, расположенную в массиве получателей по данному индексу.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function get_receiver_amount(uint index) public view returns (uint256 amount) {
        require(_active, "Contract deactivated.");
        require(index < _award_receivers.length, "Index violation");
        amount = _award_receivers[index].amount;
        
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //       Возвращает этап, в ходе которого будет выплачен данный элемент массива получателей вознаграждения.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function get_receiver_stage(uint index) public view returns(uint stage) {
        require(_active, "Contract deactivated.");
        require(index < _award_receivers.length, "Index violation");
        stage = _award_receivers[index].stage;
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                               Вернуть дату-время, когда данный элемент был оплачен.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function get_receiver_payed(uint index) public view returns(uint payed) {
        require(_active, "Contract deactivated.");
        require(index < _award_receivers.length, "Index violation");
        payed = _award_receivers[index].payed;
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    // 
    //                                              Уничтожение контракта. 
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    function terminate() public {
        require(msg.sender == _owner);
        require(_active, "Contract deactivated");
        
        // Затираем переменные в хранилище.
        
        for (uint i=0; i<_stages.length; i++ ) {
            _stages[i].when = 0;
            _stages[i].amount = 0;
            _stages[i].done = true;
        }
        for (uint i=0; i<_award_receivers.length; i++ ) {
            _award_receivers[i].wallet = address(0);
            _award_receivers[i].stage = 0;
            _award_receivers[i].amount = 0;
            _award_receivers[i].payed = 0;
        }
        // Активность контракта переводим в false, это будет
        // давать исключения при вызове процедур.
        _active = false;
        
        // Опасно. Поэтому используем "прерывание деятельности"
        // контракта через внутреннюю переменную _active.
        // selfdestruct(msg.sender);
    }
    
    // ------------------------------------------------------------------------------------------------------------------
    //
    //                                                 Оплатить данный этап.
    //
    //                 Функция нуждается в дополнительной отладке, поэтому на данный момент она закомментирована.
    //
    // ------------------------------------------------------------------------------------------------------------------
    
    /*
    function award(uint stage) public {
        require(_active, "Contract deactivated.");
        // Разумеется, оплачивать может только владелец контракта.
        require( msg.sender == _owner );
        // Указанный этап должен быть.
        require( stage < _stages.length );
        // Указанный этап еще не должен быть выполнен.
        require( ! _stages[stage].done );
        // Текущая дата-время должны быть больше или равны, чем 
        // запланированное время этапа, раньше оплачивать - нельзя.
        require( now >= _stages[stage].when );
        
        // Сумма, которую хотим оплатить. Она не должна
        // превышать доступный остаток.
        uint256 total_amount = 0;
        for ( uint i=0; i<_award_receivers.length; i++ ) {
            if ( ( _award_receivers[i].stage == stage ) && ( _award_receivers[i].payed == 0 ) ) {
                // Учитываются только те суммы, которые принадлежат данному этапу и не были ранее оплачены.
                total_amount += _award_receivers[i].amount;
            }
        }
        require( total_amount <= total_balance() );
        
        // Вроде все. Платим.
        for ( uint i=0; i<_award_receivers.length; i++ ) {
            if ( ( _award_receivers[i].stage == stage ) && ( _award_receivers[i].payed == 0 ) ) {
                bool success = _SWZL.transfer(_award_receivers[stage].wallet, _award_receivers[stage].amount);
                if (success) _award_receivers[stage].payed = now;
                require( success );
            }
        }
        
        _stages[stage].done = true;
    }
    */

}

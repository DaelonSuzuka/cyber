type Account object:
    var name    string
    var balance float

    func deposit(amt):
        balance += amt

    func withdraw(amt):
        if amt > balance:
            throw error.InsufficientFunds
        else:
            balance -= amt

    func show(title):
        print '$(title or ''), $(name), $(balance)'

func Account.new(name) Account:
    return [Account name: name, balance: 0.0]

var a = Account.new('Savings')
a.show('Initial')
a.deposit(1000.00)
a.show('After deposit')
a.withdraw(100.00)
--a.withdraw(2000.00)
a.show('After withdraw')
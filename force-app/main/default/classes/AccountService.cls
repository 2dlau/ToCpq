public with sharing class AccountService {
  public class AccountWrapper {
    public Account acct { get; set; }
    public List<Opportunity> topOpportunities { get; set; }
    public Boolean hasOverDueCases { get; set; }
    public Decimal totalOpportunityAmount { get; set; }

    public AccountWrapper(
      Account acct,
      List<Opportunity> opps,
      Boolean hasOverDueCases
    ) {
      this.acct = acct;
      this.topOpportunities = opps;
      this.hasOverDueCases = hasOverDueCases;

      this.totalOpportunityAmount = 0;
      for (Opportunity opp : opps) {
        this.totalOpportunityAmount += opp.Amount != null ? opp.Amount : 0;
      }
    }
  }

  public static List<AccountWrapper> buildAccountWrappers() {
    List<AccountWrapper> accountWrappers = new List<AccountWrapper>();

    Map<Id, List<Opportunity>> acctOppsMap = new Map<Id, List<Opportunity>>();

    List<Account> filteredAccounts = new List<Account>(
      [
        SELECT Id, Name
        FROM Account
        LIMIT 10
      ]
    );

    List<Opportunity> opportunities = [
      SELECT Id, Name, Amount, AccountId
      FROM Opportunity
      WHERE AccountId IN :filteredAccounts
    ];

    for (Opportunity opp : opportunities) {
      if (!acctOppsMap.containsKey(opp.AccountId)) {
        acctOppsMap.put(opp.AccountId, new List<Opportunity>());
      }
      acctOppsMap.get(opp.AccountId).add(opp);
    }

    // Check if there are overdue cases
    Set<Id> acctsWithOverDueCases = new Set<Id>();

    List<Case> overdueCases = [
      SELECT Id, AccountId
      FROM Case
      WHERE Status = 'Overdue' AND AccountId IN :filteredAccounts
    ];

    for (Case c : overdueCases) {
      if (c.AccountId != null) {
        acctsWithOverDueCases.add(c.AccountId);
      }
    }

    // Iterate through each account and create the wrapper
    for (Account acct : filteredAccounts) {
      List<Opportunity> topOpportunities = acctOppsMap.containsKey(acct.Id)
        ? acctOppsMap.get(acct.Id)
        : new List<Opportunity>();
      Boolean hasOverDueCases = acctsWithOverDueCases.contains(acct.Id);
      // Create the wrapper object
      AccountWrapper wrapper = new AccountWrapper(
        acct,
        topOpportunities,
        hasOverDueCases
      );
      accountWrappers.add(wrapper);
    }

    return accountWrappers;
  }
}

public with sharing class AccountService {
  public class AccountWrapper {
    @AuraEnabled
    public Account acct { get; set; }
    @AuraEnabled
    public List<Opportunity> topOpportunities { get; set; }
    @AuraEnabled
    public Boolean hasOverDueCases { get; set; }
    @AuraEnabled
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

  @AuraEnabled(cacheable=true)
  public static List<AccountWrapper> buildAccountWrappers() {
    List<AccountWrapper> accountWrappers = new List<AccountWrapper>();

    Map<Id, List<Opportunity>> acctOppsMap = new Map<Id, List<Opportunity>>();

    List<Account> filteredAccounts = new List<Account>(
      [
        SELECT Id, Name
        FROM Account
        ORDER BY lastModifiedDate DESC
        LIMIT 10
      ]
    );

    system.debug('Filtered Accounts: ' + filteredAccounts);

    List<Opportunity> opportunities = [
      SELECT Id, Name, Amount, AccountId
      FROM Opportunity
      WHERE AccountId IN :filteredAccounts
    ];
    system.debug('Opportunities: ' + opportunities);

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
    system.debug('Overdue Cases: ' + overdueCases);
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
      if (acct != null && acct.Id != null) {
        System.debug('Processing Account: ' + acct.Name);
        AccountWrapper wrapper = new AccountWrapper(
          acct,
          topOpportunities,
          hasOverDueCases
        );
        accountWrappers.add(wrapper);
      } else {
        System.debug('Skipping Account with null Name or Id');
      }
    }
    system.debug('Account Wrappers: ' + accountWrappers);
    return accountWrappers;
  }
}

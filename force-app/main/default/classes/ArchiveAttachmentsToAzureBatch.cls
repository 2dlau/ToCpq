public class ArchiveAttachmentsToAzureBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {
  private ArchiveAttachmentsToAzureService asvc;
  public ArchiveAttachmentsToAzureBatch() {
    asvc = new ArchiveAttachmentsToAzureService();
  }

  public Database.QueryLocator start(Database.BatchableContext bc) {
    asvc.checkObjectAccess();
    return asvc.buildQueryLocator();
  }

  public void execute(Database.BatchableContext bc, List<SObject> scope) {
    // Convert scope to ContentVersion list (safe due to QueryLocator)
    List<ContentVersion> cvList = (List<ContentVersion>) scope;
    if (!cvList.isEmpty()) {
      asvc.processFiles(cvList);
    }
  }

  public void finish(Database.BatchableContext bc) {
    asvc.logStatus();
  }
}

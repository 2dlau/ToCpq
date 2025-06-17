/**
 * @description Scheduler class to run Azure attachment archival batch process
 * To schedule in Setup:
 * 1. Go to Setup > Apex Classes
 * 2. Click "Schedule Apex"
 * 3. Set Job Name: "Archive Attachments"
 * 4. Select this class: ArchiveAttachmentsToAzureBatchSchedule
 * 5. Set schedule (recommended: daily at off-peak hours)
 * 6. Click Save
 */
public with sharing class ArchiveAttachmentsToAzureBatchSchedule implements Schedulable {
  public void execute(SchedulableContext sc) {
    ArchiveAttachmentsToAzureBatch batchJob = new ArchiveAttachmentsToAzureBatch();
    Database.executeBatch(batchJob, 100);
  }
}

public with sharing class ArchiveAttachmentsToAzureService {
  // Add custom exception classes
  public class ConfigurationException extends Exception {
  }

  private final String sasToken;
  private final String baseUrl;
  private final String containerName;
  private Boolean hasAccess = false;
  private Map<Id, List<ContentDocumentLink>> documentLinksMap;
  private static final Set<String> SUPPORTED_OBJECTS = new Set<String>{
    'Case',
    'Account',
    'Opportunity'
  };
  private static final String CONFIG_NAME = 'Default';

  public ArchiveAttachmentsToAzureService() {
    // Check security first
    checkObjectAccess();
    this.hasAccess = true;

    // Get Azure configuration
    Azure_Storage_Config__mdt config = Azure_Storage_Config__mdt.getInstance(
      CONFIG_NAME
    );
    if (config == null) {
      throw new ConfigurationException('Azure Storage configuration not found');
    }

    // Get customer's SAS token
    Azure_SAS_Token__c tokenSetting = Azure_SAS_Token__c.getOrgDefaults();
    if (tokenSetting == null || String.isBlank(tokenSetting.Token__c)) {
      throw new ConfigurationException(
        'Azure SAS Token not configured. Please update in Custom Settings.'
      );
    }

    this.baseUrl = config.Base_URL__c;
    this.containerName = config.Container_Name__c;
    this.sasToken = tokenSetting.Token__c;
  }

  private void validateAccess() {
    if (!this.hasAccess) {
      throw new SecurityException(
        'Security checks not completed. Service not properly initialized.'
      );
    }
  }

  private class BatchStats {
    public Integer totalProcessed = 0;
    public Integer successfulUploads = 0;
    public Integer failedUploads = 0;
    public Set<Id> processedDocIds = new Set<Id>();

    public void updateStats(Boolean success, Id docId) {
      totalProcessed++;
      if (success) {
        successfulUploads++;
        processedDocIds.add(docId);
      } else {
        failedUploads++;
      }
    }
  }
  private BatchStats stats = new BatchStats();

  public void logStatus() {
    System.debug('Total processed: ' + stats.totalProcessed);
    System.debug('Successful uploads: ' + stats.successfulUploads);
    System.debug('Failed uploads: ' + stats.failedUploads);
    System.debug('Processed document IDs: ' + stats.processedDocIds);
  }

  public Database.QueryLocator buildQueryLocator() {
    Set<Id> docIds = new Set<Id>();
    for (ContentDocumentLink cdl : [
      SELECT ContentDocumentId
      FROM ContentDocumentLink
      WHERE LinkedEntityId IN (SELECT Id FROM Case)
      WITH USER_MODE
    ]) {
      docIds.add(cdl.ContentDocumentId);
    }

    if (docIds.isEmpty()) {
      System.debug('No documents found to process');
      return Database.getQueryLocator(
        [SELECT Id FROM ContentVersion WHERE Id = NULL]
      );
    }
    return Database.getQueryLocator(
      [
        SELECT Id, VersionData, PathOnClient, Title, ContentDocumentId
        FROM ContentVersion
        WHERE ContentDocumentId IN :docIds AND IsLatest = TRUE
        WITH USER_MODE
      ]
    );
  }

  public Boolean processFiles(List<ContentVersion> cvList) {
    List<Archive__c> archiveRecords = new List<Archive__c>();
    Map<Id, Archive__c> successfulUploads = new Map<Id, Archive__c>();

    // Load all ContentDocumentLinks in bulk
    Set<Id> contentDocumentIds = new Set<Id>();
    for (ContentVersion cv : cvList) {
      contentDocumentIds.add(cv.ContentDocumentId);
    }
    loadContentDocumentLinks(contentDocumentIds);

    // Process files in parallel where possible
    for (ContentVersion cv : cvList) {
      String blobName = EncodingUtil.urlEncode(
        cv.Id + (cv.PathOnClient != null ? cv.PathOnClient : cv.Title),
        'UTF-8'
      );

      Archive__c archiveRecord = uploadFileToAzure(cv, blobName);
      if (archiveRecord != null) {
        archiveRecords.add(archiveRecord);
        successfulUploads.put(cv.ContentDocumentId, archiveRecord);
      }
      stats.updateStats(archiveRecord != null, cv.ContentDocumentId);
    }

    return insertArchiveRecords(archiveRecords);
  }

  private Archive__c uploadFileToAzure(ContentVersion cv, String blobName) {
    Http http = new Http();
    HttpRequest req = new HttpRequest();

    // Build the endpoint URL using configuration
    String fullEndpoint = String.format(
      '{0}/{1}/{2}?{3}',
      new List<String>{
        this.baseUrl,
        this.containerName,
        blobName,
        this.sasToken
      }
    );

    req.setEndpoint(fullEndpoint);
    req.setMethod('PUT');
    req.setHeader('x-ms-blob-type', 'BlockBlob');
    req.setHeader('x-ms-version', '2020-04-08');
    req.setBodyAsBlob(cv.VersionData);

    try {
      HttpResponse res = http.send(req);
      System.debug('Upload ' + blobName + ' status: ' + res.getStatusCode());

      if (res.getStatusCode() == 201) {
        return createArchiveRecord(cv, fullEndpoint);
      }
      System.debug('Failed to upload ' + blobName + ': ' + res.getBody());
      return null;
    } catch (Exception e) {
      System.debug('Error uploading ' + blobName + ': ' + e.getMessage());
      return null;
    }
  }

  private Boolean insertArchiveRecords(List<Archive__c> archiveRecords) {
    validateAccess();

    if (!archiveRecords.isEmpty()) {
      try {
        Database.SaveResult[] results = Database.insert(archiveRecords, false);
        return true;
      } catch (DmlException e) {
        System.debug('Error creating archive records: ' + e.getMessage());
        return false;
      }
    }
    return false;
  }

  private Archive__c createArchiveRecord(
    ContentVersion cv,
    String fullEndpoint
  ) {
    validateAccess();

    // Get the first non-User parent
    String parentId;
    List<ContentDocumentLink> links = [
      SELECT LinkedEntityId, LinkedEntity.Type
      FROM ContentDocumentLink
      WHERE ContentDocumentId = :cv.ContentDocumentId
      WITH USER_MODE
    ];

    // Filter out User records in Apex
    for (ContentDocumentLink link : links) {
      String entityType = String.valueOf(link.LinkedEntityId.getSObjectType());
      if (entityType != 'User') {
        parentId = link.LinkedEntityId;
        String parentType = ((Id) parentId)
          .getSObjectType()
          .getDescribe()
          .getName();

        if (SUPPORTED_OBJECTS.contains(parentType)) {
          Archive__c archiveRecord = new Archive__c();
          archiveRecord.Archive_Date__c = Datetime.now();
          archiveRecord.Record_Link__c = fullEndpoint;

          switch on parentType {
            when 'Case' {
              archiveRecord.Case__c = parentId;
            }
            when 'Account' {
              archiveRecord.Account__c = parentId;
            }
            when 'Opportunity' {
              archiveRecord.Opportunity__c = parentId;
            }
          }
          return archiveRecord;
        }
      }
    }
    return null;
  }

  private void deleteRecords(Set<Id> contentDocumentIdsToDelete) {
    validateAccess();

    List<ContentDocument> contentDocumentsToDelete = new List<ContentDocument>();
    for (Id docId : contentDocumentIdsToDelete) {
      contentDocumentsToDelete.add(new ContentDocument(Id = docId));
    }

    if (!contentDocumentsToDelete.isEmpty()) {
      try {
        Database.DeleteResult[] results = Database.delete(
          contentDocumentsToDelete,
          false,
          AccessLevel.USER_MODE
        );
        Integer successCount = 0;
        for (Database.DeleteResult dr : results) {
          if (dr.isSuccess()) {
            successCount++;
          } else {
            for (Database.Error err : dr.getErrors()) {
              System.debug(
                LoggingLevel.ERROR,
                'Delete error: ' + err.getStatusCode() + ': ' + err.getMessage()
              );
            }
          }
        }
        System.debug(
          'Successfully deleted ' +
            successCount +
            ' of ' +
            results.size() +
            ' documents'
        );
      } catch (DmlException e) {
        System.debug(
          LoggingLevel.ERROR,
          'Bulk delete error: ' + e.getMessage()
        );
      }
    }
  }

  public void finish(Database.BatchableContext bc) {
    System.debug('Batch processing complete!');
  }

  public void checkObjectAccess() {
    // Add missing object checks for Account and Opportunity
    Map<String, Schema.SObjectType> objects = new Map<String, Schema.SObjectType>{
      'Case' => Schema.Case.SObjectType,
      'Account' => Schema.Account.SObjectType,
      'Opportunity' => Schema.Opportunity.SObjectType,
      'ContentDocumentLink' => Schema.ContentDocumentLink.SObjectType,
      'ContentVersion' => Schema.ContentVersion.SObjectType,
      'AzureSAS__c' => Schema.AzureSAS__c.SObjectType
    };

    for (String objName : objects.keySet()) {
      if (!objects.get(objName).getDescribe().isAccessible()) {
        throw new System.SecurityException(
          'Insufficient permissions to access ' + objName + ' object.'
        );
      }
    }
  }

  private void loadContentDocumentLinks(Set<Id> contentDocumentIds) {
    documentLinksMap = new Map<Id, List<ContentDocumentLink>>();

    for (ContentDocumentLink link : [
      SELECT LinkedEntityId, LinkedEntity.Type, ContentDocumentId
      FROM ContentDocumentLink
      WHERE ContentDocumentId IN :contentDocumentIds
      WITH USER_MODE
    ]) {
      if (!documentLinksMap.containsKey(link.ContentDocumentId)) {
        documentLinksMap.put(
          link.ContentDocumentId,
          new List<ContentDocumentLink>()
        );
      }
      documentLinksMap.get(link.ContentDocumentId).add(link);
    }
  }
}

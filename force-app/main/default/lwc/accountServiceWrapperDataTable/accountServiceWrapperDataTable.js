import { LightningElement, api, wire } from "lwc";
import buildAccountWrappers from "@salesforce/apex/AccountService.buildAccountWrappers";
import { getRecord } from "lightning/uiRecordApi";

export default class AccountServiceWrapperDataTable extends LightningElement {
  @api recordId; // This will be the Case Id
  accountId; // This will store the Account Id
  wrappers = [];
  error;

  // Get Account ID from Case record
  @wire(getRecord, {
    recordId: "$recordId",
    fields: ["Case.AccountId"]
  })
  wireCase({ error, data }) {
    if (data) {
      this.accountId = data.fields.AccountId.value;
      console.log("Account ID from Case:", this.accountId);
    } else if (error) {
      console.error("Error loading Case:", error);
    }
  }

  columns = [
    {
      label: "Account Name",
      fieldName: "accountName",
      initialWidth: 200,
      wrapText: true
    },
    {
      label: "Has Overdue Cases",
      fieldName: "hasOverDueCases",
      type: "boolean"
    },
    {
      label: "Total Opportunity Amount",
      fieldName: "totalOpportunityAmount",
      type: "currency"
    }
  ];

  // Use accountId in wrapper query
  @wire(buildAccountWrappers, { accountId: "$accountId" })
  wiredData({ error, data }) {
    if (data) {
      // Transform data to flatten the structure
      this.wrappers = data.map((wrapper) => ({
        id: wrapper.acct.Id,
        accountName: wrapper.acct.Name,
        hasOverDueCases: wrapper.hasOverDueCases,
        totalOpportunityAmount: wrapper.totalOpportunityAmount
        // Add any other fields you need
      }));
      console.log("Transformed wrappers:", JSON.stringify(this.wrappers[0]));
      this.error = undefined;
    } else if (error) {
      this.error = error;
      this.wrappers = [];
    }
  }

  // Debug getter
  get debugData() {
    return `Case ID: ${this.recordId}\nAccount ID: ${this.accountId}\nWrappers: ${this.wrappers.length}`;
  }

  // Add a detailed debug getter
  get debugSelection() {
    if (this.wrappers.length > 0) {
      return `
        First Row Keys: ${Object.keys(this.wrappers[0])}
        Data Structure: ${JSON.stringify(this.wrappers[0], null, 2)}
        Total Records: ${this.wrappers.length}
        `;
    }
    return "No data available";
  }

  get hasNoRecords() {
    return !this.error && this.wrappers && this.wrappers.length === 0;
  }
}

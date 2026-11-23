/**
 * Single place for every Data Cloud object/field API name used in Apex.
 *
 * After you build the data model, open Data Cloud > Query Editor and CHECK
 * each name below. If one differs in your org, change it here only.
 */
public with sharing class DataCloudNames {
    // Calculated Insight (Step 6 of docs/BUILD_GUIDE.md)
    public static final String CI_OBJECT              = 'Account_Health__cio';
    public static final String CI_ACCOUNT_NUMBER      = 'account_number__c';   // = CRM Account.AccountNumber
    public static final String CI_REVENUE_12M         = 'revenue_12m__c';
    public static final String CI_REVENUE_LAST_90D    = 'revenue_last_90d__c';
    public static final String CI_REVENUE_PREV_90D    = 'revenue_prev_90d__c';
    public static final String CI_DAYS_SINCE_ORDER    = 'days_since_last_order__c';
}

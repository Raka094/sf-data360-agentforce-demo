-- Calculated Insight: Account_Health
-- Paste into Data Cloud > Calculated Insights > New > Create with SQL.
--
-- One row per CRM account number. Orders (ERP) are linked to accounts through the
-- ERP customer master, which carries the CRM account number (exact key match).
-- The "at risk" rule itself is applied in Apex (AtRiskAccountService).
--
-- Data Cloud SQL notes (verified in a Developer Edition org, Nov 2026):
--   - DATE_SUB does not exist
--   - DATEDIFF takes 3 arguments: DATEDIFF(unit, start, end)

SELECT
    c.crm_account_number__c AS account_number__c,
    SUM(CASE WHEN DATEDIFF('day', o.order_date__c, CURRENT_DATE()) <= 365
             THEN o.amount__c ELSE 0 END) AS revenue_12m__c,
    SUM(CASE WHEN DATEDIFF('day', o.order_date__c, CURRENT_DATE()) <= 90
             THEN o.amount__c ELSE 0 END) AS revenue_last_90d__c,
    SUM(CASE WHEN DATEDIFF('day', o.order_date__c, CURRENT_DATE()) > 90
              AND DATEDIFF('day', o.order_date__c, CURRENT_DATE()) <= 180
             THEN o.amount__c ELSE 0 END) AS revenue_prev_90d__c,
    MIN(DATEDIFF('day', o.order_date__c, CURRENT_DATE())) AS days_since_last_order__c
FROM Customer_Order__dlm o
JOIN ERP_Customer__dlm c
  ON o.erp_customer_id__c = c.erp_customer_id__c
GROUP BY c.crm_account_number__c

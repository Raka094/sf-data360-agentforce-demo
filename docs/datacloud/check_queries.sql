-- Run these in Data Cloud > Query Editor to check each step worked.

-- After Step 4: are orders and ERP customers in?
SELECT COUNT(*) FROM Customer_Order__dlm;          -- expect ~1,300
SELECT COUNT(*) FROM ERP_Customer__dlm;            -- expect 40

-- Does every order find its ERP customer (and so a CRM account number)?
SELECT c.crm_account_number__c, COUNT(*) AS orders
FROM Customer_Order__dlm o
JOIN ERP_Customer__dlm c ON o.erp_customer_id__c = c.erp_customer_id__c
GROUP BY c.crm_account_number__c;                 -- expect 40 rows

-- After Step 6: what does the insight say? (this is also what the Apex action reads)
SELECT * FROM Account_Health__cio ORDER BY revenue_12m__c DESC LIMIT 20;
